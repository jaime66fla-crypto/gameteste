extends RefCounted
## Árvores, toco, pedra e arbusto procedurais para a Sobrevivência.
## Cada modelo é uma ArrayMesh (casca + folhas) desenhada em lote por
## MultiMesh: centenas de árvores custam poucas chamadas de desenho.
## Cores por vértice (tronco mais escuro embaixo, copa mais clara em cima,
## sombra por baixo dos galhos) por cima das texturas de SurfaceMaterials.
## Cada tipo tem versão "perto" (detalhada) e "longe" (poucos triângulos).
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")

const TREE_VARIANTS := ["pine_a", "pine_b", "oak_a", "oak_b", "birch"]

static var _cache: Dictionary = {}
static var _bark: StandardMaterial3D
static var _leaf: StandardMaterial3D

static func bark_material() -> StandardMaterial3D:
	if _bark == null:
		_bark = SurfaceMaterials.make("bark", Color.WHITE).duplicate() as StandardMaterial3D
		_bark.vertex_color_use_as_albedo = true
	return _bark

static func leaf_material() -> StandardMaterial3D:
	if _leaf == null:
		_leaf = SurfaceMaterials.make("leaf", Color.WHITE).duplicate() as StandardMaterial3D
		_leaf.vertex_color_use_as_albedo = true
		_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _leaf

## Modelo pelo nome ("pine_a", "oak_b", "stump", "rock", "bush_full"...); `far` = versão leve.
static func mesh(variant: String, far: bool = false) -> ArrayMesh:
	var key := variant + ("_far" if far else "")
	if not _cache.has(key):
		_cache[key] = _build(variant, far)
	return _cache[key]

static func _build(variant: String, far: bool) -> ArrayMesh:
	var bark := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = variant.hash()
	match variant:
		"pine_a": _pine(bark, leaf, rng, 10.5, 2.4, 8, far)
		"pine_b": _pine(bark, leaf, rng, 8.0, 2.0, 6, far)
		"oak_a": _oak(bark, leaf, rng, 3.4, 4, far, Color("#3f6a2e"))
		"oak_b": _oak(bark, leaf, rng, 2.8, 3, far, Color("#56772f"))
		"birch": _birch(bark, leaf, rng, far)
		"stump": _stump(bark, rng)
		"rock": _rock(bark, rng, far)
		"bush_full": _bush(leaf, bark, rng, true)
		"bush_empty": _bush(leaf, bark, rng, false)
	var out := ArrayMesh.new()
	for pair in [[bark, bark_material()], [leaf, leaf_material()]]:
		var st: SurfaceTool = pair[0]
		var arrays := st.commit_to_arrays()
		var verts = arrays[Mesh.ARRAY_VERTEX]
		if verts == null or (verts as PackedVector3Array).is_empty():
			continue
		st.generate_normals()
		out = st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, pair[1])
	return out

# ---------------------------------------------------------------- formas ---

## Triângulo com a frente para fora no sentido anti-horário (Godot usa horário).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cc)
	st.add_vertex(c)
	st.set_color(cb)
	st.add_vertex(b)

static func _frame(dir: Vector3) -> Array:
	var ref := Vector3.FORWARD if absf(dir.y) > 0.9 else Vector3.UP
	var x := dir.cross(ref).normalized()
	var z := x.cross(dir).normalized()
	return [x, z]

## Tubo afinando pelos pontos (tronco, galhos). Cores de baixo para cima.
static func _tube(st: SurfaceTool, points: Array, radii: Array, segs: int, bottom: Color, top: Color, rng: RandomNumberGenerator, bands: bool = false) -> void:
	var rings: Array = []
	var colors: Array = []
	for i in points.size():
		var dir: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var f := _frame(dir)
		var ring: Array = []
		for s in segs:
			var a := -TAU * s / segs # sentido que deixa a frente das faces para fora
			var wobble := 1.0 + rng.randf_range(-0.08, 0.08)
			ring.append(points[i] + (f[0] * cos(a) + f[1] * sin(a)) * float(radii[i]) * wobble)
		rings.append(ring)
		var c := bottom.lerp(top, float(i) / maxf(1.0, points.size() - 1.0))
		if bands and rng.randf() < 0.45:
			c = c.darkened(rng.randf_range(0.45, 0.7)) # marcas escuras da bétula
		colors.append(c)
	for i in points.size() - 1:
		for s in segs:
			var n := (s + 1) % segs
			var a: Vector3 = rings[i][s]
			var b: Vector3 = rings[i][n]
			var c: Vector3 = rings[i + 1][n]
			var d: Vector3 = rings[i + 1][s]
			_tri(st, a, b, c, colors[i], colors[i], colors[i + 1])
			_tri(st, a, c, d, colors[i], colors[i + 1], colors[i + 1])

## Pinheiro: tronco reto e camadas de galhos em "saia", pontas recortadas e caídas.
static func _pine(bark: SurfaceTool, leaf: SurfaceTool, rng: RandomNumberGenerator, height: float, spread: float, tiers: int, far: bool) -> void:
	var trunk_pts: Array = []
	var trunk_r: Array = []
	var steps := 3 if far else 6
	for i in steps + 1:
		var t := float(i) / steps
		trunk_pts.append(Vector3(rng.randf_range(-0.04, 0.04) * t * height * 0.1, t * height * 0.93, 0))
		trunk_r.append(lerpf(0.3, 0.04, t) * (1.25 if i == 0 else 1.0))
	_tube(bark, trunk_pts, trunk_r, 5 if far else 8, Color("#4a382a"), Color("#7a5a40"), rng)
	var count := 3 if far else tiers
	var points := 7 if far else 12
	var dark := Color("#1f3a22")
	var mid := Color("#2f5530")
	var light := Color("#5b8048")
	for i in count:
		var t := float(i) / count
		var base_y := height * (0.22 + 0.68 * t)
		var radius := spread * pow(1.0 - t, 0.85) + 0.35
		var tier_h := height * 0.68 / count * 1.9
		var apex := Vector3(0, base_y + tier_h, 0)
		var under := Vector3(0, base_y + tier_h * 0.28, 0)
		var ring: Array = []
		for p in points:
			var a := TAU * p / points + rng.randf_range(-0.12, 0.12) + i * 0.7
			var tip := p % 2 == 0
			var r := radius * (rng.randf_range(0.9, 1.08) if tip else rng.randf_range(0.62, 0.75))
			var droop := radius * (0.32 if tip else 0.12)
			ring.append(Vector3(cos(a) * r, base_y - droop + rng.randf_range(-0.08, 0.08), sin(a) * r))
		var top_color := light.lerp(mid, 0.4 - t * 0.3)
		for p in points:
			var a: Vector3 = ring[p]
			var b: Vector3 = ring[(p + 1) % points]
			_tri(leaf, b, a, apex, mid, mid, top_color)
			_tri(leaf, a, b, under, dark, dark, dark.darkened(0.3))

## Árvore de copa larga: tronco curvo, galhos abertos e tufos de folhas irregulares.
static func _oak(bark: SurfaceTool, leaf: SurfaceTool, rng: RandomNumberGenerator, trunk_h: float, branches: int, far: bool, green: Color) -> void:
	var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
	var trunk_pts: Array = [Vector3.ZERO, Vector3(0, trunk_h * 0.4, 0) + lean * 0.3, Vector3(0, trunk_h * 0.75, 0) + lean * 0.7, Vector3(0, trunk_h, 0) + lean]
	var trunk_r: Array = [0.42, 0.3, 0.26, 0.22]
	_tube(bark, trunk_pts, trunk_r, 5 if far else 9, Color("#3d3024"), Color("#5e4a36"), rng)
	var top: Vector3 = trunk_pts[3]
	var blobs: Array = [[top + Vector3(0, 1.6, 0), 2.3]]
	for b in branches:
		var a := TAU * b / branches + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var from: Vector3 = trunk_pts[2].lerp(top, rng.randf())
		var length := rng.randf_range(2.0, 2.8)
		var end := from + (out * 0.8 + Vector3.UP * 0.75).normalized() * length
		if not far:
			var mid := from.lerp(end, 0.5) + Vector3.UP * 0.25
			_tube(bark, [from, mid, end], [0.16, 0.11, 0.06], 6, Color("#4a3a2b"), Color("#5e4a36"), rng)
		blobs.append([end + Vector3(0, 0.4, 0), rng.randf_range(1.5, 2.0)])
	if not far:
		# Tufos menores entre os grandes, para a copa não parecer bolas soltas.
		for i in branches:
			var a := TAU * (i + 0.5) / branches
			blobs.append([top + Vector3(cos(a) * 1.6, 1.0 + rng.randf_range(0.0, 1.2), sin(a) * 1.6), rng.randf_range(1.2, 1.6)])
	for blob in blobs:
		var tone := green.lerp(Color("#6d8a3a"), rng.randf_range(0.0, 0.35))
		_blob(leaf, blob[0], float(blob[1]), rng, 0 if far else 1, tone, 0.8)

## Bétula: tronco fino e branco com marcas escuras, copa alta e estreita.
static func _birch(bark: SurfaceTool, leaf: SurfaceTool, rng: RandomNumberGenerator, far: bool) -> void:
	var height := 8.5
	var pts: Array = []
	var radii: Array = []
	var steps := 3 if far else 9
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector3(sin(t * 2.6) * 0.25, t * height, cos(t * 1.9) * 0.15 - 0.15))
		radii.append(lerpf(0.17, 0.05, t))
	_tube(bark, pts, radii, 5 if far else 7, Color("#d8d4c8"), Color("#ebe7dc"), rng, not far)
	var n := 2 if far else 6
	for i in n:
		var t := 0.45 + 0.5 * float(i) / maxf(1.0, n - 1.0)
		var at: Vector3 = pts[int(t * steps)]
		var a := rng.randf() * TAU
		var offset := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.3, 0.8)
		var tone := Color("#6f9440").lerp(Color("#93a84a"), rng.randf())
		_blob(leaf, at + offset + Vector3(0, 0.4, 0), rng.randf_range(1.0, 1.5) * (1.4 if far else 1.0), rng, 0 if far else 1, tone, 1.25)

## Toco da árvore cortada: casca por fora, madeira clara no corte.
static func _stump(bark: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var pts: Array = [Vector3.ZERO, Vector3(0, 0.25, 0), Vector3(0, 0.55, 0)]
	_tube(bark, pts, [0.42, 0.33, 0.3], 9, Color("#3d3024"), Color("#5e4a36"), rng)
	var top := Vector3(0, 0.55, 0)
	var ring: Array = []
	for s in 9:
		var a := TAU * s / 9
		ring.append(top + Vector3(cos(a), 0, sin(a)) * 0.29)
	var wood := Color("#c9a978")
	for s in 9:
		_tri(bark, ring[(s + 1) % 9], ring[s], top + Vector3(0, 0.02, 0), wood.darkened(0.15), wood.darkened(0.15), wood)

## Pedra: esfera facetada amassada, achatada e com veios de cor.
static func _rock(st: SurfaceTool, rng: RandomNumberGenerator, far: bool) -> void:
	var verts := _icosphere(0 if far else 1)
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 1.4
	var shaped: Array = []
	for v in verts:
		var p: Vector3 = v
		var r := 1.0 + noise.get_noise_3dv(p) * 0.28
		shaped.append(Vector3(p.x * 1.3 * r, maxf(p.y * 0.75 * r, -0.25) + 0.25, p.z * 1.0 * r))
	for i in range(0, shaped.size(), 3):
		var cols: Array = []
		for k in 3:
			var p: Vector3 = shaped[i + k]
			var g := 0.42 + clampf(p.y, 0.0, 1.0) * 0.12 + noise.get_noise_3dv(p * 3.0) * 0.06
			cols.append(Color(g, g * 0.99, g * 0.95))
		_tri(st, shaped[i], shaped[i + 1], shaped[i + 2], cols[0], cols[1], cols[2])

## Arbusto: três tufos e, se tiver, frutinhas vermelhas.
static func _bush(leaf: SurfaceTool, fruit: SurfaceTool, rng: RandomNumberGenerator, berries: bool) -> void:
	var tone := Color("#46702f")
	for spot in [[Vector3(0, 0.55, 0), 0.75], [Vector3(0.45, 0.45, 0.2), 0.55], [Vector3(-0.4, 0.42, -0.15), 0.55]]:
		_blob(leaf, spot[0], spot[1], rng, 1, tone.lerp(Color("#5d8236"), rng.randf()), 0.85)
	if not berries:
		return
	var red := Color("#b3261e")
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		var p := Vector3(cos(a) * 0.68, 0.45 + rng.randf_range(0.0, 0.45), sin(a) * 0.62)
		var s := 0.07
		_tri(fruit, p + Vector3(0, s, 0), p + Vector3(s, -s, 0), p + Vector3(-s, -s, s), red, red.darkened(0.3), red)
		_tri(fruit, p + Vector3(0, s, 0), p + Vector3(-s, -s, s), p + Vector3(-s, -s, -s), red, red, red.darkened(0.3))
		_tri(fruit, p + Vector3(0, s, 0), p + Vector3(-s, -s, -s), p + Vector3(s, -s, 0), red, red.darkened(0.3), red)

## Tufo de folhas: esfera facetada com o contorno irregular, escura por baixo.
static func _blob(st: SurfaceTool, center: Vector3, radius: float, rng: RandomNumberGenerator, detail: int, tone: Color, squash: float) -> void:
	var verts := _icosphere(detail)
	var bumps := {}
	var shaped: Array = []
	for v in verts:
		var p: Vector3 = v
		var key := p.snapped(Vector3.ONE * 0.001)
		if not bumps.has(key):
			bumps[key] = rng.randf_range(0.78, 1.15)
		var q := p * radius * float(bumps[key])
		q.y *= squash
		shaped.append(center + q)
	for i in range(0, shaped.size(), 3):
		var cols: Array = []
		for k in 3:
			var h := (verts[i + k] as Vector3).y # -1 embaixo, +1 em cima
			cols.append(tone.darkened(0.45 - h * 0.25) if h < 0.0 else tone.lightened(h * 0.22))
		_tri(st, shaped[i], shaped[i + 1], shaped[i + 2], cols[0], cols[1], cols[2])

## Icosfera (lista de triângulos, raio 1, anti-horário visto de fora).
static func _icosphere(detail: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var p: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris: Array = []
	for f in faces:
		tris.append([(p[f[0]] as Vector3).normalized(), (p[f[1]] as Vector3).normalized(), (p[f[2]] as Vector3).normalized()])
	for d in detail:
		var next: Array = []
		for tri in tris:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			next.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		tris = next
	var out: Array = []
	for tri in tris:
		# Faces do icosaedro vêm no sentido anti-horário visto de fora.
		out.append_array(tri)
	return out
