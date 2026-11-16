extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
func _press(node: Node, button_name: String) -> bool:
    var button := node.find_child(button_name, true, false) as Button
    if button == null:
        failures.append("Missing character UI action: " + button_name)
        return false
    button.pressed.emit()
    return true
func _run() -> void:
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://character_menu_%s.cfg" % OS.get_process_id()
    var menu: Control = load("res://scenes/menu.tscn").instantiate()
    root.add_child(menu)
    current_scene = menu
    await process_frame
    if not _press(menu, "CharactersButton"):
        printerr("CHARACTER MENU: Personagens button missing")
        quit(1)
        return
    await process_frame
    for id in ["jaime_original", "jaime_swat"]:
        var card := menu.find_child("CharacterCard_" + id, true, false)
        _check(card != null, "Missing card: " + id)
        if card:
            _check(card.find_child("PreviewViewport", true, false) != null, "Missing 3D preview: " + id)
    _press(menu, "Select_jaime_swat")
    await process_frame
    _check(registry.load_selection() == "jaime_swat", "Menu did not save SWAT selection")
    var selected := menu.find_child("Select_jaime_swat", true, false) as Button
    _check(selected != null and selected.disabled, "Selected card not indicated")
    _press(menu, "BackButton")
    await process_frame
    _check(menu.find_child("StartButton", true, false) != null, "Back did not restore menu")
    _press(menu, "StartButton")
    await process_frame
    await process_frame
    _check(current_scene.get_node("Jaime").get("character_id") == "jaime_swat", "Starting match ignored selection")
    current_scene.call("return_to_menu")
    await process_frame
    await process_frame
    _check(current_scene.find_child("CharactersButton", true, false) != null, "Return to menu lost character UI")
    var output: Array = []
    var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/character_restart.gd", "--", registry.storage_path]), output, true)
    _check(code == 0, "Selection was not restored in a fresh Godot process: " + str(output))
    print("FRESH PROCESS RESTART EXIT=", code)
    current_scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures:
        printerr(failure)
    print("CHARACTER MENU: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
