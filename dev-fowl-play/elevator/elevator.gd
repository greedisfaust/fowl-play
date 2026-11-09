class_name Elevator
extends Node3D

signal ride_requested   # host only: everyone aboard, unlocked, button pressed

const SCREEN_SCENE := preload("res://tables/screen_3d.tscn")
const BUTTON_SCENE := preload("res://tables/press_button.tscn")

const CAB := Vector3(3.0, 2.6, 3.0)   # inside size: x width, y height, z depth
const WALL := 0.2
const OPENING := 1.6                  # door opening width
const OPEN_H := 2.0                   # door opening height
const DOOR_TIME := 1.2
const DOOR_OPEN_X := 1.08
const DOOR_CLOSED_X := 0.4
const SPOTS := [Vector2(-0.7, -0.6), Vector2(0.7, -0.6), Vector2(-0.7, 0.5), Vector2(0.7, 0.5)]

const RED := Color(1.0, 0.25, 0.25)
const AMBER := Color(1.0, 0.8, 0.2)
const GREEN := Color(0.3, 1.0, 0.45)
const WALL_COLOR := Color(0.85, 0.78, 0.64)
const CARPET_COLOR := Color(0.55, 0.06, 0.1)
const BRASS := Color(0.78, 0.6, 0.2)
const DOOR_COLOR := Color(0.7, 0.62, 0.4)

var open_title := "OPEN"       # big text on the monitors while unlocked (world.gd sets it)
var lock_text := "":           # empty = unlocked. world.gd sets it on every machine
	set(v):
		lock_text = v
		if is_node_ready():
			_refresh()
var doors_open := true

var _inside := {}              # host only: peer id -> true
var _inside_n := 0
var _total_n := 1
var _missing: Array = []
var _riding := false

var _door_l: AnimatableBody3D
var _door_r: AnimatableBody3D
var _door_tween: Tween
var _screen_out: Screen3D
var _screen_in: Screen3D
var _button: PressButton

func _ready() -> void:
	_build_cab()
	_door_l = _make_door(-DOOR_CLOSED_X)
	_door_r = _make_door(DOOR_CLOSED_X)
	_screen_out = _make_screen(Vector2(2.6, 0.7), 64, 24, Vector3(0, 2.4, CAB.z / 2.0 + WALL + 0.02))
	_screen_in = _make_screen(Vector2(1.5, 0.6), 48, 18, Vector3(0, 1.95, -CAB.z / 2.0 + 0.02))
	_build_button()
	_build_zone()
	Network.players_changed.connect(_check)
	_move_doors(true, true)
	_refresh()

# ---------- building ----------
func _add_box(size: Vector3, pos: Vector3, color: Color, solid := true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		mesh.add_child(body)

func _build_cab() -> void:
	var h := CAB.y + WALL
	var w := CAB.x + WALL * 2.0
	var front_z := (CAB.z + WALL) / 2.0
	var piece_w := (w - OPENING) / 2.0
	_add_box(Vector3(CAB.x, 0.02, CAB.z), Vector3(0, 0.01, 0), CARPET_COLOR, false)   # carpet
	_add_box(Vector3(w, WALL, CAB.z + WALL * 2.0), Vector3(0, CAB.y + WALL / 2.0, 0), Color(0.18, 0.12, 0.12))   # ceiling
	_add_box(Vector3(w, h, WALL), Vector3(0, h / 2.0, -front_z), WALL_COLOR)   # back wall
	for sx in [-1.0, 1.0]:
		_add_box(Vector3(WALL, h, CAB.z), Vector3(sx * (CAB.x + WALL) / 2.0, h / 2.0, 0), WALL_COLOR)   # side walls
		_add_box(Vector3(piece_w, h, WALL), Vector3(sx * (OPENING / 2.0 + piece_w / 2.0), h / 2.0, front_z), WALL_COLOR)   # front pieces
		_add_box(Vector3(0.08, OPEN_H, 0.24), Vector3(sx * (OPENING / 2.0 + 0.04), OPEN_H / 2.0, front_z), BRASS, false)   # jambs
	_add_box(Vector3(OPENING, h - OPEN_H, WALL), Vector3(0, OPEN_H + (h - OPEN_H) / 2.0, front_z), WALL_COLOR)   # above the door
	_add_box(Vector3(OPENING + 0.16, 0.08, 0.24), Vector3(0, OPEN_H + 0.04, front_z), BRASS, false)   # brass strip
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, CAB.y - 0.3, 0)
	lamp.omni_range = 5.0
	lamp.light_color = Color(1.0, 0.85, 0.6)
	add_child(lamp)

func _make_door(x: float) -> AnimatableBody3D:
	var size := Vector3(OPENING / 2.0 + 0.02, OPEN_H, 0.06)
	var body := AnimatableBody3D.new()
	body.position = Vector3(x, OPEN_H / 2.0, CAB.z / 2.0 - 0.04)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DOOR_COLOR
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	add_child(body)
	return body

func _make_screen(panel: Vector2, big: int, cap: int, pos: Vector3) -> Screen3D:
	var s := SCREEN_SCENE.instantiate() as Screen3D
	s.panel_size = panel
	s.big_font_size = big
	s.caption_font_size = cap
	s.position = pos
	add_child(s)
	return s

func _build_button() -> void:
	_button = BUTTON_SCENE.instantiate() as PressButton
	_button.label_text = "GO"
	_button.size = Vector3(0.4, 0.08, 0.4)
	_button.label_font_size = 48
	_button.position = Vector3(0, 1.15, -CAB.z / 2.0 + 0.04)
	_button.rotation_degrees = Vector3(90, 0, 0)
	add_child(_button)
	_button.pressed.connect(_on_button_pressed)

func _build_zone() -> void:
	var zone := Area3D.new()
	zone.position = Vector3(0, 1.25, 0)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CAB.x - 0.1, 2.4, CAB.z - 0.1)
	shape.shape = bs
	zone.add_child(shape)
	add_child(zone)
	zone.body_entered.connect(_on_body_entered)
	zone.body_exited.connect(_on_body_exited)

# ---------- doors ----------
func _move_doors(open: bool, instant := false) -> void:
	doors_open = open
	var x := DOOR_OPEN_X if open else DOOR_CLOSED_X
	if _door_tween:
		_door_tween.kill()
	if instant:
		_door_l.position.x = -x
		_door_r.position.x = x
		return
	_door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(_door_l, "position:x", -x, DOOR_TIME)
	_door_tween.tween_property(_door_r, "position:x", x, DOOR_TIME)

@rpc("authority", "call_local", "reliable")
func open_doors() -> void:
	_move_doors(true)

@rpc("authority", "call_local", "reliable")
func close_doors() -> void:
	_move_doors(false)

@rpc("authority", "call_local", "reliable")
func close_doors_instant() -> void:
	_move_doors(false, true)

@rpc("authority", "call_local", "reliable")
func set_riding(v: bool) -> void:
	_riding = v
	_refresh()

func reset() -> void:   # local only: world.gd uses it when the lobby collapses
	_riding = false
	_move_doors(true, true)
	_refresh()

# ---------- arrival ----------
func arrival_position(slot: int) -> Vector3:
	var s: Vector2 = SPOTS[clampi(slot - 1, 0, 3)]
	return to_global(Vector3(s.x, 0.1, s.y))

func arrival_yaw() -> float:
	return global_rotation.y + PI   # players face the doors

# ---------- host judging ----------
func _on_body_entered(body: Node3D) -> void:
	if multiplayer.is_server() and body is CharacterBody3D:
		_inside[str(body.name).to_int()] = true
		_check()

func _on_body_exited(body: Node3D) -> void:
	if multiplayer.is_server() and body is CharacterBody3D:
		_inside.erase(str(body.name).to_int())
		_check()

func _check() -> void:
	if not multiplayer.is_server():
		return
	var inside := 0
	var missing: Array = []
	for id in Network.players:
		if _inside.has(id):
			inside += 1
		else:
			missing.append(id)
	_sync_inside.rpc(inside, Network.players.size(), missing)

@rpc("authority", "call_local", "reliable")
func _sync_inside(inside: int, total: int, missing: Array) -> void:
	_inside_n = inside
	_total_n = total
	_missing = missing
	_refresh()

# ---------- button ----------
func _can_ride() -> bool:
	return not _riding and doors_open and lock_text == "" and _total_n > 0 and _inside_n == _total_n

func _on_button_pressed(_v: int) -> void:
	if _can_ride():
		_request_ride.rpc_id(1)
	else:
		_on_press_denied()

func _on_press_denied() -> void:
	pass   # TODO: click sound for a locked / not-ready button (spam-safe, nothing else happens)

@rpc("any_peer", "call_local", "reliable")
func _request_ride() -> void:
	if multiplayer.is_server() and _can_ride():
		ride_requested.emit()

# ---------- display ----------
func _waiting_text() -> String:
	if _missing.is_empty():
		return ""
	if _missing.size() == _total_n:
		return "EVERYONE GET IN"
	var names := PackedStringArray()
	for id in _missing:
		names.append(Network.player_name(id))
	var line := "WAITING: " + ", ".join(names)
	if line.length() > 28:
		line = "WAITING FOR %d PLAYERS" % _missing.size()
	return line

func _tint_button(c: Color, lit: bool) -> void:
	var mesh := _button.get_node("Visual/MeshInstance3D") as MeshInstance3D
	var mat := (mesh.mesh as BoxMesh).material as StandardMaterial3D
	mat.albedo_color = c
	mat.emission_enabled = lit
	mat.emission = c
	mat.emission_energy_multiplier = 1.5

func _refresh() -> void:
	var color: Color
	var big: String
	var small: String
	if _riding:
		color = AMBER
		big = "GOING..."
		small = "PLEASE STAND CLEAR"
	elif lock_text != "":
		color = RED
		big = "LOCKED"
		small = lock_text
	elif _total_n > 0 and _inside_n == _total_n:
		color = GREEN
		big = "READY"
		small = "PRESS THE BUTTON"
	else:
		color = AMBER
		big = open_title
		small = "%d/%d ABOARD\n%s" % [_inside_n, _total_n, _waiting_text()]
	for s in [_screen_out, _screen_in]:
		s.set_text(big, small)
		s.set_color(color)
	_tint_button(color, color == GREEN and not _riding)
