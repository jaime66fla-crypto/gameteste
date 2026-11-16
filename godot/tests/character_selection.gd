extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _run() -> void:
    if not ResourceLoader.exists("res://scripts/characters/character_registry.gd"):
        printerr("CHARACTER SELECTION: registry missing")
        quit(1)
        return
    var registry = load("res://scripts/characters/character_registry.gd")
    var path := "user://character_selection_test_%s.cfg" % OS.get_process_id()
    registry.storage_path = path
    _check(registry.load_selection() == "jaime_original", "Missing save must default to Original")
    _check(registry.all_characters().size() >= 2, "Both characters must stay registered")
    _check(registry.select_character("invalid-id") != OK, "Invalid ID accepted")
    _check(registry.select_character("jaime_swat") == OK, "SWAT selection did not save")
    _check(registry.load_selection() == "jaime_swat", "SWAT selection not restored")
    var config := ConfigFile.new()
    _check(config.load(path) == OK, "Selection ConfigFile is unreadable")
    config.set_value("future", "keep", 42)
    config.save(path)
    _check(registry.select_character("jaime_original") == OK, "Cannot return to Original")
    config.load(path)
    _check(config.get_value("future", "keep", 0) == 42, "Unrelated save fields lost")
    config.set_value("characters", "selected_id", "future-unknown-id")
    config.save(path)
    _check(registry.load_selection() == "jaime_original", "Unknown saved ID must fall back")
    var bad := FileAccess.open(path, FileAccess.WRITE)
    bad.store_string("[characters\nselected_id=\"jaime_swat\"")
    bad.close()
    var corrupted_hash := FileAccess.get_sha256(path)
    _check(registry.load_selection() == "jaime_original", "Corrupt save must fall back")
    _check(FileAccess.get_sha256(path) == corrupted_hash, "Loading overwrote corrupt save")
    _check(registry.select_character("jaime_swat") != OK, "Corrupt save overwritten without recovery")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    for failure in failures:
        printerr(failure)
    print("CHARACTER SELECTION: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
