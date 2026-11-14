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
        _check(player.get_node_or_null("SoundFX") == null, "Audio kept in gun subtree, not duplicated on root")
        _check(player.get("ammo") == 15, "Pistol magazine starts at 15")
        var order := ["smg", "rifle", "shotgun", "sniper", "pistol"]
        var expected_mags := [30, 30, 6, 5, 15]
        for i in range(order.size()):
            player.call("_equip_weapon", order[i])
            _check(player.get("current_weapon") == order[i], "Equip " + order[i])
            _check(player.get("ammo") == expected_mags[i], "Magazine size for " + order[i])
        player.set("ammo", 0)
        var reserves: Dictionary = player.get("reserve_ammo")
        reserves["pistol"] = 0
        player.call("_reload")
        _check(not player.get("reloading"), "Empty reserve must not lock reload")
    if world != null:
        _check(world.get_child_count() > 20, "World details spawned")
    if failures.is_empty():
        print("CAMPO DE FOGO: SMOKE PASS")
        quit(0)
    else:
        print("CAMPO DE FOGO: SMOKE FAILURES = ", failures)
        quit(1)
