@tool
class_name CreateAnimationTool
extends AgentToolBase

func _get_tool_name() -> String:
	return "create_animation"

func _get_tool_short_description() -> String:
	return "创建或复制动画"

func _get_tool_description() -> String:
	return "在指定动画库中创建新动画，或从已有动画复制创建。"

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
				"description": "目标动画库名称（默认库传空字符串 \"\"）"
			},
			"animation_name": {
				"type": "string",
				"description": "新动画名称"
			},
			"source_animation_full_path": {
				"type": "string",
				"description": "可选。源动画完整路径（如 \"fx/explode\"），提供则复制该动画的所有内容"
			},
			"length": {
				"type": "number",
				"description": "可选。动画长度（秒），默认 1.0"
			},
			"loop_mode": {
				"type": "string",
				"description": "可选。循环模式：\"none\" / \"linear\" / \"pingpong\""
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

	if library.has_animation(animation_name):
		return {"error": "动画 '" + animation_name + "' 已存在。"}

	var new_anim: Animation

	if json.has("source_animation_full_path"):
		var source_full_path = json.source_animation_full_path as String
		var parts = source_full_path.split("/")
		var src_lib_name: String
		var src_anim_name: String
		if parts.size() >= 2:
			src_lib_name = parts[0]
			src_anim_name = "/".join(parts.slice(1))
		else:
			src_lib_name = ""
			src_anim_name = parts[0]

		var src_library = anim_player.get_animation_library(src_lib_name)
		if not src_library:
			return {"error": "源动画库 '" + src_lib_name + "' 不存在。"}

		var src_anim = src_library.get_animation(src_anim_name)
		if not src_anim:
			return {"error": "源动画 '" + source_full_path + "' 不存在。"}

		new_anim = src_anim.duplicate()
	else:
		new_anim = Animation.new()
		var anim_length = json.get("length", 1.0)
		new_anim.length = anim_length

	if json.has("loop_mode"):
		var mode_str = json.loop_mode as String
		var mode = _string_to_loop_mode(mode_str)
		if mode == -1:
			return {"error": "无效的循环模式：'" + mode_str + "'，应为 none/linear/pingpong。"}
		new_anim.loop_mode = mode

	library.add_animation(animation_name, new_anim)

	var full_path = animation_name if library_name == "" else library_name + "/" + animation_name
	return {"success": true, "message": "动画 '" + full_path + "' 创建成功。"}

static func _string_to_loop_mode(mode: String) -> int:
	match mode:
		"none":
			return Animation.LOOP_NONE
		"linear":
			return Animation.LOOP_LINEAR
		"pingpong":
			return Animation.LOOP_PINGPONG
		_:
			return -1
