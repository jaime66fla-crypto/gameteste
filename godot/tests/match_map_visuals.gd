extends SceneTree
## Focused regression: online maps retain their authored textures and lighting
## after the shared cel adapter runs; geometry and player styling stay intact.
const Layout = preload("res://scripts/net/match_layout.gd")
const MatchMap = preload("res://scripts/match_map.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _run() -> void:
	var cel_style = load("res://scripts/cel_style.gd")
	var previous_map := Layout.map_id
	for id in Layout.map_ids():
		Layout.use_map(str(id))
		var scene := Node3D.new()
		root.add_child(scene)
		var world := WorldEnvironment.new()
		world.name = "WorldEnvironment"
		world.environment = Environment.new()
		scene.add_child(world)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		scene.add_child(sun)
		var map := MatchMap.new()
		scene.add_child(map)
		var authored_sky := world.environment.sky
		var authored_ambient := world.environment.ambient_light_energy
		var authored_sun := sun.light_energy
		var originals: Dictionary = {}
		for node in map.get_children():
			if node is MeshInstance3D:
				originals[node.name] = node.material_override
		check(not originals.is_empty(), str(id) + ": surface batches exist")
		var collision := map.get_node("MapCollision")
		var collider_count := collision.get_child_count()
		check(collider_count == Layout.load_layout().get("parts", []).size() + 1, str(id) + ": original block colliders")
		scene.add_child(cel_style.new())
		# Check the deferred node-added path as well as the initial branch pass.
		await process_frame
		await process_frame
		for node in map.get_children():
			if node is MeshInstance3D:
				var material: StandardMaterial3D = node.material_override
				check(material == originals[node.name], str(id) + "/" + str(node.name) + ": authored material retained")
				check(material.albedo_texture != null, str(id) + "/" + str(node.name) + ": visible surface texture")
				check(material.normal_enabled and material.normal_texture != null, str(id) + "/" + str(node.name) + ": surface relief")
				# Gráfico do Linha de Fogo: rugosidade fixa por superfície (sem mapa de rugosidade).
				check(material.roughness_texture != null or material.roughness < 1.0, str(id) + "/" + str(node.name) + ": roughness retained")
				check(material.next_pass == null, str(id) + "/" + str(node.name) + ": no additional render pass")
		check(world.environment.sky == authored_sky, str(id) + ": authored sky retained")
		check(is_equal_approx(world.environment.ambient_light_energy, authored_ambient), str(id) + ": ambient lighting retained")
		check(is_equal_approx(sun.light_energy, authored_sun), str(id) + ": sunlight retained")
		check(collision.get_child_count() == collider_count, str(id) + ": collisions unchanged by styling")
		var prop := MeshInstance3D.new()
		prop.mesh = BoxMesh.new()
		prop.material_override = StandardMaterial3D.new()
		scene.add_child(prop)
		await process_frame
		await process_frame
		check(prop.material_override.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, str(id) + ": other objects retain cel styling")
		scene.free()
	Layout.use_map(previous_map)
	for message in failures.slice(0, 8):
		printerr(message)
	print("MATCH MAP VISUALS: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
