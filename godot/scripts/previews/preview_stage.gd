extends RefCounted
## Palco comum das cenas de demonstração (céu, sol, chão com colisão, câmera,
## legenda de teclas) e utilidades de captura de fotos.
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")

static func build(root: Node3D) -> Camera3D:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color("#3d6f95")
	mat.sky_horizon_color = Color("#b8c7cc")
	sky.sky_material = mat
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 40, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	box(root, Vector3(0, -0.25, 0), Vector3(40, 0.5, 40), "concrete", Color("#8a8d86"))
	var camera := Camera3D.new()
	camera.fov = 50
	root.add_child(camera)
	camera.current = true
	return camera

## Bloco visível com colisão na camada do mundo (tiros, raios dos pés).
static func box(root: Node3D, center: Vector3, size: Vector3, kind: String, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = SurfaceMaterials.make(kind, color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	root.add_child(body)
	return body

## Legenda fixa no canto da tela.
static func hint(root: Node, text: String) -> Label:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var label := Label.new()
	label.text = text
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	return label

static func capture_folder() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			return arg.substr(10)
	return ""

static func save_shot(viewport: Viewport, folder: String, file_name: String) -> void:
	viewport.get_texture().get_image().save_png(folder.path_join(file_name + ".png"))

## Osso do Mixamo pelo final do nome ("RightHand" acha "mixamorig9_RightHand").
static func bone(skeleton: Skeleton3D, suffix: String) -> int:
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).ends_with("_" + suffix) or skeleton.get_bone_name(i) == suffix:
			return i
	return -1
