extends SceneTree
## Folhas de conferência dos clipes UAL2 num personagem do catálogo: 14 por
## imagem, cada um parado num ponto do clipe (fração --at, padrão 0.45).
## godot --path godot --script res://tools/characters/capture_ual2.gd -- --id=01 --out=C:/pasta/ual --at=0.45 [--only=a,b,c]
const Registry = preload("res://scripts/characters/character_registry.gd")
const Avatar = preload("res://scripts/characters/downloaded_avatar.gd")
const PER_SHEET := 14

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var id := "01"
	var out := "user://ual"
	var at := 0.45
	var names: Array = Avatar.UAL_CLIPS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--at="):
			at = float(arg.substr(5))
		elif arg.begins_with("--only="):
			names = Array(arg.substr(7).split(","))
	root.size = Vector2i(1900, 760)
	var sheet := 0
	while sheet * PER_SHEET < names.size():
		var batch := names.slice(sheet * PER_SHEET, (sheet + 1) * PER_SHEET)
		var world := _stage()
		var avatars := []
		for i in batch.size():
			var avatar := Registry.create_visual(id)
			world.add_child(avatar)
			avatar.position = Vector3((i % 7) * 1.7 - 5.1, 0, -float(i / 7) * 2.6)
			avatar.rotation.y = -0.55
			avatars.append(avatar)
		await process_frame
		for i in batch.size():
			var avatar: Node3D = avatars[i]
			avatar.call("set_armed", false)
			avatar.call("play_overlay", batch[i], "full", 1.0, 1.0, 999.0)
			var label := Label3D.new()
			label.text = batch[i]
			label.position = avatar.position + Vector3(0, 2.05, 0)
			label.font_size = 36
			label.pixel_size = 0.004
			label.modulate = Color.BLACK
			world.add_child(label)
		# Fade in, then park every clip at the same fraction of its length.
		for f in 20:
			for avatar in avatars:
				avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
			await process_frame
		for i in batch.size():
			var clip: Animation = avatars[i].get("ual_clips")[batch[i]][0]
			avatars[i].set("_overlay_time", clip.length * at)
			avatars[i].set("_overlay_speed", 0.0)
		for f in 3:
			for avatar in avatars:
				avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
			await process_frame
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.fov = 36.0
		camera.position = Vector3(0, 3.2, 9.5)
		camera.look_at(Vector3(0, 0.6, -1.3))
		camera.current = true
		await process_frame
		await process_frame
		var path := "%s_%d.png" % [out, sheet + 1]
		root.get_texture().get_image().save_png(path)
		print("salvo: " + path)
		world.queue_free()
		await process_frame
		sheet += 1
	quit(0)

func _stage() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.58, 0.66, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.76)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 14)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.31, 0.3)
	floor_mesh.material_override = mat
	world.add_child(floor_mesh)
	return world
