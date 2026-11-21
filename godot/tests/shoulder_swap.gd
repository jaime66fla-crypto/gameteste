extends SceneTree
const Controls = preload("res://scripts/controls.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    Controls.reset()
    check(Controls.binding("shoulder_swap") == KEY_Q, "Q alterna o ombro")
    check(Controls.binding("lean_left") != KEY_Q, "Q não inclina ao trocar ombro")
    var path := "C:/Users/jaime/Documents/Codex/2026-11-20/bot-o-de-cancelar-destruir-constru/work/legacy-controls.cfg"
    var legacy := ConfigFile.new()
    legacy.set_value("controls", "lean_left", KEY_J)
    legacy.set_value("controls", "reload", KEY_Q)
    legacy.save(path)
    Controls.load_and_apply(path)
    check(Controls.binding("reload") == KEY_Q and Controls.binding("shoulder_swap") != KEY_Q, "migração preserva Q personalizado sem conflito")
    legacy.set_value("controls", "lean_left", KEY_Q)
    legacy.set_value("controls", "reload", KEY_R)
    legacy.save(path)
    Controls.load_and_apply(path)
    check(Controls.binding("shoulder_swap") == KEY_Q and Controls.binding("lean_left") == KEY_J, "migração do padrão antigo mantém Q para troca")
    Controls.reset()
    var player = load("res://scripts/player.gd").new()
    if player.has_method("swap_shoulder"):
        player.call("swap_shoulder")
        check(player.get("shoulder_side") == -1.0, "primeiro toque: esquerda")
        player.call("swap_shoulder")
        check(player.get("shoulder_side") == 1.0, "segundo toque: direita")
    else:
        check(false, "troca de ombro disponível")
    var world := Node3D.new()
    root.add_child(world)
    world.add_child(player)
    player.set_physics_process(false)
    player.set_process_unhandled_input(false)
    for side in [-1.0, 1.0]:
        var wall := StaticBody3D.new()
        var collision := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(0.2, 5, 5)
        collision.shape = box
        wall.add_child(collision)
        wall.position = Vector3(side * 0.6, 1.5, 0)
        world.add_child(wall)
    await physics_frame
    await physics_frame
    var left: float = player.call("_shoulder_room", -1.0)
    var right: float = player.call("_shoulder_room", 1.0)
    check(left <= 0.0 and left > -0.45 and right >= 0.0 and right < 0.45, "paredes limitam a câmera nos dois lados")
    world.free()
    print("SHOULDER SWAP: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
