extends "res://tools/jaime_swat/build_retarget.gd"
## Offline, deterministic derivative generation. Imported scenes are read only.
const DEST := "res://assets/personagens/jaime/retargeted/locomotion/"
const ROKOKO := "res://assets/personagens/jaime/animacoes/rokoko/"
const DIRECTIONS := {"forward":"Forward", "backward":"Backward", "left":"Left", "right":"Right", "forward_left":"ForwardLeft", "forward_right":"ForwardRight", "backward_left":"BackwardLeft", "backward_right":"BackwardRight"}
const PLANAR_DIRECTIONS := {"forward":Vector2(0,-1),"forward_right":Vector2(1,-1),"right":Vector2(1,0),"backward_right":Vector2(1,1),"backward":Vector2(0,1),"backward_left":Vector2(-1,1),"left":Vector2(-1,0),"forward_left":Vector2(-1,-1)}
var rig: Skeleton3D

func source_name(target_name: String) -> String:
    var short := target_name.trim_prefix("mixamorig")
    if rig.find_bone("Sam") >= 0:
        var torso := {"Spine":"Spine1", "Spine1":"Spine2", "Spine2":"Spine4"}
        if torso.has(short): return torso[short]
    for candidate in [target_name, "mixamorig_" + short, short]:
        if rig.find_bone(candidate) >= 0: return candidate
    if rig.find_bone("B-hips") >= 0: return super.source_name(target_name)
    var center := {"Spine":"Spine1", "Spine1":"Spine2", "Spine2":"Spine4"}
    if center.has(short): return center[short]
    for side in ["Left", "Right"]:
        if not short.begins_with(side): continue
        var limb := short.trim_prefix(side)
        var legs := {"UpLeg":"Thigh", "Leg":"Shin", "ToeBase":"Toe"}
        if legs.has(limb): return side + legs[limb]
        var fingers := {"Thumb":1,"Index":2,"Middle":3,"Ring":4,"Pinky":5}
        for finger in fingers:
            if limb.begins_with("Hand"+finger):
                var segment := int(limb.right(1))
                var suffix: String = ["Metacarpal","Proximal","Distal"][segment-1] if finger == "Thumb" else ["Proximal","Medial","Distal"][segment-1]
                return side + "Finger" + str(fingers[finger]) + suffix
    return ""

func _primary_child(skeleton: Skeleton3D, bone: int) -> int:
    if skeleton == rig:
        var name := String(skeleton.get_bone_name(bone))
        var desired := {"Hips":"Spine1", "Spine4":"Neck", "LeftHand":"LeftFinger3Proximal", "RightHand":"RightFinger3Proximal", "mixamorig_Hips":"mixamorig_Spine", "mixamorig_Spine2":"mixamorig_Neck", "mixamorig_LeftHand":"mixamorig_LeftHandMiddle1", "mixamorig_RightHand":"mixamorig_RightHandMiddle1"}
        if desired.has(name): return skeleton.find_bone(desired[name])
    return super._primary_child(skeleton,bone)

func _sample(ap: AnimationPlayer, clip: String, time: float) -> void:
    rig.reset_bone_poses()
    ap.play(clip)
    ap.seek(time,true)

func _cycle(ap: AnimationPlayer, clip: String, duration: float, running: bool) -> Vector2:
    # Search steady middle of take for a full same-foot cycle, including arm swing.
    var ids: Array[int] = []
    for name in ["LeftUpLeg","RightUpLeg","LeftLeg","RightLeg","LeftArm","RightArm","LeftFoot","RightFoot"]:
        ids.append(rig.find_bone(source_name("mixamorig"+name)))
    var poses := []
    var start := duration*0.2
    var count := floori(duration*0.6*30.0)
    for f in count:
        _sample(ap,clip,start+f/30.0)
        var pose := []
        for b in ids: pose.append(rig.get_bone_pose_rotation(b))
        poses.append(pose)
    var best := INF
    var interval := Vector2(start,start+0.8)
    var minimum := 23 if running else 34
    var maximum := 31 if running else 47
    for i in count-maximum-1:
        for gap in range(minimum,maximum+1):
            var excursion := 0.0
            for b in [0,1,2,3,6,7]:
                var maximum_angle := 0.0
                for k in range(i,i+gap,3):
                    maximum_angle = maxf(maximum_angle,poses[i][b].angle_to(poses[k][b]))
                excursion += maximum_angle
            # A still/rest segment can have perfect endpoints. It is not a gait.
            if excursion < (2.2 if running else 1.3): continue
            var error := 0.0
            for b in ids.size():
                if b in [4,5]: continue
                error += pow(poses[i][b].angle_to(poses[i+gap][b]),2)
                error += pow(poses[i+1][b].angle_to(poses[i+gap+1][b]),2)
                if b in [0,1,2,3,6,7]:
                    error += 2.5*pow(poses[i][b].angle_to(poses[i+gap][b]),2)
            var score := error/excursion
            if score < best:
                best = score
                interval = Vector2(start+i/30.0,start+(i+gap)/30.0)
    assert(is_finite(best),"No active repeatable gait cycle found in "+clip)
    return interval

func _align_phase(a: Animation, target: Skeleton3D, direction: String, period: float) -> Dictionary:
    var planar: Vector2 = PLANAR_DIRECTIONS[direction].normalized()
    var travel := Vector3(-planar.x,0,-planar.y)
    var foot := target.find_bone("mixamorigLeftFoot")
    var offset := 0.0
    var best := -INF
    var worst := INF
    var samples := ceili(a.length*120.0)
    # Find the actual retargeted left foot's greatest reach along travel. This
    # establishes the same left-leg event even for strafes and backward gaits.
    for frame in samples:
        var time := a.length*float(frame)/samples
        target.reset_bone_poses()
        for bone in target.get_bone_count():
            target.set_bone_pose_rotation(bone,a.rotation_track_interpolate(bone,time))
        target.set_bone_pose_position(0,a.position_track_interpolate(52,time))
        var reach := target.get_bone_global_pose(foot).origin.dot(travel)
        worst = minf(worst,reach)
        if reach > best:
            best = reach
            offset = time
    var aligned := Animation.new()
    aligned.length = period
    aligned.loop_mode = Animation.LOOP_LINEAR
    var frames := ceili(period*60.0)
    for track in a.get_track_count():
        var kind := a.track_get_type(track)
        aligned.add_track(kind)
        aligned.track_set_path(track,a.track_get_path(track))
        for frame in frames+1:
            var time := minf(float(frame)/60.0,period)
            var source_time := fposmod(offset+time/period*a.length,a.length)
            # Use precisely the same phase on both boundary keys.
            if frame == frames: source_time = offset
            if kind == Animation.TYPE_ROTATION_3D:
                aligned.rotation_track_insert_key(track,time,a.rotation_track_interpolate(track,source_time).normalized())
            else:
                aligned.position_track_insert_key(track,time,a.position_track_interpolate(track,source_time))
    return {"animation":aligned,"offset":offset,"phase":offset/a.length,"foot_travel_range":best-worst}

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(DEST)
    var target_model = load(MODEL).instantiate()
    root.add_child(target_model)
    var target := target_model.find_child("Skeleton3D",true,false) as Skeleton3D
    var rest_toe_y := minf(target.get_bone_global_rest(47).origin.y,target.get_bone_global_rest(51).origin.y)
    var library := AnimationLibrary.new()
    library.add_animation("idle",load(OUTPUT+"normal.tres"))
    var report := {"target":MODEL,"target_bones":target.get_bone_count(),"units":"Godot meters; imported scale ignored for rotation and source horizontal displacement removed", "sprint":"No distinct sprint recording identified. Runtime explicitly increases run playback rate.","clips":[]}
    report["source_inventory"] = []
    for file in DirAccess.get_files_at(ROKOKO):
        if not file.ends_with(".fbx"): continue
        var imported = load(ROKOKO+file).instantiate()
        root.add_child(imported)
        rig = imported.find_child("Skeleton3D",true,false) as Skeleton3D
        var player := imported.find_child("AnimationPlayer",true,false) as AnimationPlayer
        var map := {}
        for bone in target.get_bone_count():
            var mapped_name := source_name(target.get_bone_name(bone))
            assert(rig.find_bone(mapped_name)>=0,"Inventory unmapped "+file+": "+str(target.get_bone_name(bone)))
            map[str(target.get_bone_name(bone))] = mapped_name
        var animations := []
        for name in player.get_animation_list():
            animations.append({"name":name,"duration":player.get_animation(name).length})
        report.source_inventory.append({"source":ROKOKO+file,"bones":rig.get_bone_count(),"bone_map":map,"animations":animations,"selection":"walk_forward" if file.begins_with("02-") else ("run_forward" if file.begins_with("05-") else "available variant; not assigned a runtime alias"),"classification":"injured run" if "injured" in file else ("run" if "running" in file else "walk variant")})
        imported.free()
    for gait in ["walk","run"]:
        for direction in DIRECTIONS:
            var alias: String = gait+"_"+direction
            var source_path: String = BASE+"Movement/"+gait.capitalize()+"/HumanM@"+gait.capitalize()+"01_"+DIRECTIONS[direction]+".fbx"
            if alias == "walk_forward": source_path = ROKOKO+"02-walkforward.fbx"
            if alias == "run_forward": source_path = ROKOKO+"05-running-treadmill.fbx"
            assert(FileAccess.file_exists(source_path+".import"),"Import first: "+source_path)
            var model = load(source_path).instantiate()
            root.add_child(model)
            rig = model.find_child("Skeleton3D",true,false) as Skeleton3D
            var ap := model.find_child("AnimationPlayer",true,false) as AnimationPlayer
            var clip := String(ap.get_animation_list()[0])
            var original := ap.get_animation(clip)
            var interval := _cycle(ap,clip,original.length,gait=="run") if source_path.begins_with(ROKOKO) else Vector2(0,original.length)
            var a := Animation.new()
            a.length = interval.y-interval.x
            a.loop_mode = Animation.LOOP_LINEAR
            var mapping := {}
            var sources: Array[int] = []
            var corrections: Array[Basis] = []
            for b in target.get_bone_count():
                var source := source_name(target.get_bone_name(b))
                var id := rig.find_bone(source)
                assert(id>=0,"Unmapped: "+str(target.get_bone_name(b))+" in "+source_path)
                mapping[String(target.get_bone_name(b))] = source
                sources.append(id)
                corrections.append(_rest_frame(rig,id)*_rest_frame(target,b).inverse()*target.get_bone_global_rest(b).basis.orthonormalized())
                var t := a.add_track(Animation.TYPE_ROTATION_3D)
                a.track_set_path(t,NodePath("Soldier/Node/Skeleton3D:"+String(target.get_bone_name(b))))
            var ht := a.add_track(Animation.TYPE_POSITION_3D)
            a.track_set_path(ht,NodePath("Soldier/Node/Skeleton3D:mixamorigHips"))
            var frames := ceili(a.length*60.0)
            _sample(ap,clip,interval.x)
            var root_start := rig.get_bone_global_pose(sources[0]).origin
            # Remove heading of the steady take; only pelvis yaw, never limb swing.
            var heading := Basis(_delta(rig,sources[0])).get_euler().y if source_path.begins_with(ROKOKO) else 0.0
            var heading_fix := Basis(Vector3.UP,-heading)
            for f in frames+1:
                var time := minf(float(f)/60.0,a.length)
                _sample(ap,clip,interval.x+time)
                target.reset_bone_poses()
                for b in target.get_bone_count():
                    var motion := _delta(rig,sources[b])
                    if rig.find_bone("B-spine")>=0 and target.get_bone_name(b)==&"mixamorigSpine1": motion = _delta(rig,rig.find_bone("B-spine")).slerp(motion,0.5)
                    var desired := heading_fix*Basis(motion)*corrections[b]
                    var parent := target.get_bone_parent(b)
                    var parent_basis := target.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
                    var q := (parent_basis.inverse()*desired).orthonormalized().get_rotation_quaternion().normalized()
                    target.set_bone_pose_rotation(b,q)
                    a.rotation_track_insert_key(b,time,q)
                var toe_y := minf(target.get_bone_global_pose(47).origin.y,target.get_bone_global_pose(51).origin.y)
                a.position_track_insert_key(ht,time,target.get_bone_rest(0).origin+Vector3.UP*(rest_toe_y-toe_y))
            var root_delta := rig.get_bone_global_pose(sources[0]).origin-root_start
            # Close a short 100ms tail with smoothstep; identical endpoints guarantee wrap continuity.
            var max_seam := 0.0
            for t in a.get_track_count():
                var n := a.track_get_key_count(t)
                var first = a.track_get_key_value(t,0)
                if t<52: max_seam = maxf(max_seam,first.angle_to(a.track_get_key_value(t,n-1)))
                for k in n:
                    var time := a.track_get_key_time(t,k)
                    var blend := smoothstep(maxf(0,a.length-0.1),a.length,time)
                    if blend <= 0: continue
                    var value = a.track_get_key_value(t,k)
                    a.track_set_key_value(t,k,value.slerp(first,blend) if t<52 else value.lerp(first,blend))
            var source_period := a.length
            var alignment := _align_phase(a,target,direction,5.0/6.0 if gait=="walk" else 17.0/30.0)
            a = alignment.animation
            assert(ResourceSaver.save(a,DEST+alias+".tres")==OK)
            a.take_over_path(DEST+alias+".tres")
            library.add_animation(alias,a)
            report.clips.append({"alias":alias,"source":source_path,"source_clip":clip,"source_bones":rig.get_bone_count(),"bone_map":mapping,"source_duration":original.length,"crop_start":interval.x,"crop_end":interval.y,"source_cycle_period":source_period,"duration":a.length,"duration_normalization_ratio":a.length/source_period,"phase_offset_source_seconds":alignment.offset,"phase_offset_normalized":alignment.phase,"phase_event":"left foot maximum target-space reach along alias travel direction","phase_search_hz":120,"phase_foot_projection_range_m":alignment.foot_travel_range,"source_root_delta_m":str(root_delta),"source_horizontal_speed_m_s":Vector2(root_delta.x,root_delta.z).length()/source_period,"nominal_speed_note":"Treadmill/in-place clips do not provide reliable travel speed.","removed_heading_radians":heading,"raw_max_loop_rotation_seam_radians":max_seam,"output_rotation_seam_radians":0,"sample_hz":60})
            print("LOCOMOTION ",alias," ",interval," bones=",mapping.size()," raw_seam=",max_seam)
            model.free()
    assert(ResourceSaver.save(library,OUTPUT+"locomotion_library.tres")==OK)
    FileAccess.open("res://tools/rokoko/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
    target_model.free()
    quit()


