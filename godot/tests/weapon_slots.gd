extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

func _select(player: Node, key: Key) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = key
    event.pressed = true
    player.call("_unhandled_input", event)

func _check_grips(player: Node, support: Vector3, trigger: Vector3 = Vector3(0, -0.18, -0.21)) -> void:
    var avatar = player.get("humanoid_avatar")
    for crouched in [false, true]:
        for aiming in [false, true]:
            for moving in [0.0, 1.0]:
                for frame in range(180):
                    avatar.animate(1.0 / 60.0, moving, false, crouched, aiming, false, false)
                var model: Node3D = player.get("weapon_model")
                for side in ["Right", "Left"]:
                    var hand: Node3D = avatar.get_node("Hips/Torso/" + side + "Arm/Elbow/Hand")
                    var grip := trigger if side == "Right" else support
                    _check(hand.global_position.distance_to(model.to_global(grip)) < 0.025, "%s hand follows equipped weapon grip" % side)

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node = scene.get_node("Jaime")
    player.set_physics_process(false)
    _select(player, KEY_1)
    _check(player.get("current_weapon") == "rifle", "1 equips rifle")
    _check(player.get("ammo") == 30, "Rifle magazine starts at 30")
    _check_grips(player, Vector3(-0.05, -0.14, -0.68))
    player.call("_shoot")
    _select(player, KEY_2)
    _check(player.get("current_weapon") == "sniper", "2 equips sniper")
    _check(player.get("ammo") == 5, "Sniper magazine starts at 5")
    _check_grips(player, Vector3(-0.05, -0.035, -0.6355))
    player.call("_shoot")
    _select(player, KEY_3)
    _check(player.get("current_weapon") == "pistol", "3 equips pistol")
    _check(player.get("ammo") == 15, "Pistol magazine stays independent")
    _check_grips(player, Vector3(-0.065, -0.14, -0.09), Vector3(0, -0.15, -0.08))
    _select(player, KEY_1)
    _check(player.get("ammo") == 29, "Switching back preserves rifle ammo")
    _select(player, KEY_2)
    _check(player.get("ammo") == 4, "Switching back preserves sniper ammo")
    scene.queue_free()
    await process_frame
    for failure in failures:
        printerr(failure)
    print("WEAPON SLOTS: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
