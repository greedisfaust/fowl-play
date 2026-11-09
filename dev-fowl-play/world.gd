extends Node3D

const PLAYER_SCENE := preload("res://player/player.tscn")
const JOIN_IP := "127.0.0.1"   # dev only: the join terminal will replace this

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_join_failed)
	multiplayer.server_disconnected.connect(_on_host_left)
	_spawn_player(1)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				_dev_host()
			KEY_J:
				_dev_join()
			KEY_K:
				_dev_teleport(true)
			KEY_L:
				_dev_teleport(false)

func _dev_host() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	var pos := _remove_solo()
	Network.host_game()
	_spawn_player(1, pos)

func _dev_join() -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		return
	var pos := _remove_solo()
	if not Network.join_game(JOIN_IP):
		_spawn_player(1, pos)

func _dev_teleport(to_casino: bool) -> void:
	var me := $Players.get_node_or_null(str(multiplayer.get_unique_id()))
	if me == null:
		return
	var spawn: Marker3D = $Casino/Spawn if to_casino else $Apartment/Spawn
	me.position = spawn.global_position + Vector3(randf_range(-1.0, 1.0), 0, 0)
	if to_casino:
		GameState.start_day()

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		var p := $Players.get_node_or_null(str(id))
		if p:
			p.queue_free()

func _on_join_failed() -> void:
	print("Could not join the host.")
	if $Players.get_child_count() == 0:
		_spawn_player(1)

func _on_host_left() -> void:
	print("The host left. Back to your own apartment.")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for p in $Players.get_children():
		$Players.remove_child(p)
		p.queue_free()
	Network.players = {1: 1}
	_spawn_player(1)

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
