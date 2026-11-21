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
    var target := CharacterBody3D.new()
    scene.add_child(target)
    target.position = Vector3(70, 0, 0)
    var wolf = Animal.new(); wolf.setup("wolf", "wolf", 70)
    var deer = Animal.new(); deer.setup("deer", "deer", 80)
    var boar = Animal.new(); boar.setup("boar", "boar", 110)
    var animals := [wolf, deer, boar]
    for a in animals:
        scene.add_child(a)
        a.set_physics_process(false)
        a.targets = func(): return [{"id": "human", "node": target}]
        a.set_controlled(true)
    wolf.position = Vector3.ZERO
    wolf.apply_needs(30.0, 80.0)
    deer.position = Vector3(8, 0, 0)
    boar.position = Vector3(20, 0, 0)
    check(wolf.has_method("set_fauna_targets"), "animals accept food chain targets")
    if wolf.has_method("set_fauna_targets"):
        for a in animals:
            a.call("set_fauna_targets", func(): return [{"id": "wolf", "node": wolf, "kind": "wolf"}, {"id": "deer", "node": deer, "kind": "deer"}, {"id": "boar", "node": boar, "kind": "boar"}])
        await physics_frame
        wolf.call("_run_ai", 0.5)
        check(wolf.get("_target_id") == "deer", "wolf selects nearby prey over distant player")
        deer.call("_run_ai", 0.5)
        check(float(deer.get("_scared")) > 0 and deer.get("_threat") == wolf, "deer flees nearby predator")
        boar.hurt("wolf", wolf)
        boar.call("_run_ai", 0.5)
        check(boar.get("_target_id") == "wolf", "boar defends against attacking wolf")
        wolf.call("feed", 30.0)
        wolf.call("_run_ai", 0.5)
        check(wolf.get("_target") == null and int(wolf.anim) == int(wolf.Anim.EAT), "fed wolf eats instead of chain killing")
        wolf.call("feed", 0.0)
        wolf.call("set_fauna_targets", func(): return [])
        target.position = wolf.position + Vector3(0, 0, 1.0)
        wolf.call("hurt", "human", target)
        wolf.anim = wolf.Anim.IDLE
        wolf.call("_run_ai", 0.5)
        check(wolf.anim == wolf.Anim.ATTACK, "wolf can attack a player body without an animal-only dead property")
    scene.queue_free()
    await process_frame
    print("ANIMAL ECOLOGY: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
