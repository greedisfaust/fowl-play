extends RigidBody3D

class_name BodyPhys

## Physical-body foundation for props AND limp players.
## Host (peer 1) simulates. Clients freeze and follow host snapshots.
## A player's own BodyPhys is DORMANT (frozen, collision off) until the player goes limp.
## It is top_level so it never rides, or fights, its parent's transform.

signal body_impact(speed: float, position: Vector3)   # wall-slam VFX hook
signal limp_recovered(body: Node)                     # host only: limp timer expired and body is at rest

## True on the machine that simulates physics (the host). Derived, never assigned.
var is_authority: bool:
	get:
		return is_inside_tree() and multiplayer.is_server()

@export var immovable: bool = false   # never simulated (set by PhysicsProp for IMMOVABLE)

var is_player_body: bool = false      # auto-detected: child of a CharacterBody3D
var carry_mode: bool = false
var carry_anchor: Node3D = null
var carry_offset: Vector3 = Vector3.ZERO
var limp_mode: bool = false
var limp_timer: float = 0.0           # host only: seconds left before recovery
var last_synced_transform: Transform3D = Transform3D.IDENTITY
var last_synced_linear_velocity: Vector3 = Vector3.ZERO
var last_synced_angular_velocity: Vector3 = Vector3.ZERO

var _snapshot_time: float = 0.0
var _sent_settled: bool = false
var _limp_elapsed: float = 0.0        # free-tumble time; pauses while carried
var _safe_transform: Transform3D = Transform3D.IDENTITY

func _enter_tree() -> void:
	top_level = true                   # keeps the global transform; stops riding a parent
	is_player_body = get_parent() is CharacterBody3D
	freeze = true

func _ready() -> void:
	mass = PhysicsTuning.PROP_MASS_KG
	linear_damp = PhysicsTuning.LINEAR_DAMP
	angular_damp = PhysicsTuning.ANGULAR_DAMP
	gravity_scale = PhysicsTuning.GRAVITY_SCALE
	continuous_cd = true
	add_to_group("body_phys")
	set_multiplayer_authority(1)
	last_synced_transform = global_transform   # never start at the world origin
	_safe_transform = global_transform
	if is_player_body:
		_set_dormant(true)

# --- dormant / collision ------------------------------------------------------

func _set_collision_enabled(enabled: bool) -> void:
	for child in get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", not enabled)

func _set_dormant(on: bool) -> void:
	_set_collision_enabled(not on)
	if on:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

# --- carry mode ---------------------------------------------------------------

func set_carry_mode(anchor: Node3D, offset: Vector3) -> void:
	carry_mode = true
	carry_anchor = anchor
	carry_offset = offset
	freeze = true
	_set_collision_enabled(false)      # a carried body must not push or block the carrier
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

## Leave carry mode. On the host, `launch` becomes the body's velocity (a throw).
func clear_carry_mode(launch: Vector3 = Vector3.ZERO) -> void:
	carry_mode = false
	carry_anchor = null
	carry_offset = Vector3.ZERO
	_set_collision_enabled(true)
	if limp_mode:
		limp_timer = PhysicsTuning.LIMP_SECONDS   # put down or thrown: stays down a while longer
		_limp_elapsed = 0.0
	freeze = immovable or not is_authority
	if is_authority and not immovable:
		linear_velocity = launch.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		angular_velocity = Vector3.ZERO
		sleeping = false

# --- limp mode ----------------------------------------------------------------

## Runs on EVERY machine so state matches. Only the host simulates and launches.
func begin_limp(start: Transform3D, launch_velocity: Vector3, seconds: float) -> void:
	limp_mode = true
	limp_timer = seconds
	_limp_elapsed = 0.0
	mass = PhysicsTuning.LIMP_MASS_KG
	global_transform = start
	last_synced_transform = start
	_safe_transform = start
	_sent_settled = false
	_set_collision_enabled(true)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if is_authority:
		freeze = false
		sleeping = false
		linear_velocity = launch_velocity.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		if launch_velocity.length() > 0.01:
			angular_velocity = Vector3.UP.cross(launch_velocity.normalized()) * PhysicsTuning.LIMP_TUMBLE_SPIN_RADPS
	else:
		freeze = true

## Runs on EVERY machine. The body goes dormant at `final`.
func end_limp(final: Transform3D) -> void:
	limp_mode = false
	limp_timer = 0.0
	mass = PhysicsTuning.PROP_MASS_KG
	global_transform = final
	last_synced_transform = final
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	if is_player_body:
		_set_dormant(true)

# Compatibility wrappers (old callers / tests).
func set_limp_mode(seconds: float) -> void:
	begin_limp(global_transform, Vector3.ZERO, seconds)

func clear_limp_mode() -> void:
	end_limp(global_transform)

# --- impulses / launch ----------------------------------------------------------

func apply_body_impulse(direction: Vector3, speed: float) -> void:
	if is_authority and not immovable:
		apply_central_impulse(direction.normalized() * speed)
		sleeping = false

func apply_launch(direction: Vector3, speed: float) -> void:
	if is_authority and not immovable:
		linear_velocity = (direction.normalized() * speed).limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
		angular_velocity = Vector3.UP.cross(direction.normalized()) * PhysicsTuning.LIMP_TUMBLE_SPIN_RADPS
		sleeping = false

# --- physics process -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_player_body and not limp_mode:
		return
	if carry_mode and carry_anchor != null:
		_carry_step(delta)
		return
	if not is_authority:
		_follow_snapshot(delta)
		return
	_host_step(delta)

func _host_step(delta: float) -> void:
	freeze = immovable
	linear_velocity = linear_velocity.limit_length(PhysicsTuning.BODY_MAX_SPEED_MPS)
	if not global_position.is_finite() or global_position.y < PhysicsTuning.BODY_KILL_PLANE_Y_M:
		_return_to_safe()
		return
	var speed: float = linear_velocity.length()
	if speed < 0.5 and global_position.y > -1.0:
		_safe_transform = global_transform
	if speed > PhysicsTuning.IMPACT_SPEED_THRESHOLD_MPS:
		body_impact.emit(speed, global_position)
	if limp_mode:
		limp_timer -= delta
		_limp_elapsed += delta
		var settled: bool = speed < PhysicsTuning.LIMP_SETTLED_SPEED_MPS
		if (limp_timer <= 0.0 and settled) or _limp_elapsed >= PhysicsTuning.LIMP_MAX_SECONDS:
			_ready_to_recover()
			return
	_snapshot_time += delta
	if not sleeping:
		_sent_settled = false
		if _snapshot_time >= PhysicsTuning.get_snapshot_interval_seconds():
			_snapshot_time = 0.0
			_send_snapshot()
	elif not _sent_settled:
		_sent_settled = true
		_sync_settled.rpc(global_transform)       # one reliable packet when the body comes to rest
		last_synced_transform = global_transform

func _send_snapshot() -> void:
	_sync_snapshot.rpc(global_transform, linear_velocity, angular_velocity)
	last_synced_transform = global_transform
	last_synced_linear_velocity = linear_velocity
	last_synced_angular_velocity = angular_velocity

func _follow_snapshot(delta: float) -> void:
	var t: float = minf(delta * PhysicsTuning.SNAPSHOT_FOLLOW_RATE, 1.0)
	global_position = global_position.lerp(last_synced_transform.origin, t)
	quaternion = quaternion.slerp(last_synced_transform.basis.get_rotation_quaternion(), t)

func _return_to_safe() -> void:
	push_warning("BodyPhys %s left the world; returned to its last safe position." % name)
	global_transform = _safe_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false

## Host: carried body follows the carrier's head anchor (wall raycast kept), but only
## send snapshots at the normal rate (not per-frame).
func _carry_step(delta: float) -> void:
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
	# Host: lock position + send snapshots at the normal rate (not per-frame).
	global_position = target
	_snapshot_time += delta
	if _snapshot_time >= PhysicsTuning.get_snapshot_interval_seconds():
		_snapshot_time = 0.0
		_send_snapshot()

## Host: the limp timer ran out and the body is at rest. Go dormant; tell the player.
func _ready_to_recover() -> void:
	var final: Transform3D = global_transform
	end_limp(final)
	_sync_settled.rpc(final)
	limp_recovered.emit(self)

# --- replication -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_snapshot(xform: Transform3D, lin: Vector3, ang: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_authority:
		return                          # only the host sends; the host ignores its own
	last_synced_transform = xform
	last_synced_linear_velocity = lin
	last_synced_angular_velocity = ang

@rpc("any_peer", "call_remote", "reliable")
func _sync_settled(xform: Transform3D) -> void:
	if multiplayer.get_remote_sender_id() != 1 or is_authority:
		return
	last_synced_transform = xform
