extends RefCounted
const SHADER = preload("res://scripts/survival/lake_water.gdshader")

static func material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	return mat

## Margem em anel: não há um disco opaco sob os vales das ondas.
static func shore_mesh(inner: float, outer: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 64:
		var a := TAU * float(segment) / 64.0
		var b := TAU * float(segment + 1) / 64.0
		var corners := [Vector3(cos(a), 0, sin(a)) * inner, Vector3(cos(b), 0, sin(b)) * inner, Vector3(cos(a), 0, sin(a)) * outer, Vector3(cos(b), 0, sin(b)) * outer]
		for i in [0, 2, 1, 1, 2, 3]:
			var p: Vector3 = corners[i]
			surface.set_normal(Vector3.UP)
			surface.set_uv(Vector2(p.x, p.z) * 0.25)
			surface.add_vertex(p)
	return surface.commit()

## Disco unitário subdividido: uma malha compartilhada por todos os lagos.
static func mesh() -> ArrayMesh:
	const SEGMENTS := 64
	const RINGS := 24
	var vertices := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ONE * 0.5])
	var indices := PackedInt32Array()
	for ring in range(1, RINGS + 1):
		for segment in SEGMENTS:
			var a := TAU * float(segment) / SEGMENTS
			var p := Vector3(cos(a), 0, sin(a)) * float(ring) / RINGS
			vertices.append(p)
			normals.append(Vector3.UP)
			uvs.append(Vector2(p.x, p.z) * 0.5 + Vector2.ONE * 0.5)
			var current := 1 + (ring - 1) * SEGMENTS + segment
			var next := 1 + (ring - 1) * SEGMENTS + (segment + 1) % SEGMENTS
			if ring == 1:
				indices.append_array(PackedInt32Array([0, next, current]))
			else:
				indices.append_array(PackedInt32Array([current - SEGMENTS, next, current, current - SEGMENTS, next - SEGMENTS, next]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
