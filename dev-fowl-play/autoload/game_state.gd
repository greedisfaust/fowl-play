extends Node

signal wallet_changed(new_value: int)
signal time_changed(seconds_left: int)
signal round_started(player_id: int, table: String, bet: int)
signal day_ended

# TEMP test values: replace with your economy numbers
const START_WALLET := 1000
const QUOTA := 1500
const DAY_LENGTH := 300.0

var wallet: int = START_WALLET
var quota: int = QUOTA
var day: int = 1
var time_left: float = DAY_LENGTH
var running := false
var ledger: Array = []

var max_bet_cap: int:
	get:
		return floori(quota * 0.5 / 10.0) * 10

var max_bet: int:
	get:
		return mini(max_bet_cap, wallet)

var min_bet: int:
	get:
		var from_cap := maxi(ceili(max_bet_cap * 0.1 / 10.0) * 10, 10)
		return mini(from_cap, wallet)

func start_day() -> void:
	time_left = DAY_LENGTH
	running = true
	wallet_changed.emit(wallet)
	time_changed.emit(ceili(time_left))

func _process(delta: float) -> void:
	if not running:
		return
	var old_sec := ceili(time_left)
	time_left = maxf(time_left - delta, 0.0)
	var new_sec := ceili(time_left)
	if new_sec != old_sec:
		time_changed.emit(new_sec)
	if time_left <= 0.0:
		running = false
		day_ended.emit()

func try_spend(amount: int) -> bool:
	if amount <= 0 or amount > wallet:
		return false
	wallet -= amount
	wallet_changed.emit(wallet)
	return true

func add_money(amount: int) -> void:
	wallet += amount
	wallet_changed.emit(wallet)

func log_round(player_id: int, table: String, bet: int, payout: int) -> void:
	ledger.append({"day": day, "player": player_id, "table": table, "bet": bet, "payout": payout})
