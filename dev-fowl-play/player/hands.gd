class_name Hands
extends Node3D

# viewmodel (your own hands, parented to the Camera3D)
const VIEW_REST := [Vector3(-0.50, -0.32, -0.6), Vector3(0.50, -0.32, -0.6)]
const VIEW_ROT := [Vector3(0.3, -0.25, 0.2), Vector3(0.3, 0.25, -0.2)]
const VIEW_SCALE := 1.5
const VIEW_REACH := 1.1
# world model (what OTHER players see, parented to the Head)
const WORLD_REST := [Vector3(-0.60, -0.5, -0.42), Vector3(0.60, -0.5, -0.42)]
const WORLD_ROT := [Vector3(0.2, -0.2, 0.15), Vector3(0.2, 0.2, -0.15)]
const WORLD_SCALE := 2.4
const WORLD_REACH := 1.5

const POKE_HAND := 1        # 0 = left, 1 = right: the only hand that reaches
const IDLE_CURL := 0.25     # relaxed fingers at rest (radians)
const FIST_CURL := 1.5      # curled fingers while pointing
const THUMB_CURL := 0.9
const CURL_DIR := -1.0      # if the fingers bend BACKWARDS, change this to 1.0

const REACH_TIME := 0.07
const RETURN_TIME := 0.2
const SPAM_WINDOW := 0.35

var world_mode := false   # set BEFORE add_child: true = the copy other players see

var _rest: Array
var _rest_rot: Array
var _scale := 1.0
var _finger_len := 0.2
var _max_reach := 1.0

var _mat: StandardMaterial3D
var _rigs: Array[Node3D] = []     # idle motion lives here
var _hands: Array[Node3D] = []    # reach animation lives here
var _fingers: Array = [{}, {}]    # per hand: {"point": index finger, "curl": [fingers], "thumb": thumb}
var _pose := [0.0, 0.0]           # 0 = open hand, 1 = pointing
var _tween: Tween
var _busy := false
var _spam := 0
var _last_press := -10.0
var _sway := Vector2.ZERO
var _speed := 0.0
var _bob_t := 0.0

func _ready() -> void:
	_rest = WORLD_REST if world_mode else VIEW_REST
	_rest_rot = WORLD_ROT if world_mode else VIEW_ROT
	_scale = WORLD_SCALE if world_mode else VIEW_SCALE
	_max_reach = WORLD_REACH if world_mode else VIEW_REACH
	_finger_len = 0.17 * _scale
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.96, 0.65, 0.14)
	if not world_mode:
		_mat.no_depth_test = true   # your own hands draw over walls; other players' hands are normal geometry
		_mat.render_priority = 10
	for i in 2:
		var rig := Node3D.new()
		rig.position = _rest[i]
		add_child(rig)
		var hand := _build_hand(-1.0 if i == 0 else 1.0, i)
		hand.rotation = _rest_rot[i]
		hand.scale = Vector3.ONE * _scale
		rig.add_child(hand)
		_rigs.append(rig)
		_hands.append(hand)
		_apply_pose(i, 0.0)

# ---------- model (palm + 4 fingers + thumb, each finger on its own joint) ----------
func _build_hand(side: float, idx: int) -> Node3D:
	var h := Node3D.new()
	var palm := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.055
	sph.height = 0.11
	palm.mesh = sph
	palm.scale = Vector3(1.0, 0.65, 1.15)
	palm.material_override = _mat
	palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(palm)
	var xs := [-0.034, -0.011, 0.011, 0.034]
	var lens := [0.085, 0.105, 0.095, 0.075]
	var curl: Array = []
	for k in 4:
		var joint := Node3D.new()
		joint.position = Vector3(xs[k], 0, -0.05)
		h.add_child(joint)
		_limb(joint, Vector3.ZERO, Vector3(0, 0, -lens[k]), 0.016)
		if k == 1:
			_fingers[idx]["point"] = joint   # the longest finger does the pointing
		else:
			curl.append(joint)
	_fingers[idx]["curl"] = curl
	var thumb := Node3D.new()
	thumb.position = Vector3(-side * 0.045, 0, -0.01)
	h.add_child(thumb)
	_limb(thumb, Vector3.ZERO, Vector3(-side * 0.035, 0, -0.06), 0.018)
	_fingers[idx]["thumb"] = thumb
	return h

func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var m := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = a.distance_to(b) + r * 2.0
	m.mesh = cap
	m.material_override = _mat
	m.position = (a + b) * 0.5
	m.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)

func _apply_pose(i: int, v: float) -> void:
	_pose[i] = v
	var f: Dictionary = _fingers[i]
	f.point.rotation.x = CURL_DIR * lerpf(IDLE_CURL, 0.0, v)    # the pointer straightens out
	for j in f.curl:
		j.rotation.x = CURL_DIR * lerpf(IDLE_CURL, FIST_CURL, v)   # the rest curl into a fist
	f.thumb.rotation.x = CURL_DIR * lerpf(IDLE_CURL * 0.5, THUMB_CURL, v)

# ---------- fed by player.gd (local viewmodel only) ----------
func add_sway(rel: Vector2) -> void:
	_sway = (_sway + rel).limit_length(50.0)

func set_speed(s: float) -> void:
	_speed = s

func set_color(c: Color) -> void:
	_mat.albedo_color = c

func _process(delta: float) -> void:
	_sway = _sway.lerp(Vector2.ZERO, minf(8.0 * delta, 1.0))
	_bob_t += delta * (5.0 + _speed)
	var moving := clampf(_speed / 5.0, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	for i in 2:
		var breathe := sin(t * 1.6 + i * 1.7) * 0.004
		var bob := absf(sin(_bob_t + i * 1.2)) * 0.02 * moving
		_rigs[i].position = _rest[i] + Vector3(-_sway.x * 0.0008, _sway.y * 0.0008 + breathe - bob, 0.0)

# ---------- reach (right hand only) ----------
func reach(world_point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_spam = _spam + 1 if now - _last_press < SPAM_WINDOW else 1
	_last_press = now
	var p := to_local(world_point)   # this node sits at the camera / head origin
	if p.length() > _max_reach:
		p = p.normalized() * _max_reach
	var i := POKE_HAND
	var rig := _rigs[i]
	var hand := _hands[i]
	var dir: Vector3 = (p - rig.position).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var aim := Basis.looking_at(dir, up).get_euler()
	var target: Vector3 = p - dir * _finger_len - rig.position
	var frantic := _spam >= 3
	var t_in := REACH_TIME / (1.0 + 0.2 * mini(_spam, 6))

	if _tween:
		_tween.kill()   # a spam press restarts from wherever the hand is: that's the yank
	_busy = true
	var tw := create_tween()
	_tween = tw
	tw.tween_property(hand, "position", target, t_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hand, "rotation", aim, t_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: _apply_pose(i, v), _pose[i], 1.0, t_in)   # curl into the point
	if frantic:
		var wob := 0.5 if randf() < 0.5 else -0.5
		tw.tween_property(hand, "rotation:z", aim.z + wob, 0.04)
		tw.tween_property(hand, "rotation:z", aim.z - wob, 0.06)
	else:
		tw.tween_interval(0.03)
	var back := Tween.TRANS_ELASTIC if frantic else Tween.TRANS_QUAD
	tw.tween_property(hand, "position", Vector3.ZERO, RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(hand, "rotation", _rest_rot[i], RETURN_TIME).set_trans(back).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float) -> void: _apply_pose(i, v), 1.0, 0.0, RETURN_TIME)   # open the hand again
	tw.finished.connect(func() -> void: _busy = false)
