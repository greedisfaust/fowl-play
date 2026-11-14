class_name BetPanel
extends Node3D

signal key_pressed(op: String, arg: int)

const KEY_SCENE := preload("res://tables/press_button.tscn")
const SCREEN_SCENE := preload("res://tables/screen_3d.tscn")

const KEY_SIZE := Vector3(0.13, 0.05, 0.13)
const PRESET_SIZE := Vector3(0.22, 0.05, 0.13)
const PITCH := 0.155
const KEYPAD_X := -0.455
const KEY_Y := 0.085

const GOOD := Color(0.2, 1.0, 0.35)
const BAD := Color(1.0, 0.25, 0.25)

var _screen: Screen3D

func _ready() -> void:
	_build_housing()
	_build_keypad()
	_build_presets()
	_build_screen()

func _build_housing() -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.09, 0.73)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.1, 0.14)
	box.material = mat
	body.mesh = box
	body.position = Vector3(0.09, 0.022, 0)
	add_child(body)

func _build_keypad() -> void:
	var cream := Color(0.85, 0.82, 0.78)
	for row in 3:
		for col in 3:
			var n := row * 3 + col + 1
			_make_key(str(n), "digit", n, cream, KEY_SIZE, _grid_pos(KEYPAD_X, col, row))
	_make_key("C", "clear", 0, Color(0.85, 0.2, 0.2), KEY_SIZE, _grid_pos(KEYPAD_X, 0, 3))
	_make_key("0", "digit", 0, cream, KEY_SIZE, _grid_pos(KEYPAD_X, 1, 3))
	_make_key("<", "back", 0, Color(0.95, 0.7, 0.2), KEY_SIZE, _grid_pos(KEYPAD_X, 2, 3))

func _build_presets() -> void:
	var presets := [["MIN", "min"], ["1/4", "quarter"], ["1/2", "half"], ["MAX", "max"]]
	for r in 4:
		_make_key(presets[r][0], presets[r][1], 0, Color(1.0, 0.75, 0.1), PRESET_SIZE, Vector3(0.59, KEY_Y, -0.2325 + r * PITCH))

func _build_screen() -> void:
	_screen = SCREEN_SCENE.instantiate() as Screen3D
	_screen.panel_size = Vector2(0.5, 0.6)
	_screen.big_font_size = 52
	_screen.caption_font_size = 20
	_screen.position = Vector3(0.2, 0.075, 0)
	_screen.rotation_degrees = Vector3(-90, 0, 0)
	add_child(_screen)

func _grid_pos(x0: float, col: int, row: int) -> Vector3:
	return Vector3(x0 + col * PITCH, KEY_Y, -0.2325 + row * PITCH)

func _make_key(text: String, op: String, arg: int, color: Color, key_size: Vector3, pos: Vector3) -> void:
	var key := KEY_SCENE.instantiate() as PressButton
	key.label_text = text
	key.button_color = color
	key.size = key_size
	key.position = pos
	key.label_font_size = 28
	key.pressed.connect(func(_v: int) -> void: key_pressed.emit(op, arg))
	add_child(key)
	# Expose the single Interactable contract (R1).
	var interactable := Interactable.new()
	interactable.kind = Interactable.Kind.USE
	key.add_child(interactable)	

func show_bet(bet: int, min_bet: int, max_bet: int, locked: bool) -> void:
	if _screen == null:
		return
	var small := "IN PLAY" if locked else "MIN $%d\nMAX $%d" % [min_bet, max_bet]
	_screen.set_text("$%d" % bet, small)
	var ok := locked or (bet > 0 and bet >= min_bet)
	_screen.set_color(GOOD if ok else BAD)
