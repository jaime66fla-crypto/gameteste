extends Node
## Fotos de conferência do bairro de parkour (treino offline).
## godot --path godot res://tools/capture_parkour.tscn -- --out=<pasta>

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	get_tree().root.size = Vector2i(1600, 900)
	# "--online": mapa do mata-mata / sala personalizada (120 m, só as bases).
	var online := "--online" in OS.get_cmdline_user_args()
	var survival := "--survival" in OS.get_cmdline_user_args()
	Net.in_match = online or survival
	if survival:
		# Sobrevivência: jogador no Bairro do Parkour (anel novo).
		var spot := Vector3(60, 0.2, -282)
		Net.my_id = "me"
		Net.host_id = "ninguem"
		Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 400000},
			"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 100, "hunger": 80, "thirst": 80, "inv": {}, "back": "", "weight": 0, "cap": 10},
			"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": []}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(30)
	var cam := Camera3D.new()
	cam.fov = 70
	main.add_child(cam)
	cam.make_current()
	# [foto, posição da câmera, para onde olha]
	var views := [
		["parkour_rua", Vector3(-20, 1.7, -70), Vector3(-35, 3, -80)],
		["parkour_sobrado", Vector3(-82, 4.0, -66), Vector3(-90, 3, -80)],
		["parkour_pista", Vector3(-55, 5, -66), Vector3(-65, 1.5, -80)],
		["parkour_telhados", Vector3(10, 14, -60), Vector3(-20, 5, -85)],
		["parkour_beco", Vector3(-70, 1.7, -95), Vector3(-90, 1.5, -94)],
		["parkour_alto", Vector3(0, 120, 30), Vector3(0, 0, -20)],
	]
	if survival:
		views = [
			["sobrev_bairro", Vector3(30, 9, -290), Vector3(70, 3, -308)],
			["sobrev_rua", Vector3(28, 1.7, -305), Vector3(70, 3, -305)],
			["sobrev_escada", Vector3(25.5, 2.2, -309.5), Vector3(29.5, 2.5, -318)],
			["sobrev_alto", Vector3(0, 300, 120), Vector3(0, 0, -40)],
		]
	elif online:
		views = [
			["base_perto", Vector3(-6, 3.5, -45), Vector3(-12, 2, -57)],
			["base_alto", Vector3(0, 95, 25), Vector3(0, 0, -12)],
		]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2])
		await _frames(10)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(str(v[0]) + ".png"))
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
