extends Node

signal players_changed

const PORT := 7777
const MAX_CLIENTS := 3

var players := {1: 1}   # peer id -> slot number (1 to 4)

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func host_game() -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_warning("Could not host (error %d). Is another window already hosting?" % err)
		return false
	multiplayer.multiplayer_peer = peer
	players = {1: 1}
	players_changed.emit()
	return true

func join_game(ip: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_warning("Could not join (error %d)." % err)
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players[id] = _free_slot()
	_sync_players.rpc(players)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	_sync_players.rpc(players)

func _free_slot() -> int:
	var used := players.values()
	for s in range(1, MAX_CLIENTS + 2):
		if not used.has(s):
			return s
	return 0

@rpc("authority", "call_local", "reliable")
func _sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()

func player_name(id: int) -> String:
	if players.has(id):
		return "Player %d" % players[id]
	return "Player ?"
