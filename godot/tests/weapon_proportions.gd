extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
func _bounds(node: Node3D, relative: Node3D) -> AABB:
    var bounds := AABB()
    var first := true
    for mesh in node.find_children("*", "MeshInstance3D", true, false):
        var box: AABB = mesh.mesh.get_aabb()
        for corner in range(8):
            var point := relative.to_local(mesh.to_global(box.get_endpoint(corner)))
            if first:
                bounds = AABB(point, Vector3.ZERO)
                first = false
            else:
                bounds = bounds.expand(point)
    return bounds
# Distância da palma ao ponto de pegada da arma (era swat_visual.grip_error).
func _grip_error(visual: Node3D, side: String) -> float:
    var Grip = load("res://scripts/characters/swat_grip.gd")
    var mount := visual.get("weapon_mount") as Node3D
    return Grip.palm_position(visual.get("skeleton"), side).distance_to((mount.get_node(side + "Grip") as Marker3D).global_position)
func _run() -> void:
    if not ResourceLoader.exists("res://scripts/weapons/WeaponProportions.gd"):
        printerr("WEAPON PROPORTIONS: calibration component missing")
        quit(1)
        return
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://weapon_proportions_%s.cfg" % OS.get_process_id()
    registry.select_character("atacante")
    var scene: Node3D = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    player.set_physics_process(false)
    var visual: Node3D = player.get("humanoid_avatar")
    var dimensions := {"pistol": 0.18, "rifle": 0.78, "sniper": 1.10, "shotgun": 0.95, "smg": 0.55}
    var initial_transforms := {}
    for cycle in range(3):
        for weapon in ["pistol", "rifle", "sniper", "shotgun", "smg"]:
            player.call("_equip_weapon", weapon)
            var model: Node3D = player.get("weapon_model")
            var bounds := _bounds(model, model)
            var size := bounds.size * model.global_basis.get_scale()
            _check(absf(size.z - float(dimensions[weapon])) < 0.015, "Wrong length: %s %.3fm" % [weapon, size.z])
            _check(absf(model.scale.x - model.scale.y) < 0.0001 and absf(model.scale.x-model.scale.z) < 0.0001, "Nonuniform weapon scale")
            if weapon == "pistol":
                _check(size.x < 0.055 and size.y < 0.18, "Pistol still oversized")
            if initial_transforms.has(weapon):
                _check(model.transform.is_equal_approx(initial_transforms[weapon]), "Scale/offset accumulates after equip: " + weapon)
            else:
                initial_transforms[weapon] = model.transform
            _check(model.get_node_or_null("Muzzle") != null, "Missing actual muzzle marker")
            _check(model.get_node_or_null("RightGrip") != null and model.get_node_or_null("LeftGrip") != null, "Missing model grip markers")
            if cycle > 0:
                continue
            for state in ["rest", "walk", "run", "crouch", "aim", "reload", "aim"]:
                for frame in range(90):
                    visual.animate(1.0/60.0, 1.0 if state in ["walk","run"] else 0.0, state=="run", state=="crouch", state=="aim", false, state=="reload", Vector2(0,-1), Vector3(0,0,-8 if state=="run" else (-5 if state=="walk" else 0)))
                for side in ["Left", "Right"]:
                    if side == "Left" and weapon == "pistol":
                        continue # pistola: só a mão direita segura (downloaded_avatar.gd grip_sides)
                    # Controlador do Linha de Fogo: na recarga a mão esquerda solta a arma e faz o caminho do carregador.
                    var free_reload: bool = state == "reload" and side == "Left" and bool(visual.get("clean_locomotion"))
                    if not free_reload:
                        _check(_grip_error(visual, side) < 0.012, "Palm contact lost: %s/%s/%s %.3fm" % [weapon,state,side,_grip_error(visual, side)])
                var muzzle := model.get_node("Muzzle") as Marker3D
                _check(player.get("gun_flash").global_position.distance_to(muzzle.global_position) < 0.002, "Flash detached from barrel")
            var profiles = load("res://scripts/weapons/WeaponProportions.gd")
            var expected: String = profiles.BASE + str(profiles.PROFILES[weapon]["file"])
            _check(player.get("equipped_external_model") and not model.get_meta("provisional",true), "Authored Polyy model not used: " + weapon)
            _check(model.get_meta("source_path","") == expected, "Wrong GLB source: " + weapon)
            player.call("_shoot")
            _check((player.get("last_shot_origin") as Vector3).distance_to(model.get_node("Muzzle").global_position) < 0.002, "Shot origin is not barrel tip")
    # A legacy mesh named Grip must survive while the physical socket keeps its name.
    var fallback := Node3D.new()
    scene.add_child(fallback)
    var mesh := MeshInstance3D.new()
    mesh.name = "Grip"
    mesh.mesh = BoxMesh.new()
    fallback.add_child(mesh)
    load("res://scripts/weapons/WeaponProportions.gd").apply(fallback,"pistol")
    _check(fallback.get_node("Grip") is Marker3D and fallback.get_node("GripMesh") == mesh,"Fallback grip marker collides with original mesh")
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures.slice(0,25):
        printerr(failure)
    print("WEAPON PROPORTIONS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
    quit(0 if failures.is_empty() else 1)
