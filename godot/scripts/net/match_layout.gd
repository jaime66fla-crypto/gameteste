extends RefCounted
## Mapas das partidas online (data/match_maps.json, gerado por
## scripts/gen-match-maps.mjs e lido também pelo servidor, que só usa os
## nascimentos). Um mapa por modo:
##   praca   — Eliminatória
##   cruz    — Mata-mata
##   equipes — Equipes 2x2 e 4x4 (sala personalizada)
## A cidade antiga (data/match_layout.json) agora é só o centro da Sobrevivência:
## city_layout().
const PATH := "res://data/match_maps.json"
const CITY_PATH := "res://data/match_layout.json"
static var _data: Dictionary = {}
static var _city: Dictionary = {}
## Mapa em uso (main.gd escolhe pelo start_info antes de montar a cena).
static var map_id := "praca"

static func _all() -> Dictionary:
	if _data.is_empty():
		_data = _read(PATH)
	return _data

static func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing " + path)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid " + path)
		return {}
	return data

static func map_ids() -> Array:
	return (_all().get("maps", {}) as Dictionary).keys()

## Mapa de uma partida: o que o servidor mandou em "map", senão pelo modo.
static func map_for(info: Dictionary) -> String:
	var maps: Dictionary = _all().get("maps", {})
	var wanted := str(info.get("map", ""))
	if maps.has(wanted):
		return wanted
	var modes: Dictionary = _all().get("modes", {})
	if bool(info.get("party", false)):
		return str(modes.get("teams", "equipes"))
	if str(info.get("mode", "")) == "dm":
		return str(modes.get("dm", "cruz"))
	return str(modes.get("elim", "praca"))

static func use_map(id: String) -> void:
	if (_all().get("maps", {}) as Dictionary).has(id):
		map_id = id

static func load_layout() -> Dictionary:
	return (_all().get("maps", {}) as Dictionary).get(map_id, {})

static func palette() -> Dictionary:
	return _all().get("palette", {})

static func spawn_point(index: int) -> Vector3:
	var spawns: Array = load_layout().get("spawns", [])
	if spawns.is_empty():
		return Vector3.ZERO
	var spot: Array = spawns[posmod(index, spawns.size())]
	return Vector3(spot[0], 0, spot[1])

## Quem nasce olha para o centro do mapa.
static func spawn_yaw(point: Vector3) -> float:
	if Vector2(point.x, point.z).length() < 0.5:
		return PI
	return atan2(point.x, point.z)

## Prédio (com porta em +Z) que contém `point`, ou {}. Os mapas novos não têm
## portas fixas: os bots andam pela grade A* (bot_nav.gd).
static func building_at(point: Vector3) -> Dictionary:
	for building in load_layout().get("buildings", []):
		var c: Array = building["center"]
		var s: Array = building["size"]
		if absf(point.x - float(c[0])) < float(s[0]) * 0.5 and absf(point.z - float(c[1])) < float(s[1]) * 0.5:
			return building
	return {}

## Cidade do meio da Sobrevivência (world_polish.gd).
static func city_layout() -> Dictionary:
	if _city.is_empty():
		_city = _read(CITY_PATH)
	return _city
