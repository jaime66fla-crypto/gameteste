extends Node
## Fotos de conferência da Sobrevivência sem servidor: HUD (minimapa e munição),
## grama alta, floresta, mochila nas costas e o inventário aberto.
## godot --path godot res://tools/survival/capture_game.tscn -- --out=<pasta>
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

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
	# Começa na borda de uma mancha de grama alta perto de uma floresta.
	# Mancha de grama alta mais perto de um ponto de nascimento (campo aberto).
	var spawn: Array = SurvivalData.world()["spawns"][2]
	var patch: Dictionary = {}
	var best := INF
	for g in SurvivalData.world()["grass"]:
		var d := Vector2(float(g["x"]) - float(spawn[0]), float(g["z"]) - float(spawn[1])).length()
		if d < best:
			best = d
			patch = g
	# Fica no ponto de nascimento (livre de prédios e árvores), olhando para a grama alta.
	var spot := Vector3(float(spawn[0]), 0.2, float(spawn[1]))
	var face := atan2(-(float(patch["x"]) - spot.x), -(float(patch["z"]) - spot.z))
	Net.my_id = "me"
	Net.host_id = "ninguem" # zumbi parado (não é anfitrião), para a foto
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 260000},
		"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 82, "hunger": 64, "thirst": 47,
			"inv": {"w_rifle": 1, "a_556": 60, "canned_beans": 2, "water_bottle": 1, "bandage": 3, "wood": 2, "cloth": 4}, "back": "backpack", "weight": 9.4, "cap": 34},
		"roster": [], "zombies": [
			{"id": "z1", "kind": "walker", "hp": 60, "p": [spot.x - sin(face) * 7.0 + 1.5, 0.2, spot.z - cos(face) * 7.0]},
			{"id": "z2", "kind": "brute", "hp": 150, "p": [spot.x - sin(face) * 10.0 - 2.0, 0.2, spot.z - cos(face) * 10.0]},
			{"id": "z3", "kind": "runner", "hp": 45, "p": [spot.x - sin(face) * 13.0 + 3.5, 0.2, spot.z - cos(face) * 13.0]}], "bags": [], "searched": [], "depleted": {},
		"vehicles": [{"id": "v0", "kind": "pickup", "color": "#8c1d18", "p": [spot.x + 4.0, 0, spot.z + 3.0], "yaw": face, "fuel": 60, "driver": null}]}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(30)
	var player: CharacterBody3D = main.get("player")
	player.set("yaw", face)
	player.set("pitch", -0.12)
	player.set("ammo", 22)
	# Zumbis olhando para o jogador, andando.
	var controller_node := main.get_node("SurvivalController")
	for zid in controller_node.zombies:
		var z: Node3D = controller_node.zombies[zid]
		var to := player.global_position - z.global_position
		z.set("_remote_yaw", atan2(-to.x, -to.z))
		z.set("anim", 1)
	await _frames(60)
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_hud.png"))
	var controller := main.get_node("SurvivalController")
	controller.inventory.call("open")
	controller.inventory.call("show_container", "k0", "Geladeira", {"soda": 2, "water_bottle": 1})
	await _frames(10)
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_inventory.png"))
	controller.inventory.call("close")
	# Visto de frente/de lado, agachado, para conferir a mochila e a pose.
	player.call("_toggle_weapon_holster") # desarmado, agachado
	Input.action_press("crouch")
	await _frames(70)
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_crouch.png"))
	Input.action_release("crouch")
	# Ctrl de novo: deita, armado e mirando (fica na posição sem segurar).
	player.call("_toggle_weapon_holster")
	await _frames(5)
	Input.action_press("crouch")
	await _frames(2)
	Input.action_release("crouch")
	player.set("yaw", face + 2.4) # de lado, para ver o corpo deitado
	await _frames(120)
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_prone.png"))
	Input.action_press("crouch") # 3º toque: levanta
	await _frames(2)
	Input.action_release("crouch")
	# Correndo desarmado, visto de lado (braços do clipe de corrida).
	player.call("_toggle_weapon_holster")
	player.set("yaw", face)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(50)
	player.set("pitch", -0.05)
	var cam: Camera3D = get_viewport().get_camera_3d()
	var saved_cam := cam.global_transform
	cam.global_position = player.global_position + player.global_basis.x * 3.2 + Vector3(0, 1.2, 0)
	cam.look_at(player.global_position + Vector3(0, 1.0, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_run.png"))
	Input.action_release("sprint")
	Input.action_release("move_forward")
	cam.global_transform = saved_cam
	# Floresta de cima.
	player.set("pitch", -0.35)
	await _frames(20)
	var forest := Vector3.ZERO
	var best_trees := 0
	for r in SurvivalData.world()["resources"]:
		if str(r["kind"]) == "tree":
			forest = Vector3(float(r["p"][0]), 0, float(r["p"][2]))
			break
	cam.global_position = forest + Vector3(14, 9, 14)
	cam.look_at(forest + Vector3(0, 3, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_trees.png"))
	await _frames(5)
	# Dirigindo a caminhonete (câmera de perseguição, velocímetro e gasolina).
	var car: Node3D = controller.driving_ctl.vehicles["v0"]
	var cp := car.global_position
	controller.driving_ctl.call("request_enter", "v0")
	Net.message.emit({"t": "veh", "id": "v0", "kind": "pickup", "color": "#8c1d18", "p": [cp.x, cp.y, cp.z], "yaw": face, "fuel": 60, "driver": "me"})
	Input.action_press("move_forward")
	Input.action_press("move_left")
	await _frames(70)
	Input.action_release("move_left")
	await _frames(20)
	get_viewport().get_texture().get_image().save_png(out.path_join("survival_driving.png"))
	Input.action_release("move_forward")
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
