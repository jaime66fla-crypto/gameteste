@tool
class_name LittleHelperToolUtils
extends RefCounted

## Shared utility methods for LittleHelper tools.

static func get_editor_root() -> Node:
	if Engine.is_editor_hint() and EditorInterface != null:
		if EditorInterface.has_method("get_edited_scene_root"):
			return EditorInterface.get_edited_scene_root()
	return null


static func get_editor_selection() -> EditorSelection:
	if Engine.is_editor_hint() and EditorInterface != null:
		if EditorInterface.has_method("get_selection"):
			return EditorInterface.get_selection()
	return null


static func get_editor_undo_redo() -> EditorUndoRedoManager:
	if Engine.is_editor_hint() and EditorInterface != null:
		if EditorInterface.has_method("get_editor_undo_redo"):
			return EditorInterface.get_editor_undo_redo()
	return null


static func find_node_in_scene(root: Node, path_str: String) -> Node:
	if not is_instance_valid(root):
		return null
	var clean := path_str.strip_edges()
	if clean.is_empty() or clean == "." or clean == root.name:
		return root
	if clean.begins_with("./"):
		clean = clean.substr(2)
	var target := root.get_node_or_null(NodePath(clean))
	if not target:
		target = find_node_by_name(root, clean)
	return target


static func find_node_by_name(parent: Node, target_name: String) -> Node:
	if parent.name.to_lower() == target_name.to_lower():
		return parent
	for child in parent.get_children():
		var found := find_node_by_name(child, target_name)
		if found:
			return found
	return null


static func sanitize_variant(val):
	if val is Vector2:
		return {"x": val.x, "y": val.y}
	elif val is Vector3:
		return {"x": val.x, "y": val.y, "z": val.z}
	elif val is Color:
		return val.to_html(true)
	elif val is Resource:
		return val.resource_path if val.resource_path else str(val)
	elif val is Node:
		return str(val.get_path())
	elif val is Array:
		var arr := []
		for item in val:
			arr.append(sanitize_variant(item))
		return arr
	elif val is Dictionary:
		var dict := {}
		for k in val.keys():
			dict[str(k)] = sanitize_variant(val[k])
		return dict
	return val


static func parse_prop_val(existing_val, input_val):
	if existing_val is Vector2 and input_val is Array and input_val.size() >= 2:
		return Vector2(float(input_val[0]), float(input_val[1]))
	elif existing_val is Vector2 and input_val is Dictionary:
		return Vector2(float(input_val.get("x", 0)), float(input_val.get("y", 0)))
	elif existing_val is Vector3 and input_val is Array and input_val.size() >= 3:
		return Vector3(float(input_val[0]), float(input_val[1]), float(input_val[2]))
	elif existing_val is Color and input_val is String:
		return Color.from_string(input_val, Color.WHITE)
	elif existing_val is bool:
		return bool(input_val)
	elif existing_val is int:
		return int(input_val)
	elif existing_val is float:
		return float(input_val)
	return input_val

