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
    registry.select_character("01")
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
        # 1) Hugging low cover: its lip right past the barrel does not eat the
        #    shot; the head sees over it, so the round clears it.
        var lip := _box(scene,muzzle.global_position+Vector3(0,0,-0.3),Vector3(0.6,0.4,0.12))
        await physics_frame
        await physics_frame
        _check((player.call("predict_shot_block") as Dictionary).is_empty(), "Crosshair shows blocked over low cover: "+weapon)
        player.call("_shoot")
        _check(lip.damage == 0, "Cover lip in front of the barrel ate the shot: "+weapon)
        _check(target.damage > 0, "Shot over low cover did not reach the target: "+weapon)
        lip.queue_free()
        await process_frame
        await physics_frame
        await physics_frame
        var before: float = target.damage
        await process_frame
        _check((player.call("predict_shot_block") as Dictionary).is_empty(), "Crosshair shows blocked with a clear shot: "+weapon)
        player.call("_shoot")
        _check(target.damage > before, "Clear barrel cannot reach camera target: "+weapon)
        # 2) A tall wall right in front (no seeing over it) still stops the round,
        #    even though the aim ray now starts at the barrel's depth.
        before = target.damage
        var wall := _box(scene,muzzle.global_position+Vector3(0,0,-0.3),Vector3(3,6,0.12))
        await physics_frame
        await physics_frame
        player.call("_shoot")
        _check(wall.damage > 0 and target.damage == before, "Shot went through a tall wall in front: "+weapon)
        wall.queue_free()
        await process_frame
        # 3) A low obstacle farther ahead on the barrel line (camera sees over it)
        #    still blocks: only the lip right past the barrel is cleared.
        before = target.damage
        # 0.8 m tall: covers the rising barrel line (+0.2 m there), still well under the camera line (+1 m).
        # 3 m wide so no shotgun pellet slips around it.
        var low := _box(scene,muzzle.global_position+Vector3(0,0,-2.5),Vector3(3,0.8,0.12))
        await physics_frame
        await physics_frame
        await process_frame # nova leitura da previsão (cache por quadro)
        # The camera sees over it, the round does not: the crosshair must say so,
        # marking the point on the obstacle.
        var block: Dictionary = player.call("predict_shot_block")
        _check(not block.is_empty() and absf((block["point"] as Vector3).z - low.global_position.z) < 0.3, "Crosshair does not warn about the wall the camera sees past: "+weapon)
        player.call("_shoot")
        _check(low.damage > 0 and target.damage == before, "Barrel obstruction farther ahead ignored: "+weapon)
        low.queue_free()
        target.queue_free()
        await process_frame
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    for failure in failures:
        printerr(failure)
    print("WEAPON OBSTRUCTION: ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
    quit(0 if failures.is_empty() else 1)
