@tool
class_name GetAnimationPlayerDetailTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "get_animation_player_detail"

func _get_tool_short_description() -> String:
	return "获取 AnimationPlayer 完整信息"

func _get_tool_description() -> String:
	return "获取 AnimationPlayer 节点的完整信息，包括所有动画库及其包含的动画列表（不含关键帧详情）。"

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
				"description": "AnimationPlayer 节点在场景树中的路径（从根节点开始，/ 分隔）"
			}
		},
		"required": ["scene_path", "animation_player_path"]
	}

func _get_tool_readonly() -> bool:
	return true

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.QUERY

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String

	var anim_player = AgentToolUtils.get_target_node(scene_path, anim_player_path)
	if not anim_player:
		return {"error": "无法获取目标节点，请检查路径是否正确。"}

	if not anim_player is AnimationPlayer:
		return {"error": "目标节点不是 AnimationPlayer 类型。"}

	var libraries_info = []
	var total_animations = 0

	var lib_names = anim_player.get_animation_library_list()
	for lib_name in lib_names:
		var library = anim_player.get_animation_library(lib_name)
		if not library:
			continue

		var anim_names = library.get_animation_list()
		var animations_info = []
		for anim_name in anim_names:
			var animation = library.get_animation(anim_name)
			if not animation:
				continue

			var full_path = anim_name if lib_name == "" else lib_name + "/" + anim_name
			animations_info.append({
				"name": anim_name,
				"full_path": full_path,
				"length": animation.length,
				"loop_mode": _loop_mode_to_string(animation.loop_mode),
				"track_count": animation.get_track_count()
			})
			total_animations += 1

		var lib_info = {
			"library_name": lib_name,
			"animations": animations_info
		}
		if lib_name == "":
			lib_info["display_name"] = "default"

		libraries_info.append(lib_info)

	return {
		"animation_player": anim_player_path,
		"libraries": libraries_info,
		"total_libraries": libraries_info.size(),
		"total_animations": total_animations
	}

static func _loop_mode_to_string(mode: int) -> String:
	match mode:
		Animation.LOOP_LINEAR:
			return "linear"
		Animation.LOOP_PINGPONG:
			return "pingpong"
		_:
			return "none"
