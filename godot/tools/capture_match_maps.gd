extends SceneTree
## Fotos de conferência dos mapas online (match_map.gd): vista de cima e uma
## vista na altura do jogador em cada mapa.
## godot --path godot --script res://tools/capture_match_maps.gd -- --out=C:/pasta
const MatchLayout = preload("res://scripts/net/match_layout.gd")

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2)) # nunca deixa a janela presa
	_run.call_deferred()

func _run() -> void:
	var out := "user://match_maps"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	root.get_node("Net").set("in_match", true)
	for id in MatchLayout.map_ids():
		root.get_node("Net").set("start_info", {"map": id})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var player: CharacterBody3D = main.get_node("Jaime")
		player.set_physics_process(false)
		for node in main.get_children():
			if node is CanvasLayer:
				node.visible = false
		var layout := MatchLayout.load_layout()
		var half := float(layout.get("map_half_size", 40))
		var spawn := MatchLayout.spawn_point(0)
		var cam := Camera3D.new()
		cam.fov = 60.0
		main.add_child(cam)
		cam.current = true
		for shot in [
			["alto", Vector3(0, half * 1.9, half * 0.9), Vector3(0, 0, 0)],
			["chao", spawn + Vector3(0, 1.6, 0), Vector3(0, 1.4, 0)],
			["diagonal", Vector3(half * 0.9, 14, half * 0.9), Vector3(0, 0, 0)],
		]:
			cam.global_position = shot[1]
			cam.look_at(shot[2])
			for i in 20:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [id, shot[0]]))
		main.queue_free()
		await process_frame
		await process_frame
	print("fotos salvas em " + out)
	quit(0)
