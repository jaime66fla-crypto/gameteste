extends SceneTree
## Isolated visual QA: creates its own camera and test save file.
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    root.size = Vector2i(1100,900)
    var registry = load("res://scripts/characters/character_registry.gd")
    registry.storage_path = "user://weapon_capture_%s.cfg" % OS.get_process_id()
    registry.select_character("atacante")
    var scene: Node3D = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: Node3D = scene.get_node("Jaime")
    player.position = Vector3(0,0.025,10)
    player.set_physics_process(false)
    var visual: Node3D = player.get("humanoid_avatar")
    var camera := Camera3D.new()
    scene.add_child(camera)
    camera.current = true
    camera.fov = 32
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35,-45,0)
    light.light_energy = 1.1
    scene.add_child(light)
    var sheet := Image.create(1650,2250,false,Image.FORMAT_RGB8)
    for index in range(5):
        var weapon: String = ["pistol","rifle","sniper","shotgun","smg"][index]
        player.call("_equip_weapon",weapon)
        for state_index in range(6):
            var state: String = ["rest","walk","run","crouch","aim","aim_side"][state_index]
            for frame in range(90):
                visual.animate(1.0/60.0,1.0 if state in ["walk","run"] else 0.0,state=="run",state=="crouch",state.begins_with("aim"),false,false,Vector2(0,-1),Vector3(0,0,-8 if state=="run" else (-5 if state=="walk" else 0)))
            var height := 1.1 if state=="crouch" else 1.42
            camera.position = player.position + (Vector3(2.3,1.5,0.15) if state=="aim_side" else Vector3(1.5,1.65,-2.2))
            camera.look_at(player.position+Vector3(0,height,-0.1))
            await process_frame
            await RenderingServer.frame_post_draw
            var capture := root.get_texture().get_image()
            capture.save_png("res://.godot/weapon-%s-%s.png" % [weapon,state])
            capture.resize(275,450,Image.INTERPOLATE_LANCZOS)
            capture.convert(Image.FORMAT_RGB8)
            sheet.blit_rect(capture,Rect2i(0,0,275,450),Vector2i(state_index*275,index*450))
    print("WEAPON CAPTURES=",sheet.save_png("res://.godot/weapon-contact-sheet.png"))
    scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(registry.storage_path))
    quit()
