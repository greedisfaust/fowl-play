class_name PokerRules
extends RefCounted
## Host-only Three Card Poker model. No UI, no wallet, no networking.
## Card IDs 0..51: suit * 13 + rank - 1 (same layout as cluckjack_rules.gd).
## Suits: 0 = clubs, 1 = diamonds, 2 = hearts, 3 = spades. Rank 1 = Ace.

# ---------- configuration (tune after playtesting) ----------
const MIN_SEATS := 1
const MAX_SEATS := 4
const MIN_ANTE := 50                # per player, in game dollars
const MAX_ANTE := 100               # per player
const DECISION_SECONDS := 15.0      # auto fold after this long
const BONUS_STRAIGHT_FLUSH := 5     # winnings ratio, on the Ante share
const BONUS_THREE_KIND := 4
const DEALER_MIN_HIGH := 12         # Queen high or better qualifies

# Higher number = stronger hand.
enum Hand { HIGH_CARD, PAIR, FLUSH, STRAIGHT, THREE_KIND, STRAIGHT_FLUSH }
const HAND_NAMES := {
	Hand.HIGH_CARD: "HIGH CARD", Hand.PAIR: "PAIR", Hand.FLUSH: "FLUSH",
	Hand.STRAIGHT: "STRAIGHT", Hand.THREE_KIND: "THREE OF A KIND",
	Hand.STRAIGHT_FLUSH: "STRAIGHT FLUSH",
}

var deck: Array[int] = []
var hands: Array = []               # one Array[int] of 3 cards per seat
var dealer: Array[int] = []

# ---------- cards ----------
static func fresh_deck() -> Array[int]:
	var cards: Array[int] = []
	for card in 52:
		cards.append(card)
	cards.shuffle()
	return cards

static func rank_value(card: int) -> int:
	var rank := card % 13 + 1
	return 14 if rank == 1 else rank   # Ace is high by default

static func suit_of(card: int) -> int:
	return floori(card / 13.0)

static func card_text(card: int) -> String:
	if card < 0:
		return "?"
	var rank := card % 13 + 1
	var rank_text := str(rank)
	if rank == 1:
		rank_text = "A"
	elif rank >= 11:
		rank_text = ["J", "Q", "K"][rank - 11]
	return "%s\n%s" % [rank_text, ["C", "D", "H", "S"][suit_of(card)]]

# ---------- hand evaluation ----------
## Returns {"category": Hand, "tiebreak": Array[int]} (tiebreak is compared left to right).
static func evaluate(cards: Array) -> Dictionary:
	var v: Array[int] = []
	for card in cards:
		v.append(rank_value(card))
	v.sort()
	v.reverse()   # highest first
	var flush := suit_of(cards[0]) == suit_of(cards[1]) and suit_of(cards[1]) == suit_of(cards[2])
	var straight := false
	var high := v[0]
	if v[0] - 1 == v[1] and v[1] - 1 == v[2]:
		straight = true
	elif v[0] == 14 and v[1] == 3 and v[2] == 2:   # A-2-3 is the lowest straight
		straight = true
		high = 3
	if straight and flush:
		return {"category": Hand.STRAIGHT_FLUSH, "tiebreak": [high]}
	if v[0] == v[1] and v[1] == v[2]:
		return {"category": Hand.THREE_KIND, "tiebreak": [v[0]]}
	if straight:
		return {"category": Hand.STRAIGHT, "tiebreak": [high]}
	if flush:
		return {"category": Hand.FLUSH, "tiebreak": v}
	if v[0] == v[1]:
		return {"category": Hand.PAIR, "tiebreak": [v[0], v[2]]}
	if v[1] == v[2]:
		return {"category": Hand.PAIR, "tiebreak": [v[1], v[0]]}
	return {"category": Hand.HIGH_CARD, "tiebreak": v}

## 1 if a beats b, -1 if b beats a, 0 for a tie.
static func compare(a: Dictionary, b: Dictionary) -> int:
	if a.category != b.category:
		return 1 if a.category > b.category else -1
	var ta: Array = a.tiebreak
	var tb: Array = b.tiebreak
	for i in ta.size():
		if ta[i] != tb[i]:
			return 1 if ta[i] > tb[i] else -1
	return 0

static func dealer_qualifies(cards: Array) -> bool:
	var e := evaluate(cards)
	if e.category != Hand.HIGH_CARD:
		return true
	return e.tiebreak[0] >= DEALER_MIN_HIGH

static func hand_name(cards: Array) -> String:
	return HAND_NAMES[evaluate(cards).category]

# ---------- ante helpers ----------
static func valid_ante(per_player: int) -> bool:
	return per_player >= MIN_ANTE and per_player <= MAX_ANTE

static func total_ante(per_player: int, seats: int) -> int:
	return per_player * seats

# ---------- settlement (one seat) ----------
## Gross returns include the stake, like Cluckjack. committed = Ante, plus Play if played.
## result: "fold", "win", "loss", "tie", "dealer_no_qualify".
static func settle(ante: int, played: bool, player: Array, dealer_cards: Array) -> Dictionary:
	if not played:
		return {"result": "fold", "regular": 0, "bonus": 0, "total_return": 0,
			"committed": ante, "net": -ante}
	var committed := ante * 2
	var p := evaluate(player)
	var bonus := 0
	if p.category == Hand.STRAIGHT_FLUSH:
		bonus = ante * BONUS_STRAIGHT_FLUSH
	elif p.category == Hand.THREE_KIND:
		bonus = ante * BONUS_THREE_KIND
	var result := ""
	var regular := 0
	if not dealer_qualifies(dealer_cards):
		result = "dealer_no_qualify"
		regular = ante * 3   # Ante 2x, Play returned
	else:
		var cmp := compare(p, evaluate(dealer_cards))
		if cmp > 0:
			result = "win"
			regular = ante * 4   # Ante and Play both pay 1:1
		elif cmp == 0:
			result = "tie"
			regular = ante * 2   # both stakes returned
		else:
			result = "loss"
	var total := regular + bonus
	return {"result": result, "regular": regular, "bonus": bonus,
		"total_return": total, "committed": committed, "net": total - committed}

# ---------- dealing ----------
func deal(seat_count: int, ordered_deck: Array[int] = []) -> void:
	deck = fresh_deck() if ordered_deck.is_empty() else ordered_deck.duplicate()
	hands.clear()
	dealer.clear()
	for s in seat_count:
		var h: Array[int] = []
		for i in 3:
			h.append(deck.pop_front())
		hands.append(h)
	for i in 3:
		dealer.append(deck.pop_front())

func hand_of(seat: int) -> Array[int]:
	return hands[seat]
