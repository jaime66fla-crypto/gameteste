extends Node
## Fotos de conferência dos animais da Sobrevivência: os quatro lado a lado
## (de lado, todos olhando para -Z = direita da foto), parados e andando.
## godot --path godot res://tools/survival/capture_animals.tscn -- --out=<pasta>
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _shot(out: String, file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(file))

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	get_tree().root.size = Vector2i(1600, 900)
	var spawn: Array = SurvivalData.world()["spawns"][2]
	var c := Vector3(float(spawn[0]), 0.2, float(spawn[1]))
	Net.my_id = "me"
	Net.host_id = "ninguem" # ninguém simula: ficam onde foram postos
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "ninguem", "clock": {"day_ms": 1440000, "time": 300000},
		"you": {"id": "me", "p": [c.x - 30, 0.2, c.z], "hp": 100, "hunger": 80, "thirst": 80, "inv": {}, "weight": 0, "cap": 10},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": [],
		"animals": [
			{"id": "a1", "kind": "rabbit", "hp": 15, "p": [c.x, 0.2, c.z - 4.5]},
			{"id": "a2", "kind": "boar", "hp": 110, "p": [c.x, 0.2, c.z - 2.4]},
			{"id": "a3", "kind": "wolf", "hp": 70, "p": [c.x, 0.2, c.z + 0.2]},
			{"id": "a4", "kind": "deer", "hp": 80, "p": [c.x, 0.2, c.z + 3.2]}]}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	var controller := main.get_node("SurvivalController")
	var cam := Camera3D.new()
	cam.fov = 45.0
	main.add_child(cam)
	cam.make_current()
	cam.global_position = c + Vector3(9.5, 1.4, -0.7)
	cam.look_at(c + Vector3(0, 0.6, -0.7))
	for a in controller.animals.values():
		a.rotation.y = 0.0
		a.set("_remote_yaw", 0.0)
	await _frames(20)
	await _shot(out, "animals_idle.png")
	for a in controller.animals.values():
		a.set("anim", 1) # andando
	await _frames(25)
	await _shot(out, "animals_walk.png")
	for a in controller.animals.values():
		a.set("anim", 2) # correndo
	await _frames(17)
	await _shot(out, "animals_run.png")
	# De perto, o javali (presas) de três quartos.
	var boar: Node3D = controller.animals["a2"]
	for a in controller.animals.values():
		a.set("anim", 0)
	cam.global_position = boar.global_position + Vector3(1.4, 0.8, -1.9)
	cam.look_at(boar.global_position + Vector3(0, 0.4, -0.4))
	await _frames(20)
	await _shot(out, "animals_boar.png")
	var rabbit: Node3D = controller.animals["a1"]
	cam.global_position = rabbit.global_position + Vector3(1.0, 0.5, -0.8)
	cam.look_at(rabbit.global_position + Vector3(0, 0.15, 0))
	await _frames(20)
	await _shot(out, "animals_rabbit.png")
	# Morto: tomba (coelho e javali, que não têm animação de morte) ou cai (lobo e cervo).
	for a in controller.animals.values():
		a.call("die")
	cam.global_position = c + Vector3(9.5, 1.4, -0.7)
	cam.look_at(c + Vector3(0, 0.6, -0.7))
	await _frames(90)
	await _shot(out, "animals_dead.png")
	if true:
		print("fotos salvas em " + out)
		Net.in_match = false
		get_tree().quit(0)
		return
	await _frames(20)
	await _shot(out, "animals_boar.png")
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
