extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    if not ResourceLoader.exists("res://scripts/ui/match_loading.gd"):
        check(false, "carregamento disponível")
    else:
        var dead := OS.get_cmdline_user_args().has("--dead")
        if OS.get_cmdline_user_args().has("--survival") or dead:
            var net := root.get_node("Net")
            net.set("in_match", true)
            net.set("my_id", "test")
            net.set("host_id", "test")
            net.set("start_info", {"survival": true, "host": "test", "you": {"id": "test", "p": [0, 0.2, 0], "hp": 100, "hunger": 85, "thirst": 85, "inv": {}}, "roster": [], "zombies": [], "animals": [], "vehicles": [], "bags": [], "searched": [], "depleted": {}})
            if dead:
                net.get("start_info")["you"]["dead"] = true
        var loading = load("res://scripts/ui/match_loading.gd").begin(self)
        check(is_instance_valid(loading) and root.has_node("MatchLoading"), "tela aparece antes de carregar")
        for i in 1800:
            await process_frame
            if current_scene != null and bool(current_scene.get("match_ready")):
                break
        check(current_scene != null and bool(current_scene.get("match_ready")), "partida pronta")
        await process_frame
        await process_frame
        check(not root.has_node("MatchLoading"), "tela fecha ao concluir")
        if current_scene != null:
            check(current_scene.get("player") != null, "jogador criado")
            if dead:
                check(not current_scene.get("player").is_physics_processing(), "morte mantém física desativada")
                check(not load("res://scripts/pointer_mode.gd").is_captured(), "morte mantém cursor livre")
                current_scene.get("match_controller").call("_on_respawned", {"p": [0, 0.2, 0], "hp": 100, "inv": {}})
                check(current_scene.get("player").is_processing_unhandled_input(), "renascer restaura os comandos")
    print("MATCH LOADING: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
