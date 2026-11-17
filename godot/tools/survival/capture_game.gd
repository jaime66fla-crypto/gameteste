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
		"roster": [], "zombies": [{"id": "z1", "kind": "walker", "hp": 60, "p": [float(patch["x"]), 0.2, float(patch["z"])]}], "bags": [], "searched": [], "depleted": {}}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(30)
	var player: CharacterBody3D = main.get("player")
	player.set("yaw", face)
	player.set("pitch", -0.12)
	player.set("ammo", 22)
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
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
