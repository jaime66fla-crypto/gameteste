extends SceneTree
## Foto de conferência do nado: 8 momentos de uma braçada de crawl (colunas),
## vistos de lado, de trás/cima (câmera do jogo) e de frente (linhas), com a
## linha d'água marcada.
## godot --path godot --script res://tools/survival/capture_swim.gd -- --out=<png> [--tread]
const AvatarScript = preload("res://scripts/characters/downloaded_avatar.gd")

const SAMPLES := 8
const CELL := Vector2i(320, 240)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://swim.png"
	var move := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		if arg == "--tread":
			move = 0.0
	root.size = CELL
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#9fb4c0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	water.mesh = plane
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.1, 0.35, 0.5, 0.45)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = wm
	water.position.y = 1.02
	world.add_child(water)
	var avatar: Node3D = AvatarScript.new()
	world.add_child(avatar)
	await process_frame
	avatar.call("set_swimming", true)
	for i in 180:
		avatar.call("animate", 1.0 / 60.0, move, false, false, false, true, false)
	var camera := Camera3D.new()
	camera.fov = 45
	world.add_child(camera)
	camera.current = true
	var sheet := Image.create(CELL.x * SAMPLES, CELL.y * 3, false, Image.FORMAT_RGBA8)
	var period := TAU / lerpf(2.4, 4.6, move)
	for s in SAMPLES:
		for view in 3:
			match view:
				0:
					camera.position = Vector3(3.2, 1.1, 0.4) # lado
					camera.look_at(Vector3(0, 0.95, 0.4))
				1:
					camera.position = Vector3(0.0, 3.0, 2.6) # atrás e acima (câmera do jogo)
					camera.look_at(Vector3(0, 0.9, 0.2))
				2:
					camera.position = Vector3(1.6, 1.6, -2.6) # de frente, meio de lado
					camera.look_at(Vector3(0, 0.95, 0.0))
			for i in 3:
				await process_frame
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(s * CELL.x, view * CELL.y))
		var steps := int(round(period / SAMPLES * 60.0))
		for i in steps:
			avatar.call("animate", 1.0 / 60.0, move, false, false, false, true, false)
	sheet.save_png(out)
	print("salvo: " + out)
	quit(0)
