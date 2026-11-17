extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    player.set_physics_process(false)
    await physics_frame
    await process_frame
    var shape := CapsuleShape3D.new()
    shape.radius = 0.36
    shape.height = 1.8
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = shape
    query.exclude = [player.get_rid()]
    var space := player.get_world_3d().direct_space_state
    for avenue in [-48, 0, 48]:
        for along in range(-48, 49, 4):
            for point in [Vector3(avenue, 0.95, along), Vector3(along, 0.95, avenue)]:
                query.transform = Transform3D(Basis.IDENTITY, point)
                if not space.intersect_shape(query, 1).is_empty():
                    failures.append("Main road obstructed at " + str(point))
    query.transform = Transform3D(Basis.IDENTITY, Vector3(player.position.x, 0.95, player.position.z))
    if not space.intersect_shape(query, 1).is_empty():
        failures.append("Player spawn obstructed")
    if get_nodes_in_group("cover_wall").size() < 10:
        failures.append("Map needs cover walls in the open areas")
    var buildings := get_nodes_in_group("map_building")
    if buildings.size() < 8:
        failures.append("Map needs identifiable buildings with entrances")
    # Flood actual collision-free space rather than trusting layout metadata.
    var open: Dictionary = {}
    for x in range(-28, 29):
        for z in range(-28, 29):
            query.transform = Transform3D(Basis.IDENTITY, Vector3(x * 2, 0.95, z * 2))
            if space.intersect_shape(query, 1).is_empty():
                open[Vector2i(x, z)] = true
    var origin := Vector2i(roundi(player.position.x / 2), roundi(player.position.z / 2))
    var visited: Dictionary = {origin: true}
    var queue: Array[Vector2i] = [origin]
    var index := 0
    while index < queue.size():
        var point := queue[index]
        index += 1
        for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
            var neighbor: Vector2i = point + direction
            if open.has(neighbor) and not visited.has(neighbor):
                query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x * 2, 0.95, point.y * 2))
                query.motion = Vector3(direction.x * 2, 0, direction.y * 2)
                var travel := space.cast_motion(query)
                if travel[0] >= 0.999:
                    visited[neighbor] = true
                    queue.append(neighbor)
    query.motion = Vector3.ZERO
    for building in buildings:
        var entrance: Vector3 = building.get_meta("entrance")
        var entry_cell := Vector2i(roundi(entrance.x / 2), roundi(entrance.z / 2))
        if not visited.has(entry_cell):
            failures.append("Cannot reach entrance: " + String(building.name))
        for distance in [-0.8, 0.0, 0.8]:
            query.transform = Transform3D(Basis.IDENTITY, entrance + Vector3(0, 0.95, distance))
            if not space.intersect_shape(query, 1).is_empty():
                failures.append("Door blocks player capsule: " + String(building.name))
    scene.queue_free()
    await process_frame
    for failure in failures.slice(0, 10):
        printerr(failure)
    print("MAP LAYOUT: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
    quit(0 if failures.is_empty() else 1)
