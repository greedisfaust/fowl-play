class_name Interactable
extends Node

## The one interactable contract (R1).
##
## Added as a child Node component of any object a player can aim at and act on:
## buttons, terminals, plaques, props, limp players, the elevator GO button,
## bet-panel keys. Focus, prompts, glow, and hands all route through
## `Interactable.find(collider)` — one lookup, one prompt source, one highlight
## rule, no `if target is PressButton / elif TextTerminal` chains.
##
## GDScript has single inheritance, so this is a component, not a base class.
## The component's interact()/get_interaction_prompt()/can_interact() delegate
## to its owner (the parent node) when the owner implements them, which lets
## existing objects keep their interact logic while exposing the single contract.

enum Kind { USE, GRAB, BOTH }

signal interacted(player: Node)   # emitted when a player successfully interacts

@export var kind: Kind = Kind.USE        # what verb applies to this object
@export var enabled: bool = true         # whether interaction is allowed right now

var _owner: Node = null                  # the node this component belongs to (get_parent)

func _enter_tree() -> void:
	_owner = get_parent()

# --- the contract (delegates to owner when the owner implements it) ----------

func can_interact(player: Node) -> bool:
	if not enabled:
		return false
	if _owner != null and _owner.has_method("can_interact"):
		return bool(_owner.can_interact(player))
	return true

func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if _owner != null and _owner.has_method("interact"):
		_owner.interact(player)
	interacted.emit(player)

func get_interaction_prompt(player: Node) -> String:
	if _owner != null and _owner.has_method("get_interaction_prompt"):
		return _owner.get_interaction_prompt(player)
	return "Interact"

# --- lookup ------------------------------------------------------------------

## Find the Interactable component for a raycast collider by walking up the
## parent chain. Returns null if nothing in the chain hosts an Interactable.
static func find(collider: Node) -> Interactable:
	var n: Node = collider
	while n != null:
		for child in n.get_children():
			if child is Interactable:
				return child as Interactable
		n = n.get_parent()
	return null
