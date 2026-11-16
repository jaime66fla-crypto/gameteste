@tool
class_name SetSingletonTool
extends AgentToolBase

## 获取脚本的 class_name。先查 ProjectSettings 已注册全局类，未注册则解析文件。
func _get_script_class_name(path: String) -> String:
	if not path.ends_with(".gd"):
		return ""

	# 优先查 ProjectSettings：Godot 已解析过的脚本这里最准最快
	var class_list: Array = ProjectSettings.get_global_class_list()
	for entry in class_list:
		if entry.path == path:
			return entry.get("class", "")

	# 未注册则读文件解析 class_name 行
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text = file.get_as_string()
	for line in text.split("\n"):
		var s = line.strip_edges()
		if s.is_empty() or s.begins_with("#"):
			continue
		if s.begins_with("class_name "):
			return s.substr(11).strip_edges().split(" ")[0]  # 取 extends 前的部分
	return ""

## 检查脚本是否继承自 Node（autoload 必要条件）
func _script_extends_node(path: String) -> bool:
	if not path.ends_with(".gd"):
		return true  # .tscn 场景必然是 Node

	var script = load(path)
	if not script is GDScript:
		return false

	var base: StringName = script.get_instance_base_type()
	if base.is_empty() or not ClassDB.class_exists(base):
		return false

	return ClassDB.is_parent_class(base, "Node")

func _get_tool_name() -> String:
	return "set_singleton"

func _get_tool_short_description() -> String:
	return "调用编辑器接口设置自动加载脚本或场景。"

func _get_tool_description() -> String:
	return "设置或删除项目自动加载脚本或场景"

func _get_tool_parameters() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"name": {
				"type": "string",
				"description": "需要设置的自动加载名称，需要以大驼峰的方式命名。一般可以和脚本或场景文件同名。**依赖**：设置的自动加载脚本或场景文件必须存在。且不能和已有的自动加载名称重复。",
			},
			"path": {
				"type": "string",
				"description": "需要设置为自动加载的脚本或场景路径，必须是以res://开头的绝对路径。如果为空时则会删除该自动加载。**依赖**：设置的自动加载脚本或场景文件必须存在。",
			},
		},
		"required": ["name"]
	}

func _get_tool_readonly() -> bool:
	return false

func _get_tool_group() -> AgentToolBase.ToolGroup:
	return ToolGroup.EDITOR

func do_action(tool_call: AgentModelUtils.ToolCallsInfo) -> Dictionary:
	var json = JSON.parse_string(tool_call.function.arguments)
	if not json == null and json.has("name"):
		var singleton_name = json.name
		var singleton_path = json.get("path", "")
		if singleton_path:
			var script_class := _get_script_class_name(singleton_path)
			if script_class != "" and script_class == singleton_name:
				return {"error": "自动加载名 '%s' 与脚本 class_name '%s' 冲突，不可挂载。请使用不同的自动加载名称。" % [singleton_name, script_class]}
			if not _script_extends_node(singleton_path):
				return {"error": "脚本 '%s' 不继承自 Node，无法设为自动加载。" % singleton_path}
			var singleton = AlphaAgentSingleton.get_instance()
			singleton.add_autoload_singleton(singleton_name, singleton_path)
			return {
				"name": singleton_name,
				"path": singleton_path,
				"success": "添加自动加载成功"
			}
		else:
			var singleton = AlphaAgentSingleton.get_instance()
			singleton.remove_autoload_singleton(singleton_name)
			return {
				"name": singleton_name,
				"success": "删除自动加载成功"
			}

	return { "error": "调用失败。请检查参数是否正确。" }
