extends SceneTree
var failures: Array[String] = []
var low := INF
var high := -INF

func _initialize() -> void:
    call_deferred("_run")

func _bounds(node: Node, player: Node3D) -> void:
    if node is MeshInstance3D and node.is_visible_in_tree():
        for surface in range(node.mesh.get_surface_count()):
            var arrays: Array = node.mesh.surface_get_arrays(surface)
            for vertex in arrays[Mesh.ARRAY_VERTEX]:
                var point: Vector3 = player.to_local(node.to_global(vertex))
                low = minf(low, point.y)
                high = maxf(high, point.y)
    for child in node.get_children():
        _bounds(child, player)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    player.set_physics_process(false)
    var avatar: Node3D = player.get("humanoid_avatar")
    for path in ["Hips/Torso/Chest", "Hips/Torso/Head/Face"]:
        var mesh: Mesh = avatar.get_node(path).mesh
        var arrays: Array = mesh.surface_get_arrays(0)
        var outward_score := 0.0
        for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
            var v: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
            var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][i]
            outward_score += v.x * n.x + v.z * n.z
        if outward_score <= 0:
            failures.append("Mesh normals face inward: " + path)
    _bounds(avatar, player)
    if absf((high - low) - float(player.get("height"))) > 0.04:
        failures.append("Visible body height does not match player collision height")
    if low < -0.03:
        failures.append("Boots penetrate the floor")
    scene.queue_free()
    await process_frame
    for failure in failures:
        printerr(failure)
    print("AVATAR GEOMETRY: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
