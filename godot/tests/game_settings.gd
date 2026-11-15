extends SceneTree
const Settings = preload("res://scripts/game_settings.gd")
func _initialize() -> void:
    var path := "user://settings_test_%d.cfg" % OS.get_process_id()
    var wanted := {"sensitivity":1.25,"volume":0.35,"msaa":2,"fullscreen":false}
    var error := Settings.save_settings(wanted,path)
    var loaded := Settings.load_settings(path)
    var passed: bool = error == OK and is_equal_approx(loaded["sensitivity"],1.25) and is_equal_approx(loaded["volume"],0.35) and loaded["msaa"] == 2
    Settings.apply(loaded,root)
    passed = passed and root.msaa_3d == Viewport.MSAA_4X and absf(db_to_linear(AudioServer.get_bus_volume_db(0))-0.35) < 0.001
    Settings.save_settings({"sensitivity":-10,"volume":0,"msaa":99},path)
    loaded = Settings.load_settings(path)
    Settings.apply(loaded,root)
    passed = passed and loaded["sensitivity"] == 0.2 and loaded["msaa"] == 2 and AudioServer.is_bus_mute(0)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("GAME SETTINGS: ","PASS" if passed else "FAIL")
    quit(0 if passed else 1)
