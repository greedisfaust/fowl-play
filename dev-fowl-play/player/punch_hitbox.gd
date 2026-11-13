extends Area3D

class_name PunchHitbox

## Punch hitbox: spawned by Combat on the host, lives briefly, applies effects
## to whatever it overlaps via body_entered. Quick punch = jiggle only; charged
## punch = ragdoll + strong push. Then queue_free.
##
## Authority: host only. Clients never spawn or simulate hitboxes.

@export var is_quick: bool = false
@export var charge: float = 0.0
@export var size_m: float = 0.9
@export var duration_s: float = 0.10
@export var owner_id: int = 0
@export var push_speed: float = 0.0
@export var ragdoll_seconds: float = 0.0

var _timer: float = 0.0
var _hit: Array = []   # bodies already hit by this hitbox (avoid double-apply)

func _ready() -> void:
	add_to_group("punch_hitbox")
	body_entered.connect(_on_body_entered)
	# Shape: sphere sized by size_m
	var shape := SphereShape3D.new()
	shape.radius = size_m
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	# Layers: hitbox IS on PUNCH_HITBOX layer; hits healthy players, limp bodies, props
	collision_layer = PhysicsLayers.LAYER_PUNCH_HITBOX
	collision_mask = PhysicsLayers.MASK_PUNCH_HITBOX
	# VFX flash on spawn (mesh flash + color by punch type)
	var flash := MeshInstance3D.new()
	flash.mesh = SphereMesh.new()
	flash.scale = Vector3.ONE * size_m * 1.2
	flash.material_override = StandardMaterial3D.new()
	flash.material_override.albedo_color = Color(1.0, 0.6, 0.2) if is_quick else Color(1.0, 0.2, 0.2)
	add_child(flash)
	# Short-lived flash tween: shrink then free
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ZERO, 0.05)
	tw.finished.connect(func(): flash.queue_free())

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= duration_s:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Never hit yourself
	var owner_node := _get_owner_node()
	if owner_node != null and owner_node.is_ancestor_of(body):
		return
	# Avoid double-hit
	if _hit.has(body):
		return
	_hit.append(body)

	# Walk up to player root (named by peer ID, e.g. "2", "3")
	var root: Node = body
	while root != null and not str(root.name).match(r"^\d+$"):
		root = root.get_parent()
	if root == null:
		root = body

	var bp := root.get_node_or_null("BodyPhys")
	var dir: Vector3 = (root.global_position - global_position).normalized()
	if dir == Vector3.ZERO:
		dir = -global_basis.z

	if is_quick:
		# Quick punch: jiggle only, no ragdoll, no push
		var ps := root.get_node_or_null("PlayerState")
		if ps != null:
			# Jiggle applied by player.gd; trigger via hit notice
			pass
		if bp is BodyPhys:
			bp.apply_body_impulse(dir, PhysicsTuning.QUICK_PUNCH_JIGGLE_SPEED_MPS)
	else:
		# Charged punch: ragdoll + strong push
		if bp is BodyPhys:
			bp.set_limp_mode(ragdoll_seconds)
			bp.apply_launch(dir, push_speed)
		var ps := root.get_node_or_null("PlayerState")
		if ps != null:
			ps.transition_to(PlayerState.State.LIMP)
			ps.set_limp_phase(PlayerState.LimpPhase.LIMP_GROUND)
			ps.start_limp_timer(ragdoll_seconds)

	# Prop hit: physics push (regardless of quick/charged)
	if body is PhysicsProp:
		var pdir: Vector3 = (body.global_position - global_position).normalized()
		if pdir == Vector3.ZERO:
			pdir = -global_basis.z
		body.apply_body_impulse(pdir, push_speed if push_speed > 0.0 else PhysicsTuning.PROP_MASS_KG * 2.2)

func _get_owner_node() -> Node:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null:
		return world.get_node_or_null("Players/" + str(owner_id))
	return null
