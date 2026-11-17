extends SceneTree
## Inspeciona um modelo importado: ossos, malhas (vértices), materiais/texturas, animações e altura.
## godot --headless --path godot --script res://tools/characters/inspect_fbx.gd -- --path=res://...

func _initialize() -> void:
	var path := "res://assets/personagens/zumbi/zumbi.fbx"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--path="):
			path = arg.substr(7)
	var packed := load(path) as PackedScene
	if packed == null:
		print("não carregou: " + path)
		quit(1)
		return
	var root := packed.instantiate()
	var aabb := AABB()
	var first := true
	for node in root.find_children("*", "", true, false):
		if node is Skeleton3D:
			var sk := node as Skeleton3D
			print("Skeleton: %s  ossos=%d  ex: %s, %s, %s" % [sk.name, sk.get_bone_count(), sk.get_bone_name(0), sk.get_bone_name(1), sk.get_bone_name(sk.get_bone_count() - 1)])
		elif node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var verts := 0
			for s in mi.mesh.get_surface_count():
				verts += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var mat := mi.mesh.surface_get_material(s)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
					var tex := (mat as StandardMaterial3D).albedo_texture
					print("   material %d: albedo %dx%d" % [s, tex.get_width(), tex.get_height()])
			print("Mesh: %s  superfícies=%d  vértices=%d  skin=%s" % [mi.name, mi.mesh.get_surface_count(), verts, mi.skin != null])
			var box := mi.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
		elif node is AnimationPlayer:
			var ap := node as AnimationPlayer
			for a in ap.get_animation_list():
				print("Animação: %s  %.2f s  trilhas=%d" % [a, ap.get_animation(a).length, ap.get_animation(a).get_track_count()])
	print("AABB (local das malhas): %s" % aabb)
	root.free()
	quit(0)
