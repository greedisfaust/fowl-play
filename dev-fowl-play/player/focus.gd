class_name Focus extends RefCounted

## Local "what am I looking at" component. Single source of truth for focus,
## hover/glow, and the interaction prompt. Uses Interactable.can() instead of
## duck-typed has_method("interact") so buttons, signs, terminals, props, and
## downed players all route through the one contract.

var target: Node = null       # currently focused interactable, or null
var prompt: String = ""       # prompt text for the focused target
var held_name: String = ""    # name of what we're holding (for HUD)
var active: bool = false      # whether we can interact right now

# Preload Interactable so we can call the static can() check.
const Interactable := preload("res://interaction/interactable.gd")

# Update focus each frame. Call from the owning player's _process.
# `player` is passed so prompts can be personalized (e.g. "Hand full" checks).
# `carrier` is passed so we know if we're holding a player (keep charge bar).
func update(
	ray: RayCast3D,
	player: Node,
	input_locked: bool,
	mouse_captured: bool,
	carrier: Object,
	overlay_held_name: String = "",
) -> void:
	var now_active := not input_locked and mouse_captured
	var hit: Node = ray.get_collider() as Node if now_active and ray.is_colliding() else null
	# Walk up from the raycast collider to find the Interactable component
	# (one lookup, one prompt source, one highlight rule).
	var found: Interactable = null
	if hit != null:
		found = Interactable.find(hit)
		if found != null:
			hit = found.get_parent()   # the node hosting the component
		else:
			hit = null
	# Only hover/glow GRAB targets that are limp or carried — healthy players
	# expose kind=GRAB only when limp, so no separate suppression hack is needed.
	if hit != null and str(hit.name).match(r"^\d+$"):
		var ps := hit.get_node_or_null("PlayerState")
		if ps != null and ps.has_method("is_limp") and not ps.is_limp():
			hit = null
	if hit != target:
		target = hit
	# Prompt text via the polymorphic contract — no type-based special-casing
	prompt = ""
	if target != null:
		var it := Interactable.find(target)
		prompt = it.get_interaction_prompt(player) if it != null else "Interact"
	active = now_active
	held_name = overlay_held_name
