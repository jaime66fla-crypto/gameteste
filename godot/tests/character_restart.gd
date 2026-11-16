extends SceneTree
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    # Standalone suite mode also checks disk persistence, without touching the real save.
    var registry = load("res://scripts/characters/character_registry.gd")
    var arguments := OS.get_cmdline_user_args()
    var owned := arguments.is_empty()
    registry.storage_path = "user://character_restart_%s.cfg" % OS.get_process_id() if owned else arguments[0]
    if owned:
        registry.select_character("jaime_swat")
    var passed: bool = registry.load_selection() == "jaime_swat"
    var menu: Control = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
    root.add_child(menu)
    current_scene = menu
    passed = passed and menu.find_child("CharactersButton", true, false) != null
    if menu.has_method("_start_match"):
        menu.call("_start_match")
        await process_frame
        await process_frame
        var player := current_scene.get_node_or_null("Jaime")
        passed = passed and player != null and player.get("character_id") == "jaime_swat"
    else:
        passed = false
    current_scene.queue_free()
    await process_frame
    if owned:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    print("CHARACTER RESTART: ", "PASS" if passed else "FAIL")
    quit(0 if passed else 1)
