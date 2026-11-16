extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    root.size = Vector2i(1280, 720)
    var scene: Node3D = load("res://scenes/jaime_swat_test.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    scene.set_process(false)
    for clip in ["normal", "aim", "fire"]:
        for side in [false, true]:
            scene.call("set_view", side)
            scene.call("preview_clip", clip, 0.20 if clip == "fire" else 0.0)
            await process_frame
            await RenderingServer.frame_post_draw
            var path := "res://.godot/swat-preview-%s-%s.png" % [clip, "side" if side else "front"]
            var result := root.get_texture().get_image().save_png(path)
            print("SWAT SCREENSHOT ", path, " result=", result)
    scene.queue_free()
    await process_frame
    quit()
