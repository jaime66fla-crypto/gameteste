@tool
class_name GetAnimationInfoTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "get_animation_info"

func _get_tool_short_description() -> String:
	return "获取动画详情"

func _get_tool_description() -> String:
	return "获取指定动画的详细信息，包括所有轨道及关键帧数据。"

func _get_tool_parameters() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"scene_path": {
				"type": "string",
				"description": "场景路径，以 res:// 开头"
			},
			"animation_player_path": {
				"type": "string",
				"description": "AnimationPlayer 节点路径"
			},
			"library_name": {
				"type": "string",
				"description": "动画库名称（默认库传空字符串 \"\"）"
			},
			"animation_name": {
				"type": "string",
				"description": "动画名称"
			},
			"include_keyframe_values": {
				"type": "boolean",
				"description": "是否需要同时返回关键帧的值，默认 true"
			}
		},
		"required": ["scene_path", "animation_player_path", "library_name", "animation_name"]
	}

func _get_tool_readonly() -> bool:
	return true

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.QUERY

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path") or not json.has("library_name") or not json.has("animation_name"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String
	var library_name = json.library_name as String
	var animation_name = json.animation_name as String
	var include_keyframe_values = json.get("include_keyframe_values", true)

	var anim_player = AgentToolUtils.get_target_node(scene_path, anim_player_path)
	if not anim_player:
		return {"error": "无法获取目标节点，请检查路径是否正确。"}

	if not anim_player is AnimationPlayer:
		return {"error": "目标节点不是 AnimationPlayer 类型。"}

	var library = anim_player.get_animation_library(library_name)
	if not library:
		return {"error": "动画库 '" + library_name + "' 不存在。"}

	var animation = library.get_animation(animation_name)
	if not animation:
		return {"error": "动画 '" + animation_name + "' 不存在。"}

	var full_path = animation_name if library_name == "" else library_name + "/" + animation_name

	var tracks = []
	for i in range(animation.get_track_count()):
		var track_type = animation.track_get_type(i)
		var track_path = animation.track_get_path(i)
		var path_str = str(track_path)

		var track_info = {
			"index": i,
			"type": _track_type_to_string(track_type),
			"node_path": path_str
		}

		if track_type == Animation.TYPE_VALUE:
			var colon_idx = path_str.rfind(":")
			if colon_idx >= 0:
				track_info["node_path"] = path_str.substr(0, colon_idx)
				track_info["property"] = path_str.substr(colon_idx + 1)

		var keyframes = []
		for j in range(animation.track_get_key_count(i)):
			var key_time = animation.track_get_key_time(i, j)
			var keyframe_info = {
				"time": key_time
			}
			if include_keyframe_values:
				keyframe_info["value"] = var_to_str(animation.track_get_key_value(i, j))
			keyframes.append(keyframe_info)

		track_info["keyframes"] = keyframes
		tracks.append(track_info)

	return {
		"library_name": library_name,
		"animation_name": animation_name,
		"full_path": full_path,
		"length": animation.length,
		"loop_mode": _loop_mode_to_string(animation.loop_mode),
		"step": animation.step,
		"tracks": tracks
	}

static func _track_type_to_string(type: int) -> String:
	match type:
		Animation.TYPE_VALUE:
			return "value"
		Animation.TYPE_METHOD:
			return "method"
		Animation.TYPE_BEZIER:
			return "bezier"
		Animation.TYPE_AUDIO:
			return "audio"
		Animation.TYPE_ANIMATION:
			return "animation"
		Animation.TYPE_BLEND_SHAPE:
			return "blend_shape"
		Animation.TYPE_POSITION_3D:
			return "position_3d"
		Animation.TYPE_ROTATION_3D:
			return "rotation_3d"
		Animation.TYPE_SCALE_3D:
			return "scale_3d"
		_:
			return "unknown"

static func _loop_mode_to_string(mode: int) -> String:
	match mode:
		Animation.LOOP_LINEAR:
			return "linear"
		Animation.LOOP_PINGPONG:
			return "pingpong"
		_:
			return "none"
