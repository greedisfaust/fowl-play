extends BodyPhys

class_name PhysicsProp

## Carryable prop (R2 + R3): a BodyPhys that routes hold state through
## CarryRegistry. One pickup/drop/throw path shared with limp players.
##
## Authority: host simulates (freeze=false), clients freeze + interpolate
## BodyPhys changed-only snapshots. While carried, freeze=true and the body
## follows the carrier anchor via BodyPhys carry mode.
##
## A PropProfile resource (assigned in the Inspector) picks weight class,
## pickup/throw allowed, friction/bounce preset, size class, and optional
## impact sound. No per-prop magic numbers.

@export var item_name: String = "Object"
@export var can_pick_up: bool = true
@export var profile: PropProfile = null   # assigned in Inspector; no code default
var holder_id: int = 0        # mirrored from CarryRegistry for quick reads
var _home: Transform3D = Transform3D.IDENTITY

# --- setup ----------------------------------------------------------------

func _ready() -> void:
	add_to_group("physics_props")
	_home = global_transform

	# Props live on the PROPS layer so the focus ray (MASK_FOCUS_RAY) can hit them.
	# Scene-based props set this in their .tscn; code-built props (house_environment.gd)
	# need it here so they remain focusable during the room-by-room migration.
	collision_layer = 4

	# Apply the profile: mass, friction, bounce, pickup, throwable.
	if profile != null:
		match profile.weight_class:
			PropProfile.WeightClass.LIGHT:
				mass = PhysicsTuning.PROP_MASS_KG
			PropProfile.WeightClass.MEDIUM:
				mass = 2.0
			PropProfile.WeightClass.HEAVY:
				mass = PhysicsTuning.LARGE_PROP_MASS_KG
			PropProfile.WeightClass.IMMOVABLE:
				mass = PhysicsTuning.LARGE_PROP_MASS_KG
				freeze = true   # immovable: never simulated by anyone
		linear_damp = PhysicsTuning.LINEAR_DAMP
		angular_damp = PhysicsTuning.ANGULAR_DAMP
		gravity_scale = PhysicsTuning.GRAVITY_SCALE
		can_pick_up = profile.pickup_allowed
		continuous_cd = true
	else:
		mass = PhysicsTuning.PROP_MASS_KG
		linear_damp = PhysicsTuning.LINEAR_DAMP
		angular_damp = PhysicsTuning.ANGULAR_DAMP
		gravity_scale = PhysicsTuning.GRAVITY_SCALE

	# Expose the single Interactable contract (R1).
	var interactable := Interactable.new()
	interactable.kind = Interactable.Kind.GRAB if can_pick_up else Interactable.Kind.USE
	add_child(interactable)

	# Host simulates; clients interpolate (set in BodyPhys._enter_tree).

# --- Carryable contract ---------------------------------------------------

func pickup(holder: Node) -> void:
	# Called by Carrier: ask the host to register the hold.
	var who := _holder_peer_id(holder)
	if who == 0:
		who = 1
	if multiplayer.is_server():
		CarryRegistry.hold_request_pickup(who, name)   # local call when we're the host
	else:
		CarryRegistry.hold_request_pickup.rpc_id(1, who, name)

func release(throw: bool, direction: Vector3, speed: float) -> void:
	# Called by Carrier: ask the host to release (drop or throw).
	var who := holder_id
	if who == 0:
		who = 1
	if multiplayer.is_server():
		CarryRegistry.hold_request_drop(who, throw)   # local call when we're the host
	else:
		CarryRegistry.hold_request_drop.rpc_id(1, who, throw)

func is_carried() -> bool:
	if CarryRegistry == null:
		return false
	return CarryRegistry.held_by.has(self)

func get_carry_offset() -> Vector3:
	# Held in the right hand, head-relative:
	#   x = right, y = down from eye level to chest, z = in front of face
	return Vector3(0.45, -0.40, -0.70)

func get_throw_speed(charge: float) -> float:
	return lerpf(PhysicsTuning.MIN_THROW_SPEED_MPS, PhysicsTuning.MAX_THROW_SPEED_MPS, clampf(charge, 0.0, 1.0))

# --- interaction (USE when not carryable, GRAB when carryable) ------------

func interact(player: Node) -> void:
	if not can_pick_up:
		# Non-pickupable: shove away (host-authoritative push).
		request_push.rpc_id(1, _holder_peer_id(player))
		return
	# Carryable: request pickup via the registry.
	var who := _holder_peer_id(player)
	if multiplayer.is_server():
		CarryRegistry.hold_request_pickup(who, name)   # local call when we're the host
	else:
		CarryRegistry.hold_request_pickup.rpc_id(1, who, name)

func get_interaction_prompt(player: Node) -> String:
	if is_carried():
		return item_name + " (carried)"
	if can_pick_up:
		return "Pick up " + item_name
	return "Push " + item_name

func can_interact(player: Node) -> bool:
	return can_pick_up or true   # pushable props are always interactable

# --- host-side hold application (called by CarryRegistry) -----------------

## Apply a hold: this prop is now carried by `holder`. Called by CarryRegistry
## on the host; replicated to clients via hold_begin.rpc.
func _apply_hold(holder_id_arg: int) -> void:
	holder_id = holder_id_arg
	var holder := _player_node(holder_id_arg)
	var offset := get_carry_offset()
	if holder != null:
		set_carry_mode(holder as Node3D, offset)
	else:
		set_carry_mode(null, Vector3.ZERO)

## Release the hold. `threw` true = apply launch velocity.
func _release_hold(threw: bool, launch: Vector3 = Vector3.ZERO) -> void:
	holder_id = 0
	clear_carry_mode(launch)

# --- push (non-pickupable props) ------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_push(who: int = 1) -> void:
	if not multiplayer.is_server() or is_carried():
		return
	var player := _player_node(who)
	if player == null:
		return
	var direction: Vector3 = global_position - player.global_position
	direction.y = 0.0
	if direction == Vector3.ZERO:
		direction = Vector3.RIGHT
	apply_body_impulse(direction.normalized(), mass * 2.2)

var _last_push: float = -1000.0

# --- out-of-bounds home return (host) -------------------------------------

func _process(delta: float) -> void:
	# Host: return out-of-bounds props home (runs alongside BodyPhys physics).
	if multiplayer.is_server() and not is_carried() and global_position.y < -10.0:
		global_transform = _home
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false

# --- helpers --------------------------------------------------------------

func _sender_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return 1 if sender == 0 else sender

func _holder_peer_id(holder: Node) -> int:
	if holder == null:
		return 1
	var id := str(holder.name).to_int()
	return id if id != 0 else 1

func _player_node(id: int) -> Node:
	var world := get_tree().get_first_node_in_group("game_world")
	return world.get_node_or_null("Players/" + str(id)) if world != null else null
