class_name ColorBoard
extends Node3D

signal chosen(index: int)

const BUTTON_SCENE := preload("res://tables/press_button.tscn")
const PITCH := 0.2

var _buttons: Array[PressButton] = []

func _ready() -> void:
	var count := Network.PALETTE.size()
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(count * PITCH + 0.1, 0.3, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.1, 0.14)
	box.material = mat
	plate.mesh = box
	add_child(plate)
	for i in count:
		var b := BUTTON_SCENE.instantiate() as PressButton
		b.value = i
		b.button_color = Network.PALETTE[i]
		b.size = Vector3(0.16, 0.06, 0.16)
		b.position = Vector3((i - (count - 1) / 2.0) * PITCH, 0, 0.06)
		b.rotation_degrees = Vector3(90, 0, 0)
		add_child(b)
		b.pressed.connect(func(v: int) -> void: chosen.emit(v))
		_buttons.append(b)
	Network.players_changed.connect(refresh)
	refresh()

func refresh() -> void:
	var me := multiplayer.get_unique_id()
	var mine: int = Network.colors.get(me, -1)
	for i in _buttons.size():
		var taken := false
		for id in Network.colors:
			if id != me and Network.colors[id] == i:
				taken = true
		var mesh := _buttons[i].get_node("Visual/MeshInstance3D") as MeshInstance3D
		var mat := (mesh.mesh as BoxMesh).material as StandardMaterial3D
		var c: Color = Network.PALETTE[i]
		mat.albedo_color = c.darkened(0.7) if taken else c
		mat.emission_enabled = i == mine
		mat.emission = c
		mat.emission_energy_multiplier = 1.5
