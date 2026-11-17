extends SceneTree
## Gera o zumbi otimizado a partir do FBX original (assets/personagens/zumbi/zumbi.fbx,
## 105 MB, texturas 4K, fica só no seu PC):
##   fase 1: reduz as texturas de cor e relevo para 1024 px (otimizado/*.png)
##   (rode --import entre as fases)
##   fase 2: salva malha + esqueleto + materiais novos em zumbi_modelo.scn (poucos MB)
## godot --headless --path godot --script res://tools/characters/build_zombie_model.gd -- --phase=1
## godot --headless --path godot --import
## godot --headless --path godot --script res://tools/characters/build_zombie_model.gd -- --phase=2
const SOURCE := "res://assets/personagens/zumbi/zumbi.fbx"
const OUT_DIR := "res://assets/personagens/zumbi/otimizado"
const OUT_SCENE := "res://assets/personagens/zumbi/zumbi_modelo.scn"
const SIZE := 1024

func _initialize() -> void:
	var phase := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			phase = int(arg.substr(8))
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		print("FBX não encontrado: " + SOURCE)
		quit(1)
		return
	var root := packed.instantiate()
	var mesh_node := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	if phase == 1:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		for s in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.mesh.surface_get_material(s) as StandardMaterial3D
			for spec in [["albedo", mat.albedo_texture], ["normal", mat.normal_texture if mat.normal_enabled else null]]:
				var tex: Texture2D = spec[1]
				if tex == null:
					continue
				var image := tex.get_image()
				if image.is_compressed():
					image.decompress()
				image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
				var path := "%s/zumbi_%d_%s.png" % [OUT_DIR, s, spec[0]]
				image.save_png(ProjectSettings.globalize_path(path))
				print("salvo " + path)
		root.free()
		quit(0)
		return
	# Fase 2: cena independente do FBX.
	var skeleton := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var model := Node3D.new()
	model.name = "ZumbiModelo"
	var sk := skeleton.duplicate() as Skeleton3D
	for child in sk.get_children():
		sk.remove_child(child)
		child.free()
	model.add_child(sk)
	sk.owner = model
	var mesh := mesh_node.mesh.duplicate() as ArrayMesh
	for s in mesh.get_surface_count():
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("%s/zumbi_%d_albedo.png" % [OUT_DIR, s])
		var normal_path := "%s/zumbi_%d_normal.png" % [OUT_DIR, s]
		if ResourceLoader.exists(normal_path):
			mat.normal_enabled = true
			mat.normal_texture = load(normal_path)
			mat.normal_scale = 0.9
		mat.roughness = 0.85
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mesh.surface_set_material(s, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Corpo"
	mi.mesh = mesh
	mi.skin = mesh_node.skin.duplicate() if mesh_node.skin != null else null
	sk.add_child(mi)
	mi.owner = model
	mi.skeleton = NodePath("..")
	var scene := PackedScene.new()
	var err := scene.pack(model)
	if err == OK:
		err = ResourceSaver.save(scene, OUT_SCENE, ResourceSaver.FLAG_COMPRESS)
	print("cena %s: %s" % [OUT_SCENE, error_string(err)])
	root.free()
	model.free()
	quit(0 if err == OK else 1)
