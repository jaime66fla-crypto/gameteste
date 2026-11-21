extends RefCounted
## Carro procedural "o mais real possível" sem arquivos externos: carroceria
## pelo perfil lateral (capô, para-brisa inclinado, teto, porta-malas, caixas
## de roda), cabine de vidro com colunas, para-choques, faróis, lanternas,
## grade, retrovisores, linhas das portas, maçanetas, placa e rodas com pneu,
## aro e calota. Pintura metálica com sujeira embaixo; versão abandonada com
## ferrugem, vidros quebrados e pneu murcho.
##
## Tudo de um carro vira uma única ArrayMesh (uma superfície por material),
## guardada em cache por modelo/cor/estado: 100+ carros no mapa custam pouco.
## A frente é -Z, o chão é y = 0.

const KINDS := {
	# l: comprimento, w: largura, wb: entre-eixos, r: raio da roda,
	# belt: linha da cintura, roof: altura do teto, hood: altura do capô na frente,
	# deck: altura do porta-malas, ws/rf/rb/rw: z da base do para-brisa, frente
	# do teto, fim do teto, base do vidro traseiro.
	"sedan": {"l": 4.55, "w": 1.80, "wb": 2.70, "r": 0.33, "belt": 0.98, "roof": 1.44, "hood": 0.82, "deck": 0.96, "ws": -0.95, "rf": -0.25, "rb": 0.80, "rw": 1.42},
	"hatch": {"l": 3.95, "w": 1.74, "wb": 2.50, "r": 0.31, "belt": 0.97, "roof": 1.46, "hood": 0.80, "deck": 1.00, "ws": -0.80, "rf": -0.15, "rb": 1.30, "rw": 1.72},
	"pickup": {"l": 5.10, "w": 1.86, "wb": 3.10, "r": 0.38, "belt": 1.12, "roof": 1.78, "hood": 1.00, "deck": 0.86, "ws": -1.05, "rf": -0.55, "rb": 0.30, "rw": 0.40, "bed": true},
}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

## Nó pronto: "Body" (carroceria inteira) e 4 rodas "Wheel_FL/FR/RL/RR"
## (giram ao dirigir). `wreck` = carro abandonado (sucata).
static func build(kind: String, color_hex: String, wreck: bool, seed_value: int = 0) -> Node3D:
	var spec: Dictionary = KINDS.get(kind, KINDS["sedan"])
	var root := Node3D.new()
	root.name = "CarModel"
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.set_meta("preserve_authored_material", true)
	body.mesh = _body_mesh(kind, color_hex, wreck, seed_value % 3)
	root.add_child(body)
	var half_wb := float(spec["wb"]) * 0.5
	var r := float(spec["r"])
	var x := float(spec["w"]) * 0.5 - 0.13
	var wheels := {"FL": Vector3(-x, r, -half_wb), "FR": Vector3(x, r, -half_wb), "RL": Vector3(-x, r, half_wb), "RR": Vector3(x, r, half_wb)}
	var index := 0
	for key in wheels:
		index += 1
		if wreck and (seed_value + index) % 7 == 0:
			continue # roda roubada
		var pivot := Node3D.new()
		pivot.name = "Wheel_" + key
		pivot.position = wheels[key]
		root.add_child(pivot)
		var wheel := MeshInstance3D.new()
		wheel.name = "Tire"
		wheel.set_meta("preserve_authored_material", true)
		wheel.mesh = _wheel_mesh(r, wreck)
		wheel.rotation.y = PI if key.ends_with("L") else 0.0
		pivot.add_child(wheel)
		if wreck and (seed_value + index) % 3 == 0:
			pivot.position.y -= r * 0.28 # pneu murcho
			pivot.scale = Vector3(1, 0.75, 1)
	return root

## Níveis de detalhe pela distância: rodas até `wheels_end`, carroceria até
## `body_end` e, dali até `proxy_end` (0 = sem fim), um bloco só na cor do
## carro no lugar da carroceria de várias superfícies e das 4 rodas.
static func apply_lod(model: Node3D, kind: String, color_hex: String, wheels_end: float, body_end: float, proxy_end: float, margin: float = 6.0) -> void:
	for node in model.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		var is_body := g.name == "Body"
		g.visibility_range_end = body_end if is_body else wheels_end
		g.visibility_range_end_margin = margin
		if not is_body:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spec: Dictionary = KINDS.get(kind, KINDS["sedan"])
	var proxy := MeshInstance3D.new()
	proxy.name = "FarProxy"
	proxy.set_meta("preserve_authored_material", true)
	var box := BoxMesh.new()
	box.size = Vector3(float(spec["w"]), float(spec["roof"]) * 0.82, float(spec["l"]) * 0.96)
	proxy.mesh = box
	proxy.position.y = float(spec["roof"]) * 0.45
	var key := "proxy" + color_hex
	if not _mat_cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color_hex).darkened(0.15)
		mat.roughness = 0.6
		_mat_cache[key] = mat
	proxy.material_override = _mat_cache[key]
	proxy.set_meta("paint", _mat_cache[key]) # quem troca o material (carro queimado) volta para este
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	proxy.visibility_range_begin = body_end
	proxy.visibility_range_begin_margin = margin
	proxy.visibility_range_end = proxy_end
	proxy.visibility_range_end_margin = margin if proxy_end > 0.0 else 0.0
	model.add_child(proxy)

## Dimensões para a colisão.
static func size_of(kind: String) -> Vector3:
	var spec: Dictionary = KINDS.get(kind, KINDS["sedan"])
	return Vector3(float(spec["w"]), float(spec["roof"]), float(spec["l"]))

# ------------------------------------------------------------- materiais ---

static func _paint_texture(color: Color, wreck: bool, variant: int) -> ImageTexture:
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 31 + variant * 17
	noise.frequency = 0.045
	var fine := FastNoiseLite.new()
	fine.seed = 7 + variant
	fine.frequency = 0.35
	var rust := Color("#7a3d1c")
	var rust_dark := Color("#3e2414")
	for y in size:
		for x in size:
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var f := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var c := color.lerp(color.lightened(0.08), f * 0.25)
			if wreck:
				c = c.lerp(c.darkened(0.25), 0.35) # tinta desbotada
				c = c.lerp(Color(0.55, 0.52, 0.45), 0.18) # poeira
				if n > 0.62:
					c = c.lerp(rust.lerp(rust_dark, f), clampf((n - 0.62) * 6.0, 0.0, 1.0))
			image.set_pixel(x, y, c)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func _material(key: String, maker: Callable) -> Material:
	if not _mat_cache.has(key):
		_mat_cache[key] = maker.call()
	return _mat_cache[key]

static func _paint(color_hex: String, wreck: bool, variant: int) -> Material:
	return _material("paint%s%s%d" % [color_hex, wreck, variant], func():
		var m := StandardMaterial3D.new()
		m.albedo_texture = _paint_texture(Color(color_hex), wreck, variant)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.6, 0.6, 0.6)
		m.vertex_color_use_as_albedo = true # sujeira embaixo (cor por vértice)
		m.metallic = 0.05 if wreck else 0.12
		m.roughness = 0.82 if wreck else 0.48
		m.metallic_specular = 0.6
		if not wreck:
			m.clearcoat_enabled = true
			m.clearcoat = 0.25
			m.clearcoat_roughness = 0.3
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		return m)

static func _simple(key: String, color: Color, metallic: float, roughness: float, alpha: float = 1.0, emission: Color = Color.BLACK) -> Material:
	return _material(key, func():
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color.r, color.g, color.b, alpha)
		m.metallic = metallic
		m.roughness = roughness
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if emission != Color.BLACK:
			m.emission_enabled = true
			m.emission = emission
			m.emission_energy_multiplier = 0.6
		return m)

## Faróis acesos (motor ligado): material separado para trocar na hora.
static func headlight_material(on: bool) -> Material:
	return _simple("headlight%s" % on, Color("#f4f1e4"), 0.2, 0.08, 1.0, Color("#fff6d8") if on else Color.BLACK)

static func taillight_material(on: bool) -> Material:
	return _simple("taillight%s" % on, Color("#a3150f"), 0.1, 0.15, 1.0, Color("#ff2a1a") if on else Color("#3a0503"))

# ------------------------------------------------------------- geometria ---

class Builder:
	var tools: Dictionary = {} # nome do material -> SurfaceTool
	var materials: Dictionary = {}
	var bottom := 0.0
	var top := 1.5

	func st(name: String, material: Material) -> SurfaceTool:
		if not tools.has(name):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[name] = tool
			materials[name] = material
		return tools[name]

	## Sujeira: mais escuro perto do chão.
	func dirt(y: float) -> Color:
		var t := clampf((y - bottom) / maxf(top - bottom, 0.01), 0.0, 1.0)
		return Color(0.55, 0.5, 0.45).lerp(Color.WHITE, smoothstep(0.0, 0.55, t))

	## `a, b, c` em sentido anti-horário visto de fora (normal pela regra da mão
	## direita); o Godot quer horário para a face da frente, então grava a, c, b.
	func tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		for v in [a, c, b]:
			tool.set_normal(n)
			tool.set_color(dirt(v.y))
			tool.add_vertex(v)

	func quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		tri(tool, a, b, c)
		tri(tool, a, c, d)

	## Caixa orientada: centro, tamanho e base (rotação).
	func box(tool: SurfaceTool, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
		var h := size * 0.5
		var p := func(x: float, y: float, z: float) -> Vector3: return center + basis * Vector3(x * h.x, y * h.y, z * h.z)
		quad(tool, p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1)) # +Z
		quad(tool, p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1)) # -Z
		quad(tool, p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1)) # +X
		quad(tool, p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1)) # -X
		quad(tool, p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1)) # +Y
		quad(tool, p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1)) # -Y

	## Extrusão de um perfil lateral (pontos (z, y)) entre x0 e x1, com chanfro
	## nas bordas: as faces laterais ficam `bevel` para dentro e a borda inclinada.
	func extrude(tool: SurfaceTool, profile: PackedVector2Array, x0: float, x1: float, bevel: float = 0.0) -> void:
		var inner := _inset(profile, bevel)
		var ids := Geometry2D.triangulate_polygon(inner)
		for side in [x0, x1]:
			var sx: float = side
			for i in range(0, ids.size(), 3):
				var a := Vector3(sx, inner[ids[i]].y, inner[ids[i]].x)
				var b := Vector3(sx, inner[ids[i + 1]].y, inner[ids[i + 1]].x)
				var c := Vector3(sx, inner[ids[i + 2]].y, inner[ids[i + 2]].x)
				if (sx > (x0 + x1) * 0.5) == ((b - a).cross(c - a).x > 0.0):
					tri(tool, a, b, c)
				else:
					tri(tool, a, c, b)
		var n := profile.size()
		var ccw := _signed_area(profile) > 0.0
		var xin0 := x0 + bevel if x0 < x1 else x0 - bevel
		var xin1 := x1 - bevel if x0 < x1 else x1 + bevel
		for i in n:
			var p := profile[i]
			var q := profile[(i + 1) % n]
			var pi := inner[i]
			var qi := inner[(i + 1) % n]
			# Normal para fora da borda p→q, no plano do perfil (z, y).
			var d := q - p
			var out2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
			var out3 := Vector3(0, out2.y, out2.x)
			var outer_a := Vector3(xin0, p.y, p.x)
			var outer_b := Vector3(xin1, p.y, p.x)
			var outer_c := Vector3(xin1, q.y, q.x)
			var outer_d := Vector3(xin0, q.y, q.x)
			_face_out(tool, outer_a, outer_b, outer_c, outer_d, out3)
			if bevel > 0.0:
				var side0 := Vector3(signf(x0 - x1), 0, 0)
				_face_out(tool, Vector3(x0, pi.y, pi.x), outer_a, outer_d, Vector3(x0, qi.y, qi.x), out3 + side0)
				_face_out(tool, outer_b, Vector3(x1, pi.y, pi.x), Vector3(x1, qi.y, qi.x), outer_c, out3 - side0)

	func _signed_area(profile: PackedVector2Array) -> float:
		var area := 0.0
		for i in profile.size():
			var a := profile[i]
			var b := profile[(i + 1) % profile.size()]
			area += a.x * b.y - b.x * a.y
		return area * 0.5

	func _face_out(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
		if (b - a).cross(c - a).dot(outward) < 0.0:
			quad(tool, a, d, c, b)
		else:
			quad(tool, a, b, c, d)

	func _inset(profile: PackedVector2Array, amount: float) -> PackedVector2Array:
		if amount <= 0.0:
			return profile
		var result := Geometry2D.offset_polygon(profile, -amount, Geometry2D.JOIN_MITER)
		if result.is_empty() or (result[0] as PackedVector2Array).size() != profile.size():
			# Contorno simples: puxa cada ponto para o centro.
			var c := Vector2.ZERO
			for p in profile:
				c += p
			c /= profile.size()
			var out := PackedVector2Array()
			for p in profile:
				out.append(p + (c - p).normalized() * amount)
			return out
		return _align(profile, result[0])

	## offset_polygon pode começar em outro ponto: realinha pelo mais próximo.
	func _align(profile: PackedVector2Array, shrunk: PackedVector2Array) -> PackedVector2Array:
		var best := 0
		var best_d := INF
		for i in shrunk.size():
			var d := shrunk[i].distance_squared_to(profile[0])
			if d < best_d:
				best_d = d
				best = i
		var out := PackedVector2Array()
		for i in shrunk.size():
			out.append(shrunk[(best + i) % shrunk.size()])
		return out

	## Cilindro ao longo do eixo X (rodas), centrado em `center`.
	func cylinder_x(tool: SurfaceTool, center: Vector3, radius: float, width: float, segments: int = 18, caps: bool = true) -> void:
		var hw := width * 0.5
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var p0 := Vector3(0, cos(a0) * radius, sin(a0) * radius)
			var p1 := Vector3(0, cos(a1) * radius, sin(a1) * radius)
			quad(tool, center + p0 + Vector3(hw, 0, 0), center + p0 + Vector3(-hw, 0, 0), center + p1 + Vector3(-hw, 0, 0), center + p1 + Vector3(hw, 0, 0))
			if caps:
				tri(tool, center + Vector3(hw, 0, 0), center + p0 + Vector3(hw, 0, 0), center + p1 + Vector3(hw, 0, 0))
				tri(tool, center + Vector3(-hw, 0, 0), center + p1 + Vector3(-hw, 0, 0), center + p0 + Vector3(-hw, 0, 0))

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for name in tools:
			var tool: SurfaceTool = tools[name]
			tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials[name])
			mesh.surface_set_name(mesh.get_surface_count() - 1, name)
		return mesh

# -------------------------------------------------------------- carroceria ---

static func _lower_profile(s: Dictionary) -> PackedVector2Array:
	var l := float(s["l"]) * 0.5
	var wb := float(s["wb"]) * 0.5
	var r := float(s["r"])
	var floor_y := r * 0.95
	var belt := float(s["belt"])
	var pts := PackedVector2Array()
	pts.append(Vector2(-l + 0.08, floor_y))
	# Caixa de roda dianteira e traseira (arcos por cima das rodas).
	var rr := r + 0.09
	var cy := r + 0.02
	for i in 11:
		var a := PI - PI * float(i) / 10.0
		pts.append(Vector2(-wb + cos(a) * rr, maxf(floor_y, cy + sin(a) * rr)))
	for i in 11:
		var a := PI - PI * float(i) / 10.0
		pts.append(Vector2(wb + cos(a) * rr, maxf(floor_y, cy + sin(a) * rr)))
	pts.append(Vector2(l - 0.08, floor_y))
	pts.append(Vector2(l, floor_y + 0.22))
	pts.append(Vector2(l - 0.03, float(s["deck"]) - 0.12))
	pts.append(Vector2(l - 0.22, float(s["deck"])))
	if s.get("bed", false):
		# Caminhonete: o chão da caçamba é baixo; a cabine começa num degrau.
		pts.append(Vector2(float(s["rw"]) + 0.08, float(s["deck"])))
		pts.append(Vector2(float(s["rw"]) + 0.02, belt))
	else:
		pts.append(Vector2(float(s["rw"]), belt + (float(s["deck"]) - belt) * 0.5))
	pts.append(Vector2(float(s["ws"]), belt))
	pts.append(Vector2(-l + 0.55, float(s["hood"]) + 0.08))
	pts.append(Vector2(-l + 0.05, float(s["hood"]) - 0.06))
	pts.append(Vector2(-l - 0.02, floor_y + 0.25))
	return pts

static func _body_mesh(kind: String, color_hex: String, wreck: bool, variant: int) -> ArrayMesh:
	var key := "%s|%s|%s|%d" % [kind, color_hex, wreck, variant]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var s: Dictionary = KINDS.get(kind, KINDS["sedan"])
	var b := Builder.new()
	b.bottom = float(s["r"])
	b.top = float(s["roof"])
	var paint := b.st("paint", _paint(color_hex, wreck, variant))
	var glass := b.st("glass", _simple("glass%s" % wreck, Color("#1c262c"), 0.4, 0.05, 0.62 if not wreck else 0.45))
	var trim := b.st("trim", _simple("trim", Color("#16181a"), 0.1, 0.6))
	var chrome := b.st("chrome", _simple("chrome%s" % wreck, Color("#c9ccce") if not wreck else Color("#7d7468"), 0.95 if not wreck else 0.3, 0.12 if not wreck else 0.7))
	var head := b.st("headlight", headlight_material(false))
	var tail := b.st("taillight", taillight_material(false))
	var plate := b.st("plate", _simple("plate", Color("#e9e9e3"), 0.0, 0.5))
	var l := float(s["l"]) * 0.5
	var w := float(s["w"]) * 0.5
	var belt := float(s["belt"])
	var roof := float(s["roof"])
	var ws := float(s["ws"])
	var rf := float(s["rf"])
	var rb := float(s["rb"])
	var rw := float(s["rw"])
	# Carroceria baixa (cintura para baixo), com chanfro nas bordas.
	b.extrude(paint, _lower_profile(s), -w, w, 0.06)
	# Cabine: vidro com colunas e teto pintados, um pouco mais estreita no alto.
	var cw := w - 0.08
	var cabin := PackedVector2Array([Vector2(ws, belt), Vector2(rf, roof - 0.04), Vector2(rb, roof - 0.04), Vector2(rw, belt)])
	b.extrude(glass, cabin, -cw, cw, 0.08)
	b.box(paint, Vector3(0, roof - 0.02, (rf + rb) * 0.5), Vector3(cw * 2.0 - 0.1, 0.06, rb - rf + 0.06))
	for side in [-1.0, 1.0]:
		var x: float = side * (cw - 0.04)
		# Coluna A (para-brisa), B (meio) e C (traseira).
		for pillar in [[Vector2(ws, belt), Vector2(rf, roof - 0.04)], [Vector2(rb, roof - 0.04), Vector2(rw, belt)]]:
			var a: Vector2 = pillar[0]
			var c: Vector2 = pillar[1]
			var mid := (a + c) * 0.5
			var length := a.distance_to(c)
			var angle := atan2(c.y - a.y, c.x - a.x)
			b.box(paint, Vector3(x, mid.y, mid.x), Vector3(0.09, 0.07, length + 0.04), Basis(Vector3.RIGHT, -angle))
		var b_z := (rf + rb) * 0.5 if kind != "pickup" else rb - 0.02
		b.box(paint if kind != "pickup" else paint, Vector3(x, (belt + roof) * 0.5, b_z), Vector3(0.08, roof - belt, 0.1))
		# Retrovisor, maçanetas, frisos das portas e caixa de roda escura.
		b.box(trim, Vector3(side * (w + 0.07), belt + 0.08, ws + 0.18), Vector3(0.12, 0.1, 0.18))
		b.box(paint, Vector3(side * (w + 0.12), belt + 0.08, ws + 0.2), Vector3(0.05, 0.12, 0.2))
		var doors := [ws + 0.1, (rf + rb) * 0.5] if kind == "sedan" else [ws + 0.1]
		for z0 in doors:
			b.box(chrome, Vector3(side * (w + 0.005), belt - 0.12, float(z0) + 0.62), Vector3(0.02, 0.035, 0.14))
		for seam in ([ws - 0.02, (rf + rb) * 0.5 + 0.02, rw - 0.05] if kind == "sedan" else [ws - 0.02, rw - 0.05 if kind == "hatch" else rb + 0.02]):
			b.box(trim, Vector3(side * (w + 0.003), (float(s["r"]) * 1.1 + belt) * 0.5, float(seam)), Vector3(0.01, belt - float(s["r"]) * 1.1, 0.012))
		b.box(trim, Vector3(side * (w + 0.004), float(s["r"]) * 1.15, 0.0), Vector3(0.015, 0.06, float(s["wb"]) - float(s["r"]) * 2.4)) # soleira
		for cz in [-float(s["wb"]) * 0.5, float(s["wb"]) * 0.5]:
			b.box(trim, Vector3(side * (w - 0.14), float(s["r"]) + 0.05, cz), Vector3(0.26, float(s["r"]) * 1.7, float(s["r"]) * 2.1))
	# Frente: grade, faróis, para-choque e placa.
	var front := -l
	b.box(trim, Vector3(0, float(s["hood"]) - 0.22, front + 0.02), Vector3(w * 1.05, 0.2, 0.04))
	var tail_y := (belt - 0.12) if s.get("bed", false) else float(s["deck"]) - 0.16
	for side in [-1.0, 1.0]:
		b.box(head, Vector3(side * (w - 0.3), float(s["hood"]) - 0.14, front + 0.04), Vector3(0.36, 0.14, 0.05))
		b.box(chrome, Vector3(side * (w - 0.3), float(s["hood"]) - 0.14, front + 0.055), Vector3(0.38, 0.16, 0.01))
		b.box(tail, Vector3(side * (w - 0.08), tail_y, l - 0.02), Vector3(0.14, 0.26 if s.get("bed", false) else 0.16, 0.05) if s.get("bed", false) else Vector3(0.32, 0.16, 0.05))
	b.box(trim, Vector3(0, float(s["r"]) + 0.12, front - 0.03), Vector3(w * 2.0 + 0.04, 0.22, 0.14)) # para-choque
	b.box(trim, Vector3(0, float(s["r"]) + 0.12, l + 0.03), Vector3(w * 2.0 + 0.04, 0.22, 0.14))
	b.box(plate, Vector3(0, float(s["r"]) + 0.14, front - 0.105), Vector3(0.52, 0.13, 0.01))
	b.box(plate, Vector3(0, float(s["deck"]) - 0.32, l + 0.02), Vector3(0.52, 0.13, 0.01))
	b.box(trim, Vector3(0, float(s["hood"]) - 0.02, front + 0.35), Vector3(w * 1.6, 0.012, 0.012)) # linha do capô
	if s.get("bed", false):
		# Caçamba aberta: assoalho com frisos, laterais, tampa traseira e friso no topo das laterais.
		var bed_floor := float(s["deck"])
		var bed_len := l - rw - 0.12
		var bed_z := rw + 0.06 + bed_len * 0.5
		b.box(trim, Vector3(0, bed_floor + 0.01, bed_z), Vector3(w * 2.0 - 0.2, 0.02, bed_len))
		for i in 5:
			b.box(paint, Vector3(-w + 0.3 + i * (w * 2.0 - 0.6) / 4.0, bed_floor + 0.03, bed_z), Vector3(0.05, 0.03, bed_len))
		for side in [-1.0, 1.0]:
			b.box(paint, Vector3(side * (w - 0.04), (bed_floor + belt) * 0.5, bed_z), Vector3(0.08, belt - bed_floor, bed_len))
			b.box(trim, Vector3(side * (w - 0.04), belt + 0.015, bed_z), Vector3(0.1, 0.03, bed_len))
		b.box(paint, Vector3(0, (bed_floor + belt) * 0.5, l - 0.05), Vector3(w * 2.0 - 0.16, belt - bed_floor, 0.08))
		b.box(paint, Vector3(0, (bed_floor + belt) * 0.5, rw + 0.08), Vector3(w * 2.0 - 0.16, belt - bed_floor, 0.06))
	var mesh := b.commit()
	_mesh_cache[key] = mesh
	return mesh

# ------------------------------------------------------------------- rodas ---

static func _wheel_mesh(r: float, wreck: bool) -> ArrayMesh:
	var key := "wheel%.2f%s" % [r, wreck]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b := Builder.new()
	b.bottom = -10.0
	b.top = -9.0 # sem sujeira por vértice nas rodas
	var tire := b.st("tire", _simple("tire", Color("#151515"), 0.0, 0.92))
	var rim := b.st("rim%s" % wreck, _simple("rim%s" % wreck, Color("#b9bcbe") if not wreck else Color("#6e655a"), 0.9 if not wreck else 0.3, 0.2 if not wreck else 0.8))
	var hub := b.st("hub", _simple("hub", Color("#2a2c2e"), 0.6, 0.4))
	var width := 0.22
	# Pneu com sulcos: anel externo em degraus.
	b.cylinder_x(tire, Vector3.ZERO, r, width, 24)
	for i in 16:
		var a := TAU * i / 16.0
		b.box(tire, Vector3(0, cos(a) * (r + 0.005), sin(a) * (r + 0.005)), Vector3(width * 0.9, 0.025, 0.035), Basis(Vector3.RIGHT, -a))
	# Aro com raios e calota, virado para fora (+X).
	b.cylinder_x(rim, Vector3(width * 0.5 + 0.005, 0, 0), r * 0.64, 0.02, 20)
	for i in 5:
		var a := TAU * i / 5.0
		b.box(rim, Vector3(width * 0.5 + 0.02, cos(a) * r * 0.32, sin(a) * r * 0.32), Vector3(0.025, r * 0.56, 0.07), Basis(Vector3.RIGHT, -a))
	b.cylinder_x(hub, Vector3(width * 0.5 + 0.03, 0, 0), r * 0.16, 0.03, 12)
	var mesh := b.commit()
	_mesh_cache[key] = mesh
	return mesh
