class_name Combat extends RefCounted

## Punch / parry / knockdown logic. Host-authoritative:
## clients send `punch_request(target_id, charge)`; the host validates
## reach/state and calls `apply_take_punch` on the target.
##
## Combat owns all punch/parry/knockdown STATE and LOGIC. The player node
## (owner) owns the RPCs and node mutations; player.gd calls Combat from its
## input/process/RPC handlers.

const PUNCH_CHARGE_MS := 500      # hold Q this long for a charged punch
const PARRY_COOLDOWN := 1.5       # seconds before F can parry again
const PARRY_GRACE := 1.5          # max seconds parry stays active while holding F
const PUNCH_RANGE := 3.0          # how far a charged punch reaches (bug #9)

var owner: Node3D = null          # the player node (set by player.gd in _ready)
var head: Node3D = null
var ray: RayCast3D = null
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

# --- knockdown state ---
var _knocked_down_until := 0.0

# Call from player.gd's _ready after everything is wired up.
func setup(o: Node3D, h: Node3D, r: RayCast3D, hands_in: Object, ov: Object, ps: PlayerState, c: Carrier) -> void:
	owner = o
	head = h
	ray = r
	hands = hands_in
	overlay = ov
	player_state = ps
	carrier = c

# Call from player.gd's _process each frame.
func process(delta: float) -> void:
	_expire_parry()

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
	return not _punch_charge_held and not player_state.is_knocked_down() and not player_state.is_carrying()

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
	if target and not target.has_method("take_punch"):
		target = null
	return target

# --- parry -------------------------------------------------------------

func can_start_parry(now: float) -> bool:
	return _parry_cooldown <= 0.0 and now >= _parry_active_until

func start_parry(now: float) -> void:
	_parry_active_until = now + PARRY_GRACE
	if overlay != null:
		overlay.show_notice("PARRY READY")

func expire_parry(now: float) -> void:
	if _parry_active_until > 0.0 and now >= _parry_active_until:
		_parry_active_until = 0.0
		_parry_cooldown = PARRY_COOLDOWN
		if overlay != null:
			overlay.show_notice("PARRY COOLDOWN")

func is_parrying(now: float) -> bool:
	return _parry_active_until > 0.0 and now < _parry_active_until

# --- knockdown ---------------------------------------------------------

func knocked_down_until() -> float:
	return _knocked_down_until

func set_knocked_down_until(val: float) -> void:
	_knocked_down_until = val

# Apply knockdown to self: state transition, drop carried, lock input.
# player.gd calls this from its take_punch RPC.
func apply_knockdown(seconds: float) -> void:
	player_state.transition_to(PlayerState.KNOCKED_DOWN)
	_knocked_down_until = Time.get_ticks_msec() / 1000.0 + seconds
	owner.input_locked = true
	# visual slump: look down so the player reads as "downed"
	if owner.has_node("Head"):
		owner.get_node("Head").rotation.x = deg_to_rad(60)
	# drop anything being carried — handled by player.gd via carrier
	# (Combat doesn't know the RPC mechanics; player.gd coordinates)

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
