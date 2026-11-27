extends SceneTree
const Registry = preload("res://scripts/characters/character_registry.gd")
func _initialize() -> void:
    call_deferred("_run")
func _capture(name: String) -> void:
    for frame in range(4):
        await process_frame
    await RenderingServer.frame_post_draw
    var path := "res://.godot/character-selection-" + name + ".png"
    print("CHARACTER CAPTURE ", path, " result=", root.get_texture().get_image().save_png(path))
func _run() -> void:
    root.size = Vector2i(1280, 720)
    Registry.storage_path = "user://character_capture_%s.cfg" % OS.get_process_id()
    var menu: Control = load("res://scenes/menu.tscn").instantiate()
    root.add_child(menu)
    current_scene = menu
    menu.call("_show_characters")
    await _capture("original")
    menu.call("_select_character", "01")
    await _capture("swat")
    menu.call("_start_match")
    await process_frame
    await process_frame
    var match_scene := current_scene
    var player: CharacterBody3D = match_scene.get_node("Jaime")
    player.call("_equip_weapon", "rifle")
    Input.action_press("aim")
    for frame in range(40):
        await physics_frame
        await process_frame
    player.set_physics_process(false)
    var camera := Camera3D.new()
    match_scene.add_child(camera)
    camera.current = true
    camera.position = player.position + Vector3(2.7, 1.35, -3.5)
    camera.fov = 39
    camera.look_at(player.position + Vector3.UP * 1.0)
    await _capture("match-aim")
    player.set_physics_process(true)
    Input.action_release("aim")
    Input.action_press("crouch")
    for frame in range(40):
        await physics_frame
        await process_frame
    await _capture("match-crouch")
    Input.action_release("crouch")
    match_scene.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(Registry.storage_path))
    quit()
