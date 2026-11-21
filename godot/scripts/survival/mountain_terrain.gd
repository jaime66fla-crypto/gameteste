extends RefCounted
## Encostas suaves na extensão do mapa. A fórmula também existe no servidor.
const Hitbox = preload("res://scripts/net/hitbox.gd")
const STEPS := 32

static func height_at(point: Vector3, mountains: Array) -> float:
	var height := 0.0
	for m in mountains:
		var distance := Vector2(point.x - float(m.x), point.z - float(m.z)).length()
		var radius := float(m.r)
		if distance < radius:
			height = maxf(height, float(m.h) * 0.5 * (1.0 + cos(PI * distance / radius)))
	return height

static func build(parent: Node3D, mountains: Array) -> void:
	for m in mountains:
		var radius := float(m.r)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for z in STEPS:
			for x in STEPS:
				var corners: Array[Vector3] = []
				for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var point := Vector3(float(m.x) - radius + (x + offset.x) * radius * 2.0 / STEPS, 0, float(m.z) - radius + (z + offset.y) * radius * 2.0 / STEPS)
					point.y = height_at(point, [m])
					corners.append(point)
				if corners[0].y + corners[1].y + corners[2].y + corners[3].y < 0.01:
					continue # Não desenhar um quadrado coplanar com o chão.
				for index in [0, 1, 2, 1, 3, 2]:
					var point := corners[index]
					point.y = maxf(0.025, point.y)
					var rock := smoothstep(float(m.h) * 0.35, float(m.h) * 0.85, point.y)
					surface.set_color(Color("526441").lerp(Color("89867d"), rock))
					surface.set_uv(Vector2(point.x, point.z) * 0.1)
					surface.add_vertex(point)
		surface.generate_normals()
		var mesh := surface.commit()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		var body := StaticBody3D.new()
		body.name = "Mountain"
		body.collision_layer = Hitbox.LAYER_WORLD
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = material
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		collision.shape = mesh.create_trimesh_shape()
		body.add_child(collision)
		parent.add_child(body)
