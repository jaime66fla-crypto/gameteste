extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(ok: bool, message: String) -> void:
    if not ok: failures.append(message)
func _run() -> void:
    var visual = load("res://scenes/characters/jaime_swat.tscn").instantiate()
    root.add_child(visual)
    await process_frame
    if not visual.has_method("set_armed"):
        printerr("SWAT LOCOMOTION RUNTIME: missing armed API and layered locomotion")
        visual.free()
        quit(1)
        return
    _check(visual.is_visual_ready(),"Visual initialization")
    var player: AnimationPlayer = visual.get_node("AnimationPlayer")
    _check(player.has_animation("walk_forward") and player.has_animation("run_backward_right"),"Locomotion library merged")
    var original = load("res://scenes/characters/jaime_swat.tscn").instantiate()
    _check(original.get_node("AnimationPlayer").get_animation_library("") != player.get_animation_library(""),"Default library must be scene-local")
    original.free()
    var sk: Skeleton3D = visual.skeleton
    var upper: AnimationNodeBlend2 = (visual.animation_tree.tree_root as AnimationNodeBlendTree).get_node("Upper")
    _check(not upper.is_path_filtered(NodePath("Soldier/Node/Skeleton3D:mixamorigHips")),"Upper layer must preserve pelvis")
    _check(not upper.is_path_filtered(NodePath("Soldier/Node/Skeleton3D:mixamorigLeftUpLeg")),"Upper layer must preserve legs")
    _check(upper.is_path_filtered(NodePath("Soldier/Node/Skeleton3D:mixamorigSpine")),"Upper layer must include spine")
    visual.set_armed(false)
    var poses := []
    for direction in [Vector2(0,-1),Vector2(1,-1),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(-1,1),Vector2(-1,0),Vector2(-1,-1)]:
        for frame in 40:
            visual.animate(1.0/60.0,1.0,false,false,false,false,false,direction,Vector3(direction.normalized().x,0,direction.normalized().y)*5)
        var expected: Vector2 = direction.normalized()*0.5
        _check((visual.animation_tree.get("parameters/Locomotion/blend_position") as Vector2).distance_to(expected)<0.03,"Directional blend "+str(direction))
        poses.append(sk.get_bone_pose_rotation(sk.find_bone("mixamorigLeftUpLeg")))
    _check(poses[0].angle_to(poses[4])>0.05,"Forward/backward source poses must differ")
    _check(float(visual.animation_tree.get("parameters/Upper/blend_amount"))<0.01,"Unarmed disables tactical upper body")
    visual.set_armed(true)
    for frame in 45: visual.animate(1.0/60.0,1.0,true,false,true,false,false,Vector2(1,0),Vector3(8,0,0))
    _check(float(visual.animation_tree.get("parameters/Upper/blend_amount"))>0.99,"Armed enables filtered upper body")
    _check((visual.animation_tree.get("parameters/Locomotion/blend_position") as Vector2).distance_to(Vector2(1,0))<0.03,"Run radius")
    var before: Quaternion = sk.get_bone_pose_rotation(sk.find_bone("mixamorigLeftUpLeg"))
    visual.animate(0.12,1.0,true,false,true,false,false,Vector2(1,0),Vector3(8,0,0))
    _check(before.angle_to(sk.get_bone_pose_rotation(sk.find_bone("mixamorigLeftUpLeg")))>0.03,"Real source clip advances")
    for frame in 90: visual.animate(1.0/60.0,0,false,false,false,false,false,Vector2.ZERO,Vector3.ZERO)
    _check((visual.animation_tree.get("parameters/Locomotion/blend_position") as Vector2).length()<0.01,"Stopping settles blend")
    for bone in sk.get_bone_count(): _check(sk.get_bone_global_pose(bone).is_finite(),"Finite transform")
    # Physical support is sampled below the recorded FK feet. Translate the
    # visual at the real controller's 5/8m/s rates; a live world plant must stay
    # stationary while active, and both toes must stay above the floor.
    var floor := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(200,1,200)
    shape.shape = box
    floor.add_child(shape)
    floor.position.y = -0.5
    root.add_child(floor)
    await physics_frame
    var maximum_slip := 0.0
    var plant_samples := 0
    var minimum_toe_y := INF
    for speed in [5.0,8.0]:
        for direction in [Vector2(0,-1),Vector2(1,-1),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(-1,1),Vector2(-1,0),Vector2(-1,-1)]:
            visual.position = Vector3.ZERO
            visual.foot_plants.clear()
            var previous := {}
            var velocity: Vector3 = Vector3(direction.normalized().x,0,direction.normalized().y)*speed
            for frame in 120:
                visual.position += velocity/60.0
                visual.animate(1.0/60.0,1.0,speed>5,false,false,false,false,direction,velocity)
                for side in ["Left","Right"]:
                    var point := sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig"+side+"Foot")).origin)
                    var toe := sk.to_global(sk.get_bone_global_pose(sk.find_bone("mixamorig"+side+"ToeBase")).origin)
                    minimum_toe_y = minf(minimum_toe_y,toe.y)
                    var pinned: bool = visual.foot_plants.has(side) and not visual.foot_plants[side].released
                    if pinned and previous.has(side) and previous[side].pinned:
                        maximum_slip = maxf(maximum_slip,Vector2(point.x,point.z).distance_to(Vector2(previous[side].point.x,previous[side].point.z)))
                        plant_samples += 1
                    previous[side] = {"point":point,"pinned":pinned}
    _check(plant_samples>8,"World-space plants must actually engage")
    _check(maximum_slip<0.015,"Active plant slip exceeds 15mm: "+str(maximum_slip))
    _check(minimum_toe_y>=-0.035,"Recorded feet penetrate physical support: "+str(minimum_toe_y))
    print("RUNTIME CONTACT samples=",plant_samples," maximum_active_slip_m=",maximum_slip," minimum_toe_y=",minimum_toe_y)
    floor.free()
    visual.free()
    for message in failures: printerr(message)
    print("SWAT LOCOMOTION RUNTIME: ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
    quit(0 if failures.is_empty() else 1)

