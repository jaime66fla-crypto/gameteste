extends SceneTree
var failures := 0
func check(ok: bool, text: String) -> void:
    if not ok:
        failures += 1
        printerr("FAIL: ", text)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var data: Dictionary = load("res://scripts/survival/survival_data.gd").world()
    var mountains: Array = data.get("mountains", [])
    check(mountains.size() >= 3, "montanhas compartilhadas com o servidor")
    if not mountains.is_empty():
        var terrain = load("res://scripts/survival/mountain_terrain.gd")
        var world := Node3D.new()
        root.add_child(world)
        terrain.build(world, mountains)
        await physics_frame
        await physics_frame
        for m in mountains:
            var center := Vector3(float(m.x), float(m.h) + 10.0, float(m.z))
            var query := PhysicsRayQueryParameters3D.create(center, center - Vector3(0, 100, 0), 1)
            var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
            check(not hit.is_empty() and absf(float(hit.position.y) - float(m.h)) < 0.05, "colisão no cume")
            check(float(m.h) * PI / (2.0 * float(m.r)) < 0.95, "encosta abaixo de 45 graus")
            check(maxf(absf(float(m.x)), absf(float(m.z))) - float(m.r) >= 300.0, "área antiga preservada")
            var point := Vector3(float(m.x) + float(m.r) * 0.5, 0, float(m.z))
            check(absf(float(terrain.height_at(point, mountains)) - float(m.h) * 0.5) < 0.05, "altura no meio da subida")
        # Uma cápsula caminha da base ao cume usando a mesma física do jogador.
        var m: Dictionary = mountains[0]
        var walker := CharacterBody3D.new()
        var shape := CollisionShape3D.new()
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.25
        capsule.height = 1.7
        shape.shape = capsule
        shape.position.y = 0.85
        walker.add_child(shape)
        walker.floor_snap_length = 0.5
        walker.floor_max_angle = deg_to_rad(45.0)
        world.add_child(walker)
        walker.position = Vector3(float(m.x) - float(m.r) + 2.0, 0.5, float(m.z))
        for i in 650:
            await physics_frame
            walker.velocity = Vector3(8.0, walker.velocity.y - 20.0 / 60.0, 0)
            walker.move_and_slide()
            if walker.position.x >= float(m.x) - 2.0:
                break
        check(walker.position.y > 25.0, "personagem sobe fisicamente até o cume")
        world.free()
    print("MOUNTAIN TERRAIN: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
