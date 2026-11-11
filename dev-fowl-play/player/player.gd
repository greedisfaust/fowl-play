extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003
const Highlight := preload("res://interaction/focus_highlight.gd")
const Overlay := preload("res://ui/interaction_overlay.gd")
const Prop := preload("res://interaction/physics_prop.gd")

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
	if event.is_action_pressed("interact") or event.is_action_pressed("primary"):
		_try_interact()

func _handle_carry_input(event: InputEvent) -> void:
	var held := Prop.held_by(get_tree(), str(name).to_int())
	if event.is_action_pressed("drop_item") and held != null:
		held.request_release.rpc_id(1, false)
		_charge_started = -1
	if event.is_action_pressed("throw_item") and held != null:
		_charge_started = Time.get_ticks_msec()
		held.request_charge.rpc_id(1)
	if event.is_action_released("throw_item") and held != null and _charge_started >= 0:
		held.request_release.rpc_id(1, true)
		_charge_started = -1

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
	if target != null and not target.has_method("interact"):
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
		if _focus.has_method("get_interaction_prompt"):
			prompt = _focus.get_interaction_prompt(self)
		elif _focus is PressButton:
			prompt = "Press " + _focus.label_text
		elif _focus is TextTerminal:
			prompt = "Edit " + _focus.title
		else:
			prompt = "Interact"
	var held := Prop.held_by(get_tree(), str(name).to_int())
	if held == null:
		_charge_started = -1
	var charge := clampf((Time.get_ticks_msec() - _charge_started) / 1250.0, 0.0, 1.0) if _charge_started >= 0 else -1.0
	overlay.update_focus(prompt, held.item_name if held != null else "", charge, active)

func _exit_tree() -> void:
	_highlight.clear()

func _try_interact() -> void:
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	if target and target.has_method("interact"):
		var p := ray.get_collision_point()
		hands.reach(p)
		_net_reach.rpc(p)   # tell everyone else where to swing this player's hand
		target.interact(self)

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
	var input_dir := Vector2.ZERO if input_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
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
