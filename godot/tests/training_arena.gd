extends Node
## Treino offline: arena do zumbi no parque. O jogador entra, pega o bastão no
## suporte (E), mira no zumbi e golpeia (Q) até matar; depois o zumbi volta.
## Confere: arena livre (nada da cidade dentro), dano 34 do bastão, recuo,
## zumbi preso dentro e não sai caçando quem está fora.
## godot --headless --path godot res://tests/training_arena.tscn
## Foto: godot --path godot res://tests/training_arena.tscn -- --capture=<pasta>
const Arena = preload("res://scripts/training_arena.gd")

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

func _aim_at(player: Node, point: Vector3) -> void:
	var camera: Camera3D = player.get("camera")
	# A câmera segue o jogador suavizada: repete até o centro da tela parar no alvo.
	for k in 10:
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
	var arena: Node3D = main.get_node_or_null("TrainingArena")
	check(arena != null, "a arena existe no treino offline")
	if arena == null:
		get_tree().quit(1)
		return
	# Nada da cidade dentro da arena: só o chão (raios de cima para baixo batem no chão).
	var space := player.get_world_3d().direct_space_state
	var blocked := 0
	var steps := int((Arena.HALF - 0.3) / 0.25)
	for i in range(-steps, steps + 1):
		for k in range(-steps, steps + 1):
			var p := Arena.CENTER + Vector3(i * 0.25, 0, k * 0.25)
			if Arena.RACK.distance_to(p) < 0.6:
				continue # o próprio suporte do bastão
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 6, 0), p + Vector3(0, -1, 0), 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty() and (hit["position"] as Vector3).y > 0.2:
				blocked += 1
	check(blocked == 0, "chão da arena livre (%d pontos com algo em cima)" % blocked)
	if OS.has_environment("ARENA_SCAN"):
		for x in range(-8, 9):
			for z in range(-8, 9):
				var p := Arena.CENTER + Vector3(x, 0, z)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 8, 0), p + Vector3(0, -1, 0), 1))
				if not hit.is_empty() and (hit["position"] as Vector3).y > 1.3:
					var c: Node = hit["collider"]
					print("alto em %s: y=%.1f %s pai=%s" % [p, (hit["position"] as Vector3).y, c.name, c.get_parent().name])
	# Fora da arena o zumbi não caça.
	var zombie: CharacterBody3D = arena.get("zombie")
	var start := zombie.global_position
	player.global_position = Arena.CENTER + Vector3(0, 0.1, -Arena.HALF - 4.0)
	await _frames(120)
	check(zombie.global_position.distance_to(start) < 0.5, "com o jogador fora, o zumbi fica parado")
	# Entra e pega o bastão.
	player.global_position = Arena.RACK + Vector3(-0.8, 0.1, 0.3)
	await _frames(5)
	check(bool(arena.call("_interact")), "E perto do suporte pega o bastão")
	check(bool(arena.get("holding")), "segurando o bastão")
	await _frames(3)
	var avatar: Node3D = player.get("humanoid_avatar")
	check(bool(player.get("weapon_holstered")), "ao pegar o bastão a arma de fogo é guardada")
	check(str(avatar.get("work_action")) == "hold" and avatar.get("_tool_node") != null, "o bastão aparece na mão (pose de carregar no ombro)")
	var sk: Skeleton3D = avatar.get("skeleton")
	var tool: Node3D = avatar.get("_tool_node")
	for side in ["Left", "Right"]:
		var hb := -1
		for b in sk.get_bone_count():
			if sk.get_bone_name(b).ends_with("_" + side + "Hand"):
				hb = b
		var hand := sk.global_transform * sk.get_bone_global_pose(hb).origin
		# Distância da mão ao eixo do cabo do bastão.
		var base := tool.global_position
		var axis := tool.global_basis.y.normalized()
		var along := clampf((hand - base).dot(axis), 0.0, 1.12)
		var gap := hand.distance_to(base + axis * along)
		print("mão %s a %.2f m do cabo (%.2f m do pé do cabo)" % [side, gap, along])
		check(gap < 0.12, "segurando: mão %s no cabo (%.2f m)" % [side, gap])
	if not _capture_folder().is_empty():
		var side_cam := Camera3D.new()
		main.add_child(side_cam)
		side_cam.global_position = player.global_position + Vector3(2.2, 1.5, -1.6)
		side_cam.look_at(player.global_position + Vector3(0, 1.1, 0))
		side_cam.current = true
		await _frames(5)
		get_viewport().get_texture().get_image().save_png(_capture_folder().path_join("arena_segurando.png"))
		var fwd := -player.global_basis.z
		var left := -player.global_basis.x
		side_cam.global_position = player.global_position + Vector3(0, 1.3, 0) + fwd * 1.2 + left * 0.9
		side_cam.look_at(player.global_position + Vector3(0, 1.15, 0))
		await _frames(5)
		get_viewport().get_texture().get_image().save_png(_capture_folder().path_join("arena_segurando_2.png"))
		side_cam.current = false
		side_cam.queue_free()
		await _frames(2)
	# Andando para o lado com o bastão: o corpo vira para onde anda (sem passo lateral).
	player.global_position = Arena.CENTER + Vector3(-2.0, 0.1, 0.5)
	player.set("yaw", 0.0)
	await _frames(5)
	Input.action_press("move_right")
	await _frames(45)
	var turned := float(player.get("avatar").rotation.y)
	var clip := str(avatar.get("current_clip"))
	if not _capture_folder().is_empty():
		get_viewport().get_texture().get_image().save_png(_capture_folder().path_join("arena_andando_de_lado.png"))
	Input.action_release("move_right")
	print("andando para a direita: corpo girado %.0f° em relação à câmera, clipe %s" % [rad_to_deg(turned), clip])
	check(absf(wrapf(turned + PI * 0.5, -PI, PI)) < 0.25, "com o bastão, andar para a direita vira o corpo para a direita (%.0f°)" % rad_to_deg(turned))
	check(not clip.ends_with("_right") and not clip.ends_with("_left"), "e anda para a frente, sem passo lateral (clipe %s)" % clip)
	await _frames(20)
	player.call("face_aim", 0.5)
	await _frames(20)
	check(absf(float(player.get("avatar").rotation.y)) < 0.15, "ao golpear o corpo vira para a mira (%.0f°)" % rad_to_deg(float(player.get("avatar").rotation.y)))
	player.global_position = Arena.RACK + Vector3(-0.8, 0.1, 0.3)
	await _frames(5)
	# Clique esquerdo com o bastão: golpeia (não atira).
	var ammo_before := int(player.get("ammo"))
	var swing_before := float(arena.get("_swing_left"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(2)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		arena.set("_cooldown", 0.0)
		Input.action_press("fire")
		await _frames(2)
		Input.action_release("fire")
		check(float(arena.get("_swing_left")) > swing_before and str(avatar.get("work_action")) == "swing", "clique esquerdo com o bastão faz o golpe")
		check(int(player.get("ammo")) == ammo_before, "clique esquerdo com o bastão não atira")
		await _frames(45)
		check(str(avatar.get("work_action")) == "hold", "depois do golpe volta a carregar o bastão")
	else:
		print("aviso: sem captura do mouse aqui (headless); clique esquerdo não testado")
	# Golpeia até matar (60 de vida: 2 golpes de 34).
	var hp_before := float(zombie.get("hp"))
	var swings := 0
	while not bool(zombie.get("dead")) and swings < 12:
		var target := zombie.global_position + Vector3(0, 1.2, 0)
		var dist := Vector2(target.x - player.global_position.x, target.z - player.global_position.z).length()
		if dist > 2.6:
			# Chega perto (como o jogador faria), mas fica fora do bote.
			var dir := (zombie.global_position - player.global_position)
			dir.y = 0.0
			player.global_position = zombie.global_position - dir.normalized() * 2.3 + Vector3(0, 0.1, 0)
			player.global_position.x = clampf(player.global_position.x, Arena.CENTER.x - 3.4, Arena.CENTER.x + 3.4)
			player.global_position.z = clampf(player.global_position.z, Arena.CENTER.z - 3.4, Arena.CENTER.z + 3.4)
			await _frames(2)
		await _aim_at(player, zombie.global_position + Vector3(0, 1.2, 0))
		arena.set("_cooldown", 0.0)
		var before := float(zombie.get("hp"))
		var pos_before := zombie.global_position
		arena.call("_melee")
		swings += 1
		print("  golpe %d: distância %.2f, vida %.0f -> %.0f, jogador %s, zumbi %s" % [swings, Vector2(zombie.global_position.x - player.global_position.x, zombie.global_position.z - player.global_position.z).length(), before, float(zombie.get("hp")), player.global_position, zombie.global_position])
		if swings == 1:
			check(is_equal_approx(before - float(zombie.get("hp")), 34.0) or is_equal_approx(before - float(zombie.get("hp")), 51.0), "golpe do bastão tira 34 (51 na cabeça): tirou %.0f" % (before - float(zombie.get("hp"))))
			await _frames(30)
			var pushed := Vector2(zombie.global_position.x - pos_before.x, zombie.global_position.z - pos_before.z).length()
			check(pushed > 0.4, "o zumbi recua com o golpe (%.2f m)" % pushed)
			var shot := _capture_folder()
			if not shot.is_empty():
				get_viewport().get_texture().get_image().save_png(shot.path_join("arena_golpe.png"))
		await _frames(40)
	print("golpes: %d  vida antes %.0f  acertos %d  mordidas %d" % [swings, hp_before, arena.get("hits"), arena.get("bites")])
	check(bool(zombie.get("dead")), "o zumbi morre a golpes de bastão (%d golpes)" % swings)
	check(int(arena.get("kills")) == 1, "abate contado")
	await _frames(int(Arena.RESPAWN * 60) + 30)
	var fresh: CharacterBody3D = arena.get("zombie")
	check(fresh != zombie and not bool(fresh.get("dead")) and Arena.new().inside(fresh.global_position), "o zumbi volta dentro da arena")
	# Larga o bastão: volta ao soco.
	player.global_position = Arena.RACK + Vector3(-0.8, 0.1, 0.3)
	await _frames(3)
	arena.call("_interact")
	check(not bool(arena.get("holding")), "E de novo larga o bastão")
	# Sem arma (guardada, sem bastão): também vira para onde anda.
	check(bool(player.get("weapon_holstered")) and str(player.get("melee_weapon")) == "", "largou o bastão e está de mãos vazias")
	player.global_position = Arena.CENTER + Vector3(-2.0, 0.1, 0.5)
	player.set("yaw", 0.0)
	await _frames(5)
	Input.action_press("move_right")
	await _frames(45)
	var turned_free := float(player.get("avatar").rotation.y)
	var clip_free := str(avatar.get("current_clip"))
	Input.action_release("move_right")
	print("sem arma, andando para a direita: corpo %.0f°, clipe %s" % [rad_to_deg(turned_free), clip_free])
	check(absf(wrapf(turned_free + PI * 0.5, -PI, PI)) < 0.25 and not clip_free.ends_with("_right"), "sem arma, andar para o lado vira o corpo e corre de frente (%.0f°, %s)" % [rad_to_deg(turned_free), clip_free])
	await _frames(15)
	player.global_position = Arena.RACK + Vector3(-0.8, 0.1, 0.3)
	await _frames(3)
	# Pegar de novo e sacar a pistola (tecla 3): o bastão volta para o suporte.
	arena.call("_interact")
	await _frames(2)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_3
	key.keycode = KEY_3
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(3)
	check(str(player.get("melee_weapon")) == "" and not bool(arena.get("holding")), "sacar uma arma larga o bastão")
	# Com a pistola na mão o corpo segue a câmera (passo lateral de quem mira).
	Input.action_press("move_right")
	await _frames(40)
	var gun_turn := float(player.get("avatar").rotation.y)
	Input.action_release("move_right")
	check(not bool(player.get("weapon_holstered")) and absf(gun_turn) < 0.05, "com arma de fogo o corpo continua de frente para a mira (%.0f°)" % rad_to_deg(gun_turn))
	# Zumbi preso: mesmo empurrado para fora, volta para dentro.
	fresh.global_position = Arena.CENTER + Vector3(0, 0.05, -Arena.HALF - 2.0)
	await _frames(3)
	check(Arena.new().inside(fresh.global_position), "o zumbi não sai da arena")
	var folder := _capture_folder()
	if not folder.is_empty():
		player.global_position = Arena.CENTER + Vector3(-2.5, 0.1, -Arena.HALF - 3.0)
		await _aim_at(player, Arena.CENTER + Vector3(0, 0.8, 0))
		await _frames(20)
		get_viewport().get_texture().get_image().save_png(folder.path_join("arena_visao.png"))
		var top := Camera3D.new()
		main.add_child(top)
		top.global_position = Arena.CENTER + Vector3(0, 16, 9)
		top.look_at(Arena.CENTER)
		top.current = true
		await _frames(10)
		get_viewport().get_texture().get_image().save_png(folder.path_join("arena_cima.png"))
	print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures else 0)

func _capture_folder() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.substr(10)
	return ""
