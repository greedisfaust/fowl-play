extends Node

const Rules := preload("res://tables/cluckjack/cluckjack_rules.gd")
const Table := preload("res://tables/cluckjack/cluckjack.tscn")
const Fixture := preload("res://tests/cluckjack_fixture.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _ready() -> void:
	await get_tree().process_frame
	_rules()
	await _integration()
	await _cross_regression()
	print("Cluckjack: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _rules() -> void:
	check(Rules.total([0, 13, 26]) == 13, "multiple aces downgrade")
	check(Rules.total([0, 5]) == 17, "soft 17")
	check(Rules.total([0, 13, 8]) == 21, "two aces with nine")
	check(Rules.total([10, 11, 12]) == 30, "all faces worth ten")
	check(not Rules.natural([0, 13, 8]), "three-card 21 is not natural")
	var h := Rules.new()
	h.begin([0, 8, 9, 5])
	check(h.result == "natural" and h.payout(100) == 250, "player natural 2.5x gross")
	check(h.payout(101) == 252, "odd natural rounds down")
	h.begin([0, 13, 9, 22])
	check(h.result == "push" and h.payout(100) == 100, "two naturals push")
	h.begin([9, 0, 6, 22])
	check(h.result == "dealer_natural" and h.payout(100) == 0, "dealer natural wins")
	h.begin([9, 0, 7, 5, 4])
	h.stand()
	check(h.dealer.size() == 2 and h.result == "win", "dealer stands on soft 17")
	h.begin([9, 22, 6, 5, 4])
	var public := h.public_state()
	check(public.dealer == [22, -1] and public.dealer_total == -1, "hole card and total hidden")
	check(not public.has("deck"), "deck never in public state")
	public.player.clear()
	check(h.player.size() == 2, "snapshot cannot mutate model")
	h.stand()
	check(h.dealer.size() == 3 and h.result == "loss", "dealer hits below 17")
	h.begin([9, 22, 6, 19])
	h.stand()
	check(h.result == "push" and h.payout(70) == 70, "ordinary tie returns stake")
	h.begin([9, 22, 6, 18, 35])
	h.stand()
	check(h.result == "win" and h.payout(70) == 140, "dealer bust pays 2x")
	h.begin([9, 22, 6, 18, 35])
	h.hit()
	check(h.result == "bust" and h.payout(70) == 0, "player bust loses stake")
	var used := h.deck.size()
	h.hit()
	h.stand()
	check(h.deck.size() == used, "resolved hand ignores repeated actions")
	h.begin([9, 8, 4, 5, 18, 3])
	h.hit()
	check(not h.active and Rules.total(h.player) == 21 and h.result == "win", "drawn 21 auto-stands and pays ordinary win")
	var deck := Rules.fresh_deck()
	var unique := {}
	for card in deck:
		unique[card] = true
	check(unique.size() == 52 and deck.min() == 0 and deck.max() == 51, "full unique 52-card deck")
	for i in 2000:
		h.begin()
		while h.active:
			if Rules.total(h.player) < 17:
				h.hit()
			else:
				h.stand()
		var dealt := h.player + h.dealer + h.deck
		var ids := {}
		for card in dealt:
			ids[card] = true
		check(ids.size() == 52 and dealt.size() == 52, "random hand %d preserves deck" % i)

func _integration() -> void:
	GameState.reset_run()
	var t := Table.instantiate()
	t.set_script(Fixture)
	t.display_name = "Cluckjack"
	add_child(t)
	t.request_bet_input("min", 0)
	check(not t.start_round(1, t.bet) and GameState.wallet == 1000, "REST rejects spending")
	GameState.start_day()
	t.request_bet_input("clear", 0)
	check(not t.start_round(1, 0), "zero bet rejected")
	t.request_bet_input("min", 0)
	var stake: int = t.bet
	t.request_bet_input("digit", -2)
	check(t.bet == stake, "invalid digit rejected")
	check(not t.start_round(9876, stake), "unknown bettor rejected")
	check(not t.start_round(1, stake + 1), "stale displayed bet rejected")
	check(t.start_round(1, stake), "valid deal accepted")
	check(GameState.wallet == 1000 - stake, "stake deducted once")
	check(not t.start_round(1, stake), "duplicate play rejected")
	check(t._public.dealer == [22, -1], "table broadcast hides hole card")
	var revision: int = t._view_revision
	t._request_action("hit", {"revision": revision - 1})
	check(t.hand.player.size() == 2, "stale action token rejected")
	t._request_action("invalid", {"revision": revision})
	check(t.running, "unknown action ignored")
	t._request_action("stand", {"revision": revision})
	check(not t.running and GameState.wallet == 1000 + stake, "table settlement returns gross payout")
	check(GameState.ledger.size() == 1 and GameState.ledger[0].table == "Cluckjack", "ledger records one named round")
	t._request_action("stand", {"revision": revision})
	t.finish_round(stake * 2)
	check(GameState.ledger.size() == 1 and GameState.wallet == 1000 + stake, "duplicate settlement cannot pay twice")
	t.request_bet_input("min", 0)
	t.start_round(1, t.bet)
	GameState.running = false
	t.settle_for_day()
	check(not t.running and GameState.ledger.size() == 2, "timeout auto-stands and logs")
	t.request_bet_input("min", 0)
	check(not t.start_round(1, t.bet), "expired day rejects new hands")
	GameState.running = true
	Network.names[1] = "Departing Hen"
	t.start_round(1, t.bet)
	Network.names.erase(1)
	t._on_bettor_left(1)
	check(not t.running and GameState.ledger.size() == 3, "bettor disconnect settles")
	check(GameState.ledger[-1].name == "Departing Hen", "departed bettor keeps report attribution")
	t.request_bet_input("min", 0)
	t.start_round(1, t.bet)
	GameState.reset_run()
	check(not t.running and not t.hand.active and t.bet == 0, "reset clears table and model")
	t.settle_for_day()
	check(GameState.wallet == 1000 and GameState.ledger.is_empty(), "old hand cannot pay into fresh run")
	t.queue_free()
	await get_tree().process_frame

func _cross_regression() -> void:
	GameState.reset_run()
	GameState.start_day()
	var cross := preload("res://tables/chicken_cross/chicken_cross.tscn").instantiate()
	add_child(cross)
	cross.request_bet_input("min", 0)
	var stake: int = cross.bet
	cross.start_round(1, stake)
	cross.lane = 1 # known successful lane: verify existing cash-out transaction
	cross._request_action("cash_out", {})
	await get_tree().create_timer(1.1).timeout
	check(not cross.running and GameState.wallet == 1000 - stake + roundi(stake * 1.3), "Chicken Cross cash-out still settles")
	cross.request_bet_input("min", 0)
	cross.start_round(1, cross.bet)
	cross.lane = 1
	cross._request_action("cash_out", {})
	GameState.reset_run()
	await get_tree().create_timer(1.1).timeout
	check(GameState.wallet == 1000 and GameState.ledger.is_empty() and not cross.running, "pending Cross payout cannot survive reset")
	cross.queue_free()
	await get_tree().process_frame
