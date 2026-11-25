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
    # Qualidade: padrão Alta no PC (3D em resolução cheia); Baixa limita MSAA a 2× e desenha o 3D a 75%.
    passed = passed and loaded["quality"] == Settings.QUALITY_HIGH and is_equal_approx(root.scaling_3d_scale, 1.0)
    Settings.apply({"msaa":2,"quality":Settings.QUALITY_LOW},root)
    passed = passed and root.msaa_3d == Viewport.MSAA_2X and is_equal_approx(root.scaling_3d_scale, 0.75)
    Settings.save_settings({"quality":99},path)
    passed = passed and Settings.load_settings(path)["quality"] == Settings.QUALITY_HIGH
    # Sem arquivo salvo: MSAA começa em 2×.
    passed = passed and Settings.load_settings("user://nao_existe_%d.cfg" % OS.get_process_id())["msaa"] == 1
    # Sombra: Alta usa 2 faixas e mantém o alcance do mapa; Baixa usa 1 faixa até 40 m.
    var sun := DirectionalLight3D.new()
    sun.directional_shadow_max_distance = 80.0
    Settings.apply_shadow_quality(sun, Settings.QUALITY_HIGH)
    passed = passed and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS and is_equal_approx(sun.directional_shadow_max_distance, 80.0)
    Settings.apply_shadow_quality(sun, Settings.QUALITY_LOW)
    passed = passed and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and is_equal_approx(sun.directional_shadow_max_distance, 40.0)
    sun.free()
    Settings.apply({"msaa":2,"quality":Settings.QUALITY_HIGH},root)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("GAME SETTINGS: ","PASS" if passed else "FAIL")
    quit(0 if passed else 1)
