@tool
class_name DeleteTrackOrKeyframeTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "delete_track_or_keyframe"

func _get_tool_short_description() -> String:
	return "删除轨道或关键帧"

func _get_tool_description() -> String:
	return "删除指定动画中的轨道或指定关键帧。"

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
				"description": "动画库名称"
			},
			"animation_name": {
				"type": "string",
				"description": "动画名称"
			},
			"target_type": {
				"type": "string",
				"description": "删除目标类型：\"track\" 或 \"keyframe\""
			},
			"track_index": {
				"type": "integer",
				"description": "目标轨道索引"
			},
			"keyframe_time": {
				"type": "number",
				"description": "target_type 为 \"keyframe\" 时，指定要删除的关键帧时间位置（秒）"
			}
		},
		"required": ["scene_path", "animation_player_path", "library_name", "animation_name", "target_type", "track_index"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.SCENE

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path") or not json.has("library_name") or not json.has("animation_name") or not json.has("target_type") or not json.has("track_index"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String
	var library_name = json.library_name as String
	var animation_name = json.animation_name as String
	var target_type = json.target_type as String
	var track_index = json.track_index as int

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

	if track_index < 0 or track_index >= animation.get_track_count():
		return {"error": "轨道索引 " + str(track_index) + " 无效，有效范围 0~" + str(animation.get_track_count() - 1) + "。"}

	match target_type:
		"track":
			animation.remove_track(track_index)
			return {"success": true, "message": "轨道 " + str(track_index) + " 已删除。"}
		"keyframe":
			if not json.has("keyframe_time"):
				return {"error": "删除关键帧时必须提供 keyframe_time 参数。"}
			var keyframe_time = json.keyframe_time as float
			var key_idx = _find_key_idx(animation, track_index, keyframe_time)
			if key_idx < 0:
				return {"error": "在轨道 " + str(track_index) + " 中未找到时间点为 " + str(keyframe_time) + " 的关键帧。"}
			animation.track_remove_key(track_index, key_idx)
			return {"success": true, "message": "关键帧（轨道 " + str(track_index) + "，时间 " + str(keyframe_time) + "）已删除。"}
		_:
			return {"error": "无效的 target_type：'" + target_type + "'，应为 \"track\" 或 \"keyframe\"。"}

static func _find_key_idx(animation: Animation, track_idx: int, time: float) -> int:
	var key_count = animation.track_get_key_count(track_idx)
	for i in range(key_count):
		var key_time = animation.track_get_key_time(track_idx, i)
		if abs(key_time - time) < 0.001:
			return i
	return -1
