extends RefCounted
## Bastão longo (receita: madeira + pregos + pano): cabo de madeira que afina
## para a empunhadura, empunhadura enrolada em faixa de pano com uma tira
## solta, duas cintas de arame e pregos saindo da ponta grossa.
## Cabo ao longo de +Y, base em 0 (mesma convenção das ferramentas do avatar).
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const LENGTH := 1.12

static func build(length: float = LENGTH) -> Node3D:
	var root := Node3D.new()
	root.name = "LongStaff"
	var wood := SurfaceMaterials.make("wood", Color("#8a5f36"))
	var wood_dark := SurfaceMaterials.make("wood", Color("#5b3d22"))
	var cloth := SurfaceMaterials.make("fabric", Color("#c9bfa6"))
	var cloth_dark := SurfaceMaterials.make("fabric", Color("#8c3b2e"))
	var steel := SurfaceMaterials.make("metal", Color("#8f969a"))
	var rust := SurfaceMaterials.make("metal", Color("#6b4a36"))
	# Cabo: afina da ponta (4 cm) para a empunhadura (2,3 cm).
	_cyl(root, 0.0, length - 0.03, 0.023, 0.04, wood, 10)
	# Ponta arredondada e pomo escuro na base.
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.06
	sphere.radial_segments = 10
	sphere.rings = 4
	cap.mesh = sphere
	cap.position.y = length - 0.03
	cap.material_override = wood
	root.add_child(cap)
	_cyl(root, -0.012, 0.025, 0.028, 0.026, wood_dark, 10)
	# Empunhadura de pano (0,03–0,34 m) em voltas, com a tira solta pendurada.
	for k in 7:
		var y0 := 0.03 + k * 0.044
		_cyl(root, y0, y0 + 0.04, 0.0275, 0.0285, cloth, 10)
	_cyl(root, 0.335, 0.355, 0.03, 0.03, cloth_dark, 10)
	var tail := MeshInstance3D.new()
	var tail_box := BoxMesh.new()
	tail_box.size = Vector3(0.022, 0.09, 0.004)
	tail.mesh = tail_box
	tail.position = Vector3(0.02, 0.31, 0.022)
	tail.rotation = Vector3(0.25, 0.0, -0.35)
	tail.material_override = cloth
	root.add_child(tail)
	# Duas cintas de arame segurando a ponta.
	for y in [length - 0.30, length - 0.12]:
		_cyl(root, y, y + 0.014, 0.041, 0.041, steel, 12)
	# Pregos: cabeça encostada na madeira, ponta para fora, em volta da ponta grossa.
	var nails := [[length - 0.24, 0.0], [length - 0.20, 2.1], [length - 0.17, 4.2], [length - 0.08, 1.0], [length - 0.05, 3.1], [length - 0.21, 5.3]]
	for spec in nails:
		var y: float = spec[0]
		var a: float = spec[1]
		var out := Vector3(cos(a), 0.0, sin(a))
		var nail := MeshInstance3D.new()
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.0015
		shaft.bottom_radius = 0.003
		shaft.height = 0.055
		shaft.radial_segments = 5
		shaft.rings = 1
		nail.mesh = shaft
		nail.material_override = rust if int(a * 10) % 2 == 0 else steel
		# Cilindro em +Y: gira para apontar para fora, um pouco para cima.
		var dir := (out + Vector3(0, 0.25, 0)).normalized()
		nail.basis = Basis(Quaternion(Vector3.UP, dir))
		nail.position = Vector3(0, y, 0) + out * 0.045 + dir * 0.012
		root.add_child(nail)
	# Fibra da madeira: dois veios escuros finos ao longo do cabo.
	for a in [0.7, 3.9]:
		var grain := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(0.004, length * 0.5, 0.003)
		grain.mesh = strip
		var r := 0.034
		grain.position = Vector3(cos(a) * r, length * 0.62, sin(a) * r)
		grain.rotation.y = -a
		grain.material_override = wood_dark
		root.add_child(grain)
	return root

static func _cyl(root: Node3D, y0: float, y1: float, bottom: float, top: float, mat: Material, segments: int) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = bottom
	cyl.top_radius = top
	cyl.height = y1 - y0
	cyl.radial_segments = segments
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.position.y = (y0 + y1) * 0.5
	mesh.material_override = mat
	root.add_child(mesh)
