extends Node3D
## Escudo de braço (mão esquerda): escudo tático (balístico, preto fosco com
## visor) e escudo de madeira (redondo, tábuas com aro e umbo de ferro).
##
## Eixos do modelo: +Z = face da frente (para o inimigo), +Y = para cima,
## origem = punho (onde a mão esquerda fecha). Quem posiciona é o avatar
## (downloaded_avatar.gd, _apply_shield): a mão segura o punho e o antebraço
## passa pela alça.
##
## `blocking` = true cria um corpo na camada LAYER_SHIELD: tiros e golpes
## (SHOT_MASK) param nele. Só nos outros jogadores (net_actor): o escudo do
## jogador local não pode segurar o próprio tiro.
const Model = preload("res://scripts/survival/building_model.gd")
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")

const IDS := ["tactical_shield", "wood_shield"]
## id -> [largura, altura, espessura, deslocamento do centro da face em relação ao punho]
const SIZE := {
	"tactical_shield": [0.56, 0.98, 0.03, Vector3(0.0, 0.10, 0.075)],
	"wood_shield": [0.66, 0.66, 0.028, Vector3(0.0, 0.02, 0.07)],
}

var shield_id := ""

static var _mats := {}

static func is_shield(id: String) -> bool:
	return IDS.has(id)

static func build(id: String, blocking: bool = false) -> Node3D:
	var root: Node3D = (load("res://scripts/weapons/shield_model.gd") as GDScript).new()
	root.name = "Shield"
	root.shield_id = id
	if id == "tactical_shield":
		_tactical(root)
	else:
		_wood(root)
	for m in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if blocking:
		_blocker(root, id)
	return root

## Centro da face (no espaço do escudo): para onde o avatar vira a face.
static func face_center(id: String) -> Vector3:
	return (SIZE.get(id, SIZE["wood_shield"]) as Array)[3]

static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match key:
		"polymer": m = _flat("#33393c", 0.72, 0.2)
		"polymer_edge": m = _flat("#1a1d1f", 0.6, 0.0)
		"steel": m = _flat("#5a5e61", 0.4, 0.75)
		"visor":
			m = _flat("#4f6b78", 0.05, 0.4)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.75
		"strap": m = _flat("#2a2620", 0.95, 0.0)
		"plank_a": m = SurfaceMaterials.make("wood", Color("#5e4a35"), false)
		"plank_b": m = SurfaceMaterials.make("wood", Color("#4e3d2b"), false)
		"seam": m = _flat("#1e1711", 0.95, 0.0)
		"iron": m = _flat("#2e2f30", 0.5, 0.65)
		_: m = _flat("#ff00ff", 0.9, 0.0)
	_mats[key] = m
	return m

static func _flat(hex: String, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	m.metallic = metal
	return m

static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: String, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return Model._mesh(parent, mesh, Transform3D(basis, at), _mat(mat))

## Punho horizontal (eixo X) atrás da face, com dois suportes de aço. A mão
## fecha nele como num guidão: em guarda o antebraço vai para trás, carregando
## o braço pende e o escudo fica de lado.
static func _grip(root: Node3D, face_z: float) -> void:
	var handle := CylinderMesh.new()
	handle.top_radius = 0.016
	handle.bottom_radius = 0.016
	handle.height = 0.13
	handle.radial_segments = 8
	Model._mesh(root, handle, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat("strap"))
	for x in [-0.075, 0.075]:
		_box(root, Vector3(0.025, 0.03, face_z + 0.012), Vector3(x, 0, face_z * 0.5 - 0.006), "steel")

# ------------------------------------------------------ escudo tático ---
static func _tactical(root: Node3D) -> void:
	var s: Array = SIZE["tactical_shield"]
	var w: float = s[0]
	var h: float = s[1]
	var t: float = s[2]
	var c: Vector3 = s[3]
	# Face levemente curva: 5 faixas verticais giradas em leque (abraça o corpo).
	var strips := 5
	var strip_w := w / strips
	for i in strips:
		var u := (float(i) + 0.5) / strips - 0.5 # -0.5..0.5
		var angle := u * 0.42
		var x := u * w
		var z := c.z - absf(u) * absf(u) * 0.09
		_box(root, Vector3(strip_w + 0.004, h, t), Vector3(x, c.y, z), "polymer", Basis(Vector3.UP, -angle))
	# Borda de borracha em volta.
	for y in [c.y + h * 0.5, c.y - h * 0.5]:
		_box(root, Vector3(w * 0.96, 0.03, t + 0.016), Vector3(0, y, c.z - 0.01), "polymer_edge")
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.028, h + 0.02, t + 0.016), Vector3(side * w * 0.5, c.y, c.z - 0.02 - 0.02), "polymer_edge", Basis(Vector3.UP, -side * 0.21))
	# Visor balístico (janela na altura dos olhos) com moldura de aço.
	var visor_y := c.y + h * 0.5 - 0.17
	var front := c.z + t * 0.5 + 0.002
	_box(root, Vector3(0.27, 0.09, 0.012), Vector3(0, visor_y, front), "visor")
	_box(root, Vector3(0.30, 0.016, 0.016), Vector3(0, visor_y + 0.053, front), "steel")
	_box(root, Vector3(0.30, 0.016, 0.016), Vector3(0, visor_y - 0.053, front), "steel")
	for side in [-1.0, 1.0]:
		_box(root, Vector3(0.016, 0.12, 0.016), Vector3(side * 0.143, visor_y, front), "steel")
	# Placas de reforço e parafusos na frente (sem marca/escrita).
	_box(root, Vector3(w * 0.7, 0.012, 0.008), Vector3(0, c.y - h * 0.12, front), "polymer_edge")
	_box(root, Vector3(w * 0.7, 0.012, 0.008), Vector3(0, c.y - h * 0.32, front), "polymer_edge")
	for x in [-0.2, 0.2]:
		for y in [visor_y, c.y - h * 0.4]:
			var bolt := CylinderMesh.new()
			bolt.top_radius = 0.009
			bolt.bottom_radius = 0.009
			bolt.height = 0.012
			bolt.radial_segments = 6
			Model._mesh(root, bolt, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x, y, front)), _mat("steel"))
	_grip(root, c.z - t * 0.5)

# --------------------------------------------------- escudo de madeira ---
static func _wood(root: Node3D) -> void:
	var s: Array = SIZE["wood_shield"]
	var r: float = float(s[0]) * 0.5
	var t: float = s[2]
	var c: Vector3 = s[3]
	var face := Basis(Vector3.RIGHT, PI * 0.5) # cilindro deitado: eixo em Z
	# Disco de madeira (veio na vertical) com as frestas das tábuas por cima.
	var disc := CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = t
	disc.radial_segments = 28
	Model._mesh(root, disc, Transform3D(face, Vector3(0, c.y, c.z)), _mat("plank_a"))
	var planks := 5
	var plank_w := r * 2.0 / planks
	for i in range(1, planks):
		var x := -r + plank_w * i
		var tall := sqrt(maxf(r * r - x * x, 0.0)) * 2.0 - 0.03
		_box(root, Vector3(0.007, tall, 0.004), Vector3(x, c.y, c.z + t * 0.5 + 0.001), "seam")
	# Uma tábua mais escura no meio, para ler como tábuas e não um disco liso.
	_box(root, Vector3(plank_w - 0.008, r * 2.0 - 0.05, 0.003), Vector3(0, c.y, c.z + t * 0.5 + 0.0005), "plank_b")
	# Aro de ferro.
	var rim := TorusMesh.new()
	rim.inner_radius = r - 0.022
	rim.outer_radius = r + 0.006
	rim.rings = 28
	rim.ring_segments = 6
	Model._mesh(root, rim, Transform3D(face, Vector3(0, c.y, c.z)), _mat("iron"))
	# Umbo (cúpula de ferro no meio) sobre o punho.
	var boss := SphereMesh.new()
	boss.radius = 0.075
	boss.height = 0.075
	boss.is_hemisphere = true
	boss.radial_segments = 14
	boss.rings = 5
	Model._mesh(root, boss, Transform3D(face, Vector3(0, c.y, c.z + t * 0.5)), _mat("iron"))
	# Duas travessas por trás + rebites na frente.
	for y in [c.y + r * 0.45, c.y - r * 0.45]:
		var span := sqrt(maxf(r * r - pow(y - c.y, 2.0), 0.0)) * 2.0 - 0.05
		_box(root, Vector3(span, 0.05, 0.016), Vector3(0, y, c.z - t * 0.5 - 0.008), "plank_b")
		for x in [-span * 0.4, 0.0, span * 0.4]:
			var rivet := SphereMesh.new()
			rivet.radius = 0.009
			rivet.height = 0.012
			rivet.radial_segments = 6
			rivet.rings = 3
			Model._mesh(root, rivet, Transform3D(Basis.IDENTITY, Vector3(x, y, c.z + t * 0.5)), _mat("iron"))
	_grip(root, c.z - t * 0.5)

# --------------------------------------------------------- bloqueio ---
static func _blocker(root: Node3D, id: String) -> void:
	var s: Array = SIZE[id]
	var body := StaticBody3D.new()
	body.name = "ShieldBody"
	body.collision_layer = HitboxScript.LAYER_SHIELD
	body.collision_mask = 0
	root.add_child(body)
	var shape := CollisionShape3D.new()
	if id == "wood_shield":
		var disc := CylinderShape3D.new()
		disc.radius = float(s[0]) * 0.5
		disc.height = 0.06
		shape.shape = disc
		shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), s[3])
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(float(s[0]), float(s[1]), 0.06)
		shape.shape = box
		shape.position = s[3]
	body.add_child(shape)
