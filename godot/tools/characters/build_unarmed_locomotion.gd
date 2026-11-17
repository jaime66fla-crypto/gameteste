extends SceneTree
## Retargets the unarmed "HumanM" basic motions (idle, walk, jog) onto the Ch31
## avatar ("mixamorig9_" rig) as in-place loops for downloaded_avatar.gd.
## Same rest-frame retarget as tools/jaime_swat/build_download_retarget.gd:
## each target bone copies the source bone's world rotation change, measured
## against the direction to its main child, so the different rest poses
## (A-pose vs T-pose) do not bend the limbs. The natural ground speed of each
## cycle is measured from the planted foot and stored as "ground_speed" (m/s),
## so the game can play it at the rate that keeps the feet from sliding.
## Usage (from the repo root):
##   godot --headless --path godot --script res://tools/characters/build_unarmed_locomotion.gd [-- <out_dir>]
const TARGET_MODEL := "res://assets/personagens/downloaded/avatar.fbx"
const HUMAN := "res://assets/personagens/jaime/animacoes/Animations/Male/"
const DEFAULT_OUT := "res://assets/personagens/downloaded/movements/"
const TARGET_ROOT := "Skeleton3D:"
const FPS := 30.0
const SOURCES := {
	"idle_unarmed": HUMAN + "Idles/HumanM@Idle01.fbx",
	"walk_unarmed": HUMAN + "Movement/Walk/HumanM@Walk01_Forward.fbx",
	"jog_unarmed": HUMAN + "Movement/Run/HumanM@Run01_Forward.fbx",
}
## Ch31 bone suffix -> HumanM bone. Spine1 has no source: it takes half of the
## spine-to-chest motion. Finger/head/toe end bones keep their rest pose.
const BONE_MAP := {
	"Hips": "B-hips", "Spine": "B-spine", "Spine2": "B-chest", "Neck": "B-neck", "Head": "B-head",
	"LeftShoulder": "B-shoulder.L", "LeftArm": "B-upperArm.L", "LeftForeArm": "B-forearm.L", "LeftHand": "B-hand.L",
	"RightShoulder": "B-shoulder.R", "RightArm": "B-upperArm.R", "RightForeArm": "B-forearm.R", "RightHand": "B-hand.R",
	"LeftUpLeg": "B-thigh.L", "LeftLeg": "B-shin.L", "LeftFoot": "B-foot.L", "LeftToeBase": "B-toe.L",
	"RightUpLeg": "B-thigh.R", "RightLeg": "B-shin.R", "RightFoot": "B-foot.R", "RightToeBase": "B-toe.R",
}
const FINGERS := {"Thumb": "thumb0%d", "Index": "indexFinger0%d", "Middle": "middleFinger0%d", "Ring": "ringFinger0%d", "Pinky": "pinky0%d"}

var out_dir := DEFAULT_OUT

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0].trim_suffix("/") + "/"
	var target_model := (load(TARGET_MODEL) as PackedScene).instantiate() as Node3D
	root.add_child(target_model)
	var target := target_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if target == null or target.get_bone_count() != 65:
		printerr("Unexpected Ch31 skeleton")
		quit(1)
		return
	var failed := false
	for output_name in SOURCES:
		failed = not _retarget(SOURCES[output_name], output_name, target) or failed
	target_model.free()
	print("UNARMED LOCOMOTION: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

## HumanM bone name for a Ch31 bone, or "" when it has no counterpart.
func _source_name(target_name: String) -> String:
	var suffix := target_name.trim_prefix("mixamorig9_")
	if BONE_MAP.has(suffix):
		return BONE_MAP[suffix]
	for side in ["Left", "Right"]:
		for finger in FINGERS:
			for index in range(1, 4):
				if suffix == "%sHand%s%d" % [side, finger, index]:
					return "B-" + (FINGERS[finger] as String) % index + (".L" if side == "Left" else ".R")
	return ""

## The target bone's main child (spine chain, middle finger for hands).
func _target_child(target: Skeleton3D, bone: int) -> int:
	var name := String(target.get_bone_name(bone))
	var preferred := ""
	if name.ends_with("_Hips"):
		preferred = "mixamorig9_Spine"
	elif name.ends_with("_Spine2"):
		preferred = "mixamorig9_Neck"
	elif name.ends_with("Hand"):
		preferred = name + "Middle1"
	if preferred != "" and target.find_bone(preferred) >= 0:
		return target.find_bone(preferred)
	var children := target.get_bone_children(bone)
	return children[0] if not children.is_empty() else -1

## Source bone that plays the role of the target bone's main child (skipping
## target bones with no counterpart, e.g. Spine -> Spine1 -> Spine2 = chest).
func _mapped_child(target: Skeleton3D, source: Skeleton3D, bone: int) -> int:
	var child := _target_child(target, bone)
	while child >= 0:
		var mapped := source.find_bone(_source_name(String(target.get_bone_name(child))))
		if mapped >= 0:
			return mapped
		child = _target_child(target, child)
	return -1

func _frame(skeleton: Skeleton3D, bone: int, child: int) -> Basis:
	var origin := skeleton.get_bone_global_rest(bone).origin
	var direction := Vector3.ZERO
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

func _leg_length(skeleton: Skeleton3D, thigh: String, foot: String) -> float:
	return skeleton.get_bone_global_rest(skeleton.find_bone(thigh)).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(foot)).origin)

func _retarget(source_path: String, output_name: String, target: Skeleton3D) -> bool:
	if not ResourceLoader.exists(source_path):
		printerr("Missing source: ", source_path)
		return false
	var source_model := (load(source_path) as PackedScene).instantiate() as Node3D
	root.add_child(source_model)
	var source := source_model.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := String(player.get_animation_list()[0])
	var source_animation := player.get_animation(clip)
	var frames := int(round(source_animation.length * FPS))

	var result := Animation.new()
	result.resource_name = output_name
	result.length = frames / FPS
	result.loop_mode = Animation.LOOP_LINEAR
	result.set_meta("source", source_path.get_file())
	var source_bones: Array[int] = []
	var corrections: Array[Basis] = []
	var tracks: Array[int] = []
	var spine := source.find_bone("B-spine")
	var chest := source.find_bone("B-chest")
	for bone in target.get_bone_count():
		var name := String(target.get_bone_name(bone))
		var mapped := source.find_bone(_source_name(name))
		var source_frame_bone := mapped
		if name.ends_with("_Spine1"):
			source_frame_bone = spine # half spine, half chest (see below)
		source_bones.append(mapped if not name.ends_with("_Spine1") else spine)
		var track := -1
		var correction := Basis.IDENTITY
		if source_frame_bone >= 0:
			var source_child := chest if name.ends_with("_Spine1") else _mapped_child(target, source, bone)
			correction = _frame(source, source_frame_bone, source_child) * _frame(target, bone, _target_child(target, bone)).inverse() * target.get_bone_global_rest(bone).basis.orthonormalized()
			track = result.add_track(Animation.TYPE_ROTATION_3D)
			result.track_set_path(track, NodePath(TARGET_ROOT + name))
		corrections.append(correction)
		tracks.append(track)
	var hips_bone := target.find_bone("mixamorig9_Hips")
	var hips_track := result.add_track(Animation.TYPE_POSITION_3D)
	result.track_set_path(hips_track, NodePath(TARGET_ROOT + "mixamorig9_Hips"))
	var toes := [target.find_bone("mixamorig9_LeftToeBase"), target.find_bone("mixamorig9_RightToeBase")]
	var rest_toe_y := minf(target.get_bone_global_rest(toes[0]).origin.y, target.get_bone_global_rest(toes[1]).origin.y)
	var source_feet := [source.find_bone("B-foot.L"), source.find_bone("B-foot.R")]
	var source_hips := source.find_bone("B-hips")
	var scale := _leg_length(target, "mixamorig9_LeftUpLeg", "mixamorig9_LeftFoot") / _leg_length(source, "B-thigh.L", "B-foot.L")
	var previous_feet := []
	var travel := 0.0
	player.play(clip)
	for frame in frames + 1:
		var time := minf(frame / FPS, source_animation.length)
		source.reset_bone_poses()
		player.seek(time, true)
		# Ground speed: the lower (planted) foot slides back under the hips.
		var hips_origin := source.get_bone_global_pose(source_hips).origin
		var feet := [source.get_bone_global_pose(source_feet[0]).origin - hips_origin, source.get_bone_global_pose(source_feet[1]).origin - hips_origin]
		if not previous_feet.is_empty():
			var planted := 0 if (previous_feet[0] as Vector3).y < (previous_feet[1] as Vector3).y else 1
			travel += -((feet[planted] as Vector3).z - (previous_feet[planted] as Vector3).z)
		previous_feet = feet
		if frame == frames:
			break # the last frame equals the first: only used for the speed
		target.reset_bone_poses()
		for bone in target.get_bone_count():
			if tracks[bone] < 0:
				continue
			var motion := _delta(source, source_bones[bone])
			if String(target.get_bone_name(bone)).ends_with("_Spine1"):
				motion = motion.slerp(_delta(source, chest), 0.5)
			var desired := Basis(motion) * corrections[bone]
			var parent := target.get_bone_parent(bone)
			var parent_basis := target.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_rotation := (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized()
			target.set_bone_pose_rotation(bone, local_rotation)
			result.rotation_track_insert_key(tracks[bone], frame / FPS, local_rotation)
		var toe_y := minf(target.get_bone_global_pose(toes[0]).origin.y, target.get_bone_global_pose(toes[1]).origin.y)
		var hips_position := target.get_bone_rest(hips_bone).origin + Vector3.UP * (rest_toe_y - toe_y)
		result.position_track_insert_key(hips_track, frame / FPS, hips_position)
	var speed := maxf(0.0, travel * scale / source_animation.length)
	result.set_meta("ground_speed", speed)
	var error := ResourceSaver.save(result, out_dir + output_name + ".tres")
	print("RETARGET %s length=%.2fs speed=%.2f m/s save=%d" % [output_name, result.length, speed, error])
	source_model.free()
	return error == OK
