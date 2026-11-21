extends RefCounted
## Modelo 3D das ferramentas e armas brancas (machado, picareta, faca, facão,
## lança, bastões). Usado na mão do personagem (downloaded_avatar.gd) e no
## suporte de ferramentas do treino.
## Convenção: cabo ao longo de +Y com a base (ponta de baixo do cabo) em 0 e a
## lâmina / gume virado para -Z.
## Se existir res://assets/tools/<id>.glb (modelado no Blender), ele é usado;
## senão sai a versão simples feita de caixas e cilindros.
const StaffModel = preload("res://scripts/weapons/staff_model.gd")
const GLB_DIR := "res://assets/tools/%s.glb"

const LOOK := {
	"fishing_rod": {"handle": 2.1, "color": Color("#855d32"), "head": "rod"},
	"axe": {"handle": 0.78, "color": Color("#8a6238"), "head": "axe"},
	"improvised_axe": {"handle": 0.70, "color": Color("#6e5236"), "head": "stone"},
	"crowbar": {"handle": 0.80, "color": Color("#2f3b52"), "head": "hook"},
	"bat": {"handle": 0.82, "color": Color("#b08a5a"), "head": "bat"},
	"long_bat": {"handle": 1.12, "color": Color("#7a5634"), "head": "bat"},
	# Ferramentas primitivas da floresta (cabo de galho, cabeça de pedra amarrada com fibra).
	"stone_axe": {"handle": 0.66, "color": Color("#6b5034"), "head": "stone"},
	"stone_pick": {"handle": 0.72, "color": Color("#6b5034"), "head": "pick"},
	"club": {"handle": 0.78, "color": Color("#5e4630"), "head": "bat"},
	"stone_knife": {"handle": 0.16, "color": Color("#6b5034"), "head": "blade"},
	# Era do metal (forja).
	"iron_axe": {"handle": 0.74, "color": Color("#5c4128"), "head": "axe"},
	"iron_pick": {"handle": 0.76, "color": Color("#5c4128"), "head": "pick"},
	"iron_knife": {"handle": 0.16, "color": Color("#3e3226"), "head": "blade"},
	"machete": {"handle": 0.14, "color": Color("#3e3226"), "head": "machete"},
	"wood_spear": {"handle": 1.1, "color": Color("#6b5034"), "head": "blade"},
	"nail_bat": {"handle": 0.82, "color": Color("#6a5238"), "head": "bat"},
}

static func has(tool: String) -> bool:
	return LOOK.has(tool)

static func build(tool: String) -> Node3D:
	var path := GLB_DIR % tool
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var model := scene.instantiate() as Node3D
			model.name = "WorkTool"
			return model
	return _build_simple(tool)

static func _mat(color: Color, metal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.85 if metal else 0.0
	m.roughness = 0.3 if metal else 0.8
	return m

static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = mat
	parent.add_child(mesh)

static func _build_simple(tool: String) -> Node3D:
	if tool == "long_bat":
		var staff := StaffModel.build(float(LOOK[tool]["handle"]))
		staff.name = "WorkTool"
		return staff
	var look: Dictionary = LOOK[tool]
	var node := Node3D.new()
	node.name = "WorkTool"
	var length := float(look["handle"])
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.022
	cyl.height = length
	cyl.radial_segments = 8
	handle.mesh = cyl
	handle.position.y = length * 0.5
	handle.material_override = _mat(look["color"], tool == "crowbar")
	node.add_child(handle)
	var steel := _mat(Color("#9aa0a4"), true)
	match str(look["head"]):
		"axe":
			_box(node, Vector3(0, length - 0.05, -0.05), Vector3(0.03, 0.09, 0.16), steel)
			_box(node, Vector3(0, length - 0.05, -0.15), Vector3(0.012, 0.17, 0.06), steel) # gume
			_box(node, Vector3(0, length - 0.05, 0.05), Vector3(0.04, 0.06, 0.05), steel) # olho/martelo
		"stone":
			_box(node, Vector3(0, length - 0.06, -0.07), Vector3(0.05, 0.1, 0.16), _mat(Color("#77746c"), false), Vector3(0.2, 0, 0))
			_box(node, Vector3(0, length - 0.06, 0.0), Vector3(0.06, 0.07, 0.06), _mat(Color("#c9b98a"), false)) # amarração de corda
		"hook":
			_box(node, Vector3(0, length + 0.03, -0.04), Vector3(0.022, 0.022, 0.1), handle.material_override)
			_box(node, Vector3(0, -0.02, -0.03), Vector3(0.02, 0.02, 0.07), handle.material_override, Vector3(0.6, 0, 0))
		"bat":
			handle.mesh = cyl.duplicate()
			(handle.mesh as CylinderMesh).top_radius = 0.035
		"pick":
			# Pedra comprida atravessada no cabo (ponta para os dois lados), amarrada com fibra.
			var rock := _mat(Color("#6f6c64"), false)
			_box(node, Vector3(0, length - 0.05, -0.1), Vector3(0.045, 0.06, 0.16), rock, Vector3(0.25, 0, 0))
			_box(node, Vector3(0, length - 0.05, 0.08), Vector3(0.04, 0.05, 0.1), rock, Vector3(-0.25, 0, 0))
			_box(node, Vector3(0, length - 0.05, 0.0), Vector3(0.06, 0.07, 0.06), _mat(Color("#c9b98a"), false))
		"blade":
			# Lasca de pedra afiada presa num cabo curto.
			_box(node, Vector3(0, length + 0.07, 0), Vector3(0.012, 0.15, 0.045), _mat(Color("#5d5b55"), false))
			_box(node, Vector3(0, length, 0), Vector3(0.035, 0.035, 0.035), _mat(Color("#c9b98a"), false))
		"machete":
			# Lâmina longa de ferro, mais larga perto da ponta, gume para -Z.
			var iron := _mat(Color("#8c9094"), true)
			_box(node, Vector3(0, length + 0.2, -0.005), Vector3(0.008, 0.4, 0.045), iron)
			_box(node, Vector3(0, length + 0.34, -0.012), Vector3(0.008, 0.14, 0.06), iron)
			_box(node, Vector3(0, length + 0.005, 0), Vector3(0.03, 0.012, 0.07), iron) # guarda
	return node
