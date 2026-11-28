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

func _check_equipped_model(player: Node) -> void:
    var avatar = player.get("humanoid_avatar")
    _check(bool(avatar.call("is_visual_ready")), "Equipped soldier is ready")
    _check(avatar.get("bound_weapon") == player.get("weapon_model"), "Avatar holds the equipped weapon model")
    _check(avatar.get("weapon_id") == player.get("current_weapon"), "Avatar grip matches the selected weapon")
    # Hand IK and wrist limits are covered by stance_hands.gd for the skeletal soldiers.

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node = scene.get_node("Jaime")
    player.set_physics_process(false)
    _select(player, KEY_1)
    _check(player.get("current_weapon") == "rifle", "1 equips rifle")
    _check(player.get("ammo") == 30, "Rifle magazine starts at 30")
    _check_equipped_model(player)
    player.call("_shoot")
    _select(player, KEY_2)
    _check(player.get("current_weapon") == "sniper", "2 equips sniper")
    _check(player.get("ammo") == 5, "Sniper magazine starts at 5")
    _check_equipped_model(player)
    player.call("_shoot")
    _select(player, KEY_3)
    _check(player.get("current_weapon") == "pistol", "3 equips pistol")
    _check(player.get("ammo") == 15, "Pistol magazine stays independent")
    _check_equipped_model(player)
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
