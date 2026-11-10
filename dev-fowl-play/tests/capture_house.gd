extends Node

func _ready() -> void:
	Network.my_nickname = "Guest Hen"
	Network.names[1] = "Guest Hen"
	var world := preload("res://world.tscn").instantiate()
	add_child(world)
	var player: Node3D = world.get_node("Players/1")
	var output := OS.get_cmdline_user_args()[0]
	var views := [
		["apartment", Vector3(0, 0, 4), Vector3(-1, 1.5, -3)],
		["casino", Vector3(100, 0.5, -9), Vector3(100, 2.5, 5)],
		["rest", Vector3(50, 0, 4), Vector3(49, 1.5, -3)],
		["focus", Vector3(3.4, 0, -3.6), Vector3(5.82, 1.8, -3.6)],
	]
	for view in views:
		player.position = view[1]
		player.velocity = Vector3.ZERO
		player.head.look_at(view[2])
		for i in 8:
			await get_tree().physics_frame
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(view[0] + ".png"))
	var guide: Node = get_tree().get_nodes_in_group("lore_guides")[3]
	player.read_lore(guide.title, guide.body)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("lore.png"))
	player.overlay.close_lore()
	player.input_locked = false
	player.position = Vector3(-3.6, 0, 1.4)
	player.head.look_at(Vector3(-3.6, 1.5, -2))
	for prop in get_tree().get_nodes_in_group("physics_props"):
		if prop.item_name == "Last clean cup":
			prop.request_use()
	var charge := InputEventMouseButton.new()
	charge.button_index = MOUSE_BUTTON_RIGHT
	charge.pressed = true
	player._unhandled_input(charge)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("carry.png"))
	charge.pressed = false
	player._unhandled_input(charge)
	world.queue_free()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit()
