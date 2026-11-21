extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", text)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    if not ResourceLoader.exists("res://scripts/survival/collectible_glow.gd"):
        check(false, "brilho dos coletáveis disponível")
    else:
        var world = load("res://scripts/survival/survival_world.gd").new()
        world.staged_loading = true
        root.add_child(world)
        world.call("_light_resource", {"id": "r1", "p": [0, 0, 0]}, "stick", Vector3.ZERO)
        var glow = load("res://scripts/survival/collectible_glow.gd").new()
        world.add_child(glow)
        glow.setup(world.resources)
        world.set("_resource_glow", glow)
        check(glow.is_active("r1"), "galho disponível brilha")
        world.set_depleted("r1", true)
        check(not glow.is_active("r1"), "coletado não brilha")
        world.set_depleted("r1", false)
        check(glow.is_active("r1"), "recurso reaparecido volta a brilhar")
        world.call("_container", {"id": "testbox", "type": "crate", "p": [4, 0, 0]})
        world.set_container_empty("testbox", true)
        check(not world.containers.testbox.glow.visible, "recipiente vazio perde brilho")
        world.set_container_empty("testbox", false)
        check(world.containers.testbox.glow.visible, "recipiente reposto recupera brilho")
        world.call("add_branch", {"id": "tb_r2", "kind": "stick", "tree": "r2", "p": [2, 0.025, 1]}, true)
        check(world.resources.has("tb_r2") and glow.is_active("tb_r2"), "novo galho cai e recebe destaque")
        var node: Node3D = world.resources["tb_r2"].node
        check(absf(node.position.y - 0.025) < 0.001, "posição de coleta permanece no chão durante animação")
        world.call("remove_branch", "tb_r2")
        check(not world.resources.has("tb_r2") and not glow.is_active("tb_r2"), "coletar remove galho e brilho")
        var crate = load("res://scripts/net/loot_crate.gd").new()
        crate.setup({"id": "test-crate", "items": {"rifle": 60}})
        world.add_child(crate)
        await physics_frame
        var crate_glow := crate.get_node_or_null("CollectibleGlow") as MeshInstance3D
        check(crate_glow != null, "suprimentos de outros modos também brilham")
        if crate_glow != null:
            crate.mark_opened()
            check(not crate_glow.visible, "caixa aberta não brilha")
            crate.refill({"items": {"rifle": 60}})
            check(crate_glow.visible, "suprimentos repostos voltam a brilhar")
        world.free()
    print("COLLECTIBLE GLOW: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
