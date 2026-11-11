class_name Carrier extends RefCounted

## "What a player is holding." Client-side bookkeeping + charge UI for
## whatever the player carries. The actual replication (who holds what)
## stays with the carried object: PhysicsProp replicates via
## `_sync_holder.rpc` (server-mediated `request_use`/`request_release`),
## and downed players replicate via `_pickup_request.rpc` /
## `_launch_carried_player.rpc`. Carrier never calls RPCs itself — it
## just holds the `carried` reference and charge state so input, UI, and
## state queries share ONE code path instead of `_carry_mode` /
## `_carried_item` / `_carried_player_id` scattered logic.
##
## Anything carried implements `Carryable` (`get_carry_offset`,
## `get_throw_speed`). In Phase 3 that's items (PhysicsProp); downed
## players join in Phase 4 when Player implements Carryable.

signal released(threw: bool)    # emitted when we let go of what we carry

# What we're holding; null when empty. Variant-typed because GDScript
# single inheritance means PhysicsProp (RigidBody3D) and Player
# (CharacterBody3D) can't both extend Carryable — they duck-type the
# Carryable contract instead.
var carried: Variant = null     # what we're holding; null when empty
var charge_started: float = -1.0
var charge_held: bool = false
var owner: Node3D = null        # the player that owns this Carrier

const CHARGE_MS := 1250.0       # how long a full-throw charge takes

# Preload PhysicsProp so `is_carrying_player` can tell items from players.
const PhysicsProp := preload("res://interaction/physics_prop.gd")

# True iff we're holding something (item or downed player).
func is_carrying() -> bool:
	return carried != null

# True iff what we're holding is a downed player (both-hands carry).
func is_carrying_player() -> bool:
	return carried != null and not (carried is PhysicsProp)

# Record that we're now holding `target`. Returns false if already carrying.
# Replication of the hold state is the caller's responsibility
# (prop.interact / _pickup_request.rpc).
func pickup(target: Variant) -> bool:
	if carried != null:
		return false
	carried = target
	charge_started = -1
	charge_held = false
	return true

# Begin charging a throw (drives the throw-meter UI).
func start_charge() -> void:
	if carried == null or charge_held:
		return
	charge_held = true
	charge_started = Time.get_ticks_msec()

# Release a held charge. Returns the charge 0..1, or -1 if none was held.
func release_charge() -> float:
	if not charge_held:
		return -1.0
	charge_held = false
	var held_ms := Time.get_ticks_msec() - charge_started
	charge_started = -1
	return clampf(float(held_ms) / CHARGE_MS, 0.0, 1.0)

# Clear what we're carrying (drop or throw). Does NOT replicate — caller
# handles `request_release.rpc_id` / `_launch_carried_player.rpc_id`.
func drop(threw: bool = false) -> void:
	carried = null
	charge_started = -1
	charge_held = false
	released.emit(threw)

# Direction we'd throw from, based on where the holder is looking.
func _throw_direction() -> Vector3:
	if owner != null and owner.has_node("Head"):
		return -owner.get_node("Head").global_basis.z
	return Vector3.FORWARD
