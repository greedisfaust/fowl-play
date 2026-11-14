extends Area3D

class_name PunchHitbox

## Punch hitbox: spawned by Combat on the host, lives briefly, applies effects to
## whatever it overlaps via body_entered. Quick punch = jiggle only; charged punch =
## knockdown + strong shove (sent to the victim's own machine). Host only.

@export var is_quick: bool = false
@export var charge: float = 0.0
@export var size_m: float = 0.9
@export var duration_s: float = 0.10
@export var owner_id: int = 0
@export var origin: Vector3 = Vector3.ZERO     # where the puncher stood when it was thrown
@export var push_speed: float = 0.0
@export var ragdoll_seconds: float = 0.0
# The Combat that launched this hitbox, so a hit during the lunge can stop it.
# (Not @export: Combat extends RefCounted, which @export doesn't allow.)
var puncher_combat: Combat = null

const FLASH_SECONDS := 0.25   # how long the hit flash stays visible (the damage window is still duration_s)

var _timer: float = 0.0
var _hit: Array = []     # player roots / props already hit by this hitbox

func _ready() -> void:
	add_to_group("punch_hitbox")
	body_entered.connect(_on_body_entered)
	var shape := SphereShape3D.new()
	shape.radius = size_m
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	collision_layer = PhysicsLayers.LAYER_PUNCH_HITBOX
	# World layer included on purpose: if a player capsule is still on the default layer 1
	# the hitbox would never see it. Walls it overlaps are ignored in _on_body_entered.
	collision_mask = PhysicsLayers.MASK_PUNCH_HITBOX | PhysicsLayers.LAYER_WORLD_STATIC
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.2) if is_quick else Color(1.0, 0.2, 0.2)
	var flash := MeshInstance3D.new()
	flash.mesh = SphereMesh.new()
	flash.scale = Vector3.ONE * size_m * 1.2
	flash.material_override = mat
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ZERO, FLASH_SECONDS)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= duration_s:
		set_deferred("monitoring", false)   # damage window over; the flash keeps playing
	if _timer >= maxf(duration_s, FLASH_SECONDS):
		queue_free()

# Walk up to the player root (a node named by its peer id, e.g. "2"). null = not a player.
func _player_root(node: Node) -> Node:
	var n: Node = node
	while n != null and not str(n.name).is_valid_int():
		n = n.get_parent()
	return n

func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	var root := _player_root(body)
	if root != null:
		if str(root.name).to_int() == owner_id:
			return   # never hit yourself
		if _hit.has(root):
			return   # one hit per player, even if they have several bodies
		_hit.append(root)
		# Parry check here removes the race with the barrier's own area_entered.
		var barrier := root.get_node_or_null("ParryBarrier") as ParryBarrier
		if barrier != null and barrier.try_parry(self):
			return
		_hit_player(root as Node3D)
		# A hit during the lunge stops the lunge immediately: the puncher stops
		# where they landed the punch instead of carrying through to the end.
		var pc := puncher_combat
		if pc != null:
			pc.finish_lunge()
			# Tell the puncher's client to stop their lunge too (host's own copy
			# is handled above; remote punches need the client to stop).
			var puncher_node: Player = pc.owner as Player
			if puncher_node != null:
				var peer_id := puncher_node.get_multiplayer_authority()
				if peer_id == multiplayer.get_unique_id():
					# Our own copy: stop locally instead of RPCing to ourselves.
					puncher_node.combat.finish_lunge()
				else:
					puncher_node._net_lunge_stop.rpc_id(peer_id)
	elif body is PhysicsProp:
		if _hit.has(body):
			return
		_hit.append(body)
		_hit_prop(body as Node3D)

func _hit_player(root: Node3D) -> void:
	var victim_id := str(root.name).to_int()
	# Direction is mostly HORIZONTAL (puncher -> target) with a slight upward boost
	# so the victim flies in an arc instead of dropping like a stone.
	var dir: Vector3 = root.global_position - origin
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else _flat_forward()
	print("PUNCH HIT: victim=", victim_id, " quick=", is_quick, " speed=", push_speed)
	if is_quick:
		root.rpc("receive_jiggle", dir)
		return
	# Single knockdown path: the host decides and simulates; everyone mirrors via
	# _net_limp_begin / _net_limp_end reliable RPCs.
	root.call("host_knock_down", dir, push_speed, ragdoll_seconds)

func _hit_prop(body: Node3D) -> void:
	var pdir: Vector3 = body.global_position - origin
	pdir.y = 0.0
	pdir = pdir.normalized() if pdir.length() > 0.01 else _flat_forward()
	if body.has_method("apply_body_impulse"):
		body.apply_body_impulse(pdir, push_speed if push_speed > 0.0 else PhysicsTuning.PROP_MASS_KG * 2.2)

func _flat_forward() -> Vector3:
	var f: Vector3 = -global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD
