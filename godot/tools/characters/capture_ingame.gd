extends SceneTree
## Fotos do personagem dentro do mapa, pela câmera do jogo (3ª pessoa):
## parado com o fuzil e andando enquanto vira (inclinação nas curvas).
## Não mexe na seleção salva do jogador: usa um arquivo de seleção próprio.
## godot --path godot --script res://tools/characters/capture_ingame.gd -- --id=01 --out=C:/pasta/01
const Registry = preload("res://scripts/characters/character_registry.gd")
const SELECTION := "user://capture_ingame_selection.cfg"

func _initialize() -> void:
	# Watchdog: never leave a window hanging if something fails.
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var id := "01"
	var out := "user://ingame"
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
	var player := scene.get_node_or_null("Jaime") as CharacterBody3D
	if player == null:
		printerr("jogador não encontrado")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player.has_method("_equip_weapon"):
		player.call("_equip_weapon", "rifle")
	for i in 60:
		await process_frame
	root.get_texture().get_image().save_png(out + "_ingame_idle.png")
	# Walk forward and turn: hold W while sweeping the yaw.
	Input.action_press("move_forward")
	for i in 70:
		player.set("yaw", float(player.get("yaw")) + 0.022)
		await physics_frame
	root.get_texture().get_image().save_png(out + "_ingame_turn.png")
	Input.action_release("move_forward")
	print("salvo: " + out + "_ingame_*.png  personagem=" + str(player.get("character_id")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SELECTION))
	quit(0)
