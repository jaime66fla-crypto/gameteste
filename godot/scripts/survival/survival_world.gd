extends Node3D
## Mundo aberto da Sobrevivência (840 x 840 m, núcleo antigo de 600 x 600 m), montado a partir de
## data/survival_world.json: só natureza — florestas, clareiras, lagos, rochas,
## arbustos de frutas e coisas pequenas no chão (galhos, pedrinhas, capim, ervas).
## (Prédios, estradas e recipientes ainda são montados se o arquivo tiver.)
##
## Recipientes (saque) e recursos (coleta) guardam o id do servidor em
## `containers` / `resources`, para o controlador achar o que está perto.
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const MapMaterials = preload("res://scripts/map_materials.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CarModel = preload("res://scripts/survival/car_model.gd")
const NatureModel = preload("res://scripts/survival/nature_model.gd")
const ParkourDistrictScript = preload("res://scripts/parkour_district.gd")
const MountainTerrain = preload("res://scripts/survival/mountain_terrain.gd")
const CollectibleGlow = preload("res://scripts/survival/collectible_glow.gd")
const LakeWater = preload("res://scripts/survival/lake_water.gd")
var _resource_glow: Node3D
## Coisas pequenas do chão: um modelo só, visíveis até PICKUP_RANGE, sem colisão.
const PICKUPS := ["stick", "pebble", "fiber", "herb"]
const PICKUP_RANGE := 50.0

var containers: Dictionary = {} # id -> {node, type, pos}
var resources: Dictionary = {} # id -> {node, kind, pos, parts, r}
var fallen_fruit: Dictionary = {} # alimento dos animais, separado da coleta do jogador
var ponds: Array = [] # [{x, z, r}]
var half_size := 240.0
var center_half := 0.0 # cidade do meio (mapas antigos); 0 = sem cidade
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
var staged_loading := false

func _ready() -> void:
	name = "SurvivalWorld"
	if not staged_loading:
		build_staged()

func _loading_batch(progress: Callable, message: String, fraction: float) -> void:
	if progress.is_valid():
		progress.call(message, fraction)
		await get_tree().process_frame

func build_staged(progress: Callable = Callable()) -> void:
	var data := SurvivalData.world()
	half_size = float(data.get("half_size", 240))
	center_half = float(data.get("center_town", {}).get("half_size", 0.0))
	ponds = data.get("ponds", [])
	_ground()
	MountainTerrain.build(self, data.get("mountains", []))
	await _loading_batch(progress, "Montando lagos e estradas…", 0.08)
	for pond in ponds:
		_pond(pond)
	for road in data.get("roads", []):
		_road(road)
	var buildings: Array = data.get("buildings", [])
	for i in buildings.size():
		_building(buildings[i])
		if i % 6 == 5:
			await _loading_batch(progress, "Montando cidades…", 0.12 + 0.18 * float(i) / maxf(1, buildings.size()))
	# Bairros e bases de parkour do anel novo (sobrados, térreas, pistas).
	if not data.get("parkour", []).is_empty() or not data.get("parkour_bases", []).is_empty():
		var district := ParkourDistrictScript.new()
		district.set("survival_lots", data.get("parkour", []))
		district.set("survival_bases", data.get("parkour_bases", []))
		add_child(district)
	for spot in data.get("containers", []):
		_container(spot)
	var resources_data: Array = data.get("resources", [])
	for i in resources_data.size():
		_resource(resources_data[i])
		if i % 100 == 99:
			await _loading_batch(progress, "Montando florestas e recursos…", 0.32 + 0.5 * float(i) / maxf(1, resources_data.size()))
	_flush_batches()
	await _loading_batch(progress, "Preparando vegetação…", 0.84)
	for town in data.get("towns", []):
		_town_sign(town)
	grass_patches = data.get("grass", [])
	_prepare_pavement(data)
	_short_grass()
	for i in grass_patches.size():
		_tall_grass(grass_patches[i])
		if i % 12 == 11:
			await _loading_batch(progress, "Preparando vegetação…", 0.87 + 0.1 * float(i) / maxf(1, grass_patches.size()))
	_fence()
	_resource_glow = CollectibleGlow.new()
	add_child(_resource_glow)
	_resource_glow.call("setup", resources)
	await _loading_batch(progress, "Finalizando o mundo…", 1.0)
	_cull_details.call_deferred()

## Objetos pequenos (móveis, janelas, placas, detalhes da cidade do meio) somem
## de longe: a maior parte das chamadas de desenho era de coisas de 1 m a 200 m.
func _cull_details() -> void:
	var root := get_parent() if get_parent() != null else self
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g is MultiMeshInstance3D or g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0 or _in_character(g):
			continue
		var box := g.get_aabb()
		var longest := maxf(box.size.x * g.global_basis.get_scale().x, maxf(box.size.y * g.global_basis.get_scale().y, box.size.z * g.global_basis.get_scale().z))
		if g is Label3D:
			g.visibility_range_end = 70.0
		elif longest < 1.6:
			g.visibility_range_end = 50.0
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif longest < 5.0:
			g.visibility_range_end = 170.0
		elif longest < 14.0:
			g.visibility_range_end = 320.0

func _in_character(node: Node) -> bool:
	var n := node.get_parent()
	while n != null:
		if n is CharacterBody3D or n is VehicleBody3D:
			return true
		n = n.get_parent()
	return false

# ------------------------------------------------------------------ grama ---
# Grama baixa espalhada pelo campo (só visual, some de longe) e manchas de
# grama alta (1,3–1,7 m): agachado dentro delas, zumbis só te veem bem de perto.
var grass_patches: Array = []
var _pavement: Dictionary = {"roads": [], "buildings": []}
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
				if absf(p.x) < center_half + 1 and absf(p.z) < center_half + 1:
					continue
				if in_pond(p, 0.5) or _on_pavement(p):
					continue
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
				list.append(Transform3D(basis, p))
			if not list.is_empty():
				var node := _multimesh(mesh, list, 55.0)
				node.name = "ShortGrass"
			z += tile
		x += tile

## Ponto em cima de estrada ou dentro de prédio? (sem capim no asfalto nem no piso)
func _on_pavement(p: Vector3) -> bool:
	for b in _pavement["buildings"]:
		var r: Rect2 = b
		if r.has_point(Vector2(p.x, p.z)):
			return true
	for road in _pavement["roads"]:
		var a: Vector2 = road[0]
		var b2: Vector2 = road[1]
		var box: Rect2 = road[3]
		if not box.has_point(Vector2(p.x, p.z)):
			continue
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b2)
		if q.distance_to(Vector2(p.x, p.z)) < float(road[2]):
			return true
	return false

## Estradas e prédios do mapa, prontos para _on_pavement (com caixa para descartar rápido).
func _prepare_pavement(data: Dictionary) -> void:
	_pavement = {"roads": [], "buildings": []}
	for road in data.get("roads", []):
		var a := Vector2(float(road["from"][0]), float(road["from"][1]))
		var b := Vector2(float(road["to"][0]), float(road["to"][1]))
		var half := float(road.get("width", 6)) * 0.5 + 0.3
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(half)
		_pavement["roads"].append([a, b, half, box])
	for building in data.get("buildings", []):
		var size := Vector2(float(building["size"][0]), float(building["size"][1]))
		var center := Vector2(float(building["center"][0]), float(building["center"][1]))
		_pavement["buildings"].append(Rect2(center - size * 0.5, size))

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
		# Chão, estrada, parede e telhado: atlas urbano (map_materials.gd);
		# madeira, metal e o resto continuam em SurfaceMaterials.
		var atlas := MapMaterials.surface(kind, hex) if kind != "flat" else null
		if atlas != null:
			_mats[key] = atlas
		else:
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

## Chão de grama do mundo inteiro (mapas antigos: quatro placas em volta da
## cidade do meio, que tem o próprio chão).
func _ground() -> void:
	var grass := _mat("grass", "#5d7a4e")
	var h := half_size
	var c := center_half
	var slabs := [[Vector3(0, -0.5, 0), Vector3(h * 2, 1, h * 2)]]
	if c > 0.0:
		slabs = [
			[Vector3(0, -0.5, -(h + c) * 0.5), Vector3(h * 2, 1, h - c)],
			[Vector3(0, -0.5, (h + c) * 0.5), Vector3(h * 2, 1, h - c)],
			[Vector3(-(h + c) * 0.5, -0.5, 0), Vector3(h - c, 1, c * 2)],
			[Vector3((h + c) * 0.5, -0.5, 0), Vector3(h - c, 1, c * 2)],
		]
	for slab in slabs:
		_solid(self, slab[0], slab[1], grass).name = "Ground"
	# Manchas de terra e de grama mais clara/escura, para o campo não ficar liso.
	var tints := [_mat("dirt", "#7a6a4f"), _mat("grass", "#6f8a52"), _mat("grass", "#4e6a40"), _mat("grass", "#7c8e4a")]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lists: Array = [[], [], [], []]
	for i in 220:
		var p := Vector3(rng.randf_range(-h + 10, h - 10), 0.004 + (i % 4) * 0.003, rng.randf_range(-h + 10, h - 10))
		if c > 0.0 and absf(p.x) < c + 10 and absf(p.z) < c + 10:
			continue
		var size := rng.randf_range(8, 30) if i % 4 else rng.randf_range(5, 14)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, 1.0, size * rng.randf_range(0.5, 1.2)))
		lists[i % 4].append(Transform3D(basis, p))
	# Um lote por cor (4 chamadas de desenho em vez de ~200).
	for k in 4:
		_flat_batch(_box_mesh(Vector3(1, 0.01, 1)), tints[k], lists[k], "GroundPatches")

## Várias caixas iguais num MultiMesh só (sem sombra).
func _flat_batch(mesh: Mesh, material: Material, transforms: Array, title: String) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)

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
	# Faixa amarela tracejada no meio (um lote por estrada).
	var step := 7.0
	var n := int(length / step)
	var dashes: Array = []
	var basis := Basis(Vector3.UP, node.rotation.y)
	for i in n:
		dashes.append(Transform3D(basis, node.position + basis * Vector3(0, 0.012, -length * 0.5 + (i + 0.5) * step)))
	_flat_batch(_box_mesh(Vector3(0.15, 0.01, 3.0)), _mat("flat", "#cdb56a"), dashes, "RoadPaint")

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
	_building_lod(root, w, d, h, wall)

## Prédio em 3 níveis: perto tudo (placa e piso só aqui); médio paredes, teto e
## janelas; longe um bloco só no lugar das ~10 peças (1 desenho em vez de ~10).
func _building_lod(root: Node3D, w: float, d: float, h: float, wall: Material) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.get_parent() is StaticBody3D:
			_lod_range(g, 0, LOD_MID) # paredes e teto (com sombra)
		elif g is Label3D or g.get_aabb().size.y < 0.1:
			_lod_range(g, 0, LOD_NEAR) # placa e piso
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_lod_range(g, 0, LOD_MID) # janelas, cruz do hospital
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shell := MeshInstance3D.new()
	shell.name = "FarShell"
	shell.mesh = _box_mesh(Vector3(w + 0.25, h + 0.2, d + 0.25))
	shell.material_override = wall
	shell.position.y = (h + 0.2) * 0.5
	root.add_child(shell)
	_lod_range(shell, 2, LOD_FAR)

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
	"fuel": [Vector3(0.7, 1.0, 0.7), "#5a3524", "metal"],
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
	var main_part := _part(body, Vector3(0, size.y * 0.5, 0), size, mat)
	# Detalhes: porta/gaveta escura na frente, cruz no armário de remédios.
	if size.y > 1.0:
		_part(body, Vector3(0, size.y * 0.5, size.z * 0.5 + 0.01), Vector3(0.04, size.y * 0.9, 0.02), _flat("#222"))
	else:
		_part(body, Vector3(0, size.y * 0.55, size.z * 0.5 + 0.01), Vector3(size.x * 0.8, 0.04, 0.02), _flat("#222"))
	if type == "medcab":
		_part(body, Vector3(0, size.y * 0.6, size.z * 0.5 + 0.02), Vector3(0.36, 0.1, 0.01), _flat("#c8261f"))
		_part(body, Vector3(0, size.y * 0.6, size.z * 0.5 + 0.02), Vector3(0.1, 0.36, 0.01), _flat("#c8261f"))
	# Móveis ficam dentro dos prédios: o corpo some no meio da faixa média,
	# portas, gavetas e a cruz somem ainda perto. Nenhum faz sombra.
	for node in body.get_children():
		if node is MeshInstance3D:
			_lod_range(node, 0, 90.0 if node == main_part else 35.0)
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var glow := CollectibleGlow.make_marker(Vector3(0, size.y + 0.35, 0))
	body.add_child(glow)
	containers[str(spot["id"])] = {"node": body, "type": type, "pos": pos, "label": label, "glow": glow, "empty": false}

## O servidor avisou que o recipiente foi esvaziado (até reabastecer).
func set_container_empty(id: String, empty: bool) -> void:
	var entry: Dictionary = containers.get(id, {})
	if entry.is_empty():
		return
	entry["empty"] = empty
	if entry.has("glow"):
		entry["glow"].visible = not empty
	entry["label"].modulate = Color("#9a9a9a") if empty else Color("#ffe08a")

# --------------------------------------------------------------- recursos ---

func _resource(res: Dictionary) -> void:
	var kind := str(res["kind"])
	var p: Array = res["p"]
	if kind in PICKUPS or kind == "pond":
		_light_resource(res, kind, Vector3(float(p[0]), 0, float(p[2])))
		return
	var body := StaticBody3D.new()
	body.name = "Res_" + str(res["id"])
	body.collision_layer = HitboxScript.LAYER_WORLD
	body.position = Vector3(float(p[0]), 0, float(p[2]))
	body.rotation.y = float(res.get("yaw", 0.0))
	add_child(body)
	var parts: Array = []
	var seed_value := int(str(res["id"]).substr(1))
	var s := 0.8 + float(seed_value % 7) * 0.07
	var slots := {}
	var xform := Transform3D(Basis(Vector3.UP, body.rotation.y).scaled(Vector3.ONE * s), body.position)
	match kind:
		"tree":
			# Desenhada em lote (MultiMesh); o corpo só guarda a colisão do tronco.
			var variant: String = NatureModel.tree_variant(seed_value)
			var tree_scale := s * (1.12 if variant.begins_with("pine") else 1.0)
			xform = Transform3D(Basis(Vector3.UP, body.rotation.y).scaled(Vector3.ONE * tree_scale), body.position)
			slots["full"] = _slot(variant, xform, true)
			slots["empty"] = _slot("stump", xform, false)
			_collider(body, CylinderShape3D.new(), Vector3(0, 1.5, 0), 0.32 * tree_scale, 3.0)
		"rock", "ore", "saltpeter":
			var rock_variant: String = {"rock": "rock", "ore": "rock_ore", "saltpeter": "rock_salt"}[kind]
			slots["full"] = _slot(rock_variant, xform, true)
			_collider(body, SphereShape3D.new(), Vector3(0, 0.35 * s, 0), 1.0 * s, 0.0)
		"car":
			# Carro abandonado realista (ferrugem, vidro sujo, pneu murcho às vezes).
			var colors := ["#7a2e28", "#2e4b6a", "#8a8a80", "#3d5a3a", "#8a7a52", "#c9c4b8", "#2b2b2b"]
			var car_kind: String = ["sedan", "hatch", "pickup"][seed_value % 3]
			var model := CarModel.build(car_kind, colors[seed_value % colors.size()], true, seed_value)
			body.add_child(model)
			parts.append(model)
			# Perto: carroceria e rodas; médio: só a carroceria; longe: um bloco na cor.
			CarModel.apply_lod(model, car_kind, colors[seed_value % colors.size()], LOD_NEAR, LOD_MID, 380.0)
			var size := CarModel.size_of(car_kind)
			var shape := BoxShape3D.new()
			shape.size = Vector3(size.x, size.y - 0.2, size.z)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.position.y = 0.2 + shape.size.y * 0.5
			body.add_child(col)
			body.rotation.z = 0.03 * float(seed_value % 3 - 1)
		"bush":
			slots["full"] = _slot("bush_full", xform, true)
			slots["empty"] = _slot("bush_empty", xform, false)
			_collider(body, SphereShape3D.new(), Vector3(0, 0.5 * s, 0), 0.6 * s, 0.0)
	resources[str(res["id"])] = {"node": body, "kind": kind, "pos": body.position, "parts": parts, "slots": slots, "depleted": false, "r": 0.0}

## Coisa do chão (galho, pedrinha, capim, erva) ou lago: sem corpo nem colisão.
## O que aparece na tela fica no lote (MultiMesh) ou na água do lago.
func _light_resource(res: Dictionary, kind: String, pos: Vector3) -> void:
	var slots := {}
	if kind != "pond":
		var seed_value := int(str(res["id"]).substr(1))
		var s := 0.85 + float(seed_value % 5) * 0.08
		slots["full"] = _slot(kind, Transform3D(Basis(Vector3.UP, float(res.get("yaw", 0.0))).scaled(Vector3.ONE * s), pos), true)
	resources[str(res["id"])] = {"node": null, "kind": kind, "pos": pos, "parts": [], "slots": slots, "depleted": false, "r": float(res.get("r", 0.0))}

## Galho natural do servidor: o visual cai; o ponto de coleta fica no chão.
func add_branch(res: Dictionary, animate: bool = false) -> void:
	var id := str(res.get("id", ""))
	if id.is_empty() or resources.has(id):
		return
	var p: Array = res.get("p", [])
	if p.size() != 3:
		return
	var node := Node3D.new()
	node.name = "FallenBranch"
	node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var visual := MeshInstance3D.new()
	visual.mesh = NatureModel.mesh("stick")
	visual.rotation.y = float(res.get("yaw", 0.0))
	visual.visibility_range_end = PICKUP_RANGE
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(visual)
	add_child(node)
	resources[id] = {"node": node, "kind": "stick", "pos": node.position, "parts": [visual], "slots": {}, "depleted": false, "r": 0.0, "dynamic": true}
	if _resource_glow != null:
		_resource_glow.call("add_resource", id, resources[id])
	if animate:
		visual.position.y = 2.7
		visual.rotation.z = 0.8
		var fall := visual.create_tween().set_parallel(true)
		fall.tween_property(visual, "position:y", 0.0, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(visual, "rotation:z", 0.0, 0.85)

func remove_branch(id: String) -> void:
	var entry: Dictionary = resources.get(id, {})
	if not bool(entry.get("dynamic", false)):
		return
	if _resource_glow != null:
		_resource_glow.call("remove_resource", id)
	entry["node"].queue_free()
	resources.erase(id)

func add_fruit(res: Dictionary, animate: bool = false) -> void:
	var id := str(res.get("id", ""))
	var p: Array = res.get("p", [])
	var kind := str(res.get("kind", ""))
	if id.is_empty() or fallen_fruit.has(id) or p.size() != 3 or kind not in ["apple", "acorn"]:
		return
	var node := Node3D.new()
	node.name = "FallenApple" if kind == "apple" else "FallenAcorn"
	node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	var visual := MeshInstance3D.new()
	visual.mesh = NatureModel.fruit_mesh(kind)
	visual.set_meta("preserve_authored_material", true)
	visual.visibility_range_end = 75.0
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(visual)
	add_child(node)
	fallen_fruit[id] = {"node": node, "kind": kind, "pos": node.position}
	if animate:
		visual.position.y = 2.5
		var fall := visual.create_tween()
		fall.tween_property(visual, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func remove_fruit(id: String) -> void:
	var fruit: Dictionary = fallen_fruit.get(id, {})
	if fruit.is_empty():
		return
	fruit["node"].queue_free()
	fallen_fruit.erase(id)

# ------------------------------------------------------------------ lagos ---

var _water_material: ShaderMaterial
var _water_mesh: ArrayMesh
var _shore_material: StandardMaterial3D

## Lago raso com ondas leves e reflexos em movimento; coleta e colisão preservadas.
func _pond(data: Dictionary) -> void:
	if _water_material == null:
		_water_material = LakeWater.material()
		_water_mesh = LakeWater.mesh()
		_shore_material = _mat("dirt", "#4f4334")
	var r := float(data["r"])
	var node := Node3D.new()
	node.name = "Pond"
	node.position = Vector3(float(data["x"]), 0, float(data["z"]))
	add_child(node)
	var shore := MeshInstance3D.new()
	shore.name = "Shore"
	shore.mesh = LakeWater.shore_mesh(r - 0.15, r + 1.4)
	shore.material_override = _shore_material
	shore.position.y = 0.022
	node.add_child(shore)
	shore.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = _water_mesh
	water.material_override = _water_material
	water.position.y = 0.036
	water.scale = Vector3(r, 1.0, r)
	node.add_child(water)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Juncos na beira da água.
	var reeds: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(node.position.x * 31 + node.position.z * 17)
	for i in int(r * 5):
		var a := rng.randf() * TAU
		var d := r + rng.randf_range(-0.3, 0.9)
		reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, rng.randf_range(0.9, 1.6), 1)), node.position + Vector3(cos(a) * d, 0, sin(a) * d)))
	_multimesh(_clump_mesh(6, 0.9, 0.06, Color("#3d4a26"), Color("#8b8a52")), reeds, 120.0).name = "Reeds"

## Ponto dentro (ou a até `margin` m) de um lago?
func in_pond(point: Vector3, margin: float = 0.0) -> bool:
	for pond in ponds:
		var r := float(pond["r"]) + margin
		var dx := point.x - float(pond["x"])
		var dz := point.z - float(pond["z"])
		if dx * dx + dz * dz < r * r:
			return true
	return false

# ---------------------------------------------------- desenho em lote ---
# Árvores, pedras e arbustos: um MultiMesh por modelo, por nível de detalhe e
# por quadrado de 120 m (o motor descarta quadrados fora da câmera).
# Esconder = escala zero naquela posição do lote (em todos os níveis).
const CHUNK := 120.0
const HAS_SILHOUETTE := ["pine_a", "pine_b", "oak_a", "oak_b", "birch", "rock", "rock_ore", "rock_salt"]
var _batches: Dictionary = {} # "modelo|cx|cz" -> {variant, center, list, mms}

func _slot(variant: String, xform: Transform3D, visible: bool) -> Array:
	var cx := int(floor((xform.origin.x + half_size) / CHUNK))
	var cz := int(floor((xform.origin.z + half_size) / CHUNK))
	var key := "%s|%d|%d" % [variant, cx, cz]
	if not _batches.has(key):
		var center := Vector3((cx + 0.5) * CHUNK - half_size, 0, (cz + 0.5) * CHUNK - half_size)
		_batches[key] = {"variant": variant, "center": center, "list": [], "mms": []}
	var batch: Dictionary = _batches[key]
	var local := Transform3D(xform.basis, xform.origin - batch["center"])
	batch["list"].append(local if visible else _hidden(local))
	return [key, batch["list"].size() - 1, local]

static func _hidden(local: Transform3D) -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), local.origin)

func _flush_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var variant: String = batch["variant"]
		# Árvores e pedras: perto / médio / longe (silhueta). Arbusto e toco são
		# pequenos: perto (com sombra) e médio (sem sombra), e somem de longe.
		var levels := [0, 1, 2] if variant in HAS_SILHOUETTE else [0, 1]
		if variant in PICKUPS:
			levels = [0] # coisas do chão: só de perto
		for lod in levels:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = NatureModel.mesh(variant, lod if variant in HAS_SILHOUETTE else 0)
			mm.instance_count = batch["list"].size()
			for i in batch["list"].size():
				mm.set_instance_transform(i, batch["list"][i])
			var node := MultiMeshInstance3D.new()
			node.name = "Nature_%s_lod%d" % [variant, lod]
			node.multimesh = mm
			node.position = batch["center"]
			var end := LOD_FAR if lod == 2 else (LOD_MID if variant in HAS_SILHOUETTE else LOD_SMALL_MID)
			_lod_range(node, lod, end if lod > 0 else (PICKUP_RANGE if variant in PICKUPS else LOD_NEAR))
			if variant in PICKUPS:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
			batch["mms"].append(mm)

# ------------------------------------------------------ níveis de detalhe ---
# Três faixas pela distância da câmera: quanto mais longe, menos detalhe.
#   perto  0–60 m:   modelo completo, com sombra
#   médio  60–170 m: modelo leve, sem sombra, detalhes pequenos somem
#   longe  170–430 m: silhuetas e blocos (a neblina cobre o resto)
const LOD_NEAR := 60.0
const LOD_MID := 170.0
const LOD_FAR := 430.0
const LOD_SMALL_MID := 140.0 # coisas pequenas (arbusto, toco, rodas): somem antes
const LOD_MARGIN := 6.0 # folga para não piscar na troca de nível

## Faixa do nível `lod` (0 perto, 1 médio, 2 longe), terminando em `end`.
## Só o nível perto faz sombra.
func _lod_range(node: GeometryInstance3D, lod: int, end: float) -> void:
	node.visibility_range_begin = [0.0, LOD_NEAR, LOD_MID][lod]
	node.visibility_range_end = end
	node.visibility_range_begin_margin = LOD_MARGIN
	node.visibility_range_end_margin = LOD_MARGIN
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _set_slot(slot: Array, visible: bool, scale_factor: float = 1.0) -> void:
	if slot.is_empty():
		return
	var local: Transform3D = slot[2]
	var xform := Transform3D(local.basis.scaled(Vector3.ONE * scale_factor), local.origin) if visible else _hidden(local)
	for mm in _batches[slot[0]]["mms"]:
		(mm as MultiMesh).set_instance_transform(int(slot[1]), xform)

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

## Coletado: a árvore vira toco, a pedra encolhe, o arbusto fica sem frutas,
## galho/pedrinha/capim/erva somem (até voltar).
func set_depleted(id: String, value: bool) -> void:
	var entry: Dictionary = resources.get(id, {})
	if entry.is_empty() or bool(entry["depleted"]) == value:
		return
	entry["depleted"] = value
	if _resource_glow != null:
		_resource_glow.call("set_active", id, not value)
	var slots: Dictionary = entry.get("slots", {})
	match str(entry["kind"]):
		"stick", "pebble", "fiber", "herb":
			_set_slot(slots.get("full", []), not value)
		"tree", "bush":
			_set_slot(slots.get("full", []), not value)
			_set_slot(slots.get("empty", []), value)
		"rock", "ore", "saltpeter":
			_set_slot(slots.get("full", []), true, 0.45 if value else 1.0)
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
