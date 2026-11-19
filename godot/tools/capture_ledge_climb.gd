extends SceneTree
## Fotos de conferência da escalada (player.gd start_climb + clipe ClimbUp_1m):
## câmera de lado num muro de 2,2 m, uma foto em cada fase da subida.
## godot --path godot --script res://tools/capture_ledge_climb.gd -- --out=C:/pasta
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2)) # nunca deixa a janela presa
	_run.call_deferred()

func _box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	body.add_child(mesh)
	parent.add_child(body)

func _run() -> void:
	var out := "user://ledge_climb"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("Net").set("in_match", false)
	root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var o := Vector3(600, 40, 600)
	_box(main, o + Vector3(0, -0.5, 0), Vector3(40, 1, 40), Color("#7d8a6a"))
	_box(main, o + Vector3(0, 1.1, -3.0), Vector3(4, 2.2, 2), Color("#9a8f80"))
	var player: CharacterBody3D = main.get_node("Jaime")
	for armed in [false, true]:
		if armed:
			player.call("_equip_weapon", "rifle")
			if bool(player.get("weapon_holstered")):
				player.call("_toggle_weapon_holster")
		elif not bool(player.get("weapon_holstered")):
			player.call("_toggle_weapon_holster")
		player.velocity = Vector3.ZERO
		player.global_position = o + Vector3(0, 0.05, -1.4)
		player.set("yaw", 0.0)
		player.set("_body_yaw", 0.0)
		for i in 40:
			await physics_frame
		var cam := Camera3D.new()
		cam.fov = 50.0
		main.add_child(cam)
		cam.global_position = o + Vector3(5.5, 2.0, -1.8)
		cam.look_at(o + Vector3(0, 1.4, -2.0))
		cam.current = true
		for i in 30:
			await process_frame # deixa o FPS estabilizar antes de subir
		Engine.time_scale = 0.15 # câmera lenta: cada foto cai na fase certa
		Input.action_press("jump")
		await physics_frame
		Input.action_release("jump")
		var marks := [0.15, 0.35, 0.55, 0.75, 0.95]
		var next := 0
		for i in 1500:
			await process_frame
			var t := float(player.get("_climb_t")) if bool(player.get("climbing")) else 1.0
			if next < marks.size() and t >= marks[next]:
				root.get_texture().get_image().save_png(out.path_join("escalada_%s_%02d.png" % ["arma" if armed else "maos", int(marks[next] * 100)]))
				next += 1
			if not bool(player.get("climbing")) and next > 0:
				break
		Engine.time_scale = 1.0
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("escalada_%s_fim.png" % ("arma" if armed else "maos")))
		cam.queue_free()
	print("fotos salvas em " + out)
	quit(0)
