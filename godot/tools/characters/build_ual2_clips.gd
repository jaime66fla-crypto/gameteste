extends SceneTree
## Retargets every clip of Quaternius' Universal Animation Library 2 (CC0,
## assets/personagens/ual2/UAL2_Standard.glb, UE-style rig) onto the Ch31
## Mixamo rig ("mixamorig9_"), saved as assets/personagens/ual2/clips/<name>.tres.
## downloaded_avatar.gd remaps them to any other Mixamo model (Remy, ...).
##
## Rest-frame retarget (same idea as build_unarmed_locomotion.gd): each target
## bone copies the source bone's world rotation change, measured against the
## direction to its main child, so different rest poses do not bend limbs.
## Differences from that tool:
## - the source is turned about Y so its facing matches the target's (the UAL
##   root bone is Z-up and may face another axis);
## - the Hips height follows the source pelvis (scaled by leg length), so
##   jumps, slides, lying down and climbing keep their vertical motion;
## - fingers are mapped too (UAL has 4 segments, Mixamo 3).
## Usage (from the repo root):
##   godot --headless --path godot --script res://tools/characters/build_ual2_clips.gd
const SOURCE := "res://assets/personagens/ual2/UAL2_Standard.glb"
const TARGET_MODEL := "res://assets/personagens/downloaded/avatar.fbx"
const OUT_DIR := "res://assets/personagens/ual2/clips/"
const TARGET_ROOT := "Skeleton3D:"
const PREFIX := "mixamorig9_"
const FPS := 30.0
## Clips that cycle (the rest play once).
const LOOPING := ["Idle_FoldArms", "Idle_Lantern", "Idle_No", "Idle_Rail", "Idle_Rail_Call", "Idle_Shield", "Idle_TalkingPhone", "Yes", "NinjaJump_Idle", "Slide", "Walk_Carry", "Zombie_Idle", "Zombie_Walk_Fwd", "Farm_Watering"]
const SKIP := ["A_TPose"]
const BONE_MAP := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Pinky": "pinky"}

var align := Basis.IDENTITY # turns source world space so it faces like the target

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var target_model := (load(TARGET_MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(target_model)
	var target := target_model.find_child("Skeleton3D", true, false) as Skeleton3D
	var source_model := (load(SOURCE) as PackedScene).instantiate() as Node3D
	root.add_child(source_model)
	var source := source_model.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if target == null or source == null or player == null:
		printerr("UAL2: modelo ou biblioteca não carregou")
		quit(1)
		return
	align = _facing_alignment(source, target)
	print("UAL2: alinhamento de frente ", rad_to_deg(align.get_euler().y), "°")
	var failed := false
	var count := 0
	for clip_name in player.get_animation_list():
		if String(clip_name) in SKIP or String(clip_name) == "RESET":
			continue
		failed = not _retarget(player, String(clip_name), source, target) or failed
		count += 1
	source_model.free()
	target_model.free()
	print("UAL2 CLIPS: %d  %s" % [count, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

## Horizontal facing of a skeleton from the hip line (feet splay outwards and
## would tilt the estimate): forward = lateral (left hip -> right hip) x up,
## checked against the toes so it is not reversed.
static func forward_of(skeleton: Skeleton3D, left_hip: String, right_hip: String, foot: String, toe: String) -> Vector3:
	var lateral := skeleton.get_bone_global_rest(skeleton.find_bone(right_hip)).origin - skeleton.get_bone_global_rest(skeleton.find_bone(left_hip)).origin
	lateral.y = 0.0
	var forward := lateral.normalized().cross(Vector3.UP)
	var toes := skeleton.get_bone_global_rest(skeleton.find_bone(toe)).origin - skeleton.get_bone_global_rest(skeleton.find_bone(foot)).origin
	return -forward if forward.dot(toes) < 0.0 else forward

func _facing_alignment(source: Skeleton3D, target: Skeleton3D) -> Basis:
	var s := forward_of(source, "thigh_l", "thigh_r", "foot_l", "ball_l")
	var t := forward_of(target, PREFIX + "LeftUpLeg", PREFIX + "RightUpLeg", PREFIX + "LeftFoot", PREFIX + "LeftToeBase")
	return Basis(Vector3.UP, atan2(s.cross(t).y, s.dot(t)))

func _source_name(target_name: String) -> String:
	var suffix := target_name.trim_prefix(PREFIX)
	if BONE_MAP.has(suffix):
		return BONE_MAP[suffix]
	for side in ["Left", "Right"]:
		for finger in FINGERS:
			for index in range(1, 4):
				if suffix == "%sHand%s%d" % [side, finger, index]:
					return "%s_0%d_%s" % [FINGERS[finger], index, "l" if side == "Left" else "r"]
	return ""

## The target bone's main child (spine chain, middle finger for hands).
func _target_child(target: Skeleton3D, bone: int) -> int:
	var name := String(target.get_bone_name(bone))
	var preferred := ""
	if name.ends_with("_Hips"):
		preferred = PREFIX + "Spine"
	elif name.ends_with("_Spine2"):
		preferred = PREFIX + "Neck"
	elif name.ends_with("Hand"):
		preferred = name + "Middle1"
	if preferred != "" and target.find_bone(preferred) >= 0:
		return target.find_bone(preferred)
	var children := target.get_bone_children(bone)
	return children[0] if not children.is_empty() else -1

func _mapped_child(target: Skeleton3D, source: Skeleton3D, bone: int) -> int:
	var child := _target_child(target, bone)
	while child >= 0:
		var mapped := source.find_bone(_source_name(String(target.get_bone_name(child))))
		if mapped >= 0:
			return mapped
		child = _target_child(target, child)
	return -1

## Source rest frames and pose deltas are read through `align` (source turned to face like the target).
func _global_rest(skeleton: Skeleton3D, bone: int, is_source: bool) -> Transform3D:
	var rest := skeleton.get_bone_global_rest(bone)
	return Transform3D(align * rest.basis, align * rest.origin) if is_source else rest

func _frame(skeleton: Skeleton3D, bone: int, child: int, is_source: bool) -> Basis:
	var origin := _global_rest(skeleton, bone, is_source).origin
	var direction := Vector3.ZERO
	if child >= 0:
		direction = _global_rest(skeleton, child, is_source).origin - origin
	if child < 0 or direction.length_squared() < 0.00000001:
		var parent := skeleton.get_bone_parent(bone)
		direction = origin - _global_rest(skeleton, parent, is_source).origin if parent >= 0 else Vector3.UP
	var y := direction.normalized()
	var reference := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.UP
	var x := y.cross(reference).normalized()
	return Basis(x, y, x.cross(y).normalized())

func _delta(skeleton: Skeleton3D, bone: int) -> Quaternion:
	var change := skeleton.get_bone_global_pose(bone).basis.orthonormalized() * skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
	return (align * change * align.inverse()).get_rotation_quaternion()

func _leg_length(skeleton: Skeleton3D, thigh: String, foot: String) -> float:
	return skeleton.get_bone_global_rest(skeleton.find_bone(thigh)).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(foot)).origin)

func _retarget(player: AnimationPlayer, clip: String, source: Skeleton3D, target: Skeleton3D) -> bool:
	var source_animation := player.get_animation(clip)
	var frames := maxi(1, int(round(source_animation.length * FPS)))
	var result := Animation.new()
	result.resource_name = clip
	result.length = frames / FPS
	var looping := clip in LOOPING
	result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	result.set_meta("source", "UAL2_Standard.glb:" + clip)
	var tracks: Array[int] = []
	var source_bones: Array[int] = []
	var corrections: Array[Basis] = []
	for bone in target.get_bone_count():
		var name := String(target.get_bone_name(bone))
		var mapped := source.find_bone(_source_name(name))
		var track := -1
		var correction := Basis.IDENTITY
		if mapped >= 0:
			var source_child := _mapped_child(target, source, bone)
			correction = _frame(source, mapped, source_child, true) * _frame(target, bone, _target_child(target, bone), false).inverse() * target.get_bone_global_rest(bone).basis.orthonormalized()
			track = result.add_track(Animation.TYPE_ROTATION_3D)
			result.track_set_path(track, NodePath(TARGET_ROOT + name))
		tracks.append(track)
		source_bones.append(mapped)
		corrections.append(correction)
	var hips_bone := target.find_bone(PREFIX + "Hips")
	var hips_track := result.add_track(Animation.TYPE_POSITION_3D)
	result.track_set_path(hips_track, NodePath(TARGET_ROOT + PREFIX + "Hips"))
	var pelvis := source.find_bone("pelvis")
	var source_rest_pelvis := _global_rest(source, pelvis, true).origin
	var scale := _leg_length(target, PREFIX + "LeftUpLeg", PREFIX + "LeftFoot") / _leg_length(source, "thigh_l", "foot_l")
	var hips_rest := target.get_bone_rest(hips_bone).origin
	# Ground speed of a cycle: the lower (planted) foot slides back under the hips.
	var source_feet := [source.find_bone("foot_l"), source.find_bone("foot_r")]
	var previous_feet := []
	var travel := Vector2.ZERO
	player.play(clip)
	for frame in frames + 1:
		var time := minf(frame / FPS, source_animation.length)
		source.reset_bone_poses()
		player.seek(time, true)
		var pelvis_now := align * source.get_bone_global_pose(pelvis).origin
		var feet := [align * source.get_bone_global_pose(source_feet[0]).origin - pelvis_now, align * source.get_bone_global_pose(source_feet[1]).origin - pelvis_now]
		if not previous_feet.is_empty():
			var planted := 0 if (previous_feet[0] as Vector3).y < (previous_feet[1] as Vector3).y else 1
			var step: Vector3 = (feet[planted] as Vector3) - (previous_feet[planted] as Vector3)
			travel -= Vector2(step.x, step.z)
		previous_feet = feet
		if looping and frame == frames:
			break # the last frame equals the first: only used for the speed
		target.reset_bone_poses()
		for bone in target.get_bone_count():
			if tracks[bone] < 0:
				continue
			var desired := Basis(_delta(source, source_bones[bone])) * corrections[bone]
			var parent := target.get_bone_parent(bone)
			var parent_basis := target.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_rotation := (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized()
			target.set_bone_pose_rotation(bone, local_rotation)
			result.rotation_track_insert_key(tracks[bone], frame / FPS, local_rotation)
		# Pelvis offset from its rest spot, in target space (Hips' parent is the
		# skeleton root on Ch31, so skeleton space == Hips parent space).
		var offset := (align * source.get_bone_global_pose(pelvis).origin - source_rest_pelvis) * scale
		result.position_track_insert_key(hips_track, frame / FPS, hips_rest + offset)
	if looping:
		result.set_meta("ground_speed", travel.length() * scale / source_animation.length)
	var out := OUT_DIR + clip.to_lower() + ".tres"
	var error := ResourceSaver.save(result, out)
	print("UAL2 %-22s %.2fs %s %s save=%d" % [clip, result.length, "loop" if looping else "once", ("%.2f m/s" % float(result.get_meta("ground_speed"))) if result.has_meta("ground_speed") else "", error])
	return error == OK
