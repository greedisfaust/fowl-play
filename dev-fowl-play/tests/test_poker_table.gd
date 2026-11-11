extends Node
## Host-side lifecycle checks for tables/poker/poker.tscn (offline peer, fake seat owners).

const Table := preload("res://tables/poker/poker.tscn")
const CLUBS := 0
const DIAMONDS := 1
const HEARTS := 2
const SPADES := 3
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func c(rank: int, suit: int) -> int:
	return suit * 13 + rank - 1

func _ready() -> void:
	await get_tree().process_frame
	Network.players = {1: 1, 2: 2, 3: 3, 4: 4}
	await _full_round()
	await _edge_cases()
	await _timer_fold()
	Network.players = {1: 1}
	print("Poker table: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _new_table() -> Node:
	GameState.reset_run()
	GameState.start_day()
	var t := Table.instantiate()
	add_child(t)
	return t

func _full_round() -> void:
	var t := _new_table()
	t.occupy(0, 1)
	t.occupy(1, 2)
	t.request_bet_input("min", 0)
	var stake: int = t.bet
	check(stake == 50, "min keypad value is the per player ante")
	t._on_player_action(2, "confirm", {"seat": 1, "seen_bet": stake})
	check(not t.running and GameState.wallet == 1000, "only the first seated player can start")
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": stake + 10})
	check(not t.running, "stale ante rejected")
	t._on_player_action(1, "confirm", {"seat": "0", "seen_bet": stake})
	check(not t.running, "malformed seat ignored")
	var deck: Array[int] = [c(8, SPADES), c(8, HEARTS), c(8, DIAMONDS),
		c(10, HEARTS), c(7, CLUBS), c(3, DIAMONDS),
		c(13, SPADES), c(9, DIAMONDS), c(4, CLUBS)]
	t.test_deck = deck
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": stake})
	check(t.running and GameState.wallet == 900 and t.bet == 100, "ante charged once per seat")
	check(t._my_cards.has(0) and not t._my_cards.has(1), "host only receives its own cards")
	check(t._view.dealer == [-1, -1, -1] and t._view.hands[0].is_empty(), "nothing public before reveal")
	t._on_player_action(2, "play", {"seat": 0})
	check(t._seat_data[0].selection == "", "cannot control another seat")
	t._on_player_action(1, "confirm", {"seat": 0})
	check(not t._seat_data[0].confirmed, "confirm needs a selection")
	t._on_player_action(1, "play", {"seat": 0})
	t._on_player_action(1, "confirm", {"seat": 0})
	check(GameState.wallet == 850, "play bet charged on confirm")
	t._on_player_action(1, "confirm", {"seat": 0})
	check(GameState.wallet == 850 and t.running, "duplicate confirm ignored, round waits for seat 2")
	t._on_player_action(2, "fold", {"seat": 1})
	t._on_player_action(2, "confirm", {"seat": 1})
	check(GameState.wallet == 1250, "three of a kind: 4x regular plus 4x bonus pays 400")
	check(GameState.ledger.size() == 2 and GameState.ledger[0].bet == 100 and GameState.ledger[0].payout == 400
		and GameState.ledger[1].bet == 50 and GameState.ledger[1].payout == 0, "one ledger entry per seat")
	check(t._view.stage == "settling" and t._view.hands[1].size() == 3, "cards revealed for the result display")
	t.settle_for_day()
	check(not t.running and t._view.stage == "waiting", "day end unlocks the table")
	t.settle_for_day()
	t.finish_round(999)
	check(GameState.wallet == 1250 and GameState.ledger.size() == 2, "no double payout")
	# next hand: day ends while undecided
	t.request_bet_input("min", 0)
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": t.bet})
	check(t.running and GameState.wallet == 1150, "second hand dealt")
	t._on_player_action(1, "play", {"seat": 0})
	t.settle_for_day()
	check(not t.running and GameState.wallet == 1150 and GameState.ledger.size() == 4, "undecided seats fold at day end")
	t.queue_free()
	await get_tree().process_frame

func _edge_cases() -> void:
	var t := _new_table()
	t.occupy(0, 1)
	t.occupy(1, 2)
	t.request_bet_input("min", 0)
	GameState.wallet = 120
	t.request_bet_input("min", 0)
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": t.bet})
	check(t.running and GameState.wallet == 20, "ante charged from a small wallet")
	t._on_player_action(1, "play", {"seat": 0})
	t._on_player_action(1, "confirm", {"seat": 0})
	check(t._seat_data[0].action == "fold" and GameState.wallet == 20, "unaffordable play bet forces a fold")
	t.settle_for_day()
	check(not t.running, "table unlocked after forced fold round")
	t.occupy(2, 3)
	t.occupy(3, 4)
	GameState.wallet = 1000
	check(t.get_max_bet() == 100, "max ante capped at the limit")
	GameState.wallet = 300
	check(t.get_max_bet() == 75, "max ante shrinks with four seats")
	t._on_peer_left(4)
	check(t.get_max_bet() == 100, "disconnect vacates the seat")
	GameState.reset_run()
	t.request_bet_input("min", 0)
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": t.bet})
	check(not t.running, "no round outside an active day")
	GameState.start_day()
	t.request_bet_input("min", 0)
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": t.bet})
	check(t.running, "round starts in an active day")
	GameState.reset_run()
	check(not t.running and t._seat_data.is_empty() and t.bet == 0, "reset clears the round")
	t.settle_for_day()
	check(GameState.wallet == 1000 and GameState.ledger.is_empty(), "old round cannot pay into a fresh run")
	t.queue_free()
	await get_tree().process_frame

func _timer_fold() -> void:
	var t := _new_table()
	t.decision_seconds = 0.3
	t.result_seconds = 0.2
	t.occupy(0, 1)
	t.request_bet_input("min", 0)
	t._on_player_action(1, "confirm", {"seat": 0, "seen_bet": t.bet})
	check(t.running and GameState.wallet == 950, "single seat round dealt")
	await get_tree().create_timer(1.0).timeout
	check(not t.running and GameState.wallet == 950 and GameState.ledger.size() == 1, "timer folds and unlocks")
	t.queue_free()
	await get_tree().process_frame
