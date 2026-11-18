extends SceneTree
## Editar perfil: botão no cartão, tela com foto e nick, foto preparada
## (quadrado 128 px JPEG) e foto aparecendo nos círculos quando baixada.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var net: Node = root.get_node("Net")
	var saved_token: String = net.get("session_token")
	var saved_profile: Dictionary = net.get("profile")
	net.set("session_token", "test-token")
	net.set("profile", {"name": "Jaimexzz", "rank": "Cabo", "xp": 900, "avatar": 0, "renamedAt": 0})
	net.set("_friends_timer", 999.0)
	var menu = load("res://scenes/menu.tscn").instantiate()
	menu.set("leaderboard_cache", {"players": []})
	menu.set("_suppress_ui_save", true)
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.call("_show_main")
	await process_frame
	var edit := menu.find_child("EditProfileButton", true, false) as Button
	_check(edit != null, "Profile card has an Edit button")
	edit.pressed.emit()
	await process_frame
	var nick := menu.find_child("NickField", true, false) as LineEdit
	_check(nick != null and nick.text == "Jaimexzz", "Editor shows the current nick")
	_check(menu.find_child("ChoosePhotoButton", true, false) != null, "Editor can choose a photo")
	var remove := menu.find_child("RemovePhotoButton", true, false) as Button
	_check(remove != null and remove.disabled, "No photo yet: remove is disabled")
	# Foto preparada: centro em quadrado, 128×128, JPEG.
	var wide := Image.create(400, 200, false, Image.FORMAT_RGBA8)
	wide.fill(Color(0.2, 0.5, 0.9))
	var bytes: PackedByteArray = menu.photo_bytes(wide)
	_check(bytes.size() > 100 and bytes.size() < 60 * 1024 and bytes[0] == 0xFF and bytes[1] == 0xD8, "Photo becomes a small JPEG (%d bytes)" % bytes.size())
	var check_image := Image.new()
	check_image.load_jpg_from_buffer(bytes)
	_check(check_image.get_width() == 128 and check_image.get_height() == 128, "Photo is 128x128")
	# Recém trocado: botão de salvar nick travado com aviso.
	net.set("profile", {"name": "Jaimexzz", "rank": "Cabo", "xp": 900, "avatar": 0, "renamedAt": int(Time.get_unix_time_from_system() * 1000.0)})
	menu.call("_show_profile_editor")
	await process_frame
	var save := menu.find_child("SaveNickButton", true, false) as Button
	_check(save != null and save.disabled, "Nick change locked for a day after renaming")
	# Foto em cache: os círculos mostram a foto no lugar das iniciais.
	var texture := ImageTexture.create_from_image(check_image)
	var cache: Dictionary = net.get("_avatar_cache")
	cache["Ana"] = {"version": 7, "texture": texture}
	var badge: Control = menu.call("_avatar_badge", "Ana", true, 28.0, 7)
	_check(badge.get_node_or_null("Photo") != null and not badge.get_node("Initials").visible, "Badge shows the photo when it is loaded")
	var plain: Control = menu.call("_avatar_badge", "Beto", true, 28.0, 0)
	_check(plain.get_node_or_null("Photo") == null and plain.get_node("Initials").visible, "No photo: initials")
	badge.free()
	plain.free()
	cache.erase("Ana")
	menu.queue_free()
	await process_frame
	net.set("session_token", saved_token)
	net.set("profile", saved_profile)
	for failure in failures:
		printerr(failure)
	print("PROFILE EDIT: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
