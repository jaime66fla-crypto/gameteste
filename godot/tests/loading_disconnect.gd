extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var loading = load("res://scripts/ui/match_loading.gd").begin(self)
    if OS.get_cmdline_user_args().has("--during-build"):
        for i in 1200:
            await process_frame
            if current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn":
                break
    root.get_node("Net").emit_signal("connection_lost", "Conexão interrompida no carregamento")
    for i in 120:
        await process_frame
    var button: Button = loading.get("_retry")
    var message: Label = loading.get("_message")
    var ok := button.visible and message.text == "Conexão interrompida no carregamento"
    if current_scene != null:
        ok = ok and not bool(current_scene.get("match_ready"))
    if not ok:
        printerr("FAIL: perda de conexão precisa oferecer retorno ao menu")
    print("LOADING DISCONNECT: ", "PASS" if ok else "FAIL")
    quit(0 if ok else 1)
