extends Node
## Treino offline: estação de ferramentas (scripts/training_tools.gd). Confere
## espaço livre, troca de ferramenta no suporte (E), corte da árvore, picareta
## na pedra e o golpe de ataque de cada arma branca com dano no boneco/zumbi.
## godot --headless --path godot res://tests/training_tools.tscn
## Fotos: godot --path godot res://tests/training_tools.tscn -- --capture=<pasta>
const Tools = preload("res://scripts/training_tools.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _capture_folder() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.substr(10)
	return ""

func _shot(label: String) -> void:
	var folder := _capture_folder()
	if folder.is_empty():
		return
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _look(player: Node, point: Vector3) -> void:
	var camera: Camera3D = player.get("camera")
	for k in 8:
		var to := point - camera.global_position
		player.set("yaw", atan2(-to.x, -to.z))
		player.set("pitch", atan2(to.y, Vector2(to.x, to.z).length()))
		await _frames(3)

func _run() -> void:
	Net.in_match = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(10)
	var player: CharacterBody3D = main.get("player")
	var tools: Node3D = main.get_node_or_null("TrainingTools")
	var arena: Node3D = main.get_node_or_null("TrainingArena")
	check(tools != null and arena != null, "estação de ferramentas e arena existem no treino")
	if tools == null:
		get_tree().quit(1)
		return
	var avatar: Node3D = player.get("humanoid_avatar")
	# Espaço livre: nada do campo de treino em volta da árvore, da pedra e do suporte
	# (raio de cima bate no chão, a não ser no próprio objeto).
	var space := player.get_world_3d().direct_space_state
	var blocked := 0
	for x in range(-50, 51, 5):
		for z in range(-40, 41, 5):
			var p := Tools.CENTER + Vector3(x * 0.1, 0, z * 0.1)
			if p.distance_to(Tools.TREE) < 0.8 or p.distance_to(Tools.ROCK) < 1.1 or (absf(p.x - Tools.RACK.x) < 2.4 and absf(p.z - Tools.RACK.z) < 0.5):
				continue
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 8, 0), p + Vector3(0, -1, 0), 1))
			if not hit.is_empty() and (hit["position"] as Vector3).y > 0.2:
				blocked += 1
	check(blocked == 0, "área da estação livre (%d pontos com obstáculo)" % blocked)
	# Pega ferramentas no suporte (E): a primeira é o machado de pedra.
	player.global_position = Tools.RACK + Vector3(0, 0.1, -1.2)
	await _frames(5)
	await _look(player, Tools.RACK + Vector3(0, 0.9, 0))
	await _shot("1_suporte")
	check(bool(tools.call("_interact")), "E no suporte troca de ferramenta")
	await _frames(5)
	check(str(player.get("melee_weapon")) == "stone_axe" and bool(player.get("weapon_holstered")), "pegou o machado de pedra (arma de fogo guardada)")
	check(str(avatar.get("work_action")) == "hold" and str(avatar.get("work_tool")) == "stone_axe", "carrega o machado na mão")
	# Corta a árvore.
	player.global_position = Tools.TREE + Vector3(0.4, 0.1, -1.8)
	await _frames(5)
	check(bool(tools.call("_interact")), "E perto da árvore corta")
	await _frames(20)
	check(str(avatar.get("work_action")) == "chop", "machadada na árvore (chop)")
	var d := Vector2(player.global_position.x - Tools.TREE.x, player.global_position.z - Tools.TREE.z).length()
	check(absf(d - 1.15) < 0.2, "chega na distância do golpe (%.2f m)" % d)
	await _look(player, Tools.TREE + Vector3(0, 1.0, 0))
	player.set("yaw", float(player.get("yaw")) + 1.2) # câmera de lado para ver o golpe
	await _frames(25)
	await _shot("2_cortando")
	await _frames(int(Tools.WORK_TIME * 60))
	check(str(avatar.get("work_action")) == "hold", "terminou de cortar e volta a carregar")
	# Picareta na pedra: troca até a picareta de pedra (E no suporte duas vezes).
	player.global_position = Tools.RACK + Vector3(0, 0.1, -1.2)
	await _frames(3)
	tools.call("_interact")
	tools.call("_interact")
	await _frames(5)
	check(str(player.get("melee_weapon")) == "stone_pick", "trocou para a picareta de pedra")
	player.global_position = Tools.ROCK + Vector3(-0.3, 0.1, -1.9)
	await _frames(5)
	tools.call("_interact")
	await _frames(20)
	check(str(avatar.get("work_action")) == "pry" and str(avatar.get("work_tool")) == "stone_pick", "picareta na pedra")
	await _look(player, Tools.ROCK + Vector3(0, 0.4, 0))
	player.set("yaw", float(player.get("yaw")) - 1.2)
	await _frames(30)
	await _shot("3_picareta")
	player.call("cancel_channel")
	await _frames(5)
	# Ataque de cada ferramenta no boneco de treino mais perto (arena._melee = clique esquerdo).
	var dummy: Node3D = null
	for node in get_tree().get_nodes_in_group("training_dummy"):
		dummy = node
		break
	check(dummy != null, "boneco de treino para os golpes")
	if dummy != null:
		for tool in Tools.TOOLS:
			player.set("melee_weapon", tool)
			await _frames(3)
			player.global_position = dummy.global_position + Vector3(0, 0.1, 1.6)
			await _frames(3)
			await _look(player, dummy.global_position + Vector3(0, 1.3, 0))
			arena.set("_cooldown", 0.0)
			var before := int(dummy.get("hits"))
			arena.call("_melee")
			check(str(avatar.get("work_action")) == "swing" and str(avatar.get("work_tool")) == tool, "%s: golpe de ataque" % tool)
			check(int(dummy.get("hits")) == before + 1, "%s: acerta o boneco" % tool)
			if tool in ["iron_axe", "stone_knife", "wood_spear"]:
				await _frames(14)
				await _shot("4_ataque_" + tool)
			await _frames(45)
			check(str(avatar.get("work_action")) == "hold", "%s: depois do golpe volta a carregar" % tool)
	# Último E no suporte devolve.
	player.set("melee_weapon", Tools.TOOLS[Tools.TOOLS.size() - 1])
	player.global_position = Tools.RACK + Vector3(0, 0.1, -1.2)
	await _frames(3)
	tools.call("_interact")
	await _frames(5)
	check(str(player.get("melee_weapon")) == "" and str(avatar.get("work_action")) == "", "E no fim da lista devolve a ferramenta")
	print("TRAINING TOOLS: ", "PASS" if failures == 0 else "FAIL", " (", failures, " falhas)")
	get_tree().quit(0 if failures == 0 else 1)
