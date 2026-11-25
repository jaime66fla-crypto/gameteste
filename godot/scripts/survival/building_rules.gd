extends RefCounted
## Grade de construção da Sobrevivência: as mesmas contas do servidor
## (src/godot-building.js), para a prévia já mostrar verde/vermelho.
## O servidor confere de novo e tem a palavra final.
##
## A célula (i, j) cobre x ∈ [i·S, (i+1)·S] e z ∈ [j·S, (j+1)·S]. Andar k: chão
## em base + story·k + LIFT·b. Bordas: "h" (i, j) = lado z = j·S; "v" (i, j) = lado x = i·S.
##
## Relevo: cada peça da grade tem um degrau "b" (LIFT m cada). A fundação fica
## logo acima do ponto mais alto do chão embaixo dela, com um pilar até o ponto
## mais baixo; o que vai em cima herda o degrau. Degraus diferentes não se apoiam.
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const Hydro = preload("res://scripts/survival/hydrology.gd")
var wetness := 0.0
const EDGE_KINDS := ["wall", "doorway", "window"]
const MAX_LEVEL := 6
const LIFT := 0.25
const MAX_LIFT := 160
const MAX_PILLAR := 8.0
const FREE_R := 0.5
const MAP_BLOCKERS := {"tree": 0.5, "rock": 1.3, "ore": 1.3, "saltpeter": 1.3, "bush": 0.7, "car": 2.5}

## Altura do chão em (x, z). Treino: chão plano; Sobrevivência: o relevo do mapa.
var ground: Callable = func(_x: float, _z: float) -> float: return 0.0

## Mesmo retângulo e mesmas margens de groundFree no servidor.
func ground_error(p: Dictionary, map: Dictionary) -> String:
	var kind := str(p.get("kind", ""))
	var def: Dictionary = defs.get(kind, {})
	var box: Rect2
	if str(def.get("slot", "")) == "free":
		var v: Array = p.get("p", [0, 0, 0])
		var r := float(def.get("r", 0.0))
		box = Rect2(Vector2(float(v[0]) - r, float(v[2]) - r), Vector2.ONE * r * 2.0)
	elif kind == "foundation":
		box = Rect2(Vector2(int(p["i"]) * S, int(p["j"]) * S), Vector2.ONE * S)
	else:
		return ""
	var half := float(map.get("half_size", 240)) - 6.0
	for n in [box.position.x, box.position.y, box.end.x, box.end.y]:
		if absf(n) > half:
			return "Fora da área do mundo."
	for x in [box.position.x, box.get_center().x, box.end.x]:
		for z in [box.position.y, box.get_center().y, box.end.y]:
			if not Hydro.water_at(x, z, wetness).is_empty(): return "Não dá para construir na água."
	for pond in map.get("ponds", []):
		if _box_distance(box, Vector2(float(pond.x), float(pond.z))) < float(pond.r) + 1.0:
			return "Não dá para construir na água."
	if str(def.get("slot", "")) == "free":
		var sup := supporters(p)
		if sup.is_empty() or typeof(sup[0]) != TYPE_STRING:
			return "" # em cima de piso: o chão embaixo não importa
	for resource in map.get("resources", []):
		var res_kind := str(resource.get("kind", ""))
		if not MAP_BLOCKERS.has(res_kind):
			continue
		var margin := float(MAP_BLOCKERS[res_kind])
		var v: Array = resource["p"]
		if float(v[0]) > box.position.x - margin and float(v[0]) < box.end.x + margin and float(v[2]) > box.position.y - margin and float(v[2]) < box.end.y + margin:
			return "Tem %s no caminho." % str(SurvivalData.resource_rule(res_kind).get("name", "algo")).to_lower()
	return ""

static func _box_distance(box: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(box.position.x - p.x, 0.0), p.x - box.end.x), maxf(maxf(box.position.y - p.y, 0.0), p.y - box.end.y)).length()

var S := 3.0
var H := 3.0
var base := 0.4
var defs: Dictionary = {}
var pieces: Dictionary = {} # id -> peça (o pacote do servidor)
var slots: Dictionary = {} # chave -> id

func _init() -> void:
	var rules: Dictionary = SurvivalData.catalog().get("build_rules", {})
	S = float(rules.get("cell", 3.0))
	H = float(rules.get("story", 3.0))
	base = float(rules.get("base", 0.4))
	defs = SurvivalData.catalog().get("builds", {})

func slot_type(kind: String) -> String:
	return str(defs.get(kind, {}).get("slot", ""))

func top(k: int, b: int = 0) -> float:
	return base + H * k + LIFT * b

## Degrau da peça (peças antigas não têm: 0).
static func lift_of(p: Dictionary) -> int:
	return int(p.get("b", 0))

## Chão mais baixo e mais alto num retângulo (amostras 5×5): Vector2(min, max).
func ground_span(x0: float, z0: float, x1: float, z1: float) -> Vector2:
	var lo := INF
	var hi := -INF
	for a in 5:
		for c in 5:
			var h: float = ground.call(x0 + (x1 - x0) * a / 4.0, z0 + (z1 - z0) * c / 4.0)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)

func cell_ground(i: int, j: int) -> Vector2:
	return ground_span(i * S, j * S, (i + 1) * S, (j + 1) * S)

## Menor degrau de uma fundação em (i, j): topo `base` acima do chão mais alto.
func foundation_lift(i: int, j: int) -> int:
	return maxi(-MAX_LIFT, ceili(cell_ground(i, j).y / LIFT - 1e-6))

## Chão sob o pé de uma peça livre.
func free_ground(p: Dictionary) -> Vector2:
	var r := float(defs.get(str(p.get("kind", "")), {}).get("r", 0.0))
	if r <= 0.0:
		r = FREE_R
	var v: Array = p.get("p", [0, 0, 0])
	return ground_span(float(v[0]) - r, float(v[2]) - r, float(v[0]) + r, float(v[2]) + r)

static func cell_key(i: int, j: int, k: int) -> String:
	return "c:%d:%d:%d" % [i, j, k]

static func edge_key(o: String, i: int, j: int, k: int) -> String:
	return "e:%s:%d:%d:%d" % [o, i, j, k]

func slot_of(p: Dictionary) -> String:
	var i := int(p.get("i", 0))
	var j := int(p.get("j", 0))
	var k := int(p.get("k", 0))
	var o := str(p.get("o", ""))
	match slot_type(str(p.get("kind", ""))):
		"cell": return cell_key(i, j, k)
		"edge": return edge_key(o, i, j, k)
		"door": return "d:%s:%d:%d:%d" % [o, i, j, k]
		"stairs": return "s:%d:%d:%d" % [i, j, k]
	return ""

func at(key: String) -> Dictionary:
	var id = slots.get(key)
	return pieces.get(id, {}) if id != null else {}

static func edge_cells(o: String, i: int, j: int) -> Array:
	return [[i, j - 1], [i, j]] if o == "h" else [[i - 1, j], [i, j]]

static func cell_edges(i: int, j: int) -> Array:
	return [["h", i, j], ["h", i, j + 1], ["v", i, j], ["v", i + 1, j]]

func add(p: Dictionary) -> void:
	pieces[str(p["id"])] = p
	var key := slot_of(p)
	if not key.is_empty():
		slots[key] = str(p["id"])

func erase(id: String) -> void:
	var p: Dictionary = pieces.get(id, {})
	if p.is_empty():
		return
	pieces.erase(id)
	var key := slot_of(p)
	if not key.is_empty() and slots.get(key) == id:
		slots.erase(key)

# ------------------------------------------------------------- geometria ---

## Centro da peça no mundo.
func center(p: Dictionary) -> Vector3:
	var kind := str(p.get("kind", ""))
	var slot := slot_type(kind)
	var i := int(p.get("i", 0))
	var j := int(p.get("j", 0))
	var k := int(p.get("k", 0))
	if slot == "free":
		var v: Array = p.get("p", [0, 0, 0])
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	var t := top(k, lift_of(p))
	if slot == "edge" or slot == "door":
		var x := (i + 0.5) * S if str(p.get("o", "")) == "h" else i * S
		var z := j * S if str(p.get("o", "")) == "h" else (j + 0.5) * S
		return Vector3(x, t + (1.1 if slot == "door" else H * 0.5), z)
	var y := t + H * 0.5 if slot == "stairs" else t - 0.2
	return Vector3((i + 0.5) * S, y, (j + 0.5) * S)

# ----------------------------------------------------------------- apoio ---

## Parede/vão na borda (no degrau `b`; NO_LIFT = qualquer degrau).
const NO_LIFT := -999999

func edge_at(o: String, i: int, j: int, k: int, b: int = NO_LIFT) -> Dictionary:
	var p := at(edge_key(o, i, j, k))
	return p if not p.is_empty() and str(p["kind"]) in EDGE_KINDS and (b == NO_LIFT or lift_of(p) == b) else {}

func floor_at(i: int, j: int, k: int, b: int = NO_LIFT) -> Dictionary:
	var p := at(cell_key(i, j, k))
	if p.is_empty() or (b != NO_LIFT and lift_of(p) != b):
		return {}
	var ok := str(p["kind"]) == "foundation" if k == 0 else str(p["kind"]) == "floor"
	return p if ok else {}

func walls_under(i: int, j: int, k: int, b: int = NO_LIFT) -> Array:
	var out: Array = []
	for e in cell_edges(i, j):
		var w := edge_at(e[0], e[1], e[2], k - 1, b)
		if not w.is_empty():
			out.append(w)
	return out

## Fundação/piso embaixo do ponto (o mais alto que não passa dele).
func cell_under(point: Vector3) -> Dictionary:
	var i := floori(point.x / S)
	var j := floori(point.z / S)
	var best := {}
	for k in MAX_LEVEL + 1:
		var f := floor_at(i, j, k)
		if not f.is_empty() and top(k, lift_of(f)) <= point.y + 0.3:
			best = f
	return best

## Quem segura a peça ("ground" = o chão). Vazio = sem apoio.
func supporters(p: Dictionary) -> Array:
	var kind := str(p.get("kind", ""))
	var slot := slot_type(kind)
	var i := int(p.get("i", 0))
	var j := int(p.get("j", 0))
	var k := int(p.get("k", 0))
	var o := str(p.get("o", ""))
	var lift := lift_of(p)
	if kind == "foundation":
		return ["ground"]
	match slot:
		"cell":
			if k < 1:
				return []
			var walls := walls_under(i, j, k, lift)
			if not walls.is_empty():
				return walls
			var out: Array = []
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var n := floor_at(i + d[0], j + d[1], k, lift)
				if not n.is_empty() and str(n["kind"]) == "floor" and not walls_under(int(n["i"]), int(n["j"]), k, lift).is_empty():
					out.append(n)
			return out
		"edge":
			var out: Array = []
			if k > 0:
				var below := edge_at(o, i, j, k - 1, lift)
				if not below.is_empty():
					out.append(below)
			for c in edge_cells(o, i, j):
				var f := floor_at(c[0], c[1], k, lift)
				if not f.is_empty():
					out.append(f)
			return out
		"door":
			var frame := at(edge_key(o, i, j, k))
			return [frame] if not frame.is_empty() and str(frame["kind"]) == "doorway" and lift_of(frame) == lift else []
		"stairs":
			var f := floor_at(i, j, k, lift)
			return [f] if not f.is_empty() else []
	var point := center(p)
	if bool(p.get("wall", false)):
		return wall_behind(point)
	# Peça livre: em cima de fundação/piso, ou no chão (no ponto mais alto
	# embaixo dela, nunca enterrada nem dentro de uma fundação).
	var under := cell_under(point)
	if not under.is_empty() and absf(top(int(under["k"]), lift_of(under)) - point.y) < 0.3:
		return [under]
	var span := free_ground(p)
	if point.y < span.x - 0.1 or point.y > span.y + 0.25:
		return []
	var found := floor_at(floori(point.x / S), floori(point.z / S), 0)
	return [] if not found.is_empty() and top(0, lift_of(found)) > point.y - 0.3 else ["ground"]

## Parede/vão encostado no ponto (tocha presa na parede): [parede] ou [].
func wall_behind(point: Vector3) -> Array:
	for o in ["h", "v"]:
		var i := floori(point.x / S) if o == "h" else roundi(point.x / S)
		var j := roundi(point.z / S) if o == "h" else floori(point.z / S)
		var gap := absf(point.z - j * S) if o == "h" else absf(point.x - i * S)
		if gap > 0.3:
			continue
		for k in MAX_LEVEL + 1:
			var w := edge_at(o, i, j, k)
			if w.is_empty():
				continue
			var t := top(k, lift_of(w))
			if point.y >= t and point.y < t + H:
				return [w]
	return []

## Degrau para uma peça da grade (igual a guessLift do servidor): a fundação
## fica logo acima do chão; o resto copia o degrau de quem pode segurá-la.
func guess_lift(p: Dictionary) -> int:
	var kind := str(p.get("kind", ""))
	var slot := slot_type(kind)
	var i := int(p.get("i", 0))
	var j := int(p.get("j", 0))
	var k := int(p.get("k", 0))
	var o := str(p.get("o", ""))
	if kind == "foundation":
		return foundation_lift(i, j)
	var near: Array = []
	var candidates: Array = []
	if slot == "cell" or slot == "stairs":
		for e in cell_edges(i, j):
			candidates.append(at(edge_key(e[0], e[1], e[2], k - 1)))
		candidates.append(at(cell_key(i, j, k)))
		for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			candidates.append(at(cell_key(i + d[0], j + d[1], k)))
	elif slot == "edge" or slot == "door":
		candidates.append(at(edge_key(o, i, j, k)))
		candidates.append(at(edge_key(o, i, j, k - 1)))
		for c in edge_cells(o, i, j):
			candidates.append(at(cell_key(c[0], c[1], k)))
	for c in candidates:
		if not c.is_empty():
			near.append(lift_of(c))
	for b in near:
		var probe := p.duplicate()
		probe["b"] = b
		if not supporters(probe).is_empty():
			return b
	return near[0] if not near.is_empty() else 0

## Motivo para não poder construir ("" = pode). `owns` diz se quem constrói
## pode se apoiar na peça (dono ou liberado).
func check(p: Dictionary, owns: Callable) -> String:
	var kind := str(p.get("kind", ""))
	if not defs.has(kind):
		return "Peça desconhecida."
	var slot := slot_type(kind)
	var i := int(p.get("i", 0))
	var j := int(p.get("j", 0))
	var k := int(p.get("k", 0))
	var o := str(p.get("o", ""))
	if slot != "free" and (k < 0 or k > MAX_LEVEL):
		return "Alto demais."
	if kind == "foundation" and k != 0:
		return "A fundação vai no chão."
	if slot == "cell" and kind != "foundation" and k < 1:
		return "Piso e telhado vão em cima das paredes."
	if slot != "free":
		if absi(lift_of(p)) > MAX_LIFT:
			return "Altura inválida."
		if kind == "foundation":
			var span := cell_ground(i, j)
			var t := top(0, lift_of(p))
			if t < span.y + 0.15:
				return "A fundação ficaria enterrada."
			if t - span.x > MAX_PILLAR:
				return "Alto demais: o pilar não chega ao chão."
	var key := slot_of(p)
	if not key.is_empty() and slots.has(key):
		return "Já tem uma peça aí."
	if slot == "cell" and k >= 1 and not at("s:%d:%d:%d" % [i, j, k - 1]).is_empty():
		return "A escada passa por aqui."
	if slot == "stairs" and not at(cell_key(i, j, k + 1)).is_empty():
		return "Tem um piso em cima: a escada não passa."
	if slot == "edge" and k > 0:
		for c in edge_cells(o, i, j):
			var roof := at(cell_key(c[0], c[1], k))
			if not roof.is_empty() and str(roof["kind"]) == "roof" and edge_at(o, i, j, k - 1).is_empty():
				return "Não dá para construir em cima do telhado."
	var sup := supporters(p)
	if sup.is_empty():
		return str({"cell": "Precisa de paredes embaixo (ou um piso vizinho apoiado).", "edge": "Precisa de fundação, piso ou parede embaixo.",
			"door": "Precisa de uma parede com porta.", "stairs": "Precisa de fundação ou piso embaixo.", "free": "Precisa de chão firme."}.get(slot, "Sem apoio."))
	for s in sup:
		if typeof(s) == TYPE_STRING or bool(owns.call(s)):
			return ""
	return "Essa construção é de outro jogador."
