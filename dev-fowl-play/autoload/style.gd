extends Node

const FONT_PATH := "res://assets/fonts/ui_font.ttf"


var font: Font
var text_scale := 1.0   # 1.0 = normal size; try 0.7 to 0.9 for smaller text everywhere

func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
