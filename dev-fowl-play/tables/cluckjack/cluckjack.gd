extends TableBase

const Rules := preload("res://tables/cluckjack/cluckjack_rules.gd")
const RESULT_TEXT := {
	"natural": "CLUCKJACK!", "win": "WINNER WINNER!", "push": "PUSH - STAKE RETURNED",
	"bust": "BUST!", "dealer_natural": "THE HOUSE HAS CLUCKJACK", "loss": "THE HOUSE WINS",
}

var hand := Rules.new() # never replicated: includes the deck and hole card
var _revision := 0 # monotonic action token rejects duplicate/stale button requests
var _view_revision := -1
var _public := {}
var _cards: Node3D
var _dealer_label: Label3D
var _player_label: Label3D
@onready var status: Screen3D = $StatusScreen

func _on_table_ready() -> void:
	$Buttons/PlayButton.label_text = "DEAL"
	$Buttons/PlayButton/Visual/Label3D.text = "DEAL"
	$Buttons/HitButton.pressed.connect(func(_v: int) -> void: send_action("hit", {"revision": _view_revision}))
	$Buttons/StandButton.pressed.connect(func(_v: int) -> void: send_action("stand", {"revision": _view_revision}))
	GameState.day_ended.connect(settle_for_day)
	multiplayer.peer_disconnected.connect(_on_bettor_left)
	_build_board()
	_on_table_reset()

func _on_round_start(_who: int, _total: int) -> void:
	hand.begin()
	_publish_or_finish()

func _on_player_action(_who: int, action: String, data: Dictionary) -> void:
	if not running or not hand.active or data.get("revision", -1) != _revision:
		return
	match action:
		"hit": hand.hit()
		"stand": hand.stand()
		_: return
	_publish_or_finish()

func _publish_or_finish(reason := "") -> void:
	_revision += 1
	var snapshot := hand.public_state()
	snapshot["revision"] = _revision
	snapshot["bettor"] = bettor_id
	snapshot["stake"] = locked_bet
	snapshot["reason"] = reason
	snapshot["payout"] = hand.payout(locked_bet)
	emit_event("hand", snapshot)
	if not hand.active:
		round_info = {
			"bust": hand.result == "bust", "result": hand.result,
			"player_total": Rules.total(hand.player), "dealer_total": Rules.total(hand.dealer),
			"note": "Cluckjack: %s%s" % [hand.result, " (" + reason + ")" if reason != "" else ""],
		}
		super.finish_round(hand.payout(locked_bet))

func settle_for_day() -> void:
	if multiplayer.is_server() and running and hand.active:
		hand.stand()
		_publish_or_finish("day ended - auto stand")

func _on_bettor_left(id: int) -> void:
	if multiplayer.is_server() and running and bettor_id == id and hand.active:
		hand.stand()
		_publish_or_finish("bettor left - auto stand")

func finish_round(_payout: int) -> void:
	# Forced world settlement must use card rules, not silently forfeit a live hand.
	settle_for_day()

func _on_table_reset() -> void:
	hand = Rules.new()
	_revision += 1
	_view_revision = -1
	_public.clear()
	_clear_cards()
	_dealer_label.text = "THE HOUSE"
	_player_label.text = "YOUR HAND"
	status.set_text("PLACE A BET, THEN DEAL", "CLUCKJACK")

func _on_event(event: String, data: Dictionary) -> void:
	if event != "hand":
		return
	_public = data
	_view_revision = data.revision
	_clear_cards()
	_draw_hand(data.dealer, 2.25)
	_draw_hand(data.player, 1.6)
	_dealer_label.text = "THE HOUSE - ?" if data.active else "THE HOUSE - %d" % data.dealer_total
	_player_label.text = "%s - %d" % [Network.player_name(data.bettor), data.player_total]
	if data.active:
		status.set_text("HIT OR STAND", "CLUCKJACK | %s | BET $%d" % [Network.player_name(data.bettor), data.stake])
	else:
		status.set_text("%s  $%d" % [RESULT_TEXT.get(data.result, data.result), data.payout],
			"CLUCKJACK | GROSS RETURN | " + (data.reason if data.reason != "" else "PLACE A BET TO DEAL AGAIN"))

func _clear_cards() -> void:
	if _cards == null:
		return
	for card in _cards.get_children():
		_cards.remove_child(card)
		card.queue_free()

func _build_board() -> void:
	_box(Vector3(3.55, 1.75, 0.06), Vector3(0, 1.98, -0.66), Color("143e35"), self)
	for x in [-1.8, 1.8]:
		_box(Vector3(0.04, 1.8, 0.08), Vector3(x, 1.98, -0.65), Color("d8ac56"), self)
	_cards = Node3D.new()
	add_child(_cards)
	_dealer_label = _label("THE HOUSE", Vector3(0, 2.58, -0.6), 32, Color("f3dd9b"), self)
	_player_label = _label("YOUR HAND", Vector3(0, 1.93, -0.6), 32, Color("f3dd9b"), self)
	_label("A = 1/11 | FACES = 10 | HOUSE STANDS ON ALL 17s\nWIN 2x | NATURAL 2.5x | PUSH 1x (GROSS)\nOdd-stake natural returns round down. No split or double.",
		Vector3(0, 1.15, -0.6), 32, Color.WHITE, self)

func _draw_hand(cards: Array, y: float) -> void:
	var spacing := minf(0.39, 3.15 / maxi(cards.size(), 1))
	for i in cards.size():
		var card: int = cards[i]
		var x := (i - (cards.size() - 1) * 0.5) * spacing
		_box(Vector3(spacing * 0.9, 0.43, 0.025), Vector3(x, y, -0.59),
			Color("b47637") if card < 0 else Color("fff3db"), _cards)
		var red := card >= 13 and card < 39
		_label(Rules.card_text(card), Vector3(x, y, -0.57), 43,
			Color("b52e36") if red else Color("17232b"), _cards)

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)

func _label(text: String, pos: Vector3, font_size: int, color: Color, parent: Node) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.pixel_size = 0.002
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)
	return label
