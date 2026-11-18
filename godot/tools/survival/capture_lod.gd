extends Node
## Fotos de conferência dos níveis de detalhe (perto / médio / longe) da Sobrevivência:
## vista longa na altura dos olhos e vista do alto, olhando para o centro do mapa.
## godot --path godot res://tools/survival/capture_lod.tscn -- --out=<pasta>
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
	var spawn: Array = SurvivalData.world()["spawns"][2]
	var spot := Vector3(float(spawn[0]), 0.2, float(spawn[1]))
	Net.my_id = "me"
	Net.host_id = "ninguem"
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 400000},
		"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 100, "hunger": 80, "thirst": 80, "inv": {}, "back": "", "weight": 0, "cap": 10},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": []}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	# A câmera segue o jogador (braço de mola): as vistas giram e movem o próprio jogador.
	var player: CharacterBody3D = main.get("player")
	# Cidade mais perto do jogador: os prédios dela ficam na faixa perto/médio e o resto longe.
	var towns: Array = SurvivalData.world()["towns"]
	var town := Vector3.ZERO
	var best := INF
	for t in towns:
		var c := Vector3(float(t["center"][0]), 0, float(t["center"][1]))
		if c.distance_to(spot) < best:
			best = c.distance_to(spot)
			town = c
	# [foto, onde o jogador fica, para onde olha]
	var views := [
		["lod_olhos", spot, Vector3.ZERO],
		["lod_cidade", town + (spot - town).normalized() * 45.0 + Vector3(0, 0.2, 0), town],
	]
	for v in views:
		var at: Vector3 = v[1]
		var target: Vector3 = v[2]
		player.global_position = at
		player.velocity = Vector3.ZERO
		player.set("yaw", atan2(-(target.x - at.x), -(target.z - at.z)))
		player.set("pitch", -0.02)
		await _frames(40)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(str(v[0]) + ".png"))
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
