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
##   godot --headless --path godot --script res://tools/characters/build_unarmed_locomotion.gd [-- <out_dir> [clip names...]]
const TARGET_MODEL := "res://assets/personagens/downloaded/avatar.fbx"
const HUMAN := "res://assets/personagens/jaime/animacoes/Animations/Male/"
const DEFAULT_OUT := "res://assets/personagens/downloaded/movements/"
const TARGET_ROOT := "Skeleton3D:"
const FPS := 30.0
## Directional cycles: "walk_unarmed"/"jog_unarmed" are forward, the others
## get a suffix (walk_unarmed_left, jog_unarmed_backward_right, ...).
const DIRECTIONS := {
	"": "Forward", "_forward_left": "ForwardLeft", "_forward_right": "ForwardRight",
	"_left": "Left", "_right": "Right",
	"_backward": "Backward", "_backward_left": "BackwardLeft", "_backward_right": "BackwardRight",
}

static func sources() -> Dictionary:
	var result := {"idle_unarmed": HUMAN + "Idles/HumanM@Idle01.fbx"}
	for suffix in DIRECTIONS:
		result["walk_unarmed" + suffix] = HUMAN + "Movement/Walk/HumanM@Walk01_%s.fbx" % DIRECTIONS[suffix]
		result["jog_unarmed" + suffix] = HUMAN + "Movement/Run/HumanM@Run01_%s.fbx" % DIRECTIONS[suffix]
	for output_name in REAL_CONTROLLER_CLIPS:
		result[output_name] = REAL_CONTROLLER + REAL_CONTROLLER_CLIPS[output_name] + ".res"
	return result
## Addon real-controller (addons/real-controller, fora do export): mesmo pacote
## HumanM, com o que faltava aqui — sprint e pulo/queda/pouso de corpo inteiro.
const REAL_CONTROLLER := "res://addons/real-controller/animations/"
const REAL_CONTROLLER_SCENE := "res://addons/real-controller/character.tscn"
const REAL_CONTROLLER_CLIPS := {
	"sprint_unarmed": "sprint_forward",
	"jump_unarmed_start": "jump_begin", "fall_unarmed": "fall", "land_unarmed": "jump_land",
}
## Clips whose hips follow the source height instead of keeping a toe on the floor.
## (sprint too: its flight phase has no planted foot, and pinning the lowest
## toe to the floor dropped the hips into a crouch).
const AIR_CLIPS := ["sprint_unarmed", "jump_unarmed_start", "fall_unarmed", "land_unarmed"]
const HUMANOID_NAMES := {
	"hips": "Hips", "spine": "Spine", "chest": "Chest", "neck": "Neck", "head": "Head",
	"shoulder": "Shoulder", "upperArm": "UpperArm", "forearm": "LowerArm", "hand": "Hand",
	"thigh": "UpperLeg", "shin": "LowerLeg", "foot": "Foot", "toe": "Toes",
}
const HUMANOID_FINGERS := {"Thumb": "Thumb", "Index": "Index", "Middle": "Middle", "Ring": "Ring", "Pinky": "Little"}
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
	var all := sources()
	# Optional names after the out dir rebuild only those clips.
	var only := args.slice(1)
	for output_name in all:
		if not only.is_empty() and not output_name in only:
			continue
		failed = not _retarget(all[output_name], output_name, target) or failed
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
		var mapped := _find(source, _source_name(String(target.get_bone_name(child))))
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

## Source bone by HumanM name; the real-controller skeleton uses the Godot
## humanoid names for the same bones (B-thigh.L = LeftUpperLeg).
func _find(skeleton: Skeleton3D, name: String) -> int:
	var bone := skeleton.find_bone(name)
	if bone < 0 and name.begins_with("B-"):
		bone = skeleton.find_bone(_humanoid_name(name))
	return bone

static func _humanoid_name(human_m: String) -> String:
	var base := human_m.trim_prefix("B-")
	var side := ""
	if base.ends_with(".L") or base.ends_with(".R"):
		side = "Left" if base.ends_with(".L") else "Right"
		base = base.left(-2)
	if HUMANOID_NAMES.has(base):
		return side + String(HUMANOID_NAMES[base])
	for finger in HUMANOID_FINGERS:
		for index in range(1, 4):
			if base == (FINGERS[finger] as String) % index:
				return side + String(HUMANOID_FINGERS[finger]) + (["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"])[index - 1]
	return ""

## Poses a skeleton from a bare Animation whose tracks are "<node>:<bone>".
func _sample(animation: Animation, skeleton: Skeleton3D, time: float) -> void:
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, time))

func _leg_length(skeleton: Skeleton3D, thigh: String, foot: String) -> float:
	return skeleton.get_bone_global_rest(_find(skeleton, thigh)).origin.distance_to(skeleton.get_bone_global_rest(_find(skeleton, foot)).origin)

func _retarget(source_path: String, output_name: String, target: Skeleton3D) -> bool:
	if not ResourceLoader.exists(source_path):
		printerr("Missing source: ", source_path)
		return false
	# FBX: the clip comes with its own skeleton. real-controller .res: a bare
	# Animation on the humanoid-named GeneralSkeleton of its character scene,
	# sampled track by track (no AnimationPlayer path to resolve).
	var from_res := source_path.ends_with(".res")
	var source_model := (load(REAL_CONTROLLER_SCENE if from_res else source_path) as PackedScene).instantiate() as Node3D
	root.add_child(source_model)
	var source := source_model.find_child("GeneralSkeleton" if from_res else "Skeleton3D", true, false) as Skeleton3D
	var player: AnimationPlayer = null
	var clip := ""
	var source_animation: Animation
	if from_res:
		source_animation = load(source_path) as Animation
	else:
		player = source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		clip = String(player.get_animation_list()[0])
		source_animation = player.get_animation(clip)
	var looping := not from_res or source_animation.loop_mode != Animation.LOOP_NONE
	var air := output_name in AIR_CLIPS
	var frames := int(round(source_animation.length * FPS))

	var result := Animation.new()
	result.resource_name = output_name
	result.length = frames / FPS
	result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	result.set_meta("source", source_path.get_file())
	var source_bones: Array[int] = []
	var corrections: Array[Basis] = []
	var tracks: Array[int] = []
	var spine := _find(source, "B-spine")
	var chest := _find(source, "B-chest")
	for bone in target.get_bone_count():
		var name := String(target.get_bone_name(bone))
		var mapped := _find(source, _source_name(name))
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
	var source_feet := [_find(source, "B-foot.L"), _find(source, "B-foot.R")]
	var source_hips := _find(source, "B-hips")
	var scale := _leg_length(target, "mixamorig9_LeftUpLeg", "mixamorig9_LeftFoot") / _leg_length(source, "B-thigh.L", "B-foot.L")
	var previous_feet := []
	var travel := Vector2.ZERO
	var source_rest_hips_y := source.get_bone_global_rest(source_hips).origin.y
	if player != null:
		player.play(clip)
	for frame in frames + 1:
		var time := minf(frame / FPS, source_animation.length)
		source.reset_bone_poses()
		if player != null:
			player.seek(time, true)
		else:
			_sample(source_animation, source, time)
		# Ground speed: the lower (planted) foot slides back under the hips.
		var hips_origin := source.get_bone_global_pose(source_hips).origin
		var feet := [source.get_bone_global_pose(source_feet[0]).origin - hips_origin, source.get_bone_global_pose(source_feet[1]).origin - hips_origin]
		if not previous_feet.is_empty():
			var planted := 0 if (previous_feet[0] as Vector3).y < (previous_feet[1] as Vector3).y else 1
			var step: Vector3 = (feet[planted] as Vector3) - (previous_feet[planted] as Vector3)
			travel -= Vector2(step.x, step.z) # any direction: forward, sideways, backward
		previous_feet = feet
		if frame == frames and looping:
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
		if air:
			# Pulo/queda/pouso: pés fora do chão (pernas encolhidas no ar). O quadril
			# segue a altura do clipe (escala da perna); quem sobe e desce é o corpo físico.
			hips_position = target.get_bone_rest(hips_bone).origin + Vector3.UP * (hips_origin.y - source_rest_hips_y) * scale
		result.position_track_insert_key(hips_track, frame / FPS, hips_position)
	var speed := travel.length() * scale / source_animation.length
	result.set_meta("ground_speed", speed)
	# Travel direction in the clip (x right, y forward), for checking the set.
	result.set_meta("travel_direction", travel.normalized() if travel.length() > 0.01 else Vector2.ZERO)
	var error := ResourceSaver.save(result, out_dir + output_name + ".tres")
	print("RETARGET %s length=%.2fs speed=%.2f m/s dir=%s save=%d" % [output_name, result.length, speed, result.get_meta("travel_direction"), error])
	source_model.free()
	return error == OK
