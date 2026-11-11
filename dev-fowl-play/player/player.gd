extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003
const Highlight := preload("res://interaction/focus_highlight.gd")
const Interactable := preload("res://interaction/interactable.gd")
const Overlay := preload("res://ui/interaction_overlay.gd")
const Prop := preload("res://interaction/physics_prop.gd")

const PUNCH_CHARGE_MS := 500      # hold Q this long for a charged punch
const PARRY_COOLDOWN := 1.5       # seconds before F can parry again
const PARRY_GRACE := 1.5          # max seconds parry stays active while holding F
const PUNCH_RANGE := 3.0          # how far a charged punch reaches

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D

var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var input_locked := false
var hands: Hands
var overlay: InteractionOverlay
var _focus: Node
var _highlight := Highlight.new()
var _charge_started := -1
var _last_push := 0
var _hover_sent := false
var _hover_clock := 0.0
var _punch_charge_started := -1     # Q held for charged punch (empty-handed)
var _punch_charge_held := false     # true while Q is currently held down
var _parry_cooldown := 0.0          # seconds remaining before F can parry again
var _parry_active_until := 0.0      # time until parry window expires
var _knocked_down_until := 0.0      # time until player gets back up
var _last_press := -10.0            # jab spam guard (seconds)
var _wall_hit_until := 0.0          # time until wall-hit stun expires
var _launch_until := 0.0            # time until thrown-player flight ends (preserves velocity)
var _cam_shake_until := 0.0         # time until camera shake expires
var _cam_shake_intensity := 1.0
# ---------- unified carry ----------
var _carry_mode := "none"           # "none" | "item" | "player"
var _carried_item: PhysicsProp = null  # item I'm carrying (local ref)
var _carried_player_id := 0         # peer id of player I'm carrying
var _carrier_id := 0                # peer id of who is carrying me (set when I'm downed)
var _carry_charge_started := -1     # charge timer for throwing whatever I carry
var _carry_charge_held := false     # true while Q is held to charge a throw
var _pickup_attempting := false     # true on the frame Q initiates a pickup (blocks punch charge)
var _just_picked_up := false        # set when Q resulted in a pickup; blocks punch charge

func _update_nameplate() -> void:
	$NamePlate.text = Network.player_name(str(name).to_int())
	_apply_color()

func _apply_color() -> void:
	var c: Color = Network.player_color(str(name).to_int())
	var m := StandardMaterial3D.new()   # a new one per player, because the scene's material is shared
	m.albedo_color = c
	$Body.material_override = m
	$NamePlate.modulate = c
	if hands:
		hands.set_color(c)

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	var mine := is_multiplayer_authority()
	camera.current = mine
	$Body.visible = not mine
	$Head/Beak.visible = not mine
	ray.add_exception(self)
	if Style.font:
		$NamePlate.font = Style.font
	$NamePlate.visible = not mine
	hands = Hands.new()
	hands.world_mode = not mine   # your own hands are first-person; everyone else's sit on the body
	(camera if mine else head).add_child(hands)
	Network.players_changed.connect(_update_nameplate)
	_update_nameplate()
	_net_pos = position
	if mine:
		overlay = Overlay.new()
		add_child(overlay)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	_just_picked_up = false   # one-frame flag: cleared each input frame
	if overlay != null and overlay.reading:
		overlay.scroll_lore(event)
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			overlay.close_lore()
			input_locked = false
		get_viewport().set_input_as_handled()
		return
	if input_locked:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_charge()
		_cancel_punch_charge()
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		hands.add_sway(event.relative)
	_handle_carry_input(event)
	_handle_punch_input(event)
	_handle_parry_input(event)
	# Only interact when not carrying anything — fixes the button bug while holding an item/player
	if Prop.held_by(get_tree(), str(name).to_int()) == null:
		if event.is_action_pressed("interact") or event.is_action_pressed("primary"):
			_try_interact()

func _resolve_carry_state() -> void:
	# Safety: if we think we're carrying but the reference is gone, reset carry mode
	# so G-drop and Q-throw work again instead of leaving you stuck.
	if _carry_mode == "item" and _carried_item == null:
		_carry_mode = "none"
		_charge_started = -1
	elif _carry_mode == "player" and _carried_player_id == 0:
		_carry_mode = "none"
		_charge_started = -1

func is_stunned() -> bool:
	return _knocked_down_until > Time.get_ticks_msec() / 1000.0 or _carrier_id != 0

func _handle_carry_input(event: InputEvent) -> void:
	_resolve_carry_state()
	# --- cannot do anything while being carried ourselves ---
	if _carrier_id != 0:
		return
	# --- dropping what we carry (G) ---
	if event.is_action_pressed("drop_item"):
		if _carry_mode == "item" and _carried_item != null:
			_carried_item.request_release.rpc_id(1, false)
			_carried_item = null
			_carry_mode = "none"
			_charge_started = -1
		elif _carry_mode == "player" and _carried_player_id != 0:
			# release carried player without throwing
			_launch_carried_player.rpc_id(_carried_player_id, Vector3.ZERO, 0.0, _carried_player_id)
			_carried_player_id = 0
			_carry_mode = "none"
			_charge_started = -1
		return
	# --- charging / throwing (hold Q or RMB, release) ---
	if _carry_mode != "none":
		if event.is_action_pressed("throw_item") or event.is_action_pressed("punch_charge"):
			_start_carry_charge()
		if event.is_action_released("throw_item") or event.is_action_released("punch_charge"):
			if _carry_charge_held:
				_release_carry_charge()
		return
	# --- empty-handed: Q picks up looked-at target (item or downed player) ---
	# NOTE: _raycast_hit() filters for take_punch() targets, which items
	# don't have. Do our own raycast here so Q can pick up both items
	# (interact()) and downed players (take_punch()).
	if event.is_action_pressed("punch_charge"):
		_pickup_attempting = true
		var target := ray.get_collider() if ray.is_colliding() else null
		if target != null and Interactable.can(target):
			target.interact(self)
			_just_picked_up = true   # block punch charge this frame
		_pickup_attempting = false

func _start_carry_charge() -> void:
	if _carry_mode == "none" or _carry_charge_held or _pickup_attempting:
		return
	_carry_charge_held = true
	_carry_charge_started = Time.get_ticks_msec()
	_charge_started = _carry_charge_started   # drives the throw-meter UI

func _release_carry_charge() -> void:
	if not _carry_charge_held or _carry_mode == "none":
		return
	_carry_charge_held = false
	var held_ms := Time.get_ticks_msec() - _carry_charge_started
	_carry_charge_started = -1
	var charge := clampf(float(held_ms) / PUNCH_CHARGE_MS, 0.0, 1.0)
	var direction := -head.global_basis.z
	if _carry_mode == "item" and _carried_item != null:
		_carried_item.request_release.rpc_id(1, true)
		_carried_item = null
		_carry_mode = "none"
		_charge_started = -1
	elif _carry_mode == "player" and _carried_player_id != 0:
		var speed := lerpf(6.0, 16.0, charge)
		_launch_carried_player.rpc_id(_carried_player_id, direction, speed, _carried_player_id)
		_carried_player_id = 0
		_carry_mode = "none"
		_charge_started = -1

func _handle_punch_input(event: InputEvent) -> void:
	# Q starts / releases a punch charge only when empty-handed (no item, no carried player).
	if _carry_mode != "none":
		return
	if event.is_action_pressed("punch_charge"):
		_start_punch_charge()
	if event.is_action_released("punch_charge"):
		_release_punch_charge()

func _start_punch_charge() -> void:
	if _punch_charge_held or _knocked_down_until > Time.get_ticks_msec() / 1000.0 or _pickup_attempting or _just_picked_up or _carry_mode != "none":
		return
	_punch_charge_held = true
	_punch_charge_started = Time.get_ticks_msec()

func _release_punch_charge() -> void:
	if not _punch_charge_held:
		return
	_punch_charge_held = false
	var held_ms := Time.get_ticks_msec() - _punch_charge_started
	_punch_charge_started = -1
	if held_ms < 150:
		_do_light_jab()
	else:
		_throw_charged_punch(clampf(float(held_ms) / PUNCH_CHARGE_MS, 0.0, 1.0))

func _cancel_punch_charge() -> void:
	_punch_charge_held = false
	_punch_charge_started = -1

func _do_light_jab() -> void:
	# Quick slap: short range, no knockdown, just a tiny stun/recoil. Runs on authority then tells peers.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_press < 0.35:
		return   # jab spam guard
	_last_press = now
	var target := _raycast_hit()
	if target != null and target.has_method("take_punch"):
		target.take_punch.rpc(str(name).to_int(), 0.0, false)   # light jab = 0 charge, not a knockdown
	_net_jab.rpc()

func _throw_charged_punch(charge: float) -> void:
	var target := _raycast_hit()
	if target != null and target.has_method("take_punch"):
		target.take_punch.rpc(str(name).to_int(), charge, charge >= 1.0)
	_net_punch.rpc(charge)

func _raycast_hit() -> Node:
	if not ray.is_colliding():
		return null
	var target = ray.get_collider()
	if target and not target.has_method("take_punch"):
		target = null
	return target

func _handle_parry_input(event: InputEvent) -> void:
	if _knocked_down_until > Time.get_ticks_msec() / 1000.0:
		return   # can't parry while down
	if event.is_action_pressed("parry"):
		_start_parry()

func _start_parry() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _parry_cooldown > 0.0 or now < _parry_active_until:
		return
	_parry_active_until = now + PARRY_GRACE   # press F: parry up for 1.5s grace
	show_notice("PARRY READY")

# Grace window expires on its own; cooldown starts after.
# Release of F does not cancel early — the full grace period runs.
func _expire_parry() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _parry_active_until > 0.0 and now >= _parry_active_until:
		_parry_active_until = 0.0
		_parry_cooldown = PARRY_COOLDOWN
		show_notice("PARRY COOLDOWN")

func _cancel_charge() -> void:
	if _charge_started >= 0:
		var held := Prop.held_by(get_tree(), str(name).to_int())
		if held != null:
			held.request_release.rpc_id(1, false)
	_charge_started = -1

func read_lore(title: String, text: String) -> void:
	_cancel_charge()
	input_locked = true
	overlay.show_lore(title, text)

func show_notice(message: String) -> void:
	if overlay != null:
		overlay.notice(message)

func _process(delta: float) -> void:
	if not is_multiplayer_authority() or overlay == null:
		return
	var active := not input_locked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var target: Node = ray.get_collider() if active and ray.is_colliding() else null
	if target != null and not Interactable.can(target):
		target = null
	# Only hover/glow players who are stunned or being carried — never healthy players
	if target != null and target.has_method("is_stunned") and not target.is_stunned():
		target = null
	var on := target != null
	if target != _focus:
		_focus = target
		_highlight.set_target(_focus)
	var point := ray.get_collision_point() if on else Vector3.ZERO
	hands.set_hover(on, point)
	_hover_clock -= delta
	if on != _hover_sent:
		_hover_sent = on
		_hover_clock = 0.07
		_net_hover_state.rpc(on, point)      # reliable: on/off can never get lost
	elif on and _hover_clock <= 0.0:
		_hover_clock = 0.07
		_net_hover_point.rpc(point)          # unreliable: just keeps the finger tracking
	var prompt := ""
	if is_instance_valid(_focus):
		prompt = _focus.get_interaction_prompt(self)
	var held := Prop.held_by(get_tree(), str(name).to_int())
	# Don't hide the charge bar when carrying a player — players aren't PhysicsProps,
	# so held_by() returns null even while we're holding one.
	if held == null and _carry_mode != "player":
		_charge_started = -1
	var charge := clampf((Time.get_ticks_msec() - _charge_started) / 1250.0, 0.0, 1.0) if _charge_started >= 0 else -1.0
	# Knockdown expired naturally: restore movement and release carrier link
	# But NOT while being carried — carried players stay down until thrown.
	if _knocked_down_until > 0.0 and _carrier_id == 0 and Time.get_ticks_msec() / 1000.0 >= _knocked_down_until:
		_knocked_down_until = 0.0
		input_locked = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_expire_parry()   # parry grace window expires on its own -> cooldown starts
	overlay.update_focus(prompt, held.item_name if held != null else "", charge, active)
	# camera shake decay
	var t := Time.get_ticks_msec() / 1000.0
	if t < _cam_shake_until:
		var s := _cam_shake_intensity * 0.03
		camera.rotation.x += randf_range(-s, s)
		camera.rotation.y += randf_range(-s, s)
	else:
		_cam_shake_until = 0.0

func _exit_tree() -> void:
	_highlight.clear()

func _try_interact() -> void:
	if _carry_mode != "none":
		return   # can't interact while carrying something
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	if target and Interactable.can(target):
		var p := ray.get_collision_point()
		hands.reach(p)
		_net_reach.rpc(p)   # tell everyone else where to swing this player's hand
		target.interact(self)

# ---------- punch / parry (phase 1) ----------

@rpc("any_peer", "call_local", "reliable")
func take_punch(attacker_id: int, _charge: float, is_charged: bool) -> void:
	# If the target is parrying, the attacker gets knocked down instead.
	if _parry_active_until > Time.get_ticks_msec() / 1000.0:
		_parry_active_until = 0.0
		_parry_cooldown = PARRY_COOLDOWN
		var attacker := _player_node(attacker_id)
		if attacker != null:
			attacker._apply_knockdown(2.5)
		show_notice("PARRIED!")
		return

	if is_charged:
		_apply_knockdown(2.5)
		# Shakedown: only during Day phase (casino), never in lobby/rest
		if GameState.phase == GameState.Phase.DAY:
			var pct := 5
			var new_wallet := maxi(0, GameState.wallet - (GameState.wallet * pct / 100.0))
			GameState._set_wallet.rpc(new_wallet)   # host-authoritative, replicates to all
			show_notice("SHAKEDOWN - %d%%" % pct)
		else:
			show_notice("KNOCKED DOWN")
	else:
		# Light jab: brief flinch, no knockdown
		_knocked_down_until = Time.get_ticks_msec() / 1000.0 + 0.35

@rpc("authority", "call_remote", "unreliable")
func _net_jab() -> void:
	hands.reach(ray.get_collision_point())

@rpc("authority", "call_remote", "unreliable")
func _net_punch(_charge: float) -> void:
	hands.reach(ray.get_collision_point())

func _player_node(id: int) -> Node3D:
	var world := get_tree().get_first_node_in_group("game_world")
	return world.get_node_or_null("Players/" + str(id)) if world != null else null

func _apply_knockdown(seconds: float) -> void:
	_knocked_down_until = Time.get_ticks_msec() / 1000.0 + seconds
	input_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# drop anything being carried
	if _carry_mode == "item" and _carried_item != null:
		_carried_item.request_release.rpc_id(1, false)
		_carried_item = null
		_carry_mode = "none"
		_charge_started = -1
	elif _carry_mode == "player":
		_carried_player_id = 0
		_carry_mode = "none"
		_charge_started = -1
	# visual slump: look down so the player reads as "downed"
	head.rotation.x = deg_to_rad(60)

# Called by physics_prop when this player picks up or drops an item.
func _set_carry_item(item: PhysicsProp) -> void:
	_carried_item = item
	_carry_mode = "item"
	# carrier keeps input (can move while carrying)

func _clear_carry_item() -> void:
	_carried_item = null
	_carry_mode = "none"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------- carry / throw knocked-down players (phase 2) ----------

# Called by another player pressing Q while looking at this downed player.
# Runs on the carrier's machine; player.name holds the carrier's peer ID,
# self.name holds this (downed) player's peer ID.
func interact(player: Node) -> void:
	var carrier_id := str(player.name).to_int()
	if carrier_id == 0:
		carrier_id = 1
	var carried_id := str(name).to_int()
	if carried_id == 0:
		carried_id = 1
	if Time.get_ticks_msec() / 1000.0 >= _knocked_down_until:
		return  # not downed, can't be picked up
	if _carrier_id != 0:
		return  # already being carried
	var carrier := _player_node(carrier_id)
	if carrier == null or carrier._carried_player_id != 0:
		return  # carrier already holding someone
	_pickup_request.rpc(carrier_id, carried_id)

@rpc("any_peer", "call_local", "reliable")
func _pickup_request(carrier_id: int, carried_id: int) -> void:
	# Runs on all machines. Each machine sets state for the player it owns.
	var my_id := multiplayer.get_unique_id()
	if my_id == carrier_id:
		var carrier := _player_node(carrier_id)
		if carrier != null:
			carrier._carried_player_id = carried_id
			carrier._carry_mode = "player"
			# carrier keeps input (can move while carrying)
	elif my_id == carried_id:
		_carrier_id = carrier_id
		input_locked = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		head.rotation.x = deg_to_rad(60)

func _carry_tick() -> void:
	# Runs on the carried player's machine each frame: follow the carrier.
	if _carrier_id == 0:
		return
	var carrier := _player_node(_carrier_id)
	if carrier == null:
		return
	var offset = -carrier.global_basis.z * 1.6 + Vector3(0, 0.6, 0)
	var target = carrier.global_position + offset
	# Raycast from carrier to target: stop at walls so carried player doesn't clip
	var from = carrier.global_position
	var query = PhysicsRayQueryParameters3D.create(from, target)
	query.exclude = [carrier.get_rid(), get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		target = hit.position + hit.normal * 0.25
	global_position = target
	global_basis = carrier.global_basis

@rpc("any_peer", "call_local", "reliable")
func _launch_carried_player(direction: Vector3, speed: float, target_id: int) -> void:
	# Runs on the carried player's machine: release with launch velocity.
	var my_id := multiplayer.get_unique_id()
	if my_id != target_id:
		return
	_carrier_id = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	velocity = direction * speed
	_knocked_down_until = Time.get_ticks_msec() / 1000.0 + 2.5
	_launch_until = Time.get_ticks_msec() / 1000.0 + 1.5   # keep velocity during flight, input returns after landing
	head.rotation.x = deg_to_rad(60)
	var world = get_tree().get_first_node_in_group("game_world")
	if world != null:
		world.add_child(self)

@rpc("any_peer", "call_local", "reliable")
func teleport_to(pos: Vector3, yaw: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may move players
	position = pos
	_cancel_charge()
	if overlay != null:
		overlay.close_lore()
		input_locked = false
	rotation.y = yaw
	_net_yaw = yaw
	velocity = Vector3.ZERO
	_net_pos = pos

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		position = position.lerp(_net_pos, 0.3)
		rotation.y = lerp_angle(rotation.y, _net_yaw, 0.3)
		head.rotation.x = lerpf(head.rotation.x, _net_pitch, 0.3)
		return
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not input_locked:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	# Preserve throw velocity during launch flight; don't overwrite it with input
	var now := Time.get_ticks_msec() / 1000.0
	if not input_locked and now >= _launch_until:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	if _carrier_id != 0:
		_carry_tick()   # being carried: follow carrier, skip physics
	else:
		move_and_slide()
	if Time.get_ticks_msec() - _last_push > 180:
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider is PhysicsProp:
				collider.request_push.rpc_id(1)
				_last_push = Time.get_ticks_msec()
				break
	hands.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
	_net_state.rpc(position, rotation.y, head.rotation.x)
	# wall-hit VFX: if we're moving fast and collide with a wall, play impact
	if velocity.length() > 8.0 and not is_on_floor():
		var wall_hit := false
		for i in get_slide_collision_count():
			var collider = get_slide_collision(i).get_collider()
			if collider is not PhysicsProp and collider is not CharacterBody3D:
				wall_hit = true
				break
		if wall_hit and Time.get_ticks_msec() / 1000.0 > _wall_hit_until:
			_wall_hit_until = Time.get_ticks_msec() / 1000.0 + 0.3
			_wall_hit_vfx.rpc(velocity.length())

@rpc("any_peer", "call_local", "reliable")
func _wall_hit_vfx(speed: float) -> void:
	var intensity := clampf(speed / 20.0, 0.5, 1.5)
	show_notice("WALL SLAM!")
	if hands != null:
		hands.shake(intensity)
	# camera shake (this peer's own camera) — applied in _process below
	_cam_shake_until = Time.get_ticks_msec() / 1000.0 + 0.25
	_cam_shake_intensity = intensity

@rpc("authority", "call_remote", "unreliable")
func _net_state(pos: Vector3, yaw: float, pitch: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch

@rpc("authority", "call_remote", "reliable")
func _net_hover_state(on: bool, point: Vector3) -> void:
	hands.set_hover(on, point)

@rpc("authority", "call_remote", "unreliable")
func _net_hover_point(point: Vector3) -> void:
	hands.update_hover_point(point)

@rpc("authority", "call_remote", "reliable")
func _net_reach(point: Vector3) -> void:
	hands.reach(point)   # runs on everyone else's copy of this player
