extends Node3D
## Bairro de parkour em volta da cidade (mapa de 200 m, só treino e mata-mata).
## Um anel de rua a 66 m liga as avenidas da cidade a quatro faixas de lotes:
## sobrados (dois andares, janelas abertas, varanda e laje), casas térreas e
## pistas de parkour, com caçambas, lixeiras, caixotes, paletes e cercas.
##
## O pulo sobe ~1,6 m (jump_velocity 8,5 / gravidade 22), então toda rota
## sobe em degraus de no máximo 1,45 m:
##   sobrado, lado direito: chão > caçamba 1,3 > depósito 2,0 > varanda 3,4 >
##   caixote 4,8 > caixote 6,2 > laje 6,6; pelos telhados dá para pular de casa
##   em casa (vão de 2,7 m).
##   sobrado, frente: caixote 1,3 > marquise 2,75 > janela do 1º andar 3,9.
##   térrea: caçamba 1,3 > caixote 2,4 > laje 3,6.
## Cada lote vira um StaticBody3D com uma malha por material (poucas draw calls).
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")

const RING := 66.0 # eixo do anel de rua
const ROAD_W := 6.0
const BAND := 80.0 # centro das casas
const LOT := 13.0 # passo entre lotes
const WALL := 0.25
const FLOOR_H := 3.4 # piso do 1º andar
const ROOF_Y := 6.4 # base da laje do sobrado
const ALONG := [-91.0, -78.0, -65.0, -52.0, -39.0, -26.0, -13.0, 0.0, 13.0, 26.0, 39.0, 52.0, 65.0, 78.0, 91.0]
const SIDE_ALONG := [-52.0, -39.0, -26.0, -13.0, 0.0, 13.0, 26.0, 39.0, 52.0]
const HOUSE_COLORS := ["#c7b596", "#acb6af", "#cabd9f", "#a2acb4", "#c9a98e", "#b7b39a", "#9fb0a6"]

var _body: StaticBody3D
var _tools: Dictionary = {}
var _tool_mats: Dictionary = {}

## Lotes do bairro: centro no chão, rotação (frente local +Z vira para a
## cidade), tipo e área ocupada (alinhada aos eixos), para o minimapa também.
static func lots() -> Array:
	var result: Array = []
	var index := 0
	for band in [[Vector2(0, -BAND), 0.0, true], [Vector2(0, BAND), PI, true], [Vector2(-BAND, 0), PI * 0.5, false], [Vector2(BAND, 0), -PI * 0.5, false]]:
		var list: Array = ALONG if band[2] else SIDE_ALONG
		for along in list:
			var center: Vector2 = band[0] + (Vector2(along, 0) if band[2] else Vector2(0, along))
			var kind: String = ["sobrado", "sobrado", "pista", "sobrado", "terrea"][index % 5]
			var size := Vector2(10, 8) if kind == "sobrado" else (Vector2(9, 8) if kind == "terrea" else Vector2(12, 12))
			if not band[2]:
				size = Vector2(size.y, size.x)
			result.append({"center": center, "yaw": band[1], "kind": kind, "index": index, "size": size})
			index += 1
	return result

## Ruas do bairro para o minimapa: [de, até, largura].
static func roads() -> Array:
	var r := RING
	var list: Array = [
		[Vector2(-r - 3, -r), Vector2(r + 3, -r), ROAD_W], [Vector2(-r - 3, r), Vector2(r + 3, r), ROAD_W],
		[Vector2(-r, -r), Vector2(-r, r), ROAD_W], [Vector2(r, -r), Vector2(r, r), ROAD_W],
	]
	for lane in [-48.0, 0.0, 48.0]:
		for side in [-1.0, 1.0]:
			list.append([Vector2(lane, side * 52.0), Vector2(lane, side * (r - 3.0)), ROAD_W])
			list.append([Vector2(side * 52.0, lane), Vector2(side * (r - 3.0), lane), ROAD_W])
	return list

## false: só as bases de parkour na faixa da cidade (mata-mata e sala
## personalizada, mapa de 120 m); true: o bairro inteiro (treino offline).
var full := true

## Bases compactas na faixa de grama entre a rua do anel (±52) e o muro
## (±59,2), entre as árvores da borda: [centro, rotação (frente para a cidade)].
static func bases() -> Array:
	var result: Array = []
	for along in [-36.0, -12.0, 12.0, 36.0]:
		result.append([Vector2(along, -BASE_AT), 0.0])
		result.append([Vector2(along, BASE_AT), PI])
		result.append([Vector2(-BASE_AT, along), PI * 0.5])
		result.append([Vector2(BASE_AT, along), -PI * 0.5])
	return result

const BASE_AT := 56.6

## Sobrevivência: lotes e bases vindos de data/survival_world.json ("parkour",
## "parkour_bases"); quando preenchido, monta só isso (sem o anel do treino).
var survival_lots: Array = []
var survival_bases: Array = []

func _ready() -> void:
	name = "ParkourDistrict"
	if not survival_lots.is_empty() or not survival_bases.is_empty():
		for lot in survival_lots:
			_build_lot({"center": Vector2(float(lot["center"][0]), float(lot["center"][1])), "yaw": float(lot["yaw"]), "kind": String(lot["kind"]), "index": int(lot["index"])})
		for b in survival_bases.size():
			var spot: Dictionary = survival_bases[b]
			_base(Vector2(float(spot["center"][0]), float(spot["center"][1])), float(spot["yaw"]), b)
		return
	var n := 0
	for spot in bases():
		_base(spot[0], spot[1], n)
		n += 1
	if not full:
		return
	_streets()
	for lot in lots():
		_build_lot(lot)
	_border_trees()

func _build_lot(lot: Dictionary) -> void:
	match String(lot["kind"]):
		"sobrado":
			_two_story(lot)
		"terrea":
			_one_story(lot)
		_:
			_course(lot)

## Base de parkour (9 × 5 m, fundo encostado no muro): caçamba 1,3 >
## caixote 2,4 > andaime 3,6 > viga > andaime 3,6 > caixotes 2,4 / 1,2 > chão,
## mais mureta de vault e lixeiras.
func _base(center: Vector2, yaw: float, n: int) -> void:
	_begin(center, yaw, "BaseParkour_%02d" % n)
	_body.add_to_group("parkour_base")
	_dumpster(-3.5, 1.4, true, "#4a5f73" if n % 2 == 0 else "#3f6b4a")
	_crate(Vector3(-3.5, 1.2, -0.3), Vector3(1.0, 2.4, 1.0))
	_scaffold(Vector3(-1.4, 3.6, -1.4))
	_add(Vector3(0.8, 3.52, -1.4), Vector3(2.4, 0.15, 0.25), "#58646a", "metal")
	_scaffold(Vector3(3.0, 3.6, -1.4))
	_crate(Vector3(3.0, 1.2, 0.5), Vector3(1.0, 2.4, 1.0))
	_crate(Vector3(3.0, 0.6, 1.6), Vector3(1.0, 1.2, 1.0))
	_add(Vector3(0.6, 0.45, 1.7), Vector3(2.2, 0.9, 0.3), "#a9aaa1", "concrete")
	_bin(-1.6, 2.1)
	_pallets(0.8, 0.2, 2)
	_end()

# ------------------------------------------------------------------ malha ---

func _begin(center: Vector2, yaw: float, title: String) -> void:
	_body = StaticBody3D.new()
	_body.name = title
	_body.position = Vector3(center.x, 0, center.y)
	_body.rotation.y = yaw
	add_child(_body)
	_tools.clear()

func _tool(color: String, kind: String) -> SurfaceTool:
	var key := kind + color
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
		if not _tool_mats.has(key):
			_tool_mats[key] = SurfaceMaterials.make(kind, Color(color))
	return _tools[key]

## Caixa no espaço local do lote atual; `solid` cria a colisão.
func _add(center: Vector3, size: Vector3, color: String, kind: String = "plaster", solid: bool = true, basis: Basis = Basis.IDENTITY) -> void:
	var box := BoxMesh.new()
	box.size = size
	_tool(color, kind).append_from(box, 0, Transform3D(basis, center))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		_collider(shape, Transform3D(basis, center))

func _add_cyl(center: Vector3, radius: float, height: float, color: String, kind: String = "metal") -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	cyl.rings = 1
	_tool(color, kind).append_from(cyl, 0, Transform3D(Basis.IDENTITY, center))
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_collider(shape, Transform3D(Basis.IDENTITY, center))

func _collider(shape: Shape3D, xform: Transform3D) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = xform
	_body.add_child(collider)

func _end() -> void:
	for key in _tools:
		var instance := MeshInstance3D.new()
		instance.mesh = (_tools[key] as SurfaceTool).commit()
		instance.material_override = _tool_mats[key]
		_body.add_child(instance)
	_tools.clear()

## Rampa de `from` (pé) até `to` (topo); a superfície passa pelos dois pontos.
## visible = false: só a colisão (o piso das escadas).
func _ramp(from: Vector3, to: Vector3, width: float, color: String, kind: String = "concrete", visible: bool = true) -> void:
	var dir := (to - from).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir)
	var thickness := 0.25
	var start := from - dir * 0.6 # enterrada no piso
	var length := start.distance_to(to)
	var center := (start + to) * 0.5 - up * thickness * 0.5
	var basis := Basis(right, up, -dir)
	if visible:
		_add(center, Vector3(width, thickness, length), color, kind, true, basis)
	else:
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, thickness, length)
		_collider(shape, Transform3D(basis, center))

## Escada usável: degraus de ~20 cm (visuais) sobre uma rampa invisível que o
## jogador sobe andando (o CharacterBody não sobe degrau). `base` é o pé da
## escada no chão, `dir` a direção horizontal da subida.
func _stairs(base: Vector3, dir: Vector3, run: float, rise: float, width: float, color: String = "#a9aaa1") -> void:
	var n := maxi(2, roundi(rise / 0.2))
	var tread := run / n
	var step := rise / n
	var turn := Basis(Vector3.UP, atan2(dir.x, dir.z))
	# Degraus para os pés (camada própria): o IK dos pés pisa neles, o corpo segue a rampa.
	var probe := StaticBody3D.new()
	probe.name = "StairSteps"
	probe.collision_layer = HitboxScript.LAYER_FOOT_PROBE
	probe.collision_mask = 0
	_body.add_child(probe)
	for k in n:
		var top := (k + 1) * step
		# Cada degrau desce até o chão nos primeiros e vira uma laje fina no alto.
		var height := minf(top, 0.45)
		var center := base + dir * ((k + 0.5) * tread) + Vector3(0, top - height * 0.5, 0)
		_add(center, Vector3(width, height, tread + 0.01), color, "concrete", false, turn)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, height, tread + 0.01)
		shape.shape = box
		shape.transform = Transform3D(turn, center)
		probe.add_child(shape)
	# Viga inclinada por baixo dos degraus (só visual) e corrimão do lado de fora.
	var foot := base
	var head := base + dir * run + Vector3(0, rise, 0)
	var slope := (head - foot).normalized()
	var right := slope.cross(Vector3.UP).normalized()
	var up := right.cross(slope)
	var length := foot.distance_to(head)
	_add((foot + head) * 0.5 - up * 0.3, Vector3(width * 0.8, 0.2, length), "#7d7f78", "concrete", false, Basis(right, up, -slope))
	# Corrimão à esquerda de quem sobe (lado de fora: as escadas ficam encostadas na parede à direita).
	_add((foot + head) * 0.5 + up * 0.95 - right * (width * 0.5 - 0.04), Vector3(0.06, 0.06, length), "#3b4949", "metal", false, Basis(right, up, -slope))
	# Piso: passa pelo meio dos degraus.
	_ramp(base + Vector3(0, step * 0.5, 0), head, width, color, "concrete", false)

# ----------------------------------------------------------------- paredes ---

## Parede com vãos. along_x: corre em X no z=`at`; senão em Z no x=`at`.
## Cada vão: [centro, largura, peitoril, topo] (alturas absolutas). `out` é o
## lado de fora (+1/-1), onde ficam peitoril saliente e venezianas.
func _wall(along_x: bool, at: float, from: float, to: float, y0: float, y1: float, holes: Array, color: String, out: float) -> void:
	holes.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := from
	for hole in holes:
		var a: float = hole[0] - hole[1] * 0.5
		var b: float = hole[0] + hole[1] * 0.5
		var sill: float = hole[2]
		var top: float = hole[3]
		_piece(along_x, at, cursor, a, y0, y1, color)
		_piece(along_x, at, a, b, y0, sill, color)
		_piece(along_x, at, a, b, top, y1, color)
		var face := at + out * (WALL * 0.5)
		if sill > y0 + 0.05:
			# Peitoril de concreto saliente: degrau/apoio para escalar.
			_piece_at(along_x, face + out * 0.13, hole[0], hole[1] + 0.25, sill - 0.04, 0.08, 0.28, "#bcb8a5", "concrete", true)
			for side in [-1.0, 1.0]:
				_piece_at(along_x, face + out * 0.025, hole[0] + side * (hole[1] * 0.5 + 0.3), 0.55, sill + (top - sill) * 0.5, top - sill, 0.05, "#5c6e64", "wood", false)
		# Verga escura em cima do vão.
		_piece_at(along_x, face + out * 0.03, hole[0], hole[1] + 0.2, top + 0.07, 0.14, 0.06, "#8a8576", "concrete", false)
		cursor = b
	_piece(along_x, at, cursor, to, y0, y1, color)

func _piece(along_x: bool, at: float, a: float, b: float, y0: float, y1: float, color: String) -> void:
	if b - a < 0.01 or y1 - y0 < 0.01:
		return
	_piece_at(along_x, at, (a + b) * 0.5, b - a, (y0 + y1) * 0.5, y1 - y0, WALL, color, "plaster", true)

func _piece_at(along_x: bool, at: float, mid: float, length: float, y: float, height: float, depth: float, color: String, kind: String, solid: bool) -> void:
	if along_x:
		_add(Vector3(mid, y, at), Vector3(length, height, depth), color, kind, solid)
	else:
		_add(Vector3(at, y, mid), Vector3(depth, height, length), color, kind, solid)

# ------------------------------------------------------------------- props ---

## Caçamba de lixo (1,3 m): corpo, tampa e base. long_x: comprimento em X.
func _dumpster(x: float, z: float, long_x: bool, color: String = "#3f6b4a") -> void:
	var size := Vector3(1.8, 1.15, 1.1) if long_x else Vector3(1.1, 1.15, 1.8)
	_add(Vector3(x, 0.65, z), size, color, "metal")
	_add(Vector3(x, 1.26, z), size + Vector3(0.1, -1.07, 0.1), "#2f3d36", "metal")
	_add(Vector3(x, 0.04, z), size + Vector3(-0.2, -1.07, -0.2), "#22282a", "metal", false)

func _bin(x: float, z: float, color: String = "#4d5a63") -> void:
	_add_cyl(Vector3(x, 0.475, z), 0.3, 0.95, color)
	_add_cyl(Vector3(x, 0.975, z), 0.33, 0.05, "#2f3638")

func _crate(center: Vector3, size: Vector3) -> void:
	_add(center, size, "#8b765b", "wood")
	# Ripas escuras nas faces para ler como caixote.
	_add(center, size + Vector3(0.02, -size.y + 0.1, 0.02), "#6a5741", "wood", false)

func _pallets(x: float, z: float, layers: int) -> void:
	for i in layers:
		_add(Vector3(x, 0.07 + i * 0.15, z), Vector3(1.2, 0.13, 1.0), "#7e684b" if i % 2 == 0 else "#8b765b", "wood")

func _fence(along_x: bool, at: float, from: float, to: float, height: float = 1.8) -> void:
	var mid := (from + to) * 0.5
	var length := absf(to - from)
	_piece_at(along_x, at, mid, length, height * 0.5, height, 0.08, "#7c6c54", "wood", true)
	_piece_at(along_x, at, mid, length + 0.1, height + 0.03, 0.06, 0.12, "#5e5140", "wood", false)

func _ac_unit(center: Vector3) -> void:
	_add(center, Vector3(1.0, 0.8, 0.8), "#dfdfd4", "metal")
	_add(center + Vector3(0, 0.41, 0), Vector3(0.6, 0.02, 0.6), "#3b4949", "metal", false)

func _sign(text: String, pos: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = 0.007
	label.modulate = Color("#eee5c7")
	label.outline_size = 8
	label.position = pos
	label.rotation.y = yaw
	_body.add_child(label)

## Calçada e acesso da frente (comuns a todo lote; frente local +Z).
func _frontage(path_x: float) -> void:
	_add(Vector3(0, 0.03, 10.0), Vector3(LOT, 0.02, 2.0), "#a9aaa1", "concrete")
	if not is_nan(path_x):
		_add(Vector3(path_x, 0.03, 6.5), Vector3(1.6, 0.02, 5.0), "#bcb8a5", "concrete")

# ----------------------------------------------------------------- sobrado ---

## Janela do 1º andar (2 m de vão: dá para entrar em pé) e do térreo (vault).
func _win(c: float, wide: float) -> Array:
	return [c, wide, FLOOR_H + 0.5, FLOOR_H + 2.5]

func _low(c: float, wide: float) -> Array:
	return [c, wide, 0.9, 2.3]

func _two_story(lot: Dictionary) -> void:
	var i: int = lot["index"]
	var color: String = HOUSE_COLORS[i % HOUSE_COLORS.size()]
	_begin(lot["center"], lot["yaw"], "Sobrado_%02d" % i)
	_body.add_to_group("parkour_house")
	var w := 10.0
	var d := 8.0
	var hx := w * 0.5
	var hz := d * 0.5
	var fz := hz - WALL * 0.5 # eixo das paredes frente/fundo
	var sx := hx - WALL * 0.5 # eixo das paredes laterais
	var inner_z := hz - WALL
	# Térreo (0 – 3,4) e 1º andar (3,4 – 6,4).
	_wall(true, fz, -hx, hx, 0.0, FLOOR_H, [[0.0, 1.6, 0.0, 2.3], _low(-3.0, 1.4), _low(3.0, 1.4)], color, 1.0)
	_wall(true, fz, -hx, hx, FLOOR_H, ROOF_Y, [_win(-3.0, 1.3), _win(0.0, 1.3), _win(3.0, 1.3)], color, 1.0)
	_wall(true, -fz, -hx, hx, 0.0, FLOOR_H, [[1.0, 1.2, 0.0, 2.3], _low(3.2, 1.2)], color, -1.0)
	_wall(true, -fz, -hx, hx, FLOOR_H, ROOF_Y, [_win(-1.5, 1.3), _win(2.5, 1.3)], color, -1.0)
	_wall(false, -sx, -inner_z, inner_z, 0.0, FLOOR_H, [], color, -1.0)
	_wall(false, -sx, -inner_z, inner_z, FLOOR_H, ROOF_Y, [_win(0.0, 1.3)], color, -1.0)
	_wall(false, sx, -inner_z, inner_z, 0.0, FLOOR_H, [_low(-1.0, 1.4)], color, 1.0)
	_wall(false, sx, -inner_z, inner_z, FLOOR_H, ROOF_Y, [[1.0, 1.0, FLOOR_H, FLOOR_H + 2.2], _win(-2.6, 1.0)], color, 1.0)
	# Faixa entre os andares (só visual).
	_add(Vector3(0, FLOOR_H - 0.05, 0), Vector3(w + 0.1, 0.18, d + 0.1), "#8a8576", "concrete", false)
	# Piso do 1º andar com o vão da escada junto à parede esquerda.
	var hole_x := -hx + WALL + 1.3
	_add(Vector3((hole_x + hx - WALL) * 0.5, FLOOR_H - 0.1, 0), Vector3(hx - WALL - hole_x, 0.2, d - WALL * 2), "#a49e8c", "concrete")
	_add(Vector3((-hx + WALL + hole_x) * 0.5, FLOOR_H - 0.1, (1.5 + inner_z) * 0.5), Vector3(1.3, 0.2, inner_z - 1.5), "#a49e8c", "concrete")
	_add(Vector3(0, 0.035, 0), Vector3(w - 0.5, 0.02, d - 0.5), "#a49e8c", "concrete", false)
	# Escada interna (~38°) subindo da frente para o fundo. Termina num patamar
	# de 0,9 m na altura do piso, antes da parede do fundo: dali se sai para o
	# lado direto no 1º andar (antes a escada batia na parede e sobrava uma
	# borda de ~15 cm até o piso, que o personagem não sobe).
	var landing := 0.9
	_stairs(Vector3(-hx + WALL + 0.6, 0, 1.5), Vector3(0, 0, -1), 1.5 + inner_z - landing, FLOOR_H, 1.2, "#8f918a")
	_add(Vector3(-hx + WALL + 0.65, FLOOR_H - 0.1, -inner_z + landing * 0.5), Vector3(1.3, 0.2, landing), "#a49e8c", "concrete")
	# Metade dos sobrados tem escada externa até a laje, pelo lado esquerdo
	# (passa pela janela lateral do 1º andar).
	if i % 2 == 0:
		_stairs(Vector3(-hx - 0.6, 0, hz + 0.4), Vector3(0, 0, -1), d + 0.2, ROOF_Y + 0.2, 1.1)
	# Laje plana (andável) com caixa d'água e ar-condicionado para saltar.
	_add(Vector3(0, ROOF_Y + 0.1, 0), Vector3(w + 0.3, 0.2, d + 0.3), "#535b5b", "roof")
	_ac_unit(Vector3(-2.0, ROOF_Y + 0.6, -1.5))
	_add_cyl(Vector3(2.6, ROOF_Y + 0.8, -2.2), 0.6, 1.2, "#3b4949")
	# Marquise da porta e caixote para alcançá-la.
	_add(Vector3(0, 2.675, hz + 0.65), Vector3(2.8, 0.15, 1.3), "#58646a", "metal")
	_crate(Vector3(2.3, 0.65, hz + 0.6), Vector3(1.0, 1.3, 1.0))
	_bin(-2.2, hz + 0.7)
	_bin(-2.9, hz + 0.7, "#5b4a3a")
	# Varanda lateral (direita) com a rota até a laje.
	_add(Vector3(hx + 0.8, FLOOR_H - 0.1, 0), Vector3(1.6, 0.2, 4.0), "#a9aaa1", "concrete")
	_add(Vector3(hx + 1.55, FLOOR_H + 0.5, -0.8), Vector3(0.08, 1.0, 2.4), "#3b4949", "metal")
	_add(Vector3(hx + 0.8, FLOOR_H + 0.5, -1.96), Vector3(1.6, 1.0, 0.08), "#3b4949", "metal")
	_crate(Vector3(hx + 0.6, FLOOR_H + 0.7, -0.6), Vector3(0.9, 1.4, 0.9))
	_crate(Vector3(hx + 0.6, FLOOR_H + 1.4, -1.5), Vector3(0.9, 2.8, 0.9))
	# Depósito encostado na varanda e caçamba na frente dele.
	_add(Vector3(hx + 0.9, 1.0, 3.0), Vector3(1.6, 2.0, 1.6), "#9ca9ab", "plaster")
	_add(Vector3(hx + 0.9, 2.04, 3.0), Vector3(1.75, 0.08, 1.75), "#535b5b", "roof")
	_dumpster(hx + 0.9, hz + 0.95, false)
	# Quintal dos fundos: cerca com caixote para pular, paletes, lixo no beco.
	_fence(false, 6.5, -hz, -12.0)
	_crate(Vector3(5.7, 0.45, -9.5), Vector3(0.9, 0.9, 0.9))
	_pallets(3.0, -9.0, 4)
	_dumpster(-2.0, -14.0, true, "#4a5f73" if i % 2 == 0 else "#3f6b4a")
	_bin(0.6, -14.2)
	_bin(1.3, -14.2, "#5b4a3a")
	_frontage(0.0)
	_end()

# ------------------------------------------------------------------ térrea ---

func _one_story(lot: Dictionary) -> void:
	var i: int = lot["index"]
	var color: String = HOUSE_COLORS[(i + 3) % HOUSE_COLORS.size()]
	_begin(lot["center"], lot["yaw"], "Casa_%02d" % i)
	_body.add_to_group("parkour_house")
	var w := 9.0
	var d := 8.0
	var hx := w * 0.5
	var hz := d * 0.5
	var fz := hz - WALL * 0.5
	var sx := hx - WALL * 0.5
	var inner_z := hz - WALL
	var h := 3.4
	_wall(true, fz, -hx, hx, 0.0, h, [[-1.2, 1.6, 0.0, 2.3], [1.4, 1.2, 0.9, 2.3], [-3.4, 1.0, 0.9, 2.3]], color, 1.0)
	_wall(true, -fz, -hx, hx, 0.0, h, [[-2.0, 1.4, 0.9, 2.3], [2.0, 1.2, 0.0, 2.3]], color, -1.0)
	_wall(false, -sx, -inner_z, inner_z, 0.0, h, [[0.0, 1.4, 0.9, 2.3]], color, -1.0)
	_wall(false, sx, -inner_z, inner_z, 0.0, h, [[0.0, 1.4, 0.9, 2.3]], color, 1.0)
	_add(Vector3(0, h + 0.1, 0), Vector3(w + 0.3, 0.2, d + 0.3), "#535b5b", "roof")
	_add(Vector3(0, 0.035, 0), Vector3(w - 0.5, 0.02, d - 0.5), "#a49e8c", "concrete", false)
	_ac_unit(Vector3(1.5, h + 0.6, -1.5))
	# Escada externa até a laje pelo lado esquerdo.
	_stairs(Vector3(-hx - 0.55, 0, 3.0), Vector3(0, 0, -1), 6.6, h + 0.2, 1.0)
	# Caçamba > caixote alto > laje.
	_crate(Vector3(3.0, 1.2, hz + 0.65), Vector3(1.0, 2.4, 1.0))
	_dumpster(3.0, hz + 1.75, true)
	_bin(-3.6, hz + 0.7)
	# Fundos: muro baixo para vaultar e paletes.
	_add(Vector3(0, 0.5, -9.0), Vector3(6.0, 1.0, 0.3), "#a9aaa1", "concrete")
	_pallets(-3.0, -12.0, 3)
	_bin(2.5, -14.2)
	_frontage(-1.2)
	_end()

# ------------------------------------------------------- pista de parkour ---

func _course(lot: Dictionary) -> void:
	var i: int = lot["index"]
	_begin(lot["center"], lot["yaw"], "Pista_%02d" % i)
	_body.add_to_group("parkour_course")
	_add(Vector3(0, 0.03, 0), Vector3(12, 0.02, 12), "#b4ae9c", "concrete")
	# Escada de blocos (0,8 m por degrau) até o andaime.
	var steps := [0.8, 1.6, 2.4, 3.2]
	for s in steps.size():
		var top: float = steps[s]
		_add(Vector3(-4.5, top * 0.5, 4.0 - s * 1.5), Vector3(1.4, top, 1.4), "#a9aaa1" if s % 2 == 0 else "#bcb8a5", "concrete")
	# Andaimes: 3,2 m (vão de 1 m depois do último bloco) e 4,4 m ligados por uma viga.
	_scaffold(Vector3(-4.5, 3.2, -3.6))
	_scaffold(Vector3(-1.0, 4.4, -3.6))
	_add(Vector3(1.75, 4.32, -3.6), Vector3(3.5, 0.15, 0.25), "#58646a", "metal")
	_scaffold(Vector3(4.5, 4.4, -3.6))
	# Descida: caixotes escalonados.
	_crate(Vector3(4.5, 1.4, -1.0), Vector3(1.2, 2.8, 1.2))
	_crate(Vector3(4.5, 0.7, 0.4), Vector3(1.2, 1.4, 1.2))
	# Obstáculos de vault: muretas de 0,9 e 1,2 m e corrimão.
	_add(Vector3(0.8, 0.45, 4.5), Vector3(3.0, 0.9, 0.3), "#a9aaa1", "concrete")
	_add(Vector3(0.8, 1.0, 2.6), Vector3(3.0, 0.08, 0.08), "#3b4949", "metal")
	for side in [-1.0, 1.0]:
		_add(Vector3(0.8 + side * 1.4, 0.5, 2.6), Vector3(0.08, 1.0, 0.08), "#3b4949", "metal")
	_add(Vector3(0.8, 0.6, 0.7), Vector3(3.0, 1.2, 0.3), "#bcb8a5", "concrete")
	# Parede alta (2,6 m) com caixote de impulso.
	_add(Vector3(-1.6, 1.3, 0.2), Vector3(0.3, 2.6, 2.6), "#a9aaa1", "concrete")
	_crate(Vector3(-2.4, 0.6, 0.2), Vector3(0.8, 1.2, 0.8))
	_bin(5.5, 5.4)
	_dumpster(-1.0, 5.4, true)
	_sign("PARKOUR", Vector3(0, 2.4, 5.95), 0.0)
	_frontage(NAN)
	_end()

## Plataforma 2 × 2 m com quatro pés; `top` é a altura da superfície.
func _scaffold(top: Vector3) -> void:
	_add(Vector3(top.x, top.y - 0.08, top.z), Vector3(2.0, 0.16, 2.0), "#7c6c54", "wood")
	for sx in [-0.9, 0.9]:
		for sz in [-0.9, 0.9]:
			_add(Vector3(top.x + sx, (top.y - 0.16) * 0.5, top.z + sz), Vector3(0.1, top.y - 0.16, 0.1), "#58646a", "metal")

# ------------------------------------------------------------ ruas/árvores ---

func _streets() -> void:
	_begin(Vector2.ZERO, 0.0, "RuasBairro")
	for road in roads():
		var a: Vector2 = road[0]
		var b: Vector2 = road[1]
		var width: float = road[2]
		var mid := (a + b) * 0.5
		var size := Vector2(absf(b.x - a.x) + (0.0 if absf(b.x - a.x) > 0.1 else width), absf(b.y - a.y) + (0.0 if absf(b.y - a.y) > 0.1 else width))
		_add(Vector3(mid.x, 0.015, mid.y), Vector3(size.x, 0.02, size.y), "#414950", "asphalt")
	# Faixa central tracejada no anel.
	for along in range(-60, 61, 6):
		for side in [-RING, RING]:
			_add(Vector3(along, 0.028, side), Vector3(2.2, 0.01, 0.12), "#dbcb96", "paint", false)
			_add(Vector3(side, 0.028, along), Vector3(0.12, 0.01, 2.2), "#dbcb96", "paint", false)
	_end()

func _border_trees() -> void:
	# Árvores entre os fundos dos lotes e o muro (não bloqueiam o beco).
	_begin(Vector2.ZERO, 0.0, "ArvoresBairro")
	for along in range(-84, 85, 21):
		for p in [Vector3(along + 6.5, 0, -97.5), Vector3(along + 6.5, 0, 97.5), Vector3(-97.5, 0, along * 0.6), Vector3(97.5, 0, along * 0.6)]:
			_add_cyl(p + Vector3(0, 1.7, 0), 0.18, 3.4, "#68503c", "bark")
			var crown := SphereMesh.new()
			crown.radius = 1.4
			crown.height = 2.6
			crown.radial_segments = 10
			crown.rings = 5
			_tool("#487347", "leaf").append_from(crown, 0, Transform3D(Basis.IDENTITY, p + Vector3(0, 3.9, 0)))
	_end()
