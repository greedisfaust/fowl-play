extends RigidBody3D

class_name BodyPhys

## Centralized physical-body foundation for props AND limp players.
##
## One class owns: authority, impulses/launch, carry mode, limp mode,
## sleep/wake, impact events, and changed-only snapshots.
##
## All tuning numbers come from PhysicsTuning (one class_name with units in names).
##
## Authority model (host-authoritative):
##   - Host (peer 1) simulates the body: freeze = false, is_authority = true.
##   - Clients freeze the body and interpolate changed-only snapshots.
##   - A limp player is always host-simulated â€” the owner's authority is
##     suspended while limp, so a client can never fabricate a launch.
##
## Replication: host sends _sync_snapshot only when the transform changes,
## at the rate from PhysicsTuning. Snapshots stop while the body is sleeping
## or carried, and resume on wake/release.
##
## Consumers today: PhysicsProp (props), limp players (Phase 3).

signal body_impact(speed: float, position: Vector3)   # wall-slam VFX hook
signal limp_recovered(body: Node)                     # limp timer expired

# --- state ----------------------------------------------------------------

var is_authority: bool = false       # true on host for bodies we simulate
var carry_mode: bool = false         # true while being carried
var carry_anchor: Node3D = null      # the carrier we follow while carried
var carry_offset: Vector3 = Vector3.ZERO   # offset from anchor
var limp_mode: bool = false          # true while limp (ground / carried / thrown)
var limp_timer: float = 0.0          # seconds remaining before recovery
var snap_timer: float = 0.0          # accumulator for client interpolation
var last_synced_transform: Transform3D = Transform3D.IDENTITY
var last_synced_linear_velocity: Vector3 = Vector3.ZERO
var last_synced_angular_velocity: Vector3 = Vector3.ZERO

var _snapshot_time: float = 0.0      # accumulator for host snapshot rate limiting

func _enter_tree() -> void:
	# Authority can't be resolved here: _enter_tree may run before
	# multiplayer.multiplayer_peer is configured. Defaults below; _physics_process
	# reconciles is_authority/freeze with multiplayer.is_server() each frame.
	is_authority = false
	freeze = true

func _ready() -> void:
	mass = PhysicsTuning.PROP_MASS_KG
	linear_damp = PhysicsTuning.LINEAR_DAMP
	angular_damp = PhysicsTuning.ANGULAR_DAMP
	gravity_scale = PhysicsTuning.GRAVITY_SCALE
	continuous_cd = true
	add_to_group("body_phys")

# --- carry mode -----------------------------------------------------------

## Put this body into carry mode: it follows `anchor` with a spring.
## Called by CarryRegistry (host) or by the holder's client.
func set_carry_mode(anchor: Node3D, offset: Vector3) -> void:
	carry_mode = true
	carry_anchor = anchor
	carry_offset = offset
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## Leave carry mode. If `launch` is set, apply it as a throw velocity.
func clear_carry_mode(launch: Vector3 = Vector3.ZERO) -> void:
	carry_mode = false
	carry_anchor = null
	carry_offset = Vector3.ZERO
	freeze = not is_authority
	if launch != Vector3.ZERO and is_authority:
		linear_velocity = launch
		sleeping = false

# --- limp mode ------------------------------------------------------------

## Enter limp state: host-simulated physical body, no owner control.
func set_limp_mode(seconds: float) -> void:
	limp_mode = true
	limp_timer = seconds
	mass = PhysicsTuning.LIMP_MASS_KG
	freeze = not is_authority
	sleeping = false

## Leave limp state: recover to normal, authority returns to owner.
func clear_limp_mode() -> void:
	limp_mode = false
	limp_timer = 0.0
	mass = PhysicsTuning.PROP_MASS_KG
	freeze = not is_authority

# --- impulses / launch ----------------------------------------------------

## Apply an instantaneous impulse (push).
func apply_body_impulse(direction: Vector3, speed: float) -> void:
	if is_authority:
		apply_central_impulse(direction.normalized() * speed)
		sleeping = false

## Apply a launch velocity (throw / charged punch lunge).
func apply_launch(direction: Vector3, speed: float) -> void:
	if is_authority:
		linear_velocity = direction.normalized() * speed
		angular_velocity = Vector3(2.0, 1.0, 0.0)
		sleeping = false

# --- physics process ------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Reconcile authority with the network role each frame: _enter_tree may run
	# before multiplayer.multiplayer_peer is configured. Host simulates; clients
	# freeze + interpolate toward host snapshots. Carry mode keeps freeze = true
	# on the host so carried bodies don't simulate independently.
	if multiplayer.is_server():
		is_authority = true
		if not carry_mode:
			freeze = false
			# Claim multiplayer authority (peer 1) so _sync_snapshot RPCs are
			# allowed. _enter_tree runs before the peer is configured, so we do
			# it here once multiplayer.is_server() is true.
			if get_multiplayer_authority() != 1:
				set_multiplayer_authority(1)
	else:
		is_authority = false
		freeze = true

	if carry_mode and carry_anchor != null:
		# Lock the carried body to the carrier's head (hand position relative
		# to where they're looking). No spring lag - glued to the hand.
		# The carrier client locks locally for zero lag; observers interpolate
		# from host snapshots below.
		var anchor_pos: Vector3 = carry_anchor.global_position
		var anchor_basis: Basis = carry_anchor.global_basis
		if carry_anchor.has_node("Head"):
			var head: Node3D = carry_anchor.get_node("Head") as Node3D
			anchor_pos = head.global_position
			anchor_basis = head.global_basis
		var target: Vector3 = anchor_pos + anchor_basis * carry_offset
		# Carrier client: lock locally (this peer is holding it).
		if not multiplayer.is_server() and carry_anchor.is_multiplayer_authority():
			global_position = target
			return
		# Raycast from anchor to target: stop at walls so carried bodies don't clip.
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(carry_anchor.global_position, target)
		query.exclude = [carry_anchor.get_rid(), get_rid()]
		var hit: Dictionary = get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			target = hit.position + hit.normal * 0.25
		# Observer clients: interpolate toward target every frame (smooth, not frozen).
		if not multiplayer.is_server():
			global_position = global_position.lerp(target, minf(delta * 40.0, 1.0))
			return
		# Host: simulate + send snapshots every frame.
		if multiplayer.is_server():
			_sync_snapshot.rpc(global_transform, linear_velocity, angular_velocity)
		return

	if limp_mode:
		# Tumbling limp body: gravity is applied via gravity_scale, recover
		# when the timer expires (host also watches for slow speed).
		limp_timer -= delta
		if limp_timer <= 0.0:
			# Recovery: signal the registry to transition back to IDLE.
			_ready_to_recover()

	if not multiplayer.is_server():
		# Client: interpolate toward the last host snapshot every frame. Clients never send snapshots.
		global_position = global_position.lerp(last_synced_transform.origin, minf(delta * 12.0, 1.0))
		quaternion = quaternion.slerp(last_synced_transform.basis.get_rotation_quaternion(), minf(delta * 12.0, 1.0))
		return

	# Host: simulate + impact detection + changed-only snapshots.
	var speed: float = linear_velocity.length()
	if speed > PhysicsTuning.IMPACT_SPEED_THRESHOLD_MPS:
		body_impact.emit(speed, global_position)
	var interval: float = PhysicsTuning.get_snapshot_interval_seconds()
	_snapshot_time += delta
	if _snapshot_time >= interval and not sleeping:
		_snapshot_time = 0.0
		_sync_snapshot.rpc(global_transform, linear_velocity, angular_velocity)
		last_synced_transform = global_transform
		last_synced_linear_velocity = linear_velocity
		last_synced_angular_velocity = angular_velocity

## Called by _physics_process when the limp timer expires. Emits limp_recovered
## so the host can clear limp mode and return authority to the owner.
func _ready_to_recover() -> void:
	limp_recovered.emit(self)

# --- replication ----------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_snapshot(transform: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may send snapshots
	if is_authority:
		return   # host already simulates; ignore its own snapshot
	last_synced_transform = transform
	last_synced_linear_velocity = linear_velocity
	last_synced_angular_velocity = angular_velocity
	snap_timer = 0.0   # restart interpolation on new snapshot

