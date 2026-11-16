extends Node3D
## Visual adapter only: physics, camera, input, weapons and combat stay in player.gd.
const PoseDriver = preload("res://scripts/avatar/avatar_controller.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const Locomotion = preload("res://scripts/characters/locomotion_library.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const DOWNLOAD_WALK := "res://assets/personagens/jaime/retargeted/walk_forward_download.tres"
const DOWNLOAD_FIRE := "res://assets/personagens/jaime/retargeted/fire_download.tres"
const DOWNLOAD_RUN := "res://assets/personagens/jaime/retargeted/run_forward_download.tres"
const DOWNLOAD_SPRINT := "res://assets/personagens/jaime/retargeted/sprint_forward_download.tres"
@export_range(0.12, 0.25, 0.01) var pose_transition := 0.18
var bound_weapon: Node3D
var aim_pitch := 0.0
var pose_offset := Vector3.ZERO
var pose_pitch := 0.0
var pose_initialized := false
var reload_pose := false
var skeleton: Skeleton3D
var pose_driver: Node3D
var weapon_mount: Node3D
var ready_ok := false
var weapon_id := "pistol"
var weapon_scale := 1.0
var aim_weight := 0.0
var aiming := false
var playback: AnimationNodeStateMachinePlayback
var animation_tree: AnimationTree
var right_grip := Vector3.ZERO
var left_grip := Vector3.ZERO
var armed := true
var upper_weight := 1.0
var locomotion_weight := 0.0
var locomotion_position := Vector2.ZERO
var locomotion_clock := 0.0
var foot_plants := {}

func _ready() -> void:
    skeleton = get_node_or_null("Soldier/Node/Skeleton3D") as Skeleton3D
    if skeleton == null or skeleton.get_bone_count() != 52:
        return
    var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
    if player == null:
        return
    for clip in ["normal", "aim", "fire"]:
        if not player.has_animation(clip):
            return
    # Imported resources may be shared by previews and multiple characters.
    var library := player.get_animation_library("").duplicate() as AnimationLibrary
    # Keep the user's imported takes as separate derivatives, then substitute
    # them only in this character instance's private animation library.
    var imported_fire := load(DOWNLOAD_FIRE) as Animation
    if imported_fire != null:
        library.remove_animation("fire")
        library.add_animation("fire", imported_fire)
    var movement := Locomotion.load_library()
    var movement_copy := movement.duplicate() as AnimationLibrary
    var imported_walk := load(DOWNLOAD_WALK) as Animation
    if imported_walk != null:
        movement_copy.remove_animation("walk_forward")
        movement_copy.add_animation("walk_forward", _prepare_locomotion_clip(imported_walk))
    var imported_run := load(DOWNLOAD_RUN) as Animation
    if imported_run != null:
        movement_copy.remove_animation("run_forward")
        movement_copy.add_animation("run_forward", _prepare_locomotion_clip(imported_run))
    var imported_sprint := load(DOWNLOAD_SPRINT) as Animation
    if imported_sprint != null:
        movement_copy.add_animation("sprint_forward", _prepare_locomotion_clip(imported_sprint))
    for clip in movement_copy.get_animation_list():
        if library.has_animation(clip): library.remove_animation(clip)
        library.add_animation(clip,movement_copy.get_animation(clip))
    player.remove_animation_library("")
    player.add_animation_library("",library)
    # Apply looping before the AnimationTree starts evaluating this library.
    CharacterRegistry.configure_locomotion_loops(self)
    var imported := $Soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if imported:
        imported.active = false
    pose_driver = PoseDriver.new()
    pose_driver.name = "PoseReference"
    pose_driver.visible = false
    pose_driver.scale = Vector3.ONE * (1.8 / 2.09)
    add_child(pose_driver)
    weapon_mount = Node3D.new()
    weapon_mount.name = "WeaponMount"
    skeleton.add_child(weapon_mount)
    for side in ["Right", "Left"]:
        var marker := Marker3D.new()
        marker.name = side + "Grip"
        weapon_mount.add_child(marker)
    _build_animation_tree()
    configure_weapon("pistol", 1.0)
    ready_ok = true
    animate(1.0 / 60.0, 0.0, false, false, false, false, false)

func _prepare_locomotion_clip(source: Animation) -> Animation:
    # Stretch each gait cycle so it lasts longer, and loop it while movement continues.
    var clip := source.duplicate() as Animation
    var duration_scale := 1.5
    for track in clip.get_track_count():
        for key in clip.track_get_key_count(track):
            clip.track_set_key_time(track, key, clip.track_get_key_time(track, key) * duration_scale)
    clip.length *= duration_scale
    clip.loop_mode = Animation.LOOP_LINEAR
    return clip

func is_visual_ready() -> bool:
    return ready_ok

func _build_animation_tree() -> void:
    animation_tree = $AnimationTree
    var machine := AnimationNodeStateMachine.new()
    for entry in [["Normal", "normal"], ["Mira", "aim"], ["Disparo", "fire"]]:
        var node := AnimationNodeAnimation.new()
        node.animation = entry[1]
        machine.add_node(entry[0], node)
    for pair in [["Start", "Normal"], ["Normal", "Mira"], ["Mira", "Normal"], ["Mira", "Disparo"], ["Disparo", "Mira"], ["Disparo", "Normal"]]:
        var transition := AnimationNodeStateMachineTransition.new()
        transition.xfade_time = 0.12 if pair[1] == "Disparo" else 0.2
        if pair[0] == "Start":
            transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
        elif pair == ["Disparo", "Mira"]:
            transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
            transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
        machine.add_transition(pair[0], pair[1], transition)
    var tree := AnimationNodeBlendTree.new()
    tree.add_node("Locomotion",Locomotion.build_blend_space())
    tree.add_node("GaitRate",AnimationNodeTimeScale.new())
    tree.add_node("Tactical",machine)
    var upper := AnimationNodeBlend2.new()
    upper.filter_enabled = true
    for bone in skeleton.get_bone_count():
        var name := String(skeleton.get_bone_name(bone))
        if "Spine" in name or "Neck" in name or "Head" in name or "Shoulder" in name or "Arm" in name or "Hand" in name:
            upper.set_filter_path(NodePath("Soldier/Node/Skeleton3D:"+name),true)
    tree.add_node("Upper",upper)
    tree.connect_node("GaitRate",0,"Locomotion")
    tree.connect_node("Upper",0,"GaitRate")
    tree.connect_node("Upper",1,"Tactical")
    tree.connect_node("output",0,"Upper")
    animation_tree.tree_root = tree
    animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    animation_tree.active = true
    animation_tree.set("parameters/Upper/blend_amount",upper_weight)
    playback = animation_tree.get("parameters/Tactical/playback")
    playback.start("Normal")

func configure_weapon(id: String, model_scale: float = 1.0) -> void:
    weapon_id = id
    if weapon_mount:
        weapon_mount.set_meta("weapon_id", id)
    weapon_scale = model_scale
    if pose_driver:
        pose_driver.configure_weapon(id, model_scale)
    if weapon_mount == null:
        return
    if id == "pistol":
        right_grip = Vector3(0.035, -0.15, -0.08)
        left_grip = Vector3(-0.065, -0.14, -0.09)
    else:
        right_grip = Vector3(0.035, -0.18, -0.21) * model_scale
        var support := -0.6355 if id == "sniper" else (-0.55 if id == "rifle" else (-0.48 if id == "shotgun" else -0.45))
        left_grip = Vector3(-0.05, -0.035 if id == "sniper" else -0.14, support) * model_scale
    weapon_mount.get_node("RightGrip").position = right_grip
    weapon_mount.get_node("LeftGrip").position = left_grip
    if is_instance_valid(bound_weapon):
        refresh_weapon_grip()

func set_aim_pitch(value: float) -> void:
    aim_pitch = value

func set_armed(value: bool) -> void:
    armed = value
    # Weapon ownership and visibility belong to player.gd; this adapter only
    # releases the tactical layer and its hand solvers.

func bind_weapon(model: Node3D) -> void:
    bound_weapon = model
    weapon_id = str(model.get_meta("weapon_id", weapon_id))
    weapon_mount.set_meta("weapon_id", weapon_id)
    pose_initialized = false
    refresh_weapon_grip()

func _update_contact_targets() -> void:
    for side in ["Right", "Left"]:
        var source_name: String = "ReloadGrip" if side == "Left" and reload_pose else side + "Grip"
        var contact := bound_weapon.get_node_or_null(source_name) as Marker3D
        if contact:
            weapon_mount.get_node(side + "Grip").position = weapon_mount.to_local(contact.global_position)

func refresh_weapon_grip() -> void:
    if not ready_ok or not armed or not is_instance_valid(bound_weapon):
        return
    # Project the socket into both arms' reachable region; never stretch bones.
    for iteration in range(8):
        _update_contact_targets()
        var moved := false
        for side in ["Right", "Left"]:
            var upper := skeleton.find_bone("mixamorig" + side + "Arm")
            var lower := skeleton.find_bone("mixamorig" + side + "ForeArm")
            var hand := skeleton.find_bone("mixamorig" + side + "Hand")
            var origin := skeleton.get_bone_global_pose(upper).origin
            var target := Grip.wrist_target(skeleton, weapon_mount, side)
            var reach := skeleton.get_bone_rest(lower).origin.length() + skeleton.get_bone_rest(hand).origin.length() - 0.002
            if origin.distance_to(target) > reach:
                weapon_mount.position -= (target-origin).normalized() * (origin.distance_to(target)-reach)
                moved = true
        if not moved:
            break
    _update_contact_targets()
    for side in ["Right", "Left"]:
        Grip.solve(skeleton, weapon_mount, side, true)

func notify_shot() -> void:
    if ready_ok and armed and aiming and String(playback.get_current_node()) != "Disparo":
        playback.travel("Disparo")

func animate(delta: float, move_amount: float, running: bool, crouched: bool, is_aiming: bool, airborne: bool, reloading: bool, movement_direction: Vector2 = Vector2(0, -1), planar_velocity: Vector3 = Vector3.ZERO) -> void:
    if not ready_ok:
        return
    if aiming != is_aiming:
        aiming = is_aiming
        playback.travel("Mira" if aiming else "Normal")
    var speed := Vector2(planar_velocity.x,planar_velocity.z).length()
    var moving := speed>0.08 and not crouched and not airborne
    var transition_blend := 1.0-exp(-delta*3.0/pose_transition)
    var radius := clampf(speed/10.0,0,0.5) if speed<=5.0 else clampf(0.5+(speed-5.0)/6.0,0.5,1.0)
    var forward_sprint := running and not crouched and not aiming and movement_direction.y < -0.75 and absf(movement_direction.x) < 0.35
    if forward_sprint:
        radius = 1.15
    var desired := Vector2(planar_velocity.x,planar_velocity.z).normalized()*radius if moving else Vector2.ZERO
    locomotion_position = locomotion_position.lerp(desired,transition_blend)
    locomotion_weight = lerpf(locomotion_weight,1.0 if moving else 0.0,transition_blend)
    upper_weight = lerpf(upper_weight,1.0 if armed else 0.0,transition_blend)
    var rate := clampf(speed/5.0,0.0,1.0) if speed<5.0 else 1.0
    animation_tree.set("parameters/Locomotion/blend_position",locomotion_position)
    animation_tree.set("parameters/GaitRate/scale",rate)
    animation_tree.set("parameters/Upper/blend_amount",upper_weight)
    locomotion_clock += delta*rate
    animation_tree.advance(delta)
    aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 5.0)
    # Procedural poses are the fallback for idle/crouch/air, and fade out of the
    # legs as the recorded gait takes over. They never replace moving FK feet.
    if locomotion_weight<0.999:
        pose_driver.animate(delta, move_amount, running, crouched, aiming, airborne, reloading, movement_direction, pose_driver.basis.inverse() * planar_velocity)
    var hips := skeleton.find_bone("mixamorigHips")
    var drop: float = (pose_driver.hips.position.y - 0.96) * pose_driver.scale.y / $Soldier.scale.y
    skeleton.set_bone_pose_position(hips,(skeleton.get_bone_rest(hips).origin+Vector3.UP*drop).lerp(skeleton.get_bone_pose_position(hips),locomotion_weight))
    var chest_bone := skeleton.find_bone("mixamorigSpine2")
    var lean: float = -pose_driver.torso.rotation.x
    skeleton.set_bone_pose_rotation(chest_bone, skeleton.get_bone_pose_rotation(chest_bone) * Quaternion(Vector3.RIGHT, lean*(1.0-locomotion_weight)))
    if locomotion_weight<0.999:
        for side in ["Left", "Right"]:
            var ids := [skeleton.find_bone("mixamorig"+side+"UpLeg"),skeleton.find_bone("mixamorig"+side+"Leg"),skeleton.find_bone("mixamorig"+side+"Foot")]
            var fk := []
            for bone in ids: fk.append(skeleton.get_bone_pose_rotation(bone))
            var foot := pose_driver.get_node("Hips/" + side + "Leg/Knee/Ankle") as Node3D
            var target := skeleton.to_local(foot.global_position + global_basis.y.normalized() * (0.062 * global_basis.get_scale().y))
            var basis := skeleton.global_basis.orthonormalized().inverse() * foot.global_basis.orthonormalized() * Basis(Vector3.UP, PI)
            _solve_leg(side, target, basis)
            for index in ids.size(): skeleton.set_bone_pose_rotation(ids[index],skeleton.get_bone_pose_rotation(ids[index]).slerp(fk[index],locomotion_weight))
    if moving:
        _ground_recorded_feet(delta,speed)
    else:
        foot_plants.clear()
    _stabilize_spine_posture(running, crouched, aiming, movement_direction)
    if not armed:
        return
    var chest := skeleton.get_bone_global_pose(chest_bone)
    if is_instance_valid(bound_weapon):
        reload_pose = reloading
        var state := "aim" if aiming else ("reload" if reloading else ("crouch" if crouched else ("run" if running else ("walk" if move_amount > 0.1 else "rest"))))
        var pose := WeaponProportions.stance(weapon_id, state)
        var offset: Vector3 = pose["offset"]
        var desired_pitch: float = pose["pitch"] + (aim_pitch if aiming else 0.0)
        var blend := 1.0 - exp(-delta * 3.0 / pose_transition)
        pose_offset = pose_offset.lerp(offset, blend) if pose_initialized else offset
        pose_pitch = lerpf(pose_pitch, desired_pitch, blend) if pose_initialized else desired_pitch
        pose_initialized = true
        var local_offset: Vector3 = Vector3(-pose_offset.x, pose_offset.y, pose_offset.z) / $Soldier.scale.y
        var basis := Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, pose_pitch)
        weapon_mount.transform = Transform3D(basis.scaled(Vector3.ONE*0.48), chest.origin + local_offset)
        refresh_weapon_grip()
        return
    var long_weapon := weapon_id != "pistol"
    var low := Vector3(-0.01, 0.09, -0.015) if long_weapon else Vector3(0.03, 0.08, 0.10)
    var high := Vector3(-0.025, 0.14, 0.005) if long_weapon else Vector3(0.03, 0.12, 0.12)
    var pitch := lerpf(0.35 if long_weapon else 0.05, 0.0, aim_weight)
    var orientation := Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, PI)
    weapon_mount.transform = chest * Transform3D(orientation.scaled(Vector3.ONE * 0.48), low.lerp(high, aim_weight))
    weapon_mount.get_node("LeftGrip").position = Vector3(-0.05, -0.25, -0.35) * weapon_scale if reloading else left_grip
    for side in ["Right", "Left"]:
        Grip.solve(skeleton, weapon_mount, side)

func _stabilize_spine_posture(running: bool, crouched: bool, is_aiming: bool, movement_direction: Vector2) -> void:
    # The retargeted aim clip contains a strong positive local-X spine bend.
    # Clamp it in every state so idle/aim transitions cannot restore the arch.
    var spine_names := ["mixamorigSpine", "mixamorigSpine1", "mixamorigSpine2"]
    var run_weights := [0.20, 0.32, 0.48]
    var run_lean := 0.075 if running and not crouched and not is_aiming else 0.0
    var lateral_lean := clampf(-movement_direction.x, -1.0, 1.0) * 0.025 if running and not crouched and not is_aiming else 0.0
    for index in spine_names.size():
        var bone := skeleton.find_bone(spine_names[index])
        if bone < 0:
            continue
        var pose := skeleton.get_bone_pose_rotation(bone)
        var euler := pose.get_euler()
        # Retain a modest forward bend for crouch while limiting backward
        # extension in idle, walk, run, aim and fire.
        euler.x = clampf(euler.x, -0.18 if crouched else -0.12, 0.08)
        var corrected := Basis.from_euler(euler).get_rotation_quaternion()
        var weight: float = run_weights[index]
        var run_pose := Quaternion(Vector3.RIGHT, -run_lean * weight) * Quaternion(Vector3.FORWARD, lateral_lean * weight)
        skeleton.set_bone_pose_rotation(bone, (corrected * run_pose).normalized())

func _ground_recorded_feet(delta: float, speed: float) -> void:
    var body := get_parent()
    while body != null and not body is CharacterBody3D: body = body.get_parent()
    var run_mix := clampf((speed-5.0)/3.0,0,1)
    var period := lerpf(5.0/6.0,17.0/30.0,run_mix)
    var world_scale := global_basis.get_scale().y
    var pelvis_adjusted := false
    for side in ["Left","Right"]:
        var foot := skeleton.find_bone("mixamorig"+side+"Foot")
        var toe := skeleton.find_bone("mixamorig"+side+"ToeBase")
        var fk := skeleton.get_bone_global_pose(foot)
        var world_foot := skeleton.to_global(fk.origin)
        var world_toe := skeleton.to_global(skeleton.get_bone_global_pose(toe).origin)
        var query := PhysicsRayQueryParameters3D.create(world_foot+Vector3.UP*0.35,world_foot-Vector3.UP*0.65)
        if body is CharacterBody3D:
            query.exclude = [body.get_rid()]
            query.collision_mask = body.collision_mask
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP)<0.7:
            foot_plants.erase(side)
            continue
        if not pelvis_adjusted:
            # A small supported pelvis reserve keeps contact targets reachable
            # without changing leg lengths or the controller's collision body.
            var hips := skeleton.find_bone("mixamorigHips")
            skeleton.set_bone_pose_position(hips,skeleton.get_bone_pose_position(hips)-skeleton.global_basis.inverse()*(Vector3.UP*0.035*world_scale))
            pelvis_adjusted = true
        fk = skeleton.get_bone_global_pose(foot)
        world_foot = skeleton.to_global(fk.origin)
        world_toe = skeleton.to_global(skeleton.get_bone_global_pose(toe).origin)
        var normal: Vector3 = hit.normal
        var ground: Vector3 = hit.position
        var phase := fposmod(locomotion_clock/period+(0.5 if side=="Right" else 0.0),1.0)
        var stance := phase<lerpf(0.42,0.26,run_mix)
        var world_basis := skeleton.global_basis.orthonormalized()*fk.basis.orthonormalized()
        if stance: world_basis = Basis(Quaternion(Vector3.UP,normal))*Basis(Vector3.UP,world_basis.get_euler().y)
        var toe_offset := world_basis*skeleton.get_bone_rest(toe).origin*skeleton.global_basis.get_scale().y
        var clearance := maxf(0.025*world_scale,-toe_offset.y)+0.018*world_scale
        var floor_y := ground.y+clearance
        var target := world_foot
        target.y = maxf(target.y,floor_y)
        if stance:
            # Pin in world space only while this FK stance remains reachable.
            # At 5/8m/s a recording's stride cannot cancel all controller travel;
            # release a bounded plant rather than stretching or dragging a leg.
            if not foot_plants.has(side):
                foot_plants[side] = {"anchor":Vector3(world_foot.x,floor_y,world_foot.z),"age":0.0,"released":false}
            var plant: Dictionary = foot_plants[side]
            plant.age += delta
            var anchor: Vector3 = plant.anchor
            var hip := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig"+side+"UpLeg")).origin)
            var leg_length := (skeleton.get_bone_rest(skeleton.find_bone("mixamorig"+side+"Leg")).origin.length()+skeleton.get_bone_rest(foot).origin.length())*skeleton.global_basis.get_scale().y
            if anchor.distance_to(world_foot)>0.26*world_scale or hip.distance_to(anchor)>leg_length*0.999:
                plant.released = true
            if not plant.released:
                target = anchor
                target.y = floor_y
        else:
            foot_plants.erase(side)
        _solve_leg(side,skeleton.to_local(target),skeleton.global_basis.orthonormalized().inverse()*world_basis)

func _solve_leg(side: String, target: Vector3, foot_basis: Basis) -> void:
    var upper := skeleton.find_bone("mixamorig" + side + "UpLeg")
    var knee := skeleton.find_bone("mixamorig" + side + "Leg")
    var foot := skeleton.find_bone("mixamorig" + side + "Foot")
    var hip := skeleton.get_bone_global_pose(upper)
    var knee_pose := skeleton.get_bone_global_pose(knee)
    var a := skeleton.get_bone_rest(knee).origin.length()
    var b := skeleton.get_bone_rest(foot).origin.length()
    var direction := (target - hip.origin).normalized()
    var distance := clampf(hip.origin.distance_to(target), 0.001, a + b - 0.0001)
    var pole := Vector3.BACK
    var bend := (pole - direction * pole.dot(direction)).normalized()
    var along := (a * a - b * b + distance * distance) / (2.0 * distance)
    var desired_knee := hip.origin + direction * along + bend * sqrt(maxf(0.0, a * a - along * along))
    var old_direction := (hip.basis * skeleton.get_bone_rest(knee).origin).normalized()
    _set_rotation(upper, Basis(Quaternion(old_direction, (desired_knee - hip.origin).normalized())) * hip.basis)
    knee_pose = skeleton.get_bone_global_pose(knee)
    old_direction = (knee_pose.basis * skeleton.get_bone_rest(foot).origin).normalized()
    var reachable := hip.origin + direction * distance
    _set_rotation(knee, Basis(Quaternion(old_direction, (reachable - knee_pose.origin).normalized())) * knee_pose.basis)
    _set_rotation(foot, foot_basis)

func _set_rotation(bone: int, basis: Basis) -> void:
    var parent := skeleton.get_bone_parent(bone)
    skeleton.set_bone_pose_rotation(bone, (skeleton.get_bone_global_pose(parent).basis.inverse() * basis).orthonormalized().get_rotation_quaternion().normalized())

func grip_error(side: String) -> float:
    if is_instance_valid(bound_weapon):
        return Grip.palm_position(skeleton, side).distance_to((weapon_mount.get_node(side + "Grip") as Marker3D).global_position)
    var hand := skeleton.find_bone("mixamorig" + side + "Hand")
    return skeleton.to_global(skeleton.get_bone_global_pose(hand).origin).distance_to((weapon_mount.get_node(side + "Grip") as Marker3D).global_position)
