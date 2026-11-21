extends SceneTree
## Foto de conferência dos carros: sedã, hatch e caminhonete, novos (em cima)
## e abandonados (embaixo), com céu para os reflexos da pintura.
## godot --path godot --script res://tools/survival/capture_cars.gd -- --out=<png>
const CarModel = preload("res://scripts/survival/car_model.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://cars.png"
	var angle := -0.6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		if arg.begins_with("--angle="):
			angle = float(arg.substr(8))
	root.size = Vector2i(1600, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#3d6f95")
	mat.sky_horizon_color = Color("#b8c7cc")
	mat.ground_bottom_color = Color("#3a4636")
	mat.ground_horizon_color = Color("#9aa596")
	sky.sky_material = mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#4a5052")
	gm.roughness = 0.9
	ground.material_override = gm
	world.add_child(ground)
	var specs := [["sedan", "#8c1d18"], ["hatch", "#1f3d6b"], ["pickup", "#d8d4cc"]]
	for i in specs.size():
		for row in 2:
			var car := CarModel.build(specs[i][0], specs[i][1], row == 1, i + 2)
			CarModel.apply_lod(car, specs[i][0], specs[i][1], 140.0, 220.0, 0.0)
			car.position = Vector3(-6.5 + i * 6.5, 0, -4.0 + row * 7.0)
			car.rotation.y = angle
			world.add_child(car)
	var camera := Camera3D.new()
	camera.fov = 40
	world.add_child(camera)
	camera.position = Vector3(0, 7.5, 16)
	camera.look_at(Vector3(0, 0.6, 0))
	camera.current = true
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	quit(0)
