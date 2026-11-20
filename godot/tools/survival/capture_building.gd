extends Node
## Fotos de conferência da construção da Sobrevivência, sem servidor: uma casa
## de 2 x 2 células com porta, janelas, andar de cima, escada, telhado de duas
## águas, fogueira, baú e cama; de fora, de dentro, à noite e com a prévia.
## godot --path godot res://tools/survival/capture_building.tscn -- --out=<pasta>
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name))

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	get_tree().root.size = Vector2i(1600, 900)
	var spawn: Array = SurvivalData.world()["spawns"][2]
	var S := 3.0
	var i0 := floori(float(spawn[0]) / S) + 2
	var j0 := floori(float(spawn[1]) / S) - 1
	Net.my_id = "me"
	Net.host_id = "ninguem"
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 300000},
		"you": {"id": "me", "p": [float(spawn[0]), 0.2, float(spawn[1])], "hp": 100, "hunger": 80, "thirst": 80,
			"inv": {"wood": 40, "stone": 20, "fiber": 20, "rope": 4}, "weight": 9, "cap": 60},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": [],
		"tag": "me", "auth": [], "allowed": [], "builds": _house(i0, j0, S)}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	var player: CharacterBody3D = main.get("player")
	var player_cam: Camera3D = get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.fov = 70.0
	main.add_child(cam)
	cam.make_current()
	print("peças no mundo: %d" % main.get_node("SurvivalController").building_ctl.get("nodes").size())
	var center := Vector3((i0 + 1) * S, 0, (j0 + 1) * S)
	# De fora, de frente para a porta (lado -X), um pouco do alto.
	player.global_position = center + Vector3(-12, 0.2, 6)
	await _frames(10)
	cam.global_position = center + Vector3(-11, 4.5, 8)
	cam.look_at(center + Vector3(0, 2.6, 0))
	await _shot(out, "build_outside.png")
	cam.global_position = center + Vector3(9, 5.5, -9)
	cam.look_at(center + Vector3(0, 2.4, 0))
	await _shot(out, "build_back.png")
	# Dentro, no térreo: fogueira, baú, escada.
	cam.global_position = center + Vector3(-2.2, 1.7, -2.2)
	cam.look_at(center + Vector3(1.5, 1.0, 1.5))
	await _shot(out, "build_inside.png")
	# À noite, de fora: a fogueira ilumina pela janela e pela porta.
	var controller := main.get_node("SurvivalController")
	controller.call("_apply_clock", {"day_ms": 1440000, "time": 1300000})
	controller.call("_update_daylight")
	await _frames(5)
	cam.global_position = center + Vector3(-10, 2.2, 3)
	cam.look_at(center + Vector3(0, 1.4, 0))
	await _shot(out, "build_night.png")
	controller.call("_apply_clock", {"day_ms": 1440000, "time": 300000})
	controller.call("_update_daylight")
	# Modo de construção: prévia verde de uma parede ao lado, na câmera do jogador.
	player.global_position = center + Vector3(-5, 0.2, -5)
	player.set("yaw", atan2(-(center.x + 3.0 - player.global_position.x), -(center.z - 4.5 - player.global_position.z)))
	player.set("pitch", -0.45)
	player_cam.make_current()
	await _frames(20)
	var b: Node = controller.building_ctl
	b.call("set_building", true)
	b.set("selected", 0) # fundação
	await _frames(20)
	await _shot(out, "build_ghost.png")
	b.call("set_building", false)
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)

## Casa de 2 x 2 células: porta e janelas no térreo, piso no 1º andar com
## paredes baixas e telhado de duas águas por cima; escada no canto.
func _house(i0: int, j0: int, S: float) -> Array:
	var list: Array = []
	var add := func(p: Dictionary) -> void:
		p["id"] = "P%d" % (list.size() + 1) # (lambda copia variáveis simples: conta pelo tamanho da lista)
		p["ow"] = "me"
		p["hp"] = 400
		list.append(p)
	for di in 2:
		for dj in 2:
			add.call({"kind": "foundation", "i": i0 + di, "j": j0 + dj, "k": 0})
	# Térreo: frente (-X) com porta e janela, fundos com janela, lados com parede.
	for k in 2:
		add.call({"kind": "doorway" if k == 0 else "wall", "i": i0, "j": j0, "k": k, "o": "v"})
		add.call({"kind": "window", "i": i0, "j": j0 + 1, "k": k, "o": "v"})
		add.call({"kind": "window" if k == 0 else "wall", "i": i0 + 2, "j": j0, "k": k, "o": "v"})
		add.call({"kind": "wall", "i": i0 + 2, "j": j0 + 1, "k": k, "o": "v"})
		for di in 2:
			add.call({"kind": "wall", "i": i0 + di, "j": j0, "k": k, "o": "h"})
			add.call({"kind": "window" if di == 1 else "wall", "i": i0 + di, "j": j0 + 2, "k": k, "o": "h"})
	add.call({"kind": "door", "i": i0, "j": j0, "k": 0, "o": "v", "open": true, "r": 0})
	# Piso do 1º andar (menos em cima da escada).
	add.call({"kind": "floor", "i": i0, "j": j0, "k": 1})
	add.call({"kind": "floor", "i": i0, "j": j0 + 1, "k": 1})
	add.call({"kind": "floor", "i": i0 + 1, "j": j0, "k": 1})
	add.call({"kind": "stairs", "i": i0 + 1, "j": j0 + 1, "k": 0, "r": 2})
	# Telhado de duas águas no topo do 2º andar.
	for dj in 2:
		add.call({"kind": "roof", "i": i0, "j": j0 + dj, "k": 2, "r": 3})
		add.call({"kind": "roof", "i": i0 + 1, "j": j0 + dj, "k": 2, "r": 1})
	add.call({"kind": "campfire", "p": [(i0 + 0.5) * S, 0.4, (j0 + 1.5) * S], "y": 0.0, "on": true})
	add.call({"kind": "chest", "p": [(i0 + 1.6) * S, 0.4, (j0 + 0.3) * S], "y": 0.0})
	add.call({"kind": "bed", "p": [(i0 + 0.35) * S, 3.4, (j0 + 0.5) * S], "y": 0.0, "cd": 0})
	return list
