class_name PhysicsProp
extends RigidBody3D
## Only the host simulates loose props. Clients interpolate authoritative snapshots.
const REACH := 3.2
const CHARGE_SECONDS := 1.25
const MIN_THROW_SPEED := 3.0
const MAX_THROW_SPEED := 14.0

@export var item_name := "Object"
@export var can_pick_up := true
var holder_id := 0
var _home := Transform3D.IDENTITY
var _net_position := Vector3.ZERO
var _net_rotation := Quaternion.IDENTITY
var _snapshot_time := 0.0
var _charge_started := -1
var _last_push := -1000

func _ready() -> void:
	add_to_group("physics_props")
	_home = global_transform
	_net_position = global_position
	_net_rotation = global_basis.get_rotation_quaternion()
	freeze = not multiplayer.is_server()
	continuous_cd = true
	linear_damp = 0.8
	angular_damp = 1.5
	multiplayer.peer_disconnected.connect(_peer_left)
	multiplayer.peer_connected.connect(_send_initial)
	GameState.run_reset.connect(reset_prop)

func interact(_player: Node) -> void:
	request_use.rpc_id(1)

func get_interaction_prompt(player: Node) -> String:
	if holder_id != 0:
		return item_name + " (carried)"
	if can_pick_up and held_by(get_tree(), str(player.name).to_int()) != null:
		return "Hand full - G to drop your object"
	return ("Pick up " if can_pick_up else "Push ") + item_name

static func held_by(tree: SceneTree, who: int) -> PhysicsProp:
	for prop in tree.get_nodes_in_group("physics_props"):
		if prop.holder_id == who:
			return prop
	return null

static func throw_speed(seconds: float) -> float:
	return lerpf(MIN_THROW_SPEED, MAX_THROW_SPEED, clampf(seconds / CHARGE_SECONDS, 0.0, 1.0))

func _player(who: int) -> Node3D:
	return get_tree().get_first_node_in_group("game_world").get_node_or_null("Players/" + str(who)) if get_tree().has_group("game_world") else null

func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender

func _can_reach(who: int, line_of_sight := true) -> bool:
	var player := _player(who)
	if not Network.players.has(who) or player == null:
		return false
	var eye: Vector3 = player.head.global_position
	if eye.distance_to(global_position) > REACH:
		return false
	if line_of_sight:
		var query := PhysicsRayQueryParameters3D.create(eye, global_position)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider != self:
			return false
	return true

@rpc("any_peer", "call_local", "reliable")
func request_use() -> void:
	if not multiplayer.is_server() or holder_id != 0:
		return
	var who := _sender()
	if not _can_reach(who):
		return
	if not can_pick_up:
		_push(who)
		return
	if held_by(get_tree(), who) != null:
		_notice.rpc_id(who, "One hand, one object. Press G to drop it first.")
		return
	_charge_started = -1
	_sync_holder.rpc(who, global_position, global_basis.get_rotation_quaternion())

@rpc("any_peer", "call_local", "reliable")
func request_push() -> void:
	if multiplayer.is_server() and holder_id == 0 and _can_reach(_sender(), false):
		_push(_sender())

func _push(who: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_push < 180:
		return
	_last_push = now
	var player := _player(who)
	var direction: Vector3 = global_position - player.global_position
	direction.y = 0.0
	apply_central_impulse(direction.normalized() * mass * 2.2)

@rpc("any_peer", "call_local", "reliable")
func request_charge() -> void:
	if multiplayer.is_server() and holder_id == _sender() and holder_id != 0 and _charge_started < 0:
		_charge_started = Time.get_ticks_msec()

@rpc("any_peer", "call_local", "reliable")
func request_release(throwing: bool) -> void:
	if not multiplayer.is_server() or holder_id == 0 or holder_id != _sender():
		return
	if throwing and _charge_started < 0:
		return
	_release(throwing)

func _release(throwing: bool) -> void:
	var player := _player(holder_id)
	var direction: Vector3 = Vector3.FORWARD if player == null else -player.head.global_basis.z
	var speed := throw_speed((Time.get_ticks_msec() - _charge_started) / 1000.0) if throwing else 0.0
	_charge_started = -1
	_sync_holder.rpc(0, global_position, global_basis.get_rotation_quaternion())
	linear_velocity = direction * speed
	angular_velocity = Vector3(2, 1, 0) if throwing else Vector3.ZERO
	sleeping = false

func drop_for_transition(who: int) -> void:
	if multiplayer.is_server() and holder_id == who:
		_release(false)

func _peer_left(who: int) -> void:
	drop_for_transition(who)

func _send_initial(who: int) -> void:
	if multiplayer.is_server():
		_sync_holder.rpc_id(who, holder_id, global_position, global_basis.get_rotation_quaternion())

@rpc("authority", "call_local", "reliable")
func _sync_holder(who: int, pos: Vector3, rot: Quaternion) -> void:
	holder_id = who
	freeze = who != 0 or not multiplayer.is_server()
	collision_layer = 1 if who == 0 else 0
	collision_mask = 1 if who == 0 else 0
	global_position = pos
	quaternion = rot
	_net_position = pos
	_net_rotation = rot
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_motion(pos: Vector3, rot: Quaternion) -> void:
	_net_position = pos
	_net_rotation = rot

@rpc("authority", "call_local", "reliable")
func _notice(message: String) -> void:
	var player := _player(multiplayer.get_unique_id())
	if player != null:
		player.show_notice(message)

func reset_prop() -> void:
	_charge_started = -1
	_sync_holder(0, _home.origin, _home.basis.get_rotation_quaternion())
	sleeping = false

func _physics_process(delta: float) -> void:
	if holder_id != 0:
		var player := _player(holder_id)
		if player != null:
			var eye: Vector3 = player.head.global_position
			var target: Vector3 = player.head.to_global(Vector3(0.38, -0.28, -0.85))
			var query := PhysicsRayQueryParameters3D.create(eye, target)
			query.exclude = [player.get_rid(), get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			global_position = target if hit.is_empty() else hit.position + hit.normal * 0.25
			global_basis = player.head.global_basis
	elif not multiplayer.is_server():
		freeze = true
		global_position = global_position.lerp(_net_position, minf(delta * 18.0, 1.0))
		quaternion = quaternion.slerp(_net_rotation, minf(delta * 18.0, 1.0))
	if multiplayer.is_server():
		if global_position.y < -10.0:
			_sync_holder.rpc(0, _home.origin, _home.basis.get_rotation_quaternion())
		_snapshot_time += delta
		if _snapshot_time >= 1.0 / 15.0:
			_snapshot_time = 0.0
			_sync_motion.rpc(global_position, global_basis.get_rotation_quaternion())
