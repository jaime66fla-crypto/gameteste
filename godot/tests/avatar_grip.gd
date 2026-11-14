extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var avatar = load("res://scripts/avatar/avatar_controller.gd").new()
    root.add_child(avatar)
    avatar.rotation = Vector3(0.1, 1.3, -0.05)
    avatar.position = Vector3(5, 2, -3)
    for crouched in [false, true]:
        for moving in [0.0, 1.0]:
            # Returning from a reload must reacquire both grips.
            for frame in range(60):
                avatar.animate(1.0 / 60.0, moving, false, crouched, true, false, true)
            for frame in range(180):
                avatar.animate(1.0 / 60.0, moving, false, crouched, true, false, false)
            var mount: Node3D = avatar.get("weapon_mount")
            for side in ["Right", "Left"]:
                var hand: Node3D = avatar.get_node("Hips/Torso/" + side + "Arm/Elbow/Hand")
                var grip := Vector3(0, -0.15, -0.08) if side == "Right" else Vector3(-0.065, -0.14, -0.09)
                var error := hand.global_position.distance_to(mount.to_global(grip))
                if error > 0.025:
                    failures.append("%s hand %.3fm from pistol; crouched=%s moving=%s" % [side, error, crouched, moving])
    avatar.free()
    for failure in failures:
        printerr(failure)
    print("AVATAR GRIP: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
