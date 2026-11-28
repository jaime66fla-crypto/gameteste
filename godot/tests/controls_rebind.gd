extends SceneTree
## Configurações › Controles: trocar a tecla de uma ação, troca automática com
## quem já usava a tecla, salvar/carregar, restaurar padrão e o jogo obedecer.
const Controls = preload("res://scripts/controls.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _key(code: int, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = pressed
	return e

func _run() -> void:
	# O menu salva no arquivo real: guarda o do jogador e devolve no fim.
	var real_backup := FileAccess.get_file_as_bytes(Controls.PATH) if FileAccess.file_exists(Controls.PATH) else PackedByteArray()
	var had_real := FileAccess.file_exists(Controls.PATH)
	var path := "user://controls_test_%d.cfg" % OS.get_process_id()
	Controls.load_and_apply(path)
	_check(_key(KEY_E).is_action("interact"), "Default: E interacts")
	_check(not InputMap.has_action("melee") and _key(KEY_Q).is_action("shoulder_swap") and _key(KEY_J).is_action("lean_left"), "Default: Q swaps shoulder and J leans (punch is the left click)")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_check(click.is_action("fire") and Controls.label_of("fire").contains("soco"), "Left click fires / punches")
	# Trocar interagir para F: F era de curar, então curar fica com E.
	var swapped := Controls.set_binding("interact", KEY_F)
	_check(_key(KEY_F).is_action("interact") and not _key(KEY_E).is_action("interact"), "Interact moved to F")
	_check(_key(KEY_E).is_action("heal") and swapped == "Curar", "Heal took the old key (swap): %s" % swapped)
	_check(_key(KEY_F).is_action("lean_right") and not _key(KEY_E).is_action("lean_right"), "Lean follows interact so healing does not also lean")
	# Botão do mouse também vale.
	Controls.set_binding("grenade", -MOUSE_BUTTON_XBUTTON1)
	var side := InputEventMouseButton.new()
	side.button_index = MOUSE_BUTTON_XBUTTON1
	side.pressed = true
	_check(side.is_action("grenade"), "Mouse side button bound to grenade")
	_check(Controls.key_name(-MOUSE_BUTTON_XBUTTON1) == "Botão lateral 1" and Controls.key_name(KEY_SPACE) == "Espaço", "Readable key names")
	_check(Controls.code_of(_key(KEY_ESCAPE)) == 0, "ESC cannot be bound")
	_check(Controls.help_text().contains("F interagir"), "F1 help shows the current keys")
	# Salva e carrega de novo.
	_check(Controls.save(path) == OK, "Controls saved")
	Controls.reset()
	_check(_key(KEY_E).is_action("interact"), "Reset restores defaults")
	Controls.load_and_apply(path)
	_check(_key(KEY_F).is_action("interact") and side.is_action("grenade"), "Saved keys come back on load")
	# O jogo obedece: o jogador usa a ação, não a tecla fixa.
	var scene := Node3D.new()
	root.add_child(scene)
	var player: Node3D = load("res://scripts/player.gd").new()
	scene.add_child(player)
	player.set_physics_process(false)
	var heals := [0]
	player.set("heal_handler", func(): heals[0] += 1)
	player.call("_unhandled_input", _key(KEY_E))
	_check(heals[0] == 1, "Player heals with the new key (E)")
	player.call("_unhandled_input", _key(KEY_F))
	_check(heals[0] == 1, "Old heal key (F) no longer heals")
	# Tela do menu: uma linha por ação.
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	Controls.set_binding("interact", KEY_F) # o menu recarregou o arquivo real ao abrir
	menu.call("_show_controls")
	await process_frame
	_check(menu.find_child("Bind_interact", true, false) != null and (menu.find_child("Bind_interact", true, false) as Button).text == "F", "Controls screen shows the current key")
	_check(menu.find_child("ResetControlsButton", true, false) != null, "Controls screen can reset")
	(menu.find_child("Bind_reload", true, false) as Button).pressed.emit()
	menu.call("_input", _key(KEY_V))
	await process_frame
	await process_frame
	_check(_key(KEY_V).is_action("reload"), "Clicking a key and pressing V rebinds reload")
	menu.queue_free()
	scene.queue_free()
	await process_frame
	Controls.reset()
	Controls.apply()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if had_real:
		var restore := FileAccess.open(Controls.PATH, FileAccess.WRITE)
		restore.store_buffer(real_backup)
		restore.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Controls.PATH))
	for failure in failures:
		printerr(failure)
	print("CONTROLS REBIND: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
