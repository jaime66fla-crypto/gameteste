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
func _run() -> void:
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://character_gameplay_%s.cfg" % OS.get_process_id()
    # Os personagens do catálogo atual (hoje só o avatar_ch31).
    var ids: Array = registry.all_characters().map(func(entry): return entry.id)
    for id in ids:
        _check(registry.select_character(id) == OK, "Cannot select " + id)
        var scene: Node3D = load("res://scenes/main.tscn").instantiate()
        root.add_child(scene)
        current_scene = scene
        var player: CharacterBody3D = scene.get_node("Jaime")
        player.position = Vector3(0, 0.1, 10) # Clear avenue, away from the spawn plaza bench.
        var properties := player.get_property_list().map(func(p: Dictionary): return p["name"])
        if not properties.has("character_id"):
            printerr("CHARACTER GAMEPLAY: player has no selectable visual")
            quit(1)
            return
        _check(player.get("character_id") == id, "Wrong visual loaded: " + id)
        _check(is_equal_approx(player.get("camera").fov, 72.0), "Camera FOV changed")
        await _frames(30)
        var initial_y := player.position.y
        Input.action_press("move_forward")
        await _frames(35)
        _check(Vector2(player.velocity.x, player.velocity.z).length() > 4.9, "Walk changed for " + id)
        Input.action_press("sprint")
        await _frames(25)
        _check(Vector2(player.velocity.x, player.velocity.z).length() > 7.9, "Sprint changed for " + id)
        Input.action_release("sprint")
        Input.action_release("move_forward")
        Input.action_press("crouch")
        await _frames(35)
        _check(player.get("body_capsule").height < 1.6, "Crouch capsule changed")
        _check(absf(player.position.y - initial_y) < 0.05, "Character sank while crouching")
        if id == "jaime_swat":
            var visual: Node3D = player.get("humanoid_avatar")
            _check(visual.call("is_visual_ready"), "SWAT did not initialize")
            var sk: Skeleton3D = visual.get("skeleton")
            for foot in ["Left", "Right"]:
                # Ossos do Mixamo com prefixo variável (mixamorig_, mixamorig9_...).
                var toe := -1
                for b in sk.get_bone_count():
                    if sk.get_bone_name(b).ends_with(foot + "ToeBase"):
                        toe = b
                _check(toe >= 0, "SWAT toe bone missing: " + foot)
                if toe >= 0:
                    var point := sk.to_global(sk.get_bone_global_pose(toe).origin)
                    _check(point.y >= player.position.y - 0.035, "SWAT foot penetrates floor")
        Input.action_release("crouch")
        await _frames(30)
        for weapon in ["pistol", "rifle", "sniper", "shotgun", "smg"]:
            player.call("_equip_weapon", weapon)
            Input.action_press("aim")
            await _frames(25)
            var ammo: int = player.get("ammo")
            var shots: int = player.get("shots")
            player.call("_shoot")
            _check(player.get("ammo") == ammo - 1 and player.get("shots") == shots + 1, "Combat changed for " + id + "/" + weapon)
            # Só o visual SWAT antigo media o erro da pegada; o avatar atual não tem grip_error.
            if id == "jaime_swat" and player.get("humanoid_avatar").has_method("grip_error"):
                var visual: Node3D = player.get("humanoid_avatar")
                for side in ["Left", "Right"]:
                    _check(float(visual.call("grip_error", side)) < 0.045, "SWAT grip too far: " + weapon + "/" + side + " error=" + str(visual.call("grip_error", side)))
            Input.action_release("aim")
            player.call("_reload")
            await _frames(8)
            _check(player.get("reloading"), "Reload did not start")
            player.set("reload_timer", 0.01)
            await _frames(3)
            _check(player.get("ammo") == ammo and not player.get("reloading"), "Reload mechanics changed")
        scene.queue_free()
        await _frames(3)
    # Resource failure must not mutate the saved preference or remove the Original.
    var definition: Resource = registry.definition("jaime_swat")
    # O catálogo atual pode não ter mais o SWAT: aí não há o que testar no fallback.
    if definition != null:
        var original_path: String = definition.visual_scene
        registry.select_character("jaime_swat")
        definition.visual_scene = "res://missing_character_visual.tscn"
        var fallback: Node3D = load("res://scenes/main.tscn").instantiate()
        root.add_child(fallback)
        current_scene = fallback
        _check(fallback.get_node("Jaime").get("character_id") == "jaime_original", "Missing SWAT did not fall back")
        _check(registry.load_selection() == "jaime_swat", "Fallback destroyed saved preference")
        definition.visual_scene = original_path
        fallback.queue_free()
        await _frames(3)
    registry.select_character(registry.DEFAULT_ID)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures.slice(0, 20):
        printerr(failure)
    print("CHARACTER GAMEPLAY: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
    quit(0 if failures.is_empty() else 1)
