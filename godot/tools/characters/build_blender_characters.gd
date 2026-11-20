extends SceneTree
## Turns the Blender-modelled characters (tools/blender/build_characters.py ->
## assets/personagens/blender/<id>.glb) into game-ready <id>_modelo.scn.
## The meshes are rebound onto a copy of the Ch31 Skeleton3D (the rig every clip
## is authored on, mixamorig9_ names), so no retarget runs at load: the Blender
## armature only carries joint positions, its bone axes are never used.
## Skin bind = inverse of the Ch31 bone's global rest; the Blender mesh is built
## at those exact joint positions, so the rest pose is unchanged.
## godot --headless --path godot --import
## godot --headless --path godot --script res://tools/characters/build_blender_characters.gd
const RIG_SOURCE := "res://assets/personagens/downloaded/avatar.fbx"
const DIR := "res://assets/personagens/blender/"
const IDS := ["avatar_ch31", "remy", "manequim", "pato"]
const LOOK := {
	"Matte": {"roughness": 0.86, "specular": 0.3},
	"Gloss": {"roughness": 0.3, "specular": 0.6},
}

func _initialize() -> void:
	var rig_root := (load(RIG_SOURCE) as PackedScene).instantiate()
	var rig := rig_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ok := true
	for id in IDS:
		ok = _build(id, rig) and ok
	rig_root.free()
	quit(0 if ok else 1)

func _build(id: String, rig: Skeleton3D) -> bool:
	var packed := load(DIR + id + ".glb") as PackedScene
	if packed == null:
		printerr("GLB nao encontrado: %s%s.glb (rode tools/blender/build_characters.py e --import)" % [DIR, id])
		return false
	var glb := packed.instantiate()
	var glb_skeleton := glb.find_child("Skeleton3D", true, false) as Skeleton3D
	var model := Node3D.new()
	model.name = id.to_pascal_case() + "Modelo"
	var skeleton := rig.duplicate() as Skeleton3D
	for child in skeleton.get_children():
		skeleton.remove_child(child)
		child.free()
	skeleton.name = "Skeleton3D"
	skeleton.transform = Transform3D.IDENTITY
	skeleton.reset_bone_poses()
	model.add_child(skeleton)
	skeleton.owner = model
	var top := -INF
	var ok := true
	for node in glb.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		var xf := _to_root(source, glb)
		if not xf.is_equal_approx(Transform3D.IDENTITY):
			push_warning("%s: malha com transformacao %s (esperado identidade)" % [id, xf])
		var skin := Skin.new()
		for i in source.skin.get_bind_count():
			var bone_name := String(source.skin.get_bind_name(i))
			if bone_name.is_empty():
				bone_name = String(glb_skeleton.get_bone_name(source.skin.get_bind_bone(i)))
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				printerr("%s: osso %s nao existe no Ch31" % [id, bone_name])
				ok = false
				continue
			skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(bone).affine_inverse())
		var mesh := source.mesh.duplicate() as ArrayMesh
		for s in mesh.get_surface_count():
			var src_mat := mesh.surface_get_material(s)
			var mat_name := src_mat.resource_name if src_mat != null else "Matte"
			mesh.surface_set_material(s, _material(id, mat_name))
		var mi := MeshInstance3D.new()
		mi.name = source.name
		mi.mesh = mesh
		mi.skin = skin
		skeleton.add_child(mi)
		mi.owner = model
		mi.skeleton = NodePath("..")
		top = maxf(top, mesh.get_aabb().end.y)
	var scene := PackedScene.new()
	var err := scene.pack(model)
	var out := DIR + id + "_modelo.scn"
	if err == OK:
		err = ResourceSaver.save(scene, out, ResourceSaver.FLAG_COMPRESS)
	print("%s: topo %.3f m, %d ossos -> %s: %s" % [id, top, skeleton.get_bone_count(), out, error_string(err)])
	model.free()
	glb.free()
	return ok and err == OK

func _to_root(node: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while node != root and node != null:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	return xf

func _material(id: String, mat_name: String) -> StandardMaterial3D:
	var look: Dictionary = LOOK.get(mat_name, LOOK["Matte"])
	var mat := StandardMaterial3D.new()
	mat.resource_name = "%s_%s" % [id, mat_name]
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = float(look["roughness"])
	mat.metallic_specular = float(look["specular"])
	return mat
