extends Node

signal players_changed
signal state_changed

enum State { SOLO, HOSTING, JOINING, JOINED }

const PORT := 7777
const MAX_CLIENTS := 3
const MAX_NAME := 12
const SETTINGS_PATH := "user://settings.cfg"

var state := State.SOLO
var players := {1: 1}   # peer id -> slot number (1 to 4)
var names := {}         # peer id -> nickname
var my_nickname := ""
var last_ip := ""
var last_error := ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	_load_settings()
	_send_my_name.call_deferred()

func _set_state(s: State) -> void:
	state = s
	state_changed.emit()

# ---------- connecting ----------
func host_game() -> bool:
	last_error = ""
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		last_error = "COULD NOT HOST\nIS ANOTHER GAME OPEN?"
		state_changed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	reset_roster()
	_set_state(State.HOSTING)
	return true

func join_game(ip: String) -> bool:
	last_error = ""
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		last_error = "THAT IS NOT\nAN IP ADDRESS"
		state_changed.emit()
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		last_error = "COULD NOT JOIN"
		state_changed.emit()
		return false
	multiplayer.multiplayer_peer = peer
	last_ip = ip
	_save_value("network", "last_ip", ip)
	_set_state(State.JOINING)
	return true

func leave() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	reset_roster()
	_set_state(State.SOLO)

func _on_connected() -> void:
	_set_state(State.JOINED)
	_send_my_name()

func local_ip() -> String:
	var addrs := IP.get_local_addresses()
	for a in addrs:
		if a.begins_with("192.168."):
			return a
	for a in addrs:
		if a.begins_with("10."):
			return a
	for a in addrs:
		if a.begins_with("172."):
			var second := int(a.split(".")[1])
			if second >= 16 and second <= 31:
				return a
	return "?"

# ---------- roster (host-owned, everyone mirrors) ----------
func reset_roster() -> void:
	players = {1: 1}
	names = {}
	players_changed.emit()
	_send_my_name()

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players[id] = _free_slot()
	_sync_roster.rpc(players, names)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	names.erase(id)
	_sync_roster.rpc(players, names)

func _free_slot() -> int:
	var used := players.values()
	for s in range(1, MAX_CLIENTS + 2):
		if not used.has(s):
			return s
	return 0

@rpc("authority", "call_local", "reliable")
func _sync_roster(p: Dictionary, n: Dictionary) -> void:
	players = p
	names = n
	players_changed.emit()

# ---------- nicknames ----------
func set_my_nickname(n: String) -> void:
	my_nickname = _clean(n)
	_save_value("player", "nickname", my_nickname)
	_send_my_name()

func _send_my_name() -> void:
	if my_nickname != "":
		request_set_name.rpc_id(1, my_nickname)

@rpc("any_peer", "call_local", "reliable")
func request_set_name(n: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	var clean := _clean(n)
	if clean == "":
		return
	names[id] = _unique(clean, id)
	_sync_roster.rpc(players, names)

func _clean(n: String) -> String:
	return n.strip_edges().left(MAX_NAME)

func _unique(base: String, id: int) -> String:
	var candidate := base
	var n := 2
	while _name_taken(candidate, id):
		candidate = "%s%d" % [base.left(MAX_NAME - 2), n]
		n += 1
	return candidate

func _name_taken(candidate: String, id: int) -> bool:
	for other in names:
		if other != id and String(names[other]).to_lower() == candidate.to_lower():
			return true
	return false

func player_name(id: int) -> String:
	if names.has(id):
		return names[id]
	if players.has(id):
		return "Player %d" % players[id]
	return "Player ?"

# ---------- saved settings ----------
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		my_nickname = cfg.get_value("player", "nickname", "")
		last_ip = cfg.get_value("network", "last_ip", "")

func _save_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS_PATH)
