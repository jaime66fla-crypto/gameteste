extends SceneTree
## Gera o Remy (Mixamo, sobrevivente civil) pronto para o jogo a partir do FBX
## original (assets/personagens/remy/remy.fbx, fica só no seu PC):
##   fase 1: copia sem perda só as texturas que os materiais usam (cor e relevo)
##           para otimizado/<malha>_<tipo>.png
##   (rode --import entre as fases)
##   fase 2: salva remy_modelo.scn com
##           - escala assada em metros: o FBX vem com 3,78 unidades de altura; o
##             esqueleto, a malha, as poses de ligação da pele e os blendshapes
##             são multiplicados por 1,8 / 3,785, então o espaço do esqueleto fica
##             em metros como o Ch31 (o IK e as poses do adaptador usam metros);
##           - materiais ajustados: pele com brilho suave, olhos úmidos, roupa
##             fosca, cabelo e cílios com recorte de alfa e dupla face.
## godot --headless --path godot --script res://tools/characters/build_remy_model.gd -- --phase=1
## godot --headless --path godot --import
## godot --headless --path godot --script res://tools/characters/build_remy_model.gd -- --phase=2
const SOURCE := "res://assets/personagens/remy/remy.fbx"
const OUT_DIR := "res://assets/personagens/remy/otimizado"
const OUT_SCENE := "res://assets/personagens/remy/remy_modelo.scn"
const SOURCE_HEIGHT := 3.785 # topo da malha em T-pose, tools/characters/measure_mixamo.gd
const TARGET_HEIGHT := 1.8
## Ajuste por malha: rugosidade, especular, alfa (0 nenhum, 1 recorte, 2 mistura), sombra.
const LOOK := {
	"Body": {"roughness": 0.58, "specular": 0.42},
	"Eyes": {"roughness": 0.12, "specular": 0.7, "shadow": false},
	"Eyelashes": {"roughness": 0.6, "alpha": 2, "shadow": false},
	"Hair": {"roughness": 0.52, "specular": 0.35, "alpha": 1},
	"Tops": {"roughness": 0.9, "specular": 0.25},
	"Bottoms": {"roughness": 0.88, "specular": 0.25},
	"Shoes": {"roughness": 0.68, "specular": 0.4},
}

func _initialize() -> void:
	var phase := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = int(arg.substr(8))
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		printerr("FBX não encontrado: " + SOURCE)
		quit(1)
		return
	var root := packed.instantiate()
	var ok := _phase_one(root) if phase == 1 else _phase_two(root)
	root.free()
	quit(0 if ok else 1)

func _meshes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		result.append(node as MeshInstance3D)
	return result

func _phase_one(root: Node) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for mi in _meshes(root):
		var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if mat == null:
			continue
		for tex in [mat.albedo_texture, mat.normal_texture]:
			if tex == null or tex.resource_path.is_empty():
				continue
			# Eyes and eyelashes share the body atlas: one copy per source file.
			var out := _optimized_path(tex)
			if FileAccess.file_exists(out):
				continue
			var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(tex.resource_path), ProjectSettings.globalize_path(out))
			# Import settings up front: a headless import cannot detect normal-map
			# use, and a relief map read as sRGB colour lights the skin white.
			# VRAM compression + mipmaps keep the 2K maps cheap and unaliased.
			var import_file := FileAccess.open(ProjectSettings.globalize_path(out + ".import"), FileAccess.WRITE)
			import_file.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=2\ncompress/normal_map=%d\nmipmaps/generate=true\ndetect_3d/compress_to=0\n" % (1 if tex == mat.normal_texture else 2))
			import_file.close()
			print("%s <- %s: %s" % [out, tex.resource_path, error_string(err)])
			if err != OK:
				return false
	return true

func _optimized_path(tex: Texture2D) -> String:
	return "%s/%s" % [OUT_DIR, tex.resource_path.get_file()]

func _phase_two(root: Node) -> bool:
	var k := TARGET_HEIGHT / SOURCE_HEIGHT
	var source_skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var model := Node3D.new()
	model.name = "RemyModelo"
	var skeleton := source_skeleton.duplicate() as Skeleton3D
	for child in skeleton.get_children():
		skeleton.remove_child(child)
		child.free()
	skeleton.transform = Transform3D.IDENTITY
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		rest.origin *= k
		skeleton.set_bone_rest(bone, rest)
	skeleton.reset_bone_poses()
	model.add_child(skeleton)
	skeleton.owner = model
	for source in _meshes(root):
		var mi := MeshInstance3D.new()
		mi.name = source.name
		mi.mesh = _scaled_mesh(source.mesh as ArrayMesh, k)
		mi.mesh.surface_set_material(0, _material(String(source.name), source.mesh.surface_get_material(0) as BaseMaterial3D))
		if source.skin != null:
			var skin := source.skin.duplicate() as Skin
			for i in skin.get_bind_count():
				var bind := skin.get_bind_pose(i)
				bind.origin *= k
				skin.set_bind_pose(i, bind)
			mi.skin = skin
		var look: Dictionary = LOOK.get(String(source.name), {})
		if not bool(look.get("shadow", true)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
		mi.owner = model
		mi.skeleton = NodePath("..")
	var scene := PackedScene.new()
	var err := scene.pack(model)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_SCENE, ResourceSaver.FLAG_COMPRESS)
	var hips := skeleton.find_bone("mixamorig_Hips")
	print("escala %.4f  quadril %.3f m  cena %s: %s" % [k, skeleton.get_bone_rest(hips).origin.y, OUT_SCENE, error_string(err)])
	model.free()
	return err == OK

## Mesh copy with positions (and blend shape positions) multiplied by k.
func _scaled_mesh(source: ArrayMesh, k: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = source.blend_shape_mode
	for i in source.get_blend_shape_count():
		mesh.add_blend_shape(source.get_blend_shape_name(i))
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		arrays[Mesh.ARRAY_VERTEX] = _scaled(arrays[Mesh.ARRAY_VERTEX], k)
		var blends := source.surface_get_blend_shape_arrays(s)
		for b in blends.size():
			var shape: Array = blends[b]
			shape[Mesh.ARRAY_VERTEX] = _scaled(shape[Mesh.ARRAY_VERTEX], k)
		var flags := source.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays, blends, {}, flags)
		mesh.surface_set_name(s, source.surface_get_name(s))
	return mesh

func _scaled(points: PackedVector3Array, k: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = points[i] * k
	return out

func _material(mesh_name: String, source: BaseMaterial3D) -> StandardMaterial3D:
	var look: Dictionary = LOOK.get(mesh_name, {})
	var mat := StandardMaterial3D.new()
	mat.resource_name = "Remy_" + mesh_name
	if source != null:
		mat.albedo_color = source.albedo_color
		if source.albedo_texture != null and ResourceLoader.exists(_optimized_path(source.albedo_texture)):
			mat.albedo_texture = load(_optimized_path(source.albedo_texture))
		if source.normal_texture != null and ResourceLoader.exists(_optimized_path(source.normal_texture)):
			mat.normal_enabled = true
			mat.normal_texture = load(_optimized_path(source.normal_texture))
			mat.normal_scale = 1.0
	mat.roughness = float(look.get("roughness", 0.8))
	mat.metallic_specular = float(look.get("specular", 0.5))
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match int(look.get("alpha", 0)):
		1:
			# Recorte com cobertura por MSAA: fios nítidos, sem erro de ordenação e com sombra.
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.35
			mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		2:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
