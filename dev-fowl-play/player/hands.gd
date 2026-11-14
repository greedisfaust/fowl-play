extends Node3D

class_name Hands

# viewmodel (your own hands, parented to the Camera3D)
const VIEW_REST := [Vector3(-0.45, -0.36, -0.6), Vector3(0.45, -0.36, -0.6)]
const VIEW_ROT := [Vector3(1.15, -0.2, 0.15), Vector3(1.15, 0.2, -0.15)]
const VIEW_SCALE := 1.32
const VIEW_REACH := 1.1
# The viewmodel is shrunk toward the camera so it can never poke into a wall. It looks identical on
# screen, but it can use normal depth testing, which is what stops the ringed/jumbled shading.
const VIEW_NODE_SCALE := 0.3
# world model (what OTHER players see, parented to the Head)
const WORLD_REST := [Vector3(-0.60, -0.5, -0.42), Vector3(0.60, -0.5, -0.42)]
const WORLD_ROT := [Vector3(1.2, -0.2, 0.1), Vector3(1.2, 0.2, -0.1)]
const WORLD_SCALE := 1.7
const WORLD_REACH := 1.5

const POKE_HAND := 1          # right hand only
const HOVER_ROLL := -0.95     # thumb-up twist while pointing (flip the sign if the thumb ends up DOWN)
const POKE_ROLL := -0.95
const CURL_DIR := -1.0        # if fingers bend BACKWARDS, change to 1.0

# hover pointing: the hand lifts and reaches out along the line to the target
const HOVER_SHIFT_VIEW := Vector3(0.0, 0.02, -0.05)
const HOVER_SHIFT_WORLD := Vector3(-0.25, 0.12, 0.0)   # pulls the hand toward the body's center line
const HOVER_EXTEND_VIEW := 0.05
const HOVER_EXTEND_WORLD := 0.4                        # how far the hand reaches toward what it points at

# finger curl per joint (knuckle, middle, tip) in radians
const REST_CURL := [0.10, 0.22, 0.12]
const FIST_CURL := [1.45, 1.75, 1.10]

# ---------- hand geometry (hand units, before scale) ----------
# -z = fingers, +z = wrist/forearm, -y = palm side. Fingers are listed index, middle, ring, pinky.
const FINGER_SPACING := 0.037
const FINGER_LEN := [0.090, 0.103, 0.095, 0.076]       # knuckle to fingertip
const FINGER_R := [0.0185, 0.0195, 0.0185, 0.0165]
const KNUCKLE_Z := [-0.052, -0.058, -0.052, -0.040]    # the knuckle row arcs: middle forward, pinky back
const SEG_RATIO := [0.47, 0.29, 0.24]                  # real phalanx proportions
const SPLAY := 0.05                                    # outer fingers fan out slightly
const PALM_FRONT := -0.05                              # knuckle end of the palm
const PALM_BACK := 0.07                                # wrist end of the palm
const PALM_W_FRONT := 0.075                            # half width at the knuckles
const PALM_W_BACK := 0.040                             # half width at the wrist (the palm is a trapezoid)
const PALM_THICK := 0.40
const INDEX_X := -1.5 * FINGER_SPACING                 # index finger offset on the right hand
const INDEX_REACH := 0.157                             # hand origin to index fingertip

const REACH_TIME := 0.07
const RETURN_TIME := 0.2
const SPAM_WINDOW := 0.35

var world_mode := false   # set BEFORE add_child: true = the copy other players see

var _rest: Array
var _rest_q: Array = []
var _scale := 1.0
var _node_scale := 1.0
var _max_reach := 1.0

var _mat: StandardMaterial3D
var _rigs: Array[Node3D] = []
var _hands: Array[Node3D] = []
var _fingers: Array = [{}, {}]   # {"point": [3 joints], "curl": [[3 joints]...], "thumb": [3 joints], "side": float}
var _pose := [0.0, 0.0]          # 0 = relaxed, 1 = pointing
var _tween: Tween
var _busy := false
var _hover := false
var _hover_t := 0.0
var _hover_world := Vector3.ZERO
var _offset_goal := Vector3.ZERO
var _offset_cur := Vector3.ZERO
var _aim_goal := Quaternion.IDENTITY
var _aim_cur := Quaternion.IDENTITY
var _spam := 0
var _last_press := -10.0
var _sway := Vector2.ZERO
var _speed := 0.0
var _bob_t := 0.0
var _shake_until := 0.0
var _shake_intensity := 1.0
var _guard_tween: Tween = null
var _guard_offset_goal := [Vector3.ZERO, Vector3.ZERO]
var _guard_offset_cur := [Vector3.ZERO, Vector3.ZERO]

func _ready() -> void:
	_rest = WORLD_REST if world_mode else VIEW_REST
	var rest_rot: Array = WORLD_ROT if world_mode else VIEW_ROT
	_scale = WORLD_SCALE if world_mode else VIEW_SCALE
	_max_reach = WORLD_REACH if world_mode else VIEW_REACH
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.96, 0.65, 0.14)
	_mat.roughness = 0.75
	if not world_mode:
		_node_scale = VIEW_NODE_SCALE
		scale = Vector3.ONE * _node_scale
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

# ---------- model ----------
func _style(m: MeshInstance3D) -> void:
	m.material_override = _mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ball(parent: Node3D, pos: Vector3, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	m.mesh = s
	m.position = pos
	_style(m)
	parent.add_child(m)
	return m

func _seg(parent: Node3D, length: float, r_base: float, r_tip: float) -> void:
	# a tapered tube running from the joint (z = 0) toward -z
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_base
	c.bottom_radius = r_tip
	c.height = length
	c.radial_segments = 20
	m.mesh = c
	m.rotation.x = PI / 2.0
	m.position = Vector3(0, 0, -length / 2.0)
	_style(m)
	parent.add_child(m)

func _build_palm(h: Node3D, side: float) -> void:
	# trapezoid slab: narrow at the wrist, wide at the knuckles
	var slab := CylinderMesh.new()
	slab.top_radius = PALM_W_BACK        # +z end (wrist)
	slab.bottom_radius = PALM_W_FRONT    # -z end (knuckles)
	slab.height = PALM_BACK - PALM_FRONT
	slab.radial_segments = 24
	var m := MeshInstance3D.new()
	m.mesh = slab
	m.rotation.x = PI / 2.0
	m.scale = Vector3(1.0, 1.0, PALM_THICK)
	m.position = Vector3(0, 0, (PALM_BACK + PALM_FRONT) * 0.5)
	_style(m)
	h.add_child(m)
	# rounded knuckle edge across the front of the slab
	var bar := _ball(h, Vector3(0, 0, PALM_FRONT + 0.004), 0.03)
	bar.scale = Vector3(PALM_W_FRONT / 0.03, PALM_THICK * PALM_W_FRONT / 0.03, 1.0)
	# fleshy pads on the palm side: big one under the thumb, smaller one on the pinky side
	for s in [-1.0, 1.0]:
		var thumb_side: bool = is_equal_approx(s, -side)
		var pad := _ball(h, Vector3(s * 0.026, -0.014, 0.024), 0.028 if thumb_side else 0.024)
		pad.scale = Vector3(1.0, 0.65, 1.4)
	# forearm stub with a rounded end: long in first person (it runs off screen), short on the
	# world copy so it doesn't read as a hand on a stick
	var arm_len := 0.07 if world_mode else 0.16
	var arm := CylinderMesh.new()
	arm.bottom_radius = 0.034
	arm.top_radius = 0.04
	arm.height = arm_len
	arm.radial_segments = 24
	var a := MeshInstance3D.new()
	a.mesh = arm
	a.rotation.x = PI / 2.0
	a.scale = Vector3(1.0, 1.0, 0.85)
	a.position = Vector3(0, 0, PALM_BACK + arm_len * 0.5)
	_style(a)
	h.add_child(a)
	var cap := _ball(h, Vector3(0, 0, PALM_BACK + arm_len), 0.04)
	cap.scale = Vector3(1.0, 0.85, 1.0)

func _build_finger(prox: Node3D, r: float, total: float) -> Array:
	var l1: float = total * SEG_RATIO[0]
	var l2: float = total * SEG_RATIO[1]
	var l3: float = total * SEG_RATIO[2]
	_ball(prox, Vector3.ZERO, r * 1.04)                 # knuckle
	_seg(prox, l1, r, r * 0.94)
	var mid := Node3D.new()
	mid.position = Vector3(0, 0, -l1)
	prox.add_child(mid)
	_ball(mid, Vector3.ZERO, r * 0.95)                  # middle joint
	_seg(mid, l2, r * 0.94, r * 0.88)
	var tip := Node3D.new()
	tip.position = Vector3(0, 0, -l2)
	mid.add_child(tip)
	_ball(tip, Vector3.ZERO, r * 0.89)                  # tip joint
	_seg(tip, l3, r * 0.88, r * 0.8)
	_ball(tip, Vector3(0, 0, -l3), r * 0.8)             # rounded fingertip
	return [prox, mid, tip]

func _build_thumb(h: Node3D, side: float) -> Array:
	# rooted low on the thumb side of the palm, angled outward
	var base := Node3D.new()
	base.position = Vector3(-side * 0.05, -0.012, 0.018)
	h.add_child(base)
	_ball(base, Vector3.ZERO, 0.028)
	_seg(base, 0.034, 0.028, 0.025)
	var mid := Node3D.new()
	mid.position = Vector3(0, 0, -0.034)
	base.add_child(mid)
	_ball(mid, Vector3.ZERO, 0.025)
	_seg(mid, 0.030, 0.025, 0.022)
	var tip := Node3D.new()
	tip.position = Vector3(0, 0, -0.030)
	mid.add_child(tip)
	_ball(tip, Vector3.ZERO, 0.022)
	_seg(tip, 0.026, 0.022, 0.019)
	_ball(tip, Vector3(0, 0, -0.026), 0.019)
	return [base, mid, tip]

func _build_hand(side: float, idx: int) -> Node3D:
	var h := Node3D.new()
	_build_palm(h, side)
	var curl: Array = []
	for k in 4:
		var order := k if side > 0.0 else 3 - k   # 0 = index, the finger beside the thumb
		var from_mid := k - 1.5
		var prox := Node3D.new()
		prox.position = Vector3(from_mid * FINGER_SPACING, 0.0, KNUCKLE_Z[order])
		if order != 0:
			prox.rotation.y = -from_mid * SPLAY    # the index stays straight so pointing is accurate
		h.add_child(prox)
		var joints := _build_finger(prox, FINGER_R[order], FINGER_LEN[order])
		if order == 0:
			_fingers[idx]["point"] = joints
		else:
			curl.append(joints)
	_fingers[idx]["curl"] = curl
	_fingers[idx]["thumb"] = _build_thumb(h, side)
	_fingers[idx]["side"] = side
	return h

func _apply_pose(i: int, v: float) -> void:
	_pose[i] = v
	var f: Dictionary = _fingers[i]
	var pointer: Array = f["point"]
	for j in 3:
		pointer[j].rotation.x = CURL_DIR * lerpf(REST_CURL[j], 0.0, v)             # index straightens
	for finger in f["curl"]:
		for j in 3:
			finger[j].rotation.x = CURL_DIR * lerpf(REST_CURL[j], FIST_CURL[j], v)  # the rest fold into a fist
	var thumb: Array = f["thumb"]
	var side: float = f["side"]
	thumb[0].rotation.y = side * lerpf(0.6, 0.15, v)        # swings in from the side
	thumb[0].rotation.x = CURL_DIR * lerpf(0.25, 0.55, v)   # and presses against the fist
	thumb[1].rotation.x = CURL_DIR * lerpf(0.2, 0.5, v)
	thumb[2].rotation.x = CURL_DIR * lerpf(0.15, 0.6, v)

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

# Box both hands in front of the face (parry guard) or relax back to normal.
# `active` = true pulls both hands up in front of the face, palms forward.
# Sets _guard_offset_goal; _process lerps _guard_offset_cur toward it each frame
# and adds it to each rig, giving smooth 0.3s in / 0.6s out without fighting
# _process's bob/sway. Hand rotations tween directly.
func set_guard(active: bool) -> void:
	if _rigs.is_empty():
		return
	if _guard_tween != null:
		_guard_tween.kill()
		_guard_tween = null
	var tw := create_tween()
	_guard_tween = tw
	var duration := 0.3 if active else 0.6   # smooth in: 0.3s, relax: 0.6s
	var pitch_up := Quaternion.from_euler(Vector3(deg_to_rad(45.0), 0.0, 0.0))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var target_q: Quaternion
		if active:
			# Boxer guard: fists up at cheek level, palms facing inward,
			# knuckles pointing outward/toward the opponent.
			_guard_offset_goal[i] = Vector3(side * 0.07, 0.24, -0.06)
			var yaw_in := Quaternion.from_euler(Vector3(0.0, side * deg_to_rad(18.0), 0.0))
			target_q = (_rest_q[i] as Quaternion) * pitch_up * yaw_in
		else:
			_guard_offset_goal[i] = Vector3.ZERO
			target_q = (_rest_q[i] as Quaternion)
		tw.tween_property(_hands[i], "quaternion", target_q, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func(): _guard_tween = null)

func shake(intensity: float) -> void:
	_shake_intensity = clampf(intensity, 0.0, 2.0)
	_shake_until = Time.get_ticks_msec() / 1000.0 + 0.25

# world point -> the hand's own units. The viewmodel node is shrunk, so undo that here to keep all
# reach/aim math identical to an unscaled hand.
func _to_hand_units(world_point: Vector3) -> Vector3:
	return to_local(world_point) * _node_scale

func set_hover(v: bool, world_point := Vector3.ZERO) -> void:
	if _rigs.is_empty():
		return
	if v:
		if not _hover and _hover_t < 0.01:
			_aim_cur = _rest_q[POKE_HAND]
		_hover_world = world_point
	_hover = v

func update_hover_point(world_point: Vector3) -> void:
	if not _hover or _rigs.is_empty():
		return   # a late packet can't re-enable a hover that already ended
	_hover_world = world_point

# works out where the pointing hand sits and how it must turn so the INDEX FINGER lines up with the target
func _update_aim() -> void:
	var rest: Vector3 = _rest[POKE_HAND]
	var target := _to_hand_units(_hover_world)
	var shift: Vector3 = HOVER_SHIFT_WORLD if world_mode else HOVER_SHIFT_VIEW
	var reach_out: float = HOVER_EXTEND_WORLD if world_mode else HOVER_EXTEND_VIEW
	var base := rest + shift
	var to_target := target - base
	if to_target.length() < 0.1:
		return
	reach_out = clampf(to_target.length() - 0.25, 0.0, reach_out)
	var anchor := base + to_target.normalized() * reach_out
	var index_off := Vector3(INDEX_X * _scale, 0.0, 0.0)
	var b := _aim_basis((target - anchor).normalized(), HOVER_ROLL)
	var from_index := anchor + b * index_off
	b = _aim_basis((target - from_index).normalized(), HOVER_ROLL)
	_offset_goal = anchor - rest
	_aim_goal = b.get_rotation_quaternion()

func _process(delta: float) -> void:
	_hover_t = move_toward(_hover_t, 1.0 if _hover else 0.0, delta * 8.0)
	if _hover:
		_update_aim()
	_aim_cur = _aim_cur.slerp(_aim_goal, 1.0 - exp(-delta * 18.0))
	_offset_cur = _offset_cur.lerp(_offset_goal, 1.0 - exp(-delta * 14.0))
	for i in 2:
		_guard_offset_cur[i] = _guard_offset_cur[i].lerp(_guard_offset_goal[i], 1.0 - exp(-delta * 12.0))
	if not _busy:
		_apply_pose(POKE_HAND, _hover_t)
		# Don't fight the parry-guard tween: if guard is active, leave the
		# hand's quaternion to the tween (set by set_guard()).
		var guard_active: bool = _guard_offset_goal[POKE_HAND] != Vector3.ZERO
		if _guard_tween == null and not guard_active:
			_hands[POKE_HAND].quaternion = _rest_q[POKE_HAND].slerp(_aim_cur, _hover_t)
	_sway = _sway.lerp(Vector2.ZERO, minf(8.0 * delta, 1.0))
	var shake_t := Time.get_ticks_msec() / 1000.0
	if shake_t < _shake_until:
		var s := _shake_intensity * 0.015
		for i in 2:
			_rigs[i].position += Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	_bob_t += delta * (5.0 + _speed)
	var moving := clampf(_speed / 5.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in 2:
		var breathe := sin(t * 1.6 + i * 1.7) * 0.004
		var bob := absf(sin(_bob_t + i * 1.2)) * 0.02 * moving
		var offset := _offset_cur * _hover_t if i == POKE_HAND else Vector3.ZERO
		_rigs[i].position = _rest[i] + offset + _guard_offset_cur[i] + Vector3(-_sway.x * 0.0008, _sway.y * 0.0008 + breathe - bob, 0.0)

# ---------- poke (also what other players see) ----------
func reach(world_point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_spam = _spam + 1 if now - _last_press < SPAM_WINDOW else 1
	_last_press = now
	var i := POKE_HAND
	var rig := _rigs[i]
	var hand := _hands[i]
	var p := _to_hand_units(world_point)
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
	tw.parallel().tween_method(func(v: float): _apply_pose(i, v), _pose[i], 1.0, t_in)
	if frantic:
		var wob := 0.5 if randf() < 0.5 else -0.5
		tw.tween_property(hand, "rotation:z", wob, 0.04).as_relative()
		tw.tween_property(hand, "rotation:z", -wob * 2.0, 0.06).as_relative()
	else:
		tw.tween_interval(0.03)
	var back := Tween.TRANS_ELASTIC if frantic else Tween.TRANS_QUAD
	tw.tween_property(hand, "position", Vector3.ZERO, RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hand, "quaternion", end_q, RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): _apply_pose(i, v), 1.0, end_pose, RETURN_TIME)
	tw.finished.connect(func(): _busy = false)
