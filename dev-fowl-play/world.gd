extends Node3D

const PLAYER_SCENE := preload("res://player/player.tscn")

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func() -> void: $HUD.announce("JOINED THE LOBBY"))
	multiplayer.connection_failed.connect(_on_join_failed)
	multiplayer.server_disconnected.connect(_on_host_left)
	Network.players_changed.connect(_show_my_nickname)
	Network.players_changed.connect(_refresh_board)

	var nick: TextTerminal = $Apartment/NicknameTerminal
	nick.submitted.connect(Network.set_my_nickname)
	var ip_term: TextTerminal = $Apartment/JoinTerminal
	ip_term.submitted.connect(_on_ip_submitted)
	ip_term.set_text(Network.last_ip)
	$Apartment/LobbyConsole.create_pressed.connect(_on_create_pressed)
	$Apartment/LobbyConsole.leave_pressed.connect(_on_leave_pressed)
	var door: DoorZone = $Apartment/DoorZone
	door.countdown_finished.connect(_on_countdown_finished)
	GameState.day_ended.connect(_on_day_ended)
	GameState.day_result.connect(_on_day_result)
	GameState.phase_changed.connect(_refresh_board)
	GameState.quota_changed.connect(func(_q: int) -> void: _refresh_board())
	GameState.wallet_changed.connect(func(_w: int) -> void: _refresh_board())
	door.count_changed.connect(_on_count_changed)
	
	_spawn_player(1)
	_show_my_nickname()
	_refresh_board()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_K:
				_dev_teleport_home()
			KEY_L:
				_dev_teleport_home()

# ---------- lobby buttons ----------
func _on_create_pressed() -> void:
	if Network.state != Network.State.SOLO:
		return
	var pos := _remove_solo()
	Network.host_game()
	_spawn_player(1, pos)

func _on_ip_submitted(ip: String) -> void:
	if Network.state != Network.State.SOLO:
		return
	var pos := _remove_solo()
	if Network.join_game(ip):
		$HUD.announce("CONNECTING...")
	else:
		_spawn_player(1, pos)

func _on_leave_pressed() -> void:
	if Network.state == Network.State.SOLO:
		return
	_go_solo()

func _on_join_failed() -> void:
	Network.last_error = "COULD NOT JOIN"
	$HUD.announce("COULD NOT JOIN")
	_go_solo()

func _on_host_left() -> void:
	Network.last_error = "THE HOST LEFT"
	$HUD.announce("THE HOST LEFT")
	_go_solo()

func _go_solo() -> void:
	for p in $Players.get_children():
		$Players.remove_child(p)
		p.queue_free()
	Network.leave()
	_spawn_player(1)

# ---------- players ----------
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := $Players.get_node_or_null(str(id))
		if p:
			p.queue_free()

func _remove_solo() -> Vector3:
	var old := $Players.get_node_or_null("1")
	if old == null:
		return Vector3.ZERO
	var pos: Vector3 = old.position
	$Players.remove_child(old)
	old.queue_free()
	return pos

func _spawn_player(id: int, pos := Vector3.ZERO) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	if pos == Vector3.ZERO:
		pos = $Apartment/Spawn.global_position + Vector3($Players.get_child_count() * 1.0, 0, 0)
	p.position = pos
	$Players.add_child(p, true)

# ---------- in-world screens ----------
func _show_my_nickname() -> void:
	var term: TextTerminal = $Apartment/NicknameTerminal
	if not term.is_typing():
		term.set_text(Network.player_name(multiplayer.get_unique_id()))

func _refresh_board() -> void:
	var lines := PackedStringArray()
	for slot in range(1, 5):
		var line := "%d  -" % slot
		for id in Network.players:
			if Network.players[id] == slot:
				line = "%d  %s" % [slot, Network.player_name(id)]
		lines.append(line)
	var life := "EXTRA LIFE: YES" if GameState.extra_life else "EXTRA LIFE: NO"
	$Apartment/PlayerBoard.set_text("\n".join(lines), "DAY %d   WALLET $%d\nQUOTA $%d   %s" % [GameState.day, GameState.wallet, GameState.quota, life])
	
func _on_countdown_finished() -> void:
	if not multiplayer.is_server():
		return
	$Apartment/DoorZone.enabled = false
	multiplayer.multiplayer_peer.refuse_new_connections = true
	for id in Network.players:
		var player = $Players.get_node_or_null(str(id))
		if player:
			var slot: int = Network.players[id]
			var dest: Vector3 = $Casino/Spawn.global_position + Vector3((slot - 2.5) * 1.0, 0, 0)
			player.teleport_to.rpc_id(id, dest)
	GameState.start_day()
	
func _on_day_ended() -> void:
	if not multiplayer.is_server():
		return
	# let any round in progress finish so its payout isn't lost
	while get_tree().get_nodes_in_group("tables").any(func(t: Node) -> bool: return t.running):
		await get_tree().create_timer(0.25).timeout
	GameState.end_day()
	_return_to_apartment()

func _return_to_apartment() -> void:
	for id in Network.players:
		var player = $Players.get_node_or_null(str(id))
		if player:
			var slot: int = Network.players[id]
			var dest: Vector3 = $Apartment/Spawn.global_position + Vector3((slot - 2.5) * 1.0, 0, 0)
			player.teleport_to.rpc_id(id, dest)
	$Apartment/DoorZone.enabled = true
	multiplayer.multiplayer_peer.refuse_new_connections = false

func _on_day_result(outcome: int, finished_day: int) -> void:
	match outcome:
		GameState.Outcome.PASSED:
			$HUD.announce("DAY %d COMPLETE! QUOTA MET" % finished_day)
		GameState.Outcome.EXTRA_LIFE_SPENT:
			$HUD.announce("QUOTA MISSED! EXTRA LIFE SPENT")
		GameState.Outcome.GAME_OVER:
			$HUD.announce("GAME OVER. THE HOUSE WINS")
		GameState.Outcome.WON:
			$HUD.announce("CONTRACT VOIDED! YOU WIN")

func _on_count_changed(s: int) -> void:
	if s > 0:
		$HUD.announce("STARTING IN %d..." % s)
	elif s == 0:
		$HUD.announce("HEADING OUT!")
	else:
		$HUD.announce("COUNTDOWN CANCELLED")

# ---------- dev only (L4 replaces these) ----------
func _dev_teleport_home() -> void:
	var me := $Players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null:
		return
	me.position = $Apartment/Spawn.global_position + Vector3(randf_range(-1.0, 1.0), 0, 0)
	if multiplayer.is_server():
		$Apartment/DoorZone.enabled = true
		GameState.phase = GameState.Phase.REST
		multiplayer.multiplayer_peer.refuse_new_connections = false
