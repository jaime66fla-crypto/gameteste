extends Control
## Minimapa redondo (canto superior esquerdo). Gira com o jogador: a frente é
## sempre para cima. Mostra ruas, estradas, prédios, grama alta, árvores e
## aliados (partidas em equipe). Inimigos e zumbis não aparecem.
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const RADIUS := 92.0

var player: Node3D
var meters_per_px := 0.55
var allies: Callable # devolve Array[Node3D] (equipes)
var _roads: Array = [] # [from Vector2, to Vector2, width]
var _buildings: Array = [] # [center Vector2, size Vector2]
var _grass: Array = [] # [center Vector2, r]
var _ponds: Array = [] # [center Vector2, r]
var _mountains: Array = []
var _trees: PackedVector2Array = PackedVector2Array()
var _is_island := false
var _half := 60.0
var _canvas: Control
var _last_view := Vector3.INF
var _warmup := 10

func setup(local_player: Node3D, survival: bool) -> void:
	player = local_player
	if not survival:
		# Mapa da partida (match_map.gd): o contorno dos blocos de cada mapa.
		var layout := MatchLayout.load_layout()
		_half = float(layout.get("map_half_size", 40))
		meters_per_px = 0.42
		for f in layout.get("footprints", []):
			_buildings.append([Vector2(float(f[0]), float(f[1])), Vector2(float(f[2]), float(f[3]))])
		return
	# Sobrevivência: o mundo aberto (floresta, lagos; cidade do meio só nos mapas antigos).
	if survival:
		_is_island = true
		meters_per_px = 0.95
		var data := SurvivalData.world()
		_half = float(data.get("half_size", 240)) + 90.0
		for m in data.get("mountains", []):
			_mountains.append([Vector2(float(m.x), float(m.z)), float(m.r)])
		if data.has("center_town"):
			for lane in [-48.0, 0.0, 48.0]:
				_roads.append([Vector2(lane, -52), Vector2(lane, 52), 8.0])
				_roads.append([Vector2(-52, lane), Vector2(52, lane), 8.0])
			for b in MatchLayout.city_layout().get("buildings", []):
				_buildings.append([Vector2(float(b["center"][0]), float(b["center"][1])), Vector2(float(b["size"][0]), float(b["size"][1]))])
		for pond in data.get("ponds", []):
			_ponds.append([Vector2(float(pond["x"]), float(pond["z"])), float(pond["r"])])
		for road in data.get("roads", []):
			_roads.append([Vector2(float(road["from"][0]), float(road["from"][1])), Vector2(float(road["to"][0]), float(road["to"][1])), float(road.get("width", 6))])
		for b in data.get("buildings", []):
			_buildings.append([Vector2(float(b["center"][0]), float(b["center"][1])), Vector2(float(b["size"][0]), float(b["size"][1]))])
		for lot in data.get("parkour", []):
			if str(lot["kind"]) != "pista":
				_buildings.append([Vector2(float(lot["center"][0]), float(lot["center"][1])), Vector2(10, 8)])
		for g in data.get("grass", []):
			_grass.append([Vector2(float(g["x"]), float(g["z"])), float(g["r"])])
		for r in data.get("resources", []):
			if str(r["kind"]) == "tree":
				_trees.append(Vector2(float(r["p"][0]), float(r["p"][2])))

## Treino offline (training_ground.gd): sem ruas nem prédios da cidade, só os
## blocos sólidos do campo de prova. Chamar depois de setup, antes de entrar na árvore.
func use_training_map(blocks: Array, half: float) -> void:
	_roads.clear()
	_buildings = blocks.duplicate()
	_half = half
	_map_color = Color(0.36, 0.37, 0.4, 1.0) # chão de grade cinza, não grama

var _map_color := Color(0.33, 0.45, 0.27, 1.0)

func _ready() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2(18, 18)
	size = Vector2(RADIUS * 2, RADIUS * 2)
	# Fundo redondo que recorta o desenho do mapa (clip_children).
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.20, 0.27, 0.17, 0.86)
	style.set_corner_radius_all(int(RADIUS))
	style.anti_aliasing = true
	disc.add_theme_stylebox_override("panel", style)
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(disc)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.size = size
	_canvas.draw.connect(_draw_map)
	disc.add_child(_canvas)
	_bake()
	_build_coords()

# ----------------------------------------------------------- coordenadas ---
# Ao lado do minimapa: posição em metros a partir do canto noroeste do mapa
# (X cresce para o leste, Y para o sul) e para onde o jogador está olhando.
const COMPASS := ["N", "NE", "L", "SE", "S", "SO", "O", "NO"]
var _coords_label: Label
var _heading_label: Label
var _last_coords := Vector3i(-99999, -99999, -1)

func _build_coords() -> void:
	var panel := PanelContainer.new()
	panel.name = "Coords"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.06, 0.62)
	style.set_corner_radius_all(6)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 4
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.position = Vector2(RADIUS * 2.0 + 10.0, 4.0) # à direita, na altura do topo do minimapa
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", -2)
	panel.add_child(stack)
	_coords_label = Label.new()
	_coords_label.name = "CoordsText"
	_coords_label.add_theme_font_size_override("font_size", 15)
	_coords_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_coords_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_coords_label.add_theme_constant_override("outline_size", 3)
	stack.add_child(_coords_label)
	_heading_label = Label.new()
	_heading_label.name = "HeadingText"
	_heading_label.add_theme_font_size_override("font_size", 12)
	_heading_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	stack.add_child(_heading_label)

## Texto das coordenadas para uma posição do mundo (também usado nos testes).
func coords_of(world: Vector3) -> Vector2i:
	var origin := float(SurvivalData.world().get("half_size", 420)) if _is_island else _half
	return Vector2i(int(round(world.x + origin)), int(round(world.z + origin)))

## Direção em graus (0 = norte, 90 = leste) e o nome curto.
static func heading_of(yaw: float) -> Array:
	var deg := int(round(fposmod(rad_to_deg(-yaw), 360.0))) % 360
	return [deg, COMPASS[int(round(deg / 45.0)) % 8]]

func _update_coords() -> void:
	if _coords_label == null or player == null or not is_instance_valid(player):
		return
	var c := coords_of(player.global_position)
	var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
	var h: Array = heading_of(yaw)
	var key := Vector3i(c.x, c.y, int(h[0]))
	if key == _last_coords:
		return # só reescreve quando muda
	_last_coords = key
	_coords_label.text = "X %d  ·  Y %d" % [c.x, c.y]
	_heading_label.text = "%s  %03d°" % [h[1], h[0]]

# O mapa (grama, árvores, ruas, prédios) não muda: é desenhado uma vez numa
# textura e, a cada quadro, só essa textura é girada em volta do jogador.
const Hydro = preload("res://scripts/survival/hydrology.gd")
const BAKE_PX_PER_M := 2.0
var _map_texture: Texture2D

func _bake() -> void:
	var viewport := SubViewport.new()
	var px := int(ceil(_half * 2.0 * BAKE_PX_PER_M))
	viewport.size = Vector2i(px, px)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var painter := Control.new()
	painter.size = Vector2(px, px)
	painter.draw.connect(_paint_map.bind(painter))
	viewport.add_child(painter)
	_map_texture = viewport.get_texture()

func _paint_map(ci: Control) -> void:
	ci.draw_set_transform(Vector2(_half, _half) * BAKE_PX_PER_M, 0.0, Vector2.ONE * BAKE_PX_PER_M)
	ci.draw_rect(Rect2(Vector2(-_half, -_half), Vector2(_half, _half) * 2.0), _map_color)
	if _is_island:
		ci.draw_rect(Rect2(Vector2(-_half,-_half),Vector2.ONE*_half*2),Color("#275c72"))
		var coast := PackedVector2Array()
		var land := PackedVector2Array()
		var h := float(SurvivalData.world().get("half_size",420))
		for i in 128:
			var a := TAU * float(i) / 128.0
			var d := Vector2(cos(a),sin(a))
			var r := h+20.0+sin(a*3)*7+sin(a*7)*4
			coast.append(d*r)
			land.append(d*(r-15.0))
		ci.draw_colored_polygon(coast,Color("#b3a177"))
		ci.draw_colored_polygon(land,Color("#547342"))
	for m in _mountains:
		ci.draw_circle(m[0], m[1], Color("647354"))
		ci.draw_circle(m[0], m[1] * 0.65, Color("777b68"))
		ci.draw_circle(m[0], m[1] * 0.3, Color("969388"))
	for g in _grass:
		ci.draw_circle(g[0], g[1], Color(0.56, 0.58, 0.30, 0.9))
	for t in _trees:
		ci.draw_circle(t, 1.6, Color(0.14, 0.28, 0.14, 1.0))
	for p in _ponds:
		ci.draw_circle(p[0], p[1] + 1.4, Color(0.31, 0.26, 0.2, 1.0))
		ci.draw_circle(p[0], p[1], Color(0.18, 0.34, 0.4, 1.0))
	if _is_island:
		var points := PackedVector2Array()
		for point in SurvivalData.world().hydrology.river.points:
			points.append(Vector2(float(point[0]),float(point[1])))
		ci.draw_polyline(points,Color("#38778b"),18.0,true)
	for road in _roads:
		ci.draw_line(road[0], road[1], Color(0.30, 0.31, 0.31, 1.0), road[2])
	for b in _buildings:
		var s: Vector2 = b[1]
		ci.draw_rect(Rect2(b[0] - s * 0.5, s), Color(0.78, 0.72, 0.60, 1.0))
		ci.draw_rect(Rect2(b[0] - s * 0.5, s), Color(0.25, 0.22, 0.18, 1.0), false, 0.6)

func _process(_delta: float) -> void:
	# Só redesenha quando o jogador anda ou gira (ou há aliados se mexendo).
	if player != null and is_instance_valid(player):
		var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
		var key := Vector3(player.global_position.x, player.global_position.z, yaw)
		if key.is_equal_approx(_last_view) and not allies.is_valid() and _warmup <= 0:
			return
		_warmup -= 1 # primeiros quadros: a textura do mapa ainda está sendo assada
		if not is_equal_approx(yaw, _last_view.z):
			queue_redraw() # aro e "N" giram com a câmera
		_last_view = key
	if _canvas != null:
		_canvas.queue_redraw()
	_update_coords()

## Mapa no espaço do mundo, girado e escalado em volta do jogador.
func _draw_map() -> void:
	if player == null or not is_instance_valid(player):
		return
	var c := size * 0.5
	var me := Vector2(player.global_position.x, player.global_position.z)
	var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
	_canvas.draw_set_transform(c, yaw, Vector2.ONE / meters_per_px)
	if _map_texture != null:
		_canvas.draw_texture_rect(_map_texture, Rect2(Vector2(-_half, -_half) - me, Vector2(_half, _half) * 2.0), false)
	if allies.is_valid():
		for node in allies.call():
			if is_instance_valid(node):
				var p := Vector2(node.global_position.x, node.global_position.z) - me
				_canvas.draw_circle(p, 3.2, Color("#5fb4ff"))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Por cima do recorte: aro, seta do jogador e o "N".
func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, RADIUS - 1.0, 0.0, TAU, 64, Color(0, 0, 0, 0.75), 3.0, true)
	draw_arc(c, RADIUS - 3.0, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 1.0, true)
	var arrow := PackedVector2Array([c + Vector2(0, -9), c + Vector2(6.5, 7), c + Vector2(0, 3.5), c + Vector2(-6.5, 7)])
	draw_colored_polygon(arrow, Color(1, 0.95, 0.75))
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.8), 1.2, true)
	if player != null and is_instance_valid(player):
		var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
		var north := c + Vector2(sin(yaw), -cos(yaw)) * (RADIUS - 11.0)
		draw_circle(north, 8.0, Color(0, 0, 0, 0.7))
		var font := ThemeDB.fallback_font
		draw_string(font, north + Vector2(-4.5, 5.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.4))
