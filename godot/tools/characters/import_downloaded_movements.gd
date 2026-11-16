extends SceneTree

const AVATAR_PATH := "res://assets/personagens/downloaded/avatar.fbx"
const MOVEMENT_DIR := "res://assets/personagens/downloaded/movements/"
const SOURCES := {
	"walk_with_rifle": "Walk With Rifle.fbx",
	"run_to_stop": "Run To Stop.fbx",
	"punch": "Punching.fbx",
	"elbow_punch": "Illegal Elbow Punch.fbx",
}

func _initialize() -> void:
	call_deferred("_import")

func _import() -> void:
	var avatar_scene := (load(AVATAR_PATH) as PackedScene).instantiate()
	var avatar_player := avatar_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var idle := avatar_player.get_animation("Take 001") as Animation
	var hip_anchor := Vector3.ZERO
	for track in idle.get_track_count():
		if idle.track_get_type(track) == Animation.TYPE_POSITION_3D and "mixamorig9_Hips" in String(idle.track_get_path(track)):
			hip_anchor = idle.track_get_key_value(track, 0)
			break
	avatar_scene.free()

	for clip_name in SOURCES:
		var source_scene := (load(MOVEMENT_DIR + SOURCES[clip_name]) as PackedScene).instantiate()
		var source_player := source_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip := (source_player.get_animation("mixamo_com") as Animation).duplicate() as Animation
		for track in clip.get_track_count():
			if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or "mixamorig9_Hips" not in String(clip.track_get_path(track)):
				continue
			for key in clip.track_get_key_count(track):
				var position: Vector3 = clip.track_get_key_value(track, key)
				clip.track_set_key_value(track, key, Vector3(hip_anchor.x, position.y, hip_anchor.z))
		clip.loop_mode = Animation.LOOP_LINEAR if clip_name == "walk_with_rifle" else Animation.LOOP_NONE
		var output: String = MOVEMENT_DIR + clip_name + ".tres"
		var error := ResourceSaver.save(clip, output)
		print(clip_name, " duration=", clip.length, " tracks=", clip.get_track_count(), " save_error=", error)
		source_scene.free()
	var idle_scene := (load(MOVEMENT_DIR + SOURCES["run_to_stop"]) as PackedScene).instantiate()
	var idle_player := idle_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var stop_animation := idle_player.get_animation("mixamo_com") as Animation
	var idle_pose := _pose_from(stop_animation, stop_animation.length)
	var idle_error := ResourceSaver.save(idle_pose, MOVEMENT_DIR + "idle_with_rifle.tres")
	print("idle_with_rifle duration=", idle_pose.length, " tracks=", idle_pose.get_track_count(), " save_error=", idle_error)
	idle_scene.free()
	quit()

func _pose_from(source: Animation, time: float) -> Animation:
	var pose := Animation.new()
	pose.resource_name = "idle_with_rifle"
	pose.length = 1.0
	pose.loop_mode = Animation.LOOP_LINEAR
	for source_track in source.get_track_count():
		var track := pose.add_track(source.track_get_type(source_track))
		pose.track_set_path(track, source.track_get_path(source_track))
		pose.track_set_enabled(track, source.track_is_enabled(source_track))
		pose.track_set_interpolation_type(track, source.track_get_interpolation_type(source_track))
		pose.track_set_interpolation_loop_wrap(track, source.track_get_interpolation_loop_wrap(source_track))
		var key_count := source.track_get_key_count(source_track)
		if key_count == 0:
			continue
		var source_key := key_count - 1
		for key in key_count:
			if source.track_get_key_time(source_track, key) >= time:
				source_key = key
				break
		pose.track_insert_key(track, 0.0, source.track_get_key_value(source_track, source_key))
	return pose
