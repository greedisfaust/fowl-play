extends Area3D

class_name ParryBarrier

## Parry barrier: a shield cylinder around the parrying player. The HOST copy judges
## parries (try_parry); client copies are visual only. Despawned by Combat.

@export var owner_id: int = 0
@export var radius_m: float = 1.2
@export var height_m: float = 2.0
var combat: Combat = null        # set by Combat before add_child (host copy only)
var visual_only := false         # client copies: show the shield, never judge

func _ready() -> void:
	add_to_group("parry_barrier")
	position = Vector3(0, height_m * 0.5, 0)   # centered on the body, not on the feet
	_fit_shape()
	_fit_visual()
	if visual_only:
		monitoring = false
		monitorable = false
		collision_layer = 0
		collision_mask = 0
		return
	collision_layer = PhysicsLayers.LAYER_PARRY_BARRIER
	collision_mask = PhysicsLayers.MASK_PARRY_BARRIER | PhysicsLayers.LAYER_PUNCH_HITBOX
	area_entered.connect(_on_area_entered)

func _fit_shape() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		add_child(col)
	var shape := CylinderShape3D.new()   # fresh resource: the scene's one is shared by every instance
	shape.radius = radius_m
	shape.height = height_m
	col.shape = shape

func _fit_visual() -> void:
	var mi := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		add_child(mi)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius_m
	mesh.bottom_radius = radius_m
	mesh.height = height_m
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.6)   # more visible than 0.3 alpha
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA   # use alpha blending
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("punch_hitbox"):
		try_parry(area)

## Returns true if this barrier just blocked the punch. Called from both the
## barrier's area_entered and the hitbox's body_entered, so order doesn't matter.
## One barrier can block multiple punches during the parry window.
func try_parry(hitbox: Node) -> bool:
	if visual_only:
		return false
	if hitbox == null or not is_instance_valid(hitbox):
		return false
	if int(hitbox.get("owner_id")) == owner_id:
		return false   # your own punch can't trip your own shield
	if combat != null:
		combat.on_parry_success(hitbox)
	return true
