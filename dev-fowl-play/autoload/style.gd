extends Node

const FONT_PATH := "res://assets/fonts/ui_font.ttf"

var font: Font

func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
