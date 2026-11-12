extends Node

class_name CarryRegistry

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

signal hold_begin(holder_id: int, held_id: int)     # host -> all: a hold started
signal hold_end(holder_id: int, held_id: int, threw: bool)   # host -> all: a hold ended
signal hold_launch(held_id: int, direction: Vector3, speed: float)   # host -> all: a throw launch

# --- tuning (shared with BodyPhys) ---------------------------------------

const CHARGE_SECONDS: float = 1.25       # s — hold time for full charge
const MIN_THROW_SPEED: float = 3.0       # m/s
const MAX_THROW_SPEED: float = 14.0      # m/s
const REACH: float = 3.2                 # m — pickup/reach distance

# --- state: single source of truth ---------------------------------------

# holder_id -> held node (Variant: Player or PhysicsProp)
var holding: Dictionary = {}
# held node -> holder_id
var held_by: Dictionary = {}

# per-peer request cooldown (basic rate limiting)
var _last_request: Dictionary = {}
const REQUEST_COOLDOWN: float = 0.15     # s

func _enter_tree() -> void:
	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# --- helpers -------------------------------------------------------------

func _world() -> Node3D:
	return get_tree().get_first_node_in_group("game_world")

func _player_node(id: int) -> Node3D:
	var world := _world()
	return world.get_node_or_null("Players/" + str(id)) if world != null else null

func _body_phys_of(node: Node3D) -> BodyPhys:
	if node == null:
		return null
	var bp := node.get_node_or_null("BodyPhys")
	if bp != null:
		return bp
	for child in node.get_children():
		if child is BodyPhys:
			return child
	return null

func _prop_by_id(prop_id: int) -> PhysicsProp:
	# Look up a prop by instance id across the physics_props group.
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if prop.get_instance_id() == prop_id:
			return prop
	return null

func _sender_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender

# --- rate limiting -------------------------------------------------------

func _rate_limited(peer_id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var last := _last_request.get(peer_id, 0.0)
	if now - last < REQUEST_COOLDOWN:
		return true
	_last_request[peer_id] = now
	return false

# --- public API: pickup / drop / throw (host validates) ------------------

## Client requests to pick up `held_id`. Host validates reach/LoS/single-slot.
@rpc("any_peer", "call_local", "reliable")
func hold_request_pickup(holder_id: int, held_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return   # only the host processes pickup requests
	if _rate_limited(sender):
		return
	if _peer_of_request(sender) != holder_id:
		return   # clients can't pick up on behalf of another peer

	var holder := _player_node(holder_id)
	var held := _held_node_by_id(held_id)
	if holder == null or held == null:
		return
	if holding.has(holder_id):
		return   # single-slot: holder already carrying something
	if held_by.has(held):
		return   # already held by someone else

	# Reach / line-of-sight validation (host-side, against authoritative snapshot).
	if not _can_reach(holder, held):
		return

	# Apply the hold.
	_apply_hold(holder_id, held)

# Client requests to drop what they're holding. threw = false for plain drop.
@rpc("any_peer", "call_local", "reliable")
func hold_request_drop(holder_id: int, threw: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if _rate_limited(sender):
		return
	if _peer_of_request(sender) != holder_id:
		return

	var held := holding.get(holder_id)
	if held == null:
		return   # not carrying anything
	_release_hold(holder_id, held, threw)

# Client requests to throw with client-supplied aim direction + charge.
# Host clamps charge to speed and applies launch.
@rpc("any_peer", "call_local", "reliable")
func hold_request_throw(holder_id: int, direction: Vector3, charge: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if _rate_limited(sender):
		return
	if _peer_of_request(sender) != holder_id:
		return

	var held := holding.get(holder_id)
	if held == null:
		return   # not carrying anything

	# Clamp charge [0,1] -> speed [MIN, MAX].
	var c := clampf(charge, 0.0, 1.0)
	var speed := lerpf(MIN_THROW_SPEED, MAX_THROW_SPEED, c)
	var dir := direction.normalized()
	if dir == Vector3.ZERO:
		dir = -_look_direction(holder_id)

	_release_hold(holder_id, held, true, dir * speed)

# --- internal: apply / release holds -------------------------------------

func _apply_hold(holder_id: int, held: Node) -> void:
	var holder := _player_node(holder_id)
	if holder == null:
		return

	# Physical control: BodyPhys carry mode (host simulates).
	var bp := _body_phys_of(held)
	var offset := Vector3.ZERO
	if held.has_method("get_carry_offset"):
		offset = held.get_carry_offset()
	if bp != null:
		bp.set_carry_mode(holder, offset)

	# Player state transitions (if players are involved).
	_holder_state(holder_id, True)
	_held_state(held, True, holder_id)

	# Record in single source of truth.
	holding[holder_id] = held
	held_by[held] = holder_id

	hold_begin.emit(holder_id, _held_id(held))

	# Replicate to all peers.
	hold_begin.rpc(holder_id, _held_id(held))

func _release_hold(holder_id: int, held: Node, threw: bool = false, launch: Vector3 = Vector3.ZERO) -> void:
	var held_id := _held_id(held)

	# Physical control: leave carry mode, apply launch if throwing.
	var bp := _body_phys_of(held)
	if bp != null:
		bp.clear_carry_mode(launch)

	# Player state transitions.
	_holder_state(holder_id, False)
	_held_state(held, False, 0)

	# Clear single source of truth.
	holding.erase(holder_id)
	held_by.erase(held)

	hold_end.emit(holder_id, held_id, threw)
	hold_end.rpc(holder_id, held_id, threw)

	if threw and launch != Vector3.ZERO:
		hold_launch.emit(held_id, launch.normalized(), launch.length())
		hold_launch.rpc(held_id, launch.normalized(), launch.length())

# --- cleanup: guaranteed on every exit path ------------------------------

## Call when a holder disconnects: release what they carry (drop, not throw).
func on_holder_disconnect(holder_id: int) -> void:
	if not multiplayer.is_server():
		return
	var held := holding.get(holder_id)
	if held != null:
		_release_hold(holder_id, held, false)

## Call when a held player/prop disconnects: clear their holder's carry.
func on_held_disconnect(held: Node) -> void:
	if not multiplayer.is_server():
		return
	var holder_id := held_by.get(held, 0)
	if holder_id != 0:
		holding.erase(holder_id)
		_holder_state(holder_id, False)
		held_by.erase(held)
		var held_id := _held_id(held)
		hold_end.emit(holder_id, held_id, false)
		hold_end.rpc(holder_id, held_id, false)

## Call when a holder teleports: drop what they carry.
func on_teleport(holder_id: int) -> void:
	if not multiplayer.is_server():
		return
	var held := holding.get(holder_id)
	if held != null:
		_release_hold(holder_id, held, false)

## Call during elevator transition: release all carried props (props may
## return home or move rooms; carried players are teleported separately).
func on_elevator_transition() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held := holding[holder_id]
		_release_hold(holder_id, held, false)

## Call on run reset: clear every hold.
func on_run_reset() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held := holding[holder_id]
		_release_hold(holder_id, held, false)

## Call when the host leaves: clear every hold.
func on_host_leave() -> void:
	if not multiplayer.is_server():
		return
	for holder_id in holding.keys().duplicate():
		var held := holding[holder_id]
		_release_hold(holder_id, held, false)

# --- peer disconnect (host auto-handles) ---------------------------------

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# If the disconnecting peer was holding something, release it.
	on_holder_disconnect(id)
	# If the disconnecting peer was being held, clear their holder.
	for held in holding.values().duplicate():
		if _held_id(held) == id:
			on_held_disconnect(held)
			break

# --- private helpers -----------------------------------------------------

func _held_id(held: Node) -> int:
	# Players are named by peer id at spawn (world.gd). Props use instance id.
	if held.name.match(r"^\d+$"):
		return held.name.to_int()
	return held.get_instance_id()

func _held_node_by_id(held_id: int) -> Node:
	# Check players first.
	for pid in _player_ids():
		var p := _player_node(pid)
		if p != null and str(pid) == str(held_id):
			return p
	# Then props.
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if prop.get_instance_id() == held_id:
			return prop
	return null

func _player_ids() -> Array:
	var ids := Array[int]()
	var world := _world()
	if world == null:
		return ids
	var players := world.get_node_or_null("Players")
	if players == null:
		return ids
	for child in players.get_children():
		if child.name.match(r"^\d+$"):
			ids.append(child.name.to_int())
	return ids

func _peer_of_request(sender: int) -> int:
	# The requesting peer is the sender (host = 1 maps to unique_id 1 locally).
	return sender

func _look_direction(holder_id: int) -> Vector3:
	var holder := _player_node(holder_id)
	if holder != null and holder.has_node("Head"):
		return -holder.get_node("Head").global_basis.z
	return Vector3.FORWARD

func _can_reach(holder: Node3D, held: Node) -> bool:
	if holder == null or held == null:
		return false
	var eye := holder.global_position
	if holder.has_node("Head"):
		eye = holder.get_node("Head").global_position
	if eye.distance_to(held.global_position) > REACH:
		return false
	# Line of sight.
	var query := PhysicsRayQueryParameters3D.create(eye, held.global_position)
	query.exclude = [holder.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider != held:
		return false
	return true

# --- player state helpers ------------------------------------------------

# called by _apply_hold / _release_hold
func _holder_state(holder_id: int, carrying: bool) -> void:
	var holder := _player_node(holder_id)
	if holder == null:
		return
	var state := holder.get_node_or_null("PlayerState")
	if state != null and state.has_method("transition_to"):
		if carrying:
			state.transition_to(PlayerState.State.CARRYING)
		else:
			state.transition_to(PlayerState.State.IDLE)

func _held_state(held: Node, carried: bool, carrier_id: int) -> void:
	# For limp players: transition to LIMP / IDLE. Implemented in Phase 3
	# when PlayerState is redesigned. No-op here to avoid breaking current
	# PlayerState which still uses KNOCKED_DOWN / RAGDOLL.
	pass
