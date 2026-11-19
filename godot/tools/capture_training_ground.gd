extends SceneTree
## Fotos de conferência do campo de treino offline (training_ground.gd):
## a câmera do jogo no nascimento e câmeras livres em cada zona.
## godot --path godot --script res://tools/capture_training_ground.gd -- --out=C:/pasta
func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2)) # nunca deixa a janela presa
	_run.call_deferred()

func _run() -> void:
	var out := "user://training_ground"
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
	var player: CharacterBody3D = main.get_node("Jaime")
	player.call("_equip_weapon", "rifle")
	for i in 90:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("treino_jogo_nascimento.png"))
	var cam := Camera3D.new()
	cam.fov = 70.0
	main.add_child(cam)
	cam.current = true
	for shot in [
		["treino_alto", Vector3(0, 70, 62), Vector3(0, 0, -4)],
		["treino_estande", Vector3(12, 4.5, -6), Vector3(12, 1, -36)],
		["treino_agilidade", Vector3(-6, 9, 4), Vector3(-25, 1, -24)],
		["treino_torre", Vector3(-22, 7, 46), Vector3(-42, 4, 34)],
		["treino_da_torre", Vector3(-45, 7.6, 37), Vector3(-44, 1.2, -45)],
		["treino_cobertura", Vector3(22, 6, 20), Vector3(38, 1, -14)],
		["treino_casa", Vector3(30, 2.2, -19), Vector3(37, 1.4, -29)],
		["treino_arena", Vector3(22, 5, 22), Vector3(30, 0.5, 32)],
	]:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join(shot[0] + ".png"))
	print("fotos salvas em " + out)
	quit(0)
