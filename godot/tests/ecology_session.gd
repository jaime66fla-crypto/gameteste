extends SceneTree
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
    if not ok:
        failures.append(what)
        printerr("FAIL: ", what)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var net := root.get_node("Net")
    net.set("in_match", true)
    net.set("my_id", "audit")
    net.set("host_id", "audit")
    net.set("start_info", {"survival": true, "you": {"id": "audit", "p": [70, 0.2, 0], "hp": 100, "hunger": 85, "thirst": 85, "inv": {}, "cap": 20}, "roster": [], "zombies": [], "vehicles": [], "bags": [], "animals": [{"id": "w", "kind": "wolf", "hp": 70, "p": [0, 0.3, 0], "fed": 12}, {"id": "d", "kind": "deer", "hp": 80, "p": [8, 0.3, 0]}, {"id": "b", "kind": "boar", "hp": 110, "p": [20, 0.3, 0]}]})
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    current_scene = main
    for i in 1800:
        await process_frame
        if bool(main.get("match_ready")): break
    check(bool(main.get("match_ready")), "survival scene starts with ecology and lake shader")
    var ctl = main.get("match_controller")
    var animals: Dictionary = ctl.get("animals")
    for a in animals.values(): a.set_physics_process(false)
    main.get("player").set_physics_process(false)
    var wolf = animals["w"]
    var boar = animals["b"]
    check(float(wolf.get("_fed_left")) > 0.0, "feeding state restored from join snapshot")
    net.message.emit({"t": "aneeds", "l": [{"id": "w", "hunger": 28, "thirst": 32, "hp": 70}]})
    check(float(wolf.hunger) == 28.0 and float(wolf.thirst) == 32.0, "network needs update reaches animal AI")
    net.message.emit({"t": "fruit", "r": {"id": "apple-test", "kind": "apple", "p": [2, 0.1, 0]}})
    check(main.get_node("SurvivalWorld").fallen_fruit.has("apple-test"), "fallen fruit reaches the rendered world")
    check((ctl.call("_fauna_food_sources", "rabbit", Vector3.ZERO, false) as Array).size() == 1, "rabbit sees apples as food")
    check((ctl.call("_fauna_food_sources", "boar", Vector3.ZERO, false) as Array).is_empty(), "boar does not select rabbit apples")
    net.message.emit({"t": "fruit_gone", "id": "apple-test"})
    check(not main.get_node("SurvivalWorld").fallen_fruit.has("apple-test"), "consumed fruit disappears for everyone")
    check((ctl.call("_fauna_targets") as Array).size() == 3, "controller exposes wildlife to animal AI")
    net.message.emit({"t": "ahp", "id": "b", "hp": 99, "by": "w"})
    check(boar.get("_target") == wolf and boar.get("_target_id") == "w", "network animal hit starts boar retaliation")
    net.message.emit({"t": "afed", "id": "w", "left": 30})
    check(float(wolf.get("_fed_left")) == 30.0 and wolf.get("_target") == null, "feeding message stops current chase")
    net.message.emit({"t": "aspawn", "l": [{"id": "r", "kind": "rabbit", "hp": 15, "p": [9, 0.3, 0]}]})
    animals["r"].set_physics_process(false)
    check((ctl.call("_fauna_targets") as Array).size() == 4, "newly spawned animals join the food chain")
    net.message.emit({"t": "adead", "id": "d", "by": "w"})
    check((ctl.call("_fauna_targets") as Array).size() == 3, "dead prey leaves AI target list")
    main.queue_free()
    await process_frame
    print("ECOLOGY SESSION: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
