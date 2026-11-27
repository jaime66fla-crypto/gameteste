extends SceneTree
## Escudo no braço esquerdo (tático e de madeira): carregando fica ao lado do
## corpo com a face para fora; em guarda (FIXA) fica na frente do peito com a
## face para a frente; a mão esquerda segura o punho e a arma vai só na direita.
## godot --headless --path godot --quit-after 3000 --script res://tests/shield_pose.gd
## Com imagens (sem --headless): ... -- --capture=C:/pasta
const Grip = preload("res://scripts/characters/swat_grip.gd")
const ShieldModel = preload("res://scripts/weapons/shield_model.gd")

var failures := 0
var capture := ""
var camera: Camera3D

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
	_run.call_deferred()

func _pose(avatar: Node3D, frames: int, move: float) -> void:
	for i in frames:
		avatar.call("animate", 1.0 / 60.0, move, false, false, false, false, false, Vector2(0, -1), Vector3(0, 0, -2.0 * move))
		await process_frame

func _p(skel: Skeleton3D, name: String) -> Vector3:
	return skel.get_bone_global_pose(Grip._bone(skel, name)).origin

func _shot(label: String, from: Vector3) -> void:
	if capture.is_empty():
		return
	camera.look_at_from_position(from, Vector3(0, 1.15, 0))
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(capture.path_join(label + ".png"))

func _run() -> void:
	if not capture.is_empty():
		DirAccess.make_dir_recursive_absolute(capture)
		root.get_viewport().size = Vector2i(900, 900)
		camera = Camera3D.new()
		camera.fov = 45
		root.add_child(camera)
		camera.make_current()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 30, 0)
		root.add_child(sun)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color("#6b7077")
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
		root.add_child(env)
	var avatar: Node3D = load("res://scenes/characters/atacante.tscn").instantiate()
	root.add_child(avatar)
	await process_frame
	check(bool(avatar.call("is_visual_ready")), "avatar carregado")
	var skel: Skeleton3D = avatar.get("skeleton")
	for id in ShieldModel.IDS:
		avatar.call("set_shield", id, false)
		await _pose(avatar, 50, 0.0)
		var shield := skel.get_node_or_null("Shield") as Node3D
		check(shield != null and shield.visible, "%s: aparece no braço" % id)
		if shield == null:
			continue
		var chest := _p(skel, "Spine2")
		var hand := _p(skel, "LeftHand")
		var side := signf(_p(skel, "LeftArm").x)
		var carry := shield.transform
		print("%s carregando: punho %s mão %s face %s" % [id, carry.origin, hand, carry.basis.z])
		check(hand.y < chest.y - 0.25, "%s carregando: mão esquerda baixa, ao lado do corpo" % id)
		check(carry.origin.distance_to(hand) < 0.16, "%s carregando: o punho está na mão" % id)
		check(carry.basis.z.x * side > 0.6, "%s carregando: face virada para fora (esquerda)" % id)
		await _shot(id + "_carregando", Vector3(-2.4 * side, 1.5, -1.6))
		avatar.call("set_shield", id, true)
		await _pose(avatar, 50, 0.0)
		var guard := shield.transform
		chest = _p(skel, "Spine2")
		hand = _p(skel, "LeftHand")
		var head := _p(skel, "Head")
		var face := guard * ShieldModel.face_center(id)
		print("%s guarda: punho %s mão %s face %s centro %s cabeça %s" % [id, guard.origin, hand, guard.basis.z, face, head])
		check(guard.basis.z.z > 0.85, "%s guarda: face para a frente" % id)
		check(face.z > chest.z + 0.3, "%s guarda: escudo na frente do peito" % id)
		check(guard.origin.distance_to(hand) < 0.16, "%s guarda: o punho está na mão" % id)
		check(face.y > chest.y - 0.35 and face.y < head.y, "%s guarda: cobre o tronco" % id)
		await _shot(id + "_guarda_frente", Vector3(-0.9, 1.6, -3.0))
		await _shot(id + "_guarda_lado", Vector3(3.0, 1.5, -0.8))
		# Andando em guarda continua na mão.
		await _pose(avatar, 40, 1.0)
		check(shield.transform.origin.distance_to(_p(skel, "LeftHand")) < 0.16, "%s guarda andando: na mão" % id)
	avatar.call("set_shield", "", false)
	await _pose(avatar, 5, 0.0)
	var gone := skel.get_node_or_null("Shield")
	check(gone == null or gone.is_queued_for_deletion(), "sem escudo: some do braço")
	# Modelo de bloqueio (outros jogadores): corpo na camada do escudo.
	var blocker := ShieldModel.build("tactical_shield", true)
	var body := blocker.get_node_or_null("ShieldBody") as StaticBody3D
	check(body != null and body.collision_layer == ShieldModel.HitboxScript.LAYER_SHIELD, "escudo dos outros segura tiro (camada LAYER_SHIELD)")
	blocker.free()
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
