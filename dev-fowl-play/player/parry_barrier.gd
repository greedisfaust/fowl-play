extends Area3D

class_name ParryBarrier

## Parry barrier: spawned by Combat around the parrying player. Detects incoming
## PunchHitbox areas via area_entered; on detection, triggers parry success
## (punch cancelled, puncher recoils). Despawns when parry ends.
##
## Authority: host only.

@export var owner_id: int = 0
@export var radius_m: float = 1.2
@export var height_m: float = 2.0
var combat: Combat = null   # set by Combat._spawn_barrier()

var _timer: float = 0.0
var _active: bool = true
var _parried: bool = false   # only parry once per barrier lifetime

func _ready() -> void:
	add_to_group("parry_barrier")
	area_entered.connect(_on_area_entered)
	# Shape: cylinder
	var shape := CylinderShape3D.new()
	shape.radius = radius_m
	shape.height = height_m
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	# Layers: barrier IS on PARRY_BARRIER layer; detects PUNCH_HITBOX
	collision_layer = PhysicsLayers.LAYER_PARRY_BARRIER
	collision_mask = PhysicsLayers.MASK_PARRY_BARRIER
	# Visual: transparent cylinder so players can see the parry state
	var visual := MeshInstance3D.new()
	visual.mesh = CylinderMesh.new()
	visual.scale = Vector3.ONE * radius_m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_alpha = 0.3
	visual.material_override = mat
	add_child(visual)

func _process(delta: float) -> void:
	if not _active:
		queue_free()
		return

func _on_area_entered(area: Area3D) -> void:
	if _parried:
		return
	if not area.is_in_group("punch_hitbox"):
		return
	# Parry success: incoming punch hitbox cancelled
	_parried = true
	_active = false
	# Notify combat (passed by Combat._spawn_barrier)
	if combat != null and combat.has_method("on_parry_success"):
		combat.on_parry_success(area)
	queue_free()

func _get_owner_node() -> Node:
	var world := get_tree().get_first_node_in_group("game_world")
	if world != null:
		return world.get_node_or_null("Players/" + str(owner_id))
	return null
