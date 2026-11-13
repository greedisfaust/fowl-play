class_name Combat extends RefCounted

## Punch / parry / knockdown / ragdoll logic. Host-authoritative:
## clients send `punch_request(target_id, charge)`; the host validates
## reach/state and tells the target to take the punch.
##
## Combat owns all punch/parry/knockdown STATE and LOGIC. The player node
## (owner) owns the RPCs and node mutations; player.gd calls Combat from its
## input/process/RPC handlers.

const PUNCH_CHARGE_MS := int(1000.0 * PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS)  # hold Q this long for a charged punch
const PARRY_COOLDOWN := PhysicsTuning.PARRY_COOLDOWN_SECONDS   # seconds before F can parry again
const PARRY_GRACE := PhysicsTuning.PARRY_GRACE_SECONDS          # max seconds parry stays active while holding F
const PUNCH_RANGE := PhysicsTuning.PUNCH_RANGE_M          # how far a charged punch reaches (bug #9)
const LUNGE_SPEED := PhysicsTuning.LUNGE_SPEED_MPS        # how far a charged punch lunges the puncher

var owner: Node3D = null          # the player node (set by player.gd in _ready)
var head: Node3D = null
var ray: RayCast3D = null
var hands: Object = null
var overlay: InteractionOverlay = null
var player_state: PlayerState = null
var carrier: Carrier = null

# --- punch charge state ---
var _punch_charge_started := -1.0
var _punch_charge_held := false
var _last_press := -10.0          # jab spam guard (seconds)

# --- parry state ---
var _parry_cooldown := 0.0
var _parry_active_until := 0.0

# Call from player.gd's _ready after everything is wired up.
func setup(o: Node3D, h: Node3D, r: RayCast3D, hands_in: Object, ov: Object, ps: PlayerState, c: Carrier) -> void:
	owner = o
	head = h
	ray = r
	hands = hands_in
	overlay = ov as InteractionOverlay
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

# --- punch input logic (client side) -----------------------------------

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

# --- raycast -----------------------------------------------------------

func raycast_hit() -> Node:
	if not ray.is_colliding():
		return null
	var target = ray.get_collider()
	# Only players can take punches — walk up to find player root (named by peer ID).
	# Raycasts hit body parts (Body, Head, Beak), not the player root, so has_node("Head")
	# fails on Body. Walk up instead.
	var n: Node = target
	while n != null:
		if str(n.name).match(r"^\d+$"):
			return n
		n = n.get_parent()
	return null

# --- parry -------------------------------------------------------------

func can_start_parry(now: float) -> bool:
	return _parry_cooldown <= 0.0 and now >= _parry_active_until

func start_parry(now: float) -> void:
	_parry_active_until = now + PARRY_GRACE
	if overlay != null:
		overlay.notice("PARRY READY")

func expire_parry(now: float) -> void:
	if _parry_active_until > 0.0 and now >= _parry_active_until:
		_parry_active_until = 0.0
		_parry_cooldown = PARRY_COOLDOWN
		if overlay != null:
			overlay.notice("PARRY COOLDOWN")

func is_parrying(now: float) -> bool:
	return _parry_active_until > 0.0 and now < _parry_active_until

# --- limp (knockdown / ragdoll / carried / thrown) ---------------------------

# Limp the target: input locked, host-simulated physical body, can be carried.
# `direction` and `speed` launch them; `seconds` is how long they stay down.
# The owner's BodyPhys limp mode + launch is applied by player.gd's punch_request
# on the host (host authority over bodies). This function handles state machine
# + visuals only: apply_launch is a no-op on clients since they lack authority.
func apply_ragdoll(direction: Vector3, speed: float, seconds: float) -> void:
	player_state.transition_to(PlayerState.State.LIMP)
	player_state.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
	player_state.start_limp_timer(seconds)
	# Drop anything being carried before going limp (tell the host to release).
	if carrier.is_carrying():
		carrier.request_drop(false)
	# visual slump: look down so the player reads as "downed"
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
	var rotated := current.rotated(axis, step)
	var speed := _lunge_velocity.length()
	_lunge_velocity = rotated.normalized() * speed

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


# --- host-authoritative punch validation -------------------------------

# Returns (valid: bool, is_charged: bool) after validating reach/state.
func validate_punch(sender: Node3D, target: Node3D, charge: float) -> Array:
	var dist := sender.global_position.distance_to(target.global_position)
	if dist > PUNCH_RANGE:
		return [false, false]
	var is_charged := charge >= 1.0
	return [true, is_charged]

# --- helpers -----------------------------------------------------------

# Preload PhysicsProp for type checks.
const PhysicsProp := preload("res://interaction/physics_prop.gd")
const InteractionOverlay := preload("res://ui/interaction_overlay.gd")
