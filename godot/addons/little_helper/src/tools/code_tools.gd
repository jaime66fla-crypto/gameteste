@tool
class_name LittleHelperCodeTools
extends RefCounted

## ClassDB query, GDScript reading, and in-editor dynamic execution tools.

const Utils = preload("res://addons/little_helper/src/tools/tool_utils.gd")

static func get_tools() -> Array[Dictionary]:
	return [
		{
			"name": "get_class_info",
			"description": "Queries Godot's built-in ClassDB for class properties, methods, signals, and inheritance.",
			"parameters": {
				"type": "object",
				"properties": {
					"class_name": {
						"type": "string",
						"description": "Name of the Godot class (e.g. 'CharacterBody2D', 'Area3D', 'GPUParticles2D')."
					}
				},
				"required": ["class_name"]
			}
		},
		{
			"name": "read_script",
			"description": "Reads GDScript code from a file in the project with optional line range.",
			"parameters": {
				"type": "object",
				"properties": {
					"file_path": {
						"type": "string",
						"description": "Path to the script file (e.g. 'res://player.gd')."
					},
					"start_line": {
						"type": "integer",
						"description": "First line to read (1-indexed)."
					},
					"end_line": {
						"type": "integer",
						"description": "Last line to read (inclusive)."
					}
				},
				"required": ["file_path"]
			}
		},
		{
			"name": "execute_code",
			"description": "Executes a GDScript code snippet or expression inside the Godot editor, with access to the active scene root.",
			"parameters": {
				"type": "object",
				"properties": {
					"code": {
						"type": "string",
						"description": "GDScript expression (e.g. 'root.get_child_count()') or multi-line statement block to execute."
					}
				},
				"required": ["code"]
			}
		}
	]


static func has_tool(tool_name: String) -> bool:
	return tool_name in ["get_class_info", "read_script", "execute_code"]


static func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"get_class_info":
			return _get_class_info(args)
		"read_script":
			return _read_script(args)
		"execute_code":
			return _execute_code(args)
	return {"error": "Tool '%s' not found in CodeTools" % tool_name}


static func _get_class_info(args: Dictionary) -> Dictionary:
	var c_name: String = str(args.get("class_name", "")).strip_edges()
	if c_name.is_empty():
		return {"error": "Parameter 'class_name' is required."}
	
	if not ClassDB.class_exists(c_name):
		return {"error": "Class '%s' does not exist in Godot's ClassDB." % c_name}
	
	var parent_class := ClassDB.get_parent_class(c_name)
	
	var methods := []
	for m in ClassDB.class_get_method_list(c_name, true):
		methods.append(m["name"])
	
	var properties := []
	for p in ClassDB.class_get_property_list(c_name, true):
		properties.append(p["name"])
	
	var signals := []
	for s in ClassDB.class_get_signal_list(c_name, true):
		signals.append(s["name"])
	
	return {
		"class_name": c_name,
		"parent_class": parent_class,
		"can_instantiate": ClassDB.can_instantiate(c_name),
		"methods_count": methods.size(),
		"methods": methods.slice(0, 40),
		"properties_count": properties.size(),
		"properties": properties.slice(0, 40),
		"signals": signals
	}


static func _read_script(args: Dictionary) -> Dictionary:
	var path: String = str(args.get("file_path", "")).strip_edges()
	if path.is_empty():
		return {"error": "Parameter 'file_path' is required."}
	
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	
	if not FileAccess.file_exists(path):
		return {"error": "Script file not found: %s" % path}
	
	var fa := FileAccess.open(path, FileAccess.READ)
	if not fa:
		return {"error": "Failed to open script file: %s" % path}
	
	var content := fa.get_as_text()
	fa.close()
	
	var lines := content.split("\n")
	var total_lines := lines.size()
	
	var start_line: int = int(args.get("start_line", 1))
	var end_line: int = int(args.get("end_line", total_lines))
	
	start_line = clampi(start_line, 1, total_lines)
	end_line = clampi(end_line, start_line, total_lines)
	
	var slice := lines.slice(start_line - 1, end_line)
	return {
		"file_path": path,
		"total_lines": total_lines,
		"start_line": start_line,
		"end_line": end_line,
		"content": "\n".join(slice)
	}


static func _execute_code(args: Dictionary) -> Dictionary:
	var code_str: String = str(args.get("code", "")).strip_edges()
	if code_str.is_empty():
		return {"error": "Parameter 'code' is required."}
	
	var root := Utils.get_editor_root()
	var is_statement := code_str.contains("\n") or code_str.begins_with("var ") or code_str.begins_with("return ") or code_str.begins_with("for ") or code_str.begins_with("if ") or code_str.begins_with("while ")
	
	if not is_statement:
		var expr := Expression.new()
		var parse_err := expr.parse(code_str, ["root"])
		if parse_err == OK:
			var result = expr.execute([root], root)
			if not expr.has_execute_failed():
				return {"success": true, "result": Utils.sanitize_variant(result), "mode": "expression"}
	
	# Wrap in dynamic script
	var script := GDScript.new()
	var lines := code_str.split("\n")
	var indented_lines := []
	for l in lines:
		indented_lines.append("\t" + l)
	var method_body := "\n".join(indented_lines)
	
	script.source_code = "@tool\nextends RefCounted\n\nfunc execute(root: Node):\n" + method_body + "\n"
	var reload_err := script.reload()
	if reload_err != OK:
		return {"error": "Failed to compile GDScript (code %d)" % reload_err}
	
	var inst = script.new()
	var res = inst.execute(root)
	return {"success": true, "result": Utils.sanitize_variant(res), "mode": "script"}

