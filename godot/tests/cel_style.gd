extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/cel_style.gd"):
		printerr("CEL STYLE FAIL: missing runtime cel style adapter")
		quit(1)
		return
	var style = load("res://scripts/cel_style.gd").new()
	var source := StandardMaterial3D.new()
	source.albedo_color = Color("#637350")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.albedo_texture = ImageTexture.create_from_image(image)
	var toon: StandardMaterial3D = style.material_for(source, 0.012)
	check(toon != source, "imported source must remain unchanged")
	check(source.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON and source.next_pass == null, "source must not receive style changes")
	check(toon.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, "opaque material uses toon diffuse")
	check(toon.albedo_texture == source.albedo_texture, "avatar color texture preserved")
	check(toon.next_pass != null and toon.next_pass.cull_mode == BaseMaterial3D.CULL_FRONT, "opaque mesh gets an inverted hull outline")
	check(style.material_for(source, 0.012) == toon, "shared source reuses cached styled material")
	check(style.material_for(toon, 0.012) == toon, "conversion is idempotent")
	var map := StandardMaterial3D.new()
	map.resource_name = "map_grass"
	map.albedo_texture = source.albedo_texture
	var grass: StandardMaterial3D = style.material_for(map, 0.0)
	check(grass.albedo_texture == null and grass.albedo_color.g > grass.albedo_color.r, "map grass replaces photo with green palette")
	check(grass.next_pass == null, "flat ground gets no hull")
	for transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
		var transparent := StandardMaterial3D.new()
		transparent.transparency = transparency
		check(style.material_for(transparent, 0.012) == transparent, "transparency and leaf cutouts remain intact")
	var effect := StandardMaterial3D.new()
	effect.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	check(style.material_for(effect, 0.012) == effect, "unshaded effects stay intact")
	var shader := ShaderMaterial.new()
	check(style.material_for(shader, 0.012) == shader, "custom shaders stay intact")
	var scene := Node3D.new()
	root.add_child(scene)
	scene.add_child(style)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = source
	scene.add_child(mesh)
	await process_frame
	await process_frame
	check(mesh.material_override != source, "newly spawned mesh gets styled")
	check(mesh.material_override.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, "spawned mesh uses toon shading")
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = load("res://scripts/survival/nature_model.gd").mesh("oak_a", 0)
	batch.multimesh.instance_count = 1
	batch.multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	var original_mesh := batch.multimesh.mesh
	var original_bark := original_mesh.surface_get_material(0)
	scene.add_child(batch)
	await process_frame
	await process_frame
	check(batch.multimesh.mesh.surface_get_material(0).diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, "batched trees use toon shading")
	check(batch.multimesh.mesh.surface_get_material(0).albedo_texture == null, "batched bark loses photographic grain")
	check(original_mesh.surface_get_material(0) == original_bark and original_bark.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON, "shared original nature mesh stays unchanged")
	var target = load("res://scripts/training_target.gd").new()
	scene.add_child(target)
	await process_frame
	await process_frame
	target.take_damage(1.0)
	target._process(0.01)
	check(target._mesh.material_override.emission_enabled, "training target keeps visible hit feedback")
	var cache_size: int = style._materials.size()
	for index in 20:
		var disposable := StandardMaterial3D.new()
		var styled: Material = style.material_for(disposable, 0.012)
		styled = null
	style._prune(style._materials)
	check(style._materials.size() <= cache_size, "removed objects do not retain material cache entries")
	scene.free()
	for message in failures:
		printerr(message)
	print("CEL STYLE: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
