class_name Carrier extends RefCounted

## "What a player is holding." Routes pickup/drop/throw through CarryRegistry
## (R2: one carry model for items and limp players). Client-side bookkeeping
## + charge UI; the host owns the hold relationship and applies it via
## BodyPhys. Carrier never holds replicated state — it asks the host.
##
## Public RPCs are NOT called by Carrier itself; it sends hold_request_* to
## the host (peer 1), and CarryRegistry applies + replicates hold_begin /
## hold_end / hold_launch to all peers.

signal released(threw: bool)    # emitted when we let go of what we carry

# What we're holding; null when empty. Variant-typed because items (PhysicsProp)
# and limp players both implement the Carryable contract.
var carried: Variant = null     # what we're holding; null when empty
var charge_started: float = -1.0
var charge_held: bool = false
var _owner: Node3D = null        # the player that owns this Carrier

# Call once from player.gd's _ready to mirror registry holds locally.
func bind_registry() -> void:
	CarryRegistry.hold_begin.connect(_on_hold_begin)
	CarryRegistry.hold_end.connect(_on_hold_end)

func _on_hold_begin(holder_id: int, held_id: Variant) -> void:
	if holder_id != _owner_peer_id():
		return
	var node: Node = CarryRegistry.node_for_held(held_id)
	if node != null:
		carried = node
		# Client-side prediction: lock the held body to our head every frame
		# so the carrier feels zero lag while holding.
		var bp: Node = node.get_node_or_null("BodyPhys")
		if bp != null and bp.has_method("set_carry_mode"):
			var offset: Vector3 = node.call("get_carry_offset") if node.has_method("get_carry_offset") else Vector3.ZERO
			bp.call("set_carry_mode", _owner as Node3D, offset)

func _on_hold_end(holder_id: int, held_id: Variant, threw: bool) -> void:
	if holder_id != _owner_peer_id():
		return
	carried = null
	# Client-side prediction: release the local carry-mode lock.
	var node: Node = CarryRegistry.node_for_held(held_id)
	if node != null:
		var bp: Node = node.get_node_or_null("BodyPhys")
		if bp != null and bp.has_method("clear_carry_mode"):
			bp.call("clear_carry_mode")

const CHARGE_MS := int(1000.0 * PhysicsTuning.THROW_FULL_CHARGE_SECONDS)  # full-throw charge time (client UI)

# True iff we're holding something (item or limp player).
func is_carrying() -> bool:
	return carried != null

# Record that we're now holding `target`. Returns false if already carrying.
# Replication is the caller's responsibility (CarryRegistry holds the state).
func pickup(target: Variant) -> bool:
	if carried != null:
		return false
	carried = target
	charge_started = -1
	charge_held = false
	if carried != null and carried.has_method("pickup"):
		carried.pickup(_owner)
	return true

# Begin charging a throw (drives the throw-meter UI).
func start_charge() -> void:
	if carried == null or charge_held:
		return
	charge_held = true
	charge_started = Time.get_ticks_msec() / 1000.0

# Release a held charge. Returns the charge 0..1, or -1 if none was held.
# Note: the host re-times the charge on release (R6); this value is UI only.
func release_charge() -> float:
	if not charge_held:
		return -1.0
	charge_held = false
	var held_ms := (Time.get_ticks_msec() / 1000.0 - charge_started) * 1000.0
	charge_started = -1
	return clampf(float(held_ms) / CHARGE_MS, 0.0, 1.0)

# Clear what we're carrying (drop or throw). Does NOT replicate — caller
# tells CarryRegistry. Emits released(threw) for UI/hands.
func drop(threw: bool = false) -> void:
	carried = null
	charge_started = -1
	charge_held = false
	released.emit(threw)

# Direction we'd throw from, based on where the holder is looking.
func throw_direction() -> Vector3:
	if _owner != null and _owner.has_node("Head"):
		return -(_owner.get_node("Head") as Node3D).global_basis.z
	return Vector3.FORWARD

# Ask the host to pick up `target`. Caller must validate can_pickup first.
func request_pickup(target: Variant) -> void:
	if carried != null:
		return
	var held_id: Variant = _held_id(target)
	if held_id == null or (held_id is int and held_id == 0):
		return
	var holder_id := _owner_peer_id()
	if holder_id == 0:
		holder_id = 1
	if holder_id == 1:
		CarryRegistry.hold_request_pickup(holder_id, held_id)   # local call when we're the host
	else:
		CarryRegistry.hold_request_pickup.rpc_id(1, holder_id, held_id)

# Ask the host to drop what we carry. threw=false for plain drop.
func request_drop(threw: bool = false) -> void:
	if carried == null:
		return
	var holder_id := _owner_peer_id()
	if holder_id == 0:
		holder_id = 1
	if holder_id == 1:
		CarryRegistry.hold_request_drop(holder_id, threw)   # local call when we're the host
	else:
		CarryRegistry.hold_request_drop.rpc_id(1, holder_id, threw)

# Ask the host to throw with client-supplied aim direction + charge.
func request_throw(direction: Vector3, charge: float) -> void:
	if carried == null:
		return
	var holder_id := _owner_peer_id()
	if holder_id == 0:
		holder_id = 1
	if holder_id == 1:
		CarryRegistry.hold_request_throw(holder_id, direction, charge)   # local call when we're the host
	else:
		CarryRegistry.hold_request_throw.rpc_id(1, holder_id, direction, charge)

# --- private helpers --------------------------------------------------------

func _owner_peer_id() -> int:
	if _owner == null:
		return 0
	var id := str(_owner.name).to_int()
	return id if id != 0 else 1

func _held_id(held: Variant) -> Variant:
	# Players are named by peer id at spawn (world.gd). Props use their set name.
	# Names replicate across peers; instance ids do not.
	if held is Node:
		var node: Node = held as Node
		if str(node.name).match(r"^\d+$"):
			return node.name.to_int()
		return node.name
	return 0
