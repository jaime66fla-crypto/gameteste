extends SceneTree
## Mede um personagem Mixamo importado: altura real (topo da cabeça), quadril,
## caminho do esqueleto, escala dos nós e materiais de cada malha.
## godot --headless --path godot --script res://tools/characters/measure_mixamo.gd -- --path=res://...
func _initialize() -> void:
	var path := "res://assets/personagens/remy/remy.fbx"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
	var root := (load(path) as PackedScene).instantiate() as Node3D
	get_root().add_child(root)
	var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("skeleton node path: ", root.get_path_to(sk), "  global scale: ", sk.global_transform.basis.get_scale())
	if ap:
		print("anim player root -> skeleton: ", ap.get_node(ap.root_node).get_path_to(sk))
	var top := -INF
	var bottom := INF
	for i in sk.get_bone_count():
		var y := (sk.global_transform * sk.get_bone_global_rest(i).origin).y
		top = maxf(top, y)
		bottom = minf(bottom, y)
	var hips := sk.find_bone("mixamorig_Hips")
	print("bone height range (world): %.3f .. %.3f" % [bottom, top])
	print("hips rest local: ", sk.get_bone_rest(hips).origin, " world y: ", (sk.global_transform * sk.get_bone_global_rest(hips).origin).y)
	var mesh_top := -INF
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.global_transform * m.get_aabb()
		mesh_top = maxf(mesh_top, box.end.y)
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null:
				print("  %s: material %s" % [m.name, m.get_active_material(s)])
				continue
			print("  %s: albedo=%s normal=%s rough_tex=%s metal_tex=%s transp=%d cull=%d rough=%.2f metal=%.2f" % [m.name, mat.albedo_texture != null, mat.normal_texture != null if mat.normal_enabled else false, mat.roughness_texture != null, mat.metallic_texture != null, mat.transparency, mat.cull_mode, mat.roughness, mat.metallic])
	print("mesh top (bind pose aabb): %.3f" % mesh_top)
	for name in ["mixamorig_HeadTop_End", "mixamorig_LeftToeBase", "mixamorig_LeftFoot"]:
		var b := sk.find_bone(name)
		if b >= 0:
			print("%s world: %s" % [name, sk.global_transform * sk.get_bone_global_rest(b).origin])
	root.queue_free()
	quit(0)
