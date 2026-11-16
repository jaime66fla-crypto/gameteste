@tool
class_name DeleteAnimationTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "delete_animation"

func _get_tool_short_description() -> String:
	return "删除动画"

func _get_tool_description() -> String:
	return "删除指定动画库中的某个动画。"

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
				"description": "要删除的动画名称"
			}
		},
		"required": ["scene_path", "animation_player_path", "library_name", "animation_name"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.SCENE

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path") or not json.has("library_name") or not json.has("animation_name"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String
	var library_name = json.library_name as String
	var animation_name = json.animation_name as String

	var anim_player = AgentToolUtils.get_target_node(scene_path, anim_player_path)
	if not anim_player:
		return {"error": "无法获取目标节点，请检查路径是否正确。"}

	if not anim_player is AnimationPlayer:
		return {"error": "目标节点不是 AnimationPlayer 类型。"}

	var library = anim_player.get_animation_library(library_name)
	if not library:
		return {"error": "动画库 '" + library_name + "' 不存在。"}

	if not library.has_animation(animation_name):
		return {"error": "动画 '" + animation_name + "' 不存在。"}

	library.remove_animation(animation_name)

	return {"success": true, "message": "动画 '" + animation_name + "' 已删除。"}
