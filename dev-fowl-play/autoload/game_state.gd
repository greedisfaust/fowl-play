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
var wallet_history: Array = []   # [seconds into the day, wallet]
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
	wallet_history = [[0.0, wallet]]
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
	match preview_outcome():
		Outcome.WON:
			_finish_day.rpc(Outcome.WON, 1, QUOTA, START_WALLET, true)
		Outcome.PASSED:
			_finish_day.rpc(Outcome.PASSED, day + 1, _quota_for(day + 1, wallet), wallet, extra_life)
		Outcome.EXTRA_LIFE_SPENT:
			_finish_day.rpc(Outcome.EXTRA_LIFE_SPENT, day + 1, _quota_for(day + 1, day_start_wallet), floori(day_start_wallet / 2.0), false)
		_:
			_finish_day.rpc(Outcome.GAME_OVER, 1, QUOTA, START_WALLET, true)

@rpc("authority", "call_local", "reliable")
func _finish_day(outcome: int, new_day: int, new_quota: int, new_wallet: int, new_extra: bool) -> void:
	if outcome == Outcome.GAME_OVER or outcome == Outcome.WON:
		ledger.clear()   # the next run starts with a clean ledger
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

func preview_outcome() -> int:   # host only: what end_day() will decide, without applying it
	if wallet >= quota:
		return Outcome.WON if day >= FINAL_DAY else Outcome.PASSED
	return Outcome.EXTRA_LIFE_SPENT if extra_life else Outcome.GAME_OVER

func reset_run() -> void:   # local only: a fresh run (used when a player drops to solo)
	running = false
	phase = Phase.REST
	day = 1
	quota = QUOTA
	wallet = START_WALLET
	extra_life = true
	day_start_wallet = START_WALLET
	time_left = DAY_LENGTH
	ledger.clear()
	wallet_history.clear()
	wallet_changed.emit(wallet)
	quota_changed.emit(quota)
	time_changed.emit(ceili(time_left))
	phase_changed.emit()

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
	if phase == Phase.DAY:
		wallet_history.append([day_elapsed(), v])
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

func log_round(player_id: int, table: String, bet: int, payout: int, info := {}) -> void:
	ledger.append({
		"day": day, "t": day_elapsed(), "player": player_id,
		"name": Network.player_name(player_id), "color": Network.player_color(player_id),
		"table": table, "bet": bet, "payout": payout, "info": info,
	})

func day_elapsed() -> float:
	return DAY_LENGTH - time_left
	
func day_summary() -> Dictionary:   # host only: everything the Day Report shows
	var rounds: Array = []
	for e in ledger:
		if e.day == day:
			rounds.append(e)
	var net := {}
	var colors := {}
	var events: Array = []
	var notes: Array = []
	var worst := {}
	var best := {}
	var unlucky := {}
	var greedy := {}
	for e in rounds:
		var gain: int = e.payout - e.bet
		net[e.name] = net.get(e.name, 0) + gain
		colors[e.name] = e.color
		events.append({"t": e.t, "name": e.name, "gain": gain, "table": e.table, "color": e.color})
		if gain < 0 and (worst.is_empty() or gain < worst.gain):
			worst = {"name": e.name, "gain": gain, "table": e.table, "color": e.color}
		if gain > 0 and (best.is_empty() or gain > best.gain):
			best = {"name": e.name, "gain": gain, "table": e.table, "color": e.color}
		var info: Dictionary = e.info
		if info.get("bust", false) and info.has("chance") and info.has("depth") \
				and (unlucky.is_empty() or info.chance < unlucky.chance):
			unlucky = {"name": e.name, "depth": info.depth, "chance": info.chance, "table": e.table, "color": e.color}
		if info.has("depth") and (greedy.is_empty() or info.depth > greedy.depth):
			greedy = {"name": e.name, "depth": info.depth, "bust": info.get("bust", false), "table": e.table, "color": e.color}
		if info.has("note"):
			notes.append({"name": e.name, "note": info.note, "table": e.table, "color": e.color})
	var liability := {}
	var lucky := {}
	for n in net:
		if net[n] < 0 and (liability.is_empty() or net[n] < liability.gain):
			liability = {"name": n, "gain": net[n], "color": colors[n]}
		if net[n] > 0 and (lucky.is_empty() or net[n] > lucky.gain):
			lucky = {"name": n, "gain": net[n], "color": colors[n]}
	return {
		"day": day, "quota": quota, "wallet": wallet, "start_wallet": day_start_wallet,
		"rounds": rounds.size(), "events": events, "notes": notes,
		"worst": worst, "best": best, "unlucky": unlucky, "greedy": greedy,
		"liability": liability, "lucky": lucky,
	}
