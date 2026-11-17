extends RefCounted
## Mochila "o mais real possível" sem arquivos externos: corpo arredondado de
## tecido (com textura de trama e relevo), tampa com dobra, bolso frontal com
## zíper e puxador de metal, bolsos laterais (um com garrafa), alças de ombro
## acolchoadas com fivelas, alça de mão e, na militar, fitas MOLLE e saco de
## dormir enrolado embaixo. Fica de costas para -Z (encostada no personagem em +Z).
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")

static var _cache: Dictionary = {}

static func _fabric(color: Color) -> Material:
	var key := "fabric%s" % color.to_html()
	if not _cache.has(key):
		var m: StandardMaterial3D = SurfaceMaterials.make("fabric", color, false).duplicate()
		m.roughness = 0.95
		m.uv1_scale = Vector3(3, 3, 3) # trama fina
		_cache[key] = m
	return _cache[key]

static func _plain(color: Color, metallic: float, roughness: float) -> Material:
	var key := "plain%s%.2f%.2f" % [color.to_html(), metallic, roughness]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		_cache[key] = m
	return _cache[key]

static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	m.scale = scale
	m.material_override = mat
	parent.add_child(m)
	return m

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 16
	c.rings = 6
	return c

static func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = 14
	return c

## size = (largura, altura, profundidade) do corpo; color = cor do tecido.
static func build(kind: String, size: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Backpack"
	var fabric := _fabric(color)
	var darker := _fabric(color.darkened(0.25))
	var webbing := _plain(Color("#1d1f1c"), 0.0, 0.85)
	var metal := _plain(Color("#b5b8ba"), 0.9, 0.3)
	var plastic := _plain(Color("#141414"), 0.0, 0.5)
	var w := size.x
	var h := size.y
	var d := size.z
	var cz := -d * 0.5 # centro do corpo (atrás das costas)
	# Corpo arredondado: núcleo + quatro "cantos" de cápsula (bordas macias).
	_add(root, _box(Vector3(w - d * 0.5, h - d * 0.4, d)), Vector3(0, 0, cz), fabric)
	_add(root, _box(Vector3(w, h - d * 0.9, d * 0.55)), Vector3(0, -d * 0.05, cz), fabric)
	for x in [-1.0, 1.0]:
		_add(root, _capsule(d * 0.5, h - d * 0.2), Vector3(x * (w * 0.5 - d * 0.42), -d * 0.05, cz), fabric, Vector3.ZERO, Vector3(0.75, 1, 1))
	# Topo abaulado com tampa que dobra para a frente.
	_add(root, _capsule(d * 0.5, w), Vector3(0, h * 0.5 - d * 0.32, cz), fabric, Vector3(0, 0, PI * 0.5), Vector3(1, 1, 1))
	_add(root, _box(Vector3(w * 0.92, d * 0.12, d * 1.08)), Vector3(0, h * 0.5 - d * 0.02, cz - d * 0.04), darker, Vector3(-0.12, 0, 0))
	_add(root, _box(Vector3(w * 0.9, h * 0.22, 0.012)), Vector3(0, h * 0.37, -d - 0.008), darker) # aba da tampa
	for x in [-0.32, 0.32]:
		_add(root, _box(Vector3(0.025, h * 0.34, 0.006)), Vector3(x * w, h * 0.22, -d - 0.016), webbing) # fitas da tampa
		_add(root, _box(Vector3(0.04, 0.03, 0.012)), Vector3(x * w, h * 0.06, -d - 0.02), plastic) # fivelas
	# Bolso frontal com zíper em arco e puxador.
	var pocket_h := h * 0.42
	_add(root, _capsule(d * 0.28, w * 0.62), Vector3(0, -h * 0.18, -d - d * 0.18), fabric, Vector3(0, 0, PI * 0.5), Vector3(1, 1.0, 0.8))
	_add(root, _box(Vector3(w * 0.66, pocket_h, d * 0.3)), Vector3(0, -h * 0.2, -d - d * 0.1), fabric)
	_add(root, _box(Vector3(w * 0.6, 0.008, 0.006)), Vector3(0, -h * 0.2 + pocket_h * 0.42, -d - d * 0.26), plastic) # zíper
	_add(root, _box(Vector3(0.012, 0.035, 0.006)), Vector3(w * 0.22, -h * 0.2 + pocket_h * 0.38, -d - d * 0.27), metal) # puxador
	_add(root, _box(Vector3(0.012, 0.035, 0.006)), Vector3(-w * 0.18, -h * 0.2 + pocket_h * 0.38, -d - d * 0.27), metal)
	# Bolsos laterais de rede (um com garrafa).
	for x in [-1.0, 1.0]:
		_add(root, _box(Vector3(d * 0.28, h * 0.32, d * 0.7)), Vector3(x * (w * 0.5 + d * 0.08), -h * 0.24, cz), darker)
	_add(root, _cyl(0.032, 0.032, h * 0.38), Vector3(w * 0.5 + d * 0.1, -h * 0.12, cz), _plain(Color("#3f7fae"), 0.1, 0.15))
	_add(root, _cyl(0.018, 0.018, 0.04), Vector3(w * 0.5 + d * 0.1, h * 0.09, cz), plastic)
	# Painel das costas acolchoado e alças de ombro (passam por cima do ombro para a frente).
	_add(root, _box(Vector3(w * 0.86, h * 0.86, 0.025)), Vector3(0, 0, 0.0), darker)
	for x in [-1.0, 1.0]:
		var sx: float = x * w * 0.24
		_add(root, _box(Vector3(0.06, 0.035, 0.11)), Vector3(sx, h * 0.5 - 0.02, 0.05), darker, Vector3(0.35, 0, 0)) # sobe no ombro
		_add(root, _box(Vector3(0.06, h * 0.62, 0.03)), Vector3(sx, h * 0.12, 0.2), darker, Vector3(-0.08, 0, 0)) # desce no peito
		_add(root, _box(Vector3(0.022, h * 0.5, 0.012)), Vector3(sx, -h * 0.25, 0.08), webbing) # regulagem
		_add(root, _box(Vector3(0.045, 0.03, 0.015)), Vector3(sx, -h * 0.14, 0.2), plastic) # fivela
	_add(root, _capsule(0.012, 0.1), Vector3(0, h * 0.5 + 0.03, -d * 0.35), webbing, Vector3(0, 0, PI * 0.5)) # alça de mão
	match kind:
		"backpack":
			# Militar: fitas MOLLE horizontais e saco de dormir enrolado embaixo.
			for i in 4:
				_add(root, _box(Vector3(w * 0.7, 0.018, 0.006)), Vector3(0, -h * 0.36 + i * 0.05, -d - d * 0.28), webbing)
			_add(root, _cyl(d * 0.42, d * 0.42, w * 1.05), Vector3(0, -h * 0.5 - d * 0.32, cz), _fabric(Color("#5b5a3a")), Vector3(0, 0, PI * 0.5))
			for x in [-0.3, 0.3]:
				_add(root, _cyl(d * 0.44, d * 0.44, 0.025), Vector3(x * w, -h * 0.5 - d * 0.32, cz), webbing, Vector3(0, 0, PI * 0.5))
		"school_bag":
			# Escolar: faixa refletiva e chaveiro.
			_add(root, _box(Vector3(w * 0.5, 0.02, 0.006)), Vector3(0, h * 0.05, -d - d * 0.03), _plain(Color("#d8d8c8"), 0.6, 0.2))
			_add(root, _cyl(0.014, 0.014, 0.05), Vector3(w * 0.22, -h * 0.02, -d - d * 0.3), _plain(Color("#e0b030"), 0.3, 0.4))
		"sack_bag":
			# Improvisada: saco de lona amarrado com corda no topo.
			_add(root, _cyl(0.05, d * 0.35, 0.08), Vector3(0, h * 0.5 + 0.05, cz), fabric)
			_add(root, _cyl(0.035, 0.035, 0.03), Vector3(0, h * 0.5 + 0.06, cz), _plain(Color("#c9b98a"), 0.0, 0.9))
	return root
