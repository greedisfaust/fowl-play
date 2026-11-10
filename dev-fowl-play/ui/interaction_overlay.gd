class_name InteractionOverlay
extends CanvasLayer

var reading := false
var _prompt: Label
var _inventory: Label
var _charge: ProgressBar
var _reader: PanelContainer
var _title: Label
var _body: Label
var _reticle: Label
var _scroll: ScrollContainer
var _notice_until := 0
var _notice := ""

func _ready() -> void:
	layer = 4
	_reticle = _label("·", Vector2(0.5, 0.5), Vector2(-12, -23), Vector2(24, 46), 32)
	_prompt = _label("", Vector2(0.5, 0.5), Vector2(-320, 36), Vector2(640, 70), 19)
	_inventory = _label("", Vector2(0.5, 1), Vector2(-400, -80), Vector2(800, 60), 18)
	_charge = ProgressBar.new()
	_charge.anchor_left = 0.5
	_charge.anchor_right = 0.5
	_charge.anchor_top = 1.0
	_charge.anchor_bottom = 1.0
	_charge.offset_left = -140
	_charge.offset_right = 140
	_charge.offset_top = -106
	_charge.offset_bottom = -94
	_charge.show_percentage = false
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charge.modulate = Color("edca78")
	add_child(_charge)
	_reader = PanelContainer.new()
	_reader.anchor_left = 0.5
	_reader.anchor_right = 0.5
	_reader.anchor_top = 0.5
	_reader.anchor_bottom = 0.5
	_reader.offset_left = -340
	_reader.offset_right = 340
	_reader.offset_top = -230
	_reader.offset_bottom = 230
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172322")
	style.border_color = Color("bd9d5c")
	style.set_border_width_all(2)
	style.set_content_margin_all(30)
	_reader.add_theme_stylebox_override("panel", style)
	_reader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reader)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	_reader.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 27)
	_title.modulate = Color("f1d69b")
	column.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 20)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	var close := Label.new()
	close.text = "E / Escape - fold  |  Mouse wheel / Page Up / Down - scroll"
	close.modulate = Color("c9c5b6")
	column.add_child(close)
	_reader.hide()
	_charge.hide()

func _label(text: String, anchor: Vector2, offset: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.anchor_left = anchor.x
	label.anchor_right = anchor.x
	label.anchor_top = anchor.y
	label.anchor_bottom = anchor.y
	label.position = offset
	label.size = size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func update_focus(prompt: String, held: String, charge: float, active: bool) -> void:
	_reticle.visible = active and not reading
	_reticle.text = "+" if prompt != "" else "·"
	_reticle.modulate = Color("ffdf8d") if prompt != "" else Color.WHITE
	_prompt.visible = active and not reading
	_prompt.text = "[E / LMB] " + prompt if prompt != "" else ""
	if Time.get_ticks_msec() < _notice_until:
		_prompt.text = _notice
	_inventory.visible = not reading
	_inventory.text = "HAND: EMPTY  |  E - pick up / interact" if held == "" else "HOLDING: %s  |  G - drop  |  hold RMB, release - throw" % held
	_charge.visible = charge >= 0.0 and not reading
	_charge.value = charge * 100.0

func notice(message: String) -> void:
	_notice = message
	_notice_until = Time.get_ticks_msec() + 2200

func show_lore(title: String, body: String) -> void:
	reading = true
	_title.text = title
	_body.text = body
	_scroll.scroll_vertical = 0
	_reader.show()

func scroll_lore(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical += 64
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical -= 64
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_PAGEDOWN:
			_scroll.scroll_vertical += 200
		elif event.keycode == KEY_PAGEUP:
			_scroll.scroll_vertical -= 200

func close_lore() -> void:
	reading = false
	_reader.hide()
