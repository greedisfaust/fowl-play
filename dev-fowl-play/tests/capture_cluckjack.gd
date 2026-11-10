extends Node3D
## Optional rendered QA: -- --capture=C:/absolute/path.png (not headless).
func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("15202d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	add_child(light)
	var table := preload("res://tables/cluckjack/cluckjack.tscn").instantiate()
	table.set_script(preload("res://tests/cluckjack_fixture.gd"))
	add_child(table)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.3, 3.1)
	add_child(camera)
	camera.look_at(Vector3(0, 1.65, -0.4))
	GameState.start_day()
	table.request_bet_input("min", 0)
	table.request_play(table.bet)
	for i in 5:
		await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			var error := get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			print("Cluckjack capture: ", error)
	get_tree().quit()
