extends SceneTree
## Foto de conferência dos zumbis animados: andarilho andando, corredor
## correndo, brutamontes parado e um atacando (perto da câmera).
## godot --path godot --script res://tools/survival/capture_zombies.gd -- --out=<png>
const ZombieScript = preload("res://scripts/survival/zombie.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://zombies.png"
	var angle := 0.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		if arg.begins_with("--angle="):
			angle = float(arg.substr(8))
	root.size = Vector2i(1500, 800)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#7d8f8a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.68, 0.62)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 1, 30)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	ground.add_child(col)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	mesh.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#4f5f45")
	mesh.material_override = gm
	ground.add_child(mesh)
	world.add_child(ground)
	var specs := [["walker", 1], ["runner", 2], ["brute", 0], ["walker", 3]]
	var zombies: Array = []
	for i in specs.size():
		var z: CharacterBody3D = ZombieScript.new()
		z.call("setup", "z%d" % i, specs[i][0], 60)
		z.position = Vector3(-3.0 + i * 2.0, 0.05, 0)
		z.rotation.y = angle
		world.add_child(z)
		z.set("_remote_yaw", angle)
		z.set("anim", specs[i][1])
		zombies.append(z)
	var camera := Camera3D.new()
	camera.fov = 32
	world.add_child(camera)
	camera.position = Vector3(0, 1.5, 7.5)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	for frame in 50:
		for i in zombies.size():
			zombies[i].set("anim", specs[i][1])
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
