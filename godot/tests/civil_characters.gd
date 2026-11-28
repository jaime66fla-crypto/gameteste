extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
func _run() -> void:
	var registry = load("res://scripts/characters/character_registry.gd")
	for id in ["atacante", "defensor"]:
		var avatar: Node3D = registry.create_visual(id)
		root.add_child(avatar)
		_check(bool(avatar.call("is_visual_ready")), id + ": visual ready")
		var meshes := avatar.find_children("*", "MeshInstance3D", true, false)
		var main_mesh: MeshInstance3D
		for child in meshes:
			if child.skin != null:
				main_mesh = child
				break
		_check(main_mesh != null, id + ": skinned body exists")
		if main_mesh != null:
			var height := main_mesh.mesh.get_aabb().size.y * main_mesh.global_basis.get_scale().y
			_check(absf(height - 1.8) < 0.003, "%s: height must be 1.8 m (got %.4f)" % [id,height])
			var shirt := false
			var jeans := false
			var shoes := false
			for s in main_mesh.mesh.get_surface_count():
				var m := main_mesh.mesh.surface_get_material(s) as BaseMaterial3D
				var label := m.resource_name
				_check(not (label.begins_with("Colete_") or label.begins_with("Bolsos_") or label.begins_with("Capacete_")), id + ": tactical equipment remains")
				if "camisa_civil" in label:
					shirt = m.albedo_color.r < 0.18 and m.albedo_color.g < 0.18 and m.albedo_color.b < 0.18
				if "calca_civil" in label:
					jeans = m.albedo_color.b > m.albedo_color.r * 1.5
				if label.begins_with("Clothes_shoes"):
					shoes = m.albedo_color.r < 0.18 and m.albedo_color.b < 0.18
			_check(shirt and jeans and shoes, id + ": black shirt, blue jeans and black shoes")
		avatar.free()
	for failure in failures:
		printerr(failure)
	print("CIVIL CHARACTERS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
