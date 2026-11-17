extends SceneTree
## Foto de conferência das poses do Ch31: em pé armado, desarmado andando,
## agachado armado e agachado desarmado (lado a lado, vistos de lado e de frente).
## godot --path godot --script res://tools/characters/capture_poses.gd -- --out=<png>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://poses.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(1400, 700)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 10)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var specs := [["armado", true, false, 0.0], ["desarmado andando", false, false, 1.0], ["agachado armado", true, true, 0.0], ["agachado desarmado", false, true, 0.6]]
	var avatars: Array = []
	for i in specs.size():
		var avatar: Node3D = load("res://scenes/characters/avatar.tscn").instantiate()
		world.add_child(avatar)
		avatar.position = Vector3(-3.0 + i * 2.0, 0, 0)
		avatar.rotation.y = -0.9 # três quartos, para ver joelho e braços
		await process_frame
		avatar.call("set_armed", specs[i][1])
		avatars.append(avatar)
		var label := Label3D.new()
		label.text = specs[i][0]
		label.position = Vector3(-3.0 + i * 2.0, 2.1, 0)
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = Color.BLACK
		world.add_child(label)
	for frame in 90:
		for i in avatars.size():
			avatars[i].call("animate", 1.0 / 60.0, specs[i][3], false, specs[i][2], false, false, false, Vector2(0, -1), Vector3(0, 0, -2.0 * specs[i][3]))
		await process_frame
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 30.0
	camera.position = Vector3(0, 1.1, 11.0)
	camera.look_at(Vector3(0, 0.85, 0))
	camera.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
