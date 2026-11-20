extends RefCounted
## Modelos das construções da Sobrevivência: madeira escura e pedra, no clima
## escuro do resto do mapa. Cada peça vira um Node3D com corpos de colisão
## (camada do mundo) marcados com o id da peça (meta "build_id"): o golpe (Q),
## os zumbis e a mira descobrem o que acertaram por aí.
##
## Origem de cada peça (eixo local):
##  - célula (fundação, piso, escada, telhado): centro da célula, na altura do chão
##    do andar; escada e telhado sobem para -Z local (girados por r · 90°);
##  - borda (paredes, porta): meio da borda, na altura do chão do andar, correndo em X;
##  - livre (fogueira, baú, cama): o ponto no chão, girado por y.
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const MapMaterials = preload("res://scripts/map_materials.gd")

const WALL_T := 0.22
const DOOR_W := 1.2 # vão da porta
const DOOR_H := 2.3
const WINDOW_SILL := 1.0
const WINDOW_TOP := 2.1
const WINDOW_W := 1.1
const ROOF_RISE := 1.5

static var _mats: Dictionary = {}

static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"wood": m = SurfaceMaterials.make("wood", Color("#5a4836"), true)
		"wood_dark": m = SurfaceMaterials.make("wood", Color("#3e3226"), true)
		"wood_local": m = SurfaceMaterials.make("wood", Color("#4d3d2d"), false)
		"plank": m = SurfaceMaterials.make("wood", Color("#6a5640"), true)
		"stone":
			m = MapMaterials.surface("concrete", "#6e6a62")
			if m == null:
				m = SurfaceMaterials.make("concrete", Color("#6e6a62"), true)
		"roof":
			m = MapMaterials.surface("roof", "#4a3a30")
			if m == null:
				m = SurfaceMaterials.make("wood", Color("#3b3029"), true)
		"rock": m = _flat("#5b5852")
		"ash": m = _flat("#1d1a17")
		"seam": m = _flat("#241c15")
		"cloth": m = _flat("#5f5a44")
		"pillow": m = _flat("#8a846c")
		"iron": m = _flat("#2b2d2e", 0.5, 0.6)
		"rust": m = _flat("#5a3524", 0.85, 0.3)
		"glass":
			var g := _flat("#7f9a8e", 0.1, 0.0)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.albedo_color.a = 0.55
			m = g
		_: m = _flat("#ff00ff")
	_mats[key] = m
	return m

static func _flat(hex: String, rough: float = 0.9, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	m.metallic = metal
	return m

## Material da prévia (verde pode, vermelho não pode).
static func ghost_material(ok: bool) -> StandardMaterial3D:
	var key := "ghost_ok" if ok else "ghost_bad"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.35, 0.95, 0.45, 0.38) if ok else Color(1.0, 0.3, 0.25, 0.38)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_mats[key] = m
	return m

# --------------------------------------------------------------- blocos ---

static func _body(parent: Node3D, id: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = HitboxScript.LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("build_id", id)
	parent.add_child(body)
	return body

static func _mesh(parent: Node3D, mesh: Mesh, xform: Transform3D, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.transform = xform
	m.material_override = material
	parent.add_child(m)
	return m

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if _mats.has(key):
		return _mats[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	_mats[key] = mesh
	return mesh

## Caixa visível + colisão (se `body` não for nulo).
static func _box(parent: Node3D, body: StaticBody3D, center: Vector3, size: Vector3, material: String, basis: Basis = Basis.IDENTITY) -> void:
	_mesh(parent, _box_mesh(size), Transform3D(basis, center), _mat(material))
	if body != null:
		_shape(body, center, size, basis)

static func _shape(body: StaticBody3D, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(basis, center)
	body.add_child(col)

# ---------------------------------------------------------------- peças ---

## Monta a peça. `rules` = building_rules.gd (tamanho da grade).
static func build(p: Dictionary, rules) -> Node3D:
	var root := Node3D.new()
	var kind := str(p.get("kind", ""))
	var id := str(p.get("id", ""))
	root.name = "Build_" + (id if not id.is_empty() else kind)
	var S: float = rules.S
	var H: float = rules.H
	var slot: String = rules.slot_type(kind)
	var k := int(p.get("k", 0))
	var r := int(p.get("r", 0))
	match slot:
		"cell", "stairs":
			root.position = Vector3((int(p.get("i", 0)) + 0.5) * S, rules.top(k), (int(p.get("j", 0)) + 0.5) * S)
			if kind in ["stairs", "roof"]:
				root.rotation.y = r * PI * 0.5
		"edge", "door":
			var horizontal := str(p.get("o", "h")) == "h"
			var x: float = (int(p.get("i", 0)) + 0.5) * S if horizontal else int(p.get("i", 0)) * S
			var z: float = int(p.get("j", 0)) * S if horizontal else (int(p.get("j", 0)) + 0.5) * S
			root.position = Vector3(x, rules.top(k), z)
			root.rotation.y = 0.0 if horizontal else PI * 0.5
		_:
			var v: Array = p.get("p", [0, 0, 0])
			root.position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			root.rotation.y = float(p.get("y", 0.0))
	var body := _body(root, id)
	match kind:
		"foundation": _foundation(root, body, S, rules.base)
		"floor": _floor(root, body, S)
		"wall": _wall(root, body, S, H)
		"doorway": _doorway(root, body, S, H)
		"window": _window(root, body, S, H)
		"door": _door(root, p)
		"stairs": _stairs(root, body, S, H)
		"roof": _roof(root, body, S)
		"campfire": _campfire(root, body, bool(p.get("on", false)))
		"chest": _chest(root, body)
		"bed": _bed(root, body)
		"workbench": _workbench(root, body)
		"forge": _forge(root, body, bool(p.get("on", false)))
		"workshop": _workshop(root, body)
		"chem_table": _chem_table(root, body)
	return root

static func _foundation(root: Node3D, body: StaticBody3D, S: float, base: float) -> void:
	var h := base + 0.35 # enterrada 35 cm
	_box(root, body, Vector3(0, -h * 0.5, 0), Vector3(S, h, S), "stone")
	# Tábuas por cima e um rodapé de tora escura (lê-se bem como chão de casa).
	_box(root, null, Vector3(0, 0.005, 0), Vector3(S - 0.12, 0.012, S - 0.12), "plank")
	for side in [-1.0, 1.0]:
		_box(root, null, Vector3(side * (S * 0.5 - 0.06), -0.08, 0), Vector3(0.14, 0.18, S), "wood_dark")
		_box(root, null, Vector3(0, -0.08, side * (S * 0.5 - 0.06)), Vector3(S, 0.18, 0.14), "wood_dark")

static func _floor(root: Node3D, body: StaticBody3D, S: float) -> void:
	_box(root, body, Vector3(0, -0.1, 0), Vector3(S, 0.2, S), "plank")
	# Vigas por baixo (vistas de dentro de casa).
	for x in [-1.0, 0.0, 1.0]:
		_box(root, null, Vector3(x * S * 0.33, -0.26, 0), Vector3(0.16, 0.14, S - 0.05), "wood_dark")

## Parede maciça de toras com frisos escuros.
static func _wall(root: Node3D, body: StaticBody3D, S: float, H: float) -> void:
	_box(root, body, Vector3(0, H * 0.5, 0), Vector3(S, H, WALL_T), "wood")
	_seams(root, -S * 0.5, S * 0.5, 0.0, H)

static func _seams(root: Node3D, x0: float, x1: float, y0: float, y1: float) -> void:
	var y := y0 + 0.5
	while y < y1 - 0.2:
		_box(root, null, Vector3((x0 + x1) * 0.5, y, 0), Vector3(x1 - x0, 0.04, WALL_T + 0.02), "seam")
		y += 0.5

static func _doorway(root: Node3D, body: StaticBody3D, S: float, H: float) -> void:
	var side := (S - DOOR_W) * 0.5
	for s in [-1.0, 1.0]:
		var cx: float = s * (DOOR_W * 0.5 + side * 0.5)
		_box(root, body, Vector3(cx, H * 0.5, 0), Vector3(side, H, WALL_T), "wood")
		_seams(root, cx - side * 0.5, cx + side * 0.5, 0.0, H)
		# Batente escuro.
		_box(root, null, Vector3(s * (DOOR_W * 0.5 + 0.05), DOOR_H * 0.5, 0), Vector3(0.1, DOOR_H, WALL_T + 0.04), "wood_dark")
	_box(root, body, Vector3(0, DOOR_H + (H - DOOR_H) * 0.5, 0), Vector3(DOOR_W, H - DOOR_H, WALL_T), "wood")
	_box(root, null, Vector3(0, DOOR_H + 0.05, 0), Vector3(DOOR_W + 0.2, 0.1, WALL_T + 0.04), "wood_dark")

static func _window(root: Node3D, body: StaticBody3D, S: float, H: float) -> void:
	_box(root, body, Vector3(0, WINDOW_SILL * 0.5, 0), Vector3(S, WINDOW_SILL, WALL_T), "wood")
	_box(root, body, Vector3(0, WINDOW_TOP + (H - WINDOW_TOP) * 0.5, 0), Vector3(S, H - WINDOW_TOP, WALL_T), "wood")
	var side := (S - WINDOW_W) * 0.5
	for s in [-1.0, 1.0]:
		_box(root, body, Vector3(s * (WINDOW_W * 0.5 + side * 0.5), (WINDOW_SILL + WINDOW_TOP) * 0.5, 0), Vector3(side, WINDOW_TOP - WINDOW_SILL, WALL_T), "wood")
	_seams(root, -S * 0.5, S * 0.5, 0.0, WINDOW_SILL)
	_seams(root, -S * 0.5, S * 0.5, WINDOW_TOP - 0.5, H)
	# Grade de galhos na janela (dá para ver e atirar, não para passar).
	for x in [-0.3, 0.0, 0.3]:
		_box(root, null, Vector3(x, (WINDOW_SILL + WINDOW_TOP) * 0.5, 0), Vector3(0.05, WINDOW_TOP - WINDOW_SILL, 0.05), "wood_dark")
	_box(root, null, Vector3(0, WINDOW_SILL + 0.03, 0), Vector3(WINDOW_W + 0.1, 0.06, WALL_T + 0.08), "wood_dark")

## Porta: gira na dobradiça (lado esquerdo do vão). Aberta, gira 90° para um lado (r).
static func _door(root: Node3D, p: Dictionary) -> void:
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(-DOOR_W * 0.5 + 0.02, 0, 0)
	root.add_child(hinge)
	var body := _body(hinge, str(p.get("id", "")))
	var w := DOOR_W - 0.04
	var h := DOOR_H - 0.04
	_box(hinge, body, Vector3(w * 0.5, h * 0.5 + 0.01, 0), Vector3(w, h, 0.08), "wood_local")
	for y in [0.4, h - 0.4]:
		_box(hinge, null, Vector3(w * 0.5, y, 0), Vector3(w - 0.08, 0.1, 0.11), "wood_dark")
	_box(hinge, null, Vector3(w - 0.14, 1.05, 0.07), Vector3(0.05, 0.16, 0.05), "iron")
	_box(hinge, null, Vector3(w - 0.14, 1.05, -0.07), Vector3(0.05, 0.16, 0.05), "iron")
	set_door_open(root, bool(p.get("open", false)), int(p.get("r", 0)), false)

static func set_door_open(root: Node3D, open: bool, r: int, animate: bool = true) -> void:
	var hinge := root.get_node_or_null("Hinge") as Node3D
	if hinge == null:
		return
	var angle := (PI * 0.5 * (1.0 if r % 2 == 0 else -1.0)) if open else 0.0
	if animate and hinge.is_inside_tree():
		hinge.create_tween().tween_property(hinge, "rotation:y", angle, 0.35).set_trans(Tween.TRANS_SINE)
	else:
		hinge.rotation.y = angle

## Escada de 3 m de altura em 3 m: degraus visíveis sobre uma rampa (o corpo
## do jogador não sobe degrau). Sobe para -Z local.
static func _stairs(root: Node3D, body: StaticBody3D, S: float, H: float) -> void:
	var width := S - 0.5
	var n := 15
	var tread := S / n
	var rise := H / n
	for i in n:
		var top := (i + 1) * rise
		var hgt := minf(top, 0.35)
		_box(root, null, Vector3(0, top - hgt * 0.5, S * 0.5 - (i + 0.5) * tread), Vector3(width, hgt, tread + 0.01), "plank")
	# Vigas laterais inclinadas e a rampa invisível.
	var foot := Vector3(0, 0, S * 0.5)
	var head := Vector3(0, H, -S * 0.5)
	var dir := (head - foot).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir)
	var basis := Basis(right, up, -dir)
	var length := foot.distance_to(head)
	for s in [-1.0, 1.0]:
		_box(root, null, (foot + head) * 0.5 + right * s * (width * 0.5 + 0.06) - up * 0.15, Vector3(0.1, 0.3, length), "wood_dark", basis)
	var start := foot + Vector3(0, rise * 0.5, 0) - dir * 0.4
	var center := (start + head) * 0.5 - up * 0.12
	_shape(body, center, Vector3(width, 0.24, start.distance_to(head)), basis)

## Telhado de uma água: baixo em +Z local, alto (1,5 m) em -Z; duas peças de
## frente uma para a outra fazem um telhado de duas águas. Empenas nos lados.
static func _roof(root: Node3D, body: StaticBody3D, S: float) -> void:
	var low := Vector3(0, 0.0, S * 0.5 + 0.25)
	var high := Vector3(0, ROOF_RISE, -S * 0.5)
	var dir := (high - low).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir)
	var basis := Basis(right, up, -dir)
	var length := low.distance_to(high)
	_box(root, body, (low + high) * 0.5 + up * 0.08, Vector3(S + 0.3, 0.16, length), "roof", basis)
	# Frisos de telha e caibros.
	var steps := 5
	for i in steps:
		var t := (i + 0.5) / steps
		_box(root, null, low.lerp(high, t) + up * 0.17, Vector3(S + 0.3, 0.03, 0.05), "wood_dark", basis)
	for s in [-1.0, 1.0]:
		var gable := _triangle_prism(S, ROOF_RISE, 0.16)
		_mesh(root, gable, Transform3D(Basis.IDENTITY, Vector3(s * (S * 0.5 - 0.08), 0, 0)), _mat("wood"))
		var shape := ConvexPolygonShape3D.new()
		shape.points = gable.get_meta("points")
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(s * (S * 0.5 - 0.08), 0, 0)
		body.add_child(col)

## Prisma triangular (empena): base em y = 0 de z = +S/2 a -S/2, ponta alta em z = -S/2.
static func _triangle_prism(S: float, rise: float, thick: float) -> ArrayMesh:
	var a := Vector3(0, 0, S * 0.5)
	var b := Vector3(0, 0, -S * 0.5)
	var c := Vector3(0, rise, -S * 0.5)
	var off := Vector3(thick * 0.5, 0, 0)
	var pts := PackedVector3Array([a - off, b - off, c - off, a + off, b + off, c + off])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [[0, 2, 1], [3, 4, 5], [0, 1, 4], [0, 4, 3], [1, 2, 5], [1, 5, 4], [2, 0, 3], [2, 3, 5]]
	for f in faces:
		for idx in f:
			st.set_uv(Vector2(pts[idx].z, pts[idx].y) * 0.5)
			st.add_vertex(pts[idx])
	st.generate_normals()
	var mesh := st.commit()
	mesh.set_meta("points", pts)
	return mesh

static func _campfire(root: Node3D, body: StaticBody3D, on: bool) -> void:
	var stone := SphereMesh.new()
	stone.radius = 0.13
	stone.height = 0.18
	stone.radial_segments = 8
	stone.rings = 4
	for i in 9:
		var a := TAU * i / 9.0
		_mesh(root, stone, Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1.2, 1.0, 0.9)), Vector3(cos(a) * 0.42, 0.07, sin(a) * 0.42)), _mat("rock"))
	_mesh(root, _box_mesh(Vector3(0.62, 0.02, 0.62)), Transform3D(Basis.IDENTITY, Vector3(0, 0.01, 0)), _mat("ash"))
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.06
	log_mesh.bottom_radius = 0.07
	log_mesh.height = 0.7
	log_mesh.radial_segments = 6
	# Três toras inclinadas, encostadas no meio (fogueira em pirâmide).
	for i in 3:
		var a := TAU * i / 3.0
		var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(28))
		_mesh(root, log_mesh, Transform3D(tilt, Vector3(sin(a) * 0.12, 0.28, cos(a) * 0.12)), _mat("wood_dark"))
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 0.3
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.15
	body.add_child(col)
	set_fire(root, on)

## Acende/apaga a fogueira (ou a forja): luz quente que tremula e chamas (partículas).
## A altura do fogo vem da meta "fire_y" (forja: dentro da boca de pedra).
static func set_fire(root: Node3D, on: bool) -> void:
	var light := root.get_node_or_null("FireLight") as OmniLight3D
	var flames := root.get_node_or_null("Flames") as CPUParticles3D
	var fire_y := float(root.get_meta("fire_y", 0.0))
	if on and light == null:
		light = OmniLight3D.new()
		light.name = "FireLight"
		light.position.y = 0.7 + fire_y
		light.light_color = Color("#ff9a4a")
		light.light_energy = 2.2
		light.omni_range = 11.0
		light.shadow_enabled = false
		light.set_script(preload("res://scripts/survival/fire_flicker.gd"))
		root.add_child(light)
		flames = CPUParticles3D.new()
		flames.name = "Flames"
		flames.amount = 26
		flames.lifetime = 0.7
		flames.position.y = 0.12 + fire_y
		flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		flames.emission_sphere_radius = 0.16
		flames.direction = Vector3.UP
		flames.spread = 12.0
		flames.gravity = Vector3(0, 1.4, 0)
		flames.initial_velocity_min = 0.4
		flames.initial_velocity_max = 0.9
		flames.scale_amount_min = 0.18
		flames.scale_amount_max = 0.34
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1.4)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.vertex_color_use_as_albedo = true
		# Mancha redonda e macia (sem ela cada chama vira um quadrado).
		var soft := GradientTexture2D.new()
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(0.5, 0.0)
		soft.width = 64
		soft.height = 64
		var falloff := Gradient.new()
		falloff.set_color(0, Color(1, 1, 1, 1))
		falloff.set_color(1, Color(1, 1, 1, 0))
		soft.gradient = falloff
		mat.albedo_texture = soft
		quad.material = mat
		flames.mesh = quad
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.75, 0.3, 0.9))
		ramp.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
		flames.color_ramp = ramp
		root.add_child(flames)
	elif not on and light != null:
		light.queue_free()
		if flames != null:
			flames.queue_free()

static func _chest(root: Node3D, body: StaticBody3D) -> void:
	_box(root, body, Vector3(0, 0.3, 0), Vector3(1.0, 0.6, 0.6), "wood_local")
	_box(root, null, Vector3(0, 0.52, 0), Vector3(1.04, 0.08, 0.64), "wood_dark")
	for x in [-0.42, 0.42]:
		_box(root, null, Vector3(x, 0.3, 0), Vector3(0.06, 0.62, 0.63), "iron")
	_box(root, null, Vector3(0, 0.42, 0.31), Vector3(0.12, 0.12, 0.03), "iron")

static func _bed(root: Node3D, body: StaticBody3D) -> void:
	_box(root, body, Vector3(0, 0.15, 0), Vector3(1.0, 0.3, 2.0), "wood_local")
	_box(root, null, Vector3(0, 0.36, 0.1), Vector3(0.9, 0.14, 1.75), "cloth")
	_box(root, null, Vector3(0, 0.47, -0.7), Vector3(0.6, 0.1, 0.32), "pillow")
	_box(root, null, Vector3(0, 0.45, -0.97), Vector3(1.0, 0.6, 0.08), "wood_dark")

## Bancada: tampo grosso de tábuas em quatro pernas, prateleira embaixo,
## morsa de ferro num canto e ferramentas penduradas no fundo.
static func _workbench(root: Node3D, body: StaticBody3D) -> void:
	_box(root, body, Vector3(0, 0.86, 0), Vector3(1.6, 0.1, 0.8), "plank")
	for x in [-0.72, 0.72]:
		for z in [-0.32, 0.32]:
			_box(root, null, Vector3(x, 0.41, z), Vector3(0.1, 0.82, 0.1), "wood_dark")
	_box(root, null, Vector3(0, 0.22, 0), Vector3(1.44, 0.05, 0.62), "wood_local")
	_shape(body, Vector3(0, 0.41, 0), Vector3(1.6, 0.82, 0.8))
	# Fundo com ferramentas penduradas.
	_box(root, null, Vector3(0, 1.22, -0.36), Vector3(1.6, 0.62, 0.05), "wood_dark")
	_box(root, null, Vector3(-0.45, 1.25, -0.32), Vector3(0.05, 0.4, 0.03), "wood")
	_box(root, null, Vector3(-0.45, 1.42, -0.31), Vector3(0.18, 0.08, 0.03), "iron")
	_box(root, null, Vector3(0.1, 1.2, -0.32), Vector3(0.04, 0.34, 0.03), "wood")
	_box(root, null, Vector3(0.45, 1.24, -0.32), Vector3(0.3, 0.05, 0.03), "iron")
	# Morsa no canto e uma tora em cima.
	_box(root, null, Vector3(0.62, 0.98, 0.22), Vector3(0.16, 0.14, 0.2), "iron")
	_box(root, null, Vector3(0.62, 1.07, 0.22), Vector3(0.06, 0.06, 0.26), "iron")
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.08
	log_mesh.bottom_radius = 0.08
	log_mesh.height = 0.6
	log_mesh.radial_segments = 7
	_mesh(root, log_mesh, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.3, 0.99, 0.1)), _mat("wood_dark"))

## Forja: bloco de pedra com a boca do fogo na frente, chaminé atrás e uma
## bigorna de ferro ao lado. Acesa, o fogo fica dentro da boca.
static func _forge(root: Node3D, body: StaticBody3D, on: bool) -> void:
	root.set_meta("fire_y", 0.42)
	_box(root, body, Vector3(-0.15, 0.4, 0), Vector3(1.1, 0.8, 1.0), "stone")
	_box(root, null, Vector3(-0.15, 0.6, 0.47), Vector3(0.5, 0.36, 0.08), "ash")
	_box(root, null, Vector3(-0.15, 0.82, 0.05), Vector3(1.16, 0.08, 1.06), "rock")
	_box(root, body, Vector3(-0.15, 1.35, -0.25), Vector3(0.4, 1.0, 0.4), "stone")
	_box(root, null, Vector3(-0.15, 1.88, -0.25), Vector3(0.46, 0.08, 0.46), "rock")
	# Bigorna num toco.
	var stump := CylinderMesh.new()
	stump.top_radius = 0.17
	stump.bottom_radius = 0.2
	stump.height = 0.5
	stump.radial_segments = 8
	_mesh(root, stump, Transform3D(Basis.IDENTITY, Vector3(0.68, 0.25, 0.15)), _mat("wood_dark"))
	_box(root, null, Vector3(0.68, 0.58, 0.15), Vector3(0.16, 0.16, 0.2), "iron")
	_box(root, null, Vector3(0.68, 0.7, 0.15), Vector3(0.24, 0.08, 0.42), "iron")
	_shape(body, Vector3(0.68, 0.37, 0.15), Vector3(0.4, 0.74, 0.44))
	set_fire(root, on)

## Oficina mecânica: bancada de chapa de ferro sobre cavaletes, morsa grande,
## esmeril, um pneu encostado e um tambor ao lado.
static func _workshop(root: Node3D, body: StaticBody3D) -> void:
	_box(root, body, Vector3(0, 0.9, 0), Vector3(2.0, 0.08, 0.9), "iron")
	for x in [-0.85, 0.85]:
		_box(root, null, Vector3(x, 0.43, 0), Vector3(0.12, 0.86, 0.8), "wood_dark")
	_shape(body, Vector3(0, 0.43, 0), Vector3(2.0, 0.86, 0.9))
	_box(root, null, Vector3(-0.7, 1.02, 0.2), Vector3(0.22, 0.16, 0.24), "iron")
	_box(root, null, Vector3(-0.7, 1.12, 0.2), Vector3(0.08, 0.08, 0.36), "iron")
	# Esmeril: motor e dois discos.
	_box(root, null, Vector3(0.55, 1.04, -0.15), Vector3(0.3, 0.2, 0.18), "rock")
	for side in [-1.0, 1.0]:
		var disc := CylinderMesh.new()
		disc.top_radius = 0.1
		disc.bottom_radius = 0.1
		disc.height = 0.04
		disc.radial_segments = 10
		_mesh(root, disc, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.55 + side * 0.2, 1.07, -0.15)), _mat("iron"))
	# Pneu encostado na perna e tambor de óleo.
	var tire := TorusMesh.new()
	tire.inner_radius = 0.2
	tire.outer_radius = 0.34
	tire.rings = 12
	tire.ring_segments = 6
	_mesh(root, tire, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.3), Vector3(1.2, 0.34, 0.25)), _mat("ash"))
	var drum := CylinderMesh.new()
	drum.top_radius = 0.28
	drum.bottom_radius = 0.28
	drum.height = 0.85
	drum.radial_segments = 10
	_mesh(root, drum, Transform3D(Basis.IDENTITY, Vector3(-1.3, 0.43, -0.1)), _mat("rust"))
	_shape(body, Vector3(-1.3, 0.43, -0.1), Vector3(0.56, 0.85, 0.56))

## Mesa de química: mesa de madeira com tampo de chapa, frascos de vidro,
## um fogareiro e uma prateleira de potes no fundo.
static func _chem_table(root: Node3D, body: StaticBody3D) -> void:
	_box(root, body, Vector3(0, 0.84, 0), Vector3(1.5, 0.06, 0.75), "iron")
	for x in [-0.68, 0.68]:
		for z in [-0.3, 0.3]:
			_box(root, null, Vector3(x, 0.41, z), Vector3(0.08, 0.82, 0.08), "wood_dark")
	_shape(body, Vector3(0, 0.41, 0), Vector3(1.5, 0.82, 0.75))
	_box(root, null, Vector3(0, 1.25, -0.34), Vector3(1.5, 0.04, 0.2), "wood_dark")
	for x in [-0.6, -0.35, -0.1, 0.2, 0.5]:
		_box(root, null, Vector3(x, 1.34, -0.34), Vector3(0.1, 0.16, 0.1), "glass")
	for spot in [[Vector3(-0.4, 0.97, 0.1), 0.08, 0.2], [Vector3(-0.15, 0.95, 0.15), 0.06, 0.16], [Vector3(0.1, 1.0, 0.05), 0.05, 0.26]]:
		var flask := CylinderMesh.new()
		flask.top_radius = float(spot[1]) * 0.45
		flask.bottom_radius = float(spot[1])
		flask.height = float(spot[2])
		flask.radial_segments = 8
		_mesh(root, flask, Transform3D(Basis.IDENTITY, spot[0]), _mat("glass"))
	# Fogareiro com uma panelinha.
	_box(root, null, Vector3(0.5, 0.92, 0.12), Vector3(0.26, 0.1, 0.26), "iron")
	var pot := CylinderMesh.new()
	pot.top_radius = 0.1
	pot.bottom_radius = 0.09
	pot.height = 0.12
	pot.radial_segments = 10
	_mesh(root, pot, Transform3D(Basis.IDENTITY, Vector3(0.5, 1.03, 0.12)), _mat("rust"))

## Prévia: o mesmo modelo, sem colisão, todo na cor verde/vermelha.
static func make_ghost(p: Dictionary, rules) -> Node3D:
	var node := build(p, rules)
	for body in node.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 0
		body.remove_meta("build_id")
	for light in node.find_children("*", "Light3D", true, false):
		light.queue_free()
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func paint_ghost(node: Node3D, ok: bool) -> void:
	var m := ghost_material(ok)
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = m
