extends Node
## Full-world ENet check with the new CarryRegistry foundation (R2/R3).
## Host validates pickup reach/state/single-slot; clients request holds via
## CarryRegistry RPCs; carry state replicates via hold_begin/hold_end signals.

const Prop := preload("res://interaction/physics_prop.gd")
var world: Node3D
var a: PhysicsProp
var b: PhysicsProp
var _host := false
var _awaiting_disconnect := false

func make_prop(label: String, pos: Vector3) -> PhysicsProp:
	var prop := PhysicsProp.new()
	prop.name = label
	prop.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.25
	collision.shape = shape
	prop.add_child(collision)
	world.add_child(prop)
	return prop

# Wait for a hold_begin signal matching (holder_id, held_name), with a timeout.
# Must be connected BEFORE sending the pickup RPC, otherwise the replicated
# hold_begin can fire on localhost before the callback is attached.
var _hold_begin_got: bool = false
var _hold_begin_holder: int = 0
var _hold_begin_held: String = ""

func _on_hold_begin_wait(h_id: int, held_id: Variant) -> void:
	if str(held_id) == _hold_begin_held and h_id == _hold_begin_holder:
		_hold_begin_got = true

func _wait_for_hold_begin(holder_id: int, held_name: String, timeout: float = 5.0) -> bool:
	_hold_begin_got = false
	_hold_begin_holder = holder_id
	_hold_begin_held = held_name
	var waited := 0.0
	while not _hold_begin_got and waited < timeout:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	CarryRegistry.hold_begin.disconnect(_on_hold_begin_wait)
	return _hold_begin_got

func _ready() -> void:
	print("NETTEST ready: host=" + str(_host))
	world = preload("res://world.tscn").instantiate()
	world.name = "World"
	add_child(world)
	a = make_prop("TestPropA", Vector3(-0.4, 0.7, -1))
	b = make_prop("TestPropB", Vector3(0.4, 0.7, -1))
	await get_tree().process_frame
	_host = "--is-host" in OS.get_cmdline_user_args() or "--is-host" in OS.get_cmdline_args()
	print("NETTEST cmdline: " + str(OS.get_cmdline_user_args()) + " _host=" + str(_host))
	var peer := ENetMultiplayerPeer.new()
	if not _host:
		world._remove_solo()
	var error := peer.create_server(17778, 3) if _host else peer.create_client("127.0.0.1", 17778)
	print("NETTEST peer create error: " + str(error) + " _host=" + str(_host))
	if error != OK:
		_fail("could not open physics test peer")
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	get_tree().create_timer(20).timeout.connect(func() -> void: _fail("physics ENet timeout"))
	if not _host:
		await multiplayer.connected_to_server
		print("NETTEST client connected, uid=" + str(multiplayer.get_unique_id()))
		# Move the host player out of the way via the host, then request a prop.
		_ready_to_pick.rpc_id(1)
		await get_tree().create_timer(0.2).timeout
		# Connect to hold_begin BEFORE sending pickup: on fast localhost the
		# replicated hold_begin can fire before we attach the callback.
		var uid := multiplayer.get_unique_id()
		_hold_begin_got = false
		_hold_begin_holder = uid
		_hold_begin_held = a.name
		CarryRegistry.hold_begin.connect(_on_hold_begin_wait)
		# Request pickup of prop A (reach-checked and slot-checked by host).
		CarryRegistry.hold_request_pickup.rpc_id(1, uid, a.name)
		print("NETTEST client: sent pickup for " + a.name)
		if not await _wait_for_hold_begin(uid, a.name):
			_fail("pickup did not replicate to client")
			return
		print("NETTEST client: hold_begin received for " + a.name)
		# Single slot: requesting b must be rejected by the host.
		CarryRegistry.hold_request_pickup.rpc_id(1, uid, b.name)
		print("NETTEST client: sent pickup for " + b.name + " (expect rejection)")
		_verify_single_slot.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _ready_to_pick() -> void:
	if not _host:
		return
	var sender := multiplayer.get_remote_sender_id()
	print("NETTEST host: _ready_to_pick, sender=" + str(sender))
	# Move the requesting client's player next to prop A so reach passes.
	var holder_node := world.get_node_or_null("Players/" + str(sender))
	if holder_node != null:
		(holder_node as Node3D).position = Vector3(-0.4, 0.7, 0)

@rpc("any_peer", "call_remote", "reliable")
func _verify_single_slot() -> void:
	if not _host:
		return
	var who := multiplayer.get_remote_sender_id()
	if CarryRegistry.held_by.get(a) != who or CarryRegistry.held_by.has(b):
		_fail("client acquired more than one prop")
		return
	_check_unauthorized.call_deferred(who)

func _check_unauthorized(who: int) -> void:
	# Host cannot drop a prop belonging to the client.
	# A direct local call simulates the sender check (sender 0 -> peer 1 != who),
	# so the client's hold must survive.
	var survived: bool = CarryRegistry.held_by.has(a)
	CarryRegistry.hold_request_drop(who, false)
	if not survived or not CarryRegistry.held_by.has(a):
		_fail("unauthorized drop should not release client's prop")
		return
	_charge.rpc_id(who)

@rpc("any_peer", "call_remote", "reliable")
func _charge() -> void:
	await get_tree().create_timer(1.5).timeout
	var dir := Vector3(0, 0, -1)
	CarryRegistry.hold_request_throw.rpc_id(1, multiplayer.get_unique_id(), dir, 1.0)
	_verify_throw.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _verify_throw() -> void:
	if not _host:
		return
	if CarryRegistry.held_by.has(a) or a.freeze or not is_equal_approx(a.linear_velocity.length(), 14.0):
		_fail("host charged throw physics incorrect")
		return
	_check_client_release.rpc_id(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func _check_client_release() -> void:
	if CarryRegistry.held_by.has(a) or not a.freeze:
		_fail("release state did not replicate")
		return
	print("House ENet client: PASS (one slot, carry state, charged release)")
	var uid := multiplayer.get_unique_id()
	_hold_begin_got = false
	_hold_begin_holder = uid
	_hold_begin_held = b.name
	CarryRegistry.hold_begin.connect(_on_hold_begin_wait)
	# Rate limit cooldown (0.15s) passed since the throw; wait a moment so the
	# second pickup isn't rejected as spam.
	await get_tree().create_timer(0.2).timeout
	CarryRegistry.hold_request_pickup.rpc_id(1, uid, b.name)
	if not await _wait_for_hold_begin(uid, b.name):
		_fail("second pickup did not replicate to client")
		return
	_verified.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _verified() -> void:
	if not _host:
		return
	if CarryRegistry.held_by.get(b) != multiplayer.get_remote_sender_id():
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
	if CarryRegistry.held_by.has(b):
		_fail("disconnect left prop locked in an absent hand")
		return
	print("House ENet host: PASS (full-world spawn, sender validation, single slot, capped charge, disconnect cleanup)")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
