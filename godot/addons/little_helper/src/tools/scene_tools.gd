@tool
class_name LittleHelperSceneTools
extends RefCounted

## Scene and node inspection tools for LittleHelper.

const Utils = preload("res://addons/little_helper/src/tools/tool_utils.gd")

static func get_tools() -> Array[Dictionary]:
	return [
		{
			"name": "get_selected_nodes",
			"description": "Returns the currently selected nodes in the Godot scene tree editor.",
			"parameters": {
				"type": "object",
				"properties": {},
				"required": []
			}
		},
		{
			"name": "get_scene_tree",
			"description": "Returns the full node hierarchy of the currently open scene in the editor.",
			"parameters": {
				"type": "object",
				"properties": {
					"max_depth": {
						"type": "integer",
						"description": "Maximum depth of child nodes to traverse (default 6)."
					}
				},
				"required": []
			}
		},
		{
			"name": "inspect_node",
			"description": "Inspects a specific node by path or selection, returning its properties, transform, script, and warnings.",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path to the node relative to the scene root (e.g. 'Player/CollisionShape2D'). If empty, inspects scene root or current selection."
					}
				},
				"required": []
			}
		},
		{
			"name": "select_node",
			"description": "Selects a node in the Godot scene tree and inspector by path or name.",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path or name of the node to select (e.g. 'Player' or 'Player/CollisionShape2D'). Leave empty to select scene root."
					},
					"clear_selection": {
						"type": "boolean",
						"description": "Whether to deselect other currently selected nodes first (default true)."
					}
				},
				"required": []
			}
		}
	]


static func has_tool(tool_name: String) -> bool:
	return tool_name in ["get_selected_nodes", "get_scene_tree", "inspect_node", "select_node"]


static func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"get_selected_nodes":
			return _get_selected_nodes(args)
		"get_scene_tree":
			return _get_scene_tree(args)
		"inspect_node":
			return _inspect_node(args)
		"select_node":
			return _select_node(args)
	return {"error": "Tool '%s' not found in SceneTools" % tool_name}


static func _get_selected_nodes(_args: Dictionary) -> Dictionary:
	var sel_obj := Utils.get_editor_selection()
	if not sel_obj:
		return {"count": 0, "selected_nodes": [], "message": "Editor selection is not active."}
	var selection := sel_obj.get_selected_nodes()
	var root := Utils.get_editor_root()
	var list := []
	
	for node in selection:
		var rel_path := str(root.get_path_to(node)) if is_instance_valid(root) and root != node else "."
		list.append({
			"name": node.name,
			"class": node.get_class(),
			"path": rel_path,
			"scene_file_path": node.scene_file_path,
			"has_script": node.get_script() != null
		})
	return {
		"count": list.size(),
		"selected_nodes": list
	}


static func _get_scene_tree(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var max_depth: int = int(args.get("max_depth", 6))
	return {
		"scene_name": root.name,
		"scene_file": root.scene_file_path,
		"tree": _dump_tree_node(root, 0, max_depth)
	}


static func _dump_tree_node(node: Node, current_depth: int, max_depth: int) -> Dictionary:
	var info := {
		"name": node.name,
		"class": node.get_class(),
		"children_count": node.get_child_count()
	}
	if node.get_script():
		info["script"] = node.get_script().resource_path
	if not node.scene_file_path.is_empty():
		info["instance_scene"] = node.scene_file_path
	
	if current_depth < max_depth:
		var children := []
		for child in node.get_children():
			children.append(_dump_tree_node(child, current_depth + 1, max_depth))
		if not children.is_empty():
			info["children"] = children
	return info


static func _inspect_node(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var path_str: String = str(args.get("node_path", "")).strip_edges()
	var target_node: Node = null
	
	if path_str.is_empty():
		var sel_obj := Utils.get_editor_selection()
		var sel := sel_obj.get_selected_nodes() if sel_obj else []
		if not sel.is_empty():
			target_node = sel[0]
		else:
			target_node = root
	else:
		target_node = Utils.find_node_in_scene(root, path_str)
	
	if not is_instance_valid(target_node):
		return {"error": "Node not found at path: '%s'" % path_str}
	
	var props := {}
	for p in target_node.get_property_list():
		var p_name: String = p["name"]
		var usage: int = p["usage"]
		if (usage & PROPERTY_USAGE_EDITOR) != 0 and not p_name.begins_with("metadata/"):
			var val = target_node.get(p_name)
			props[p_name] = Utils.sanitize_variant(val)
	
	var rel_path := str(root.get_path_to(target_node)) if root != target_node else "."
	var result := {
		"name": target_node.name,
		"class": target_node.get_class(),
		"path": rel_path,
		"properties": props
	}
	
	if target_node.get_script():
		result["script"] = target_node.get_script().resource_path
	if target_node is Node2D:
		result["transform_2d"] = {
			"position": Utils.sanitize_variant(target_node.position),
			"rotation_deg": target_node.rotation_degrees,
			"scale": Utils.sanitize_variant(target_node.scale)
		}
	elif target_node is Node3D:
		result["transform_3d"] = {
			"position": Utils.sanitize_variant(target_node.position),
			"rotation_deg": Utils.sanitize_variant(target_node.rotation_degrees),
			"scale": Utils.sanitize_variant(target_node.scale)
		}
	
	var warnings = target_node.get_configuration_warnings()
	if not warnings.is_empty():
		result["configuration_warnings"] = warnings
	return result


static func _select_node(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No active scene is currently open in the editor."}
	
	var sel_obj := Utils.get_editor_selection()
	if not sel_obj:
		return {"error": "EditorSelection interface is not available."}
	
	var path_str: String = str(args.get("node_path", "")).strip_edges()
	var clear_sel: bool = bool(args.get("clear_selection", true))
	var target_node := Utils.find_node_in_scene(root, path_str)
	
	if not is_instance_valid(target_node):
		return {"error": "Could not find node at '%s' in current scene." % path_str}
	
	if clear_sel:
		sel_obj.clear()
	
	sel_obj.add_node(target_node)
	if Engine.is_editor_hint() and EditorInterface != null and EditorInterface.has_method("edit_node"):
		EditorInterface.edit_node(target_node)
	
	var rel_path := str(root.get_path_to(target_node)) if target_node != root else "."
	return {
		"success": true,
		"selected_node": target_node.name,
		"type": target_node.get_class(),
		"path": rel_path
	}
