extends VBoxContainer
## Loja de Brasas (botão + do saldo no canto do menu): pacotes de Brasas que
## serão comprados no site do Campo de Fogo (data/store.json "pacotes").
## O pagamento ainda não está ligado (Fase 2): os botões ficam em "Em breve"
## e a tela explica como ganhar Brasas jogando enquanto isso.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const CARD_WIDTH := 230.0
## Quando o site de pagamento existir, basta preencher (abre no navegador).
const SITE_URL := ""

signal store_requested

func _ready() -> void:
	name = "BrasasShop"
	add_theme_constant_override("separation", 18)
	var balance := UiTheme.title("Seu saldo: %s Brasas" % StoreCatalog.format_amount(StoreCatalog.balance()), 24, UiTheme.ACCENT)
	balance.name = "BrasasShopBalance"
	balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(balance)
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	add_child(flow)
	for pack in StoreCatalog.packs():
		flow.add_child(_card(pack))
	var note := UiTheme.label("A compra de Brasas pelo site chega numa próxima atualização. Enquanto isso, ganhe Brasas jogando online: 1 a cada %d XP, nas partidas e na Sobrevivência." % int(StoreCatalog._load().get("xp_per_brasa", 10)), 14, UiTheme.MUTED)
	note.name = "BrasasShopNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size.x = 640
	add_child(note)
	var store := Button.new()
	store.name = "OpenItemStore"
	store.text = "Ver itens da Loja"
	store.custom_minimum_size = Vector2(260, 44)
	store.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.secondary(store, 15)
	store.pressed.connect(func(): store_requested.emit())
	add_child(store)

func _card(pack: Dictionary) -> Control:
	var id := str(pack.get("id", ""))
	var featured := bool(pack.get("destaque", false))
	var card := PanelContainer.new()
	card.name = "Pack_" + id
	card.custom_minimum_size.x = CARD_WIDTH
	var style := UiTheme.card(16)
	if featured:
		style.border_color = UiTheme.ACCENT
		style.set_border_width_all(2)
		style.shadow_color = Color(UiTheme.ACCENT, 0.18)
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(UiTheme.caps("MAIS ESCOLHIDO" if featured else "PACOTE", 11, UiTheme.ACCENT if featured else UiTheme.MUTED))
	var flame := TextureRect.new()
	flame.texture = load("res://icon.png") as Texture2D
	flame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flame.custom_minimum_size = Vector2(0, 72)
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(flame)
	var amount := UiTheme.title(StoreCatalog.format_amount(int(pack.get("brasas", 0))), 34, UiTheme.TEXT)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(amount)
	var unit := UiTheme.caps("BRASAS", 12, UiTheme.MUTED)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(unit)
	var bonus := int(pack.get("bonus", 0))
	var bonus_label := UiTheme.label("+%s de bônus" % StoreCatalog.format_amount(bonus) if bonus > 0 else " ", 13, UiTheme.GOOD, 600)
	bonus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(bonus_label)
	var price := UiTheme.label(StoreCatalog.format_brl(int(pack.get("preco_centavos", 0))), 18, UiTheme.ACCENT, 700)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(price)
	var button := Button.new()
	button.name = "BuyPack_" + id
	button.custom_minimum_size.y = 40
	button.text = "Comprar no site" if not SITE_URL.is_empty() else "Em breve"
	button.disabled = SITE_URL.is_empty()
	button.tooltip_text = "" if not SITE_URL.is_empty() else "A compra pelo site ainda não está disponível."
	UiTheme.primary(button, 14)
	button.pressed.connect(func(): OS.shell_open(SITE_URL))
	column.add_child(button)
	return card
