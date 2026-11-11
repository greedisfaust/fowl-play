class_name Interactable
extends Node3D

## The one interactable contract. Anything a player can aim at and use implements
## interact(player) and get_interaction_prompt(player) — on this class, on a child
## component, or by duck-typing on the node itself. Use Interactable.can(node) to
## check; everything in player focus, prompts, glow, and hands routes through it.
## No more scattered has_method("interact") checks.

signal interacted(player: Node)   # emitted when a player successfully interacts

@export var enabled := true

# Called when a player interacts with this object. Override in subclass.
func interact(player: Node) -> void:
	push_warning("Interactable.interact() not implemented on " + str(self) + " — override in subclass")

# Text shown on the interaction overlay while looking at this object.
func get_interaction_prompt(player: Node) -> String:
	return "Interact"

# Whether this player is allowed to interact right now (range, cooldown, etc.)
func can_interact(player: Node) -> bool:
	return enabled

# True iff `node` exposes both interact(player) and get_interaction_prompt(player).
# GDScript has no interfaces, so this is the explicit contract check used everywhere.
static func can(node: Node) -> bool:
	return node != null and node.has_method("interact") and node.has_method("get_interaction_prompt")
