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
var _trees: PackedVector2Array = PackedVector2Array()
var _half := 60.0
var _canvas: Control

func setup(local_player: Node3D, survival: bool) -> void:
	player = local_player
	# Cidade do meio (mapa do mata-mata): avenidas e prédios do layout.
	for lane in [-48.0, 0.0, 48.0]:
		_roads.append([Vector2(lane, -52), Vector2(lane, 52), 8.0])
		_roads.append([Vector2(-52, lane), Vector2(52, lane), 8.0])
	for b in MatchLayout.load_layout().get("buildings", []):
		_buildings.append([Vector2(float(b["center"][0]), float(b["center"][1])), Vector2(float(b["size"][0]), float(b["size"][1]))])
	if survival:
		meters_per_px = 0.95
		var data := SurvivalData.world()
		_half = float(data.get("half_size", 240))
		for road in data.get("roads", []):
			_roads.append([Vector2(float(road["from"][0]), float(road["from"][1])), Vector2(float(road["to"][0]), float(road["to"][1])), float(road.get("width", 6))])
		for b in data.get("buildings", []):
			_buildings.append([Vector2(float(b["center"][0]), float(b["center"][1])), Vector2(float(b["size"][0]), float(b["size"][1]))])
		for g in data.get("grass", []):
			_grass.append([Vector2(float(g["x"]), float(g["z"])), float(g["r"])])
		for r in data.get("resources", []):
			if str(r["kind"]) == "tree":
				_trees.append(Vector2(float(r["p"][0]), float(r["p"][2])))

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

func _process(_delta: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()
	queue_redraw()

## Mapa no espaço do mundo, girado e escalado em volta do jogador.
func _draw_map() -> void:
	if player == null or not is_instance_valid(player):
		return
	var c := size * 0.5
	var me := Vector2(player.global_position.x, player.global_position.z)
	var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
	var view := RADIUS * meters_per_px + 10.0
	_canvas.draw_set_transform(c, yaw, Vector2.ONE / meters_per_px)
	# Fora do mundo: mais escuro.
	_canvas.draw_rect(Rect2(Vector2(-_half, -_half) - me, Vector2(_half, _half) * 2.0), Color(0.33, 0.45, 0.27, 1.0))
	for g in _grass:
		if (g[0] as Vector2).distance_to(me) < view + float(g[1]):
			_canvas.draw_circle(g[0] - me, g[1], Color(0.56, 0.58, 0.30, 0.9))
	for t in _trees:
		if absf(t.x - me.x) < view and absf(t.y - me.y) < view:
			_canvas.draw_circle(t - me, 1.6, Color(0.14, 0.28, 0.14, 1.0))
	for road in _roads:
		_canvas.draw_line(road[0] - me, road[1] - me, Color(0.30, 0.31, 0.31, 1.0), road[2])
	for b in _buildings:
		var center: Vector2 = b[0]
		if center.distance_to(me) > view + 20.0:
			continue
		var s: Vector2 = b[1]
		_canvas.draw_rect(Rect2(center - me - s * 0.5, s), Color(0.78, 0.72, 0.60, 1.0))
		_canvas.draw_rect(Rect2(center - me - s * 0.5, s), Color(0.25, 0.22, 0.18, 1.0), false, 0.6)
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
