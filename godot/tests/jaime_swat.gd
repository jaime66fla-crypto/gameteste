extends SceneTree
var failures: Array[String] = []
var previous_arms: Dictionary = {}

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)

func _run() -> void:
    var scene_path := "res://scenes/jaime_swat_test.tscn"
    if not ResourceLoader.exists(scene_path):
        printerr("SWAT TEST: independent scene is missing")
        quit(1)
        return
    var actions_before := InputMap.get_actions()
    var scene: Node3D = load(scene_path).instantiate()
    root.add_child(scene)
    current_scene = scene
    scene.set_process(false)
    var skeleton: Skeleton3D = scene.get("skeleton")
    var tree: AnimationTree = scene.get_node("AnimationTree")
    _check(skeleton != null and skeleton.get_bone_count() == 52, "SWAT skeleton must preserve 52 bones")
    _check(tree.active, "AnimationTree must be active")
    _check(InputMap.get_actions() == actions_before, "Test scene modified global controls")
    for clip in ["normal", "aim", "fire"]:
        var animation: Animation = scene.get_node("AnimationPlayer").get_animation(clip)
        _check(animation != null and animation.length > 0.5, "Missing retargeted clip: " + clip)
        if animation == null:
            continue
        for track in range(animation.get_track_count()):
            _check(animation.track_get_type(track) != Animation.TYPE_SCALE_3D, "Retarget must not animate bone scale")
        scene.call("preview_clip", clip, 0.0)
        for sample_index in range(12):
            scene.call("preview_clip", clip, animation.length * sample_index / 12.0)
            var leg_track := animation.find_track(NodePath("Soldier/Node/Skeleton3D:mixamorigRightUpLeg"), Animation.TYPE_ROTATION_3D)
            var expected_leg := animation.rotation_track_interpolate(leg_track, animation.length * sample_index / 12.0)
            _check(skeleton.get_bone_pose_rotation(skeleton.find_bone("mixamorigRightUpLeg")).angle_to(expected_leg) < 0.005, "Preview did not apply sampled clip")
            for bone in range(skeleton.get_bone_count()):
                var pose := skeleton.get_bone_global_pose(bone)
                _check(pose.origin.is_finite() and pose.basis.is_finite(), "Non-finite bone transform")
                _check(skeleton.get_bone_pose_scale(bone).distance_to(Vector3.ONE) < 0.001, "Bone scale changed")
                if bone != 0:
                    _check(skeleton.get_bone_pose_position(bone).distance_to(skeleton.get_bone_rest(bone).origin) < 0.001, "Bone length/translation changed")
            _check(float(scene.call("grip_error", "Right")) < 0.025, "Right hand detached from rifle")
            _check(float(scene.call("grip_error", "Left")) < 0.025, "Left hand detached from rifle: %s sample=%s error=%.3fm" % [clip, sample_index, float(scene.call("grip_error", "Left"))])
            if sample_index % 4 == 0:
                _check_skin_bounds(skeleton)
    scene.call("resume_preview")
    var right := InputEventMouseButton.new()
    right.button_index = MOUSE_BUTTON_RIGHT
    right.pressed = true
    scene.call("_unhandled_input", right)
    for frame in range(30):
        _advance_checked(scene, 1.0 / 60.0)
    _check(scene.call("current_state") == "Mira", "Right mouse must enter aim")
    var left := InputEventMouseButton.new()
    left.button_index = MOUSE_BUTTON_LEFT
    left.pressed = true
    scene.call("_unhandled_input", left)
    _advance_checked(scene, 0.10)
    _check(scene.call("current_state") == "Disparo", "Left mouse while aiming must trigger fire")
    for frame in range(80):
        _advance_checked(scene, 1.0 / 60.0)
    _check(scene.call("current_state") == "Mira", "Fire must return to aim")
    right.pressed = false
    scene.call("_unhandled_input", right)
    for frame in range(30):
        _advance_checked(scene, 1.0 / 60.0)
    _check(scene.call("current_state") == "Normal", "Releasing right mouse must restore normal stance")
    scene.call("_unhandled_input", left)
    _advance_checked(scene, 0.1)
    _check(scene.call("current_state") == "Normal", "Firing without aiming must be ignored")
    right.pressed = true
    scene.call("_unhandled_input", right)
    for frame in range(30):
        _advance_checked(scene, 1.0 / 60.0)
    scene.call("_unhandled_input", left)
    _advance_checked(scene, 0.1)
    right.pressed = false
    scene.call("_unhandled_input", right)
    for frame in range(30):
        _advance_checked(scene, 1.0 / 60.0)
    _check(scene.call("current_state") == "Normal", "Releasing aim during fire must exit safely")
    scene.queue_free()
    await process_frame
    for failure in failures.slice(0, 15):
        printerr(failure)
    print("JAIME SWAT: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
    quit(0 if failures.is_empty() else 1)

func _advance_checked(scene: Node3D, delta: float) -> void:
    scene.call("advance_preview", delta)
    var skeleton: Skeleton3D = scene.get("skeleton")
    for side in ["Right", "Left"]:
        _check(float(scene.call("grip_error", side)) < 0.025, "Grip lost during transition: " + side)
        var bone := skeleton.find_bone("mixamorig" + side + "Arm")
        var rotation := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
        if previous_arms.has(side):
            _check(rotation.angle_to(previous_arms[side]) < maxf(0.5, delta * 30.0), "Arm flips during transition: " + side)
        previous_arms[side] = rotation

func _check_skin_bounds(skeleton: Skeleton3D) -> void:
    # CPU skinning of the original vertices catches gross deformation/spikes,
    # beyond checking that the bone transforms themselves remain valid.
    var mesh := skeleton.get_node("geometry_0") as MeshInstance3D
    var matrices: Array[Transform3D] = []
    for binding in range(mesh.skin.get_bind_count()):
        var bone := skeleton.find_bone(mesh.skin.get_bind_name(binding))
        if bone < 0:
            bone = mesh.skin.get_bind_bone(binding)
        _check(bone >= 0, "Skin bind does not map to target skeleton")
        matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(binding))
    var low := Vector3(INF, INF, INF)
    var high := Vector3(-INF, -INF, -INF)
    for surface in range(mesh.mesh.get_surface_count()):
        var arrays := mesh.mesh.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        var influences := bones.size() / vertices.size()
        for vertex in range(vertices.size()):
            var point := Vector3.ZERO
            for influence in range(influences):
                var index: int = vertex * influences + influence
                point += (matrices[bones[index]] * vertices[vertex]) * weights[index]
            point = skeleton.to_global(point)
            _check(point.is_finite(), "Skinned vertex became non-finite")
            low = low.min(point)
            high = high.max(point)
    var extent := high - low
    _check(low.y > -0.07 and high.y < 2.2 and extent.y > 1.3, "Skinned body height/ground contact invalid")
    _check(extent.x < 1.5 and extent.z < 1.5, "Skinned body has extreme deformation")
