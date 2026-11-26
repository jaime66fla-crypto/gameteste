extends SceneTree
## Jogador de verdade (main.tscn) com escudo: fuzil só na mão direita, escudo na
## esquerda; FIXA (ação "shield") levanta a guarda, que só anda (não corre).
## godot --headless --path godot --quit-after 3000 --script res://tests/shield_player.gd
## Com imagens (sem --headless): ... -- --capture=C:/pasta
const Grip = preload("res://scripts/characters/swat_grip.gd")

var failures := 0
var capture := ""

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture = arg.substr(10)
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(1)

func _shot(player: Node3D, label: String, offset: Vector3) -> void:
	if capture.is_empty():
		return
	var cam := Camera3D.new()
	root.add_child(cam)
	var at := player.global_position
	cam.look_at_from_position(at + player.global_basis * offset, at + Vector3(0, 1.2, 0))
	cam.make_current()
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png(capture.path_join(label + ".png"))
	cam.queue_free()
	(player.get("camera") as Camera3D).make_current()

func _run() -> void:
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.position = Vector3(0, 0.1, 10)
	player.set("yaw", 0.0)
	player.set("pitch", 0.0)
	player.call("_equip_weapon", "rifle")
	await _frames(30)
	var avatar: Node3D = player.get("humanoid_avatar")
	check(avatar != null and avatar.has_method("set_shield"), "avatar do jogador aceita escudo")
	if avatar == null:
		quit(1)
		return
	var skel: Skeleton3D = avatar.get("skeleton")
	var weapon: Node3D = player.get("weapon_model")
	var spread_two_hands := float(player.call("current_spread"))
	# Sem escudo, FIXA não faz nada.
	player.call("toggle_shield_guard")
	check(not bool(player.get("shield_raised")), "sem escudo a guarda não levanta")
	player.call("set_shield", "tactical_shield")
	await _frames(40)
	var shield := skel.get_node_or_null("Shield") as Node3D
	check(shield != null and shield.visible, "escudo no braço esquerdo")
	var left := skel.get_bone_global_pose(Grip._bone(skel, "LeftHand")).origin
	var right := skel.get_bone_global_pose(Grip._bone(skel, "RightHand")).origin
	var right_grip := (weapon.get_node("RightGrip") as Marker3D).global_position if weapon != null else Vector3.ZERO
	check(shield != null and shield.transform.origin.distance_to(left) < 0.16, "mão esquerda no punho do escudo")
	check(left.distance_to(right) > 0.3, "mão esquerda saiu do fuzil (uma mão só)")
	check(weapon != null and weapon.visible and skel.to_global(right).distance_to(right_grip) < 0.2, "fuzil continua na mão direita")
	check(float(player.call("current_spread")) > spread_two_hands * 1.2, "fuzil numa mão só espalha mais")
	await _shot(player, "jogador_fuzil_escudo_carregando", Vector3(-2.2, 1.6, -2.4))
	await _press("shield")
	check(bool(player.get("shield_raised")), "FIXA levanta a guarda")
	await _frames(40)
	check(float(avatar.get("shield_weight")) > 0.95, "avatar em guarda")
	var face := shield.transform.basis.z
	check(face.z > 0.85, "guarda: face do escudo para a frente")
	await _shot(player, "jogador_fuzil_escudo_guarda", Vector3(-1.6, 1.7, -3.2))
	await _shot(player, "jogador_fuzil_escudo_guarda_lado", Vector3(-3.2, 1.6, -0.4))
	# Em guarda só anda: segurando correr para a frente não passa da velocidade da guarda.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(60)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("sprint")
	Input.action_release("move_forward")
	check(speed <= float(player.get("SHIELD_GUARD_SPEED")) + 0.05 and not bool(player.get("sprinting")), "em guarda não corre (%.2f m/s)" % speed)
	await _press("shield")
	check(not bool(player.get("shield_raised")), "FIXA de novo abaixa a guarda")
	player.call("set_shield", "")
	await _frames(20)
	left = skel.get_bone_global_pose(Grip._bone(skel, "LeftHand")).origin
	right = skel.get_bone_global_pose(Grip._bone(skel, "RightHand")).origin
	check(left.distance_to(right) < 0.45, "sem escudo, a mão esquerda volta ao fuzil")
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
