extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D

var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var input_locked := false
var hands: Hands

func _update_nameplate() -> void:
	$NamePlate.text = Network.player_name(str(name).to_int())
	_apply_color()

func _apply_color() -> void:
	var c := Network.player_color(str(name).to_int())
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if input_locked:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		hands.add_sway(event.relative)
	if event.is_action_pressed("interact") or event.is_action_pressed("primary"):
		_try_interact()

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
	hands.set_speed(Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0)
	_net_state.rpc(position, rotation.y, head.rotation.x)

@rpc("authority", "call_remote", "unreliable")
func _net_state(pos: Vector3, yaw: float, pitch: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch

@rpc("authority", "call_remote", "reliable")
func _net_reach(point: Vector3) -> void:
	hands.reach(point)   # runs on everyone else's copy of this player
