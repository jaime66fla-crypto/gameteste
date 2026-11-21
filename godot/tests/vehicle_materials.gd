extends SceneTree
func _initialize() -> void:
	var cars = load("res://scripts/survival/car_model.gd")
	var model = cars.build("pickup", "#d8d4cc", false, 1)
	var body: MeshInstance3D = model.get_node("Body")
	var paint: StandardMaterial3D = body.mesh.surface_get_material(0)
	var errors := 0
	if not body.get_meta("preserve_authored_material", false):
		printerr("FAIL: vehicle paint is replaced by the global toon and outline pass")
		errors += 1
	if paint.metallic > 0.25:
		printerr("FAIL: paint loses its diffuse color in the night scene without sky reflections")
		errors += 1
	for i in body.mesh.get_surface_count():
		var arrays: Array = body.mesh.surface_get_arrays(i)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for j in range(0, vertices.size(), 3):
			var face := (vertices[j+2]-vertices[j]).cross(vertices[j+1]-vertices[j]).normalized()
			if face.length_squared() > 0.1 and face.dot(normals[j]) < 0.99:
				errors += 1
	model.free()
	print("VEHICLE MATERIALS failures: ", errors)
	quit(1 if errors else 0)
