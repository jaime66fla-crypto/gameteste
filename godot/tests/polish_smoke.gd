extends SceneTree
## Run: godot --headless --path godot --script res://tests/polish_smoke.gd
## Verifies that the scene, audio nodes, world, and arsenal initialize.
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run_smoke")

func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
        push_error("SMOKE FAIL: " + message)

func _run_smoke() -> void:
    var scene_resource: PackedScene = load("res://scenes/main.tscn")
    _check(scene_resource != null, "Main scene loads")
    if scene_resource == null:
        quit(1)
        return
    var scene: Node = scene_resource.instantiate()
    root.add_child(scene)
    current_scene = scene
    await process_frame
    await physics_frame
    var player: Node = scene.get_node_or_null("Jaime")
    var world: Node = scene.get_node_or_null("WorldPolish")
    var environment_sound: Node = scene.get_node_or_null("EnvironmentAudio")
    _check(player != null, "Player spawns")
    _check(world != null, "Visual environment exists")
    _check(environment_sound != null, "Outdoor sound exists")
    if player != null:
        var gun: Node = player.get("gun")
        _check(gun != null, "Equipped gun exists")
        if gun != null:
            var fx: Node = gun.get_node_or_null("SoundFX")
            _check(fx != null, "Sound FX belongs to gun")
            if fx != null:
                _check(fx.has_method("shot"), "Shot sound method exists")
                fx.call("shot", "rifle")
                fx.call("shot", "shotgun")
        var model: Node = player.get("weapon_model")
        _check(player.has_method("_animate_avatar"), "Avatar procedural animation present")
        _check(player.has_method("_rebuild_weapon_model"), "Weapon model fallback present")
        _check(model != null, "Weapon model exists")
        var humanoid: Node = player.get("humanoid_avatar")
        _check(humanoid != null, "New humanoid avatar initialized")
        if humanoid != null:
            _check(humanoid.get_node_or_null("Hips") != null, "Humanoid hips created")
            _check(humanoid.get_node_or_null("WeaponMount") != null, "Weapon mount created")
            _check(humanoid.has_method("animate"), "Avatar pose blending available")
        _check(absf(float(player.get("height")) - 1.8) < 0.001, "Ghost proportions: 1.80 m configured")
        var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
        # Current player creates its collision child without a fixed name; inspect children.
        if collision_shape == null:
            for child in player.get_children():
                if child is CollisionShape3D:
                    collision_shape = child
                    break
        _check(collision_shape != null, "Player capsule exists")
        if collision_shape != null and collision_shape.shape is CapsuleShape3D:
            _check(absf((collision_shape.shape as CapsuleShape3D).height - 1.8) < 0.001, "Capsule height configured")
        _check(player.get("ammo") == 15, "Pistol magazine starts at 15")
        var order := ["smg", "rifle", "shotgun", "sniper", "pistol"]
        var expected_mags := [30, 30, 6, 5, 15]
        for i in range(order.size()):
            player.call("_equip_weapon", order[i])
            _check(player.get("current_weapon") == order[i], "Equip " + order[i])
            _check(player.get("ammo") == expected_mags[i], "Magazine size for " + order[i])
            if model != null:
                _check(model.get_child_count() >= 1, "Weapon geometry for " + order[i])
                var external_model: bool = bool(player.get("equipped_external_model"))
                if not external_model:
                    _check(model.get_child_count() >= 2, "Procedural weapon fallback for " + order[i])
        player.set("ammo", 0)
        var reserves: Dictionary = player.get("reserve_ammo")
        reserves["pistol"] = 0
        player.call("_reload")
        _check(not player.get("reloading"), "Empty reserve must not lock reload")
        reserves["pistol"] = 7
        player.call("_reload")
        _check(player.get("reloading"), "Reload starts when reserve exists")
        player.set("reload_timer", 0.001)
        await physics_frame
        _check(player.get("ammo") == 7, "Reload transfers only available ammo")
        _check(int(reserves["pistol"]) == 0, "Reserve ammo gets consumed")
    if world != null:
        _check(world.get_child_count() > 20, "World details spawned")
    if failures.is_empty():
        print("CAMPO DE FOGO: SMOKE PASS")
        quit(0)
    else:
        print("CAMPO DE FOGO: SMOKE FAILURES = ", failures)
        quit(1)
