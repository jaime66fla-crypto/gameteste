extends SceneTree
## Foto de um modelo (frente e lado) para conferência.
## godot --path godot --script res://tools/characters/capture_model.gd -- --path=res://... --out=<png>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://assets/personagens/zumbi/zumbi.fbx"
	var out := "user://model.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
		if arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(1200, 800)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#8ea4b0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 25, 0)
	world.add_child(sun)
	for i in 2:
		var model: Node3D = (load(path) as PackedScene).instantiate()
		model.position = Vector3(-0.9 + i * 1.8, 0, 0)
		model.rotation.y = 0.0 if i == 0 else PI * 0.5
		world.add_child(model)
	var camera := Camera3D.new()
	camera.fov = 35
	world.add_child(camera)
	camera.position = Vector3(0, 1.0, 5.2)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
