extends Node3D
## Mapa da partida online, montado com blocos coloridos e lisos (visual de
## brinquedo, sem texturas) a partir de data/match_maps.json:
## Praça central (Eliminatória), Cruz (Mata-mata) e Equipes (2x2 e 4x4).
## Uma malha por cor (poucas draw calls) e um StaticBody3D com todas as caixas.
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const BotNav = preload("res://scripts/net/bot_nav.gd")

var map_half := 40.0
var half_x := 40.0
var half_z := 40.0
var map_id := ""
var _mats: Dictionary = {}

func _ready() -> void:
	name = "MatchMap"
	BotNav.reset()
	var layout := MatchLayout.load_layout()
	map_id = str(layout.get("id", ""))
	half_x = float(layout.get("half_x", 40))
	half_z = float(layout.get("half_z", 40))
	map_half = float(layout.get("map_half_size", maxf(half_x, half_z)))
	_tune_environment()
	var palette := MatchLayout.palette()
	var body := StaticBody3D.new()
	body.name = "MapCollision"
	body.collision_layer = HitboxScript.LAYER_WORLD
	add_child(body)
	# Chão: a área jogável e uma faixa em volta dos muros (só visual).
	var ground := str(layout.get("ground", "grass"))
	var margin := 24.0
	var batches: Dictionary = {}
	_add_box(batches, ground, Vector3(0, -0.5, 0), Vector3(half_x * 2 + margin * 2, 1, half_z * 2 + margin * 2))
	_collider(body, Vector3(0, -0.5, 0), Vector3(half_x * 2 + 4, 1, half_z * 2 + 4))
	for part in layout.get("parts", []):
		var center := Vector3(float(part[0]), float(part[1]), float(part[2]))
		var size := Vector3(float(part[3]), float(part[4]), float(part[5]))
		_add_box(batches, str(part[6]), center, size)
		_collider(body, center, size)
	for colour in batches:
		var mesh := MeshInstance3D.new()
		mesh.name = "Blocks_" + str(colour)
		mesh.mesh = (batches[colour] as SurfaceTool).commit()
		mesh.material_override = _material(str(palette.get(colour, "#a3a2a5")))
		add_child(mesh)
	_edge_barriers()

func _material(hex: String) -> StandardMaterial3D:
	if _mats.has(hex):
		return _mats[hex]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = 0.55
	material.metallic = 0.0
	material.metallic_specular = 0.35
	# As faces das caixas são montadas à mão: sem culling, nenhuma some por
	# causa da ordem dos vértices.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[hex] = material
	return material

func _collider(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = center
	body.add_child(collider)

## Caixa alinhada aos eixos na malha da cor (6 faces, normais retas).
func _add_box(batches: Dictionary, colour: String, center: Vector3, size: Vector3) -> void:
	if not batches.has(colour):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[colour] = tool
	var st: SurfaceTool = batches[colour]
	var h := size * 0.5
	var faces := [
		[Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3.DOWN, Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3.RIGHT, Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3.LEFT, Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3.BACK, Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3.FORWARD, Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for face in faces:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var c := center + n * h
		var du := u * h
		var dv := v * h
		var corners := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		for index in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.add_vertex(corners[index])

func _tune_environment() -> void:
	var parent := get_parent()
	if parent == null or parent.get_node_or_null("WorldEnvironment") == null:
		return
	var env := (parent.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#3d8fe0")
	sky_material.sky_horizon_color = Color("#bfe0f7")
	sky_material.ground_bottom_color = Color("#6f8f6a")
	sky_material.ground_horizon_color = Color("#bfe0f7")
	sky_material.sun_angle_max = 4.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffffff")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.fog_enabled = false
	var sun := parent.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 0.88
		sun.light_color = Color("#fffaf0")
		sun.rotation_degrees = Vector3(-55, -35, 0)
		sun.directional_shadow_max_distance = 80.0

## Muro invisível de 30 m em cada borda: ninguém pula nem escala para fora.
func _edge_barriers() -> void:
	var thickness := 0.8
	for spec in [
		[Vector3(half_x - 0.4, 15, 0), Vector3(thickness, 30, half_z * 2)],
		[Vector3(-half_x + 0.4, 15, 0), Vector3(thickness, 30, half_z * 2)],
		[Vector3(0, 15, half_z - 0.4), Vector3(half_x * 2, 30, thickness)],
		[Vector3(0, 15, -half_z + 0.4), Vector3(half_x * 2, 30, thickness)],
	]:
		var barrier := StaticBody3D.new()
		barrier.name = "EdgeBarrier"
		barrier.position = spec[0]
		add_child(barrier)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec[1]
		collider.shape = shape
		barrier.add_child(collider)
