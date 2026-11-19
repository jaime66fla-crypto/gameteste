extends SceneTree
## Fotos dos braços em primeira pessoa de cada personagem do catálogo, com
## pistola e fuzil: <out>_<id>_<arma>.png
## godot --path godot --script res://tools/characters/capture_viewmodel.gd -- --out=C:/pasta/fp
const Registry = preload("res://scripts/characters/character_registry.gd")
const FirstPersonViewmodel = preload("res://scripts/weapons/first_person_viewmodel.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://fp"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	root.size = Vector2i(960, 540)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.64, 0.71, 0.76)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_energy = 0.5
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 72
	camera.current = true
	world.add_child(camera)
	# null = default look (tactical sleeves and gloves) for characters without fp_* fields.
	var entries: Array = [null]
	entries.append_array(Registry.all_characters())
	for entry in entries:
		for weapon in ["pistol", "rifle"]:
			var viewmodel := FirstPersonViewmodel.new()
			camera.add_child(viewmodel)
			viewmodel.apply_character(entry)
			viewmodel.build(weapon)
			# Settle into the in-game rest pose.
			for i in 40:
				viewmodel.animate(1.0 / 60.0, 0.0, 0.0, false)
				await physics_frame
			await process_frame
			var path := "%s_%s_%s.png" % [out, entry.id if entry else "padrao", weapon]
			root.get_texture().get_image().save_png(path)
			print("salvo: ", path)
			camera.remove_child(viewmodel)
			viewmodel.free()
	quit()
