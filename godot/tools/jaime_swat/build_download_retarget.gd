extends SceneTree
## Retargets the two user-provided Mixamo clips onto the SWAT rig.
## Source FBX files and the existing retargeted clips remain untouched.
const TARGET_MODEL := "res://assets/personagens/jaime/[FREE] Rigged Stylized SWAT Soldier.glb"
const WALK_SOURCE := "res://assets/personagens/jaime/animacoes/Downloads/Brutal To Happy Walking.fbx"
const FIRE_SOURCE := "res://assets/personagens/jaime/animacoes/Downloads/Firing Rifle.fbx"
const RUN_SOURCE := "res://assets/personagens/jaime/animacoes/Downloads/Run Forward.fbx"
const SPRINT_SOURCE := "res://assets/personagens/jaime/animacoes/Downloads/Running.fbx"
const OUTPUT := "res://assets/personagens/jaime/retargeted/"
const TARGET_ROOT := "Soldier/Node/Skeleton3D:"

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var target_model := load(TARGET_MODEL).instantiate() as Node3D
	root.add_child(target_model)
	var target := target_model.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(target != null and target.get_bone_count() == 52, "Unexpected SWAT skeleton")
	for entry in [[WALK_SOURCE, "walk_forward_download"], [FIRE_SOURCE, "fire_download"], [RUN_SOURCE, "run_forward_download"], [SPRINT_SOURCE, "sprint_forward_download"]]:
		_retarget(entry[0], entry[1], target)
	target_model.free()
	print("DOWNLOAD RETARGET: PASS")
	quit()

func _source_name(target_name: String) -> String:
	return "mixamorig9_" + target_name.trim_prefix("mixamorig")

func _primary_child(skeleton: Skeleton3D, bone: int) -> int:
	var name := String(skeleton.get_bone_name(bone))
	var preferred := ""
	if name.ends_with("Hips"):
		preferred = "mixamorig9_Spine" if name.begins_with("mixamorig9_") else "mixamorigSpine"
	elif name == "mixamorig9_Spine2":
		preferred = "mixamorig9_Neck"
	elif name == "mixamorigSpine2":
		preferred = "mixamorigNeck"
	elif name.ends_with("Hand"):
		preferred = name + "Middle1"
	if preferred != "":
		var preferred_index := skeleton.find_bone(preferred)
		if preferred_index >= 0:
			return preferred_index
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

func _retarget(source_path: String, output_name: String, target: Skeleton3D) -> void:
	var source_model := load(source_path).instantiate() as Node3D
	root.add_child(source_model)
	var source := source_model.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := source_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(source != null and player != null, "Missing source skeleton or AnimationPlayer: " + source_path)
	assert(player.has_animation("mixamo_com"), "Expected mixamo_com clip in " + source_path)
	var source_animation := player.get_animation("mixamo_com")
	var result := Animation.new()
	result.length = source_animation.length
	result.loop_mode = Animation.LOOP_LINEAR if output_name.begins_with("walk") else Animation.LOOP_NONE
	var source_bones: Array[int] = []
	var corrections: Array[Basis] = []
	for bone in target.get_bone_count():
		var mapped := source.find_bone(_source_name(String(target.get_bone_name(bone))))
		assert(mapped >= 0, "Unmapped target bone: " + String(target.get_bone_name(bone)))
		source_bones.append(mapped)
		corrections.append(_rest_frame(source, mapped) * _rest_frame(target, bone).inverse() * target.get_bone_global_rest(bone).basis.orthonormalized())
		var track := result.add_track(Animation.TYPE_ROTATION_3D)
		result.track_set_path(track, NodePath(TARGET_ROOT + String(target.get_bone_name(bone))))
	var hips_track := result.add_track(Animation.TYPE_POSITION_3D)
	result.track_set_path(hips_track, NodePath(TARGET_ROOT + "mixamorigHips"))
	var rest_toe_y := minf(target.get_bone_global_rest(target.find_bone("mixamorigLeftToeBase")).origin.y, target.get_bone_global_rest(target.find_bone("mixamorigRightToeBase")).origin.y)
	player.play("mixamo_com")
	var frame_count := ceili(result.length * 30.0)
	for frame in frame_count + 1:
		var time := minf(float(frame) / 30.0, result.length)
		source.reset_bone_poses()
		player.seek(time, true)
		target.reset_bone_poses()
		for bone in target.get_bone_count():
			var motion := _delta(source, source_bones[bone])
			if target.get_bone_name(bone) == &"mixamorigSpine1":
				motion = _delta(source, source.find_bone("mixamorig9_Spine")).slerp(motion, 0.5)
			var desired := Basis(motion) * corrections[bone]
			var parent := target.get_bone_parent(bone)
			var parent_basis := target.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
			var local_rotation := (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized()
			target.set_bone_pose_rotation(bone, local_rotation)
			result.rotation_track_insert_key(bone, time, local_rotation)
		var toe_y := minf(target.get_bone_global_pose(target.find_bone("mixamorigLeftToeBase")).origin.y, target.get_bone_global_pose(target.find_bone("mixamorigRightToeBase")).origin.y)
		var hips_position := target.get_bone_rest(0).origin + Vector3.UP * (rest_toe_y - toe_y)
		result.position_track_insert_key(hips_track, time, hips_position)
	var error := ResourceSaver.save(result, OUTPUT + output_name + ".tres")
	assert(error == OK, "Could not save retargeted clip: " + output_name)
	print("RETARGET ", output_name, " frames=", frame_count + 1, " duration=", result.length)
	source_model.free()
