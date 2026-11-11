extends TableBase
## Three Card Poker table: 1 to 4 seated players, each against the automated dealer.
## The host owns the deck, wallet and results. Clients get public snapshots, plus
## each player's own three cards over a private RPC.

const Rules := preload("res://tables/poker/poker_rules.gd")
const BUTTON_SCENE := preload("res://tables/press_button.tscn")
const SCREEN_SCENE := preload("res://tables/screen_3d.tscn")

enum Stage { WAITING, DECIDING, SETTLING }

const STAGE_NAMES := ["waiting", "deciding", "settling"]
const RESULT_TEXT := {"win": "WIN", "loss": "LOSS", "tie": "PUSH", "dealer_no_qualify": "WIN", "fold": "FOLDED"}
const COUNTER_SIZE := Vector3(5.0, 0.9, 1.6)   # wider than the base table: four seats plus the keypad
const KEYPAD_X := -2.2
const SEAT_PITCH := 0.8
const SEAT_Z := 1.55                           # where a seated player stands (table local)
const BOARD_Z := -0.66
const CARD_Z := -0.59
const LABEL_Z := -0.57

@export var seat_count := 4                    # lower to 2 for early playtests

var decision_seconds := Rules.DECISION_SECONDS # tests shorten these two
var result_seconds := 6.0
var test_deck: Array[int] = []                 # tests only: fixed deal order, seat by seat, then dealer

# ----- host only -----
var _rules := Rules.new()
var _stage := Stage.WAITING
var _occupant := {}                            # seat -> peer id standing in that seat's zone
var _arrival_order: Array[int] = []            # seats in the order they were taken
var _round_seats: Array[int] = []              # seats locked into the current round
var _seat_data := {}                           # seat -> per round record (cards, ante, action, result)
var _ante := 0                                 # per player Ante of the current round
var _deadline_ms := 0
var _dealer_text := ""

# ----- every machine -----
var _view := {}                                # latest public snapshot from the host
var _my_cards := {}                            # seat -> my own cards (private)
var _countdown_end := 0
var _last_secs := -1
var _zones: Array[Area3D] = []
var _name_labels: Array[Label3D] = []
var _state_labels: Array[Label3D] = []
var _dealer_label: Label3D
var _cards: Node3D
var _status: Screen3D

func _on_table_ready() -> void:
	seat_count = clampi(seat_count, Rules.MIN_SEATS, Rules.MAX_SEATS)
	_build_counter()
	_build_board()
	for s in seat_count:
		_build_seat(s)
	state_changed.connect(func(_b: int, _r: bool, _w: int) -> void: _update_status())
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.peer_connected.connect(func(_id: int) -> void: _publish())
	_on_table_reset()

# ---------- keypad limits: the keypad value is the Ante PER PLAYER ----------
func get_min_bet() -> int:
	return Rules.MIN_ANTE

func get_max_bet() -> int:
	return mini(Rules.MAX_ANTE, floori(GameState.wallet / float(maxi(_seated_count(), 1))))

func _seated_count() -> int:
	if multiplayer.is_server():
		return _occupant.size()
	var n := 0
	for entry in _view.get("seats", []):
		if entry.occupied:
			n += 1
	return n

# ---------- seats (host) ----------
func occupy(seat: int, id: int) -> void:
	if not multiplayer.is_server() or seat < 0 or seat >= seat_count:
		return
	_occupant[seat] = id
	if not _arrival_order.has(seat):
		_arrival_order.append(seat)
	_refresh_label()
	_publish()

func vacate(seat: int, id: int) -> void:
	if not multiplayer.is_server() or _occupant.get(seat, -1) != id:
		return
	_occupant.erase(seat)
	_arrival_order.erase(seat)
	_refresh_label()
	_publish()

func _ante_owner_seat() -> int:   # the first player who sat down and is still seated
	for s in _arrival_order:
		if _occupant.has(s):
			return s
	return -1

func _on_zone_entered(body: Node3D, seat: int) -> void:
	if body is CharacterBody3D:
		occupy(seat, str(body.name).to_int())

func _on_zone_exited(body: Node3D, seat: int) -> void:
	if body is CharacterBody3D:
		vacate(seat, str(body.name).to_int())

func _on_peer_left(id: int) -> void:
	if not multiplayer.is_server():
		return
	for s in seat_count:
		vacate(s, id)
	# A hand already dealt keeps its owner id. If it is undecided, the 15 second timer folds it.

# ---------- player input (runs on the player who pressed) ----------
func _on_seat_button(_v: int, seat: int, action: String) -> void:
	send_action(action, {"seat": seat, "seen_bet": bet})

# ---------- rules (host only) ----------
func _on_player_action(who: int, action: String, data: Dictionary) -> void:
	var raw_seat: Variant = data.get("seat", -1)
	if typeof(raw_seat) != TYPE_INT:
		return
	var seat: int = raw_seat
	if seat < 0 or seat >= seat_count:
		return
	if not running:
		if action == "confirm":
			var raw_bet: Variant = data.get("seen_bet", -1)
			_try_start(who, seat, raw_bet if typeof(raw_bet) == TYPE_INT else -1)
		return
	if _stage != Stage.DECIDING or not _seat_data.has(seat):
		return
	var d: Dictionary = _seat_data[seat]
	if d.id != who or d.confirmed:
		return
	match action:
		"fold", "play":
			d.selection = action
			_publish()
		"confirm":
			_confirm_decision(seat)

func _try_start(who: int, seat: int, seen_bet: int) -> void:
	if _occupant.get(seat, -1) != who:
		return
	if seat != _ante_owner_seat():
		_publish("THE FIRST SEATED PLAYER SETS THE ANTE")
		return
	if GameState.phase != GameState.Phase.DAY or not GameState.running:
		_publish("NO ACTIVE DAY")
		return
	if seen_bet != bet:
		_publish("THE ANTE CHANGED. CHECK IT AND PRESS OK AGAIN")
		return
	if not Rules.valid_ante(bet):
		_publish("ANTE MUST BE $%d TO $%d EACH" % [Rules.MIN_ANTE, Rules.MAX_ANTE])
		return
	var seats: Array[int] = []
	for s in seat_count:
		if _occupant.has(s) and Network.players.has(_occupant[s]):
			seats.append(s)
	if not seats.has(seat):
		return
	var total := Rules.total_ante(bet, seats.size())
	if not GameState.try_spend(total):
		_publish("THE WALLET CAN'T COVER $%d" % total)
		return
	_ante = bet
	locked_bet = total
	round_generation += 1
	_rules = Rules.new()
	_rules.deal(seats.size(), test_deck)
	test_deck = []
	_round_seats = seats
	_seat_data.clear()
	for i in seats.size():
		var s: int = seats[i]
		var id: int = _occupant[s]
		_seat_data[s] = {
			"id": id, "name": Network.player_name(id), "color": Network.player_color(id),
			"cards": _rules.hand_of(i), "ante": _ante, "play": 0,
			"selection": "", "confirmed": false, "action": "", "result": {}, "hand_name": "",
		}
	_stage = Stage.DECIDING
	_deadline_ms = Time.get_ticks_msec() + int(decision_seconds * 1000.0)
	_sync.rpc(true, total, who)   # the keypad now shows the committed total
	for s in seats:
		var d: Dictionary = _seat_data[s]
		_send_private(d.id, s, d.cards)
	_publish()
	_decision_timer(round_generation)

func _send_private(id: int, seat: int, cards: Array) -> void:
	if id == multiplayer.get_unique_id() or multiplayer.get_peers().has(id):
		_receive_hand.rpc_id(id, seat, cards)

func _confirm_decision(seat: int) -> void:
	var d: Dictionary = _seat_data[seat]
	if d.selection == "":
		_publish("PICK FOLD OR PLAY FIRST")
		return
	var msg := ""
	if d.selection == "play":
		if GameState.try_spend(d.ante):
			d.play = d.ante
			d.action = "play"
		else:
			d.action = "fold"
			msg = "%s CAN'T AFFORD THE PLAY BET AND FOLDS" % String(d.name).to_upper()
	else:
		d.action = "fold"
	d.confirmed = true
	if _all_confirmed():
		_reveal_and_settle()
	else:
		_publish(msg)

func _all_confirmed() -> bool:
	for s in _round_seats:
		var d: Dictionary = _seat_data[s]
		if not d.confirmed:
			return false
	return true

func _decision_timer(gen: int) -> void:
	await get_tree().create_timer(decision_seconds).timeout
	if gen == round_generation and running and _stage == Stage.DECIDING:
		_fold_undecided()

func _fold_undecided() -> void:
	for s in _round_seats:
		var d: Dictionary = _seat_data[s]
		if not d.confirmed:
			d.confirmed = true
			d.action = "fold"
	_reveal_and_settle()

func _reveal_and_settle() -> void:
	if _stage != Stage.DECIDING:
		return
	_stage = Stage.SETTLING
	var gen := round_generation
	var dealer_cards: Array[int] = _rules.dealer
	var qualifies := Rules.dealer_qualifies(dealer_cards)
	_dealer_text = "THE HOUSE: %s%s" % [Rules.hand_name(dealer_cards), "" if qualifies else " - NO QUALIFY"]
	var total_return := 0
	for s in _round_seats:
		var d: Dictionary = _seat_data[s]
		var cards: Array[int] = d.cards
		var res := Rules.settle(d.ante, d.action == "play", cards, dealer_cards)
		d.result = res
		d.hand_name = Rules.hand_name(cards)
		total_return += res.total_return
	# Pay and log first, so a day ending during the result display can't lose money.
	if total_return > 0:
		GameState.add_money(total_return)
	for s in _round_seats:
		var d: Dictionary = _seat_data[s]
		var res: Dictionary = d.result
		GameState.log_round(d.id, display_name, res.committed, res.total_return,
			{"note": _note(d)}, {"name": d.name, "color": d.color})
	_publish()
	await get_tree().create_timer(result_seconds).timeout
	if gen == round_generation and running:
		_unlock()

func _note(d: Dictionary) -> String:
	var res: Dictionary = d.result
	var hand := String(d.hand_name).to_lower()
	match res.result:
		"win":
			return "won with %s" % hand
		"dealer_no_qualify":
			return "collected with %s (dealer did not qualify)" % hand
		"tie":
			return "tied the dealer with %s" % hand
		"loss":
			return "lost with %s" % hand
	return "folded"

func _unlock() -> void:   # back to the waiting state
	round_generation += 1
	round_info = {}
	_bettor_identity = {}
	locked_bet = 0
	_seat_data.clear()
	_round_seats.clear()
	_stage = Stage.WAITING
	_ante = 0
	_dealer_text = ""
	_sync.rpc(false, 0, 0)
	_publish()

# Called by world.gd when the day ends or the lift leaves. Undecided seats fold, then the table frees up.
func settle_for_day() -> void:
	if not multiplayer.is_server() or not running:
		return
	if _stage == Stage.DECIDING:
		_fold_undecided()
	if _stage == Stage.SETTLING:
		_unlock()

func finish_round(_payout: int) -> void:
	# world.gd's forfeit path must go through poker rules, not the single bettor logging.
	settle_for_day()

func _on_table_reset() -> void:
	_rules = Rules.new()
	_stage = Stage.WAITING
	_seat_data.clear()
	_round_seats.clear()
	_ante = 0
	_dealer_text = ""
	_my_cards.clear()
	_view = {}
	_render()
	_update_status()
	if multiplayer.is_server():
		_publish()

# ---------- snapshots ----------
func _publish(msg := "") -> void:
	emit_event("view", _snapshot(msg))

func _snapshot(msg: String) -> Dictionary:
	var reveal := _stage == Stage.SETTLING
	var seats: Array = []
	var hands: Array = []
	var owner_seat := _ante_owner_seat()
	for s in seat_count:
		var entry := {"occupied": false, "playing": false, "name": "", "color": Color.WHITE, "text": "EMPTY"}
		var cards: Array = []
		if running:
			if _seat_data.has(s):
				var d: Dictionary = _seat_data[s]
				entry.occupied = true
				entry.playing = true
				entry.name = d.name
				entry.color = d.color
				entry.text = _seat_text(d)
				if reveal:
					cards = d.cards.duplicate()
		elif _occupant.has(s):
			var id: int = _occupant[s]
			entry.occupied = true
			entry.name = Network.player_name(id)
			entry.color = Network.player_color(id)
			entry.text = "PICK THE ANTE\nTHEN PRESS OK" if s == owner_seat else "SEATED"
		seats.append(entry)
		hands.append(cards)
	var left := 0.0
	if _stage == Stage.DECIDING:
		left = maxf((_deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
	return {
		"running": running, "stage": STAGE_NAMES[_stage], "ante": _ante,
		"seats": seats, "hands": hands,
		"dealer": _rules.dealer.duplicate() if reveal else [-1, -1, -1],
		"dealer_text": _dealer_text, "timer_left": left, "msg": msg,
	}

func _seat_text(d: Dictionary) -> String:
	var res: Dictionary = d.result
	if not res.is_empty():
		var net: int = res.net
		var first := "FOLDED" if res.result == "fold" else "%s: %s" % [d.hand_name, RESULT_TEXT[res.result]]
		return "%s\n%s$%d%s" % [first, "+" if net >= 0 else "-", absi(net), " (BONUS)" if res.bonus > 0 else ""]
	if d.confirmed:
		return "FOLDED" if d.action == "fold" else "PLAYING"
	match d.selection:
		"fold":
			return "FOLD? PRESS OK"
		"play":
			return "PLAY? PRESS OK"
	return "FOLD OR PLAY?"

@rpc("authority", "call_local", "reliable")
func _receive_hand(seat: int, cards: Array) -> void:   # only the owner is ever sent this
	_my_cards[seat] = cards
	_render()

func _on_event(event: String, data: Dictionary) -> void:
	if event != "view":
		return
	_view = data
	if not data.running:
		_my_cards.clear()
	if data.stage == "deciding":
		_countdown_end = Time.get_ticks_msec() + int(float(data.timer_left) * 1000.0)
	_last_secs = -1
	_refresh_label()   # the keypad caption depends on how many seats are taken
	_render()
	_update_status()

func _process(_delta: float) -> void:
	if _view.get("stage", "") != "deciding":
		return
	var secs := maxi(ceili((_countdown_end - Time.get_ticks_msec()) / 1000.0), 0)
	if secs != _last_secs:
		_last_secs = secs
		_update_status()

# ---------- drawing (every machine) ----------
func _update_status() -> void:
	if _status == null:
		return
	var stage: String = _view.get("stage", "waiting")
	var msg: String = _view.get("msg", "")
	var ante: int = _view.get("ante", 0)
	match stage:
		"deciding":
			var secs := maxi(ceili((_countdown_end - Time.get_ticks_msec()) / 1000.0), 0)
			_status.set_text("FOLD OR PLAY   %d" % secs,
				msg if msg != "" else "ANTE $%d EACH | PLAY COSTS $%d MORE" % [ante, ante])
		"settling":
			var house: String = _view.get("dealer_text", "")
			_status.set_text(house if house != "" else "THE HOUSE",
				msg if msg != "" else "RESULTS | NEXT HAND SOON")
		_:
			var seated := _seated_count()
			var big := ""
			var small := ""
			if seated == 0:
				big = "TAKE A SEAT"
				small = "THREE CARD POKER | 1 TO %d PLAYERS" % seat_count
			elif bet <= 0:
				big = "SET THE ANTE"
				small = "$%d TO $%d EACH | FIRST SEAT PRESSES OK" % [Rules.MIN_ANTE, Rules.MAX_ANTE]
			else:
				big = "ANTE $%d x %d = $%d" % [bet, seated, bet * seated]
				small = "FIRST SEAT PRESSES OK TO DEAL"
			_status.set_text(big, msg if msg != "" else small)

func _render() -> void:
	if _cards == null:
		return
	for card in _cards.get_children():
		_cards.remove_child(card)
		card.queue_free()
	var seats: Array = _view.get("seats", [])
	var hands: Array = _view.get("hands", [])
	var is_running: bool = _view.get("running", false)
	for s in seat_count:
		var entry: Dictionary = seats[s] if s < seats.size() else {}
		var occupied: bool = entry.get("occupied", false)
		var tint: Color = entry.get("color", Color.WHITE)
		_name_labels[s].text = String(entry.get("name", "")) if occupied else "SEAT %d" % (s + 1)
		_name_labels[s].modulate = tint if occupied else Color("f3dd9b")
		_state_labels[s].text = String(entry.get("text", "EMPTY"))
		if not is_running or not entry.get("playing", false):
			continue
		var shown: Array = [-1, -1, -1]   # backs, unless this is my seat or the reveal has happened
		if s < hands.size() and not (hands[s] as Array).is_empty():
			shown = hands[s]
		elif _my_cards.has(s):
			shown = _my_cards[s]
		_draw_hand(shown, _seat_x(s), 1.62, 0.25)
	var dealer_text: String = _view.get("dealer_text", "")
	_dealer_label.text = dealer_text if is_running and dealer_text != "" else "THE HOUSE"
	if is_running:
		_draw_hand(_view.get("dealer", [-1, -1, -1]), 0.0, 2.34, 0.3)

func _draw_hand(cards: Array, center_x: float, y: float, spacing: float) -> void:
	for i in cards.size():
		var card: int = cards[i]
		var x := center_x + (i - (cards.size() - 1) * 0.5) * spacing
		_box(Vector3(0.22, 0.34, 0.025), Vector3(x, y, CARD_Z),
			Color("b47637") if card < 0 else Color("fff3db"), _cards)
		var suit := Rules.suit_of(card) if card >= 0 else 0
		var red := card >= 0 and (suit == 1 or suit == 2)   # diamonds and hearts
		_label(Rules.card_text(card), Vector3(x, y, LABEL_Z), 36,
			Color("b52e36") if red else Color("17232b"), _cards)

# ---------- building (every machine builds the same nodes) ----------
func _seat_x(s: int) -> float:
	return (s - (seat_count - 1) / 2.0) * SEAT_PITCH

func _build_counter() -> void:
	var counter := $Counter as MeshInstance3D
	var mesh := BoxMesh.new()
	mesh.size = COUNTER_SIZE
	counter.mesh = mesh
	var counter_shape := $Counter/StaticBody3D/CollisionShape3D as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = COUNTER_SIZE
	counter_shape.shape = shape
	var keypad := $BetPanel as Node3D
	keypad.position.x = KEYPAD_X

func _build_board() -> void:
	_box(Vector3(5.0, 1.8, 0.06), Vector3(0, 2.0, BOARD_Z), Color("143e35"), self)
	for x in [-2.5, 2.5]:
		_box(Vector3(0.04, 1.85, 0.08), Vector3(x, 2.0, BOARD_Z + 0.01), Color("d8ac56"), self)
	_cards = Node3D.new()
	add_child(_cards)
	_dealer_label = _label("THE HOUSE", Vector3(0, 2.62, LABEL_Z), 32, Color("f3dd9b"), self)
	_status = SCREEN_SCENE.instantiate() as Screen3D
	_status.panel_size = Vector2(4.6, 0.55)
	_status.big_font_size = 48
	_status.caption_font_size = 22
	_status.text_color = Color(1, 0.9, 0.6)
	_status.glass = false
	_status.position = Vector3(0, 3.15, BOARD_Z)
	add_child(_status)

func _build_seat(s: int) -> void:
	var x := _seat_x(s)
	var defs := [
		["FOLD", "fold", Color(0.85, 0.2, 0.2), -1.0],
		["PLAY", "play", Color(0.2, 0.75, 0.3), 0.0],
		["OK", "confirm", Color(0.95, 0.75, 0.1), 1.0],
	]
	for def in defs:
		var b := BUTTON_SCENE.instantiate() as PressButton
		b.label_text = def[0]
		b.button_color = def[2]
		b.size = Vector3(0.22, 0.06, 0.2)
		b.position = Vector3(x + float(def[3]) * 0.25, 0.95, 0.5)
		b.pressed.connect(_on_seat_button.bind(s, def[1]))
		$Buttons.add_child(b)
	var zone := Area3D.new()
	zone.position = Vector3(x, 1.0, SEAT_Z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.76, 2.0, 0.9)
	shape.shape = box
	zone.add_child(shape)
	add_child(zone)
	zone.body_entered.connect(_on_zone_entered.bind(s))
	zone.body_exited.connect(_on_zone_exited.bind(s))
	_zones.append(zone)
	_box(Vector3(0.7, 0.01, 0.8), Vector3(x, 0.015, SEAT_Z), Color(0.35, 0.28, 0.1), self)   # floor mark
	_name_labels.append(_label("SEAT %d" % (s + 1), Vector3(x, 2.0, LABEL_Z), 28, Color("f3dd9b"), self))
	_state_labels.append(_label("EMPTY", Vector3(x, 1.25, LABEL_Z), 26, Color.WHITE, self))

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
