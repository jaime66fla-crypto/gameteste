extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var scene = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player = scene.get_node("Jaime")
    player.set_physics_process(false)
    var avatar = player.get("humanoid_avatar")
    var chest: MeshInstance3D = avatar.get_node("Hips/Torso/Chest")
    var blocker := StaticBody3D.new()
    blocker.collision_layer = 32
    blocker.collision_mask = 0
    chest.add_child(blocker)
    var collision := CollisionShape3D.new()
    collision.shape = chest.mesh.create_trimesh_shape()
    blocker.add_child(collision)
    var camera: Camera3D = player.get("camera")
    var spring: SpringArm3D = camera.get_parent()
    spring.spring_length = 2.15
    var failures := 0
    for crouched in [false, true]:
        player.get("arm_pivot").position.y = 1.062 if crouched else 1.548
        for angle in [-0.14, 0.0, 0.15]:
            player.get("arm_pivot").rotation.x = angle
            for frame in range(180):
                avatar.animate(1.0 / 60.0, 0.0, false, crouched, true, false, false)
            await physics_frame
            await process_frame
            var slide: Node3D = player.get("weapon_model").get_node("Slide")
            var query := PhysicsRayQueryParameters3D.create(camera.global_position, slide.global_position, 32)
            var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
            if not hit.is_empty():
                failures += 1
                printerr("Pistol slide occluded by torso; crouched=", crouched, " pitch=", angle)
    scene.queue_free()
    await process_frame
    print("PISTOL VISIBILITY: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
