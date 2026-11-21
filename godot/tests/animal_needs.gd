extends SceneTree
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
    if not ok:
        failures.append(what)
        printerr("FAIL: ", what)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var Animal = load("res://scripts/survival/animal.gd")
    var scene := Node3D.new()
    root.add_child(scene)
    current_scene = scene
    var human := Node3D.new()
    scene.add_child(human)
    human.position = Vector3(70, 0, 0)
    var deer = Animal.new();deer.setup("d", "deer", 80)
    var wolf = Animal.new();wolf.setup("w", "wolf", 70)
    for a in [deer,wolf]:
        scene.add_child(a)
        a.set_physics_process(false)
        a.set_controlled(true)
        a.targets = func(): return [{"id": "human", "node": human}]
    deer.position = Vector3(8, 0, 0)
    check(deer.has_method("set_food_sources"), "food sources are connected to animal needs")
    if deer.has_method("set_food_sources"):
        deer.call("set_food_sources", func(_kind, _at, water): return [{"id": "water:0" if water else "grass:0", "pos": Vector3(20, 0, 0), "radius": 3.0 if water else 2.0, "water": water}])
        deer.call("apply_needs", 90.0, 90.0)
        await physics_frame
        deer.call("_run_ai", .5)
        check((deer.get("_need_goal") as Dictionary).is_empty(), "satisfied deer does not seek food or water")
        deer.call("apply_needs", 25.0, 90.0)
        deer.set("_think", 0.0)
        deer.call("_run_ai", .5)
        check(str(deer.get("_need_goal").get("id", "")) == "grass:0", "hungry deer seeks grass")
        var requested: Array = []
        deer.forage_requested.connect(func(_id, source, phase): requested.append([source, phase]))
        deer.position = deer.get("_need_goal")["point"]
        for i in 7: deer.call("_run_ai", 0.5)
        check(requested.has(["grass:0", "start"]) and requested.has(["grass:0", "finish"]), "grazing uses a timed start and finish")
        check(float(deer.hunger) == 25.0, "client does not invent hunger recovery before server confirms")
        deer.position = Vector3(8, 0, 0)
        deer.call("apply_needs", 25.0, 15.0)
        deer.set("_think", 0.0)
        deer.call("_run_ai", .5)
        check(str(deer.get("_need_goal").get("id", "")) == "water:0", "critical thirst takes priority over food")
        wolf.call("set_fauna_targets", func(): return [{"id": "d", "node": deer, "kind": "deer"}])
        wolf.call("apply_needs", 90.0, 90.0)
        wolf.call("_run_ai", .5)
        check(wolf.get("_target") == null, "satisfied wolf does not hunt")
        wolf.call("apply_needs", 25.0, 90.0)
        wolf.set("_think", 0.0)
        wolf.call("_run_ai", .5)
        check(wolf.get("_target_id") == "d", "hungry wolf hunts prey")
        wolf.set("_chase_left", .01)
        wolf.set("_think", 2.0)
        wolf.call("_run_ai", .5)
        check(wolf.get("_target") == null and float(wolf.get("_hunt_rest")) > 0, "failed chase makes wolf stop and recover")
    var nature = load("res://scripts/survival/nature_model.gd").new()
    check(nature.has_method("tree_variant"), "tree species mapping is shared with fruit rules")
    if nature.has_method("tree_variant"):
        check(nature.call("tree_variant",18) == "apple", "selected trees become apple trees")
        check(nature.call("tree_variant",17) == "oak_a", "existing oaks remain acorn trees")
        check(nature.call("mesh", "apple").get_faces().size() > 0, "apple tree has a visible model")
        for kind in ["apple", "acorn"]:
            check(nature.call("fruit_mesh", kind).get_faces().size() > 0, "fallen fruit has a visible model")
    scene.queue_free()
    await process_frame
    print("ANIMAL NEEDS: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
