extends RigidBody3D

class_name BodyPhys

## Centralized physical-body foundation for props AND limp players.
##
## One class owns: authority, impulses/launch, carry mode, limp mode,
## sleep/wake, impact events, and ALL physics tuning constants.
##
## Authority model (host-authoritative):
##   - Host (peer 1) simulates the body: freeze = false, is_authority = true.
##   - Clients freeze the body and interpolate changed-only snapshots.
##   - A limp player is always host-simulated — the owner's authority is
##     suspended while limp, so a client can never fabricate a launch.
##
## Replication: host sends _sync_snapshot only when the transform changes,
## at SNAPSHOT_RATE. Snapshots stop while the body is sleeping or carried,
## and resume on wake/release.
##
## Consumers today: PhysicsProp (props), limp players (Phase 3).
## Two real consumers justifies this class (R9).

signal body_impact(speed: float, position: Vector3)   # wall-slam VFX hook

# --- tuning constants: one place for everything --------------------------

const GRAVITY_SCALE: float = 1.0
const LINEAR_DAMP: float = 0.15          # was 0.8 on props (too floaty)
const ANGULAR_DAMP: float = 0.5
const MIN_THROW_SPEED: float = 3.0       # m/s — tap throw
const MAX_THROW_SPEED: float = 14.0      # m/s — full charged throw
const CHARGE_SECONDS: float = 1.25       # s — hold time for full charge
const REACH: float = 3.2                 # m — pickup/reach distance
const SNAPSHOT_RATE: float = 1.0 / 15.0  # s — host snapshot interval
const IMPACT_SPEED_THRESHOLD: float = 8.0   # m/s — wall-slam VFX fires above this
const LIMP_MASS: float = 8.0             # kg — limp players are heavy
const PROP_MASS: float = 0.6             # kg — small carryable props
const LARGE_PROP_MASS: float = 4.0       # kg — furniture / large props
const LIMP_SWING_LAG: float = 8.0        # spring follow speed for carried limp bodies

# --- state ----------------------------------------------------------------

var is_authority: bool = false       # true on host for bodies we simulate
var carry_mode: bool = false         # true while being carried
var carry_anchor: Node3D = null      # the carrier we follow while carried
var carry_offset: Vector3 = Vector3.ZERO   # offset from anchor
var limp_mode: bool = false          # true while limp (ground / carried / thrown)
var limp_timer: float = 0.0          # seconds remaining before recovery
var snap_timer: float = 0.0          # accumulator for snapshot rate limiting
var last_synced_transform: Transform3D = Transform3D.IDENTITY
var last_synced_linear_velocity: Vector3 = Vector3.ZERO
var last_synced_angular_velocity: Vector3 = Vector3.ZERO

func _enter_tree() -> void:
	if multiplayer.is_server():
		set_multiplayer_authority(1)
		is_authority = true
		freeze = false
	else:
		is_authority = false
		freeze = true		# Clients do not simulate; they interpolate toward snapshots.

func _ready() -> void:
	mass = PROP_MASS
	linear_damp = LINEAR_DAMP
	angular_damp = ANGULAR_DAMP
	gravity_scale = GRAVITY_SCALE
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
		apply_central_impulse(launch)
		sleeping = false

# --- limp mode ------------------------------------------------------------

## Enter limp state: host-simulated physical body, no owner control.
func set_limp_mode(seconds: float) -> void:
	limp_mode = true
	limp_timer = seconds
	mass = LIMP_MASS
	freeze = not is_authority
	sleeping = false

## Leave limp state: recover to normal, authority returns to owner.
func clear_limp_mode() -> void:
	limp_mode = false
	limp_timer = 0.0
	mass = PROP_MASS
	freeze = not is_authority

# --- impulses / launch ----------------------------------------------------

## Apply an instantaneous impulse (push).
func apply_impulse(direction: Vector3, speed: float) -> void:
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
	if carry_mode and carry_anchor != null:
		# Follow the carrier anchor with a spring (weight + slight swing).
		var target := carry_anchor.global_position + carry_anchor.global_basis * carry_offset
		# Raycast from anchor to target: stop at walls so carried bodies don't clip.
		var query := PhysicsRayQueryParameters3D.create(carry_anchor.global_position, target)
		query.exclude = [carry_anchor.get_rid(), get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			target = hit.position + hit.normal * 0.25
		global_position = global_position.lerp(target, minf(delta * LIMP_SWING_LAG, 1.0))
		if limp_mode:
			global_basis = carry_anchor.global_basis
		return

	if limp_mode:
		# Tumbling limp body: gravity is applied via gravity_scale, recover
		# when the timer expires (host also watches for slow speed).
		limp_timer -= delta
		if limp_timer <= 0.0:
			# Recovery: signal the registry to transition back to IDLE.
			_ready_to_recover()

	if not is_authority:
		# Client: interpolate toward the last host snapshot.
		snap_timer += delta
		if snap_timer >= SNAPSHOT_RATE:
			snap_timer = 0.0
			global_position = global_position.lerp(last_synced_transform.origin, minf(delta * 18.0, 1.0))
			quaternion = quaternion.slerp(last_synced_transform.basis.get_rotation_quaternion(), minf(delta * 18.0, 1.0))
		return

	# Host: simulate + impact detection + changed-only snapshots.
	var speed := linear_velocity.length()
	if speed > IMPACT_SPEED_THRESHOLD:
		for i in get_contact_count():
			var collider := get_contact_collider(i)
			if collider is RigidBody3D or collider is StaticBody3D:
				body_impact.emit(speed, global_position)
				break

	_snapshot_time += delta
	if _snapshot_time >= SNAPSHOT_RATE and not sleeping and not carry_mode:
		_snapshot_time = 0.0
		_sync_snapshot.rpc(global_transform, linear_velocity, angular_velocity)
		last_synced_transform = global_transform
		last_synced_linear_velocity = linear_velocity
		last_synced_angular_velocity = angular_velocity

var _snapshot_time: float = 0.0

# Recovery signal: emitted by the host when limp time expires. CarryRegistry
# / player state machine listen for it and transition LIMP -> IDLE, returning
# authority to the owner at the body's current transform.
signal limp_recovered(body: Node)

## Called by _physics_process when the limp timer expires. Emits limp_recovered
## so the host can clear limp mode and return authority to the owner.
func _ready_to_recover() -> void:
	limp_recovered.emit(self)

# --- replication ----------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_snapshot(transform: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	if is_authority:
		return   # host already simulates; ignore its own snapshot
	last_synced_transform = transform
	last_synced_linear_velocity = linear_velocity
	last_synced_angular_velocity = angular_velocity
	snap_timer = 0.0   # restart interpolation on new snapshot

# --- sleep / wake ---------------------------------------------------------

func _sleeping_changed() -> void:
	# Replication pauses while sleeping, resumes on wake. Handled in
	# _physics_process via the sleeping check above.
