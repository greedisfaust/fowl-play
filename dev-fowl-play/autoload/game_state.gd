extends Node

signal wallet_changed(new_value: int)
signal time_changed(seconds_left: int)
@warning_ignore("unused_signal")
signal round_started(player_id: int, table: String, bet: int)
signal day_ended
signal phase_changed
signal quota_changed(new_value: int)
signal day_result(outcome: int, finished_day: int)

enum Outcome { PASSED, EXTRA_LIFE_SPENT, GAME_OVER, WON }
enum Phase { REST, DAY }

# TEMP test values: replace with your economy numbers
const START_WALLET := 1000
const QUOTA := 1250
const DAY_LENGTH := 300.0
const MULTIPLIERS := [1.25, 1.28, 1.32, 1.36, 1.40, 1.45, 1.50, 1.55, 1.62, 1.70]
const FINAL_DAY := 10

var wallet: int = START_WALLET
var quota: int = QUOTA
var day: int = 1
var time_left: float = DAY_LENGTH
var running := false
var ledger: Array = []
var phase := Phase.REST
var extra_life := true
var day_start_wallet: int = START_WALLET

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

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_full_state.rpc_id(id, wallet, quota, day, time_left, running, extra_life)

@rpc("authority", "call_remote", "reliable")
func _full_state(w: int, q: int, d: int, t: float, r: bool, e: bool) -> void:
	wallet = w
	quota = q
	day = d
	time_left = t
	running = r
	extra_life = e
	wallet_changed.emit(wallet)
	quota_changed.emit(quota)
	time_changed.emit(ceili(time_left))

func start_day() -> void:
	if multiplayer.is_server():
		_begin_day.rpc()

@rpc("authority", "call_local", "reliable")
func _begin_day() -> void:
	phase = Phase.DAY
	day_start_wallet = wallet
	time_left = DAY_LENGTH
	running = true
	phase_changed.emit()
	wallet_changed.emit(wallet)
	time_changed.emit(ceili(time_left))

# ---------- day end (host decides, everyone mirrors) ----------
func _quota_for(for_day: int, basis: int) -> int:
	return roundi(basis * MULTIPLIERS[mini(for_day, FINAL_DAY) - 1])

func end_day() -> void:   # host only
	if not multiplayer.is_server():
		return
	if wallet >= quota:
		if day >= FINAL_DAY:
			_finish_day.rpc(Outcome.WON, 1, QUOTA, START_WALLET, true)   # TEMP: fresh run
		else:
			_finish_day.rpc(Outcome.PASSED, day + 1, _quota_for(day + 1, wallet), wallet, extra_life)
	elif extra_life:
		_finish_day.rpc(Outcome.EXTRA_LIFE_SPENT, day + 1, _quota_for(day + 1, day_start_wallet), floori(day_start_wallet / 2.0), false)
	else:
		_finish_day.rpc(Outcome.GAME_OVER, 1, QUOTA, START_WALLET, true)   # TEMP: fresh run

@rpc("authority", "call_local", "reliable")
func _finish_day(outcome: int, new_day: int, new_quota: int, new_wallet: int, new_extra: bool) -> void:
	var finished := day
	running = false
	phase = Phase.REST
	day = new_day
	quota = new_quota
	wallet = new_wallet
	extra_life = new_extra
	time_left = DAY_LENGTH
	wallet_changed.emit(wallet)
	quota_changed.emit(quota)
	time_changed.emit(ceili(time_left))
	phase_changed.emit()
	day_result.emit(outcome, finished)

# ---------- money ----------
func try_spend(amount: int) -> bool:
	if not multiplayer.is_server() or amount <= 0 or amount > wallet:
		return false
	_set_wallet.rpc(wallet - amount)
	return true

func add_money(amount: int) -> void:
	if multiplayer.is_server():
		_set_wallet.rpc(wallet + amount)

@rpc("authority", "call_local", "reliable")
func _set_wallet(v: int) -> void:
	wallet = v
	wallet_changed.emit(wallet)

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

func log_round(player_id: int, table: String, bet: int, payout: int) -> void:
	ledger.append({"day": day, "player": player_id, "table": table, "bet": bet, "payout": payout})
