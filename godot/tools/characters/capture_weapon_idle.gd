extends SceneTree
## Fotos de perto do personagem parado com cada arma (de lado, de trás em
## três quartos, de frente e de cima), para ver se a arma atravessa o braço
## ou o corpo. De costas a coronha pode parecer entrar no quadril quando só
## passa atrás dele: a foto de cima tira a dúvida.
## Não mexe na seleção salva do jogador: usa um arquivo de seleção próprio.
## godot --path godot --script res://tools/characters/capture_weapon_idle.gd -- --id=remy --out=C:/pasta/remy [--no-stand]
const Registry = preload("res://scripts/characters/character_registry.gd")
const SELECTION := "user://capture_weapon_idle_selection.cfg"
const WEAPONS := ["rifle", "pistol", "smg", "shotgun", "sniper"]

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var id := "remy"
	var out := "user://weapon_idle"
	var stand := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="):
			id = arg.substr(5)
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg == "--no-stand":
			stand = false
	Registry.storage_path = SELECTION
	if Registry.select_character(id) != OK:
		printerr("seleção falhou: " + id)
		quit(1)
		return
	root.get_node("Net").set("in_match", false)
	root.size = Vector2i(640, 720)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	var player := scene.get_node("Jaime") as CharacterBody3D
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var avatar = player.get("humanoid_avatar")
	if avatar != null:
		avatar.set("stand_pose_enabled", stand)
	var cam := Camera3D.new()
	cam.fov = 35.0
	scene.add_child(cam)
	for weapon in WEAPONS:
		player.call("_equip_weapon", weapon)
		if bool(player.get("weapon_holstered")):
			player.call("_toggle_weapon_holster")
		for i in 50:
			await process_frame
		var basis: Basis = player.global_basis
		var chest := player.global_position + Vector3.UP * 1.2
		var skeleton := avatar.get("skeleton") as Skeleton3D if avatar != null else null
		if skeleton != null:
			var bone := skeleton.find_bone(String(avatar.get("bone_prefix")) + "Spine2")
			if bone >= 0:
				chest = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin) + Vector3.DOWN * 0.1
			basis = Basis(Vector3.UP, (avatar as Node3D).global_rotation.y)
		# Lado direito (onde fica a arma) e trás-direita (câmera do jogo).
		for view in [["lado", Vector3(2.2, 0.2, -0.3)], ["costas", Vector3(1.0, 0.5, 2.0)], ["frente", Vector3(0.9, 0.2, -2.1)], ["cima", Vector3(0.05, 2.3, 0.15)]]:
			cam.global_position = chest + basis * (view[1] as Vector3)
			cam.look_at(chest)
			cam.current = true
			for i in 3:
				await process_frame
			root.get_texture().get_image().save_png("%s_%s_%s.png" % [out, weapon, view[0]])
	print("salvo: " + out + "_*.png  personagem=" + str(player.get("character_id")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)
