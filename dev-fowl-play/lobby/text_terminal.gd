class_name TextTerminal
extends StaticBody3D

signal submitted(text: String)

@export var title := "NICKNAME"
@export var max_length := 12
@export var allowed_chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-"

@onready var screen: Screen3D = $Screen

var text := ""
var _backup := ""
var _typing := false
var _player: Node = null
var _open_frame := -1

func _ready() -> void:
	_refresh()

func is_typing() -> bool:
	return _typing

func set_text(t: String) -> void:
	text = t
	_refresh()

func get_interaction_prompt(_player: Node) -> String:
	return "Edit " + title

func interact(player: Node) -> void:
	if _typing:
		return
	_typing = true
	_player = player
	_player.input_locked = true
	_open_frame = Engine.get_process_frames()
	_backup = text
	text = ""
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not _typing:
		return
	get_viewport().set_input_as_handled()
	if Engine.get_process_frames() == _open_frame:
		return
	if event is InputEventKey and event.pressed:
		_handle_key(event)

func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_finish(true)
		KEY_ESCAPE:
			_finish(false)
		KEY_BACKSPACE:
			text = text.left(text.length() - 1)
			_refresh()
		_:
			if event.echo or event.unicode < 32:
				return
			var c := char(event.unicode)
			if allowed_chars.contains(c) and text.length() < max_length:
				text += c
				_refresh()

func _finish(accept: bool) -> void:
	_typing = false
	if _player:
		_player.input_locked = false
		_player = null
	if accept and text.strip_edges() != "":
		submitted.emit(text)
	else:
		text = _backup
	_refresh()

func _refresh() -> void:
	if _typing:
		screen.set_text(text + "_", title + "  (ENTER = OK, ESC = CANCEL)")
	else:
		screen.set_text(text, title + "  (CLICK TO EDIT)")
