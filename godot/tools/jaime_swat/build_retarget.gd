extends SceneTree
## Rebuilds derived animations only; never edits the imported GLB/FBX or their rest poses.
const MODEL := "res://assets/personagens/jaime/[FREE] Rigged Stylized SWAT Soldier.glb"
const BASE := "res://assets/personagens/jaime/animacoes/Animations/Male/"
const OUTPUT := "res://assets/personagens/jaime/retargeted/"
const CLIPS := {
    "normal": "Idles/HumanM@MilitaryIdle01.fbx",
    "aim": "Combat/AssaultRifle/HumanM@AssaultRifle_Aim01.fbx",
    "fire": "Combat/AssaultRifle/HumanM@AssaultRifle_Aim01_Shoot01.fbx"
}
const CENTER_MAP := {"Hips": "B-hips", "Spine": "B-spine", "Spine1": "B-chest", "Spine2": "B-chest", "Neck": "B-neck", "Head": "B-head"}
const LIMB_MAP := {"Shoulder": "shoulder", "Arm": "upperArm", "ForeArm": "forearm", "Hand": "hand", "UpLeg": "thigh", "Leg": "shin", "Foot": "foot", "ToeBase": "toe"}
const FINGERS := {"Index": "indexFinger", "Middle": "middleFinger", "Ring": "ringFinger", "Pinky": "pinky", "Thumb": "thumb"}

func _initialize() -> void:
    call_deferred("_run")

func source_name(target_name: String) -> String:
    var short := target_name.trim_prefix("mixamorig")
    if CENTER_MAP.has(short):
        return CENTER_MAP[short]
    for side in ["Left", "Right"]:
        if not short.begins_with(side):
            continue
        var limb := short.trim_prefix(side)
        var suffix := ".L" if side == "Left" else ".R"
        if LIMB_MAP.has(limb):
            return "B-" + LIMB_MAP[limb] + suffix
        for finger in FINGERS:
            if limb.begins_with("Hand" + finger):
                return "B-" + FINGERS[finger] + "0" + limb.right(1) + suffix
    return ""

func _primary_child(skeleton: Skeleton3D, bone: int) -> int:
    var name := String(skeleton.get_bone_name(bone))
    var preferred := ""
    if name.ends_with("Hips"):
        preferred = "mixamorigSpine"
    elif name == "B-hips":
        preferred = "B-spine"
    elif name == "mixamorigSpine2":
        preferred = "mixamorigNeck"
    elif name == "B-chest":
        preferred = "B-neck"
    elif name.ends_with("Hand"):
        preferred = name + "Middle1"
    elif name.begins_with("B-hand."):
        preferred = "B-middleFinger01" + name.right(2)
    if preferred != "":
        return skeleton.find_bone(preferred)
    var children := skeleton.get_bone_children(bone)
    return children[0] if not children.is_empty() else -1

func _rest_frame(skeleton: Skeleton3D, bone: int) -> Basis:
    var child := _primary_child(skeleton, bone)
    var origin := skeleton.get_bone_global_rest(bone).origin
    var direction: Vector3
    if child >= 0:
        direction = skeleton.get_bone_global_rest(child).origin - origin
    if child < 0 or direction.length_squared() < 0.00000001:
        var parent := skeleton.get_bone_parent(bone)
        direction = origin - skeleton.get_bone_global_rest(parent).origin if parent >= 0 else Vector3.UP
    var y := direction.normalized()
    var reference := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.UP
    var x := y.cross(reference).normalized()
    return Basis(x, y, x.cross(y).normalized())

func _delta(skeleton: Skeleton3D, bone: int) -> Quaternion:
    return (skeleton.get_bone_global_pose(bone).basis.orthonormalized() * skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()).get_rotation_quaternion()

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(OUTPUT)
    var target_model: Node3D = load(MODEL).instantiate()
    root.add_child(target_model)
    var target := target_model.find_child("Skeleton3D", true, false) as Skeleton3D
    var rest_toe_y := minf(target.get_bone_global_rest(47).origin.y, target.get_bone_global_rest(51).origin.y)
    var mapped := 0
    for clip_name in CLIPS:
        var source_model: Node3D = load(BASE + CLIPS[clip_name]).instantiate()
        root.add_child(source_model)
        var source := source_model.find_child("Skeleton3D", true, false) as Skeleton3D
        var player := source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
        var source_clip := String(player.get_animation_list()[0])
        var source_animation := player.get_animation(source_clip)
        var animation := Animation.new()
        animation.length = source_animation.length
        animation.loop_mode = Animation.LOOP_NONE if clip_name == "fire" else Animation.LOOP_LINEAR
        var sources: Array[int] = []
        var corrections: Array[Basis] = []
        for bone in range(target.get_bone_count()):
            var mapped_bone := source.find_bone(source_name(target.get_bone_name(bone)))
            assert(mapped_bone >= 0, "Unmapped SWAT bone: " + String(target.get_bone_name(bone)))
            sources.append(mapped_bone)
            corrections.append(_rest_frame(source, mapped_bone) * _rest_frame(target, bone).inverse() * target.get_bone_global_rest(bone).basis.orthonormalized())
            assert(absf(corrections[-1].determinant() - 1.0) < 0.001, "Invalid rest frame")
            var track := animation.add_track(Animation.TYPE_ROTATION_3D)
            animation.track_set_path(track, NodePath("Soldier/Node/Skeleton3D:" + String(target.get_bone_name(bone))))
        var hips_track := animation.add_track(Animation.TYPE_POSITION_3D)
        animation.track_set_path(hips_track, NodePath("Soldier/Node/Skeleton3D:mixamorigHips"))
        var frame_count := ceili(animation.length * 30.0)
        player.play(source_clip)
        for frame in range(frame_count + 1):
            var time := minf(frame / 30.0, animation.length)
            source.reset_bone_poses()
            player.seek(time, true)
            target.reset_bone_poses()
            for bone in range(target.get_bone_count()):
                var motion := _delta(source, sources[bone])
                if target.get_bone_name(bone) == &"mixamorigSpine1":
                    motion = _delta(source, source.find_bone("B-spine")).slerp(motion, 0.5)
                var desired_basis := Basis(motion) * corrections[bone]
                var parent := target.get_bone_parent(bone)
                var parent_basis := target.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
                var local_rotation := (parent_basis.inverse() * desired_basis).orthonormalized().get_rotation_quaternion().normalized()
                target.set_bone_pose_rotation(bone, local_rotation)
                animation.rotation_track_insert_key(bone, time, local_rotation)
            # In-place poses: preserve sole height instead of importing source root motion.
            var toe_y := minf(target.get_bone_global_pose(47).origin.y, target.get_bone_global_pose(51).origin.y)
            var hips_position := target.get_bone_rest(0).origin + Vector3.UP * (rest_toe_y - toe_y)
            animation.position_track_insert_key(hips_track, time, hips_position)
        var result := ResourceSaver.save(animation, OUTPUT + clip_name + ".tres")
        assert(result == OK, "Cannot save retargeted animation")
        print("RETARGET ", clip_name, ": mapped=", sources.size(), " frames=", frame_count + 1, " length=", animation.length)
        mapped = sources.size()
        source_model.free()
    target_model.free()
    print("SWAT RETARGET: PASS mapped=", mapped)
    quit()
