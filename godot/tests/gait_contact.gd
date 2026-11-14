extends SceneTree
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    player.position = Vector3(0, 0.1, 10)
    var avatar: Node3D = player.get("humanoid_avatar")
    for frame in range(30):
        await physics_frame
        await process_frame
    Input.action_press("move_forward")
    for frame in range(50):
        await physics_frame
        await process_frame
    var previous := [Vector3.ZERO, Vector3.ZERO]
    var contacts := [0, 0]
    var samples := 0
    var worst_drift := 0.0
    for frame in range(120):
        await physics_frame
        await process_frame
        for index in range(2):
            var leg: Node3D = avatar.get("left_leg" if index == 0 else "right_leg")
            var ankle: Node3D = leg.get_node("Knee/Ankle")
            var foot := ankle.global_position
            var local_foot := player.to_local(foot)
            var planted := absf(local_foot.y - 0.095 * avatar.scale.y) < 0.002
            contacts[index] = contacts[index] + 1 if planted else 0
            if contacts[index] > 2 and absf(foot.y - previous[index].y) < 0.00001:
                var drift := Vector2(foot.x - previous[index].x, foot.z - previous[index].z).length()
                worst_drift = maxf(worst_drift, drift)
                samples += 1
            previous[index] = foot
    Input.action_release("move_forward")
    scene.queue_free()
    await process_frame
    var passed := samples >= 8 and worst_drift < 0.015
    print("GAIT CONTACT: ", "PASS" if passed else "FAIL", " samples=", samples, " worst planted-foot drift=", worst_drift)
    quit(0 if passed else 1)
