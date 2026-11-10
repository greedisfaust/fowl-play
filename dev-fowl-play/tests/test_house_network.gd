extends Node
## Full-world ENet check, including dynamic dressing and late prop snapshots.
const Prop := preload("res://interaction/physics_prop.gd")
var world: Node3D
var a: PhysicsProp
var b: PhysicsProp
var _host := false
var _awaiting_disconnect := false

func make_prop(label: String, pos: Vector3) -> PhysicsProp:
	var prop := Prop.new()
	prop.name = label
	prop.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.25
	collision.shape = shape
	prop.add_child(collision)
	world.add_child(prop)
	return prop

func _ready() -> void:
	world = preload("res://world.tscn").instantiate()
	world.name = "World"
	add_child(world)
	a = make_prop("TestPropA", Vector3(-0.4, 0.7, -1))
	b = make_prop("TestPropB", Vector3(0.4, 0.7, -1))
	await get_tree().process_frame
	_host = OS.get_cmdline_user_args().has("--host")
	var peer := ENetMultiplayerPeer.new()
	if not _host:
		world._remove_solo()
	var error := peer.create_server(17778, 3) if _host else peer.create_client("127.0.0.1", 17778)
	if error != OK:
		_fail("could not open physics test peer")
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	get_tree().create_timer(20).timeout.connect(func() -> void: _fail("physics ENet timeout"))
	if not _host:
		await multiplayer.connected_to_server
		while world.get_node_or_null("Players/" + str(multiplayer.get_unique_id())) == null:
			await get_tree().process_frame
		# Move the host away from the pickup line via the host, then request a prop.
		_ready_to_pick.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _ready_to_pick() -> void:
	if not _host:
		return
	world.get_node("Players/1").position = Vector3(3, 0, 3)
	world.get_node("Players/1")._net_pos = Vector3(3, 0, 3)
	_pick.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func _pick() -> void:
	var player: Node = world.get_node("Players/" + str(multiplayer.get_unique_id()))
	player.position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	# Allow client pose packets to reach the host before the range-checked request.
	await get_tree().create_timer(0.2).timeout
	a.request_use.rpc_id(1)
	while a.holder_id == 0:
		await get_tree().process_frame
	if a.holder_id != multiplayer.get_unique_id() or not a.freeze or a.collision_layer != 0:
		_fail("held prop state did not replicate to client")
		return
	b.request_use.rpc_id(1)
	_verify_single_slot.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _verify_single_slot() -> void:
	if not _host:
		return
	var who := multiplayer.get_remote_sender_id()
	if a.holder_id != who or b.holder_id != 0:
		_fail("client acquired more than one prop")
		return
	_check_unauthorized.call_deferred(who)

func _check_unauthorized(who: int) -> void:
	a.request_release(false) # host cannot drop a prop belonging to client
	if a.holder_id != who:
		_fail("non-holder released someone else's prop")
		return
	_charge.rpc_id(who)

@rpc("authority", "call_remote", "reliable")
func _charge() -> void:
	var started := Time.get_ticks_msec()
	a.request_charge.rpc_id(1)
	while Time.get_ticks_msec() - started < 1400:
		await get_tree().process_frame
	a.request_release.rpc_id(1, true)
	_verify_throw.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _verify_throw() -> void:
	if not _host:
		return
	if a.holder_id != 0 or a.freeze or not is_equal_approx(a.linear_velocity.length(), 14.0):
		_fail("host charged throw physics incorrect")
		return
	_check_client_release.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func _check_client_release() -> void:
	if a.holder_id != 0 or not a.freeze or a.collision_layer != 1:
		_fail("release state did not replicate")
		return
	print("House ENet client: PASS (one slot, carry state, charged release)")
	b.request_use.rpc_id(1)
	while b.holder_id == 0:
		await get_tree().process_frame
	_verified.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _verified() -> void:
	if not _host:
		return
	if b.holder_id != multiplayer.get_remote_sender_id():
		_fail("client did not acquire prop before disconnect check")
		return
	_awaiting_disconnect = true
	_disconnect_now.rpc_id(multiplayer.get_remote_sender_id())

@rpc("authority", "call_remote", "reliable")
func _disconnect_now() -> void:
	multiplayer.multiplayer_peer.close()
	get_tree().quit()

func _peer_disconnected(_who: int) -> void:
	if not _host or not _awaiting_disconnect:
		return
	if b.holder_id != 0:
		_fail("disconnect left prop locked in an absent hand")
		return
	print("House ENet host: PASS (full-world spawn, sender validation, single slot, capped charge, disconnect cleanup)")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
