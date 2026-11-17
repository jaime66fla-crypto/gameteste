extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _run() -> void:
    var scene: Node3D = load("res://scenes/main.tscn").instantiate()
    root.add_child(scene)
    current_scene = scene
    var player: CharacterBody3D = scene.get_node("Jaime")
    player.set_physics_process(false)
    var fx: Node = player.get("sound_fx")
    var camera: Camera3D = player.get("camera")
    var bus_volume := AudioServer.get_bus_volume_db(0)
    var bus_mute := AudioServer.is_bus_mute(0)
    print("AUDIO CAMERA current=", camera.current, " custom_listener=", root.get_audio_listener_3d())
    var areas := scene.find_children("*", "Area3D", true, false)
    print("AUDIO AREA COUNT=", areas.size(), " BUS COUNT=", AudioServer.bus_count)
    for point in [Vector3.ZERO, Vector3(12, 0.1, -10), Vector3(48, 0.1, 48), Vector3(-48, 0.1, -48)]:
        player.position = point
        await physics_frame
        await process_frame
        for source_name in ["shot_player", "step_player"]:
            var source: Node = fx.get(source_name)
            if source is AudioStreamPlayer3D:
                print("AUDIO DIAGNOSTIC ", source_name, " player=", player.global_position, " source=", source.global_position, " listener_distance=", source.global_position.distance_to(camera.global_position), " unit=", source.unit_size, " max=", source.max_distance)
            _check(source is AudioStreamPlayer, "Local " + source_name + " remains distance-attenuated at " + str(point))
        for weapon_id in ["pistol", "smg", "rifle", "shotgun", "sniper"]:
            fx.shot(weapon_id)
            # One player per weapon sound (so bursts keep their tails): check the one that fired.
            var shot: Node = fx.get("last_shot_player")
            _check(shot is AudioStreamPlayer, "Local shot became distance-attenuated: " + weapon_id)
            _check(is_equal_approx(shot.volume_db, float(fx.SHOT_GAIN[weapon_id])), "Weapon gain changed")
            _check(shot.playing, "Shot did not start")
            shot.stop()
        for crouched in [false, true]:
            fx.update_steps(1.0, true, true, false, crouched)
            var step: Node = fx.get("step_player")
            _check(is_equal_approx(step.volume_db, -22.0 if crouched else -16.0), "Footstep gain changed")
            _check(step.playing, "Footstep did not start")
            step.stop()
        _check(is_equal_approx(AudioServer.get_bus_volume_db(0), bus_volume) and AudioServer.is_bus_mute(0) == bus_mute, "Map position changed master volume")
    # Shared effects must keep a spatial default for remote actors.
    var remote_host := Node3D.new()
    scene.add_child(remote_host)
    remote_host.position = Vector3(35, 0, -25)
    var remote = load("res://scripts/sound_fx.gd").new()
    remote_host.add_child(remote)
    for source_name in ["shot_player", "step_player"]:
        var source: Node = remote.get(source_name)
        _check(source is AudioStreamPlayer3D, "Remote effects lost spatialization")
        if source is AudioStreamPlayer3D:
            _check(source.global_position.distance_to(remote_host.global_position) < 0.01, "Remote source does not follow its actor")
            _check(source.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED, "Remote attenuation disabled")
    remote_host.position += Vector3(-20, 2, 10)
    remote_host.rotation.y = 1.2
    for source_name in ["shot_player", "step_player"]:
        var source: Node = remote.get(source_name)
        if source is AudioStreamPlayer3D:
            _check(source.global_position.distance_to(remote_host.global_position) < 0.01, "Remote source detached while actor moved")
    var ambience: Node = scene.get_node("EnvironmentAudio").get("player")
    _check(ambience is AudioStreamPlayer and is_equal_approx(ambience.volume_db, -27.0), "Existing ambience changed")
    scene.queue_free()
    await process_frame
    # Allow the audio mixing thread to release stopped/queued playbacks.
    await create_timer(0.15).timeout
    for failure in failures:
        printerr(failure)
    print("AUDIO CONSISTENCY: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
    quit(0 if failures.is_empty() else 1)
