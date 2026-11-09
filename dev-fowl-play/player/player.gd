extends CharacterBody3D

const SPEED := 5.0
const JUMP_VELOCITY := 6.5
const GRAVITY := 20.0
const MOUSE_SENS := 0.003

@onready var head: Node3D = $Head
@onready var ray: RayCast3D = $Head/Camera3D/RayCast3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ray.add_exception(self)

func _unhandled_input(event: InputEvent) -> void:
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
	if event.is_action_pressed("interact") or event.is_action_pressed("primary"):
		_try_interact()

func _try_interact() -> void:
	if not ray.is_colliding():
		return
	var target = ray.get_collider()
	if target and target.has_method("interact"):
		target.interact(self)

func _physics_process(delta: float) -> void:
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	move_and_slide()
