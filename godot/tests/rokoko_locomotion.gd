extends SceneTree
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var path := "res://assets/personagens/jaime/retargeted/locomotion_library.tres"
    if not ResourceLoader.exists(path):
        push_error("Missing generated SWAT locomotion library")
        quit(1)
        return
    var lib = load(path) as AnimationLibrary
    var failures := 0
    var report = JSON.parse_string(FileAccess.get_file_as_string("res://tools/rokoko/report.json"))
    if report.target_bones != 52 or report.clips.size() != 16: failures += 1
    if report.source_inventory.size() != 16: failures += 1
    for source in report.source_inventory:
        if source.bone_map.size() != 52: failures += 1
    for clip in report.clips:
        if clip.bone_map.size() != 52: failures += 1
        if clip.phase_foot_projection_range_m < 0.1: failures += 1
        if clip.phase_offset_normalized < 0 or clip.phase_offset_normalized >= 1: failures += 1
    var factory = load("res://scripts/characters/locomotion_library.gd")
    var blend: AnimationNodeBlendSpace2D = factory.build_blend_space()
    if blend.get_blend_point_count() != 17: failures += 1
    var model = load("res://assets/personagens/jaime/[FREE] Rigged Stylized SWAT Soldier.glb").instantiate()
    root.add_child(model)
    var skeleton := model.find_child("Skeleton3D",true,false) as Skeleton3D
    for name in lib.get_animation_list():
        var a := lib.get_animation(name)
        if String(name).begins_with("walk_") and absf(a.length-5.0/6.0)>0.00001: failures += 1
        if String(name).begins_with("run_") and absf(a.length-17.0/30.0)>0.00001: failures += 1
        if a.loop_mode != Animation.LOOP_LINEAR: failures += 1
        var rotations := 0
        for t in a.get_track_count():
            var kind := a.track_get_type(t)
            if kind == Animation.TYPE_ROTATION_3D:
                rotations += 1
                var first: Quaternion = a.track_get_key_value(t,0)
                var last: Quaternion = a.track_get_key_value(t,a.track_get_key_count(t)-1)
                if first.angle_to(last) > 0.001 and name != &"idle": failures += 1
                for k in a.track_get_key_count(t):
                    var q: Quaternion = a.track_get_key_value(t,k)
                    if not q.is_finite() or absf(q.length()-1.0)>0.001: failures += 1
            elif kind == Animation.TYPE_POSITION_3D:
                if not str(a.track_get_path(t)).ends_with(":mixamorigHips"): failures += 1
                var first: Vector3 = a.track_get_key_value(t,0)
                for k in a.track_get_key_count(t):
                    var p: Vector3 = a.track_get_key_value(t,k)
                    if not p.is_finite() or absf(p.x-first.x)>0.00001 or absf(p.z-first.z)>0.00001: failures += 1
            else: failures += 1
        if rotations != 52: failures += 1
        # Evaluate actual target global bone transforms at 17 subframes: lengths and
        # local child translations must stay at imported rest values.
        var first_reach := 0.0
        var maximum_reach := -INF
        for sample in 17:
            skeleton.reset_bone_poses()
            var time := a.length*sample/16.0
            for t in a.get_track_count():
                var bone := skeleton.find_bone(a.track_get_path(t).get_subname(0))
                if bone < 0:
                    failures += 1
                    continue
                if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
                    skeleton.set_bone_pose_rotation(bone,a.rotation_track_interpolate(t,time))
                elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
                    skeleton.set_bone_pose_position(bone,a.position_track_interpolate(t,time))
            for bone in skeleton.get_bone_count():
                if not skeleton.get_bone_global_pose(bone).is_finite(): failures += 1
                if bone>0 and skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin)>0.00001: failures += 1
                if skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE)>0.00001: failures += 1
            if name != &"idle":
                var direction: Vector2 = factory.DIRECTIONS[String(name).trim_prefix("walk_").trim_prefix("run_")].normalized()
                var travel := Vector3(-direction.x,0,-direction.y)
                var reach := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorigLeftFoot")).origin.dot(travel)
                if sample == 0: first_reach = reach
                maximum_reach = maxf(maximum_reach,reach)
        if name != &"idle" and maximum_reach-first_reach>0.005: failures += 1
    if lib.get_animation_list().size() != 17: failures += 1
    print("ROKOKO LOCOMOTION: ","PASS" if failures == 0 else "FAIL", " animations=",lib.get_animation_list().size(), " failures=",failures)
    model.free()
    quit(0 if failures == 0 else 1)

