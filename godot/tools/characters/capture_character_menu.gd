extends SceneTree
## Foto da tela Personagens (cartões com a prévia 3D de cada personagem).
## Não mexe na seleção salva do jogador: usa um arquivo de seleção próprio.
## godot --path godot --script res://tools/characters/capture_character_menu.gd -- --out=C:/pasta/personagens.png
const Registry = preload("res://scripts/characters/character_registry.gd")

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _run() -> void:
	var out := "user://personagens.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	Registry.storage_path = "user://capture_character_menu.cfg"
	root.size = Vector2i(1600, 900)
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	# O menu reconstrói a tela principal quando o perfil carrega: espera e abre de novo.
	for i in 150:
		await process_frame
	menu.call("_show_characters")
	for i in 60:
		await process_frame
	if menu.find_child("CharacterCards", true, false) == null:
		menu.call("_show_characters")
		for i in 60:
			await process_frame
	root.get_texture().get_image().save_png(out)
	print("salvo: " + out)
	# Prévia 3D de cada cartão em tamanho grande (900 × 630), para conferir a pose.
	var viewports: Array = []
	for card in menu.find_children("CharacterCard_*", "", true, false):
		var viewport := card.find_child("PreviewViewport", true, false) as SubViewport
		if viewport == null:
			continue
		(viewport.get_parent() as SubViewportContainer).stretch = false
		viewport.size = Vector2i(900, 630)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewports.append([str(card.name).trim_prefix("CharacterCard_"), viewport])
	for i in 20:
		await process_frame
	for entry in viewports:
		var path: String = out.get_basename() + "_" + entry[0] + ".png"
		(entry[1] as SubViewport).get_texture().get_image().save_png(path)
		print("salvo: " + path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Registry.storage_path))
	quit(0)
