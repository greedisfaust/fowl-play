class_name Hands
extends Node3D

# viewmodel (your own hands, parented to the Camera3D)
const VIEW_REST := [Vector3(-0.45, -0.36, -0.6), Vector3(0.45, -0.36, -0.6)]
const VIEW_ROT := [Vector3(1.15, -0.2, 0.15), Vector3(1.15, 0.2, -0.15)]
const VIEW_SCALE := 1.1
const VIEW_REACH := 1.1
# world model (what OTHER players see, parented to the Head)
const WORLD_REST := [Vector3(-0.60, -0.5, -0.42), Vector3(0.60, -0.5, -0.42)]
const WORLD_ROT := [Vector3(1.2, -0.2, 0.1), Vector3(1.2, 0.2, -0.1)]
const WORLD_SCALE := 1.6
const WORLD_REACH := 1.5

const POKE_HAND := 1          # right hand only
const HOVER_ROLL := -0.95     # thumb-up twist while pointing (flip the sign if the thumb ends up DOWN)
const POKE_ROLL := -0.95
const HOVER_LIFT := Vector3(0.0, 0.02, -0.05)
const IDLE_CURL := 0.08
const FIST_KNUCKLE := 1.5
const FIST_TIP := 1.75
const CURL_DIR := -1.0        # if fingers bend BACKWARDS, change to 1.0

# hand geometry (hand units, before scale)
const FINGER_X := [-0.036, -0.012, 0.012, 0.036]   # thumb side first on the right hand
const FINGER_LEN := [0.105, 0.115, 0.105, 0.085]   # index, middle, ring, pinky
const FINGER_R := [0.016, 0.0175, 0.017, 0.015]
const BASE_Z := -0.045
const INDEX_X := -0.036
const INDEX_REACH := 0.16     # hand origin to index fingertip

const REACH_TIME := 0.07
const RETURN_TIME := 0.2
const SPAM_WINDOW := 0.35

var world_mode := false   # set BEFORE add_child: true = the copy other players see

var _rest: Array
var _rest_q: Array = []
var _scale := 1.0
var _max_reach := 1.0

var _mat: StandardMaterial3D
var _rigs: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _fingers: Array = [{}, {}]   # {"point": [prox, dist], "curl": [[prox, dist]...], "thumb": [base, tip], "side": float}
var _pose := [0.0, 0.0]          # 0 = relaxed, 1 = pointing
var _tween: Tween
var _busy := false
var _hover := false
var _hover_t := 0.0
var _aim_goal := Quaternion.IDENTITY
var _aim_cur := Quaternion.IDENTITY
var _spam := 0
var _last_press := -10.0
var _sway := Vector2.ZERO
var _speed := 0.0
var _bob_t := 0.0
var _hover_msec := 0

func _ready() -> void:
	_rest = WORLD_REST if world_mode else VIEW_REST
	var rest_rot: Array = WORLD_ROT if world_mode else VIEW_ROT
	_scale = WORLD_SCALE if world_mode else VIEW_SCALE
	_max_reach = WORLD_REACH if world_mode else VIEW_REACH
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.96, 0.65, 0.14)
	if not world_mode:
		_mat.no_depth_test = true
		_mat.render_priority = 10
	for i in 2:
		var rig := Node3D.new()
		rig.position = _rest[i]
		add_child(rig)
		var hand := _build_hand(-1.0 if i == 0 else 1.0, i)
		_rest_q.append(Quaternion.from_euler(rest_rot[i]))
		hand.quaternion = _rest_q[i]
		hand.scale = Vector3.ONE * _scale
		rig.add_child(hand)
		_rigs.append(rig)
		_hands.append(hand)
		_apply_pose(i, 0.0)
	_aim_cur = _rest_q[POKE_HAND]
	_aim_goal = _aim_cur

# ---------- model: chunky tapered fingers with joint balls ----------
func _ball(parent: Node3D, pos: Vector3, r: float) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	m.mesh = s
	m.position = pos
	m.material_override = _mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)

func _seg(parent: Node3D, length: float, r_base: float, r_tip: float) -> void:
	# a tapered tube running from the joint (z = 0) toward -z
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_base
	c.bottom_radius = r_tip
	c.height = length
	c.radial_segments = 16
	m.mesh = c
	m.rotation.x = PI / 2.0
	m.position = Vector3(0, 0, -length / 2.0)
	m.material_override = _mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)

func _build_hand(side: float, idx: int) -> Node3D:
	var h := Node3D.new()
	_ball(h, Vector3.ZERO, 0.048)   # palm, squashed below
	(h.get_child(0) as Node3D).scale = Vector3(1.15, 0.6, 1.0)
	var wrist := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.024
	cyl.bottom_radius = 0.028
	cyl.height = 0.06
	wrist.mesh = cyl
	wrist.rotation.x = PI / 2.0
	wrist.position = Vector3(0, 0, 0.06)
	wrist.material_override = _mat
	wrist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(wrist)

	var curl: Array = []
	for k in 4:
		var order := k if side > 0.0 else 3 - k   # 0 = index, the finger beside the thumb
		var r: float = FINGER_R[order]
		var len_total: float = FINGER_LEN[order]
		var l1 := len_total * 0.55
		var l2 := len_total * 0.45
		var prox := Node3D.new()
		prox.position = Vector3(FINGER_X[k], 0.0, BASE_Z)
		h.add_child(prox)
		_ball(prox, Vector3.ZERO, r * 1.02)               # knuckle ball
		_seg(prox, l1, r, r * 0.9)
		var dist := Node3D.new()
		dist.position = Vector3(0, 0, -l1)
		prox.add_child(dist)
		_ball(dist, Vector3.ZERO, r * 0.92)               # middle joint ball
		_seg(dist, l2, r * 0.9, r * 0.75)
		_ball(dist, Vector3(0, 0, -l2), r * 0.76)         # rounded fingertip
		if order == 0:
			_fingers[idx]["point"] = [prox, dist]
		else:
			curl.append([prox, dist])
	_fingers[idx]["curl"] = curl

	# thumb: fleshy base + two segments, swings in beside the fist
	var tbase := Node3D.new()
	tbase.position = Vector3(-side * 0.055, -0.012, -0.005)
	h.add_child(tbase)
	_ball(tbase, Vector3.ZERO, 0.026)
	_seg(tbase, 0.042, 0.024, 0.021)
	var ttip := Node3D.new()
	ttip.position = Vector3(0, 0, -0.042)
	tbase.add_child(ttip)
	_ball(ttip, Vector3.ZERO, 0.021)
	_seg(ttip, 0.034, 0.021, 0.018)
	_ball(ttip, Vector3(0, 0, -0.034), 0.018)
	_fingers[idx]["thumb"] = [tbase, ttip]
	_fingers[idx]["side"] = side
	return h

func _apply_pose(i: int, v: float) -> void:
	_pose[i] = v
	var f: Dictionary = _fingers[i]
	f.point[0].rotation.x = CURL_DIR * lerpf(IDLE_CURL, 0.0, v)          # index straightens
	f.point[1].rotation.x = CURL_DIR * lerpf(IDLE_CURL * 0.8, 0.0, v)
	for j in f.curl:
		j[0].rotation.x = CURL_DIR * lerpf(IDLE_CURL, FIST_KNUCKLE, v)    # others fold into a fist
		j[1].rotation.x = CURL_DIR * lerpf(IDLE_CURL * 1.2, FIST_TIP, v)
	var side: float = f.side
	f.thumb[0].rotation.y = side * lerpf(0.55, 0.1, v)                   # swings in from the side
	f.thumb[0].rotation.x = CURL_DIR * lerpf(0.1, 0.5, v)                # and presses against the fist
	f.thumb[1].rotation.x = CURL_DIR * lerpf(0.15, 0.6, v)

func _aim_basis(dir: Vector3, roll: float) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	return Basis.looking_at(dir, up) * Basis(Vector3.BACK, roll)

# ---------- fed by player.gd ----------
func add_sway(rel: Vector2) -> void:
	_sway = (_sway + rel).limit_length(50.0)

func set_speed(s: float) -> void:
	_speed = s

func set_color(c: Color) -> void:
	_mat.albedo_color = c

func set_hover(v: bool, world_point := Vector3.ZERO) -> void:
	_hover_msec = Time.get_ticks_msec()
	if _rigs.is_empty():
		return
	if v:
		if not _hover and _hover_t < 0.01:
			_aim_cur = _rest_q[POKE_HAND]
		var d: Vector3 = (to_local(world_point) - _rigs[POKE_HAND].position).normalized()
		_aim_goal = _aim_basis(d, HOVER_ROLL).get_rotation_quaternion()
	_hover = v

func _process(delta: float) -> void:
	if world_mode and _hover and Time.get_ticks_msec() - _hover_msec > 250:
		_hover = false
	_hover_t = move_toward(_hover_t, 1.0 if _hover else 0.0, delta * 8.0)
	_aim_cur = _aim_cur.slerp(_aim_goal, 1.0 - exp(-delta * 18.0))
	if not _busy:
		_apply_pose(POKE_HAND, _hover_t)
		_hands[POKE_HAND].quaternion = _rest_q[POKE_HAND].slerp(_aim_cur, _hover_t)
	_sway = _sway.lerp(Vector2.ZERO, minf(8.0 * delta, 1.0))
	_bob_t += delta * (5.0 + _speed)
	var moving := clampf(_speed / 5.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in 2:
		var breathe := sin(t * 1.6 + i * 1.7) * 0.004
		var bob := absf(sin(_bob_t + i * 1.2)) * 0.02 * moving
		var lift := HOVER_LIFT * _hover_t if i == POKE_HAND else Vector3.ZERO
		_rigs[i].position = _rest[i] + lift + Vector3(-_sway.x * 0.0008, _sway.y * 0.0008 + breathe - bob, 0.0)

# ---------- poke (also what other players see) ----------
func reach(world_point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_spam = _spam + 1 if now - _last_press < SPAM_WINDOW else 1
	_last_press = now
	var i := POKE_HAND
	var rig := _rigs[i]
	var hand := _hands[i]
	var p := to_local(world_point)
	if p.length() > _max_reach:
		p = p.normalized() * _max_reach
	var dir: Vector3 = (p - rig.position).normalized()
	var aim_basis := _aim_basis(dir, POKE_ROLL)
	var target: Vector3 = p - rig.position - aim_basis * Vector3(INDEX_X * _scale, 0, -INDEX_REACH * _scale)
	var aim_q := aim_basis.get_rotation_quaternion()
	var frantic := _spam >= 3
	var t_in := REACH_TIME / (1.0 + 0.2 * mini(_spam, 6))
	var end_pose := _hover_t if _hover else 0.0
	var end_q: Quaternion = _rest_q[i].slerp(_aim_cur, end_pose)

	if _tween:
		_tween.kill()
	_busy = true
	var tw := create_tween()
	_tween = tw
	tw.tween_property(hand, "position", target, t_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hand, "quaternion", aim_q, t_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: _apply_pose(i, v), _pose[i], 1.0, t_in)
	if frantic:
		var wob := 0.5 if randf() < 0.5 else -0.5
		tw.tween_property(hand, "rotation:z", wob, 0.04).as_relative()
		tw.tween_property(hand, "rotation:z", -wob * 2.0, 0.06).as_relative()
	else:
		tw.tween_interval(0.03)
	var back := Tween.TRANS_ELASTIC if frantic else Tween.TRANS_QUAD
	tw.tween_property(hand, "position", Vector3.ZERO, RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hand, "quaternion", end_q, RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: _apply_pose(i, v), 1.0, end_pose, RETURN_TIME)
	tw.finished.connect(func() -> void: _busy = false)
