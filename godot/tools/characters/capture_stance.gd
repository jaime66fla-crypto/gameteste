extends SceneTree
## Fotos da postura de tiro da UAL (igual ao fps-tatico) dentro do mapa:
## pela câmera do jogo (ombro) e por uma câmera de lado/frente, com fuzil e pistola,
## mira para cima/baixo, andando de lado e no tiro.
## godot --path godot --script res://tools/characters/capture_stance.gd -- --id=atacante --out=C:/pasta/stance
const Registry = preload("res://scripts/characters/character_registry.gd")
const SELECTION := "user://capture_stance_selection.cfg"

var player: CharacterBody3D
var out := "user://stance"


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "_" + name + ".png")
	print("foto " + name)


func _side_camera(on: bool, from_front := false) -> void:
	var cam := root.get_node_or_null("CapturaLado") as Camera3D
	if on:
		if cam == null:
			cam = Camera3D.new()
			cam.name = "CapturaLado"
			root.add_child(cam)
		var fwd := -player.global_basis.z
		var right := player.global_basis.x
		var eye := player.global_position + Vector3.UP * 1.2
		var pos := eye + (fwd * 2.6 + right * 1.2 if from_front else right * 2.8 + fwd * 0.6) + Vector3.UP * 0.1
		cam.global_position = pos
		cam.look_at(eye, Vector3.UP)
		cam.fov = 50
		cam.current = true
	elif cam:
		cam.current = false
		var game_cam: Camera3D = player.get("camera")
		game_cam.current = true


func _run() -> void:
	var id := "atacante"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
	Registry.storage_path = SELECTION
	if Registry.select_character(id) != OK:
		printerr("seleção falhou: " + id)
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	player = scene.get_node_or_null("Jaime") as CharacterBody3D
	if player == null:
		printerr("jogador não encontrado")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for weapon in ["rifle", "pistol"]:
		player.call("_equip_weapon", weapon)
		player.set("pitch", 0.0)
		for i in 70:
			await process_frame
		await _shot(weapon + "_ombro")
		_side_camera(true, true)
		await _shot(weapon + "_frente")
		_side_camera(true, false)
		await _shot(weapon + "_lado")
		player.set("pitch", deg_to_rad(35.0))
		for i in 25:
			await process_frame
		await _shot(weapon + "_lado_cima")
		player.set("pitch", deg_to_rad(-30.0))
		for i in 25:
			await process_frame
		await _shot(weapon + "_lado_baixo")
		player.set("pitch", 0.0)
		_side_camera(false)
		# andando de lado (strafe)
		Input.action_press("move_right")
		for i in 40:
			await physics_frame
		await _shot(weapon + "_strafe")
		Input.action_release("move_right")
		for i in 20:
			await process_frame
		# tiro
		var avatar = player.get("humanoid_avatar")
		if avatar and avatar.has_method("raise_weapon_now"):
			avatar.call("raise_weapon_now")
		for i in 4:
			await process_frame
		_side_camera(true, true)
		await _shot(weapon + "_tiro_frente")
		_side_camera(false)
		print("postura %s: stance=%.2f" % [weapon, float(avatar.get("_stance")) if avatar else -1.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)
