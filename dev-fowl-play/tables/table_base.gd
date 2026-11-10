class_name TableBase
extends Node3D

signal state_changed(bet: int, running: bool, bettor_id: int)

@export var display_name := "Unnamed Table"
@export var only_bettor_can_act := true
@export var uses_play_button := true

var bet := 0            # pending bet, visible to everyone
var running := false    # is a round in progress?
var bettor_id := 0      # who pressed Play
var locked_bet := 0     # host only: what was charged at Play
var round_info := {}    # host only: a table fills this in for the day report

# ---------- HOOKS: tables override these ----------
func _on_table_ready() -> void: pass
func _on_round_start(_who: int, _total: int) -> void: pass                          # host only
func _on_player_action(_who: int, _action: String, _data: Dictionary) -> void: pass # host only
func _on_event(_event: String, _data: Dictionary) -> void: pass                     # every machine
func get_total_bet() -> int:
	return bet

func _ready() -> void:
	add_to_group("tables")
	$BetPanel.key_pressed.connect(_on_bet_key)
	if uses_play_button:
		$Buttons/PlayButton.pressed.connect(_on_play_pressed)
	else:
		$Buttons/PlayButton.queue_free()
	GameState.wallet_changed.connect(func(_w: int) -> void: _refresh_label())
	_refresh_label()
	_on_table_ready()

func _on_bet_key(op: String, arg: int) -> void:
	request_bet_input.rpc_id(1, op, arg)
	
func get_min_bet() -> int:
	return GameState.min_bet

# ---------- CALLS: tables use these ----------
func send_action(action: String, data: Dictionary = {}) -> void:
	_request_action.rpc_id(1, action, data)

func emit_event(event: String, data: Dictionary = {}) -> void:
	if multiplayer.is_server():
		_receive_event.rpc(event, data)

func finish_round(payout: int) -> void:
	if not multiplayer.is_server() or not running:
		return
	GameState.add_money(payout)
	GameState.log_round(bettor_id, display_name, locked_bet, payout, round_info)
	round_info = {}
	locked_bet = 0
	_sync.rpc(false, 0, 0)
	
func get_max_bet() -> int:
	return GameState.max_bet

#NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN

func _on_play_pressed(_value: int) -> void:
	request_play.rpc_id(1, get_total_bet())

@rpc("any_peer", "call_local", "reliable")
func request_bet_input(op: String, arg: int) -> void:
	if not multiplayer.is_server() or running:
		return
	var hi := get_max_bet()
	var new_bet := bet
	match op:
		"digit":
			new_bet = bet * 10 + arg
		"back":
			new_bet = floori(bet / 10.0)
		"clear":
			new_bet = 0
		"min", "quarter", "half", "max":
			new_bet = _preset(op, hi)
	_sync.rpc(running, mini(new_bet, hi), bettor_id)

func _preset(op: String, hi: int) -> int:
	var lo := get_min_bet()
	if hi < lo:
		return 0
	match op:
		"min":
			return lo
		"quarter":
			return clampi(floori(hi * 0.25 / 10.0) * 10, lo, hi)
		"half":
			return clampi(floori(hi * 0.5 / 10.0) * 10, lo, hi)
	return hi

#UNKNOWN CHECK THIS IF IT WORKS LOCAL
@rpc("any_peer", "call_local", "reliable")
func start_round(who: int, seen_bet: int) -> bool:   # host only
	if not multiplayer.is_server() or running:
		return false
	var total := get_total_bet()
	if total < maxi(get_min_bet(), 1) or total > get_max_bet() or seen_bet != total:		return false
	if not GameState.try_spend(total):
		return false
	locked_bet = total
	_sync.rpc(true, total, who)
	_on_round_start(who, total)
	return true

@rpc("any_peer", "call_local", "reliable")
func request_play(seen_bet: int) -> void:
	start_round(_sender(), seen_bet)

@rpc("any_peer", "call_local", "reliable")
func _request_action(action: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender()
	if running and only_bettor_can_act and who != bettor_id:
		return
	_on_player_action(who, action, data)

@rpc("authority", "call_local", "reliable")
func _receive_event(event: String, data: Dictionary) -> void:
	_on_event(event, data)

@rpc("authority", "call_local", "reliable")
func _sync(r: bool, b: int, who: int) -> void:
	var just_started := r and not running
	running = r
	bet = b
	bettor_id = who
	_refresh_label()
	state_changed.emit(bet, running, bettor_id)
	if just_started:
		GameState.round_started.emit(who, display_name, b)

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return 1 if id == 0 else id

func _refresh_label() -> void:
	$BetPanel.show_bet(bet, get_min_bet(), get_max_bet(), running)
