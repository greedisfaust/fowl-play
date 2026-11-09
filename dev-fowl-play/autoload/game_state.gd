extends Node

signal wallet_changed(new_value: int)
signal time_changed(seconds_left: int)
@warning_ignore("unused_signal")
signal round_started(player_id: int, table: String, bet: int)
signal day_ended
signal phase_changed

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
enum Phase { REST, DAY }
var phase := Phase.REST

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
		_full_state.rpc_id(id, wallet, quota, day, time_left, running)


@rpc("authority", "call_remote", "reliable")
func _full_state(w: int, q: int, d: int, t: float, r: bool) -> void:
	wallet = w
	quota = q
	day = d
	time_left = t
	running = r
	wallet_changed.emit(wallet)
	time_changed.emit(ceili(time_left))

func start_day() -> void:
	if multiplayer.is_server():
		_begin_day.rpc()

@rpc("authority", "call_local", "reliable")
func _begin_day() -> void:
	phase = Phase.DAY
	time_left = DAY_LENGTH
	running = true
	phase_changed.emit()
	wallet_changed.emit(wallet)
	time_changed.emit(ceili(time_left))
	

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
