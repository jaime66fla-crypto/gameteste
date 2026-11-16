@tool
class_name LittleHelperToolRegistry
extends RefCounted

## Central tool registry and dispatcher for LittleHelper.
## Aggregates modular category toolsets from src/tools/.

const SceneTools   = preload("res://addons/little_helper/src/tools/scene_tools.gd")
const NodeTools    = preload("res://addons/little_helper/src/tools/node_tools.gd")
const ProjectTools = preload("res://addons/little_helper/src/tools/project_tools.gd")
const CodeTools    = preload("res://addons/little_helper/src/tools/code_tools.gd")

const MODULES = [
	SceneTools,
	NodeTools,
	ProjectTools,
	CodeTools
]

static func get_tool_definitions() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for module in MODULES:
		list.append_array(module.get_tools())
	return list


static func execute_tool(tool_name: String, args: Dictionary) -> Dictionary:
	for module in MODULES:
		if module.has_tool(tool_name):
			return module.execute(tool_name, args)
	return {"error": "Unknown tool: %s" % tool_name}
