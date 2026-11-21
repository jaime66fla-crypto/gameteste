extends SceneTree
class Controller extends Node:
    var ui := CanvasLayer.new()
    var local_dead := false
    var inv: Dictionary = {}
    func is_driving() -> bool: return false
    func _toast(_text: String) -> void: pass
var failures := 0
func check(ok: bool, text: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", text)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    load("res://scripts/controls.gd").reset()
    var controller := Controller.new()
    root.add_child(controller)
    controller.add_child(controller.ui)
    var player = load("res://scripts/player.gd").new()
    var building = load("res://scripts/survival/survival_building.gd").new()
    building.setup(controller, controller, player)
    building.offline = true
    building.my_tag = "test"
    controller.add_child(building)
    building.rules.add({"id": "base", "kind": "foundation", "i": 0, "j": 0, "k": 0, "ow": "test", "hp": 100})
    building.set_building(true)
    building.set("_aimed_id", "base")
    building.call("_demolish_aimed")
    check(player.channel_left > 0, "desmonte iniciou")
    if building.has_method("cancel_demolition"):
        var button: Button = building.get("_cancel_demolition_button")
        check(button.visible, "botão visível durante o desmonte")
        button.emit_signal("pressed")
        check(player.channel_left == 0 and not player.get("_channel_done").is_valid(), "cancelar elimina a ação e o callback")
        check(building.rules.pieces.has("base"), "cancelar preserva a construção")
        building.call("_demolish_aimed")
        var esc := InputEventKey.new()
        esc.physical_keycode = KEY_ESCAPE
        esc.pressed = true
        check(building.handle_input(esc) and player.channel_left == 0, "Esc cancela desmonte")
        building.call("_demolish_aimed")
        building.set_building(false)
        check(player.channel_left == 0, "sair da construção cancela desmonte")
    else:
        check(false, "cancelamento disponível")
    player.free()
    controller.free()
    print("DEMOLITION CANCEL: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
