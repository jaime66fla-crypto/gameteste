extends SceneTree
var failures: Array[String] = []
class Target extends StaticBody3D:
    var damage := 0.0
    func take_damage(amount: float) -> void:
        damage += amount
func _initialize() -> void:
    call_deferred("_run")
func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
func _box(parent: Node3D, at: Vector3, size: Vector3) -> Target:
    var body := Target.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    parent.add_child(body)
    body.global_position = at
    return body
func _run() -> void:
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://obstruction_%s.cfg" % OS.get_process_id()
    registry.select_character("jaime_swat")
    # Own empty world: map buildings must not intercept the synthetic targets.
    var scene := Node3D.new()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = load("res://scripts/player.gd").new()
    scene.add_child(player)
    player.set_physics_process(false)
    player.position = Vector3(0,20,0)
    var visual: Node3D = player.get("humanoid_avatar")
    # SpringArm3D updates its own child even while Player physics is paused.
    # A fixed test camera makes the two ray paths deterministic.
    var camera := Camera3D.new()
    scene.add_child(camera)
    player.set("camera",camera)
    for weapon in ["rifle","sniper","pistol","shotgun","smg"]:
        player.call("_equip_weapon",weapon)
        for frame in range(60):
            visual.animate(1.0/60.0,0.0,false,false,true,false,false)
        var muzzle: Marker3D = player.get("weapon_model").get_node("Muzzle")
        # Camera has a clear line above the low barrier beside the muzzle.
        camera.global_transform = Transform3D(Basis.IDENTITY,muzzle.global_position+Vector3(0,1,0.5))
        var target := _box(scene,camera.global_position+Vector3(0,0,-12),Vector3(2,2,0.6))
        var wall := _box(scene,muzzle.global_position+Vector3(0,0,-0.3),Vector3(0.6,0.4,0.12))
        await physics_frame
        await physics_frame
        player.call("_shoot")
        _check(wall.damage > 0, "Barrel obstruction ignored: "+weapon)
        _check(target.damage == 0, "Shot penetrated nearby obstruction: "+weapon)
        wall.queue_free()
        await process_frame
        await physics_frame
        await physics_frame
        player.call("_shoot")
        _check(target.damage > 0, "Clear barrel cannot reach camera target: "+weapon)
        var before: float = target.damage
        var grip: Marker3D = player.get("weapon_model").get_node("Grip")
        var inside := _box(scene,grip.global_position.lerp(muzzle.global_position,0.5),Vector3(0.3,0.3,0.035))
        await physics_frame
        await physics_frame
        player.call("_shoot")
        _check(inside.damage > 0 and target.damage == before,"Protruding barrel bypasses grip-to-muzzle wall: "+weapon)
        inside.queue_free()
        target.queue_free()
        await process_frame
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures:
        printerr(failure)
    print("WEAPON OBSTRUCTION: ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
    quit(0 if failures.is_empty() else 1)
