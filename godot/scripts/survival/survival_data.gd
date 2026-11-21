extends RefCounted
## Dados do modo Sobrevivência, os mesmos que o servidor usa:
## data/survival_world.json (mapa gerado por scripts/gen-survival-world.mjs)
## e data/survival_items.json (itens, saques, coleta, receitas).

static var _world: Dictionary = {}
static var _items: Dictionary = {}

static func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Sobrevivência: não abriu " + path)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if typeof(data) == TYPE_DICTIONARY else {}

static func world() -> Dictionary:
	if _world.is_empty():
		_world = _load("res://data/survival_world.json")
	return _world

static func catalog() -> Dictionary:
	if _items.is_empty():
		_items = _load("res://data/survival_items.json")
	return _items

static func item(id: String) -> Dictionary:
	return catalog().get("items", {}).get(id, {})

static func item_name(id: String) -> String:
	return str(item(id).get("name", id))

static func recipes() -> Array:
	return catalog().get("recipes", [])

## Estações utilizáveis agora: mesmo alcance horizontal e vertical do servidor.
static func nearby_stations(pieces: Array, position: Vector3) -> Dictionary:
	var available := {}
	for piece in pieces:
		var kind := str(piece.get("kind", ""))
		var def := build_def(kind)
		if not bool(def.get("station", false)) or (bool(def.get("lit", false)) and not bool(piece.get("on", false))):
			continue
		var p: Array = piece.get("p", [])
		if p.size() != 3:
			continue
		var dx := float(p[0]) - position.x
		var dz := float(p[2]) - position.z
		if sqrt(dx * dx + dz * dz) < 3.6 and absf(float(p[1]) - position.y) < 2.0:
			available[kind] = true
	return available

## Uma única regra de disponibilidade para o inventário e o manual.
static func craft_error(recipe: Dictionary, inv: Dictionary, known: Array, stations: Dictionary, weight: float = 0.0, cap: float = INF) -> String:
	var station := str(recipe.get("station", ""))
	if bool(recipe.get("soon", false)) or bool(build_def(station).get("soon", false)):
		return "Essa receita ainda não existe no jogo."
	if bool(recipe.get("page", false)) and not known.has(str(recipe.get("id", ""))):
		return "Falta a página do manual dessa receita."
	var needs: Dictionary = recipe.get("needs", {})
	for id in needs:
		if int(inv.get(id, 0)) < int(needs[id]):
			return "Falta %s." % item_name(str(id)).to_lower()
	if not station.is_empty() and not bool(stations.get(station, false)):
		return station_note(station) + "."
	var gives: Array = recipe.get("gives", ["", 0])
	var output := float(item(str(gives[0])).get("weight", 0.0)) * int(gives[1])
	if weight - inventory_weight(needs) + output > maxf(cap, weight) + 0.000001:
		return "Peso demais para fabricar. Guarde ou largue alguns itens."
	return ""

## Construção pelo id ("forge" -> {name, cost, station, lit...}).
static func build_def(kind: String) -> Dictionary:
	return catalog().get("builds", {}).get(kind, {})

## "Perto de uma forja acesa" / "Perto de uma bancada" / "" (na mão).
static func station_note(station: String) -> String:
	if station.is_empty():
		return ""
	var def := build_def(station)
	var name := str(def.get("name", station)).to_lower()
	return ("Perto de uma %s acesa" if bool(def.get("lit", false)) else "Perto de uma %s") % name

static func resource_rule(kind: String) -> Dictionary:
	return catalog().get("resources", {}).get(kind, {})

static func container_name(type: String) -> String:
	return str(catalog().get("loot", {}).get(type, {}).get("name", "Recipiente"))

## Arma de fogo do item ("w_rifle" -> "rifle"), ou "".
static func weapon_of(id: String) -> String:
	return str(item(id).get("weapon", ""))

## Munição usada por uma arma ("rifle" -> "a_556").
static func ammo_for(weapon_id: String) -> String:
	for id in catalog().get("items", {}):
		var entry: Dictionary = catalog()["items"][id]
		if str(entry.get("weapon", "")) == weapon_id:
			return str(entry.get("ammo", ""))
	return ""

## Melhor arma branca da mochila: [item, dano] (soco = ["", 9]).
static func best_melee(inv: Dictionary) -> Array:
	var best := ["", 9]
	for id in inv:
		var dmg := int(item(id).get("melee", 0))
		if dmg > int(best[1]):
			best = [id, dmg]
	return best

static func inventory_weight(inv: Dictionary) -> float:
	var total := 0.0
	for id in inv:
		total += float(item(id).get("weight", 0.0)) * int(inv[id])
	return total
