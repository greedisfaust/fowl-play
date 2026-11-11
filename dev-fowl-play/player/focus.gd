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
	var t: Node = ray.get_collider() if now_active and ray.is_colliding() else null
	if t != null and not Interactable.can(t):
		t = null
	# Only hover/glow players who are stunned or being carried — never healthy players
	if t != null and t.has_method("is_stunned") and not t.is_stunned():
		t = null
	var on := t != null
	if t != target:
		target = t
	# Prompt text via the polymorphic contract — no type-based special-casing
	prompt = ""
	if target != null:
		prompt = target.get_interaction_prompt(player)
	active = now_active
	held_name = overlay_held_name
