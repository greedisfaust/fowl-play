class_name LobbyConsole
extends Node3D

signal create_pressed
signal leave_pressed

const BUTTON_SCENE := preload("res://tables/press_button.tscn")
const SCREEN_SCENE := preload("res://tables/screen_3d.tscn")

var _screen: Screen3D

func _ready() -> void:
	_build_plate()
	_build_screen()
	var create_btn := _make_button("CREATE", Color(0.2, 0.75, 0.3), Vector3(-0.3, -0.28, 0.07))
	create_btn.pressed.connect(func(_v: int) -> void: create_pressed.emit())
	var leave_btn := _make_button("LEAVE", Color(0.85, 0.2, 0.2), Vector3(0.3, -0.28, 0.07))
	leave_btn.pressed.connect(func(_v: int) -> void: leave_pressed.emit())
	Network.state_changed.connect(refresh)
	Network.players_changed.connect(refresh)
	refresh()

func _build_plate() -> void:
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.9, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.1, 0.14)
	box.material = mat
	plate.mesh = box
	add_child(plate)

func _build_screen() -> void:
	_screen = SCREEN_SCENE.instantiate() as Screen3D
	_screen.panel_size = Vector2(1.1, 0.45)
	_screen.big_font_size = 56
	_screen.caption_font_size = 24
	_screen.text_color = Color(0.49, 0.98, 0.76)
	_screen.position = Vector3(0, 0.17, 0.055)
	add_child(_screen)

func _make_button(text: String, color: Color, pos: Vector3) -> PressButton:
	var b := BUTTON_SCENE.instantiate() as PressButton
	b.label_text = text
	b.button_color = color
	b.size = Vector3(0.45, 0.06, 0.2)
	b.position = pos
	b.rotation_degrees = Vector3(90, 0, 0)
	add_child(b)
	return b

func refresh() -> void:
	match Network.state:
		Network.State.SOLO:
			if Network.last_error != "":
				_screen.set_text("SOLO", Network.last_error)
			else:
				_screen.set_text("SOLO", "CREATE A LOBBY\nOR JOIN ONE")
		Network.State.HOSTING:
			_screen.set_text("HOSTING", "TELL FRIENDS: %s\n(%d/4 PLAYERS)" % [Network.local_ip(), Network.players.size()])
		Network.State.JOINING:
			_screen.set_text("JOINING...", "CONNECTING TO\n%s" % Network.last_ip)
		Network.State.JOINED:
			_screen.set_text("IN LOBBY", "HOST: %s\n(%d/4 PLAYERS)" % [Network.last_ip, Network.players.size()])
