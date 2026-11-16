@tool
class_name CreateAnimationLibraryTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "create_animation_library"

func _get_tool_short_description() -> String:
	return "创建动画库"

func _get_tool_description() -> String:
	return "在指定的 AnimationPlayer 节点下创建新的动画库。"

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
				"description": "新库名称（不能为空字符串，默认库自动存在）"
			}
		},
		"required": ["scene_path", "animation_player_path", "library_name"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.SCENE

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if json == null or not json.has("scene_path") or not json.has("animation_player_path") or not json.has("library_name"):
		return {"error": "调用失败。请检查参数是否正确。"}

	var scene_path = json.scene_path as String
	var anim_player_path = json.animation_player_path as String
	var library_name = json.library_name as String

	if library_name.is_empty():
		return {"error": "库名称不能为空字符串，默认库由 Godot 自动管理。"}

	var anim_player = AgentToolUtils.get_target_node(scene_path, anim_player_path)
	if not anim_player:
		return {"error": "无法获取目标节点，请检查路径是否正确。"}

	if not anim_player is AnimationPlayer:
		return {"error": "目标节点不是 AnimationPlayer 类型。"}

	if anim_player.has_animation_library(library_name):
		return {"error": "动画库 '" + library_name + "' 已存在。"}

	var new_lib = AnimationLibrary.new()
	anim_player.add_animation_library(library_name, new_lib)

	return {"success": true, "message": "动画库 '" + library_name + "' 创建成功。"}
