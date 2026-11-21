extends Control
## Manual de sobrevivência (tecla L): o livro de tudo que dá para fabricar,
## inclusive o que ainda vai chegar ao jogo ("em breve"). Lê tudo de
## data/survival_items.json (SurvivalData), então item ou receita nova no
## catálogo aparece aqui sozinha.
##
##  ┌ MANUAL DE SOBREVIVÊNCIA ────────────────────────────────────── [✕] ┐
##  │ ERAS          │ Era 2 · Fogo e couro              │ página da receita │
##  │  1 Pedra      │ ── Fogueira ──                    │ ícone grande      │
##  │  2 Fogo e...  │ [ícone] Carvão   1 tora  ✓        │ ingredientes e    │
##  │ ESTAÇÕES      │ ── Bancada ──                     │ onde achar cada   │
##  │  Na mão ...   │ [ícone] Lança    ...  EM BREVE    │ um, usado em...   │
##  │ MATERIAIS     │                                   │ [Fabricar]        │
##  └───────────────┴───────────────────────────────────┴───────────────────┘
## Fabricar daqui manda o mesmo pedido do inventário; o servidor confere tudo.
signal craft_requested(recipe: String)

const PointerMode = preload("res://scripts/pointer_mode.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

## Estações na ordem do livro ("" = na mão).
const STATIONS := ["", "campfire", "workbench", "forge", "workshop", "chem_table"]
const SOON_COLOR := Color("#9a8f7a")
const BG := Color(0.035, 0.05, 0.06, 0.97)

var inv: Dictionary = {}
var known: Array = [] # receitas de página já aprendidas (o servidor manda no "inv")
var _stations: Dictionary = {}
var _weight := 0.0
var _capacity := float(SurvivalData.catalog().get("carry_base", 20.0))
var _section := "era:1" # "era:N", "st:<estação>" ou "materials"
var _selected := "" # "r:<receita>" ou "i:<item>"

var _panel: PanelContainer
var _nav: VBoxContainer
var _list: VBoxContainer
var _list_head: VBoxContainer
var _page: VBoxContainer

# ------------------------------------------------------------------ dados ---

static func station_name(station: String) -> String:
	if station.is_empty():
		return "Na mão"
	return str(SurvivalData.build_def(station).get("name", station))

static func recipes_where(test: Callable) -> Array:
	var out: Array = []
	for recipe in SurvivalData.recipes():
		if test.call(recipe):
			out.append(recipe)
	return out

static func recipe_by_id(id: String) -> Dictionary:
	for recipe in SurvivalData.recipes():
		if str(recipe["id"]) == id:
			return recipe
	return {}

## Item ainda não existe no jogo?
static func item_soon(id: String) -> bool:
	return bool(SurvivalData.item(id).get("soon", false))

## A receita está "em breve" (ela mesma, o resultado ou a estação ainda não existem)?
static func recipe_soon(recipe: Dictionary) -> bool:
	if bool(recipe.get("soon", false)):
		return true
	var station := str(recipe.get("station", ""))
	return not station.is_empty() and bool(SurvivalData.build_def(station).get("soon", false))

## De onde vem o item: coleta, animais, receitas e o texto "source" do catálogo.
static func origins(id: String) -> Array[String]:
	var out: Array[String] = []
	var catalog := SurvivalData.catalog()
	var resources: Dictionary = catalog.get("resources", {})
	var bonus_finds: Array[String] = [] # "às vezes" (galho da árvore, pedra do veio) vai depois
	for kind in resources:
		var rule: Dictionary = resources[kind]
		var extra: Array = rule.get("extra", [])
		var main := str(rule.get("gives", "")) == id
		var bonus := not extra.is_empty() and str(extra[0]) == id
		for pair in rule.get("extras", []):
			bonus = bonus or str(pair[0]) == id
		if not main and not bonus:
			continue
		var text := "Coleta: " + str(rule.get("name", kind))
		if rule.has("needs"):
			text += " (precisa de " + _tool_name(str(rule["needs"])) + ")"
		if main:
			out.append(text)
		else:
			bonus_finds.append(text + ", às vezes")
	out.append_array(bonus_finds)
	# Saque nas cidades: recipientes cuja tabela tem o item (mais provável primeiro).
	var loot: Dictionary = catalog.get("loot", {})
	var boxes: Array = []
	for type in loot:
		for entry in loot[type].get("table", []):
			if str(entry[0]) == id:
				boxes.append([float(entry[1]), str(loot[type].get("name", type))])
	if not boxes.is_empty():
		boxes.sort_custom(func(a, b): return a[0] > b[0])
		var names: Array[String] = []
		for b in boxes:
			names.append(str(b[1]).to_lower())
		out.append("Cidades: " + ", ".join(names) + (" (raro)" if float(boxes[0][0]) < 3.0 else ""))
	var hunters: Array[String] = []
	var animals: Dictionary = catalog.get("animals", {})
	for kind in animals:
		if (animals[kind].get("loot", {}) as Dictionary).has(id):
			hunters.append(str(animals[kind].get("name", kind)))
	if not hunters.is_empty():
		out.append("Caça: " + ", ".join(hunters))
	for recipe in SurvivalData.recipes():
		var gives: Array = recipe["gives"]
		if str(gives[0]) == id:
			out.append("Fabricação: %s (%s)" % [str(recipe["name"]), station_name(str(recipe.get("station", ""))).to_lower()])
	var source := str(SurvivalData.item(id).get("source", ""))
	if not source.is_empty():
		out.append(source)
	return out

static func _tool_name(kind: String) -> String:
	var items: Dictionary = SurvivalData.catalog().get("items", {})
	var best := ""
	for id in items:
		if str(items[id].get("tool", "")) == kind and int(items[id].get("tier", 1)) == 1:
			best = str(items[id].get("name", id))
	return best.to_lower() if not best.is_empty() else "ferramenta"

## Materiais do livro: tudo que entra em alguma receita ou construção.
static func materials() -> Array:
	var seen := {}
	for recipe in SurvivalData.recipes():
		for item in recipe["needs"]:
			seen[str(item)] = true
	var builds: Dictionary = SurvivalData.catalog().get("builds", {})
	for kind in builds:
		for item in builds[kind].get("cost", {}):
			seen[str(item)] = true
	var list := seen.keys()
	list.sort_custom(func(a, b):
		var sa := item_soon(a)
		var sb := item_soon(b)
		return (not sa and sb) if sa != sb else SurvivalData.item_name(a) < SurvivalData.item_name(b))
	return list

# -------------------------------------------------------------- montagem ---

func _ready() -> void:
	name = "SurvivalManual"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.card(20, BG))
	center.add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)
	root.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# Coluna da esquerda: índice.
	var nav_col := _column(230, 0.65)
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 4)
	var nav_scroll := _scroll_of(_nav)
	nav_col.add_child(nav_scroll)
	body.add_child(nav_col.get_parent())
	# Meio: lista de receitas.
	var list_col := _column(400, 1.4)
	_list_head = VBoxContainer.new()
	_list_head.add_theme_constant_override("separation", 2)
	list_col.add_child(_list_head)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	list_col.add_child(_scroll_of(_list))
	body.add_child(list_col.get_parent())
	# Direita: página da receita/item escolhido.
	var page_col := _column(340, 1.1)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 8)
	page_col.add_child(_scroll_of(_page))
	body.add_child(page_col.get_parent())
	var footer := _label("L ou ESC fecha   •   clique numa receita para ver a página   •   EM BREVE = ainda não está no jogo", 11, UiTheme.DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_refresh()

func _fit() -> void:
	var screen := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(1200.0, screen.x - 56.0), minf(680.0, screen.y - 56.0))

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiTheme.title("Manual de sobrevivência", 24, UiTheme.TEXT))
	titles.add_child(UiTheme.caps("Tudo que dá para fabricar  •  e o que ainda vem", 10, UiTheme.ACCENT))
	row.add_child(titles)
	var counts := _counts()
	var summary := _label("%d receitas no jogo   •   %d em breve" % [counts[0], counts[1]], 12, UiTheme.MUTED)
	summary.size_flags_horizontal = Control.SIZE_SHRINK_END
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.custom_minimum_size.x = 230
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(summary)
	var close_button := _button("✕  Fechar")
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row

static func _counts() -> Array:
	var ready := 0
	var soon := 0
	for recipe in SurvivalData.recipes():
		if recipe_soon(recipe):
			soon += 1
		else:
			ready += 1
	return [ready, soon]

func _column(min_width: float, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.inset(14))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.custom_minimum_size.x = min_width
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	return column

func _scroll_of(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll

func _label(text: String, size_px: int = 14, color: Color = UiTheme.TEXT, wrap: bool = false, weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.font(weight))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 10
	return l

func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	return UiTheme.primary(b, 13) if primary else UiTheme.secondary(b, 13)

func _tile(id: String, n: int, size_px: float) -> Control:
	var t = InventoryUI.SlotTile.new(id, n, size_px)
	t.cat = str(SurvivalData.item(id).get("cat", "material"))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

# ------------------------------------------------------------------- API ---

## Abre o livro. `focus`: "workbench"/"forge"... abre na estação; "" mantém a página.
func open(focus: String = "") -> void:
	if not focus.is_empty():
		_section = "st:" + focus
		_selected = ""
	visible = true
	PointerMode.release()
	_fit()
	_refresh()

func close() -> void:
	visible = false
	PointerMode.capture()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func set_inventory(new_inv: Dictionary, new_known: Array = []) -> void:
	inv = new_inv
	known = new_known
	if visible:
		_refresh()

## Receita de página ainda não aprendida (falta ler a página do manual)?
func locked(recipe: Dictionary) -> bool:
	return bool(recipe.get("page", false)) and not known.has(str(recipe["id"]))

func set_crafting_context(stations: Dictionary, weight: float, capacity: float) -> void:
	if _stations == stations and is_equal_approx(_weight, weight) and is_equal_approx(_capacity, capacity):
		return
	_stations = stations.duplicate()
	_weight = weight
	_capacity = capacity
	if visible:
		_refresh()

func craft_error(recipe: Dictionary) -> String:
	return SurvivalData.craft_error(recipe, inv, known, _stations, _weight, _capacity)

func has_all(recipe: Dictionary) -> bool:
	var needs: Dictionary = recipe["needs"]
	for item in needs:
		if int(inv.get(item, 0)) < int(needs[item]):
			return false
	return true

# -------------------------------------------------------------- conteúdo ---

func _refresh() -> void:
	if _nav == null:
		return
	_refresh_nav()
	_refresh_list()
	_refresh_page()

func _nav_button(text: String, section: String, note: String = "") -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	UiTheme.tab(b, _section == section, 12)
	# Contagem/"em breve" à direita, menor, sem cortar o nome.
	if not note.is_empty():
		var tag := Label.new()
		tag.text = note
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", SOON_COLOR if note.contains("breve") else UiTheme.MUTED)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tag.offset_right = -10
		b.add_child(tag)
	b.pressed.connect(func():
		_section = section
		_selected = ""
		_refresh())
	_nav.add_child(b)

func _refresh_nav() -> void:
	_clear(_nav)
	_nav.add_child(UiTheme.caps("Eras", 11, UiTheme.MUTED))
	for era in SurvivalData.catalog().get("eras", []):
		var n := int(era["id"])
		var total := recipes_where(func(r): return int(r.get("era", 1)) == n)
		var soon := 0
		for r in total:
			if recipe_soon(r):
				soon += 1
		var note := "%d" % total.size() if soon == 0 else ("em breve" if soon == total.size() else "%d + %d breve" % [total.size() - soon, soon])
		_nav_button("%d  %s" % [n, str(era["name"])], "era:%d" % n, note)
	_nav.add_child(_spacer(6))
	_nav.add_child(UiTheme.caps("Estações", 11, UiTheme.MUTED))
	for station in STATIONS:
		var soon_station: bool = not station.is_empty() and bool(SurvivalData.build_def(station).get("soon", false))
		_nav_button(station_name(station), "st:" + station, "em breve" if soon_station else "")
	_nav.add_child(_spacer(6))
	_nav.add_child(UiTheme.caps("Referência", 11, UiTheme.MUTED))
	_nav_button("Materiais e onde achar", "materials")

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

func _refresh_list() -> void:
	_clear(_list)
	_clear(_list_head)
	if _section.begins_with("era:"):
		var n := int(_section.substr(4))
		for era in SurvivalData.catalog().get("eras", []):
			if int(era["id"]) == n:
				_list_head.add_child(_label("Era %d  ·  %s" % [n, str(era["name"])], 18, UiTheme.TEXT, false, 600))
				_list_head.add_child(_label(str(era.get("desc", "")), 12, UiTheme.MUTED, true))
		# Agrupado por estação.
		for station in STATIONS:
			var group := recipes_where(func(r): return int(r.get("era", 1)) == n and str(r.get("station", "")) == station)
			if group.is_empty():
				continue
			_list.add_child(_group_title(station_name(station)))
			for recipe in group:
				_list.add_child(_recipe_row(recipe))
	elif _section.begins_with("st:"):
		var station := _section.substr(3)
		_list_head.add_child(_label(station_name(station), 18, UiTheme.TEXT, false, 600))
		if station.is_empty():
			_list_head.add_child(_label("Sem estação: dá para fazer em qualquer lugar.", 12, UiTheme.MUTED, true))
		else:
			_list.add_child(_station_card(station))
		var eras: Array = SurvivalData.catalog().get("eras", [])
		for era in eras:
			var n := int(era["id"])
			var group := recipes_where(func(r): return int(r.get("era", 1)) == n and str(r.get("station", "")) == station)
			if group.is_empty():
				continue
			_list.add_child(_group_title("Era %d · %s" % [n, str(era["name"])]))
			for recipe in group:
				_list.add_child(_recipe_row(recipe))
	else:
		_list_head.add_child(_label("Materiais e onde achar", 18, UiTheme.TEXT, false, 600))
		_list_head.add_child(_label("Tudo que entra em receitas e construções.", 12, UiTheme.MUTED, true))
		for id in materials():
			_list.add_child(_material_row(str(id)))

func _group_title(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_spacer(4))
	box.add_child(UiTheme.caps(text, 11, UiTheme.ACCENT))
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.custom_minimum_size.y = 1
	box.add_child(line)
	return box

## Linha clicável (receita ou material): ícone, nome, uma linha de detalhe e um selo à direita.
func _row(key: String, icon_id: String, icon_n: int, title: String, detail: String, badge: String, badge_color: Color, dim: bool) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.inset(8, _selected == key))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected = key
			_refresh_list()
			_refresh_page())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon = _tile(icon_id, icon_n, 42)
	icon.dim = dim
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_label := _label(title, 14, SOON_COLOR if dim else UiTheme.TEXT, false, 600)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var detail_label := _label(detail, 11, UiTheme.MUTED)
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(detail_label)
	if not badge.is_empty():
		var b := UiTheme.caps(badge, 10, badge_color)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(b)
	return card

static func needs_text(needs: Dictionary) -> String:
	var parts: Array[String] = []
	for item in needs:
		parts.append("%d %s" % [int(needs[item]), SurvivalData.item_name(str(item)).to_lower()])
	return ", ".join(parts)

func _recipe_row(recipe: Dictionary) -> Control:
	var gives: Array = recipe["gives"]
	var soon := recipe_soon(recipe)
	var badge := "Em breve" if soon else ("Falta a página" if locked(recipe) else ("Dá pra fazer" if craft_error(recipe).is_empty() else ""))
	var color := SOON_COLOR if soon or locked(recipe) else UiTheme.GOOD
	return _row("r:" + str(recipe["id"]), str(gives[0]), int(gives[1]), str(recipe["name"]), needs_text(recipe["needs"]), badge, color, soon)

func _material_row(id: String) -> Control:
	var where := origins(id)
	var soon := item_soon(id)
	var have := int(inv.get(id, 0))
	var badge := "Em breve" if soon else ("Tem %d" % have if have > 0 else "")
	return _row("i:" + id, id, 0, SurvivalData.item_name(id), where[0] if not where.is_empty() else "—", badge, SOON_COLOR if soon else UiTheme.GOOD, soon)

## Cartão da estação: o que é, quanto custa (construção, B) e se já existe.
func _station_card(station: String) -> Control:
	var def := SurvivalData.build_def(station)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.inset(10, false))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	col.add_child(_label(str(def.get("desc", "")), 12, UiTheme.TEXT, true))
	col.add_child(_label("Construa com B:  " + needs_text(def.get("cost", {})), 12, UiTheme.ACCENT, true))
	if bool(def.get("soon", false)):
		col.add_child(_label("EM BREVE: ainda não dá para construir.", 11, SOON_COLOR))
	return card

# ---------------------------------------------------------------- página ---

func _refresh_page() -> void:
	_clear(_page)
	if _selected.begins_with("r:"):
		var recipe := recipe_by_id(_selected.substr(2))
		if not recipe.is_empty():
			_recipe_page(recipe)
			return
	elif _selected.begins_with("i:"):
		_item_page(_selected.substr(2))
		return
	var hint := _label("Escolha uma receita ou um material para abrir a página.\n\nAs eras vão da pedra até a pólvora: cada uma pede uma estação nova (fogueira, bancada, forja...).", 13, UiTheme.DIM, true)
	_page.add_child(hint)

func _page_head(id: String, n: int, title: String, soon: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon = _tile(id, n, 76)
	icon.dim = soon
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	text.add_child(_label(title, 19, SOON_COLOR if soon else UiTheme.TEXT, true, 600))
	var entry := SurvivalData.item(id)
	var cat := str(entry.get("cat", "material"))
	text.add_child(_label("%s   •   %.2f kg" % [InventoryUI.CAT_NAME.get(cat, cat), float(entry.get("weight", 0))], 11, UiTheme.MUTED))
	_page.add_child(row)
	if soon:
		_page.add_child(_label("EM BREVE  ·  ainda não está no jogo", 11, SOON_COLOR))
	var desc := _describe(id)
	if not desc.is_empty():
		_page.add_child(_label(desc, 12, Color("#c9c4b4"), true))

## Mesmo texto de efeito do inventário (dano, proteção, cura...).
static func _describe(id: String) -> String:
	return InventoryUI._describe(id)

func _recipe_page(recipe: Dictionary) -> void:
	var gives: Array = recipe["gives"]
	var out_id := str(gives[0])
	var soon := recipe_soon(recipe)
	_page_head(out_id, int(gives[1]), str(recipe["name"]) + ("   ×%d" % int(gives[1]) if int(gives[1]) > 1 else ""), soon)
	_page.add_child(_group_title("Como fazer"))
	var station := str(recipe.get("station", ""))
	_page.add_child(_label(SurvivalData.station_note(station) if not station.is_empty() else "Na mão, em qualquer lugar", 12, Color("#d9925a"), true))
	if bool(recipe.get("page", false)):
		if locked(recipe):
			_page.add_child(_label("Falta a página: ache uma página do manual nas cidades e leia (Usar). Cada página ensina uma receita.", 11, SOON_COLOR, true))
		else:
			_page.add_child(_label("Página lida: você já sabe fazer.", 11, UiTheme.GOOD, true))
	var needs: Dictionary = recipe["needs"]
	for item in needs:
		_page.add_child(_ingredient(str(item), int(needs[item])))
	if not soon and not locked(recipe):
		var make := _button("Fabricar", true)
		var reason := craft_error(recipe)
		make.disabled = not reason.is_empty()
		make.tooltip_text = reason
		var rid := str(recipe["id"])
		make.pressed.connect(func(): craft_requested.emit(rid))
		_page.add_child(make)
		if not reason.is_empty():
			_page.add_child(_label(reason, 11, UiTheme.DANGER, true))
	_used_in(out_id)

## Ingrediente: ícone, quanto tem/precisa e onde achar.
func _ingredient(item: String, need: int) -> Control:
	var have := int(inv.get(item, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_tile(item, 0, 34))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name_row := HBoxContainer.new()
	name_row.add_child(_label(SurvivalData.item_name(item), 13, UiTheme.TEXT))
	var amount := _label("%d / %d" % [mini(have, 999), need], 13, UiTheme.GOOD if have >= need else UiTheme.DANGER, false, 600)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.size_flags_horizontal = Control.SIZE_SHRINK_END
	amount.custom_minimum_size.x = 60
	name_row.add_child(amount)
	text.add_child(name_row)
	var where := origins(item)
	text.add_child(_label(where[0] if not where.is_empty() else "—", 10, UiTheme.MUTED, true))
	return row

func _item_page(id: String) -> void:
	_page_head(id, int(inv.get(id, 0)), SurvivalData.item_name(id), item_soon(id))
	_page.add_child(_group_title("Onde achar"))
	var where := origins(id)
	if where.is_empty():
		_page.add_child(_label("—", 12, UiTheme.MUTED))
	for text in where:
		_page.add_child(_label("•  " + text, 12, UiTheme.TEXT, true))
	_used_in(id)

## "Usado em": receitas e construções que pedem o item (clicáveis).
func _used_in(id: String) -> void:
	var uses := recipes_where(func(r): return (r["needs"] as Dictionary).has(id))
	var builds: Dictionary = SurvivalData.catalog().get("builds", {})
	var build_uses: Array[String] = []
	for kind in builds:
		if (builds[kind].get("cost", {}) as Dictionary).has(id):
			build_uses.append(str(builds[kind].get("name", kind)))
	if uses.is_empty() and build_uses.is_empty():
		return
	_page.add_child(_group_title("Usado em"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	_page.add_child(flow)
	for recipe in uses:
		var b := _button(str(recipe["name"]))
		var key := "r:" + str(recipe["id"])
		b.pressed.connect(func():
			_selected = key
			_refresh_list()
			_refresh_page())
		flow.add_child(b)
	if not build_uses.is_empty():
		_page.add_child(_label("Construção (B): " + ", ".join(build_uses), 11, UiTheme.MUTED, true))
