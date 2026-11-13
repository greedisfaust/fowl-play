class_name Combat extends RefCounted

## Punch / parry / knockdown / ragdoll logic. Host-authoritative:
## clients send `punch_request(is_quick, charge)`; the host validates
## state and spawns the punch hitbox. Clients send `parry_request()`;
## the host toggles parry state and spawns/despawns the barrier.
##
## Combat owns all punch/parry/knockdown STATE and LOGIC. The player node
## (owner) owns the RPCs and node mutations; player.gd calls Combat from its
## input/process/RPC handlers.

const PUNCH_CHARGE_MS := int(1000.0 * PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS)  # hold Q this long for a charged punch
const PARRY_COOLDOWN := PhysicsTuning.PARRY_COOLDOWN_SECONDS   # seconds before F can parry again
const PARRY_GRACE := PhysicsTuning.PARRY_GRACE_SECONDS          # max seconds parry stays active while holding F
const LUNGE_SPEED := PhysicsTuning.LUNGE_SPEED_MPS        # how far a charged punch lunges the puncher

var owner: Node3D = null          # the player node (set by player.gd in _ready)
var head: Node3D = null
var hands: Object = null
var overlay: Object = null
var player_state: PlayerState = null
var carrier: Carrier = null

# --- punch charge state ---
var _punch_charge_started := -1.0
var _punch_charge_held := false
var _last_press := -10.0          # jab spam guard (seconds)

# --- parry state ---
var _parry_cooldown := 0.0
var _parry_active_until := 0.0
var _parry_barrier: Node3D = null   # the barrier Area3D instance (null when not active)

# Call from player.gd's _ready after everything is wired up.
func setup(o: Node3D, h: Node3D, hands_in: Object, ov: Object, ps: PlayerState, c: Carrier) -> void:
	owner = o
	head = h
	hands = hands_in
	overlay = ov
	player_state = ps
	carrier = c

# Call from player.gd's _process each frame.
func process(delta: float) -> void:
	expire_parry(Time.get_ticks_msec() / 1000.0)

# --- punch charge state accessors (used by player.gd input handlers) ---

func is_punch_charge_held() -> bool:
	return _punch_charge_held

func punch_charge_started() -> float:
	return _punch_charge_started

func set_punch_charge_held(held: bool, started: float = -1.0) -> void:
	_punch_charge_held = held
	_punch_charge_started = started

# --- punch input logic (client side) ---

func can_start_punch_charge() -> bool:
	return not _punch_charge_held and not player_state.is_limp() and not player_state.is_carrying() and not (carrier != null and carrier.is_carrying())

func can_release_punch_charge() -> bool:
	return _punch_charge_held

func compute_charge(started: float) -> float:
	var held_ms := (Time.get_ticks_msec() / 1000.0 - started) * 1000.0
	return clampf(float(held_ms) / PUNCH_CHARGE_MS, 0.0, 1.0)

func can_do_light_jab(now: float) -> bool:
	return now - _last_press >= 0.35

func set_last_press(now: float) -> void:
	_last_press = now

# --- punch hitbox (host spawns; clients never spawn hitboxes directly) ---

## Spawn a punch hitbox at the puncher's position, forward along camera look.
## `is_quick` = true for tap Q (jiggle only), false for charged (ragdoll + push).
## Returns the spawned hitbox node (host only).
func spawn_punch_hitbox(is_quick: bool, charge: float) -> Area3D:
	var scene: PackedScene = preload("res://player/punch_hitbox.tscn")
	var hitbox: Area3D = scene.instantiate() as Area3D
	# Position: in front of the puncher's head, along camera look.
	var eye_pos: Vector3 = owner.global_position + Vector3(0, 1.6, 0)
	var head_node: Node3D = owner.get_node_or_null("Head")
	var look_dir: Vector3 = -head_node.global_basis.z if head_node != null else -owner.global_basis.z
	var range_m: float = PhysicsTuning.QUICK_PUNCH_RANGE_M if is_quick else PhysicsTuning.CHARGED_PUNCH_RANGE_M
	var size_m: float = PhysicsTuning.QUICK_PUNCH_SIZE_M if is_quick else PhysicsTuning.CHARGED_PUNCH_SIZE_M
	var duration_s: float = PhysicsTuning.QUICK_PUNCH_DURATION_S if is_quick else PhysicsTuning.CHARGED_PUNCH_DURATION_S
	hitbox.global_position = eye_pos + look_dir * (range_m * 0.5)
	hitbox.global_rotation = head_node.global_rotation if head_node != null else owner.global_rotation
	# Configure via script (script is on the root Area3D named "PunchHitbox")
	var hb: PunchHitbox = hitbox as PunchHitbox
	if hb != null:
		hb.is_quick = is_quick
		hb.charge = charge
		hb.size_m = size_m
		hb.duration_s = duration_s
		hb.owner_id = str(owner.name).to_int()
		hb.push_speed = 0.0 if is_quick else PhysicsTuning.CHARGED_PUNCH_PUSH_SPEED_MPS
		hb.ragdoll_seconds = 0.0 if is_quick else PhysicsTuning.CHARGED_PUNCH_RAGDOLL_SECONDS
	var world: Node = owner.get_tree().get_first_node_in_group("game_world")
	if world != null:
		world.add_child(hitbox)
	return hitbox

# --- parry -------------------------------------------------------------

func can_start_parry(now: float) -> bool:
	return _parry_cooldown <= 0.0 and now >= _parry_active_until

func start_parry(now: float) -> void:
	_parry_active_until = now + PARRY_GRACE
	if overlay != null and overlay.has_method("notice"):
		overlay.notice("PARRY READY")
	_spawn_barrier()
func expire_parry(now: float) -> void:
	if _parry_active_until > 0.0 and now >= _parry_active_until:
		_parry_active_until = 0.0
		_parry_cooldown = PARRY_COOLDOWN
		if overlay != null and overlay.has_method("notice"):
			overlay.notice("PARRY COOLDOWN")
		_despawn_barrier()


## End parry immediately (client released F early): drop guard, despawn barrier,
## start cooldown.
func end_parry_immediately(now: float) -> void:
	if _parry_active_until <= 0.0:
		return
	_parry_active_until = 0.0
	_parry_cooldown = PARRY_COOLDOWN
	if overlay != null and overlay.has_method("notice"):
		overlay.notice("PARRY COOLDOWN")
	_despawn_barrier()

func is_parrying(now: float) -> bool:
	return _parry_active_until > 0.0 and now < _parry_active_until

## Mirror host parry state to clients so is_parrying() works client-side
## for movement lock during parry stance.
## `active_until` = when the parry grace expires (0 = not parrying).
## `cooldown_until` = when the cooldown expires (only set when parry ends).
func set_parry_state(active_until: float, cooldown_until: float) -> void:
	_parry_active_until = active_until
	if active_until <= 0.0:
		# Parry ended: start cooldown.
		_parry_cooldown = cooldown_until

func on_parry_success(punch_area: Object) -> void:
	# Called by ParryBarrier when a punch hitbox enters the barrier.
	# Cancel the punch: queue_free the hitbox area.
	if punch_area != null and punch_area.is_inside_tree():
		punch_area.queue_free()
	# Notify owner client for visual feedback (hands guard flash, etc.)
	if overlay != null and overlay.has_method("notice"):
		overlay.notice("PARRIED!")

func _spawn_barrier() -> void:
	if _parry_barrier != null:
		return
	var scene: PackedScene = preload("res://player/parry_barrier.tscn")
	var barrier: Area3D = scene.instantiate() as Area3D
	var pb: ParryBarrier = barrier as ParryBarrier
	if pb != null:
		pb.owner_id = str(owner.name).to_int()
		pb.radius_m = PhysicsTuning.PARRY_BARRIER_RADIUS_M
		pb.height_m = PhysicsTuning.PARRY_BARRIER_HEIGHT_M
		pb.combat = self
		owner.add_child(barrier)
		_parry_barrier = barrier

func _despawn_barrier() -> void:
	if _parry_barrier != null:
		_parry_barrier.queue_free()
		_parry_barrier = null

# --- limp (knockdown / ragdoll / carried / thrown) ---------------------------

func apply_ragdoll(direction: Vector3, speed: float, seconds: float) -> void:
	player_state.transition_to(PlayerState.State.LIMP)
	player_state.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	player_state.start_limp_timer(seconds)
	if carrier.is_carrying():
		carrier.request_drop(false)
	if owner.has_node("Head"):
		(owner.get_node("Head") as Node3D).rotation.x = deg_to_rad(60)

# --- charged-punch lunge (velocity preserved through _physics_process) ---

var _lunge_until := 0.0          # timestamp when lunge expires
var _lunge_velocity := Vector3.ZERO   # launch velocity for the lunge

## Start a charged-punch lunge: velocity is preserved by player.gd's
## _physics_process until _lunge_until, so input can't overwrite it.
func start_lunge(direction: Vector3, speed: float, duration: float) -> void:
	_lunge_velocity = direction * speed
	_lunge_until = Time.get_ticks_msec() / 1000.0 + duration

func is_lunging(now: float) -> bool:
	return now < _lunge_until

func lunge_velocity() -> Vector3:
	return _lunge_velocity

## Steer the lunge toward a look direction mid-flight (camera-arc punch).
## `look_dir` is where the camera is facing (e.g. -camera.global_basis.z).
## `strength` is how hard to pull toward that direction (0..1).
## `max_turn_rad_per_sec` limits how fast the aim can swing so players can't
## instantly look behind mid-lunge.
## `delta` is seconds since the last physics frame (passed from _physics_process).
func steer_lunge(look_dir: Vector3, strength: float, max_turn_rad_per_sec: float = 6.0, delta: float = 0.016) -> void:
	if not is_lunging(Time.get_ticks_msec() / 1000.0):
		return
	if strength <= 0.0:
		return
	var target := look_dir.normalized()
	var current := _lunge_velocity.normalized()
	if current == Vector3.ZERO:
		current = target
	# Cap the turn rate so the arc can't snap around instantly.
	var max_delta := max_turn_rad_per_sec * delta * strength
	var angle := current.angle_to(target)
	if absf(angle) < 0.001:
		return
	var step := clampf(angle, -max_delta, max_delta)
	var axis := current.cross(target)
	if axis == Vector3.ZERO:
		axis = Vector3.UP
	else:
		axis = axis.normalized()   # rotated() requires a unit axis
	var rotated := current.rotated(axis, step)
	var speed_val := _lunge_velocity.length()
	_lunge_velocity = rotated.normalized() * speed_val

# Launch the owner with a lunge velocity (charged punch). Deprecated: use
# start_lunge() instead so velocity survives _physics_process input overwrite.
func lunge(speed: float) -> void:
	if owner.has_node("Head"):
		var dir := -(owner.get_node("Head") as Node3D).global_basis.z
		start_lunge(dir, speed, 0.5)

# --- helpers ----------------------------------------------------------------

func velocity_apply(direction: Vector3, speed: float) -> void:
	if owner is CharacterBody3D:
		var body: CharacterBody3D = owner
		body.velocity = direction * speed

func _body_phys_of(node: Node3D) -> BodyPhys:
	if node == null:
		return null
	var bp := node.get_node_or_null("BodyPhys")
	if bp is BodyPhys:
		return bp
	for child in node.get_children():
		if child is BodyPhys:
			return child as BodyPhys
	return null

# --- host-authoritative punch validation (kept for reference; hitbox replaces target_id validation) ---

func validate_punch(sender: Node3D, target: Node3D, charge: float) -> Array:
	var dist := sender.global_position.distance_to(target.global_position)
	if dist > PhysicsTuning.PUNCH_RANGE_M:
		return [false, false]
	var is_charged := charge >= 1.0
	return [true, is_charged]

const PhysicsProp := preload("res://interaction/physics_prop.gd")
