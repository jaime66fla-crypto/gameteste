extends SceneTree
## Foto de conferência da pose parada de todos os personagens (desarmado e
## armado), vistos de costas em três quartos, como a câmera do jogo.
## godot --path godot --script res://tools/characters/capture_idle_pose.gd -- --out=<png>
const SCENES := ["res://scenes/characters/manequim.tscn", "res://scenes/characters/remy.tscn", "res://scenes/characters/avatar.tscn"]

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var out := "user://idle_pose.png"
	var view := "back"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		if arg.begins_with("--view="):
			view = arg.substr(7)
	root.size = Vector2i(1500, 700)
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
	plane.size = Vector2(30, 10)
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)
	var avatars: Array = []
	var armed_flags: Array = []
	var i := 0
	for scene_path in SCENES:
		for armed in [false, true]:
			var avatar: Node3D = load(scene_path).instantiate()
			world.add_child(avatar)
			avatar.position = Vector3(-5.0 + i * 2.0, 0, 0)
			# De costas, um pouco virado (câmera do jogo atrás do ombro direito).
			avatar.rotation.y = 0.5 if view == "back" else (PI + 0.5) # o avatar olha para -Z
			await process_frame
			avatar.call("set_armed", armed)
			avatars.append(avatar)
			armed_flags.append(armed)
			var label := Label3D.new()
			label.text = "%s %s" % [scene_path.get_file().get_basename(), "armado" if armed else "desarmado"]
			label.position = Vector3(-5.0 + i * 2.0, 2.15, 0)
			label.font_size = 40
			label.pixel_size = 0.004
			label.modulate = Color.BLACK
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			world.add_child(label)
			i += 1
	for frame in 120:
		for avatar in avatars:
			avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false, Vector2.ZERO, Vector3.ZERO)
		await process_frame
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 30.0
	camera.position = Vector3(0, 1.6, 14.0)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
