extends RefCounted
const Hydro = preload("res://scripts/survival/hydrology.gd")
const Hitbox = preload("res://scripts/net/hitbox.gd")
const STEP := 4.0
const CELLS := 28

static func build(parent: Node3D, half_size: float) -> void:
	var extent := ceilf((half_size + 140.0) / (STEP * CELLS)) * STEP * CELLS
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	for cz in range(int(-extent), int(extent), int(STEP * CELLS)):
		for cx in range(int(-extent), int(extent), int(STEP * CELLS)):
			var samples: Array[Vector3] = []
			for z in CELLS + 1:
				for x in CELLS + 1:
					var px := cx + x * STEP
					var pz := cz + z * STEP
					samples.append(Vector3(px, Hydro.ground_height(px, pz), pz))
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in CELLS:
				for x in CELLS:
					var a := z * (CELLS + 1) + x
					for index in [a, a + 1, a + CELLS + 1, a + 1, a + CELLS + 2, a + CELLS + 1]:
						var p := samples[index]
						var color := Color("#5d7a4e")
						if p.y < -0.2 or maxf(absf(p.x), absf(p.z)) > half_size - 2: color = Color("#b3a177")
						elif p.y > 8: color = Color("#737964")
						surface.set_color(color)
						surface.set_uv(Vector2(p.x, p.z) * 0.1)
						surface.add_vertex(p)
			surface.generate_normals()
			var mesh := surface.commit()
			var body := StaticBody3D.new()
			body.name = "IslandTerrain"
			body.collision_layer = Hitbox.LAYER_WORLD
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.material_override = material
			visual.set_meta("preserve_authored_material", true)
			body.add_child(visual)
			var collision := CollisionShape3D.new()
			collision.shape = mesh.create_trimesh_shape()
			body.add_child(collision)
			parent.add_child(body)
