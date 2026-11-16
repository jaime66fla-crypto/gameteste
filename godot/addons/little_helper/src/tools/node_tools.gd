@tool
class_name LittleHelperNodeTools
extends RefCounted

## Node creation, modification, reparenting, and removal tools backed by Undo/Redo.

const Utils = preload("res://addons/little_helper/src/tools/tool_utils.gd")

static func get_tools() -> Array[Dictionary]:
	return [
		{
			"name": "add_node",
			"description": "Adds a new child node to a parent node in the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"type": {
						"type": "string",
						"description": "Type of node to create (e.g. 'CollisionShape2D', 'Sprite2D', 'Marker2D')."
					},
					"name": {
						"type": "string",
						"description": "Desired name for the new node."
					},
					"parent_path": {
						"type": "string",
						"description": "Path of the parent node (leave empty for scene root)."
					}
				},
				"required": ["type"]
			}
		},
		{
			"name": "remove_node",
			"description": "Removes a node from the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path or name of the node to remove relative to scene root (e.g. 'Player/Weapon' or 'OldSprite')."
					}
				},
				"required": ["node_path"]
			}
		},
		{
			"name": "instantiate_scene",
			"description": "Instantiates a packed scene (.tscn) into the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"scene_path": {
						"type": "string",
						"description": "Path to the packed scene file (e.g. 'res://characters/player.tscn')."
					},
					"parent_path": {
						"type": "string",
						"description": "Path of the parent node to attach the instance under (leave empty for scene root)."
					},
					"name": {
						"type": "string",
						"description": "Optional custom name for the instantiated node."
					}
				},
				"required": ["scene_path"]
			}
		},
		{
			"name": "reparent_node",
			"description": "Moves a node to a new parent in the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path or name of the node to move."
					},
					"new_parent_path": {
						"type": "string",
						"description": "Path of the new parent node (leave empty or '.' for scene root)."
					},
					"keep_global_transform": {
						"type": "boolean",
						"description": "Whether to preserve node's global transform after reparenting (default true)."
					}
				},
				"required": ["node_path", "new_parent_path"]
			}
		},
		{
			"name": "set_node_property",
			"description": "Sets a property on a node in the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path of the node relative to scene root."
					},
					"property": {
						"type": "string",
						"description": "Name of the property (e.g. 'position', 'visible', 'collision_layer')."
					},
					"value": {
						"description": "The value to set (int, float, string, bool, Vector2/3 dictionary or array)."
					}
				},
				"required": ["node_path", "property", "value"]
			}
		},
		{
			"name": "connect_signal",
			"description": "Connects a signal from a source node to a target node method in the active scene with Undo/Redo tracking.",
			"parameters": {
				"type": "object",
				"properties": {
					"source_node": {
						"type": "string",
						"description": "Path to the node emitting the signal (e.g. 'Button' or '.')."
					},
					"signal_name": {
						"type": "string",
						"description": "Name of the signal to connect (e.g. 'pressed', 'body_entered')."
					},
					"target_node": {
						"type": "string",
						"description": "Path to the node receiving the signal (e.g. '.' for scene root)."
					},
					"method_name": {
						"type": "string",
						"description": "Name of the method to call on target node (e.g. '_on_button_pressed')."
					}
				},
				"required": ["source_node", "signal_name", "target_node", "method_name"]
			}
		},
		{
			"name": "attach_script",
			"description": "Attaches an existing GDScript file to a node in the active scene with Undo/Redo tracking (supports Ctrl+Z).",
			"parameters": {
				"type": "object",
				"properties": {
					"node_path": {
						"type": "string",
						"description": "Path or name of the node to attach the script to."
					},
					"script_path": {
						"type": "string",
						"description": "Path to the GDScript file (e.g. 'res://scripts/player.gd')."
					}
				},
				"required": ["node_path", "script_path"]
			}
		}
	]


static func has_tool(tool_name: String) -> bool:
	return tool_name in ["add_node", "remove_node", "instantiate_scene", "reparent_node", "set_node_property", "connect_signal", "attach_script"]


static func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"add_node":
			return _add_node(args)
		"remove_node":
			return _remove_node(args)
		"instantiate_scene":
			return _instantiate_scene(args)
		"reparent_node":
			return _reparent_node(args)
		"set_node_property":
			return _set_node_property(args)
		"connect_signal":
			return _connect_signal(args)
		"attach_script":
			return _attach_script(args)
	return {"error": "Tool '%s' not found in NodeTools" % tool_name}


static func _add_node(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var type_name: String = str(args.get("type", "")).strip_edges()
	if not ClassDB.class_exists(type_name):
		return {"error": "Invalid node type: '%s'" % type_name}
	
	var parent_path: String = str(args.get("parent_path", "")).strip_edges()
	var parent_node := Utils.find_node_in_scene(root, parent_path) if not parent_path.is_empty() else root
	if not is_instance_valid(parent_node):
		return {"error": "Parent node not found at: '%s'" % parent_path}
	
	var new_instance = ClassDB.instantiate(type_name)
	if not new_instance is Node:
		return {"error": "Class '%s' is not a Node." % type_name}
	
	var req_name: String = str(args.get("name", "")).strip_edges()
	if not req_name.is_empty():
		new_instance.name = req_name
	
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	undo_redo.create_action("LittleHelper: Add Node %s" % new_instance.name)
	undo_redo.add_do_method(parent_node, "add_child", new_instance)
	undo_redo.add_do_method(new_instance, "set_owner", root)
	undo_redo.add_do_reference(new_instance)
	undo_redo.add_undo_method(parent_node, "remove_child", new_instance)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"created_node": new_instance.name,
		"type": type_name,
		"parent": str(root.get_path_to(parent_node)) if parent_node != root else "."
	}


static func _remove_node(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var path_str: String = str(args.get("node_path", "")).strip_edges()
	if path_str.is_empty():
		return {"error": "Parameter 'node_path' is required."}
	
	var target_node := Utils.find_node_in_scene(root, path_str)
	if not is_instance_valid(target_node):
		return {"error": "Node not found at '%s'" % path_str}
	
	if target_node == root:
		return {"error": "Cannot remove the root node of the active scene."}
	
	var parent := target_node.get_parent()
	if not is_instance_valid(parent):
		return {"error": "Node has no parent."}
	
	var node_idx := target_node.get_index()
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	
	undo_redo.create_action("LittleHelper: Remove Node %s" % target_node.name)
	undo_redo.add_do_method(parent, "remove_child", target_node)
	undo_redo.add_undo_method(parent, "add_child", target_node)
	undo_redo.add_undo_method(parent, "move_child", target_node, node_idx)
	undo_redo.add_undo_method(target_node, "set_owner", root)
	undo_redo.add_undo_reference(target_node)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"removed_node": target_node.name,
		"parent": str(root.get_path_to(parent)) if parent != root else "."
	}


static func _instantiate_scene(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var scene_path: String = str(args.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		return {"error": "Parameter 'scene_path' is required."}
	if not scene_path.begins_with("res://") and not scene_path.begins_with("user://"):
		scene_path = "res://" + scene_path
	
	if not ResourceLoader.exists(scene_path) and not FileAccess.file_exists(scene_path):
		return {"error": "Scene file not found at: '%s'" % scene_path}
	
	var packed := load(scene_path) as PackedScene
	if not packed:
		return {"error": "Failed to load PackedScene at: '%s'" % scene_path}
	
	var inst := packed.instantiate()
	if not inst is Node:
		return {"error": "Instantiated resource is not a Node."}
	
	var req_name: String = str(args.get("name", "")).strip_edges()
	if not req_name.is_empty():
		inst.name = req_name
	
	var parent_path: String = str(args.get("parent_path", "")).strip_edges()
	var parent_node := Utils.find_node_in_scene(root, parent_path) if not parent_path.is_empty() else root
	if not is_instance_valid(parent_node):
		inst.free()
		return {"error": "Parent node not found at: '%s'" % parent_path}
	
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		inst.free()
		return {"error": "UndoRedo manager not available."}
	
	undo_redo.create_action("LittleHelper: Instantiate %s" % inst.name)
	undo_redo.add_do_method(parent_node, "add_child", inst)
	undo_redo.add_do_method(inst, "set_owner", root)
	undo_redo.add_do_reference(inst)
	undo_redo.add_undo_method(parent_node, "remove_child", inst)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"instance_name": inst.name,
		"type": inst.get_class(),
		"scene_path": scene_path,
		"parent": str(root.get_path_to(parent_node)) if parent_node != root else "."
	}


static func _reparent_node(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"error": "Parameter 'node_path' is required."}
	
	var target_node := Utils.find_node_in_scene(root, node_path)
	if not is_instance_valid(target_node):
		return {"error": "Node not found at '%s'" % node_path}
	
	if target_node == root:
		return {"error": "Cannot reparent the scene root node."}
	
	var new_parent_path: String = str(args.get("new_parent_path", "")).strip_edges()
	var new_parent := Utils.find_node_in_scene(root, new_parent_path) if not new_parent_path.is_empty() else root
	if not is_instance_valid(new_parent):
		return {"error": "New parent node not found at '%s'" % new_parent_path}
	
	if new_parent == target_node:
		return {"error": "Cannot reparent a node to itself."}
	
	if target_node.is_ancestor_of(new_parent):
		return {"error": "Cannot reparent a node to its own descendant."}
	
	var old_parent := target_node.get_parent()
	if old_parent == new_parent:
		return {"warning": "Node '%s' is already a child of '%s'." % [target_node.name, new_parent.name]}
	
	var keep_transform: bool = bool(args.get("keep_global_transform", true))
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	
	undo_redo.create_action("LittleHelper: Reparent %s to %s" % [target_node.name, new_parent.name])
	undo_redo.add_do_method(target_node, "reparent", new_parent, keep_transform)
	undo_redo.add_do_method(target_node, "set_owner", root)
	undo_redo.add_undo_method(target_node, "reparent", old_parent, keep_transform)
	undo_redo.add_undo_method(target_node, "set_owner", root)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"node": target_node.name,
		"old_parent": str(root.get_path_to(old_parent)) if old_parent != root else ".",
		"new_parent": str(root.get_path_to(new_parent)) if new_parent != root else "."
	}


static func _set_node_property(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var path_str: String = str(args.get("node_path", "")).strip_edges()
	var target_node := Utils.find_node_in_scene(root, path_str) if not path_str.is_empty() else root
	if not is_instance_valid(target_node):
		return {"error": "Node not found at '%s'" % path_str}
	
	var prop_name: String = str(args.get("property", "")).strip_edges()
	if not prop_name in target_node:
		return {"error": "Property '%s' does not exist on node '%s'" % [prop_name, target_node.name]}
	
	var old_val = target_node.get(prop_name)
	var new_val = Utils.parse_prop_val(old_val, args.get("value"))
	
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	undo_redo.create_action("LittleHelper: Set %s.%s" % [target_node.name, prop_name])
	undo_redo.add_do_property(target_node, prop_name, new_val)
	undo_redo.add_undo_property(target_node, prop_name, old_val)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"node": target_node.name,
		"property": prop_name,
		"old_value": Utils.sanitize_variant(old_val),
		"new_value": Utils.sanitize_variant(new_val)
	}


static func _connect_signal(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var src_path: String = str(args.get("source_node", "")).strip_edges()
	var sig_name: String = str(args.get("signal_name", "")).strip_edges()
	var tgt_path: String = str(args.get("target_node", "")).strip_edges()
	var method_name: String = str(args.get("method_name", "")).strip_edges()
	
	if src_path.is_empty() or sig_name.is_empty() or tgt_path.is_empty() or method_name.is_empty():
		return {"error": "Required arguments: source_node, signal_name, target_node, method_name."}
	
	var src_node := Utils.find_node_in_scene(root, src_path) if src_path != "." else root
	var tgt_node := Utils.find_node_in_scene(root, tgt_path) if tgt_path != "." else root
	
	if not is_instance_valid(src_node):
		return {"error": "Source node not found at: '%s'" % src_path}
	if not is_instance_valid(tgt_node):
		return {"error": "Target node not found at: '%s'" % tgt_path}
	
	if not src_node.has_signal(sig_name):
		return {"error": "Node '%s' has no signal named '%s'." % [src_node.name, sig_name]}
	
	if src_node.is_connected(sig_name, Callable(tgt_node, method_name)):
		return {"warning": "Signal '%s' from '%s' is already connected to '%s.%s()'." % [sig_name, src_node.name, tgt_node.name, method_name]}
	
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	
	undo_redo.create_action("LittleHelper: Connect %s.%s -> %s.%s" % [src_node.name, sig_name, tgt_node.name, method_name])
	undo_redo.add_do_method(src_node, "connect", sig_name, Callable(tgt_node, method_name))
	undo_redo.add_undo_method(src_node, "disconnect", sig_name, Callable(tgt_node, method_name))
	undo_redo.commit_action()
	
	return {
		"success": true,
		"source": src_node.name,
		"signal": sig_name,
		"target": tgt_node.name,
		"method": method_name
	}


static func _attach_script(args: Dictionary) -> Dictionary:
	var root := Utils.get_editor_root()
	if not is_instance_valid(root):
		return {"error": "No scene is currently open in the editor."}
	
	var node_path: String = str(args.get("node_path", "")).strip_edges()
	if node_path.is_empty():
		return {"error": "Parameter 'node_path' is required."}
	
	var target_node := Utils.find_node_in_scene(root, node_path)
	if not is_instance_valid(target_node):
		return {"error": "Node not found at '%s'" % node_path}
	
	var script_path: String = str(args.get("script_path", "")).strip_edges()
	if script_path.is_empty():
		return {"error": "Parameter 'script_path' is required."}
	if not script_path.begins_with("res://") and not script_path.begins_with("user://"):
		script_path = "res://" + script_path
	
	if not FileAccess.file_exists(script_path):
		return {"error": "Script file not found at: '%s'" % script_path}
	
	var script_res := load(script_path) as Script
	if not script_res:
		return {"error": "Failed to load script at: '%s'" % script_path}
	
	var old_script = target_node.get_script()
	var undo_redo := Utils.get_editor_undo_redo()
	if not undo_redo:
		return {"error": "UndoRedo manager not available."}
	
	undo_redo.create_action("LittleHelper: Attach Script %s" % script_path.get_file())
	undo_redo.add_do_method(target_node, "set_script", script_res)
	undo_redo.add_undo_method(target_node, "set_script", old_script)
	undo_redo.commit_action()
	
	return {
		"success": true,
		"node": target_node.name,
		"attached_script": script_path,
		"previous_script": old_script.resource_path if old_script and "resource_path" in old_script else ""
	}

