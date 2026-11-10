class_name CluckjackRules
extends RefCounted
## Host-only hand model. Card IDs 0..51: suit * 13 + rank - 1.

var deck: Array[int] = []
var player: Array[int] = []
var dealer: Array[int] = []
var active := false
var result := ""

static func fresh_deck() -> Array[int]:
	var cards: Array[int] = []
	for card in 52:
		cards.append(card)
	cards.shuffle()
	return cards

static func total(cards: Array[int]) -> int:
	var value := 0
	var aces := 0
	for card in cards:
		var rank := card % 13 + 1
		value += mini(rank, 10) if rank != 1 else 11
		if rank == 1:
			aces += 1
	while value > 21 and aces > 0:
		value -= 10
		aces -= 1
	return value

static func natural(cards: Array[int]) -> bool:
	return cards.size() == 2 and total(cards) == 21

static func card_text(card: int) -> String:
	if card < 0:
		return "?"
	var rank := card % 13 + 1
	var rank_text := str(rank)
	if rank == 1:
		rank_text = "A"
	elif rank >= 11:
		rank_text = ["J", "Q", "K"][rank - 11]
	return "%s\n%s" % [rank_text, ["C", "D", "H", "S"][card / 13]]

func begin(ordered_deck: Array[int] = []) -> void:
	deck = fresh_deck() if ordered_deck.is_empty() else ordered_deck.duplicate()
	player.clear()
	dealer.clear()
	result = ""
	active = true
	player.append(deck.pop_front())
	dealer.append(deck.pop_front())
	player.append(deck.pop_front())
	dealer.append(deck.pop_front())
	if natural(player) or natural(dealer):
		_decide()

func hit() -> void:
	if not active:
		return
	player.append(deck.pop_front())
	if total(player) > 21:
		result = "bust"
		active = false
	elif total(player) == 21:
		stand()

func stand() -> void:
	if not active:
		return
	while total(dealer) < 17:
		dealer.append(deck.pop_front())
	_decide()

func _decide() -> void:
	active = false
	var p := total(player)
	var d := total(dealer)
	if natural(dealer):
		result = "push" if natural(player) else "dealer_natural"
	elif natural(player):
		result = "natural"
	elif p > 21:
		result = "bust"
	elif d > 21 or p > d:
		result = "win"
	elif p == d:
		result = "push"
	else:
		result = "loss"

func payout(stake: int) -> int:
	if active:
		return 0
	match result:
		"natural": return floori(stake * 2.5)
		"win": return stake * 2
		"push": return stake
	return 0

func public_state() -> Dictionary:
	var visible_dealer: Array[int] = dealer.duplicate()
	if active:
		visible_dealer = [dealer[0], -1]
	return {
		"player": player.duplicate(), "dealer": visible_dealer,
		"player_total": total(player),
		"dealer_total": -1 if active else total(dealer),
		"active": active, "result": result,
	}
