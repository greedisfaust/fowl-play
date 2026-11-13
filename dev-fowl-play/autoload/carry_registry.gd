extends Node

## Host-owned carry registry: the single source of truth for "who holds what".
##
## One pickup / drop / throw path used by both props and limp players.
## The registry owns the hold relationship; physical control is delegated to
## BodyPhys (host simulates, clients interpolate changed-only snapshots).
##
## Cleanup is guaranteed with no ad-hoc code for every exit path:
##   holder disconnect, held disconnect, run reset, elevator transition,
##   teleport, knockdown ending, carrier knocked down, host leaves.
##
## Authority: host-only. Clients send requests; host validates reach/state/
## single-slot and applies. All any_peer RPCs validate get_remote_sender_id().

# Preload PropProfile so its class_name is registered before headless import
# processes .tres/.tscn files that reference it (e.g. resources/profiles/*.tres).
const PropProfile = preload("res://scripts/prop_profile.gd")

signal hold_begin(holder_id: int, held_id: Variant)     # host -> all: a hold started
signal hold_end(holder_id: int, held_id: Variant, threw: bool)   # host -> all: a hold ended
signal hold_launch(held_id: Variant, direction: Vector3, speed: float)   # host -> all: a throw launch

# --- RPC wrappers for signals (signals can't be called via .rpc()) ----------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hold_begin(holder_id: int, held_id: Variant) -> void:
	hold_begin.emit(holder_id, held_id)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hold_end(holder_id: int, held_id: Variant, threw: bool) -> void:
	hold_end.emit(holder_id, held_id, threw)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hold_launch(held_id: Variant, direction: Vector3, speed: float) -> void:
	hold_launch.emit(held_id, direction, speed)

# --- tuning (shared with BodyPhys) ---------------------------------------

const CHARGE_SECONDS: float = 1.25       # s â€” hold time for full charge
const MIN_THROW_SPEED: float = 3.0       # m/s
const MAX_THROW_SPEED: float = 14.0      # m/s
const REACH: float = 3.2                 # m â€” pickup/reach distance

# --- state: single source of truth ---------------------------------------

# holder_id -> held node (Variant: Player or PhysicsProp)
var holding: Dictionary = {}
# held node -> holder_id
var held_by: Dictionary = {}

# per-peer request cooldown (basic rate limiting)
var _last_request: Dictionary = {}
const REQUEST_COOLDOWN: float = 0.15     # s

# props recently synced via _prop_state_sync — _sync_snapshot skips these
# for a short window so the client's initial position isn't overwritten by
# stale snapshots in flight.
var _just_synced: Dictionary = {}
const JUST_SYNCED_WINDOW: float = 2.0   # s

func _enter_tree() -> void:
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _ready() -> void:
	# Clear every hold when a run resets. GameState is an autoload at /root/GameState;
	# _ready runs after all autoloads are in the tree, so this connection is reliable.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.run_reset.connect(on_run_reset)

# --- helpers -------------------------------------------------------------

func _world() -> Node:
	return get_tree().get_first_node_in_group("game_world")

func _player_node(id: int) -> Node:
	var world: Node = _world()
	if world != null:
		return world.get_node_or_null("Players/" + str(id))
	return null

func _body_phys_of(node: Node3D) -> Node:
	if node == null:
		return null
	# The node itself may be a BodyPhys (PhysicsProp extends BodyPhys).
	if node.has_method("set_carry_mode"):
		return node
	var bp: Node = node.get_node_or_null("BodyPhys")
	if bp != null and bp.has_method("set_carry_mode"):
		return bp
	for child in node.get_children():
		if child != null and child.has_method("set_carry_mode"):
			return child as Node
	return null

func _prop_by_id(prop_id: int) -> Node:
	# Look up a prop by instance id across the physics_props group.
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if prop.get_instance_id() == prop_id:
			return prop
	return null

func _sender_id() -> int:
	var sender: int = multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender

# --- rate limiting -------------------------------------------------------

func _rate_limited(peer_id: int) -> bool:
	# The host (peer 1, or sender 0 for direct local calls) is authoritative
	# and trusted; only clients are rate-limited, so rapid host-driven
	# operations (tests, host logic) are never blocked.
	if peer_id == 0 or peer_id == 1:
		return false
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var last_val: Variant = _last_request.get(peer_id)
	var last: float = float(last_val if last_val != null else 0.0)
	if now - last < REQUEST_COOLDOWN:
		return true
	_last_request[peer_id] = now
	return false

# --- public API: pickup / drop / throw (host validates) ------------------

## Client requests to pick up `held_id`. Host validates reach/LoS/single-slot.
@rpc("any_peer", "call_remote", "reliable")
func hold_request_pickup(holder_id: int, held_id: Variant) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peer_of_request(sender) != holder_id:
		return   # clients can't pick up on behalf of another peer

	var holder: Node3D = _player_node(holder_id) as Node3D
	var held: Node = _held_node_by_id(held_id)
	if holder == null or held == null:
		return
	if holding.has(holder_id):
		return   # single-slot: holder already carrying something
	if held_by.has(held):
		return   # already held by someone else

	# Reach / line-of-sight validation (host-side, against authoritative snapshot).
	if not _can_reach(holder, held):
		return

	# can_pick_up gate: non-pickupable props cannot be held — shove them away instead.
	var cp: Variant = held.get("can_pick_up")
	if cp != null and not bool(cp):
		if held.has_method("request_push"):
			held.request_push(holder_id)
		return

	# Rate limit only on successful validation (failed requests don't consume budget).
	if _rate_limited(sender):
		return

	# Apply the hold.
	_apply_hold(holder_id, held)

# Client requests to drop what they're holding. threw = false for plain drop.
@rpc("any_peer", "call_remote", "reliable")
func hold_request_drop(holder_id: int, threw: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peer_of_request(sender) != holder_id:
		return

	var held: Node = holding.get(holder_id) as Node
	if held == null:
		return   # not carrying anything

	# Rate limit only on successful validation (failed requests don't consume budget).
	if _rate_limited(sender):
		return

	_release_hold(holder_id, held, threw)

# Client requests to throw with client-supplied aim direction + charge.
# Host clamps charge to speed and applies launch.
@rpc("any_peer", "call_remote", "reliable")
func hold_request_throw(holder_id: int, direction: Vector3, charge: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peer_of_request(sender) != holder_id:
		return

	var held: Node = holding.get(holder_id) as Node
	if held == null:
		return   # not carrying anything

	# Rate limit only on successful validation (failed requests don't consume budget).
	if _rate_limited(sender):
		return

	# Clamp charge [0,1] -> speed [MIN, MAX].
	var c: float = clampf(charge, 0.0, 1.0)
	var speed: float = lerpf(MIN_THROW_SPEED, MAX_THROW_SPEED, c)
	var dir: Vector3 = direction.normalized()
	if dir == Vector3.ZERO:
		dir = -_look_direction(holder_id)

	_release_hold(holder_id, held, true, dir * speed)

# --- internal: apply / release holds -------------------------------------

func _apply_hold(holder_id: int, held: Node) -> void:
	var holder: Node3D = _player_node(holder_id) as Node3D
	if holder == null:
		return

	# Physical control: BodyPhys carry mode (host simulates).
	var bp: Node = _body_phys_of(held as Node3D)
	var offset: Vector3 = Vector3.ZERO
	if held.has_method("get_carry_offset"):
		offset = held.call("get_carry_offset")
	if bp != null:
		bp.set_carry_mode(holder, offset)

	# Mirror holder_id onto the held node (quick read cache).
	if held.has_method("_apply_hold"):
		held.call("_apply_hold", holder_id)

	# Record in single source of truth.
	holding[holder_id] = held
	held_by[held] = holder_id

	hold_begin.emit(holder_id, _held_id(held))

	# Replicate to all peers.
	_rpc_hold_begin.rpc(holder_id, _held_id(held))

func _release_hold(holder_id: int, held: Node, threw: bool = false, launch: Vector3 = Vector3.ZERO) -> void:
	var held_id: Variant = _held_id(held)

	# Physical control: leave carry mode, apply launch if throwing.
	var bp: Node = _body_phys_of(held as Node3D)
	if bp != null:
		bp.clear_carry_mode(launch)

	# Mirror release onto the held node (clears holder_id cache).
	if held.has_method("_release_hold"):
		held.call("_release_hold", threw, launch)

	# Clear single source of truth.
	holding.erase(holder_id)
	held_by.erase(held)

	hold_end.emit(holder_id, held_id, threw)
	_rpc_hold_end.rpc(holder_id, held_id, threw)

	if threw and launch != Vector3.ZERO:
		hold_launch.emit(held_id, launch.normalized(), launch.length())
		_rpc_hold_launch.rpc(held_id, launch.normalized(), launch.length())

# --- cleanup: guaranteed on every exit path ------------------------------

## Call when a holder disconnects: release what they carry (drop, not throw).
func on_holder_disconnect(holder_id: int) -> void:
	if not multiplayer.is_server():
		return
	var held: Node = holding.get(holder_id) as Node
	if held != null:
		_release_hold(holder_id, held, false)

## Call when a held player/prop disconnects: clear their holder's carry.
func on_held_disconnect(held: Node) -> void:
	if not multiplayer.is_server():
		return
	var holder_id_val: Variant = held_by.get(held)
	var holder_id: int = int(holder_id_val if holder_id_val != null else 0)
	if holder_id != 0:
		holding.erase(holder_id)
		held_by.erase(held)
		var held_id: Variant = _held_id(held)
		hold_end.emit(holder_id, held_id, false)
		_rpc_hold_end.rpc(holder_id, held_id, false)

## Call when a holder teleports: drop what they carry.
func on_teleport(holder_id: int) -> void:
	if not multiplayer.is_server():
		return
	var held: Node = holding.get(holder_id) as Node
	if held != null:
		_release_hold(holder_id, held, false)

## Call during elevator transition: release all carried props (props may
## return home or move rooms; carried players are teleported separately).
func on_elevator_transition() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held: Node = holding[holder_id] as Node
		_release_hold(holder_id, held, false)

## Call on run reset: clear every hold.
func on_run_reset() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held: Node = holding[holder_id] as Node
		_release_hold(holder_id, held, false)

## Call when the host leaves: clear every hold.
func on_host_leave() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held: Node = holding[holder_id] as Node
		_release_hold(holder_id, held, false)

# --- peer disconnect (host auto-handles) ---------------------------------

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# If the disconnecting peer was holding something, release it.
	on_holder_disconnect(id)
	# If the disconnecting peer was being held, clear their holder.
	for held in holding.values().duplicate():
		if str(_held_id(held)) == str(id):
			on_held_disconnect(held)
			break

# --- late-join prop state sync --------------------------------------------

## Send every prop's current transform + carry holder to a joining peer so the
## new client renders props at their real positions (not their scene home
## positions) and can interact with them immediately. Host only; called from
## Network._on_peer_connected and by request_prop_state_sync.
func _send_prop_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var states: Array = []
	for prop in get_tree().get_nodes_in_group("physics_props"):
		var t: Transform3D = prop.global_transform
		var hid: Variant = held_by.get(prop, 0)
		var bp: Node = _body_phys_of(prop as Node3D)
		var lv: Vector3 = Vector3.ZERO
		var av: Vector3 = Vector3.ZERO
		if bp != null:
			lv = (bp as Node3D).linear_velocity
			av = (bp as Node3D).angular_velocity
		states.append([prop.name, t, hid, lv, av])
	_prop_state_sync.rpc_id(peer_id, states)

## Client receives current prop state from the host when joining. Applied only
## to props matched by name (names replicate; instance ids do not).
@rpc("any_peer", "call_remote", "reliable")
func _prop_state_sync(states: Array) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host may sync prop state
	for entry in states:
		if entry.size() < 3:
			continue
		var name: String = String(entry[0])
		var t: Transform3D = Transform3D(entry[1])
		var hid: Variant = entry[2]
		var prop: Node = _prop_by_name(name)
		if prop == null:
			continue
		var bp: Node = _body_phys_of(prop as Node3D)
		if bp != null:
			# Wake the body so the physics server doesn't reset it back home,
			# force it to our exact transform, seed interpolation, and restore
			# velocity so client-side lerp has a clean target.
			(bp as Node3D).sleeping = false
			bp.last_synced_transform = t
			if entry.size() >= 4:
				var lv: Vector3 = Vector3(entry[3])
				var av: Vector3 = Vector3(entry[4])
				(bp as Node3D).linear_velocity = lv
				(bp as Node3D).angular_velocity = av
		prop.global_transform = t

## Client requests current prop state from the host. Called by the joining
## client once its room is fully instantiated so all props are in the
## physics_props group and can be matched by name. Host only.
@rpc("any_peer", "call_remote", "reliable")
func request_prop_state_sync() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1
	_send_prop_state_to_peer(peer_id)

## Look up a prop in the physics_props group by its (replicated) name.
func _prop_by_name(name: String) -> Node:
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if str(prop.name) == str(name):
			return prop
	return null

# --- private helpers -----------------------------------------------------

func _held_id(held: Node) -> Variant:
	# Players are named by peer id at spawn (world.gd). Props use their set name.
	# Names replicate across peers; instance ids do not.
	return held.name

func _held_node_by_id(held_id: Variant) -> Node:
	# Check players first (named by peer id).
	for pid in _player_ids():
		var p: Node = _player_node(pid)
		if p != null and str(pid) == str(held_id):
			return p
	# Then props (named by their set name, e.g. "TestPropA").
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if prop.name == held_id:
			return prop
	return null

func _player_ids() -> Array[int]:
	var ids: Array[int] = []
	var world: Node = _world()
	if world == null:
		return ids
	var players: Node = world.get_node_or_null("Players")
	if players == null:
		return ids
	for child in players.get_children():
		if str(child.name).match(r"^\d+$"):
			ids.append(child.name.to_int())
	return ids

## Public: resolve a held id (peer id for players, instance id for props) back
## to the node. Used by players to keep local `carrier.carried` bookkeeping in
## sync with hold_begin/hold_end without querying the registry directly.
func node_for_held(held_id: Variant) -> Node:
	# Players are named by peer id at spawn.
	for pid in _player_ids():
		var p: Node = _player_node(pid)
		if p != null and str(pid) == str(held_id):
			return p
	# Then props (named by their set name).
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if str(prop.name) == str(held_id):
			return prop
	return null

func _peer_of_request(sender: int) -> int:
	# The requesting peer is the sender (host = 1 maps to unique_id 1 locally).
	# sender == 0 means a direct local call â€” treat as host (peer 1).
	return sender if sender != 0 else 1

func _look_direction(holder_id: int) -> Vector3:
	var holder: Node3D = _player_node(holder_id) as Node3D
	if holder != null and holder.has_node("Head"):
		return -(holder.get_node("Head") as Node3D).global_basis.z
	return Vector3.FORWARD

func _can_reach(holder: Node3D, held: Node) -> bool:
	if holder == null or held == null:
		return false
	var eye: Vector3 = holder.global_position
	if holder.has_node("Head"):
		eye = (holder.get_node("Head") as Node3D).global_position
	var held_pos: Vector3 = (held as Node3D).global_position
	if eye.distance_to(held_pos) > REACH:
		return false
	# Line of sight (a carried prop's own CollisionShape counts as held).
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(eye, held_pos)
	query.exclude = [holder.get_rid()]
	var hit: Dictionary = get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Node = hit.get("collider")
		if collider != null:
			var c: Node = collider
			while c != null:
				if c == held:
					return true
				c = c.get_parent()
			return false
	return true


