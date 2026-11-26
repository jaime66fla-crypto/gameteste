extends SceneTree
## Cofre: poses Parado / Mirando / Atirando da prévia, em todos os personagens.
## Mirando = cano reto (low ready aponta para baixo); Atirando = coice + clarão.
## Com `-- shot=<pasta>` (sem --headless) salva prints mirando e atirando.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _card(menu: Node) -> Node:
	var cards := menu.find_children("CharacterCard_*", "", true, false)
	return cards[0] if not cards.is_empty() else null

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _press(menu: Node, node_name: String) -> bool:
	var b := menu.find_child(node_name, true, false) as Button
	if b == null:
		return false
	b.pressed.emit()
	return true

## Inclinação do cano (seno: + para cima, - para baixo).
func _barrel_pitch(card: Node) -> float:
	var weapon: Node3D = card.visual.get("bound_weapon")
	if not is_instance_valid(weapon):
		return NAN
	return (-weapon.global_basis.z).normalized().dot(card.visual.global_basis.y.normalized())

func _run() -> void:
	Engine.max_fps = 60
	var registry = load("res://scripts/characters/character_registry.gd")
	registry.storage_path = "user://character_poses_%s.cfg" % OS.get_process_id()
	var shot_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("shot="):
			shot_dir = arg.trim_prefix("shot=")
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	for i in 900:
		await process_frame
		if menu.find_child("CharactersButton", true, false) != null or menu.find_child("LoginButton", true, false) != null:
			break
	var net := root.get_node("Net")
	if str(net.get("session_token")).is_empty():
		net.set("session_token", "0".repeat(64))
	var owned := []
	for entry in registry.all_characters():
		owned.append(entry.id)
	net.set("profile", {"name": "Teste", "brasas": 0, "owned": owned})
	menu.call("_show_characters")
	await process_frame
	var count: int = registry.owned_characters().size()
	_check(count >= 5, "Cofre deveria ter os 5 personagens, tem %d" % count)
	for index in count:
		var card := _card(menu)
		if card == null:
			_check(false, "Sem carta no índice %d" % index)
			break
		var id := str(card.name).trim_prefix("CharacterCard_")
		_check(menu.find_child("Pose_aim", true, false) != null and menu.find_child("Pose_fire", true, false) != null and menu.find_child("Pose_idle", true, false) != null, id + ": botões de pose faltando")
		# Sem arma, "Mirando" equipa uma e já mira.
		if index == 0:
			_check(menu.find_child("PreviewWeapon", true, false) == null, id + ": prévia já começou armada")
			_press(menu, "Pose_aim")
			await process_frame
			card = _card(menu)
			_check(menu.find_child("PreviewWeapon", true, false) != null, id + ": Mirando sem arma não equipou a arma")
		_check(card.pose == "aim", id + ": pose deveria ser aim, é " + str(card.pose))
		await _wait(0.8)
		var aim_pitch := _barrel_pitch(card)
		_check(absf(aim_pitch) < 0.14, id + ": mirando, o cano deveria ficar reto (seno %.2f)" % aim_pitch)
		if index == 0 and not shot_dir.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot_dir.path_join("pose_aim.png"))
			print("SHOT aim")
		# Atirando: rajadas com coice e clarão.
		_press(menu, "Pose_fire")
		var shots_before: int = card.shots_fired
		var flash_seen := false
		var max_rise := -INF
		var flash_shot_saved := shot_dir.is_empty() or index != 0
		for f in 150:
			await process_frame
			max_rise = maxf(max_rise, _barrel_pitch(card) - aim_pitch)
			if card.is_flash_visible():
				flash_seen = true
				if not flash_shot_saved:
					# A prévia é um SubViewport: o clarão chega à tela um quadro depois.
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(shot_dir.path_join("pose_fire.png"))
					print("SHOT fire")
					flash_shot_saved = true
		print("%s: mira %.3f, coice +%.3f, tiros %d, clarão %s" % [id, aim_pitch, max_rise, card.shots_fired - shots_before, flash_seen])
		_check(card.shots_fired - shots_before >= 2, id + ": Atirando não disparou (%d tiros)" % (card.shots_fired - shots_before))
		_check(flash_seen, id + ": clarão do cano nunca apareceu")
		_check(max_rise > 0.04, id + ": coice não levantou o cano (%.3f)" % max_rise)
		# Parado: volta ao low ready (cano para baixo) e para de atirar.
		_press(menu, "Pose_idle")
		await _wait(0.8)
		var shots_idle: int = card.shots_fired
		await _wait(0.4)
		_check(card.shots_fired == shots_idle, id + ": continuou atirando parado")
		_check(_barrel_pitch(card) < -0.3, id + ": parado, o cano deveria voltar para baixo (seno %.2f)" % _barrel_pitch(card))
		# Próximo personagem já vem mirando (a pose fica salva no Cofre).
		_press(menu, "Pose_aim")
		_press(menu, "NextCharacter")
		await process_frame
		await process_frame
	# Trocar a arma mantém a pose; "Guardar arma" volta ao parado sem arma.
	# Todas as armas miram reto e atiram (pistola com as duas mãos à frente).
	var card := _card(menu)
	for w in 5:
		_press(menu, "CycleWeaponButton")
		await process_frame
		card = _card(menu)
		_check(card != null and card.pose == "aim", "Trocar a arma perdeu a pose de mira")
		if card == null:
			break
		await _wait(0.5)
		var pitch := _barrel_pitch(card)
		_check(absf(pitch) < 0.14, "%s: mirando, o cano deveria ficar reto (seno %.2f)" % [card.weapon_id, pitch])
		var before: int = card.shots_fired
		card.fire_once()
		_check(card.shots_fired == before + 1, card.weapon_id + ": fire_once não disparou")
		if card.weapon_id == "pistol" and not shot_dir.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot_dir.path_join("pose_pistol_fire.png"))
			print("SHOT pistol")
	_press(menu, "EquipWeaponButton")
	await process_frame
	card = _card(menu)
	_check(menu.find_child("PreviewWeapon", true, false) == null, "Guardar arma não tirou a arma")
	_check(card != null and card.pose == "idle", "Guardar arma deveria voltar a pose para Parado")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
	for failure in failures:
		printerr(failure)
	print("CHARACTER POSES: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
