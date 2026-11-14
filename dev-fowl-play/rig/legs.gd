class_name Legs
extends Node3D
## Cosmetic legs: two 2-bone IK legs that take real steps. Reads only its parent's
## transform, so it works the same for local and remote players. Parent origin = feet.

const HIP_Y_M := 0.95
const HIP_X_M := 0.17
const THIGH_M := 0.48
const SHIN_M := 0.47
const THIGH_R_M := 0.124
const SHIN_R_M := 0.091
const KNEE_R_M := 0.1
const FOOT_LEN_M := 0.30
const FOOT_R_M := 0.085
const FOOT_FWD_M := 0.08
const ANKLE_H_M := 0.10
const SLACK_M := 0.01

# gait
const WALK_SPEED_REF := 2.2
const STRIDE_LENGTH_MIN := 0.35
const STRIDE_LENGTH_MAX := 1.05

const SWING_FRACTION := 0.38
const STEP_LIFT_M := 0.11
const STEP_FORWARD_FRACTION := 0.18

const MIN_WALK_SPEED := 0.08
const TELEPORT_SPEED := 25.0

const HIP_DROP_M := 0.08
const AIR_VY := 1.0
const VELOCITY_SMOOTH := 12.0

@export var color := Color(0.95, 0.45, 0.2)

var _root: Node3D
var _mat: StandardMaterial3D
var _planted: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _last_leg_phase: Array[float] = [0.4, 0.9]
var _gait_phase := 0.4
var _prev_pos := Vector3.ZERO
var _vel := Vector3.ZERO                                    # smoothed horizontal velocity
var _thigh: Array[MeshInstance3D] = []
var _shin: Array[MeshInstance3D] = []
var _knee: Array[MeshInstance3D] = []
var _foot: Array[MeshInstance3D] = []

func _ready() -> void:
	_root = get_parent() as Node3D
	_prev_pos = _root.global_position
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	for i in 2:
		_thigh.append(_capsule(THIGH_R_M, THIGH_M + THIGH_R_M * 2.0))
		_shin.append(_capsule(SHIN_R_M, SHIN_M + SHIN_R_M * 2.0))
		_foot.append(_capsule(FOOT_R_M, FOOT_LEN_M))
		_knee.append(_ball(KNEE_R_M))
		_planted[i] = _root.global_transform * Vector3(_side(i) * HIP_X_M, 0.0, 0.0)
		_last_leg_phase[i] = fposmod(_gait_phase + i * 0.5, 1.0)

func _side(i: int) -> float:
	return -1.0 if i == 0 else 1.0   # 0 = left, 1 = right

func _capsule(r: float, h: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 8
	m.mesh = c
	m.material_override = _mat
	add_child(m)
	return m

func _ball(r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	m.mesh = s
	m.material_override = _mat
	add_child(m)
	return m


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return

	var pos: Vector3 = _root.global_position

	# Prefer the actual CharacterBody velocity.
	# Fall back to position tracking for remotely interpolated players.
	var raw := Vector3.ZERO
	var character := _root as CharacterBody3D

	if character != null and character.velocity.length() > 0.001:
		raw = character.velocity
	else:
		raw = (pos - _prev_pos) / delta

	_prev_pos = pos

	var horizontal_speed := Vector2(raw.x, raw.z).length()
	var teleported := horizontal_speed > TELEPORT_SPEED
	var airborne := absf(raw.y) > AIR_VY

	if teleported:
		_vel = Vector3.ZERO
	else:
		_vel = _vel.lerp(
			Vector3(raw.x, 0.0, raw.z),
			1.0 - exp(-VELOCITY_SMOOTH * delta)
		)

	var speed := _vel.length()
	var walking := speed >= MIN_WALK_SPEED and not teleported and not airborne

	# Calculate the leg positions under the hips.
	var run := clampf(speed / WALK_SPEED_REF, 0.0, 1.0)
	var drop := HIP_DROP_M * run

	var ground_y := pos.y + ANKLE_H_M
	var max_total := THIGH_M + SHIN_M - SLACK_M
	var vertical := HIP_Y_M - drop - ANKLE_H_M
	var max_h := sqrt(maxf(max_total * max_total - vertical * vertical, 0.0))

	var hips: Array[Vector3] = []
	var spots: Array[Vector3] = []

	for i in 2:
		var hip: Vector3 = _root.global_transform * Vector3(
			_side(i) * HIP_X_M,
			HIP_Y_M - drop,
			0.0
		)

		hips.append(hip)
		spots.append(Vector3(hip.x, ground_y, hip.z))

	# If airborne, teleported, or stopped, reset feet under the body.
	if not walking:
		_gait_phase = 0.4

		for i in 2:
			_planted[i] = spots[i]
			_step_from[i] = spots[i]
			_step_to[i] = spots[i]
			_last_leg_phase[i] = fposmod(_gait_phase + i * 0.5, 1.0)

	else:
		# Stride grows with speed, while cadence increases naturally.
		var stride_length := lerpf(
			STRIDE_LENGTH_MIN,
			STRIDE_LENGTH_MAX,
			run
		)

		var cycle_frequency := speed / stride_length
		_gait_phase = fposmod(
			_gait_phase + cycle_frequency * delta,
			1.0
		)

		var move_dir := _vel.normalized()

		for i in 2:
			var phase := fposmod(_gait_phase + i * 0.5, 1.0)
			var previous_phase := _last_leg_phase[i]

			# Stance -> swing: begin a new step.
			if previous_phase >= SWING_FRACTION and phase < SWING_FRACTION:
				_begin_step(i, pos, move_dir, speed, stride_length)

			# Swing -> stance: plant the foot.
			elif previous_phase < SWING_FRACTION and phase >= SWING_FRACTION:
				_planted[i] = _step_to[i]

			_last_leg_phase[i] = phase

	# Calculate each leg's current ankle position and solve its IK.
	for i in 2:
		var ankle := _planted[i]
		var lift := 0.0

		var phase := fposmod(_gait_phase + i * 0.5, 1.0)

		if walking and phase < SWING_FRACTION:
			var t := clampf(phase / SWING_FRACTION, 0.0, 1.0)

			# Smooth forward foot movement.
			var eased := t * t * (3.0 - 2.0 * t)

			ankle = _step_from[i].lerp(_step_to[i], eased)

			# Lift the foot during the swing.
			lift = sin(PI * t) * STEP_LIFT_M

		# Keep the ankle within the leg's reachable distance.
		var flat := Vector2(
			ankle.x - hips[i].x,
			ankle.z - hips[i].z
		)

		if flat.length() > max_h:
			flat = flat.normalized() * max_h
			ankle.x = hips[i].x + flat.x
			ankle.z = hips[i].z + flat.y

			if not walking or phase >= SWING_FRACTION:
				_planted[i] = ankle

		ankle.y = ground_y + lift
		_solve(i, hips[i], ankle)


func _begin_step(
	i: int,
	root_pos: Vector3,
	move_dir: Vector3,
	speed: float,
	stride_length: float
) -> void:
	_step_from[i] = _planted[i]

	# Predict where the body will be when the swing finishes.
	var cycle_duration := stride_length / maxf(speed, 0.01)
	var swing_duration := cycle_duration * SWING_FRACTION

	var predicted_pos := root_pos + _vel * swing_duration

	# Place the landing foot slightly ahead of the predicted body position.
	var side_offset := _root.global_basis.x * _side(i) * HIP_X_M
	var forward_offset := move_dir * stride_length * STEP_FORWARD_FRACTION

	var target := predicted_pos + side_offset + forward_offset
	target.y = root_pos.y + ANKLE_H_M

	_step_to[i] = target

func _solve(i: int, hip: Vector3, ankle: Vector3) -> void:
	var to_ankle: Vector3 = ankle - hip
	var d: float = clampf(to_ankle.length(), 0.05, THIGH_M + SHIN_M - 0.001)
	var dir: Vector3 = to_ankle.normalized()
	# law of cosines: how far along hip->ankle the knee's shadow falls, and how far it sticks out
	var along: float = (THIGH_M * THIGH_M - SHIN_M * SHIN_M + d * d) / (2.0 * d)
	var out: float = sqrt(maxf(THIGH_M * THIGH_M - along * along, 0.0))
	var fwd: Vector3 = -_root.global_basis.z
	var pole: Vector3 = fwd - dir * fwd.dot(dir)   # knee bends toward the front of the body
	if pole.length() < 0.001:
		pole = _root.global_basis.x
	pole = pole.normalized()
	var knee: Vector3 = hip + dir * along + pole * out
	_place(_thigh[i], hip, knee)
	_place(_shin[i], knee, ankle)
	_knee[i].global_position = knee
	var yaw := Basis(Vector3.UP, _root.global_rotation.y)
	var foot_pos: Vector3 = ankle + yaw * Vector3(0.0, FOOT_R_M - ANKLE_H_M, -FOOT_FWD_M)
	_foot[i].global_transform = Transform3D(yaw * Basis(Vector3.RIGHT, PI / 2.0), foot_pos)

func _place(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	# stand a capsule (its long axis is Y) between two points
	var y: Vector3 = (b - a).normalized()
	var x: Vector3 = _root.global_basis.x
	x = (x - y * x.dot(y)).normalized()
	var z: Vector3 = x.cross(y)
	m.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
