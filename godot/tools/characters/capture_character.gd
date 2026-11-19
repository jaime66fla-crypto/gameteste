extends SceneTree
## Fotos de conferência de um personagem do catálogo:
##   <out>_poses.png  6 poses lado a lado (fuzil parado, mirando para cima,
##                    andando desarmado, trotando de lado, agachado, correndo)
##   <out>_close.png  close do rosto e do tronco (materiais)
## godot --path godot --script res://tools/characters/capture_character.gd -- --id=remy --out=C:/pasta/remy
const Registry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var id := "remy"
	var out := "user://capture"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(1800, 760)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.66, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_energy = 0.45
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.45
	fill.light_color = Color("#c3d8ec")
	world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 14)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.23, 0.22)
	floor_mesh.material_override = floor_mat
	world.add_child(floor_mesh)
	# [rótulo, armado, agachado, quanto anda (0..1), velocidade local, mira para cima]
	var specs := [
		["fuzil parado", true, false, 0.0, Vector3.ZERO, false],
		["mirando p/ cima", true, false, 0.0, Vector3.ZERO, true],
		["andando", false, false, 0.5, Vector3(0, 0, -1.4), false],
		["trotando de lado", false, false, 0.8, Vector3(3.0, 0, 0), false],
		["agachado", true, true, 0.0, Vector3.ZERO, false],
		["correndo", false, false, 1.0, Vector3(0, 0, -5.0), false],
	]
	var avatars: Array = []
	for i in specs.size():
		var avatar := Registry.create_visual(id)
		if avatar == null:
			printerr("personagem indisponível: " + id)
			quit(1)
			return
		world.add_child(avatar)
		avatar.position = Vector3(-6.25 + i * 2.5, 0, 0)
		avatar.rotation.y = -0.75
		await process_frame
		if not bool(avatar.call("is_visual_ready")):
			printerr("visual não ficou pronto: " + id)
			quit(1)
			return
		avatar.call("set_armed", specs[i][1])
		if specs[i][1]:
			avatar.call("configure_weapon", "rifle", 1.0)
			var weapon := Node3D.new()
			(avatar.get("weapon_mount") as Node3D).add_child(weapon)
			var model := WeaponProportions.create_model("rifle")
			if model:
				weapon.add_child(model)
				WeaponProportions.apply(weapon, "rifle", model)
				avatar.call("bind_weapon", weapon)
		if specs[i][5]:
			var forward := -avatar.global_basis.z
			avatar.call("set_aim_target", avatar.global_position + forward * 6.0 + Vector3.UP * 5.5, true)
		avatars.append(avatar)
		var label := Label3D.new()
		label.text = specs[i][0]
		label.position = avatar.position + Vector3(0, 2.15, 0)
		label.font_size = 44
		label.pixel_size = 0.004
		label.modulate = Color.BLACK
		world.add_child(label)
	for frame in 100:
		for i in avatars.size():
			var s: Array = specs[i]
			avatars[i].call("animate", 1.0 / 60.0, s[3], s[3] >= 1.0, s[2], false, false, false, Vector2(0, -1), s[4])
		await process_frame
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.fov = 34.0
	camera.position = Vector3(0, 1.3, 15.5)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "_poses.png")
	print("salvo: " + out + "_poses.png")
	# Close: rosto e tronco do primeiro (fuzil parado), de frente em três quartos.
	var first := avatars[0] as Node3D
	var face := first.global_position + Vector3(0, 1.55, 0)
	var front := (-first.global_basis.z).normalized()
	camera.fov = 26.0
	camera.position = face + front * 1.6 + first.global_basis.x * 0.5 + Vector3(0, 0.05, 0)
	camera.look_at(face + Vector3(0, -0.12, 0))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "_close.png")
	print("salvo: " + out + "_close.png")
	quit(0)
