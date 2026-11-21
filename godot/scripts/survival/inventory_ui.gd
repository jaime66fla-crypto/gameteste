extends Control
const PointerMode = preload("res://scripts/pointer_mode.gd")
const ItemIcons = preload("res://scripts/survival/item_icons.gd")
## Inventário da Sobrevivência (TAB), no estilo dos jogos de sobrevivência:
## fundo escurecido e um painel centralizado que sempre cabe na tela.
##
##  ┌ INVENTÁRIO ─────────────────────── CARGA [■■■□□□] 1,4 / 10 kg ───── [✕] ┐
##  │ PERSONAGEM    │ MOCHILA (grade de espaços)        │ [Fabricar|Chão/baú]   │
##  │ vida/fome/sede│ ▢▢▢▢▢▢                            │ filtros               │
##  │ EQUIPADO      │ ▢▢▢▢▢▢                            │ receitas com os       │
##  │ costas, arma  │ ─ detalhes do item escolhido ─    │ ingredientes em ícone │
##  │               │ ícone, nome, efeito, ações        │                       │
##  └───────────────┴───────────────────────────────────┴───────────────────────┘
## Clique escolhe o item; duplo clique usa/equipa (ou guarda, com o baú aberto).
## Só mostra e pede; o servidor confirma tudo (respostas "inv" e "container").
signal take_requested(container_id: String, item: String, amount: int)
signal take_all_requested(container_id: String)
signal drop_requested(item: String, amount: int)
signal use_requested(item: String)
signal craft_requested(recipe: String)
signal equip_requested(item: String)
signal unequip_requested(slot: String)
signal store_requested(container_id: String, item: String, amount: int)
signal place_requested(item: String) # tocha: fincar no chão / prender na parede

var torch_lit := false # tocha acesa na mão (muda o texto do botão)

const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CAT_ORDER := ["weapon", "ammo", "armor", "melee", "medical", "food", "drink", "gear", "fuel", "material"]
const CAT_NAME := {"weapon": "Arma", "ammo": "Munição", "armor": "Proteção", "melee": "Ferramenta / arma branca", "medical": "Cura", "food": "Comida", "drink": "Bebida", "gear": "Equipamento", "fuel": "Combustível", "material": "Material"}
const ARMOR_PART := {"head": "na cabeça", "chest": "no peito e quadril"}
## Filtros das receitas: [nome, categorias do item fabricado].
const FILTERS := [["Tudo", []], ["Ferramentas", ["melee", "weapon"]], ["Cura", ["medical"]], ["Comida", ["food", "drink"]], ["Equip.", ["gear", "armor"]], ["Material", ["material", "ammo", "fuel"]]]
const MIN_SLOTS := 24
const SLOT := 64.0
# Paleta do menu principal (scripts/ui/ui_theme.gd).
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const BG := Color(0.035, 0.05, 0.06, 0.97)
const PANEL := Color(1, 1, 1, 0.03)
const LINE := UiTheme.LINE
const TEXT := UiTheme.TEXT
const MUTED := UiTheme.MUTED
const FAINT := UiTheme.DIM
const ACCENT := UiTheme.ACCENT
const GOOD := UiTheme.GOOD
const BAD := UiTheme.DANGER

var inv: Dictionary = {}
var known: Array = [] # receitas de página aprendidas
var weight := 0.0
var cap := float(SurvivalData.catalog().get("carry_base", 20.0))
var _stations: Dictionary = {}
var back := "" # mochila equipada nas costas
var head := "" # capacete
var chest := "" # colete
var weapon := "" # arma na mão (só mostra)
var status: Dictionary = {"hp": 100.0, "hunger": 100.0, "thirst": 100.0}
var container_id := ""
var container_title := ""
var container_items: Dictionary = {}
var container_store := false # baú: dá para guardar itens nele
var _tab := 0 # 0 = recipiente (chão/baú), 1 = fabricar
var _selected := ""
var _filter := 0
var _only_ready := false

const InventoryLayout = preload("res://scripts/survival/inventory_layout.gd")
var _layout = InventoryLayout.new()
var _quantity_dialog: ConfirmationDialog
var _quantity: SpinBox
var _quantity_done: Callable
var _operation := ""
var _pending_operations := {}
var _operation_sequence := 0

var _panel: PanelContainer
var _weight_bar: ProgressBar
var _weight_label: Label
var _status_box: VBoxContainer
var _equip_box: VBoxContainer
var _grid: HFlowContainer
var _bag_title: Label
var _detail: PanelContainer
var _side: VBoxContainer
var _side_head: VBoxContainer
var _tab_craft: Button
var _tab_box: Button

# ------------------------------------------------------------ espaço (slot) ---

## Um espaço da grade: ícone do item, quantidade no canto, destaque no hover/escolhido.
class SlotTile extends Control:
	const Icons = preload("res://scripts/survival/item_icons.gd")
	signal clicked(id: String)
	signal double_clicked(id: String)
	var id := ""
	var count := 0
	var selected := false
	var dim := false # receita: falta este ingrediente
	var cat := ""
	var drag_source := ""
	var slot_index := -1
	var inventory_ui: Control
	var _drag_started := false
	var _double_activated := false
	var _hover := false

	func _get_drag_data(_at: Vector2):
		if inventory_ui == null or id.is_empty():
			return null
		_drag_started = true
		var preview := Label.new()
		preview.text = "%s ×%d" % [SurvivalData.item_name(id), count]
		set_drag_preview(preview)
		return {"ui": inventory_ui, "source": drag_source, "index": slot_index, "item": id, "n": count, "key": inventory_ui.container_id}

	func _can_drop_data(_at: Vector2, data) -> bool:
		return inventory_ui != null and inventory_ui.can_drop_item(data, drag_source, slot_index)

	func _drop_data(_at: Vector2, data) -> void:
		inventory_ui.drop_item(data, drag_source, slot_index)

	func _init(item_id: String = "", n: int = 0, size_px: float = 64.0) -> void:
		id = item_id
		count = n
		custom_minimum_size = Vector2(size_px, size_px)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			_hover = true
			queue_redraw())
		mouse_exited.connect(func():
			_hover = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not id.is_empty():
			if event.pressed:
				_drag_started = false
				_double_activated = event.double_click
			if event.pressed and event.double_click:
				double_clicked.emit(id)
			elif not event.pressed and not _drag_started and not _double_activated:
				clicked.emit(id)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.anti_aliasing = true
		# Cores do menu: vidro escuro, borda clara fina, laranja no escolhido/hover.
		box.bg_color = Color(0.94, 0.64, 0.23, 0.13) if (_hover and not id.is_empty()) else Color(1, 1, 1, 0.045)
		if id.is_empty():
			box.bg_color = Color(1, 1, 1, 0.018)
		box.border_color = Color("#f0a23b") if selected else Color(1, 1, 1, 0.10 if not id.is_empty() else 0.05)
		box.set_border_width_all(2 if selected else 1)
		if selected:
			box.shadow_color = Color(0.94, 0.64, 0.23, 0.25)
			box.shadow_size = 6
		box.draw(get_canvas_item(), r)
		if id.is_empty():
			return
		var pad := size.x * 0.14
		Icons.draw(self, id, r.grow(-pad), cat)
		if dim:
			draw_rect(r.grow(-1), Color(0.07, 0.08, 0.09, 0.55))
		if count > 1:
			var font: Font = load("res://scripts/ui/ui_theme.gd").font(700)
			var text := str(count)
			var fs := int(maxf(11.0, size.x * 0.2))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(size.x - w - 5, size.y - 5)
			draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f2efe6"))

# ---------------------------------------------------------------- estilos ---

static func _style(color: Color, radius: int = 6, border: Color = Color(0, 0, 0, 0), pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

func _label(text: String, size_px: int = 14, color: Color = TEXT, wrap: bool = false, weight: int = 400) -> Label:
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
	return UiTheme.primary(b, 13) if primary else UiTheme.secondary(b, 13)

func _section(text: String) -> Label:
	var l := UiTheme.caps(text, 11, MUTED)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _scroll() -> Array:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return [scroll, list]

func _tile(id: String, n: int, size_px: float = SLOT) -> SlotTile:
	var t := SlotTile.new(id, n, size_px)
	t.cat = str(SurvivalData.item(id).get("cat", "material"))
	if not id.is_empty():
		t.tooltip_text = "%s\n%s" % [SurvivalData.item_name(id), _describe(id)]
	return t

# -------------------------------------------------------------- montagem ---

func _ready() -> void:
	_quantity_dialog = ConfirmationDialog.new()
	_quantity_dialog.title = "Escolher quantidade"
	_quantity_dialog.min_size = Vector2i(360, 150)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.step = 1
	_quantity.allow_greater = false
	_quantity.allow_lesser = false
	_quantity_dialog.add_child(_quantity)
	_quantity_dialog.confirmed.connect(func():
		var callback := _quantity_done
		_quantity_done = Callable()
		if callback.is_valid(): callback.call(int(_quantity.value)))
	add_child(_quantity_dialog)
	var saved := ConfigFile.new()
	if saved.load("user://inventory_layout.cfg") == OK:
		_layout.slots = saved.get_value("layout", "slots", [])
	name = "Inventory"
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
	body.add_child(_build_left())
	body.add_child(_build_middle())
	body.add_child(_build_right())
	var footer := _label("TAB fecha   •   arraste para organizar / transferir   •   escolha a quantidade ao mover ou descartar", 11, FAINT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_refresh()

## Tamanho do painel: até 1200 x 660, sempre dentro da tela (com margem).
func _fit() -> void:
	var screen := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(1200.0, screen.x - 56.0), minf(660.0, screen.y - 56.0))

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	var title := UiTheme.title("Inventário", 24, TEXT)
	title.custom_minimum_size.x = 200
	titles.add_child(title)
	titles.add_child(UiTheme.caps("Sobrevivência  •  mochila e fabricação", 10, ACCENT))
	row.add_child(titles)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var carga := _label("CARGA", 11, MUTED)
	carga.size_flags_horizontal = Control.SIZE_SHRINK_END
	carga.custom_minimum_size.x = 46
	carga.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(carga)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(240, 10)
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiTheme.bar(_weight_bar, GOOD, 10)
	row.add_child(_weight_bar)
	_weight_label = _label("", 14, TEXT)
	_weight_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_weight_label.custom_minimum_size.x = 110
	_weight_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_weight_label)
	var close := _button("✕  Fechar")
	close.pressed.connect(close_inventory)
	row.add_child(close)
	return row

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

func _build_left() -> Control:
	var column := _column(230, 0.72)
	column.add_child(_section("Personagem"))
	_status_box = VBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 8)
	column.add_child(_status_box)
	column.add_child(_divider())
	column.add_child(_section("Equipado"))
	_equip_box = VBoxContainer.new()
	_equip_box.add_theme_constant_override("separation", 8)
	column.add_child(_equip_box)
	return column.get_parent()

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size.y = 1
	return line

func _build_middle() -> Control:
	var column := _column(380, 1.35)
	_bag_title = _section("Mochila")
	column.add_child(_bag_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	_detail = PanelContainer.new()
	_detail.add_theme_stylebox_override("panel", UiTheme.inset(12, true))
	_detail.custom_minimum_size.y = 128
	column.add_child(_detail)
	return column.get_parent()

func _build_right() -> Control:
	var column := _column(360, 1.15)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	_tab_craft = _button("Fabricar")
	_tab_craft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_craft.pressed.connect(func():
		_tab = 1
		_refresh())
	tabs.add_child(_tab_craft)
	_tab_box = _button("Chão / baú")
	_tab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_box.pressed.connect(func():
		_tab = 0
		_refresh())
	tabs.add_child(_tab_box)
	_side_head = VBoxContainer.new()
	_side_head.add_theme_constant_override("separation", 6)
	column.add_child(_side_head)
	var scroll := _scroll()
	column.add_child(scroll[0])
	_side = scroll[1]
	return column.get_parent()

# ------------------------------------------------------------------- API ---

func open() -> void:
	if not visible:
		UiSfx.play(&"open")
	visible = true
	PointerMode.release()
	# Mochila/baú aberto: mostra o conteúdo; senão abre direto nas receitas.
	_tab = 0 if not container_id.is_empty() else 1
	_fit()
	_refresh()

func close() -> void:
	_quantity_dialog.hide()
	_quantity_done = Callable()
	if visible:
		UiSfx.play(&"close")
	visible = false
	PointerMode.capture()

func close_inventory() -> void:
	close()

func set_inventory(new_inv: Dictionary, new_weight: float, new_cap: float, new_back: String = "", new_head: String = "", new_chest: String = "") -> void:
	inv = new_inv
	weight = new_weight
	cap = new_cap
	back = new_back
	head = new_head
	chest = new_chest
	if not inv.has(_selected):
		_selected = ""
	_refresh()

func set_status(hp: float, hunger: float, thirst: float, weapon_name: String = "") -> void:
	status = {"hp": hp, "hunger": hunger, "thirst": thirst}
	weapon = weapon_name
	if visible:
		_refresh_left()

func show_container(id: String, title: String, items: Dictionary, store: bool = false) -> void:
	container_id = id
	container_title = title
	container_items = items
	container_store = store
	_tab = 0
	_refresh()

func clear_container() -> void:
	container_id = ""
	container_items = {}
	container_store = false
	_refresh()

# ------------------------------------------------------------- conteúdo ---

func _sorted(items: Dictionary) -> Array:
	var list := items.keys()
	list.sort_custom(func(a, b):
		var ca := CAT_ORDER.find(str(SurvivalData.item(a).get("cat", "material")))
		var cb := CAT_ORDER.find(str(SurvivalData.item(b).get("cat", "material")))
		return ca < cb if ca != cb else SurvivalData.item_name(a) < SurvivalData.item_name(b))
	return list

static func _describe(id: String) -> String:
	var entry := SurvivalData.item(id)
	var parts: Array[String] = []
	var use: Dictionary = entry.get("use", {})
	for key in use:
		if key == "cure":
			continue # explicada em "desc"
		parts.append("%s %+d" % [{"hp": "Vida", "hunger": "Fome", "thirst": "Sede"}.get(key, key), int(use[key])])
	if entry.has("desc"):
		parts.append(str(entry["desc"]))
	if entry.has("melee"):
		parts.append("Dano %d" % int(entry["melee"]) + ("  •  alcance longo" if entry.has("reach") else ""))
	if entry.has("tool"):
		parts.append(str({"wood": "Corta árvores", "stone": "Quebra rochas", "cut": "Corta mais capim", "scrap": "Desmonta carros velhos"}.get(str(entry["tool"]), "Ferramenta")))
	if entry.has("carry"):
		parts.append("+%d kg de carga nas costas" % int(entry["carry"]))
	if entry.has("armor"):
		parts.append("−%d%% de dano %s" % [roundi(float(entry["armor"]) * 100), ARMOR_PART.get(str(entry.get("slot", "")), "")])
	if entry.has("ammo"):
		parts.append("Usa " + SurvivalData.item_name(str(entry["ammo"])))
	if entry.has("fuel"):
		parts.append("+%d L no tanque" % int(entry["fuel"]))
	return "  •  ".join(parts)

func _clear(box: Node) -> void:
	for child in box.get_children():
		child.queue_free()

func _refresh() -> void:
	if _grid == null:
		return
	_weight_bar.max_value = cap
	_weight_bar.value = minf(weight, cap)
	var ratio := weight / maxf(cap, 0.1)
	var fill_color := GOOD if ratio < 0.75 else (Color("#d6a23e") if ratio < 0.95 else BAD)
	_weight_bar.add_theme_stylebox_override("fill", UiTheme.box(fill_color, Color.TRANSPARENT, 0, 3))
	_weight_label.text = "%.1f / %.0f kg" % [weight, cap]
	_refresh_left()
	_refresh_grid()
	_refresh_detail()
	_refresh_side()

## Algum item do catálogo tem `key` (com o valor `value`, se não for vazio)?
static func _catalog_has(key: String, value: String) -> bool:
	var items: Dictionary = SurvivalData.catalog().get("items", {})
	for id in items:
		if items[id].has(key) and (value.is_empty() or str(items[id][key]) == value):
			return true
	return false

func _refresh_left() -> void:
	_clear(_status_box)
	_clear(_equip_box)
	for spec in [["Vida", "hp", Color("#c9574b")], ["Fome", "hunger", Color("#d1a043")], ["Sede", "thirst", Color("#4b9fd3")]]:
		var value := float(status.get(spec[1], 100))
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 3)
		var line := HBoxContainer.new()
		line.add_child(_label(spec[0], 12, MUTED))
		var number := _label("%d" % int(value), 12, TEXT if value > 25 else BAD)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(number)
		block.add_child(line)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		bar.value = value
		UiTheme.bar(bar, spec[2], 6)
		block.add_child(bar)
		_status_box.add_child(block)
	if not head.is_empty() or _catalog_has("slot", "head"):
		_equip_box.add_child(_slot_row("Cabeça", "head", head, "Sem capacete"))
	if not chest.is_empty() or _catalog_has("slot", "chest"):
		_equip_box.add_child(_slot_row("Peito", "chest", chest, "Sem colete"))
	_equip_box.add_child(_slot_row("Costas", "back", back, "Só bolsos (%d kg)" % int(SurvivalData.catalog().get("carry_base", 10))))
	var best: Array = SurvivalData.best_melee(inv)
	var tool_text := "Soco  ·  %d" % int(best[1]) if str(best[0]).is_empty() else "%s  ·  %d" % [SurvivalData.item_name(str(best[0])), int(best[1])]
	_equip_box.add_child(_info_row("Melhor golpe (Q)  ·  dano",str(best[0]), tool_text))
	if not weapon.is_empty() or _catalog_has("weapon", ""):
		_equip_box.add_child(_info_row("Arma na mão", "", weapon if not weapon.is_empty() else "Nenhuma"))

## Linha de um espaço do corpo: quadrado com o item, nome/efeito e "Tirar".
func _slot_row(title: String, slot: String, item_id: String, empty_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_tile(item_id, 1, 48))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(_label(title.to_upper(), 10, FAINT))
	if item_id.is_empty():
		text.add_child(_label(empty_text, 13, MUTED))
		return row
	var entry := SurvivalData.item(item_id)
	text.add_child(_label(SurvivalData.item_name(item_id), 13, TEXT))
	var effect := "+%d kg de carga" % int(entry.get("carry", 0)) if entry.has("carry") else "−%d%% de dano" % roundi(float(entry.get("armor", 0)) * 100)
	text.add_child(_label(effect, 11, GOOD))
	var off := _button("Tirar")
	off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	off.pressed.connect(func(): unequip_requested.emit(slot))
	row.add_child(off)
	return row

func _info_row(title: String, item_id: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_tile(item_id, 1, 48))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(_label(title.to_upper(), 10, FAINT))
	text.add_child(_label(value, 13, TEXT))
	return row

func _save_layout() -> void:
	var saved := ConfigFile.new()
	saved.set_value("layout", "slots", _layout.slots)
	saved.save("user://inventory_layout.cfg")

func _refresh_grid() -> void:
	_clear(_grid)
	_layout.sync(inv)
	var count := 0
	for id in inv:
		count += int(inv[id])
	_bag_title.text = "MOCHILA   •   %d itens" % count
	for i in _layout.slots.size():
		var slot: Dictionary = _layout.slots[i]
		var id := str(slot.get("item", ""))
		var tile := _tile(id, int(slot.get("n", 0)))
		tile.inventory_ui = self
		tile.drag_source = "inventory"
		tile.slot_index = i
		tile.selected = id == _selected and not id.is_empty()
		tile.clicked.connect(func(item):
			_selected = item if _selected != item else ""
			for child in _grid.get_children():
				if child is SlotTile:
					child.selected = child.id == _selected and not child.id.is_empty()
					child.queue_redraw()
			_refresh_detail())
		tile.double_clicked.connect(_primary)
		_grid.add_child(tile)

func _ask_amount(title: String, maximum: int, callback: Callable) -> void:
	if maximum < 1:
		return
	_quantity_done = callback
	_quantity_dialog.dialog_text = title + "\nQuantidade (1 a %d):" % maximum
	_quantity.max_value = maximum
	_quantity.value = maximum
	_quantity_dialog.popup_centered()
	_quantity.get_line_edit().grab_focus()
	_quantity.get_line_edit().select_all()

func _request_amount(action: String, item: String, maximum: int, source: int = -1, target: int = -1) -> void:
	var key := container_id
	_ask_amount({"store": "Guardar", "take": "Pegar", "drop": "Descartar no chão"}[action] + " " + SurvivalData.item_name(item), maximum, func(n: int):
		if action != "drop" and key != container_id:
			return
		_operation_sequence += 1
		_operation = str(_operation_sequence)
		if _pending_operations.size() >= 32:
			_pending_operations.erase(_pending_operations.keys()[0])
		_pending_operations[_operation] = {"item": item, "source": source, "target": target, "n": n}
		if action == "drop":
			drop_requested.emit(item, n)
		elif key == container_id:
			if action == "store": store_requested.emit(key, item, n)
			else: take_requested.emit(key, item, n))

func operation_token() -> String:
	return _operation

func confirm_operation(token: String, new_inv: Dictionary) -> void:
	if not _pending_operations.has(token):
		return
	var op: Dictionary = _pending_operations[token]
	_pending_operations.erase(token)
	var item := str(op["item"])
	var delta := int(new_inv.get(item, 0)) - int(inv.get(item, 0))
	var source := int(op["source"])
	var target := int(op["target"])
	if delta < 0 and source >= 0 and source < _layout.slots.size():
		var slot: Dictionary = _layout.slots[source]
		if slot.get("item") == item:
			slot["n"] = maxi(0, int(slot["n"]) - mini(-delta, int(op["n"])))
			if slot["n"] == 0: _layout.slots[source] = {}
	elif delta > 0 and target >= 0 and target < _layout.slots.size():
		var slot: Dictionary = _layout.slots[target]
		if not slot.is_empty() and slot.get("item") != item:
			var empty: int = _layout.slots.find({})
			if empty < 0:
				empty = _layout.slots.size()
				_layout.slots.append({})
			_layout.slots[empty] = slot
			slot = {}
		_layout.slots[target] = {"item": item, "n": int(slot.get("n", 0)) + mini(delta, int(op["n"]))}
	_layout.sync(new_inv)
	_save_layout()

func can_drop_item(data, destination: String, index: int) -> bool:
	if not data is Dictionary or data.get("ui") != self or not data.has("item"):
		return false
	if data.get("source") == "container":
		return destination == "inventory" and data.get("key") == container_id
	if data.get("source") != "inventory":
		return false
	return (destination == "inventory" and index != int(data.get("index", -1))) or destination == "drop" or (destination == "container" and container_store and not container_id.is_empty())

func drop_item(data: Dictionary, destination: String, index: int) -> void:
	if not can_drop_item(data, destination, index):
		return
	var item := str(data["item"])
	if data["source"] == "container":
		_request_amount("take", item, mini(int(data["n"]), int(container_items.get(item, 0))), -1, index)
	elif destination == "inventory":
		var source := int(data["index"])
		if source < 0 or source >= _layout.slots.size() or _layout.slots[source].get("item") != item:
			return
		var maximum := int(_layout.slots[source].get("n", 0))
		var target: Dictionary = _layout.slots[index]
		if not target.is_empty() and target.get("item") != item:
			_layout.move_stack(source, index, maximum)
			_save_layout()
			_refresh_grid()
		else:
			_ask_amount("Mover " + SurvivalData.item_name(item), maximum, func(n: int):
				if _layout.slots[source].get("item") == item and _layout.move_stack(source, index, n):
					_save_layout()
					_refresh_grid())
	else:
		_request_amount("drop" if destination == "drop" else "store", item, mini(int(data["n"]), int(inv.get(item, 0))), int(data["index"]))

## Ação do duplo clique: guardar no baú aberto; senão usar, equipar ou vestir.
func _primary(id: String) -> void:
	var entry := SurvivalData.item(id)
	if container_store and not container_id.is_empty():
		_request_amount("store", id, int(inv.get(id, 0)))
	elif entry.has("use") or entry.has("repair") or id == "torch":
		use_requested.emit(id)
	elif str(entry.get("slot", "")) in ["back", "head", "chest"]:
		equip_requested.emit(id)

func _refresh_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()
	if _selected.is_empty() or not inv.has(_selected):
		var hint := _label("Escolha um item para ver os detalhes.\nDuplo clique usa, equipa ou guarda no baú.", 13, FAINT, true)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_detail.add_child(hint)
		return
	var id := _selected
	var entry := SurvivalData.item(id)
	var n := int(inv[id])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_detail.add_child(row)
	row.add_child(_tile(id, n, 84))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	text.add_child(_label(SurvivalData.item_name(id) + ("   ×%d" % n if n > 1 else ""), 17, TEXT))
	var cat := str(entry.get("cat", "material"))
	text.add_child(_label("%s   •   %.2f kg cada   •   %.2f kg no total" % [CAT_NAME.get(cat, cat), float(entry.get("weight", 0)), float(entry.get("weight", 0)) * n], 11, MUTED))
	var desc := _describe(id)
	if not desc.is_empty():
		text.add_child(_label(desc, 12, GOOD if entry.has("use") and int(entry["use"].get("hp", 0)) >= 0 else Color("#c9c4b4"), true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	text.add_child(actions)
	if container_store and not container_id.is_empty():
		var store := _button("Guardar…", true)
		store.pressed.connect(func(): _request_amount("store", id, int(inv.get(id, 0))))
		actions.add_child(store)
	if entry.has("use") or entry.has("repair"):
		var use := _button("Usar" if cat != "food" else "Comer", not container_store)
		use.pressed.connect(func(): use_requested.emit(id))
		actions.add_child(use)
	if id == "torch":
		# Tocha: acende na mão (luz que anda com você) ou finca/prende para iluminar o lugar.
		var hold := _button("Apagar a da mão" if torch_lit else "Acender na mão", not container_store)
		hold.pressed.connect(func(): use_requested.emit(id))
		actions.add_child(hold)
		var place := _button("Fincar / prender na parede")
		place.pressed.connect(func(): place_requested.emit(id))
		actions.add_child(place)
	if str(entry.get("slot", "")) == "back":
		var eq := _button("Equipar nas costas", true)
		eq.pressed.connect(func(): equip_requested.emit(id))
		actions.add_child(eq)
	elif str(entry.get("slot", "")) in ["head", "chest"]:
		var wear := _button("Vestir", true)
		wear.pressed.connect(func(): equip_requested.emit(id))
		actions.add_child(wear)
	var drop := _button("Descartar…")
	drop.pressed.connect(func(): _request_amount("drop", id, n))
	actions.add_child(drop)

# ----------------------------------------------------------- lado direito ---

func _refresh_side() -> void:
	_clear(_side)
	_clear(_side_head)
	for pair in [[_tab_craft, 1], [_tab_box, 0]]:
		var on: bool = _tab == pair[1]
		var b: Button = pair[0]
		UiTheme.tab(b, on, 13)
	_tab_box.text = ("Porta-malas" if container_id.begins_with("trunk:") else "Baú") if container_store else ("Chão / mochila" if container_id.is_empty() else container_title.get_slice(" ", 0))
	if _tab == 0:
		_refresh_container()
	else:
		_refresh_recipes()

func _refresh_container() -> void:
	var destination := _tile("", 0)
	destination.custom_minimum_size = Vector2(200, 48)
	destination.inventory_ui = self
	destination.drag_source = "container" if container_store else "drop"
	var drop_hint := _label("Arraste aqui para guardar" if container_store else "Arraste aqui para descartar", 12, MUTED)
	drop_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	destination.add_child(drop_hint)
	_side.add_child(destination)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 6)
	_side_head.add_child(head_row)
	head_row.add_child(_label(container_title if not container_id.is_empty() else "Nada aberto", 15, TEXT))
	if not container_id.is_empty() and not container_items.is_empty():
		var all := _button("Pegar tudo", true)
		all.pressed.connect(func(): take_all_requested.emit(container_id))
		head_row.add_child(all)
	if container_id.is_empty():
		var hint := _label("Chegue perto de uma mochila no chão, carcaça ou baú e aperte E para abrir.", 13, FAINT, true)
		_side.add_child(hint)
		return
	if container_items.is_empty():
		_side.add_child(_label("Vazio.", 13, FAINT))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_side.add_child(grid)
	for id in _sorted(container_items):
		var tile := _tile(id, int(container_items[id]))
		tile.tooltip_text += "\nClique ou arraste para pegar uma quantidade"
		tile.inventory_ui = self
		tile.drag_source = "container"
		tile.clicked.connect(func(item): _request_amount("take", item, int(container_items.get(item, 0))))
		grid.add_child(tile)
	if container_store:
		_side.add_child(_label("Arraste para guardar ou escolha um item e use Guardar.", 11, FAINT, true))

func set_crafting_context(stations: Dictionary, carried_weight: float, limit: float) -> void:
	if _stations == stations and is_equal_approx(weight, carried_weight) and is_equal_approx(cap, limit):
		return
	_stations = stations.duplicate()
	weight = carried_weight
	cap = limit
	if visible:
		_refresh_side()

func craft_error(recipe: Dictionary) -> String:
	return SurvivalData.craft_error(recipe, inv, known, _stations, weight, cap)

func _refresh_recipes() -> void:
	# Filtros por categoria do que se fabrica + "só o que dá para fazer".
	# Linhas fixas (HFlow guardava a altura de quando a janela era estreita e o painel passava da tela).
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 4)
	_side_head.add_child(chips)
	for index in FILTERS.size():
		var chip := Button.new()
		chip.text = FILTERS[index][0]
		chip.focus_mode = Control.FOCUS_NONE

		var on := index == _filter
		UiTheme.tab(chip, on, 10)
		var i: int = index
		chip.pressed.connect(func():
			_filter = i
			_refresh_side())
		chips.add_child(chip)
	var only_box := CheckBox.new()
	only_box.text = "Só o que dá"
	only_box.focus_mode = Control.FOCUS_NONE
	only_box.button_pressed = _only_ready
	only_box.add_theme_font_size_override("font_size", 11)
	only_box.add_theme_color_override("font_color", MUTED)
	only_box.toggled.connect(func(on):
		_only_ready = on
		_refresh_side())
	_side_head.add_child(only_box)
	var shown := 0
	for recipe in SurvivalData.recipes():
		if bool(recipe.get("soon", false)):
			continue # ainda não existe: só no Manual (L)
		if bool(recipe.get("page", false)) and not known.has(str(recipe["id"])):
			continue # falta ler a página do manual
		var gives: Array = recipe["gives"]
		var cat := str(SurvivalData.item(str(gives[0])).get("cat", "material"))
		var cats: Array = FILTERS[_filter][1]
		if not cats.is_empty() and not cats.has(cat):
			continue
		var have_all := craft_error(recipe).is_empty()
		if _only_ready and not have_all:
			continue
		_side.add_child(_recipe_card(recipe, have_all))
		shown += 1
	if shown == 0:
		_side.add_child(_label("Nenhuma receita aqui ainda. Junte mais material.", 13, FAINT, true))

## Receita: ícone do resultado, nome, ingredientes em ícone (verde tem, vermelho falta), Fabricar.
func _recipe_card(recipe: Dictionary, have_all: bool) -> Control:
	var gives: Array = recipe["gives"]
	var out_id := str(gives[0])
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.inset(8, have_all))
	card.tooltip_text = "%s\n%s" % [str(recipe["name"]), _describe(out_id)]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var icon := _tile(out_id, int(gives[1]), 46)
	icon.dim = not have_all
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	text.add_child(_label(str(recipe["name"]), 14, TEXT if have_all else Color("#b9b5aa")))
	var needs_row := HBoxContainer.new()
	needs_row.add_theme_constant_override("separation", 8)
	text.add_child(needs_row)
	var needs: Dictionary = recipe["needs"]
	for item in needs:
		var have := int(inv.get(item, 0))
		var need := int(needs[item])
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		chip.tooltip_text = SurvivalData.item_name(str(item))
		var small := _tile(str(item), 0, 24)
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(small)
		var amount := Label.new()
		amount.text = "%d/%d" % [mini(have, 99), need]
		amount.add_theme_font_size_override("font_size", 11)
		amount.add_theme_color_override("font_color", GOOD if have >= need else BAD)
		chip.add_child(amount)
		needs_row.add_child(chip)
	var station_note := SurvivalData.station_note(str(recipe.get("station", "")))
	if not station_note.is_empty():
		text.add_child(_label(station_note, 10, Color("#d9925a")))
	var make := _button("Fabricar", true)
	make.disabled = not have_all
	make.tooltip_text = craft_error(recipe)
	make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rid := str(recipe["id"])
	make.pressed.connect(func(): craft_requested.emit(rid))
	row.add_child(make)
	return card
