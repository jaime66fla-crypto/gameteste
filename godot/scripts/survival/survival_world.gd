extends Node3D
## Mundo aberto da Sobrevivência (480 x 480 m), montado a partir de
## data/survival_world.json. A cidade original do Campo de Fogo (WorldPolish,
## ±60 m) fica no meio; em volta: estradas, cidades, fazenda, base militar,
## hospital, florestas, rochas e carros abandonados.
##
## Recipientes (saque) e recursos (coleta) guardam o id do servidor em
## `containers` / `resources`, para o controlador achar o que está perto.
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CarModel = preload("res://scripts/survival/car_model.gd")
const CENTER_HALF := 60.0

var containers: Dictionary = {} # id -> {node, type, pos}
var resources: Dictionary = {} # id -> {node, kind, pos, parts}
var half_size := 240.0
var _mats: Dictionary = {}
var _meshes: Dictionary = {}

func _ready() -> void:
	name = "SurvivalWorld"
	var data := SurvivalData.world()
	half_size = float(data.get("half_size", 240))
	_ground()
	for road in data.get("roads", []):
		_road(road)
	for building in data.get("buildings", []):
		_building(building)
	for spot in data.get("containers", []):
		_container(spot)
	for res in data.get("resources", []):
		_resource(res)
	for town in data.get("towns", []):
		_town_sign(town)
	grass_patches = data.get("grass", [])
	_short_grass()
	for patch in grass_patches:
		_tall_grass(patch)
	_fence()

# ------------------------------------------------------------------ grama ---
# Grama baixa espalhada pelo campo (só visual, some de longe) e manchas de
# grama alta (1,3–1,7 m): agachado dentro delas, zumbis só te veem bem de perto.
var grass_patches: Array = []
var _grass_material: ShaderMaterial
const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float sway = 0.10;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = VERTEX.y;
	float wave = sin(TIME * 1.7 + world.x * 0.31 + world.z * 0.23) + 0.4 * sin(TIME * 3.1 + world.x * 0.9);
	VERTEX.x += wave * sway * h;
	VERTEX.z += wave * sway * 0.6 * h;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
}
"""

func _grass_mat() -> ShaderMaterial:
	if _grass_material == null:
		var shader := Shader.new()
		shader.code = GRASS_SHADER
		_grass_material = ShaderMaterial.new()
		_grass_material.shader = shader
	return _grass_material

## Tufo de folhas finas (triângulos), base escura e ponta clara.
func _clump_mesh(blades: int, height: float, width: float, base: Color, tip: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = blades * 31 + int(height * 100)
	for i in blades:
		var a := TAU * i / blades + rng.randf_range(-0.3, 0.3)
		var r := rng.randf_range(0.0, 0.18)
		var center := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := height * rng.randf_range(0.7, 1.15)
		var side := Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5)) * width * 0.5
		var lean := Vector3(cos(a), 0, sin(a)) * h * rng.randf_range(0.1, 0.35)
		var b := base.lerp(base.darkened(0.2), rng.randf())
		var t := tip.lerp(tip.lightened(0.15), rng.randf())
		st.set_color(b)
		st.add_vertex(center - side)
		st.set_color(b)
		st.add_vertex(center + side)
		st.set_color(t)
		st.add_vertex(center + lean + Vector3(0, h, 0))
	st.generate_normals()
	return st.commit()

func _multimesh(mesh: Mesh, transforms: Array, visible_until: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _grass_mat()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = visible_until
	node.visibility_range_end_margin = 10.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(node)
	return node

## Grama baixa em blocos de 40 m (cada bloco some sozinho de longe).
func _short_grass() -> void:
	var mesh := _clump_mesh(4, 0.38, 0.07, Color("#3e5a2e"), Color("#8aa65a"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tile := 40.0
	var h := half_size
	var x := -h
	while x < h:
		var z := -h
		while z < h:
			var list: Array = []
			for i in 520:
				var p := Vector3(x + rng.randf() * tile, 0, z + rng.randf() * tile)
				if absf(p.x) < CENTER_HALF + 1 and absf(p.z) < CENTER_HALF + 1:
					continue
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
				list.append(Transform3D(basis, p))
			if not list.is_empty():
				var node := _multimesh(mesh, list, 55.0)
				node.name = "ShortGrass"
			z += tile
		x += tile

func _tall_grass(patch: Dictionary) -> void:
	var mesh := _clump_mesh(7, 1.45, 0.09, Color("#4a5b2a"), Color("#b8b46a"))
	var c := Vector3(float(patch["x"]), 0, float(patch["z"]))
	var r := float(patch["r"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.x * 13 + c.z * 7)
	var count := int(PI * r * r * 1.6)
	var list: Array = []
	for i in count:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, rng.randf_range(0.85, 1.2), 1))
		list.append(Transform3D(basis, c + Vector3(cos(a) * d, 0, sin(a) * d)))
	var node := _multimesh(mesh, list, 170.0)
	node.name = "TallGrass"

## Ponto dentro de uma mancha de grama alta?
func in_tall_grass(point: Vector3) -> bool:
	for patch in grass_patches:
		var dx := point.x - float(patch["x"])
		var dz := point.z - float(patch["z"])
		var r := float(patch["r"]) - 0.6
		if dx * dx + dz * dz < r * r:
			return true
	return false

# ------------------------------------------------------------ materiais ---

func _mat(kind: String, hex: String) -> StandardMaterial3D:
	var key := kind + hex
	if not _mats.has(key):
		_mats[key] = SurfaceMaterials.make(kind, Color(hex)) if kind != "flat" else _flat(hex)
	return _mats[key]

func _flat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.85
	return m

func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_meshes[key] = mesh
	return _meshes[key]

func _part(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh(size)
	m.position = pos
	m.material_override = material
	parent.add_child(m)
	return m

func _solid(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = HitboxScript.LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	_part(body, Vector3.ZERO, size, material)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	return body

# ----------------------------------------------------------------- chão ---

## Quatro placas de grama em volta da cidade do meio (ela tem o próprio chão).
func _ground() -> void:
	var grass := _mat("grass", "#5d7a4e")
	var h := half_size
	var c := CENTER_HALF
	var slabs := [
		[Vector3(0, -0.5, -(h + c) * 0.5), Vector3(h * 2, 1, h - c)],
		[Vector3(0, -0.5, (h + c) * 0.5), Vector3(h * 2, 1, h - c)],
		[Vector3(-(h + c) * 0.5, -0.5, 0), Vector3(h - c, 1, c * 2)],
		[Vector3((h + c) * 0.5, -0.5, 0), Vector3(h - c, 1, c * 2)],
	]
	for slab in slabs:
		_solid(self, slab[0], slab[1], grass).name = "Ground"
	# Manchas de terra e de grama mais clara/escura, para o campo não ficar liso.
	var tints := [_mat("concrete", "#7a6a4f"), _mat("grass", "#6f8a52"), _mat("grass", "#4e6a40"), _mat("grass", "#7c8e4a")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 220:
		var p := Vector3(rng.randf_range(-h + 10, h - 10), 0.004 + (i % 4) * 0.003, rng.randf_range(-h + 10, h - 10))
		if absf(p.x) < c + 10 and absf(p.z) < c + 10:
			continue
		var size := rng.randf_range(8, 30) if i % 4 else rng.randf_range(5, 14)
		var patch := _part(self, p, Vector3(size, 0.01, size * rng.randf_range(0.5, 1.2)), tints[i % 4])
		patch.rotation.y = rng.randf() * TAU

func _road(road: Dictionary) -> void:
	var a := Vector3(float(road["from"][0]), 0, float(road["from"][1]))
	var b := Vector3(float(road["to"][0]), 0, float(road["to"][1]))
	var length := a.distance_to(b)
	var width := float(road.get("width", 6))
	var node := Node3D.new()
	node.position = (a + b) * 0.5 + Vector3(0, 0.012, 0)
	node.rotation.y = atan2(b.x - a.x, b.z - a.z)
	add_child(node)
	_part(node, Vector3.ZERO, Vector3(width, 0.02, length), _mat("asphalt", "#4a5052"))
	# Faixa amarela tracejada no meio.
	var paint := _flat("#cdb56a")
	var step := 7.0
	var n := int(length / step)
	for i in n:
		_part(node, Vector3(0, 0.012, -length * 0.5 + (i + 0.5) * step), Vector3(0.15, 0.01, 3.0), paint)

# -------------------------------------------------------------- prédios ---

## Prédio oco com porta de 2 m na parede +Z, janelas e placa com o nome.
func _building(data: Dictionary) -> void:
	var center := Vector3(float(data["center"][0]), 0, float(data["center"][1]))
	var w := float(data["size"][0])
	var d := float(data["size"][1])
	var h := float(data.get("height", 3.4))
	var kind := str(data.get("kind", "house"))
	var wall := _mat("plaster", str(data.get("color", "#b9a58a")))
	var root := Node3D.new()
	root.name = str(data.get("name", "Predio")).replace(" ", "_").replace("—", "-")
	root.position = center
	add_child(root)
	root.add_to_group("map_building")
	var t := 0.25
	_solid(root, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, t), wall)
	for side in [-1.0, 1.0]:
		_solid(root, Vector3(side * w * 0.5, h * 0.5, 0), Vector3(t, h, d), wall)
		_solid(root, Vector3(side * (w + 2.0) * 0.25, h * 0.5, d * 0.5), Vector3((w - 2.0) * 0.5, h, t), wall)
		# Janela (só visual) na fachada.
		_part(root, Vector3(side * w * 0.3, 1.6, d * 0.5 + 0.14), Vector3(1.3, 1.0, 0.04), _flat("#3d5560"))
	_solid(root, Vector3(0, (h + 2.4) * 0.5, d * 0.5), Vector3(2.0, h - 2.4, t), wall)
	var roof_color: String = str({"barn": "#6b2c22", "military": "#4b5240", "hospital": "#9aa0a0"}.get(kind, "#535b5b"))
	_solid(root, Vector3(0, h + 0.1, 0), Vector3(w + 0.5, 0.2, d + 0.5), _mat("roof", roof_color))
	_part(root, Vector3(0, 0.01, 0), Vector3(w - 0.3, 0.02, d - 0.3), _mat("wood" if kind in ["house", "barn"] else "concrete", "#8b765b" if kind in ["house", "barn"] else "#a49e8c"))
	var title := str(data.get("name", ""))
	var dash := title.find(" — ")
	var sign_text := title.substr(dash + 3) if dash >= 0 else title
	var sign := Label3D.new()
	sign.text = sign_text.to_upper()
	sign.font_size = 40
	sign.pixel_size = 0.006
	sign.outline_size = 8
	sign.modulate = Color("#eee5c7")
	sign.position = Vector3(0, minf(h - 0.3, 2.9), d * 0.5 + 0.2)
	root.add_child(sign)
	if kind == "hospital":
		_part(root, Vector3(0, h - 0.6, d * 0.5 + 0.16), Vector3(0.9, 0.25, 0.04), _flat("#c8261f"))
		_part(root, Vector3(0, h - 0.6, d * 0.5 + 0.16), Vector3(0.25, 0.9, 0.04), _flat("#c8261f"))

func _town_sign(town: Dictionary) -> void:
	var c := Vector3(float(town["center"][0]), 0, float(town["center"][1]))
	var to_center := (-c).normalized()
	var p := c + to_center * 34.0
	var post := Node3D.new()
	post.position = p
	add_child(post)
	_part(post, Vector3(0, 1.0, 0), Vector3(0.12, 2.0, 0.12), _flat("#3b3f3f"))
	_part(post, Vector3(0, 2.1, 0), Vector3(3.6, 0.7, 0.08), _flat("#2f5d3a"))
	for side in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = str(town["name"]).to_upper()
		label.font_size = 36
		label.pixel_size = 0.006
		label.position = Vector3(0, 2.1, 0.06 * side)
		label.rotation.y = 0.0 if side > 0 else PI
		post.add_child(label)
	post.look_at(post.global_position + to_center, Vector3.UP)

# ----------------------------------------------------------- recipientes ---

const CONTAINER_LOOK := {
	"fridge": [Vector3(0.8, 1.8, 0.7), "#e8ecec", "metal"],
	"cabinet": [Vector3(1.4, 0.9, 0.55), "#7c6044", "wood"],
	"wardrobe": [Vector3(1.2, 2.0, 0.6), "#6a4d35", "wood"],
	"toolbox": [Vector3(0.9, 0.45, 0.45), "#b8352b", "metal"],
	"medcab": [Vector3(0.9, 1.2, 0.35), "#f2f2ee", "metal"],
	"shelf": [Vector3(1.8, 1.7, 0.5), "#7f8789", "metal"],
	"car_trunk": [Vector3(1.0, 0.55, 0.7), "#3a3f44", "metal"],
	"gun_locker": [Vector3(1.0, 1.9, 0.55), "#3d4a3a", "metal"],
	"military": [Vector3(1.2, 0.6, 0.7), "#55603f", "wood"],
}

func _container(spot: Dictionary) -> void:
	var type := str(spot["type"])
	var look: Array = CONTAINER_LOOK.get(type, CONTAINER_LOOK["cabinet"])
	var size: Vector3 = look[0]
	var p: Array = spot["p"]
	var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var body := StaticBody3D.new()
	body.name = "Container_" + str(spot["id"])
	body.collision_layer = HitboxScript.LAYER_WORLD
	body.position = pos
	add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	body.add_child(col)
	var mat := _mat(str(look[2]), str(look[1]))
	_part(body, Vector3(0, size.y * 0.5, 0), size, mat)
	# Detalhes: porta/gaveta escura na frente, cruz no armário de remédios.
	if size.y > 1.0:
		_part(body, Vector3(0, size.y * 0.5, size.z * 0.5 + 0.01), Vector3(0.04, size.y * 0.9, 0.02), _flat("#222"))
	else:
		_part(body, Vector3(0, size.y * 0.55, size.z * 0.5 + 0.01), Vector3(size.x * 0.8, 0.04, 0.02), _flat("#222"))
	if type == "medcab":
		_part(body, Vector3(0, size.y * 0.6, size.z * 0.5 + 0.02), Vector3(0.36, 0.1, 0.01), _flat("#c8261f"))
		_part(body, Vector3(0, size.y * 0.6, size.z * 0.5 + 0.02), Vector3(0.1, 0.36, 0.01), _flat("#c8261f"))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.pixel_size = 0.004
	label.position.y = size.y + 0.35
	label.modulate = Color("#ffe08a")
	label.text = SurvivalData.container_name(type)
	label.visible = false
	body.add_child(label)
	containers[str(spot["id"])] = {"node": body, "type": type, "pos": pos, "label": label, "empty": false}

## O servidor avisou que o recipiente foi esvaziado (até reabastecer).
func set_container_empty(id: String, empty: bool) -> void:
	var entry: Dictionary = containers.get(id, {})
	if entry.is_empty():
		return
	entry["empty"] = empty
	entry["label"].modulate = Color("#9a9a9a") if empty else Color("#ffe08a")

# --------------------------------------------------------------- recursos ---

func _resource(res: Dictionary) -> void:
	var kind := str(res["kind"])
	var p: Array = res["p"]
	var body := StaticBody3D.new()
	body.name = "Res_" + str(res["id"])
	body.collision_layer = HitboxScript.LAYER_WORLD
	body.position = Vector3(float(p[0]), 0, float(p[2]))
	body.rotation.y = float(res.get("yaw", 0.0))
	add_child(body)
	var parts: Array = []
	var seed_value := int(str(res["id"]).substr(1))
	var s := 0.8 + float(seed_value % 7) * 0.07
	match kind:
		"tree":
			var trunk_h := 3.2 * s
			_cylinder(body, Vector3(0, trunk_h * 0.5, 0), 0.16 * s, 0.26 * s, trunk_h, _mat("bark", "#5e4733"))
			var crown := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.9 * s
			cone.height = 4.2 * s
			cone.radial_segments = 8
			crown.mesh = cone
			crown.position.y = trunk_h + 1.2 * s
			crown.material_override = _mat("leaf", "#3f6a3c" if seed_value % 3 else "#4d7a42")
			body.add_child(crown)
			parts.append(crown)
			_collider(body, CylinderShape3D.new(), Vector3(0, trunk_h * 0.5, 0), 0.26 * s, trunk_h)
		"rock":
			var rock := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 1.3
			sphere.radial_segments = 7
			sphere.rings = 4
			rock.mesh = sphere
			rock.scale = Vector3(1.3, 0.9, 1.0) * s
			rock.position.y = 0.35 * s
			rock.material_override = _mat("concrete", "#7d7f7a")
			body.add_child(rock)
			parts.append(rock)
			_collider(body, SphereShape3D.new(), Vector3(0, 0.35 * s, 0), 1.0 * s, 0.0)
		"car":
			# Carro abandonado realista (ferrugem, vidro sujo, pneu murcho às vezes).
			var colors := ["#7a2e28", "#2e4b6a", "#8a8a80", "#3d5a3a", "#8a7a52", "#c9c4b8", "#2b2b2b"]
			var car_kind: String = ["sedan", "hatch", "pickup"][seed_value % 3]
			var model := CarModel.build(car_kind, colors[seed_value % colors.size()], true, seed_value)
			body.add_child(model)
			parts.append(model)
			var size := CarModel.size_of(car_kind)
			var shape := BoxShape3D.new()
			shape.size = Vector3(size.x, size.y - 0.2, size.z)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position.y = 0.2 + shape.size.y * 0.5
			body.add_child(col)
			body.rotation.z = 0.03 * float(seed_value % 3 - 1)
		"bush":
			var bush := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.8 * s
			sphere.height = 1.2 * s
			sphere.radial_segments = 8
			sphere.rings = 4
			bush.mesh = sphere
			bush.position.y = 0.5 * s
			bush.material_override = _mat("leaf", "#4f7b3a")
			body.add_child(bush)
			var fruit := _flat("#c0392b")
			for i in 5:
				var a := TAU * i / 5.0
				parts.append(_part(body, Vector3(cos(a) * 0.65 * s, 0.6 * s + (i % 2) * 0.2, sin(a) * 0.65 * s), Vector3(0.14, 0.14, 0.14), fruit))
			_collider(body, SphereShape3D.new(), Vector3(0, 0.5 * s, 0), 0.6 * s, 0.0)
	resources[str(res["id"])] = {"node": body, "kind": kind, "pos": body.position, "parts": parts, "depleted": false}

func _cylinder(parent: Node3D, pos: Vector3, top: float, bottom: float, height: float, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "cyl%.2f_%.2f_%.2f" % [top, bottom, height]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = top
		mesh.bottom_radius = bottom
		mesh.height = height
		mesh.radial_segments = 8
		_meshes[key] = mesh
	var m := MeshInstance3D.new()
	m.mesh = _meshes[key]
	m.position = pos
	m.rotation = rot
	m.material_override = material
	parent.add_child(m)
	return m

func _collider(body: StaticBody3D, shape: Shape3D, pos: Vector3, radius: float, height: float) -> void:
	if shape is CylinderShape3D:
		shape.radius = radius
		shape.height = height
	elif shape is SphereShape3D:
		shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)

## Coletado: a árvore vira toco, a pedra some, o carro fica "depenado", o arbusto sem frutas.
func set_depleted(id: String, value: bool) -> void:
	var entry: Dictionary = resources.get(id, {})
	if entry.is_empty() or bool(entry["depleted"]) == value:
		return
	entry["depleted"] = value
	match str(entry["kind"]):
		"tree", "bush", "rock":
			for part in entry["parts"]:
				part.visible = not value
			if str(entry["kind"]) == "rock":
				entry["node"].scale = Vector3.ONE * (0.45 if value else 1.0)
		"car":
			entry["node"].rotation.z = 0.12 if value else 0.0

# ----------------------------------------------------------------- borda ---

## Cerca na borda do mundo, mais uma barreira alta invisível.
func _fence() -> void:
	var h := half_size - 0.5
	var wood := _mat("wood", "#6e5a42")
	for side in [-1.0, 1.0]:
		for along_x in [true, false]:
			var pos := Vector3(0, 1.0, side * h) if along_x else Vector3(side * h, 1.0, 0)
			var size := Vector3(h * 2, 2.0, 0.3) if along_x else Vector3(0.3, 2.0, h * 2)
			_solid(self, pos, size, wood).name = "EdgeFence"
			var barrier := StaticBody3D.new()
			barrier.position = pos + Vector3(0, 14, 0)
			add_child(barrier)
			var shape := BoxShape3D.new()
			shape.size = size + Vector3(0, 26, 0)
			var col := CollisionShape3D.new()
			col.shape = shape
			barrier.add_child(col)
