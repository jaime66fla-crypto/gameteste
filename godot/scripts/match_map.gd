extends Node3D
## Mapa da partida online, montado com blocos a partir de data/match_maps.json:
## Praça central (Eliminatória), Cruz (Mata-mata) e Equipes (2x2 e 4x4).
## Cada cor da paleta vira um material PBR do atlas urbano (map_materials.gd:
## grama, asfalto, piso de pedra, concreto, tijolo, telha ondulada, caixotes e
## reboco pintado nas casas coloridas).
## Uma malha por cor (poucas draw calls) e um StaticBody3D com todas as caixas.
const LfGraphics = preload("res://scripts/lf_graphics.gd")
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const MapMaterials = preload("res://scripts/map_materials.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const BotNav = preload("res://scripts/net/bot_nav.gd")

var map_half := 40.0
var half_x := 40.0
var half_z := 40.0
var map_id := ""

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
		mesh.material_override = MapMaterials.for_colour(str(colour), str(palette.get(colour, "#a3a2a5")))
		# Keep the urban atlas and relief when the shared character style runs.
		mesh.set_meta("preserve_authored_material", true)
		add_child(mesh)
	_edge_barriers()

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
		# UV da face inteira (0..1): os caixotes mostram a imagem uma vez por face;
		# as outras superfícies usam triplanar e ignoram isto.
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for index in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uvs[index])
			st.set_normal(n)
			st.add_vertex(corners[index])

func _tune_environment() -> void:
	# Gráfico do Linha de Fogo (scripts/lf_graphics.gd).
	var holder := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder == null:
		return
	LfGraphics.apply(holder.environment, get_parent().get_node_or_null("Sun") as DirectionalLight3D)

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
