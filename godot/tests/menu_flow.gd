extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
func _press(menu: Node, button_name: String) -> bool:
    var button := menu.find_child(button_name, true, false) as Button
    if button == null:
        failures.append("Missing menu action: " + button_name)
        return false
    button.pressed.emit()
    return true
func _run() -> void:
    var packed = load(ProjectSettings.get_setting("application/run/main_scene"))
    if packed == null:
        failures.append("Menu scene must load")
    else:
        var menu = packed.instantiate()
        root.add_child(menu)
        current_scene = menu
        await process_frame
        # New players get the login screen (the saved session is left untouched).
        menu.call("_show_login", false)
        await process_frame
        _check(menu.find_child("AccountName",true,false) != null and menu.find_child("AccountPassword",true,false) != null, "Login asks for name and password")
        if _press(menu,"SwitchToCreate"):
            _check(menu.find_child("AccountPasswordConfirm",true,false) != null, "Create account confirms the password")
            _press(menu,"SwitchToLogin")
        _press(menu,"OfflineButton")
        await process_frame
        _check(menu.find_child("ExitButton",true,false) != null, "Exit action exists")
        if not root.get_node("Net").call("is_logged_in"):
            _check(menu.find_child("MultiplayerButton",true,false) == null, "Online play needs an account")
            if _press(menu,"LoginButton"):
                _check(menu.find_child("LoginSubmit",true,false) != null, "Offline menu leads back to login")
                _press(menu,"OfflineButton")
                await process_frame
        if _press(menu,"ConfigButton"):
            _check(menu.find_child("SensitivitySlider",true,false) != null, "Mouse setting exists")
            _check(menu.find_child("VolumeSlider",true,false) != null, "Volume setting exists")
            _check(menu.find_child("AASelect",true,false) != null, "Graphics setting exists")
            _press(menu,"BackButton")
        if not InputMap.has_action("fire"):
            InputMap.add_action("fire")
        Input.action_press("fire")
        if _press(menu,"StartButton"):
            await process_frame
            await process_frame
            _check(current_scene.get_node_or_null("Jaime") != null, "Start enters the actual test match")
            _check(not Input.is_action_pressed("fire"), "Menu click does not fire a shot when match starts")
            if current_scene.has_method("return_to_menu"):
                current_scene.call("return_to_menu")
                # A saved session is checked with the server first ("Entrando...").
                var deadline := Time.get_ticks_msec() + 8000
                while Time.get_ticks_msec() < deadline:
                    await process_frame
                    if current_scene != null and (current_scene.find_child("StartButton",true,false) != null or current_scene.find_child("OfflineButton",true,false) != null):
                        break
                # Without an account the menu reopens on the login screen (offline still one click away).
                _check(current_scene.find_child("StartButton",true,false) != null or current_scene.find_child("OfflineButton",true,false) != null, "Can return from match to main menu")
            else:
                failures.append("Match needs a return-to-menu action")
        current_scene.queue_free()
        await process_frame
    for failure in failures:
        printerr(failure)
    print("MENU FLOW: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
