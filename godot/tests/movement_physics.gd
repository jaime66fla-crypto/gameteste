extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _frames(count: int) -> void:
    for frame in range(count):
        await physics_frame
        await process_frame

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.position = pos
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)
    parent.add_child(body)
    return body

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    player.position = Vector3(0, 0.1, 10)
    await _frames(35)
    var collider: CollisionShape3D
    for child in player.get_children():
        if child is CollisionShape3D:
            collider = child
    var capsule := collider.shape as CapsuleShape3D
    var standing_height := capsule.height
    var floor_y := player.position.y
    Input.action_press("crouch")
    for frame in range(35):
        await _frames(1)
        _check(absf(collider.position.y - capsule.height * 0.5) < 0.001, "Capsule base moved during crouch")
        _check(absf(player.position.y - floor_y) < 0.015, "Crouch moved body through floor")
    _check(capsule.height < standing_height - 0.15, "Crouch does not reduce capsule height")
    var ceiling := _solid(scene, Vector3(0, 1.72, 10), Vector3(3, 0.20, 3))
    await _frames(4)
    Input.action_release("crouch")
    await _frames(35)
    _check(bool(player.get("crouching")), "Player stands under low ceiling")
    _check(capsule.height <= 1.62, "Capsule expands into low ceiling")
    ceiling.queue_free()
    await _frames(40)
    _check(not bool(player.get("crouching")), "Player does not stand when ceiling clears")
    _check(absf(capsule.height - standing_height) < 0.001, "Standing capsule not restored")
    _check(absf(collider.position.y - capsule.height * 0.5) < 0.001, "Standing capsule base moved")
    Input.action_press("move_forward")
    await _frames(1)
    var first_speed := Vector2(player.velocity.x, player.velocity.z).length()
    _check(first_speed > 0.0 and first_speed < 2.0, "Movement starts at full speed instead of accelerating")
    await _frames(40)
    _check(absf(Vector2(player.velocity.x, player.velocity.z).length() - 5.0) < 0.1, "Walk speed not reached")
    Input.action_release("move_forward")
    await _frames(1)
    _check(Vector2(player.velocity.x, player.velocity.z).length() > 0.1, "Movement stops instantly instead of braking")
    await _frames(35)
    _check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "Movement does not stop")
    scene.queue_free()
    await _frames(2)
    for failure in failures:
        printerr(failure)
    print("MOVEMENT PHYSICS: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
