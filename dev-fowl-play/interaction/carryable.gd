class_name Carryable extends RefCounted

## The carried-body contract. Anything that can be picked up, carried,
## dropped, and thrown implements these methods directly — GDScript has no
## interfaces, so `Carryable` documents the contract and `Interactable.can()`
## is not used here (carryable is a narrower, pickup-specific contract).
##
## The Carrier component holds a reference to whatever implements this and
## routes pickup/drop/throw through it, so items and downed players share
## ONE code path — no `if item vs player` branches.

# Emitted when the holder changes (pickup or release).
signal carrier_changed(holder: Node)

# Called by Carrier when this body is picked up.
# Implement to disable collision, snap to holder, hide highlight, etc.
func pickup(holder: Node) -> void:
	pass

# Called by Carrier on drop or throw.
# `throw` true = apply launch velocity; `direction`/`speed` only
# meaningful when throw is true.
func release(throw: bool, direction: Vector3, speed: float) -> void:
	pass

# True iff this body is currently carried.
func is_carried() -> bool:
	return false

# Offset from the holder's origin to place this body while carried.
# Items: single-hand offset in front of the head.
# Downed players: both-hands offset (lower, centered).
func get_carry_offset() -> Vector3:
	return Vector3.ZERO

# Throw speed for a given charge (0..1). Implement per body type.
func get_throw_speed(charge: float) -> float:
	return 0.0
