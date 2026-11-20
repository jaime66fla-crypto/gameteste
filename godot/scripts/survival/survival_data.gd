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
