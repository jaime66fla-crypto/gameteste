extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _foot_bottoms(node: Node, player: Node3D, bottoms: Array[float]) -> void:
    if node is MeshInstance3D and String(node.name).begins_with("Boot"):
        var bounds: AABB = node.mesh.get_aabb()
        for corner in range(8):
            var point: Vector3 = player.to_local(node.to_global(bounds.get_endpoint(corner)))
            bottoms.append(point.y)
    for child in node.get_children():
        _foot_bottoms(child, player, bottoms)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    var avatar: Node3D = player.get("humanoid_avatar")
    var head: Node3D = avatar.get("head")
    for frame in range(45):
        await physics_frame
        await process_frame
    var standing_height := player.to_local(head.global_position).y
    var worst_penetration := 0.0
    var worst_ground_gap := 0.0
    var crouched_height := standing_height
    for state in ["crouch", "crouch_walk", "stand"]:
        if state == "stand":
            Input.action_release("crouch")
            Input.action_release("move_forward")
        else:
            Input.action_press("crouch")
            if state == "crouch_walk":
                Input.action_press("move_forward")
        for frame in range(75):
            await physics_frame
            await process_frame
            var bottoms: Array[float] = []
            _foot_bottoms(avatar, player, bottoms)
            if bottoms.is_empty():
                failures.append("No visible boots to evaluate")
                break
            worst_penetration = minf(worst_penetration, bottoms.min())
            worst_ground_gap = maxf(worst_ground_gap, bottoms.min())
        if state == "crouch":
            crouched_height = player.to_local(head.global_position).y
            var leg: Node3D = avatar.get("left_leg")
            var knee := leg.get_node_or_null("Knee") as Node3D
            if knee == null or absf(knee.rotation.x) < 0.45:
                failures.append("Crouch must bend the knees")
    if worst_penetration < -0.02:
        failures.append("Boots sink below floor: %.3fm" % worst_penetration)
    if worst_ground_gap > 0.035:
        failures.append("Both feet lose floor contact: %.3fm" % worst_ground_gap)
    if standing_height - crouched_height < 0.16:
        failures.append("Crouch must lower the torso while feet remain grounded")
    if absf(player.to_local(head.global_position).y - standing_height) > 0.025:
        failures.append("Standing height must recover after crouching")
    Input.action_release("crouch")
    Input.action_release("move_forward")
    scene.queue_free()
    await process_frame
    for failure in failures:
        printerr(failure)
    print("CROUCH MOTION: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
