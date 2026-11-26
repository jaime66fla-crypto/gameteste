extends SceneTree
## Termos de Uso: criar conta exige aceitar; a janela abre por cima sem apagar o que foi digitado.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _press(menu: Node, button_name: String) -> bool:
	var button := menu.find_child(button_name, true, false) as BaseButton
	if button == null:
		failures.append("Missing button: " + button_name)
		return false
	button.pressed.emit()
	return true

func _run() -> void:
	var menu = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.set("_suppress_ui_save", true)

	menu.call("_show_login", true)
	await process_frame
	var accept := menu.find_child("AcceptTerms", true, false) as CheckBox
	_check(accept != null and not accept.button_pressed, "Create account shows an unticked terms checkbox")
	var name_field := menu.find_child("AccountName", true, false) as LineEdit
	name_field.text = "TesteTermos"
	_press(menu, "LoginSubmit")
	var feedback := menu.find_child("LoginFeedback", true, false) as Label
	_check(feedback != null and "Termos" in feedback.text, "Creating an account without accepting the terms is blocked")

	_press(menu, "ReadTermsButton")
	await process_frame
	var overlay: Node = menu.get_node_or_null("TermsOverlay")
	_check(overlay != null, "Terms link opens the terms window")
	if overlay != null:
		var text := overlay.find_child("TermsText", true, false) as RichTextLabel
		_check(text != null and "arrependimento" in text.get_parsed_text(), "Terms text includes the refund rule")
		_check(text != null and "LGPD" in text.get_parsed_text(), "Terms text includes the privacy section")
		_press(menu, "ReadTermsButton") # segundo clique não abre outra janela
		await process_frame
		var count := 0
		for child in menu.get_children():
			if child.name.begins_with("TermsOverlay"):
				count += 1
		_check(count == 1, "Only one terms window at a time")
		_press(overlay, "TermsCloseButton")
		await process_frame
		_check(menu.get_node_or_null("TermsOverlay") == null, "Close button closes the terms window")
	_check(name_field.text == "TesteTermos", "Reading the terms keeps what was typed")

	menu.call("_show_login", false)
	await process_frame
	_check(menu.find_child("AcceptTerms", true, false) == null and menu.find_child("ReadTermsButton", true, false) != null, "Login screen links the terms without a checkbox")

	menu.call("_show_config")
	await process_frame
	_press(menu, "TermsButton")
	await process_frame
	_check(menu.get_node_or_null("TermsOverlay") != null, "Settings opens the terms")

	menu.call("_show_main")
	await process_frame
	_check(menu.find_child("FooterTermsButton", true, false) != null, "Main menu footer links the terms")

	menu.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("TERMS FLOW: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
