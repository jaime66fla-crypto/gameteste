extends RefCounted
## Catálogo da loja interna (data/store.json, o mesmo que o servidor lê).
## Brasas e itens comprados vêm do perfil da conta (Net.profile: "brasas",
## "owned"); quem confere saldo e cobra é sempre o servidor (/godot/store/buy).
const PATH := "res://data/store.json"

static var _data: Dictionary = {}

static func _load() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"items": []}
	return _data

static func currency() -> String:
	return str(_load().get("currency", "Brasas"))

static func items() -> Array:
	return _load().get("items", [])

static func item(id: String) -> Dictionary:
	for entry in items():
		if str(entry.get("id", "")) == id:
			return entry
	return {}

## Pacotes de Brasas do site: [{id, brasas, bonus, preco_centavos, destaque?}].
static func packs() -> Array:
	return _load().get("pacotes", [])

## 1250 -> "1.250" (separador de milhar brasileiro).
static func format_amount(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "." + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out

## 1990 -> "R$ 19,90".
static func format_brl(cents: int) -> String:
	return "R$ %s,%02d" % [format_amount(cents / 100), cents % 100]

## Grupos da loja, na ordem da tela: [{id, nome}].
static func groups() -> Array:
	return _load().get("groups", [])

static func group_of(id: String) -> String:
	return str(item(id).get("grupo", ""))

static func items_in(group: String) -> Array:
	return items().filter(func(entry): return str(entry.get("grupo", "")) == group)

## Arma de uma skin de arma ("rifle", "pistol"...).
static func weapon(id: String) -> String:
	return str(item(id).get("arma", ""))

## Personagem liberado: o padrão (fora da loja) ou um personagem que a conta comprou.
static func owns_character(character_id: String) -> bool:
	var entry := item(character_id)
	if entry.is_empty() or str(entry.get("grupo", "")) != "personagens":
		return true
	return is_owned(character_id)

static func price(id: String) -> int:
	return int(item(id).get("preco", 0))

## Peça (malha Roupa_<peca>) que o item veste.
static func piece(id: String) -> String:
	return str(item(id).get("peca", ""))

static func texture_path(id: String) -> String:
	return str(item(id).get("textura", ""))

static func _net() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("Net") if loop != null else null

static func logged_in() -> bool:
	var net := _net()
	return net != null and bool(net.call("is_logged_in"))

static func balance() -> int:
	var net := _net()
	return int(net.get("profile").get("brasas", 0)) if net != null else 0

## Grátis é de todo mundo; pago só se a conta comprou.
static func is_owned(id: String) -> bool:
	if item(id).is_empty():
		return false
	if price(id) <= 0:
		return true
	var net := _net()
	if net == null:
		return false
	var owned = net.get("profile").get("owned", [])
	return owned is Array and id in owned
