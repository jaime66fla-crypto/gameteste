extends PanelContainer
## Painel do Cofre (tela Cofre do menu): tudo o que a conta tem da loja, menos
## os personagens (esses ficam no carrossel à esquerda). Ocupa o lado direito
## da tela; as vitrines viram uma grade com quantas colunas couberem. Roupas do 01 com
## Vestir/Tirar e skins de armas com Equipar/Tirar, cada item numa vitrine com
## prévia 3D. O que falta comprar fica na Loja (scripts/loja/store_screen.gd).
## As escolhas ficam salvas (character_registry.gd) e o jogador local entra
## assim; a carta do 01 ao lado troca de roupa na hora via outfit_changed.
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Registry = preload("res://scripts/characters/character_registry.gd")
const StoreCatalog = preload("res://scripts/loja/store_catalog.gd")
const StorePreview = preload("res://scripts/loja/store_preview.gd")
const CASE_SIZE := Vector2(104, 104)
const LIST_HEIGHT := 240.0 # mínimo: a lista cresce até a altura da carta ao lado
## Largura mínima de uma vitrine na grade (define quantas colunas cabem).
const CASE_MIN_WIDTH := 260.0

signal outfit_changed(pieces: PackedStringArray)
signal store_requested
## Skin de arma equipada/tirada (a prévia armada do personagem acompanha).
signal weapon_skin_changed(weapon: String)

var worn := PackedStringArray()
var _cases := {} # id -> {"panel", "state", "button"}
var _feedback: Label
var _balance: Label
var _grids: Array[GridContainer] = []

func _ready() -> void:
	custom_minimum_size.x = 340
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", UiTheme.card(16))
	worn = Registry.load_outfit()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(UiTheme.caps("SEU COFRE", 12, UiTheme.ACCENT))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	var title := UiTheme.title("Roupas e skins", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_balance = UiTheme.label("", 14, UiTheme.ACCENT, 700)
	_balance.name = "BrasasBalance"
	_balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_balance)
	var scroll := ScrollContainer.new()
	scroll.name = "VaultList"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = LIST_HEIGHT
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	scroll.resized.connect(_fit_columns.bind(scroll))
	_section(list, "skins_personagens", "ROUPAS DO 01", "")
	_section(list, "skins_armas", "SKINS DE ARMAS", "Nenhuma skin de arma ainda. Compre na Loja com Brasas.")
	var store := Button.new()
	store.name = "OpenStore"
	store.text = "Ir para a Loja"
	store.custom_minimum_size.y = 38
	UiTheme.secondary(store, 14)
	store.pressed.connect(func(): store_requested.emit())
	column.add_child(store)
	_feedback = UiTheme.label("", 13, UiTheme.DANGER)
	_feedback.name = "VaultFeedback"
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.x = 300
	column.add_child(_feedback)
	_refresh()
	_fit_columns.call_deferred(scroll)

func _section(list: VBoxContainer, group: String, title: String, empty_text: String) -> void:
	list.add_child(UiTheme.caps(title, 11, UiTheme.MUTED))
	var owned := StoreCatalog.items_in(group).filter(func(entry): return StoreCatalog.is_owned(str(entry["id"])))
	if owned.is_empty() and not empty_text.is_empty():
		var empty := UiTheme.label(empty_text, 13, UiTheme.DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 290
		list.add_child(empty)
	var grid := GridContainer.new()
	grid.name = "Grade_" + group
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)
	_grids.append(grid)
	for entry in owned:
		grid.add_child(_build_case(entry))

## Quantas vitrines cabem lado a lado na largura do cofre.
func _fit_columns(scroll: ScrollContainer) -> void:
	var columns := maxi(1, int((scroll.size.x - 12.0) / CASE_MIN_WIDTH))
	for grid in _grids:
		grid.columns = columns

func _build_case(entry: Dictionary) -> Control:
	var id := str(entry["id"])
	var panel := PanelContainer.new()
	panel.name = "Vitrine_" + id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(StorePreview.new(id, CASE_SIZE))
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	info.add_child(UiTheme.caps(str(entry.get("tipo", "")).to_upper(), 11, UiTheme.MUTED))
	info.add_child(UiTheme.label(str(entry.get("nome", id)), 15, UiTheme.TEXT, 600))
	var state := UiTheme.label("", 12, UiTheme.GOOD, 600)
	info.add_child(state)
	var button := Button.new()
	button.name = "Vestir_" + id
	button.custom_minimum_size = Vector2(120, 34)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(_on_case_pressed.bind(id))
	info.add_child(button)
	_cases[id] = {"panel": panel, "state": state, "button": button}
	return panel

func _on_case_pressed(id: String) -> void:
	if StoreCatalog.group_of(id) == "skins_armas":
		var weapon := StoreCatalog.weapon(id)
		var equipped := Registry.weapon_skin(weapon) == id
		if Registry.set_weapon_skin(weapon, "" if equipped else id) != OK:
			_say("Não foi possível salvar a skin.")
			return
		_feedback.text = ""
		_refresh()
		weapon_skin_changed.emit(weapon)
		return
	_toggle(id)

func _say(text: String) -> void:
	_feedback.text = text

func _toggle(id: String) -> void:
	var next := worn.duplicate()
	if id in next:
		next.remove_at(next.find(id))
	else:
		# Um item por peça; calça e bermuda ocupam o mesmo lugar.
		var piece := StoreCatalog.piece(id)
		var legs := ["calca", "bermuda"]
		for other in worn:
			var other_piece := StoreCatalog.piece(other)
			if other_piece == piece or (piece in legs and other_piece in legs):
				next.remove_at(next.find(other))
		next.append(id)
	if Registry.save_outfit(next) != OK:
		_say("Não foi possível salvar as roupas. A escolha anterior foi mantida.")
		return
	_feedback.text = ""
	worn = next
	_refresh()
	outfit_changed.emit(worn)

## Item em uso: roupa vestida ou skin equipada na arma dela.
func _in_use(id: String) -> bool:
	if StoreCatalog.group_of(id) == "skins_armas":
		return Registry.weapon_skin(StoreCatalog.weapon(id)) == id
	return id in worn

func _refresh() -> void:
	var money := StoreCatalog.currency()
	_balance.text = ("%d %s" % [StoreCatalog.balance(), money]).to_upper() if StoreCatalog.logged_in() else "Entre na conta para ganhar %s" % money
	for id in _cases:
		var on := _in_use(id)
		var weapon := StoreCatalog.group_of(id) == "skins_armas"
		var parts: Dictionary = _cases[id]
		var style := UiTheme.box(Color(0.02, 0.035, 0.04, 0.9), UiTheme.ACCENT if on else UiTheme.LINE, 2 if on else 1, 8)
		style.content_margin_left = 8
		style.content_margin_right = 10
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		(parts["panel"] as PanelContainer).add_theme_stylebox_override("panel", style)
		var state := parts["state"] as Label
		state.text = ("✓ EQUIPADA" if weapon else "✓ VESTIDO") if on else "No cofre"
		state.add_theme_color_override("font_color", UiTheme.GOOD if on else UiTheme.DIM)
		var button := parts["button"] as Button
		button.text = "Tirar" if on else ("Equipar" if weapon else "Vestir")
		if on:
			UiTheme.secondary(button, 13)
		else:
			UiTheme.primary(button, 13)
