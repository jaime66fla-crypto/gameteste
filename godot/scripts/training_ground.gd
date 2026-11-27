extends Node3D
## Treino offline: campo de prova (100 × 100 m) no gráfico do Linha de Fogo (lajotas de
## 1 m no chão, então dá para medir pulo, rampa e distância só olhando o chão; os nomes
## das peças ainda são os da grade Kenney, ver LF_FROM_KENNEY). Zonas (−Z é a frente de quem nasce):
##   - estande de tiro na frente do nascimento: bonecos a 6 e 20 m (main.gd),
##     marcas a cada 5 m e placas de aço a 34 m;
##   - tiro longo na faixa oeste: torre de 6 m com rampa e placas a ~80 m;
##   - percurso de agilidade: escadinha de blocos, vãos de 1,5 / 2,5 m, rampas
##     de 15°, 30° e 40°, escada até um deck de 3 m, muretas e túnel rasteiro;
##   - área de cobertura a leste: casa de tiro com portas e janelas, muretas
##     (1,2 m, cobre agachado), muros altos (2,2 m) e caixotes;
##   - arena do zumbi no canto sudeste (training_arena.gd);
##   - praça livre ao sul do nascimento.
## As malhas são juntadas por material (poucas draw calls); toda a colisão fica
## num único StaticBody3D. Muro de 4 m e barreira invisível de 30 m na borda.
const LfGraphics = preload("res://scripts/lf_graphics.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const MapMaterials = preload("res://scripts/map_materials.gd")
const TEX := "res://assets/textures/kenney_prototype/%s.png"
const HALF := 50.0
const TILE_M := 2.0 # metros cobertos por uma textura
const SPAWN := Vector3(12, 0.1, -10)
## Bonecos de treino (main._spawn_training_dummies): dois perto, um a 20 m.
const DUMMIES := [[Vector3(8, 0, -16), "BONECO 1"], [Vector3(16, 0, -16), "BONECO 2"], [Vector3(12, 0, -30), "BONECO DISTANTE (20 m)"]]
## Estande de tiro: entre as paredes de x = 3 e x = 21, da linha de tiro ao fundo.
const RANGE_X := Vector2(3.0, 21.0)
const FIRING_LINE := -12.0
## Tiro longo: torre na faixa oeste, placas no fundo norte.
const TOWER := Vector2(-45.0, 36.0)
const TOWER_TOP := 6.0
const TOWER_SIZE := 5.0
const TOWER_RAMP := 12.0

static var _materials: Dictionary = {}

var sound_fx: Node # o do jogador (placas de aço)
var _body: StaticBody3D
var _steps: StaticBody3D
var _tools: Dictionary = {}
## Para o minimapa: [centro Vector2, tamanho Vector2] de tudo que é sólido e alto.
var blocks: Array = []

## Material Kenney em escala de mundo. world = false: a textura acompanha o
## objeto (peças que se mexem, como as placas de aço).
## Peças do treino no gráfico do Linha de Fogo (scripts/map_materials.gd lf()): o chão
## escuro vira lajota de 1 m (continua dando para medir pulo e distância), as paredes
## claras viram blocos de pedra, as marcas viram concreto e as cores (alvos, suportes)
## viram concreto pintado na mesma cor.
const LF_FROM_KENNEY := {
	"dark_grid": ["floor", Color.WHITE], "dark_marks": ["floor", Color.WHITE],
	"light_grid": ["stone", Color.WHITE], "light_marks": ["concrete", Color.WHITE],
	"orange_grid": ["concrete", Color("#d9822b")], "red_grid": ["concrete", Color("#c8463c")],
	"green_grid": ["concrete", Color("#5f9a4a")], "purple_grid": ["concrete", Color("#8a5fb0")],
}

static func material(texture: String, world: bool = true) -> StandardMaterial3D:
	var spec: Array = LF_FROM_KENNEY.get(texture, ["concrete", Color.WHITE])
	return MapMaterials.lf(spec[0], spec[1], world)

func _ready() -> void:
	name = "TrainingGround"
	_tune_environment()
	_body = StaticBody3D.new()
	_body.name = "Geometry"
	add_child(_body)
	_steps = StaticBody3D.new()
	_steps.name = "StairSteps"
	_steps.collision_layer = HitboxScript.LAYER_FOOT_PROBE
	_steps.collision_mask = 0
	_body.add_child(_steps)
	_floor()
	_perimeter()
	_shooting_range()
	_long_range()
	_agility_course()
	_cover_area()
	_signs()
	for key in _tools:
		var instance := MeshInstance3D.new()
		instance.name = "Mesh_" + key
		instance.mesh = (_tools[key] as SurfaceTool).commit()
		instance.material_override = material(key)
		_body.add_child(instance)
	_tools.clear()

# ------------------------------------------------------------- utilitários ---

func _tool(texture: String) -> SurfaceTool:
	if not _tools.has(texture):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[texture] = st
	return _tools[texture]

## Caixa com a textura dada; `solid` cria a colisão (camada do mundo).
func _box(center: Vector3, size: Vector3, texture: String, solid: bool = true, basis: Basis = Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_tool(texture).append_from(mesh, 0, Transform3D(basis, center))
	if solid:
		_shape(size, Transform3D(basis, center))
		if basis == Basis.IDENTITY and size.y >= 0.9 and center.y - size.y * 0.5 < 1.0:
			blocks.append([Vector2(center.x, center.z), Vector2(size.x, size.z)])

func _shape(size: Vector3, xform: Transform3D, body: StaticBody3D = null) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.transform = xform
	(_body if body == null else body).add_child(collider)

## Marca pintada no chão (só visual, 1 cm acima do piso).
func _paint(center: Vector2, size: Vector2, texture: String) -> void:
	_box(Vector3(center.x, 0.005, center.y), Vector3(size.x, 0.01, size.y), texture, false)

## Rampa de `from` (pé, no chão) até `to` (topo): a superfície passa pelos dois.
## visible = false: só a colisão (o piso invisível das escadas).
func _ramp(from: Vector3, to: Vector3, width: float, texture: String, visible: bool = true) -> void:
	var dir := (to - from).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir)
	var thickness := 0.3
	var start := from - dir * 0.6 # enterrada no piso
	var length := start.distance_to(to)
	var center := (start + to) * 0.5 - up * thickness * 0.5
	var basis := Basis(right, up, -dir)
	if visible:
		_box(center, Vector3(width, thickness, length), texture, true, basis)
	else:
		_shape(Vector3(width, thickness, length), Transform3D(basis, center))

## Escada: degraus de ~20 cm (visuais e na camada dos pés, para o IK) sobre
## uma rampa invisível que o corpo sobe andando (o CharacterBody não sobe degrau).
func _stairs(base: Vector3, dir: Vector3, run: float, rise: float, width: float, texture: String) -> void:
	var n := maxi(2, roundi(rise / 0.2))
	var tread := run / n
	var step := rise / n
	var turn := Basis(Vector3.UP, atan2(dir.x, dir.z))
	for k in n:
		var top := (k + 1) * step
		var center := base + dir * ((k + 0.5) * tread) + Vector3(0, top * 0.5, 0)
		var size := Vector3(width, top, tread + 0.01)
		_box(center, size, texture, false, turn)
		_shape(size, Transform3D(turn, center), _steps)
	_ramp(base + Vector3(0, step * 0.5, 0), base + dir * run + Vector3(0, rise, 0), width, texture, false)

func _label(text: String, pos: Vector3, size: int = 48, flat: bool = false, yaw: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 10
	label.pixel_size = 0.01
	label.modulate = Color("#fff4d6")
	label.position = pos
	if flat:
		label.rotation = Vector3(-PI * 0.5, yaw, 0)
	else:
		label.rotation.y = yaw
	add_child(label)
	return label

func _target(pos: Vector3, size: Vector2, title: String) -> void:
	var plate: StaticBody3D = load("res://scripts/training_target.gd").new()
	plate.set("size", size)
	plate.set("title", title)
	plate.set("sound_fx", sound_fx)
	plate.position = pos
	add_child(plate)
	# Suporte: duas hastes finas até o chão (só visual, para não segurar bala).
	for side in [-1.0, 1.0]:
		var h := pos.y - size.y * 0.5
		_box(Vector3(pos.x + side * size.x * 0.45, h * 0.5, pos.z + 0.08), Vector3(0.05, h, 0.05), "dark_grid", false)

# ------------------------------------------------------------------- base ---

func _tune_environment() -> void:
	# Gráfico do Linha de Fogo (scripts/lf_graphics.gd).
	var holder := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder == null:
		return
	LfGraphics.apply(holder.environment, get_parent().get_node_or_null("Sun") as DirectionalLight3D)

func _floor() -> void:
	var size := HALF * 2.0
	_box(Vector3(0, -0.5, 0), Vector3(size, 1.0, size), "dark_grid")
	blocks.clear() # o chão não entra no minimapa
	# Área de nascimento.
	_paint(Vector2(SPAWN.x, SPAWN.z + 1.0), Vector2(6, 6), "light_marks")

func _perimeter() -> void:
	var half := HALF - 0.4
	var thickness := 0.8
	for side in [-1.0, 1.0]:
		_box(Vector3(side * half, 2.0, 0), Vector3(thickness, 4.0, half * 2 + thickness), "light_grid")
		_box(Vector3(0, 2.0, side * half), Vector3(half * 2 + thickness, 4.0, thickness), "light_grid")
		# Barreira invisível alta: ninguém pula para fora (a torre tem 7 m).
		_shape(Vector3(thickness, 30.0, half * 2 + thickness), Transform3D(Basis.IDENTITY, Vector3(side * half, 15.0, 0)))
		_shape(Vector3(half * 2 + thickness, 30.0, thickness), Transform3D(Basis.IDENTITY, Vector3(0, 15.0, side * half)))

# ---------------------------------------------------------- estande de tiro ---

func _shooting_range() -> void:
	var back := -46.0
	var length := FIRING_LINE - back
	var mid_z := (FIRING_LINE + back) * 0.5
	var width := RANGE_X.y - RANGE_X.x
	var mid_x := (RANGE_X.x + RANGE_X.y) * 0.5
	# Paredes laterais (2,5 m) e o barranco do fundo (6 m), que segura as balas.
	for x in [RANGE_X.x, RANGE_X.y]:
		_box(Vector3(x, 1.25, mid_z - 0.5), Vector3(0.4, 2.5, length + 1.0), "light_grid")
	_box(Vector3(mid_x, 3.0, back - 1.0), Vector3(width + 0.4, 6.0, 2.0), "orange_grid")
	# Linha de tiro e marcas a cada 5 m a partir do nascimento (z = -10).
	_paint(Vector2(mid_x, FIRING_LINE), Vector2(width - 0.4, 0.18), "orange_grid")
	for meters in range(5, 35, 5):
		var z := SPAWN.z - meters
		_paint(Vector2(mid_x, z), Vector2(width - 0.4, 0.08 if meters % 10 else 0.14), "light_grid")
		if meters % 10 == 0:
			_label("%d m" % meters, Vector3(RANGE_X.x + 1.0, 0.03, z + 0.6), 64, true)
	# Placas de aço a 34 m do nascimento.
	var plate_z := SPAWN.z - 34.0
	for spec in [[6.5, 1.0, "PLACA A"], [12.0, 1.45, "CABEÇA"], [17.5, 1.0, "PLACA B"]]:
		var size := Vector2(0.35, 0.35) if spec[2] == "CABEÇA" else Vector2(0.6, 0.6)
		_target(Vector3(spec[0], spec[1], plate_z), size, spec[2])
	_label("ESTANDE DE TIRO", Vector3(mid_x, 5.2, back + 0.05), 96)

# --------------------------------------------------------------- tiro longo ---

func _long_range() -> void:
	var c := TOWER
	var half := TOWER_SIZE * 0.5
	var top := TOWER_TOP
	# Plataforma (piso exatamente em `top`) sobre quatro pilares.
	_box(Vector3(c.x, top - 0.15, c.y), Vector3(TOWER_SIZE, 0.3, TOWER_SIZE), "purple_grid")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(c.x + sx * (half - 0.3), (top - 0.3) * 0.5, c.y + sz * (half - 0.3)), Vector3(0.4, top - 0.3, 0.4), "dark_grid")
	# Mureta de 1,1 m; aberta a leste, onde a rampa chega.
	var wall_h := 1.1
	var y := top + wall_h * 0.5
	_box(Vector3(c.x, y, c.y - half + 0.1), Vector3(TOWER_SIZE, wall_h, 0.2), "purple_grid")
	_box(Vector3(c.x, y, c.y + half - 0.1), Vector3(TOWER_SIZE, wall_h, 0.2), "purple_grid")
	_box(Vector3(c.x - half + 0.1, y, c.y), Vector3(0.2, wall_h, TOWER_SIZE), "purple_grid")
	var gap := 1.35
	var side_len := half - gap
	for sz in [-1.0, 1.0]:
		_box(Vector3(c.x + half - 0.1, y, c.y + sz * (gap + side_len * 0.5)), Vector3(0.2, wall_h, side_len), "purple_grid")
	# Rampa de 12 m (26,6°) subindo para oeste até a borda da plataforma.
	_ramp(Vector3(c.x + half + TOWER_RAMP, 0, c.y), Vector3(c.x + half, top, c.y), 2.5, "orange_grid")
	_label("TORRE — TIRO LONGO", Vector3(c.x + half + 0.05, top - 1.0, c.y), 56, false, PI * 0.5)
	# Placas no fundo norte (~80 m da torre) com barranco atrás.
	var plate_z := -45.0
	_box(Vector3(-44.0, 3.0, plate_z - 2.0), Vector3(10.0, 6.0, 2.0), "orange_grid")
	for spec in [[-47.0, 1.2, Vector2(1.0, 1.0), "80 m"], [-44.0, 1.6, Vector2(0.5, 0.5), "80 m PEQUENA"], [-41.0, 1.2, Vector2(1.0, 1.0), "80 m"]]:
		_target(Vector3(spec[0], spec[1], plate_z), spec[2], spec[3])
	# Faixa de tiro livre marcada no chão (nada atravessa entre a torre e as placas).
	_paint(Vector2(-44.0, (plate_z + c.y - half) * 0.5), Vector2(0.12, c.y - half - plate_z), "orange_grid")

# ------------------------------------------------------ percurso de agilidade ---

func _agility_course() -> void:
	# 1) Escadinha de blocos: cada um 0,5 m mais alto (o pulo sobe ~1,6 m).
	var z := -38.0
	for i in 6:
		var h := 0.5 * (i + 1)
		_box(Vector3(-35.0 + i * 2.0, h * 0.5, z), Vector3(2.0, h, 3.0), "purple_grid" if i % 2 == 0 else "orange_grid")
	_label("BLOCOS +0,5 m", Vector3(-30.0, 0.03, z + 2.6), 48, true)
	# 2) Plataformas a 3 m com vãos de 1,5 m e 2,5 m.
	var deck := 3.0
	_box(Vector3(-22.0, deck * 0.5, z), Vector3(4.0, deck, 3.0), "orange_grid") # x -24..-20
	_box(Vector3(-17.0, deck * 0.5, z), Vector3(3.0, deck, 3.0), "purple_grid") # vão 1,5 m
	_box(Vector3(-11.0, deck * 0.5, z), Vector3(4.0, deck, 3.0), "orange_grid") # vão 2,5 m
	_label("VÃO 1,5 m", Vector3(-19.25, deck + 0.8, z + 1.6), 40)
	_label("VÃO 2,5 m", Vector3(-14.25, deck + 0.8, z + 1.6), 40)
	# Descida pela rampa ao sul da última plataforma.
	_ramp(Vector3(-11.0, 0, z + 1.5 + 9.0), Vector3(-11.0, deck, z + 1.5), 3.0, "light_grid")
	# 3) Muretas para pular por cima: 0,6 / 1,0 / 1,4 m.
	for spec in [[-34.0, 0.6], [-29.0, 1.0], [-24.0, 1.4]]:
		_box(Vector3(spec[0], spec[1] * 0.5, -28.0), Vector3(3.0, spec[1], 0.4), "green_grid")
		_label("%.1f m" % spec[1], Vector3(spec[0], spec[1] + 0.5, -27.7), 36)
	# 4) Túnel rasteiro (1 m de vão): só passa deitado.
	var tunnel_z := -22.0
	var tunnel_len := 6.0
	for side in [-1.0, 1.0]:
		_box(Vector3(-19.0 + side * 1.15, 0.5, tunnel_z), Vector3(0.3, 1.0, tunnel_len), "dark_grid")
	_box(Vector3(-19.0, 1.15, tunnel_z), Vector3(2.6, 0.3, tunnel_len), "purple_grid")
	_label("TÚNEL — DEITE", Vector3(-19.0, 1.9, tunnel_z + tunnel_len * 0.5 + 0.1), 40)
	# 5) Rampas de 15°, 30° e 40° até plataformas de 2 m (subindo para o norte).
	var start_z := -6.0
	for spec in [[-34.0, 15.0], [-28.0, 30.0], [-22.0, 40.0]]:
		var x: float = spec[0]
		var run := 2.0 / tan(deg_to_rad(spec[1]))
		var top_z := start_z - run
		_ramp(Vector3(x, 0, start_z), Vector3(x, 2.0, top_z), 3.0, "light_grid")
		_box(Vector3(x, 1.0, top_z - 1.5), Vector3(3.0, 2.0, 3.0), "orange_grid")
		_label("RAMPA %d°" % int(spec[1]), Vector3(x, 0.03, start_z + 1.2), 48, true)
	# 6) Escada de verdade até um deck de 3 m.
	var stair_x := -14.0
	_stairs(Vector3(stair_x, 0, start_z), Vector3(0, 0, -1), 5.0, 3.0, 2.0, "light_grid")
	_box(Vector3(stair_x, 1.5, start_z - 5.0 - 2.0), Vector3(4.0, 3.0, 4.0), "purple_grid")
	_label("ESCADA 3 m", Vector3(stair_x, 0.03, start_z + 1.2), 48, true)

# ---------------------------------------------------------- área de cobertura ---

func _cover_area() -> void:
	# Casa de tiro (12 × 10 m, paredes de 3 m): porta ao sul e a oeste, janelas.
	var c := Vector2(36.0, -30.0)
	var w := 12.0
	var d := 10.0
	var h := 3.0
	var t := 0.3
	_wall_x(c.y - d * 0.5, c.x - w * 0.5, c.x + w * 0.5, h, t, [[c.x - 3.0, 1.6], [c.x + 3.0, 1.6]], true)
	_wall_x(c.y + d * 0.5, c.x - w * 0.5, c.x + w * 0.5, h, t, [[c.x, 1.4]], false)
	_wall_z(c.x - w * 0.5, c.y - d * 0.5, c.y + d * 0.5, h, t, [[c.y, 1.4]], false)
	_wall_z(c.x + w * 0.5, c.y - d * 0.5, c.y + d * 0.5, h, t, [[c.y, 1.6]], true)
	_box(Vector3(c.x, h + 0.15, c.y), Vector3(w + t, 0.3, d + t), "dark_grid") # laje
	_paint(c, Vector2(w - t, d - t), "light_marks")
	# Divisória interna com passagem e caixotes de cobertura.
	_box(Vector3(c.x - 1.0, h * 0.5, c.y - 1.5), Vector3(0.3, h, 4.0), "light_grid")
	_box(Vector3(c.x + 3.5, 0.5, c.y + 2.0), Vector3(1.0, 1.0, 1.0), "orange_grid")
	_box(Vector3(c.x - 4.0, 0.5, c.y - 3.0), Vector3(1.0, 1.0, 1.0), "orange_grid")
	_label("CASA DE TIRO", Vector3(c.x, h + 0.9, c.y + d * 0.5 + 0.2), 64)
	# Campo de cobertura: muretas (1,2 m, cobre agachado) e muros altos (2,2 m).
	for spec in [
		[30.0, -12.0, 4.0, true, 1.2], [40.0, -14.0, 4.0, false, 2.2], [27.0, -4.0, 3.5, false, 2.2],
		[35.0, -5.0, 4.0, true, 1.2], [44.0, -4.0, 3.5, true, 2.2], [31.0, 5.0, 4.0, true, 2.2],
		[40.0, 6.0, 4.0, false, 1.2], [26.0, 12.0, 3.5, true, 1.2], [45.0, 14.0, 4.0, false, 2.2],
	]:
		var size := Vector3(spec[2], spec[4], 0.45) if spec[3] else Vector3(0.45, spec[4], spec[2])
		_box(Vector3(spec[0], spec[4] * 0.5, spec[1]), size, "green_grid" if spec[4] < 2.0 else "light_grid")
	# Caixotes (1 m) soltos e empilhados.
	for spec in [[33.0, 0.0, 1], [37.0, -9.0, 2], [42.0, 1.0, 1], [28.0, 8.0, 2], [36.0, 12.0, 1], [46.0, -10.0, 1]]:
		for k in int(spec[2]):
			_box(Vector3(spec[0], 0.5 + k, spec[1]), Vector3(1.0, 1.0, 1.0), "orange_grid")
	_label("ÁREA DE COBERTURA", Vector3(36.0, 0.03, 18.5), 72, true)

## Parede correndo em X (no z dado) com vãos [centro, largura]. window = true:
## os vãos são janelas (peitoril a 1 m, topo a 2 m); senão portas (até 2,2 m).
func _wall_x(z: float, x0: float, x1: float, h: float, t: float, gaps: Array, window: bool) -> void:
	var cursor := x0
	for gap in gaps:
		var a: float = gap[0] - gap[1] * 0.5
		var b: float = gap[0] + gap[1] * 0.5
		_box(Vector3((cursor + a) * 0.5, h * 0.5, z), Vector3(a - cursor, h, t), "light_grid")
		_opening_fill(Vector3((a + b) * 0.5, 0, z), Vector3(b - a, 0, t), h, window)
		cursor = b
	_box(Vector3((cursor + x1) * 0.5, h * 0.5, z), Vector3(x1 - cursor, h, t), "light_grid")

func _wall_z(x: float, z0: float, z1: float, h: float, t: float, gaps: Array, window: bool) -> void:
	var cursor := z0
	for gap in gaps:
		var a: float = gap[0] - gap[1] * 0.5
		var b: float = gap[0] + gap[1] * 0.5
		_box(Vector3(x, h * 0.5, (cursor + a) * 0.5), Vector3(t, h, a - cursor), "light_grid")
		_opening_fill(Vector3(x, 0, (a + b) * 0.5), Vector3(t, 0, b - a), h, window)
		cursor = b
	_box(Vector3(x, h * 0.5, (cursor + z1) * 0.5), Vector3(t, h, z1 - cursor), "light_grid")

## Parede acima (e abaixo, nas janelas) de um vão.
func _opening_fill(center: Vector3, span: Vector3, h: float, window: bool) -> void:
	var top := 2.0 if window else 2.2
	_box(Vector3(center.x, (top + h) * 0.5, center.z), Vector3(maxf(span.x, 0.3), h - top, maxf(span.z, 0.3)), "light_grid")
	if window:
		_box(Vector3(center.x, 0.5, center.z), Vector3(maxf(span.x, 0.3), 1.0, maxf(span.z, 0.3)), "light_grid")

# ------------------------------------------------------------------ placas ---

func _signs() -> void:
	_label("CAMPO DE TREINO", Vector3(SPAWN.x, 0.03, SPAWN.z + 3.4), 80, true)
	_label("PERCURSO DE AGILIDADE", Vector3(-24.0, 0.03, -1.0), 72, true)
	_label("PRAÇA LIVRE", Vector3(0.0, 0.03, 34.0), 64, true)
