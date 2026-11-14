class_name PressButton
extends StaticBody3D

signal pressed(value: int)

@export var value: int = 0
@export var label_text: String = ""
@export var button_color := Color(0.8, 0.8, 0.85)
@export var size := Vector3(0.3, 0.1, 0.3)
@export var label_font_size := 32

@onready var visual: Node3D = $Visual
var _tween: Tween

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = button_color
	box.material = mat
	$Visual/MeshInstance3D.mesh = box
	var shape := BoxShape3D.new()
	shape.size = size
	$CollisionShape3D.shape = shape
	var label: Label3D = $Visual/Label3D
	label.text = label_text
	if Style.font:
		label.font = Style.font
	var fit := int(size.x * 0.85 / (maxi(label_text.length(), 1) * 0.55 * label.pixel_size))
	label.font_size = mini(label_font_size, fit)
	label.outline_size = 4
	label.position = Vector3(0, size.y * 0.5 + 0.005, 0)
	# Expose the single Interactable contract (R1).
	var interactable := Interactable.new()
	interactable.kind = Interactable.Kind.USE
	add_child(interactable)

func get_interaction_prompt(_player: Node) -> String:
	return label_text if label_text != "" else "Press"

func interact(_player: Node) -> void:
	pressed.emit(value)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(visual, "position:y", -0.03, 0.05)
	_tween.tween_property(visual, "position:y", 0.0, 0.12)
