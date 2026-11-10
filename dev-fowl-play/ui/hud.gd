extends CanvasLayer

@onready var wallet_label: Label = $Stats/WalletLabel
@onready var quota_label: Label = $Stats/QuotaLabel
@onready var timer_label: Label = $Stats/TimerLabel
@onready var announcer: Label = $AnnouncerLabel

var _announce_id := 0
var _fade_rect: ColorRect
var _fade_tween: Tween

func _ready() -> void:
	_build_fade()
	GameState.wallet_changed.connect(_on_wallet_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.round_started.connect(_on_round_started)
	quota_label.text = "Quota: $%d" % GameState.quota
	_on_wallet_changed(GameState.wallet)
	_on_time_changed(ceili(GameState.time_left))
	announcer.hide()
	GameState.quota_changed.connect(func(q: int) -> void: quota_label.text = "Quota: $%d" % q)

func _on_wallet_changed(value: int) -> void:
	wallet_label.text = "$%d" % value

func _on_time_changed(seconds_left: int) -> void:
	timer_label.text = "%d:%02d" % [floori(seconds_left / 60.0), seconds_left % 60]

func _on_round_started(player_id: int, table: String, bet: int) -> void:
	announce("%s bet $%d on %s!" % [Network.player_name(player_id), bet, table])

func announce(text: String) -> void:
	_announce_id += 1
	var my_id := _announce_id
	announcer.text = text
	announcer.show()
	await get_tree().create_timer(2.5).timeout
	if my_id == _announce_id:
		announcer.hide()

func _build_fade() -> void:
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 10
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func fade_to(alpha: float, secs: float) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "modulate:a", alpha, secs)
