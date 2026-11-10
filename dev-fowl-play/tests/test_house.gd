extends Node

const Prop := preload("res://interaction/physics_prop.gd")
var failures := 0
var checks := 0
var world: Node3D

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [world.get_node("Players/1").get_rid()]
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func make_prop(pos: Vector3) -> PhysicsProp:
	var prop := Prop.new()
	prop.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 0.25, 0.25)
	shape.shape = box
	prop.add_child(shape)
	world.add_child(prop)
	return prop

func _ready() -> void:
	world = preload("res://world.tscn").instantiate()
	add_child(world)
	for i in 3:
		await get_tree().physics_frame
	check(InputMap.has_action("drop_item") and InputMap.has_action("throw_item"), "carry controls exist")
	check(get_tree().get_nodes_in_group("physics_props").size() >= 18, "rooms contain loose and pushable props")
	check(get_tree().get_nodes_in_group("lore_guides").size() == 7, "all seven lore guides are available")
	check(not ray(Vector3(0, 2, 0), Vector3(0, 5, 0)).is_empty(), "apartment roof collides")
	check(not ray(Vector3(100, 2, 0), Vector3(100, 8, 0)).is_empty(), "casino roof collides")
	check(not ray(Vector3(50, 2, 0), Vector3(50, 5, 0)).is_empty(), "rest roof collides")
	check(not ray(Vector3(0, 1.8, 0), Vector3(7, 1.8, 0)).is_empty(), "window panes block escapes")
	check(ray(Vector3(0, 1.5, 5.3), Vector3(0, 1.5, 6.3)).is_empty(), "apartment lift opening remains clear")
	check(ray(Vector3(100, 1.5, -14.4), Vector3(100, 1.5, -15.3)).is_empty(), "casino lift opening remains clear")
	check(world.get_node("Casino/ChickenCross").position.x < -3 and world.get_node("Casino/Cluckjack").position.x > 3, "tables leave central aisle")
	check(is_equal_approx(Prop.throw_speed(0), 3.0), "tap throw is gentle")
	check(is_equal_approx(Prop.throw_speed(1.25), 14.0), "full throw is fourteen")
	check(is_equal_approx(Prop.throw_speed(20), 14.0), "overcharge is capped")
	check(Prop.throw_speed(0.6) > Prop.throw_speed(0.2), "holding increases strength")
	check(is_equal_approx(Prop.throw_speed(-1), 3.0), "negative duration clamps")
	var a := make_prop(Vector3(-0.4, 0.8, -1.0))
	var b := make_prop(Vector3(0.4, 0.8, -1.0))
	var far := make_prop(Vector3(4, 0.8, -4))
	await get_tree().physics_frame
	far.request_use()
	check(far.holder_id == 0, "out of reach pickup rejected")
	a.request_use()
	check(a.holder_id == 1 and a.freeze and a.collision_layer == 0, "pickup freezes and disables carry collision")
	b.request_use()
	check(b.holder_id == 0 and Prop.held_by(get_tree(), 1) == a, "second pickup cannot occupy same hand")
	a.request_release(true)
	check(a.holder_id == 1, "throw without a charge request rejected")
	a.request_charge()
	var charge_start: int = a._charge_started
	a.request_charge()
	check(a._charge_started == charge_start, "duplicate charge cannot reset hold timer")
	while Time.get_ticks_msec() - charge_start < 1300:
		await get_tree().process_frame
	a.request_release(true)
	check(a.holder_id == 0 and not a.freeze and a.collision_layer == 1, "throw restores physics collision")
	check(is_equal_approx(a.linear_velocity.length(), 14.0), "host caps charged launch speed")
	# Wall between eye and prop: the host rejects a pickup through it.
	var blocked := make_prop(Vector3(0, 1.3, -2))
	var wall := StaticBody3D.new()
	var barrier := CollisionShape3D.new()
	var barrier_shape := BoxShape3D.new()
	barrier_shape.size = Vector3(2, 2, 0.2)
	barrier.shape = barrier_shape
	wall.position = Vector3(0, 1, -1)
	wall.add_child(barrier)
	world.add_child(wall)
	await get_tree().physics_frame
	blocked.request_use()
	check(blocked.holder_id == 0, "pickup through wall rejected")
	wall.queue_free()
	a.reset_prop()
	await get_tree().physics_frame
	a.request_use()
	check(a.holder_id == 1, "prop can be picked up again after throw")
	a.drop_for_transition(1)
	check(a.holder_id == 0, "lift transition drops held object")
	b.can_pick_up = false
	b.request_use()
	check(b.holder_id == 0, "large props cannot enter inventory")
	await get_tree().create_timer(0.08).timeout # impulses take effect on the next physics step
	check(Vector2(b.linear_velocity.x, b.linear_velocity.z).length() > 0.0, "shove moves a large prop away from the player")
	a.request_use()
	check(a.holder_id == 1, "hand occupied before session reset")
	GameState.reset_run()
	check(Prop.held_by(get_tree(), 1) == null, "reset clears occupied hand")
	var player: Node = world.get_node("Players/1")
	var carry_input := Callable(player, "_handle_carry_input" if DisplayServer.get_name() == "headless" else "_unhandled_input")
	a.request_use()
	var drop := InputEventKey.new()
	drop.physical_keycode = KEY_G
	drop.pressed = true
	carry_input.call(drop) # rendered runs also verify the cursor-capture gate
	check(a.holder_id == 0, "G input drops current object")
	a.request_use()
	var throw_button := InputEventMouseButton.new()
	throw_button.button_index = MOUSE_BUTTON_RIGHT
	throw_button.pressed = true
	carry_input.call(throw_button)
	check(a._charge_started >= 0, "RMB input starts authoritative charge")
	throw_button.pressed = false
	carry_input.call(throw_button)
	check(a.holder_id == 0 and a.linear_velocity.length() >= 3.0, "RMB release launches a tap throw")
	a.reset_prop()
	a.request_use()
	a._peer_left(1)
	check(a.holder_id == 0, "disconnected holder releases prop")
	a.global_position.y = -20
	a._physics_process(0.02)
	check(a.global_position.is_equal_approx(a._home.origin), "escaped prop returns home")
	player.read_lore("Test notice", "A short House rule.")
	check(player.overlay.reading and player.input_locked, "lore opens readable modal and locks movement")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	player._unhandled_input(event)
	check(not player.overlay.reading and not player.input_locked, "Escape closes lore without trapping input")
	print("House and hand: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
