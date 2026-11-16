extends SceneTree
const FILES := ["compact_polymer_pistol", "modern_tactical_carbine", "bolt_action_sniper_rifle", "pump_action_shotgun", "compact_submachine_gun"]
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    root.size=Vector2i(1280,720)
    var control:=Control.new()
    root.add_child(control)
    var grid:=GridContainer.new()
    grid.columns=3
    control.add_child(grid)
    for filename in FILES:
        var column:=VBoxContainer.new()
        grid.add_child(column)
        var label:=Label.new()
        label.text=filename
        label.add_theme_font_size_override("font_size",15)
        column.add_child(label)
        var container:=SubViewportContainer.new()
        container.custom_minimum_size=Vector2(415,310)
        container.stretch=true
        column.add_child(container)
        var viewport:=SubViewport.new()
        viewport.own_world_3d=true
        container.add_child(viewport)
        var world:=Node3D.new()
        viewport.add_child(world)
        var model:Node3D=load("res://assets/weapons/polyy/models/"+filename+".glb").instantiate()
        world.add_child(model)
        var environment:=WorldEnvironment.new()
        var env:=Environment.new()
        env.background_mode=Environment.BG_COLOR
        env.background_color=Color("#1c2b35")
        env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color=Color.WHITE
        env.ambient_light_energy=0.8
        environment.environment=env
        world.add_child(environment)
        for angle in [-30,150]:
            var light:=DirectionalLight3D.new()
            light.rotation_degrees=Vector3(-40,angle,0)
            light.light_energy=1.4
            world.add_child(light)
        var camera:=Camera3D.new()
        world.add_child(camera)
        camera.position=Vector3(0.1,0.15,1.7)
        camera.projection=Camera3D.PROJECTION_ORTHOGONAL
        camera.size=1.3
        camera.look_at(Vector3.ZERO)
        camera.current=true
    for frame in range(10):
        await process_frame
    await RenderingServer.frame_post_draw
    print("POLYY MODELS CAPTURE=",root.get_texture().get_image().save_png("res://.godot/polyy-models.png"))
    quit()
