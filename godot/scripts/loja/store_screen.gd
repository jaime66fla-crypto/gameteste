extends VBoxContainer
## Tela da Loja (menu principal → Loja): saldo de Brasas e os itens à venda em
## grupos (Personagens, Skins de armas, Skins de personagens), cada um numa
## carta com prévia 3D, preço e Comprar. Quem confere saldo e cobra é o
## servidor (Net.buy_item); o que é comprado vai para o Cofre e já é equipado.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const StorePreview = preload("res://scripts/loja/store_preview.gd")
const CARD_WIDTH := 250.0
const PREVIEW_SIZE := Vector2(226, 190)

signal purchased(item_id: String)

var _cards := {} # id -> {"state": Label, "button": Button}
var _balance: Label
var _feedback: Label
var _buying := ""

func _ready() -> void:
	name = "StoreScreen"
	add_theme_constant_override("separation", 18)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	_balance = UiTheme.title("", 26, UiTheme.ACCENT)
	_balance.name = "StoreBalance"
	top.add_child(_balance)
	var hint := UiTheme.label("1 Brasa a cada %d XP nas partidas e na Sobrevivência online. O que você compra fica no Cofre." % int(StoreCatalog._load().get("xp_per_brasa", 10)), 14, UiTheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(hint)
	_feedback = UiTheme.label("", 14, UiTheme.MUTED, 600)
	_feedback.name = "StoreFeedback"
	add_child(_feedback)
	for group in StoreCatalog.groups():
		var on_sale := StoreCatalog.items_in(str(group.get("id", ""))).filter(func(entry): return int(entry.get("preco", 0)) > 0)
		if on_sale.is_empty():
			continue
		add_child(_section(group, on_sale))
	_refresh()

func _section(group: Dictionary, entries: Array) -> Control:
	var section := VBoxContainer.new()
	section.name = "Grupo_" + str(group.get("id", ""))
	section.add_theme_constant_override("separation", 10)
	section.add_child(UiTheme.caps(str(group.get("nome", "")).to_upper(), 13, UiTheme.ACCENT))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	section.add_child(flow)
	for entry in entries:
		flow.add_child(_card(entry))
	return section

func _card(entry: Dictionary) -> Control:
	var id := str(entry["id"])
	var card := PanelContainer.new()
	card.name = "Item_" + id
	card.custom_minimum_size.x = CARD_WIDTH
	card.add_theme_stylebox_override("panel", UiTheme.card(12))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	column.add_child(StorePreview.new(id, PREVIEW_SIZE))
	column.add_child(UiTheme.caps(str(entry.get("tipo", "")).to_upper(), 11, UiTheme.MUTED))
	column.add_child(UiTheme.label(str(entry.get("nome", id)), 16, UiTheme.TEXT, 600))
	var state := UiTheme.label("", 13, UiTheme.ACCENT, 700)
	column.add_child(state)
	var button := Button.new()
	button.name = "Buy_" + id
	button.custom_minimum_size.y = 38
	button.pressed.connect(_buy.bind(id))
	column.add_child(button)
	_cards[id] = {"state": state, "button": button}
	return card

func _buy(id: String) -> void:
	if not _buying.is_empty() or StoreCatalog.is_owned(id):
		return
	_buying = id
	_say("Comprando %s..." % StoreCatalog.item(id).get("nome", id), UiTheme.MUTED)
	_refresh()
	var net := get_node_or_null("/root/Net")
	var result: Dictionary = {"ok": false, "message": "Sem conexão com o servidor."}
	if net != null:
		result = await net.buy_item(id)
	if not is_inside_tree():
		return
	_buying = ""
	var ok := bool(result.get("ok", false)) and StoreCatalog.is_owned(id)
	if ok:
		equip(id)
		_say("%s Já está equipado no seu Cofre." % str(result.get("message", "")), UiTheme.GOOD)
		purchased.emit(id)
	else:
		_say(str(result.get("message", "Não foi possível comprar.")), UiTheme.DANGER)
	_refresh()

## Equipa um item recém-comprado: personagem selecionado, skin na arma, roupa vestida.
static func equip(id: String) -> void:
	match StoreCatalog.group_of(id):
		"personagens":
			Registry.select_character(id)
		"skins_armas":
			Registry.set_weapon_skin(StoreCatalog.weapon(id), id)
		"skins_personagens":
			var worn := Registry.load_outfit()
			var piece := StoreCatalog.piece(id)
			var legs := ["calca", "bermuda"]
			var next := PackedStringArray()
			for other in worn:
				var other_piece := StoreCatalog.piece(other)
				if other_piece != piece and not (piece in legs and other_piece in legs):
					next.append(other)
			next.append(id)
			Registry.save_outfit(next)

func _say(text: String, color: Color) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", color)

func _refresh() -> void:
	var logged := StoreCatalog.logged_in()
	var balance := StoreCatalog.balance()
	var money := StoreCatalog.currency()
	_balance.text = "%d %s" % [balance, money] if logged else "Entre na conta para comprar"
	for id in _cards:
		var parts: Dictionary = _cards[id]
		var state := parts["state"] as Label
		var button := parts["button"] as Button
		var price := StoreCatalog.price(id)
		if StoreCatalog.is_owned(id):
			state.text = "✓ NO SEU COFRE"
			state.add_theme_color_override("font_color", UiTheme.GOOD)
			button.text = "Comprado"
			button.disabled = true
			button.tooltip_text = ""
			UiTheme.secondary(button, 14)
			continue
		state.text = ("%d %s" % [price, money]).to_upper()
		state.add_theme_color_override("font_color", UiTheme.ACCENT)
		button.text = "Comprando..." if _buying == id else "Comprar"
		button.disabled = not logged or balance < price or not _buying.is_empty()
		if not logged:
			button.tooltip_text = "Entre na sua conta para comprar."
		elif balance < price:
			button.tooltip_text = "Faltam %d %s." % [price - balance, money]
		else:
			button.tooltip_text = ""
		UiTheme.primary(button, 14)
