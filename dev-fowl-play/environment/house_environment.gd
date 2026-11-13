extends Node3D
## Deterministic dressing built on every peer; only PhysicsProp simulates on host.
const Prop := preload("res://interaction/physics_prop.gd")
const Plaque := preload("res://interaction/lore_plaque.gd")
const ASSET_ROOT := "res://assets/kenney/furniture/"
const BRASS := Color("bca166")
const FLOOR_SHADER := """
shader_type spatial;
varying vec3 world;
uniform vec4 base : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform bool marble = false;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 tile = floor(world.xz * (marble ? vec2(0.65) : vec2(2.0, 0.4)));
	float shade = mod(tile.x + tile.y, 2.0) * 0.1;
	float wear = sin(world.x * 31.0 + sin(world.z * 9.0)) * 0.025;
	vec2 grout = fract(world.xz * (marble ? vec2(0.65) : vec2(2.0, 0.4)));
	float joint = step(0.98, max(grout.x, grout.y));
	ALBEDO = base.rgb * (0.87 + shade + wear - joint * 0.35);
	ROUGHNESS = marble ? 0.28 : 0.92;
}
"""
var _world: Node3D = null
var _props: Node3D = null

func _ready() -> void:
	_world = get_parent()
	_props = Node3D.new()
	_props.name = "Props"
	add_child(_props)
	_casino()
	_rest()
	_sky()

func _material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.75
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, solid := true, emission := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color, emission)
	node.mesh = mesh
	node.position = pos
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		node.add_child(body)
	return node

func _text(parent: Node3D, text: String, pos: Vector3, size: int, color := Color.WHITE, yaw := 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.rotation.y = yaw
	label.pixel_size = 0.003
	label.font_size = size
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)
	return label

func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	parent.add_child(light)

func _remove_walls(room: Node3D) -> void:
	for wall_name in ["WallN", "WallS", "WallE", "WallW", "OmniLight3D"]:
		var old := room.get_node_or_null(wall_name)
		if old != null:
			room.remove_child(old)
			old.queue_free()

func _floor(room: Node3D, color: Color, marble := false) -> void:
	var shader := Shader.new()
	shader.code = FLOOR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base", color)
	material.set_shader_parameter("marble", marble)
	room.get_node("Floor").material_override = material

func _end_wall(parent: Node3D, width: float, height: float, z: float, floor_y: float, door: bool, color: Color) -> void:
	if not door:
		_box(parent, Vector3(width, height, 0.24), Vector3(0, floor_y + height / 2, z), color)
	else:
		var side_width := (width - 8.0) / 2.0
		for side in [-1.0, 1.0]:
			_box(parent, Vector3(side_width, height, 0.24), Vector3(side * (4.0 + side_width / 2), floor_y + height / 2, z), color)
		if height > 3.1:
			_box(parent, Vector3(8, height - 3.1, 0.24), Vector3(0, floor_y + 3.1 + (height - 3.1) / 2, z), color)

func _shell(room: Node3D, width: float, depth: float, height: float, floor_y: float, fancy := false, north_door := false) -> void:
	var wall := Color("243b36") if fancy else Color("77766b")
	var trim := BRASS if fancy else Color("444a43")
	_end_wall(room, width, height, -depth / 2, floor_y, north_door, wall)
	_end_wall(room, width, height, depth / 2, floor_y, not north_door, wall)
	_box(room, Vector3(width + 0.3, 0.2, depth + 0.3), Vector3(0, floor_y + height + 0.1, 0), Color("242e2c") if fancy else Color("585c52"))
	for side in [-1.0, 1.0]:
		var x: float = side * width / 2
		var window_width := depth * 0.4
		var end_width := (depth - window_width) / 2
		_box(room, Vector3(0.24, 1.1, depth), Vector3(x, floor_y + 0.55, 0), wall)
		_box(room, Vector3(0.24, height - 2.6, depth), Vector3(x, floor_y + 2.6 + (height - 2.6) / 2, 0), wall)
		for end in [-1.0, 1.0]:
			_box(room, Vector3(0.24, 1.5, end_width), Vector3(x, floor_y + 1.85, end * (window_width + end_width) / 2), wall)
		_box(room, Vector3(0.06, 1.5, window_width), Vector3(x, floor_y + 1.85, 0), Color(0.3, 0.51, 0.58, 0.18))
		for z in [-window_width / 2, 0.0, window_width / 2]:
			_box(room, Vector3(0.32, 1.65, 0.08), Vector3(x, floor_y + 1.85, z), trim)
		for y in [1.05, 2.65]:
			_box(room, Vector3(0.34, 0.08, window_width + 0.12), Vector3(x, floor_y + y, 0), trim)
		for y in [0.12, height - 0.15]:
			_box(room, Vector3(0.3, 0.1, depth), Vector3(x - side * 0.03, floor_y + y, 0), trim, false)
		_city(room, side * (width / 2 + 8), depth, floor_y)

func _city(room: Node3D, x: float, depth: float, floor_y: float) -> void:
	for i in 7:
		var height := 3.0 + float((i * 7) % 9)
		var z := (i - 3) * depth / 6
		_box(room, Vector3(3.5, height, 3.5), Vector3(x, floor_y + height / 2 - 2, z), Color("26333e"), false)
		for row in 4:
			_box(room, Vector3(0.02, 0.25, 0.65), Vector3(x - signf(x) * 1.76, floor_y + row * 0.8, z), Color("b99663"), false, true)

func _asset(parent: Node3D, asset_name: String, pos: Vector3, height: float, yaw := 0.0) -> Node3D:
	var scene := load(ASSET_ROOT + asset_name + ".glb") as PackedScene
	var model := scene.instantiate() as Node3D
	var bounds := _bounds(model, Transform3D.IDENTITY)
	var factor := height / maxf(bounds.size.y, 0.01)
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation.y = yaw
	parent.add_child(pivot)
	model.scale *= factor
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	pivot.add_child(model)
	return pivot

func _bounds(node: Node3D, transform: Transform3D) -> AABB:
	var combined := transform * node.transform
	var bounds := AABB()
	if node is MeshInstance3D:
		bounds = combined * node.get_aabb()
	for child in node.get_children():
		if child is Node3D:
			var child_bounds := _bounds(child, combined)
			if child_bounds.size != Vector3.ZERO:
				bounds = child_bounds if bounds.size == Vector3.ZERO else bounds.merge(child_bounds)
	return bounds

func _furniture(room: Node3D, asset_name: String, pos: Vector3, height: float, footprint: Vector3, yaw := 0.0) -> void:
	var model := _asset(room, asset_name, pos, height, yaw)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = footprint
	collision.shape = shape
	collision.position.y = footprint.y / 2
	body.add_child(collision)
	model.add_child(body)

func _prop(item_name: String, pos: Vector3, size: Vector3, color: Color, pickup := true, asset_name := "") -> PhysicsProp:
	var prop := Prop.new()
	prop.name = "Prop%02d" % _props.get_child_count()
	prop.item_name = item_name
	prop.can_pick_up = pickup
	prop.mass = PhysicsTuning.PROP_MASS_KG if pickup else PhysicsTuning.LARGE_PROP_MASS_KG
	prop.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	prop.add_child(collision)
	if asset_name == "":
		_small_prop_model(prop, item_name, size, color)
	else:
		_asset(prop, asset_name, Vector3(0, -size.y / 2, 0), size.y)
	_props.add_child(prop)
	return prop

func _small_prop_model(prop: Node3D, item_name: String, size: Vector3, color: Color) -> void:
	if "cup" in item_name.to_lower():
		var cup := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size.x / 2
		cylinder.bottom_radius = size.x * 0.4
		cylinder.height = size.y
		cylinder.material = _material(color)
		cup.mesh = cylinder
		prop.add_child(cup)
		var handle := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.025
		ring.outer_radius = 0.04
		ring.material = _material(color)
		handle.mesh = ring
		handle.position.x = size.x / 2
		handle.rotation.z = PI / 2
		prop.add_child(handle)
		var coffee := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = size.x * 0.42
		disc.bottom_radius = disc.top_radius
		disc.height = 0.005
		disc.material = _material(Color("4a3325"))
		coffee.mesh = disc
		coffee.position.y = size.y / 2 + 0.001
		prop.add_child(coffee)
	elif "chip" in item_name.to_lower():
		for i in 6:
			var chip := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = size.x / 2
			cylinder.bottom_radius = size.x / 2
			cylinder.height = size.y / 6 * 0.85
			cylinder.material = _material(color if i % 2 == 0 else BRASS)
			chip.mesh = cylinder
			chip.position.y = -size.y / 2 + (i + 0.5) * size.y / 6
			prop.add_child(chip)
	else:
		_box(prop, size, Vector3.ZERO, color, false)

func _notice(room: Node3D, title: String, short_text: String, body: String, pos: Vector3, yaw := 0.0) -> void:
	var plaque := Plaque.new()
	plaque.title = title
	plaque.body = body
	plaque.position = pos
	plaque.rotation.y = yaw
	room.add_child(plaque)
	_box(plaque, Vector3(1.55, 1.0, 0.045), Vector3.ZERO, Color("ddd0a6"), false)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.55, 1.0, 0.06)
	collision.shape = shape
	plaque.add_child(collision)
	_text(plaque, title + "\n\n" + short_text + "\n\n[E] READ", Vector3(0, 0, 0.03), 25, Color("26352e"))

func _casino() -> void:
	var room: Node3D = _world.get_node("Casino")
	_floor(room, Color("b3ada0"), true)
	_shell(room, 30, 30, 5.2, 0.5, true, true)
	var cross: Node3D = room.get_node("ChickenCross")
	var cards: Node3D = room.get_node("Cluckjack")
	cross.position = Vector3(-5, 0.5, 4)
	cards.position = Vector3(5, 0.5, 4)
	cross.rotation.y = PI
	cards.rotation.y = PI
	for table in [cross, cards]:
		table.get_node("Counter").material_override = _material(Color("43212b"))
		for side in [-1.0, 1.0]:
			_box(table, Vector3(0.025, 0.035, 1.6), Vector3(side * 1.49, 0.93, 0), BRASS, false)
			_box(table, Vector3(3, 0.035, 0.025), Vector3(0, 0.93, side * 0.79), BRASS, false)
	_box(room, Vector3(4.4, 0.035, 27), Vector3(0, 0.52, -0.5), Color("622b38"), false)
	for side in [-1.0, 1.0]:
		_box(room, Vector3(0.04, 0.04, 27), Vector3(side * 2.2, 0.53, -0.5), BRASS, false)
		for z in [-12, -5, 5, 12]:
			_box(room, Vector3(0.6, 4.9, 0.6), Vector3(side * 14.6, 2.95, z), Color("33443c"))
			for y in [0.85, 5.0]:
				_box(room, Vector3(0.75, 0.16, 0.75), Vector3(side * 14.6, y, z), BRASS)
			_light(room, Vector3(side * 13.5, 3.8, z), Color("ffd6a0"), 1.7, 10)
		_furniture(room, "tableCoffee", Vector3(side * 10.5, 0.5, -3), 0.55, Vector3(1.2, 0.55, 0.7))
		_furniture(room, "loungeSofa", Vector3(side * 12.5, 0.5, -3), 1.15, Vector3(2.6, 0.75, 1.0), side * PI / 2)
		_asset(room, "plantSmall1", Vector3(side * 12, 0.5, -10), 1.6)
		_asset(room, "lampRoundFloor", Vector3(side * 12.5, 0.5, 8), 2.2)
		_prop("Velvet lounge chair", room.position + Vector3(side * 10.5, 1, -1.6), Vector3(0.75, 1, 0.75), Color.WHITE, false, "loungeChair")
	for z in [-8, 2, 11]:
		_box(room, Vector3(0.06, 0.55, 0.06), Vector3(0, 5.0, z), BRASS, false)
		_box(room, Vector3(3.4, 0.12, 1.8), Vector3(0, 4.68, z), BRASS, false)
		for x in [-1.4, 0.0, 1.4]:
			_box(room, Vector3(0.3, 0.35, 0.3), Vector3(x, 4.45, z), Color("ffe3ac"), false, true)
		_light(room, Vector3(0, 4.1, z), Color("ffdcaa"), 2.4, 14)
	_box(room, Vector3(9, 2.0, 0.15), Vector3(0, 3.2, 14.75), Color("162f2b"), false)
	_text(room, "THE GILDED COOP", Vector3(0, 3.5, 14.6), 230, Color("f0d39b"), PI)
	_text(room, "YOUR LUCK. OUR HOUSE.", Vector3(0, 2.75, 14.6), 80, BRASS, PI)
	for side in [-1.0, 1.0]:
		_box(room, Vector3(3.6, 1.05, 0.8), Vector3(side * 8, 1.025, 11), Color("432a2c"))
		_box(room, Vector3(3.8, 0.08, 1.0), Vector3(side * 8, 1.59, 11), BRASS)
		_asset(room, "kitchenCoffeeMachine", Vector3(side * 8, 1.63, 11), 0.65, PI)
		_text(room, "COMPLIMENTARY\nNOTHING ELSE IS", Vector3(side * 8, 2.7, 14.6), 70, BRASS, PI)
	_notice(room, "THE HOUSE RULES", "ONE WALLET. TEN DAYS.\nFive minutes to make quota.", "Welcome to the Gilded Coop.\n\nEvery stake leaves the SHARED wallet. Every payout returns to it. Reach the displayed quota before the five-minute bell.\n\nOnce quota is met, gather everyone in the lift and press its button to leave early. The first missed quota spends your only courtesy life and resets the wallet to half its day-start balance. A second miss ends the contract badly. Meet day ten's quota to win.", Vector3(3.1, 2, -14.82))
	_notice(room, "A WORD FROM THE DEALER", "CLUCKJACK\nHIT for courage. STAND for sense.", "Choose a wager on the keypad, then DEAL. Only the bettor may HIT or STAND.\n\nAces are 1 or 11. Face cards are 10. Get closer to 21 than the House without going over. The House stands on all 17s.\n\nGross returns: win 2x, two-card natural 2.5x, tie 1x. Odd-stake half coins round down. The bell or a departing bettor automatically stands the hand.\n\nThe hidden card belongs to the House until the decision is made.", Vector3(8.5, 2, -14.82))
	_notice(room, "WHY DID YOU CROSS?", "CHICKEN CROSS\nThe next lane is always tempting.", "Set a wager, then CROSS to risk the first lane. CROSS again to continue. CASHOUT banks the current multiplier. A car takes the whole stake.\n\nThe farther the chicken goes, the greater the danger and reward. Anyone may press CROSS or CASHOUT at this table. Agree with your friends before spending their supper.\n\nThe wallet and timer never stop while you argue.", Vector3(-8.5, 2, -14.82))
	for side in [-1.0, 1.0]:
		_prop("Complimentary cup", room.position + Vector3(side * 10.5, 1.18, -3), Vector3(0.15, 0.22, 0.15), Color("eee3c7"))
		_prop("House chip stack", room.position + Vector3(side * 9.9, 1.14, -3), Vector3(0.16, 0.14, 0.16), Color("b05551"))
	_prop("Lucky brass paperweight", room.position + Vector3(10.9, 1.18, -3), Vector3(0.18, 0.18, 0.18), BRASS)
	_prop("Room-service crate", room.position + Vector3(-11, 0.8, 8), Vector3(0.6, 0.6, 0.6), Color.WHITE, false, "cardboardBoxClosed")
	_prop("Dealer's stool", room.position + Vector3(9, 1.1, 6), Vector3(0.55, 1.2, 0.55), Color.WHITE, false, "stoolBar")

func _rest() -> void:
	var room: Node3D = _world.get_node("Rest")
	_remove_walls(room)
	_floor(room, Color("646d65"))
	_shell(room, 12, 12, 3.4, 0)
	_text(room, "COURTESY BREAK", Vector3(0, 2.7, -5.8), 100, Color("d7d7b8"))
	_text(room, "The House can wait. The debt cannot.", Vector3(0, 2.32, -5.8), 36, Color("b4bfae"))
	_box(room, Vector3(2.5, 0.07, 0.5), Vector3(0, 3.25, 0), Color("d4e3cd"), false, true)
	_light(room, Vector3(0, 2.8, 0), Color("cee6d5"), 2.0, 13)
	_furniture(room, "tableCoffee", Vector3(-4, 0, -3), 0.6, Vector3(1.4, 0.6, 0.7))
	_asset(room, "kitchenCoffeeMachine", Vector3(-4, 0.6, -3), 0.48)
	for z in [-1.8, 0, 1.8]:
		_furniture(room, "chair", Vector3(-4.7, 0, z), 0.9, Vector3(0.5, 0.9, 0.5), PI / 2)
	_notice(room, "STAFF MEMO / 04", "The courtesy is not a refund.\nPlease keep the lift clear.", "Guests keep asking where the money went.\n\nAfter a missed quota, the courtesy resets your wallet to HALF what you had at the start of that day. The next quota is still based on that day-start balance. The House offers this only once.\n\nRead the run status board. Gather everyone in the lift and press NEXT DAY when ready.\n\nThe coffee is complimentary. The cups are not collateral.", Vector3(0, 1.6, -5.82))
	_prop("Break-room cup", room.position + Vector3(-3.5, 0.75, -3), Vector3(0.15, 0.22, 0.15), Color("b8c5ad"))

func _sky() -> void:
	var environment: Environment = _world.get_node("WorldEnvironment").environment
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("121d35")
	sky_material.sky_horizon_color = Color("94766c")
	sky_material.ground_bottom_color = Color("101b28")
	sky_material.ground_horizon_color = Color("94766c")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8b9ea7")
	environment.ambient_light_energy = 0.35
	_world.get_node("DirectionalLight3D").light_energy = 0.35
