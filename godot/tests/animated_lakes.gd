extends SceneTree
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
    if not ok:
        failures.append(what)
        printerr("FAIL: ", what)
func _initialize() -> void:
    run.call_deferred()
func run() -> void:
    var World = load("res://scripts/survival/survival_world.gd")
    var world = World.new()
    world.staged_loading = true
    root.add_child(world)
    world.ponds = [{"x": 0, "z": 0, "r": 8}]
    world.call("_pond", world.ponds[0])
    var water = world.get_node("Pond").get_node_or_null("Water")
    check(water != null, "lake has dedicated animated surface")
    if water != null:
        var material = water.material_override
        check(material is ShaderMaterial, "water uses an animated shader")
        if material is ShaderMaterial:
            check(material.shader.code.contains("TIME"), "water animation advances with time")
            check(not material.shader.get_shader_uniform_list().is_empty(), "shader compiles")
        check(water.mesh is ArrayMesh and water.mesh.get_faces().size() > 100, "water mesh supports visible waves")
    check(world.in_pond(Vector3(7, 0, 0)), "drinking area stays unchanged")
    check(not world.in_pond(Vector3(10, 0, 0)), "outside remains outside lake")
    world.queue_free()
    await process_frame
    print("ANIMATED LAKES: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
