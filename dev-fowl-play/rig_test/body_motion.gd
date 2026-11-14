class_name BodyMotion
extends Node3D
## Cosmetic body life: walk bob, lean into movement, landing squash.
## Reads its parent's movement, so it works for local and remote players alike.

const BOB_HEIGHT_M := 0.04
const BOB_STRIDES_PER_M := 2.2        # bob cycles per meter walked
const LEAN_MAX_DEG := 8.0
const LEAN_REF_SPEED := 5.0
const SMOOTH := 10.0
const LAND_SPEED_MIN := 2.0           # falling this fast (m/s) triggers a squash
const SQUASH_PER_MPS := 0.015
const SQUASH_MAX := 0.18
const SQUASH_RECOVER := 9.0

@export var enabled := true

var _root: Node3D
var _base_pos := Vector3.ZERO
var _prev_root_pos := Vector3.ZERO
var _last_vy := 0.0
var _phase := 0.0
var _lean := Vector2.ZERO    # x = pitch, y = roll, in radians
var _squash := 0.0

func _ready() -> void:
	_root = get_parent() as Node3D
	_base_pos = position
	_prev_root_pos = _root.global_position

func _process(delta: float) -> void:
	if not enabled or delta <= 0.0:
		return
	var vel: Vector3 = (_root.global_position - _prev_root_pos) / delta
	_prev_root_pos = _root.global_position
	var local_vel: Vector3 = _root.global_basis.inverse() * Vector3(vel.x, 0.0, vel.z)
	var speed: float = local_vel.length()

	# bob: one up-down per half stride, only while moving
	_phase += speed * BOB_STRIDES_PER_M * TAU * delta
	var moving: float = clampf(speed / LEAN_REF_SPEED, 0.0, 1.0)
	position.y = _base_pos.y + absf(sin(_phase)) * BOB_HEIGHT_M * moving

	# lean: tilt toward the direction of travel (forward is -z), eased
	var lean_goal := Vector2(
		clampf(local_vel.z / LEAN_REF_SPEED, -1.0, 1.0),
		clampf(-local_vel.x / LEAN_REF_SPEED, -1.0, 1.0)) * deg_to_rad(LEAN_MAX_DEG)
	_lean = _lean.lerp(lean_goal, 1.0 - exp(-SMOOTH * delta))
	rotation.x = _lean.x
	rotation.z = _lean.y

	# landing squash: we were falling fast and just stopped
	if _last_vy < -LAND_SPEED_MIN and vel.y > _last_vy + LAND_SPEED_MIN:
		_squash = minf(-_last_vy * SQUASH_PER_MPS, SQUASH_MAX)
	_last_vy = vel.y
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-SQUASH_RECOVER * delta))
	scale = Vector3(1.0 + _squash * 0.5, 1.0 - _squash, 1.0 + _squash * 0.5)
