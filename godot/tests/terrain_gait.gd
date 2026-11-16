extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    player.set_physics_process(false)
    player.position = Vector3(0, 0, 10)
    var avatar: Node3D = player.get("humanoid_avatar")
    var torso: Node3D = avatar.get("torso")
    for frame in range(100):
        avatar.animate(1.0 / 60.0, 1.0, false, false, false, false, false, Vector2(0, -1), Vector3(0, 0, -5.0))
    _check(absf(torso.rotation.x) < 0.06, "Walking at 5m/s activates running pose")
    var before_run := torso.rotation.x
    avatar.animate(1.0 / 60.0, 1.0, true, false, false, false, false, Vector2(0, -1), Vector3(0, 0, -8.0))
    _check(absf(torso.rotation.x - before_run) < 0.04, "Sprint pose changes abruptly")
    for frame in range(100):
        avatar.animate(1.0 / 60.0, 1.0, true, false, false, false, false, Vector2(0, -1), Vector3(0, 0, -8.0))
    _check(torso.rotation.x < -0.09, "Sprinting does not reach running pose")
    var platform := StaticBody3D.new()
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(0.24, 0.12, 1.0)
    collider.shape = shape
    platform.add_child(collider)
    platform.position = Vector3(-0.16, 0.06, 10)
    scene.add_child(platform)
    await physics_frame
    await process_frame
    for frame in range(120):
        avatar.animate(1.0 / 60.0, 0.0, false, true, false, false, false)
    var left: Node3D = avatar.get_node("Hips/LeftLeg/Knee/Ankle")
    var right: Node3D = avatar.get_node("Hips/RightLeg/Knee/Ankle")
    _check(left.global_position.y - right.global_position.y > 0.08, "Feet ignore uneven terrain")
    var sole := left.get_node("BootSole") as MeshInstance3D
    var bottom := INF
    for corner in range(8):
        bottom = minf(bottom, sole.to_global(sole.mesh.get_aabb().get_endpoint(corner)).y)
    _check(bottom >= 0.115 and bottom <= 0.145, "Left sole does not rest on raised terrain: " + str(bottom))
    platform.queue_free()
    await physics_frame
    await process_frame
    var ramp := StaticBody3D.new()
    var ramp_collider := CollisionShape3D.new()
    var ramp_shape := BoxShape3D.new()
    ramp_shape.size = Vector3(2, 0.10, 2)
    ramp_collider.shape = ramp_shape
    ramp.add_child(ramp_collider)
    ramp.position = Vector3(0, 0.12, 10)
    ramp.rotation.x = 0.20
    scene.add_child(ramp)
    await physics_frame
    await process_frame
    for frame in range(120):
        avatar.animate(1.0 / 60.0, 0.0, false, true, false, false, false)
    for ankle in [left, right]:
        _check(ankle.global_basis.y.normalized().dot(ramp.global_basis.y) > 0.999, "Foot does not align to slope normal")
        var boot_sole := ankle.get_node("BootSole") as MeshInstance3D
        for corner in [0, 1, 4, 5]:
            var vertex := boot_sole.to_global(boot_sole.mesh.get_aabb().get_endpoint(corner))
            var ray := PhysicsRayQueryParameters3D.create(vertex + Vector3.UP * 0.1, vertex - Vector3.UP * 0.1)
            ray.exclude = [player.get_rid()]
            var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
            _check(not hit.is_empty(), "No support under sole on slope")
            if not hit.is_empty():
                var clearance: float = (vertex - hit["position"]).dot(hit["normal"])
                _check(clearance >= -0.002 and clearance < 0.04, "Sole penetrates or floats above slope")
    scene.queue_free()
    await process_frame
    for failure in failures:
        printerr(failure)
    print("TERRAIN GAIT: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
