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
    net.set("host_id", "")
    net.set("start_info", {"survival": true, "you": {"id": "audit", "p": [0, 0.2, 0], "hp": 100, "hunger": 85, "thirst": 85, "inv": {"w_pistol": 1, "a_9mm": 10}, "magazines": {"pistol": 7}, "cap": 20, "weight": 1.17}, "roster": [], "zombies": [], "animals": [], "vehicles": [], "bags": [], "buildings": []})
    var main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)
    current_scene = main
    for i in 1800:
        await process_frame
        if bool(main.get("match_ready")): break
    check(bool(main.get("match_ready")), "survival starts with updated scripts")
    var ctl = main.get("match_controller")
    var player = main.get("player")
    check(int(player.get("magazines").get("pistol", 0)) == 7, "saved magazine restored on entry")
    check(int(player.get("ammo")) == 7, "active gun shows restored rounds")
    check(int(player.get("reserve_ammo").get("pistol", 0)) == 10, "loose ammunition remains separate")
    player.set("ammo", 6)
    player.get("magazines")["pistol"] = 6
    ctl.call("_apply_inventory", {"inv": {"w_pistol": 1, "a_9mm": 10}, "magazines": {"pistol": 7}, "cap": 20, "weight": 1.17})
    check(int(player.get("ammo")) == 6, "late inventory reply cannot rewind local shot")
    var building = ctl.get("building_ctl")
    var rules = building.get("rules")
    player.set_physics_process(false)
    player.global_position = Vector3(0, 0.2, 0)
    rules.add({"id": "audit-fire", "kind": "campfire", "p": [0, 0, 0], "on": false, "hp": 120})
    ctl.call("_apply_inventory", {"inv": {"wood": 1}, "cap": 20, "weight": 1.0})
    ctl.call("_update_crafting_context")
    var recipe: Dictionary
    for r in load("res://scripts/survival/survival_data.gd").recipes():
        if r.id == "charcoal": recipe = r
    check(not str(ctl.get("inventory").call("craft_error", recipe)).is_empty(), "actual controller excludes unlit fire")
    rules.pieces["audit-fire"]["on"] = true
    ctl.call("_update_crafting_context")
    check(str(ctl.get("inventory").call("craft_error", recipe)).is_empty(), "actual controller enables lit fire")
    check(str(ctl.get("manual").call("craft_error", recipe)).is_empty(), "manual agrees with inventory")
    rules.pieces["audit-fire"]["p"] = [0, 3, 0]
    ctl.call("_update_crafting_context")
    check(not str(ctl.get("inventory").call("craft_error", recipe)).is_empty(), "station on another floor is excluded")
    main.queue_free()
    await process_frame
    print("SURVIVAL CONSISTENCY RUNTIME: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
