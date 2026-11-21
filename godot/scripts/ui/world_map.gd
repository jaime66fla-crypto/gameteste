extends Control
## Mapa grande da Sobrevivência (tecla M). Norte para cima, o mundo inteiro na
## tela: ruas, prédios, grama alta, árvores, carros (quebrados em cinza) e você.
## Não pausa o jogo nem prende o mouse — é só olhar e fechar (M ou ESC).
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const BAKE_PX_PER_M := 2.0

var player: Node3D
var controller: Node # SurvivalController (carros)
var _half := 240.0
var _roads: Array = []
var _buildings: Array = []
var _grass: Array = []
var _ponds: Array = [] # [center Vector2, r]
var _mountains: Array = []
var _trees: PackedVector2Array = PackedVector2Array()
var _texture: Texture2D

func setup(local_player: Node3D, survival_controller: Node) -> void:
	player = local_player
	controller = survival_controller

func _ready() -> void:
	name = "WorldMap"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var data := SurvivalData.world()
	_half = float(data.get("half_size", 240))
	for m in data.get("mountains", []):
		_mountains.append([Vector2(float(m.x), float(m.z)), float(m.r)])
	if data.has("center_town"): # mapas antigos: a cidade do meio
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
	for lot in data.get("parkour", []): # bairros de parkour do anel novo
		if str(lot["kind"]) != "pista":
			_buildings.append([Vector2(float(lot["center"][0]), float(lot["center"][1])), Vector2(10, 8)])
	for g in data.get("grass", []):
		_grass.append([Vector2(float(g["x"]), float(g["z"])), float(g["r"])])
	for r in data.get("resources", []):
		if str(r["kind"]) == "tree":
			_trees.append(Vector2(float(r["p"][0]), float(r["p"][2])))
	_bake()

## O desenho do mundo não muda: vira uma textura uma vez só.
func _bake() -> void:
	var viewport := SubViewport.new()
	var px := int(ceil(_half * 2.0 * BAKE_PX_PER_M))
	viewport.size = Vector2i(px, px)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var painter := Control.new()
	painter.size = Vector2(px, px)
	painter.draw.connect(func():
		painter.draw_set_transform(Vector2(_half, _half) * BAKE_PX_PER_M, 0.0, Vector2.ONE * BAKE_PX_PER_M)
		painter.draw_rect(Rect2(Vector2(-_half, -_half), Vector2(_half, _half) * 2.0), Color(0.33, 0.45, 0.27))
		for m in _mountains:
			painter.draw_circle(m[0], m[1], Color("647354"))
			painter.draw_circle(m[0], m[1] * 0.65, Color("777b68"))
			painter.draw_circle(m[0], m[1] * 0.3, Color("969388"))
		for g in _grass:
			painter.draw_circle(g[0], g[1], Color(0.56, 0.58, 0.30, 0.9))
		for t in _trees:
			painter.draw_circle(t, 1.6, Color(0.14, 0.28, 0.14))
		for p in _ponds:
			painter.draw_circle(p[0], p[1] + 1.4, Color(0.31, 0.26, 0.2))
			painter.draw_circle(p[0], p[1], Color(0.18, 0.34, 0.4))
		for road in _roads:
			painter.draw_line(road[0], road[1], Color(0.30, 0.31, 0.31), road[2])
		for b in _buildings:
			var s: Vector2 = b[1]
			painter.draw_rect(Rect2(b[0] - s * 0.5, s), Color(0.78, 0.72, 0.60))
			painter.draw_rect(Rect2(b[0] - s * 0.5, s), Color(0.25, 0.22, 0.18), false, 0.6))
	viewport.add_child(painter)
	_texture = viewport.get_texture()

func toggle() -> void:
	visible = not visible
	queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

## Mundo (x, z) -> ponto na tela.
func _to_screen(world: Vector2, origin: Vector2, scale_px: float) -> Vector2:
	return origin + (world + Vector2(_half, _half)) * scale_px

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))
	var side := minf(size.x, size.y) - 110.0
	if side <= 50.0 or _texture == null:
		return
	var scale_px := side / (_half * 2.0)
	var origin := (size - Vector2(side, side)) * 0.5 + Vector2(0, 14)
	draw_texture_rect(_texture, Rect2(origin, Vector2(side, side)), false)
	draw_rect(Rect2(origin, Vector2(side, side)), Color(1, 1, 1, 0.35), false, 2.0)
	var font := ThemeDB.fallback_font
	# Carros: brancos funcionando, cinza escuro quebrados.
	if controller != null and controller.get("driving_ctl") != null:
		var cars: Dictionary = controller.get("driving_ctl").get("vehicles")
		for id in cars:
			var v: Node3D = cars[id]
			if not is_instance_valid(v):
				continue
			var at := _to_screen(Vector2(v.global_position.x, v.global_position.z), origin, scale_px)
			var broken := bool(v.get("broken"))
			draw_rect(Rect2(at - Vector2(4, 3), Vector2(8, 6)), Color("#3a3a3a") if broken else Color("#f2f2f2"))
			draw_rect(Rect2(at - Vector2(4, 3), Vector2(8, 6)), Color(0, 0, 0, 0.8), false, 1.0)
	# Você: seta na direção para onde olha.
	if player != null and is_instance_valid(player):
		var me := _to_screen(Vector2(player.global_position.x, player.global_position.z), origin, scale_px)
		var yaw := float(player.get("yaw")) if player.get("yaw") != null else player.rotation.y
		var f := Vector2(-sin(yaw), -cos(yaw))
		var r := Vector2(-f.y, f.x)
		var arrow := PackedVector2Array([me + f * 11.0, me - f * 7.0 + r * 7.0, me - f * 3.0, me - f * 7.0 - r * 7.0])
		draw_circle(me, 14.0, Color(1, 0.85, 0.3, 0.25))
		draw_colored_polygon(arrow, Color(1, 0.9, 0.35))
		draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0, 0, 0, 0.9), 1.5, true)
	# Título, norte e legenda.
	var title := "MAPA"
	draw_string(font, Vector2(origin.x, origin.y - 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.88, 0.5))
	draw_string(font, Vector2(origin.x + side * 0.5 - 5, origin.y + 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.4))
	var legend := "Você (seta amarela)   •   Lagos (azul): água para beber   •   M ou ESC fecha"
	var w := font.get_string_size(legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, origin.y + side + 26), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))
