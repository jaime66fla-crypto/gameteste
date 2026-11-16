@tool
class_name LittleHelperProjectTools
extends RefCounted

## Scene saving/opening, project execution, debug logging, and ProjectSettings tools.

const Utils = preload("res://addons/little_helper/src/tools/tool_utils.gd")

static func get_tools() -> Array[Dictionary]:
	return [
		{
			"name": "save_scene",
			"description": "Saves the active edited scene or all open scenes to disk.",
			"parameters": {
				"type": "object",
				"properties": {
					"all": {
						"type": "boolean",
						"description": "Whether to save all open scenes instead of just the active one (default false)."
					}
				},
				"required": []
			}
		},
		{
			"name": "open_scene",
			"description": "Opens a scene (.tscn) in a Godot editor tab.",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {
						"type": "string",
						"description": "Path to the scene file to open (e.g. 'res://levels/level_1.tscn')."
					}
				},
				"required": ["scene_path"]
			}
		},
		{
			"name": "run_project",
			"description": "Runs the Godot project (main scene) or a custom scene in debug mode.",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {
						"type": "string",
						"description": "Optional path to custom scene e.g. 'res://main.tscn'. Leave empty to run main scene."
					}
				},
				"required": []
			}
		},
		{
			"name": "stop_project",
			"description": "Stops the currently running project scene.",
			"parameters": {
				"type": "object",
				"properties": {},
				"required": []
			}
		},
		{
			"name": "get_debug_logs",
			"description": "Reads recent engine output, warning, and error logs from Godot's debug log file.",
			"parameters": {
				"type": "object",
				"properties": {
					"max_lines": {
						"type": "integer",
						"description": "Maximum number of recent log lines to retrieve (default 50)."
					}
				},
				"required": []
			}
		},
		{
			"name": "project_setting",
			"description": "Gets, sets, or searches project settings in ProjectSettings (project.godot).",
			"parameters": {
				"type": "object",
				"properties": {
					"setting": {
						"type": "string",
						"description": "Setting name or prefix search (e.g. 'application/run/main_scene' or 'display/window'). If empty, returns common categories."
					},
					"value": {
						"description": "New value to set. If omitted or null, returns current setting value or searches matching prefix."
					},
					"save": {
						"type": "boolean",
						"description": "Whether to save project.godot to disk immediately when setting a value (default true)."
					}
				},
				"required": []
			}
		}
	]


static func has_tool(tool_name: String) -> bool:
	return tool_name in ["save_scene", "open_scene", "run_project", "stop_project", "get_debug_logs", "project_setting"]


static func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"save_scene":
			return _save_scene(args)
		"open_scene":
			return _open_scene(args)
		"run_project":
			return _run_project(args)
		"stop_project":
			return _stop_project(args)
		"get_debug_logs":
			return _get_debug_logs(args)
		"project_setting":
			return _project_setting(args)
	return {"error": "Tool '%s' not found in ProjectTools" % tool_name}


static func _save_scene(args: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint() or EditorInterface == null:
		return {"error": "EditorInterface is not available (not running inside Godot editor)."}
	
	var save_all: bool = bool(args.get("all", false))
	if save_all:
		if EditorInterface.has_method("save_all_scenes"):
			EditorInterface.save_all_scenes()
			return {"success": true, "message": "All open scenes saved successfully."}
		else:
			return {"error": "EditorInterface.save_all_scenes is not supported in this engine version."}
	else:
		if EditorInterface.has_method("save_scene"):
			var err = EditorInterface.save_scene()
			if err == OK:
				var root := Utils.get_editor_root()
				var path := root.scene_file_path if root else "active scene"
				return {"success": true, "message": "Scene saved: %s" % path, "path": path}
			else:
				return {"error": "Failed to save scene (error code %d)" % err}
		else:
			return {"error": "EditorInterface.save_scene is not available."}


static func _open_scene(args: Dictionary) -> Dictionary:
	var path: String = str(args.get("scene_path", "")).strip_edges()
	if path.is_empty():
		return {"error": "Parameter 'scene_path' is required."}
	if not path.begins_with("res://") and not path.begins_with("user://"):
		path = "res://" + path
	
	if not FileAccess.file_exists(path):
		return {"error": "Scene file not found at: '%s'" % path}
	
	if not Engine.is_editor_hint() or EditorInterface == null or not EditorInterface.has_method("open_scene_from_path"):
		return {"error": "EditorInterface.open_scene_from_path is not available."}
	
	EditorInterface.open_scene_from_path(path)
	return {"success": true, "opened_scene": path}


static func _run_project(args: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint() or EditorInterface == null:
		return {"error": "EditorInterface is not available."}
	
	var custom_scene: String = str(args.get("scene_path", "")).strip_edges()
	if not custom_scene.is_empty():
		if not custom_scene.begins_with("res://"):
			custom_scene = "res://" + custom_scene
		if not FileAccess.file_exists(custom_scene):
			return {"error": "Scene file does not exist: %s" % custom_scene}
		if EditorInterface.has_method("play_custom_scene"):
			EditorInterface.play_custom_scene(custom_scene)
			return {"success": true, "message": "Running custom scene: %s" % custom_scene}
		else:
			return {"error": "EditorInterface.play_custom_scene is not available."}
	else:
		if EditorInterface.has_method("play_main_scene"):
			EditorInterface.play_main_scene()
			return {"success": true, "message": "Running main project scene."}
		else:
			return {"error": "EditorInterface.play_main_scene is not available."}


static func _stop_project(_args: Dictionary) -> Dictionary:
	if not Engine.is_editor_hint() or EditorInterface == null:
		return {"error": "EditorInterface is not available."}
	
	if EditorInterface.has_method("is_playing_scene") and not EditorInterface.is_playing_scene():
		return {"message": "Project is not currently running."}
	
	if EditorInterface.has_method("stop_playing_scene"):
		EditorInterface.stop_playing_scene()
		return {"success": true, "message": "Stopped playing project."}
	else:
		return {"error": "EditorInterface.stop_playing_scene is not available."}


static func _get_debug_logs(args: Dictionary) -> Dictionary:
	var max_lines: int = int(args.get("max_lines", 50))
	if max_lines <= 0:
		max_lines = 50
	
	var log_paths := [
		"user://logs/godot.log",
		"user://logs/editor.log"
	]
	
	var file_to_read := ""
	for p in log_paths:
		if FileAccess.file_exists(p):
			file_to_read = p
			break
	
	if file_to_read.is_empty():
		return {
			"logs": "",
			"message": "No Godot log files found under user://logs/."
		}
	
	var fa := FileAccess.open(file_to_read, FileAccess.READ)
	if not fa:
		return {"error": "Failed to open log file at '%s'." % file_to_read}
	
	var all_text := fa.get_as_text()
	fa.close()
	
	var lines := all_text.split("\n")
	var total := lines.size()
	var start_idx := maxi(0, total - max_lines)
	var slice := lines.slice(start_idx)
	
	return {
		"log_file": file_to_read,
		"total_lines": total,
		"returned_lines": slice.size(),
		"logs": "\n".join(slice)
	}


static func _project_setting(args: Dictionary) -> Dictionary:
	var setting_name: String = str(args.get("setting", "")).strip_edges()
	var has_val := args.has("value") and args["value"] != null
	
	if setting_name.is_empty() and not has_val:
		return {
			"message": "Specify a setting name or prefix (e.g. 'application/run/main_scene' or 'display/window').",
			"common_categories": ["application", "display", "rendering", "physics", "audio", "input", "autoload"]
		}
	
	if has_val:
		var old_val = ProjectSettings.get_setting(setting_name) if ProjectSettings.has_setting(setting_name) else null
		var new_val = args["value"]
		ProjectSettings.set_setting(setting_name, new_val)
		var should_save: bool = bool(args.get("save", true))
		if should_save:
			var save_err := ProjectSettings.save()
			if save_err != OK:
				return {
					"warning": "Setting applied in memory but failed to save to project.godot (error %d)." % save_err,
					"setting": setting_name,
					"value": Utils.sanitize_variant(new_val)
				}
		return {
			"success": true,
			"setting": setting_name,
			"old_value": Utils.sanitize_variant(old_val),
			"new_value": Utils.sanitize_variant(new_val),
			"saved": should_save
		}
	
	if ProjectSettings.has_setting(setting_name):
		var val = ProjectSettings.get_setting(setting_name)
		return {
			"setting": setting_name,
			"value": Utils.sanitize_variant(val)
		}
	
	var props := ProjectSettings.get_property_list()
	var matches := {}
	for p in props:
		var pname: String = p.get("name", "")
		if pname.begins_with(setting_name) or pname.contains(setting_name):
			matches[pname] = Utils.sanitize_variant(ProjectSettings.get_setting(pname))
			if matches.size() >= 30:
				break
	
	if not matches.is_empty():
		return {
			"matched_settings_count": matches.size(),
			"settings": matches
		}
	
	return {"error": "Project setting not found: '%s'" % setting_name}

