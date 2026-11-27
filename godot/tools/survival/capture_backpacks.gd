extends SceneTree
## Foto de conferência das três mochilas nas costas do personagem (vista de trás e de lado).
## godot --path godot --script res://tools/survival/capture_backpacks.gd -- --out=<png>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://backpacks.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(1500, 800)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8ea4b0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.75)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 10)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var kinds := ["school_bag", "sack_bag", "backpack"]
	var avatars: Array = []
	for i in kinds.size():
		for view in 2:
			var avatar: Node3D = load("res://scenes/characters/atacante.tscn").instantiate()
			world.add_child(avatar)
			avatar.position = Vector3(-3.75 + (i * 2 + view) * 1.5, 0, 0)
			avatar.rotation.y = -0.6 if view == 0 else -1.57 # de costas (3/4) e de lado
			await process_frame
			avatar.call("set_armed", false)
			avatar.call("set_backpack", kinds[i])
			avatars.append(avatar)
	for frame in 40:
		for a in avatars:
			a.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
		await process_frame
	var camera := Camera3D.new()
	camera.fov = 22
	world.add_child(camera)
	camera.position = Vector3(0, 1.6, 12)
	camera.look_at(Vector3(0, 1.2, 0))
	camera.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
