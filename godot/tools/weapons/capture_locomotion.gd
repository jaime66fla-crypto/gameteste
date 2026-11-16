extends SceneTree
func _initialize() -> void:
    call_deferred("_run")
func _frames(count: int) -> void:
    for frame in count:
        await physics_frame
        await process_frame
func _run() -> void:
    root.size = Vector2i(1280,900)
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://locomotion_capture_%s.cfg" % OS.get_process_id()
    registry.select_character("jaime_swat")
    var scene: Node3D = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    player.call("_equip_weapon","rifle")
    var inspector := Camera3D.new()
    scene.add_child(inspector)
    inspector.current = true
    inspector.fov = 43
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-30,20,0)
    light.light_energy = 1.2
    scene.add_child(light)
    var cases := {"idle":[],"walk":["move_forward"],"run":["move_forward","sprint"],"strafe":["move_right"],"backward":["move_back"],"aim_walk":["move_forward","aim"],"crouch":["crouch","move_right"],"jump":["move_forward","jump"]}
    var sheet := Image.create(1280,1800,false,Image.FORMAT_RGB8)
    var index := 0
    for state in cases:
        for action in ["move_forward","move_back","move_right","move_left","sprint","aim","crouch","jump"]:
            Input.action_release(action)
        player.position = Vector3(0,0.1,10)
        player.set("yaw",PI/2 if state=="strafe" else 0.0)
        player.set("pitch",0.0)
        player.set("velocity",Vector3.ZERO)
        await _frames(24)
        for action in cases[state]: Input.action_press(action)
        await _frames(8 if state=="jump" else 22)
        inspector.global_position = player.global_position+Vector3(2.0,1.7,-3.5)
        inspector.look_at(player.global_position+Vector3(0,0.9,0))
        await process_frame
        await RenderingServer.frame_post_draw
        var capture := root.get_texture().get_image()
        capture.save_png("res://.godot/locomotion-%s.png" % state)
        capture.resize(640,450,Image.INTERPOLATE_LANCZOS)
        capture.convert(Image.FORMAT_RGB8)
        sheet.blit_rect(capture,Rect2i(0,0,640,450),Vector2i((index%2)*640,(index/2)*450))
        print("CAPTURE ",state," position=",player.global_position," velocity=",player.get("velocity"))
        index += 1
    for action in ["move_forward","move_back","move_right","sprint","aim","crouch","jump"]: Input.action_release(action)
    print("LOCOMOTION SHEET=",sheet.save_png("res://.godot/locomotion-contact-sheet.png"))
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    quit()
