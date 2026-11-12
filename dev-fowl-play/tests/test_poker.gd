extends Node

const Rules := preload("res://tables/poker/poker_rules.gd")
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

func c(rank: int, suit: int) -> int:   # rank 1 = Ace, 11 = J, 12 = Q, 13 = K
	return suit * 13 + rank - 1

func cat(cards: Array) -> int:
	return Rules.evaluate(cards).category

func _ready() -> void:
	await get_tree().process_frame
	_categories()
	_comparisons()
	_qualification()
	_payouts()
	_dealing()
	print("Poker: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _categories() -> void:
	check(cat([c(5, HEARTS), c(6, HEARTS), c(7, HEARTS)]) == Rules.Hand.STRAIGHT_FLUSH, "straight flush")
	check(cat([c(8, SPADES), c(8, HEARTS), c(8, DIAMONDS)]) == Rules.Hand.THREE_KIND, "three of a kind")
	check(cat([c(4, SPADES), c(5, HEARTS), c(6, DIAMONDS)]) == Rules.Hand.STRAIGHT, "straight")
	check(cat([c(2, CLUBS), c(7, CLUBS), c(13, CLUBS)]) == Rules.Hand.FLUSH, "flush")
	check(cat([c(12, SPADES), c(12, DIAMONDS), c(4, HEARTS)]) == Rules.Hand.PAIR, "pair")
	check(cat([c(1, SPADES), c(9, DIAMONDS), c(5, CLUBS)]) == Rules.Hand.HIGH_CARD, "high card")
	check(cat([c(1, SPADES), c(2, DIAMONDS), c(3, CLUBS)]) == Rules.Hand.STRAIGHT, "A-2-3 is a straight")
	check(cat([c(12, SPADES), c(13, DIAMONDS), c(1, CLUBS)]) == Rules.Hand.STRAIGHT, "Q-K-A is a straight")
	check(cat([c(13, SPADES), c(1, DIAMONDS), c(2, CLUBS)]) != Rules.Hand.STRAIGHT, "K-A-2 does not wrap")
	check(cat([c(1, HEARTS), c(2, HEARTS), c(3, HEARTS)]) == Rules.Hand.STRAIGHT_FLUSH, "A-2-3 suited")
	check(cat([c(9, CLUBS), c(3, CLUBS), c(9, DIAMONDS)]) == Rules.Hand.PAIR, "pair found in any order")

func _comparisons() -> void:
	var order: Array = [
		[c(9, SPADES), c(5, DIAMONDS), c(2, CLUBS)],      # high card
		[c(4, SPADES), c(4, DIAMONDS), c(2, CLUBS)],      # pair
		[c(2, CLUBS), c(7, CLUBS), c(13, CLUBS)],         # flush
		[c(4, SPADES), c(5, HEARTS), c(6, DIAMONDS)],     # straight
		[c(8, SPADES), c(8, HEARTS), c(8, DIAMONDS)],     # three of a kind
		[c(5, HEARTS), c(6, HEARTS), c(7, HEARTS)],       # straight flush
	]
	for i in range(1, order.size()):
		check(Rules.compare(Rules.evaluate(order[i]), Rules.evaluate(order[i - 1])) == 1, "category order %d" % i)
	var low: Array[int] = [c(1, SPADES), c(2, DIAMONDS), c(3, CLUBS)]
	var two_three_four: Array[int] = [c(2, SPADES), c(3, DIAMONDS), c(4, CLUBS)]
	check(Rules.compare(Rules.evaluate(low), Rules.evaluate(two_three_four)) == -1, "A-2-3 is the lowest straight")
	var pair_high_kicker: Array[int] = [c(9, SPADES), c(9, DIAMONDS), c(13, CLUBS)]
	var pair_low_kicker: Array[int] = [c(9, HEARTS), c(9, CLUBS), c(4, CLUBS)]
	check(Rules.compare(Rules.evaluate(pair_high_kicker), Rules.evaluate(pair_low_kicker)) == 1, "pair kicker breaks tie")
	var higher_pair: Array[int] = [c(10, SPADES), c(10, DIAMONDS), c(2, CLUBS)]
	check(Rules.compare(Rules.evaluate(higher_pair), Rules.evaluate(pair_high_kicker)) == 1, "pair rank before kicker")
	var tie_a: Array[int] = [c(13, SPADES), c(9, DIAMONDS), c(4, CLUBS)]
	var tie_b: Array[int] = [c(13, HEARTS), c(9, CLUBS), c(4, DIAMONDS)]
	check(Rules.compare(Rules.evaluate(tie_a), Rules.evaluate(tie_b)) == 0, "same ranks different suits tie")
	var flush_a: Array[int] = [c(13, CLUBS), c(9, CLUBS), c(4, CLUBS)]
	var flush_b: Array[int] = [c(13, HEARTS), c(8, HEARTS), c(7, HEARTS)]
	check(Rules.compare(Rules.evaluate(flush_a), Rules.evaluate(flush_b)) == 1, "flush compares high to low")
	for i in 1000:
		var rules := Rules.new()
		rules.deal(1)
		var a := Rules.evaluate(rules.hand_of(0))
		var b := Rules.evaluate(rules.dealer)
		check(Rules.compare(a, b) == -Rules.compare(b, a), "compare is symmetric %d" % i)

func _qualification() -> void:
	check(Rules.dealer_qualifies([c(12, SPADES), c(5, DIAMONDS), c(3, CLUBS)]), "Queen high qualifies")
	check(not Rules.dealer_qualifies([c(11, SPADES), c(10, DIAMONDS), c(8, CLUBS)]), "Jack high does not qualify")
	check(Rules.dealer_qualifies([c(2, SPADES), c(2, DIAMONDS), c(3, CLUBS)]), "any pair qualifies")
	check(Rules.dealer_qualifies([c(2, CLUBS), c(5, CLUBS), c(9, CLUBS)]), "any flush qualifies")
	check(Rules.dealer_qualifies([c(1, SPADES), c(2, DIAMONDS), c(3, CLUBS)]), "low straight qualifies")

func _payouts() -> void:
	var dealer_k: Array[int] = [c(13, SPADES), c(9, DIAMONDS), c(4, CLUBS)]
	var player_pair: Array[int] = [c(2, SPADES), c(2, DIAMONDS), c(7, CLUBS)]
	var player_weak: Array[int] = [c(10, HEARTS), c(7, CLUBS), c(3, DIAMONDS)]
	var player_tie: Array[int] = [c(13, HEARTS), c(9, CLUBS), c(4, DIAMONDS)]
	var win := Rules.settle(100, true, player_pair, dealer_k)
	check(win.result == "win" and win.total_return == 400 and win.net == 200, "normal win")
	var loss := Rules.settle(100, true, player_weak, dealer_k)
	check(loss.result == "loss" and loss.total_return == 0 and loss.net == -200, "normal loss")
	var tie := Rules.settle(100, true, player_tie, dealer_k)
	check(tie.result == "tie" and tie.total_return == 200 and tie.net == 0, "tie returns both stakes")
	var dealer_weak: Array[int] = [c(11, SPADES), c(7, DIAMONDS), c(3, CLUBS)]
	var no_q := Rules.settle(100, true, player_weak, dealer_weak)
	check(no_q.result == "dealer_no_qualify" and no_q.total_return == 300 and no_q.net == 100, "dealer does not qualify")
	var fold := Rules.settle(100, false, player_pair, dealer_k)
	check(fold.result == "fold" and fold.total_return == 0 and fold.net == -100, "fold loses Ante only")
	var dealer_sf: Array[int] = [c(9, SPADES), c(10, SPADES), c(11, SPADES)]
	var trips: Array[int] = [c(8, SPADES), c(8, HEARTS), c(8, DIAMONDS)]
	var trips_loss := Rules.settle(100, true, trips, dealer_sf)
	check(trips_loss.bonus == 400 and trips_loss.total_return == 400 and trips_loss.net == 200, "three of a kind bonus when dealer wins")
	var sf: Array[int] = [c(5, HEARTS), c(6, HEARTS), c(7, HEARTS)]
	var sf_loss := Rules.settle(100, true, sf, [c(10, SPADES), c(11, SPADES), c(12, SPADES)])
	check(sf_loss.bonus == 500 and sf_loss.total_return == 500 and sf_loss.net == 300, "straight flush bonus when dealer wins")
	var trips_win := Rules.settle(100, true, trips, dealer_k)
	check(trips_win.total_return == 800 and trips_win.net == 600, "bonus stacks with a normal win")
	var folded_trips := Rules.settle(100, false, trips, dealer_k)
	check(folded_trips.bonus == 0 and folded_trips.total_return == 0, "fold gets no bonus")
	check(Rules.settle(50, true, player_pair, dealer_k).total_return == 200, "payout scales with the Ante share")

func _dealing() -> void:
	check(Rules.valid_ante(Rules.MIN_ANTE) and Rules.valid_ante(Rules.MAX_ANTE), "ante limits are inclusive")
	check(not Rules.valid_ante(Rules.MIN_ANTE - 1) and not Rules.valid_ante(Rules.MAX_ANTE + 1), "ante outside limits rejected")
	check(Rules.total_ante(50, 3) == 150 and Rules.total_ante(100, 4) == 400, "total is per player times seats")
	var deck := Rules.fresh_deck()
	var unique := {}
	for card in deck:
		unique[card] = true
	check(unique.size() == 52 and deck.min() == 0 and deck.max() == 51, "full unique 52 card deck")
	var fixed := Rules.new()
	var ordered: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	fixed.deal(2, ordered)
	check(fixed.hand_of(0) == [0, 1, 2] and fixed.hand_of(1) == [3, 4, 5] and fixed.dealer == [6, 7, 8], "ordered deck deals seat by seat then dealer")
	for seats in range(Rules.MIN_SEATS, Rules.MAX_SEATS + 1):
		for i in 500:
			var r := Rules.new()
			r.deal(seats)
			var ids := {}
			var count := 0
			for s in seats:
				for card in r.hand_of(s):
					ids[card] = true
					count += 1
			for card in r.dealer:
				ids[card] = true
				count += 1
			for card in r.deck:
				ids[card] = true
				count += 1
			check(ids.size() == 52 and count == 52, "%d seat deal preserves the deck" % seats)
			check(r.deck.size() == 52 - 3 * (seats + 1), "remaining deck size for %d seats" % seats)
