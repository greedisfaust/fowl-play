class_name Combat extends RefCounted

## Punch / parry / knockdown / ragdoll logic. Host-authoritative:
## clients send `punch_request(...)`; the host validates and spawns the hitbox.
## Clients send `parry_request()`; the host toggles parry state and spawns the barrier.
##
## Combat owns all punch/parry/knockdown STATE and LOGIC. The player node
## (owner) owns the RPCs and node mutations; player.gd calls Combat from its
## input/process/RPC handlers.

signal parry_ended   # host: grace ran out or a parry landed, so tell everyone to drop the guard

const PUNCH_CHARGE_MS := int(1000.0 * PhysicsTuning.CHARGED_PUNCH_HOLD_SECONDS)
const PARRY_COOLDOWN := PhysicsTuning.PARRY_COOLDOWN_SECONDS
const PARRY_GRACE := PhysicsTuning.PARRY_GRACE_SECONDS
const LUNGE_SPEED := PhysicsTuning.LUNGE_SPEED_MPS
const PARRY_RECOIL_SPEED_MPS := 8.0      # shove the puncher back when their punch is parried
const PARRY_RECOIL_SECONDS := PhysicsTuning.LIMP_SECONDS   # puncher goes limp for the full knockdown
const MAX_PUNCH_POS_ERROR_M := 6.0      # host ignores a client-reported punch position farther than this from its own copy

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

# --- parry state (all values are absolute timestamps in seconds) ---
var _parry_ready_at := 0.0        # F works again at this time (the cooldown)
var _parry_active_until := 0.0    # 0 = not parrying
var _parry_barrier: Node3D = null

# --- charged-punch lunge ---
var _lunge_until := 0.0
var _lunge_started := 0.0
var _lunge_velocity := Vector3.ZERO
var _lunge_pending := false       # a charged hit is waiting for the lunge to end
var _lunge_charge := 0.0

func setup(o: Node3D, h: Node3D, hands_in: Object, ov: Object, ps: PlayerState, c: Carrier) -> void:
	owner = o
	head = h
	hands = hands_in
	overlay = ov
	player_state = ps
	carrier = c

# Called from player.gd's _process on EVERY machine (the host must tick parry timers for everyone).
func process(_delta: float) -> void:
	expire_parry(Time.get_ticks_msec() / 1000.0)

# --- punch charge state accessors (used by player.gd input handlers) ---

func is_punch_charge_held() -> bool:
	return _punch_charge_held

func punch_charge_started() -> float:
	return _punch_charge_started

func set_punch_charge_held(held: bool, started: float = -1.0) -> void:
	_punch_charge_held = held
	_punch_charge_started = started

func can_start_punch_charge() -> bool:
	if is_parrying(Time.get_ticks_msec() / 1000.0):
		return false   # guard up means no punching
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

## Spawn a punch hitbox in front of the puncher. `puncher` is the player node that threw
## the punch (used for position and parenting so the hitbox moves with the lunge).
## `puncher_combat` is the puncher's Combat component, so the hitbox can stop the lunge on hit.
## `from` / `aim` are the puncher's own reported position and look direction (accurate at the END
## of a lunge); the host falls back to its own copy of the puncher if they are missing or
## implausible. Returns the hitbox (host only), or null if there is no world yet.
func spawn_punch_hitbox(is_quick: bool, charge: float, puncher: Node3D, puncher_combat: Combat = null, from: Vector3 = Vector3.INF, aim: Vector3 = Vector3.ZERO) -> Area3D:
	var scene: PackedScene = preload("res://player/punch_hitbox.tscn")
	var hitbox: Area3D = scene.instantiate() as Area3D
	var base: Vector3 = puncher.global_position if puncher != null else owner.global_position
	if from.is_finite() and from.distance_to(base) <= MAX_PUNCH_POS_ERROR_M:
		base = from
	var flat := Vector3(aim.x, 0.0, aim.z)
	if flat.length() < 0.01:
		var head_node: Node3D = puncher.get_node_or_null("Head") if puncher != null else null
		var fwd: Vector3 = -head_node.global_basis.z if head_node != null else -owner.global_basis.z
		flat = Vector3(fwd.x, 0.0, fwd.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var range_m: float = PhysicsTuning.QUICK_PUNCH_RANGE_M if is_quick else PhysicsTuning.CHARGED_PUNCH_RANGE_M
	var size_m: float = PhysicsTuning.QUICK_PUNCH_SIZE_M if is_quick else PhysicsTuning.CHARGED_PUNCH_SIZE_M
	# Charged-punch hitbox stays alive for the full lunge so it can hit during the lunge.
	# Quick punch keeps its short damage window.
	var duration_s: float = PhysicsTuning.QUICK_PUNCH_DURATION_S if is_quick else 0.5
	var hb: PunchHitbox = hitbox as PunchHitbox
	if hb != null:
		hb.is_quick = is_quick
		hb.charge = charge
		hb.size_m = size_m
		hb.duration_s = duration_s
		hb.owner_id = str(puncher.name if puncher != null else owner.name).to_int()
		hb.origin = base
		hb.puncher_combat = puncher_combat
		hb.push_speed = 0.0 if is_quick else PhysicsTuning.CHARGED_PUNCH_PUSH_SPEED_MPS
		hb.ragdoll_seconds = 0.0 if is_quick else PhysicsTuning.CHARGED_PUNCH_RAGDOLL_SECONDS
	# Parent the hitbox to the puncher so it moves with them during the lunge,
	# instead of sitting stationary at the spawn point in game_world.
	var parent_node: Node3D = puncher if puncher != null else owner
	parent_node.add_child(hitbox)
	hitbox.global_position = base + Vector3(0.0, 1.0, 0.0) + flat * (range_m * 0.5)
	hitbox.global_rotation = Basis.looking_at(flat, Vector3.UP).get_euler()
	return hitbox

# --- parry -------------------------------------------------------------

func can_start_parry(now: float) -> bool:
	return now >= _parry_ready_at and now >= _parry_active_until

## Host: begin a parry and spawn the real barrier. Returns false if it isn't allowed.
func start_parry(now: float) -> bool:
	if not can_start_parry(now):
		return false
	_parry_active_until = now + PARRY_GRACE
	_notice("PARRY READY")
	_spawn_barrier(false)
	if hands != null:
		hands.set_guard(true)   # boxer guard visual on the local player
	return true

func expire_parry(now: float) -> void:
	if _parry_active_until > 0.0 and now >= _parry_active_until:
		_end_parry(now, true)

## End the parry now (F released early, or a parry landed). Drops the barrier and
## starts the cooldown. `notify` makes the host tell everyone to drop the guard.
func end_parry_immediately(now: float, notify := false) -> void:
	if _parry_active_until <= 0.0:
		return
	_end_parry(now, notify)

func _end_parry(now: float, notify: bool) -> void:
	_parry_active_until = 0.0
	_parry_ready_at = now + PARRY_COOLDOWN
	_notice("PARRY COOLDOWN")
	_despawn_barrier()
	if hands != null:
		hands.set_guard(false)   # drop the local player's guard pose (0.6s relax tween)
	if notify:
		parry_ended.emit()

func is_parrying(now: float) -> bool:
	return _parry_active_until > 0.0 and now < _parry_active_until

## Mirror host parry state on every machine so is_parrying() works for the
## movement lock. `ready_at` is only used when the parry ended.
func set_parry_state(active_until: float, ready_at: float) -> void:
	# Don't resurrect a parry that already expired locally (late host reply).
	if active_until > 0.0 and _parry_active_until <= 0.0:
		return
	_parry_active_until = active_until
	_parry_ready_at = ready_at   # always track cooldown end, even during active parry
	if active_until <= 0.0:
		_despawn_barrier()
		if hands != null:
			hands.set_guard(false)   # drop the local player's guard pose (0.6s relax tween)

## Clients: show a visual-only shield on the parrier. The host already has the
## real barrier from start_parry(); this still runs on all peers so the visual
## is consistent everywhere.
func show_remote_barrier(active: bool) -> void:
	if active:
		_spawn_barrier(true)
	else:
		_despawn_barrier()

## Called by ParryBarrier when a punch hitbox is blocked (host only).
func on_parry_success(punch_area: Object) -> void:
	if punch_area == null or not is_instance_valid(punch_area):
		return
	var puncher_id := int(punch_area.get("owner_id"))
	if punch_area is Node and (punch_area as Node).is_inside_tree():
		(punch_area as Node).queue_free()   # the punch is cancelled
	_recoil_puncher(puncher_id)
	_notice("PARRIED!")
	# Parry stays active for the full grace window; each attacker is recoiled.

func _recoil_puncher(puncher_id: int) -> void:
	var players := owner.get_parent()
	if players == null:
		return
	var puncher := players.get_node_or_null(str(puncher_id)) as Node3D
	if puncher == null:
		return
	var dir: Vector3 = puncher.global_position - owner.global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -owner.global_basis.z
	puncher.call("host_knock_down", dir, PARRY_RECOIL_SPEED_MPS, PARRY_RECOIL_SECONDS)

func _spawn_barrier(visual_only: bool) -> void:
	if is_instance_valid(_parry_barrier):
		return
	var scene: PackedScene = preload("res://player/parry_barrier.tscn")
	var barrier := scene.instantiate() as ParryBarrier
	if barrier == null:
		return
	barrier.owner_id = str(owner.name).to_int()
	barrier.radius_m = PhysicsTuning.PARRY_BARRIER_RADIUS_M
	barrier.height_m = PhysicsTuning.PARRY_BARRIER_HEIGHT_M
	barrier.visual_only = visual_only
	barrier.combat = self
	if owner != null:
		owner.add_child(barrier)   # exports are set before add_child so _ready sees them
	_parry_barrier = barrier

func _despawn_barrier() -> void:
	if is_instance_valid(_parry_barrier):
		_parry_barrier.queue_free()
	_parry_barrier = null

func _notice(text: String) -> void:
	if overlay != null and overlay.has_method("notice"):
		overlay.notice(text)

	# --- charged-punch lunge ------------------------------------------------------
# The lunge runs first. When it ends (time ran out, wall, or a player in the way)
# player.gd asks the host to spawn the hitbox: see _check_lunge_end().

## Start a lunge. Pass `charge >= 0` to make a hit wait at the end of it.
func start_lunge(direction: Vector3, speed: float, duration: float, charge: float = -1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_lunge_velocity = direction * speed
	_lunge_started = now
	_lunge_until = now + duration
	_lunge_pending = charge >= 0.0
	_lunge_charge = maxf(charge, 0.0)

func is_lunging(now: float) -> bool:
	return now < _lunge_until

func lunge_velocity() -> Vector3:
	return _lunge_velocity

func lunge_started() -> float:
	return _lunge_started

func has_pending_lunge_hit() -> bool:
	return _lunge_pending

## Stop the lunge now. Returns the charge the waiting hit should use.
func finish_lunge() -> float:
	_lunge_pending = false
	_lunge_until = 0.0
	_lunge_velocity = Vector3.ZERO
	return _lunge_charge

## Abort the lunge with no hit (knocked down mid-lunge).
func cancel_lunge() -> void:
	finish_lunge()

## Steer the lunge toward a look direction mid-flight (camera-arc punch).
func steer_lunge(look_dir: Vector3, strength: float, max_turn_rad_per_sec: float = 6.0, delta: float = 0.016) -> void:
	if not is_lunging(Time.get_ticks_msec() / 1000.0):
		return
	if strength <= 0.0:
		return
	var target := look_dir.normalized()
	var current := _lunge_velocity.normalized()
	if current == Vector3.ZERO:
		current = target
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

# Deprecated: use start_lunge().
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

func validate_punch(sender: Node3D, target: Node3D, charge: float) -> Array:
	var dist := sender.global_position.distance_to(target.global_position)
	if dist > PhysicsTuning.PUNCH_RANGE_M:
		return [false, false]
	var is_charged := charge >= 1.0
	return [true, is_charged]

const PhysicsProp := preload("res://interaction/physics_prop.gd")
