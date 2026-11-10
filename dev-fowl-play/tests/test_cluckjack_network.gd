extends Node
## Run with -- --host or -- --client in two processes, host first.
const Table := preload("res://tables/cluckjack/cluckjack.tscn")
const Fixture := preload("res://tests/cluckjack_fixture.gd")
const TEST_PORT := 17777
var table: Node
var _host := false

func _ready() -> void:
	# Let autoload deferred settings calls finish against the offline peer first.
	await get_tree().process_frame
	_host = OS.get_cmdline_user_args().has("--host")
	table = Table.instantiate()
	table.set_script(Fixture)
	table.name = "Table"
	table.display_name = "Cluckjack"
	add_child(table)
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(TEST_PORT, 3) if _host else peer.create_client("127.0.0.1", TEST_PORT)
	if error != OK:
		_fail("cannot open test peer: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	get_tree().create_timer(20).timeout.connect(func() -> void: _fail("network test timed out"))
	if not _host:
		await multiplayer.connected_to_server
		_client_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not _host:
		return
	GameState.start_day()
	table.request_bet_input("min", 0)
	_client_deal.rpc_id(multiplayer.get_remote_sender_id(), table.bet)

@rpc("authority", "call_remote", "reliable")
func _client_deal(stake: int) -> void:
	table.request_play.rpc_id(1, stake)
	_verify_client_hand.call_deferred(stake)

func _verify_client_hand(stake: int) -> void:
	while table._public.is_empty():
		await get_tree().process_frame
	if table.bettor_id != multiplayer.get_unique_id() or table._public.dealer != [22, -1]:
		_fail("wrong bettor or hole card leaked")
		return
	if GameState.wallet != 1000 - stake:
		_fail("client wallet did not mirror stake")
		return
	_test_spectator.rpc_id(1, table._view_revision)

@rpc("any_peer", "call_remote", "reliable")
func _test_spectator(revision: int) -> void:
	if not _host:
		return
	# Clear the current remote RPC context so this really is a host-local action.
	_spectator_action.call_deferred(multiplayer.get_remote_sender_id(), revision)

func _spectator_action(client_id: int, revision: int) -> void:
	# Host is a spectator: a local button request must not control the client's hand.
	table._request_action("hit", {"revision": revision})
	if table.hand.player.size() != 2 or not table.running:
		_fail("spectator action was accepted")
		return
	_client_stand.rpc_id(client_id, revision)

@rpc("authority", "call_remote", "reliable")
func _client_stand(revision: int) -> void:
	table.send_action("stand", {"revision": revision})
	table.send_action("stand", {"revision": revision})
	_verify_result.call_deferred()

func _verify_result() -> void:
	while table.running:
		await get_tree().process_frame
	if GameState.wallet != 1070 or table._public.dealer != [22, 18, 35] or table._public.result != "win":
		_fail("client settlement state or wallet incorrect")
		return
	_client_verified.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _client_verified() -> void:
	if not _host:
		return
	if GameState.wallet != 1070 or GameState.ledger.size() != 1:
		_fail("duplicate action paid or logged more than once")
		return
	print("Cluckjack ENet host: PASS (client-owned hand, spectator rejection, duplicate stand, wallet and ledger)")
	_success.rpc_id(multiplayer.get_remote_sender_id())
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

@rpc("authority", "call_remote", "reliable")
func _success() -> void:
	print("Cluckjack ENet client: PASS (hidden card, remote controls, reveal and wallet replication)")
	get_tree().quit()

func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
