extends Control
## Inventário da Sobrevivência (TAB). Cobre a tela com um fundo escurecido e
## um painel centralizado que sempre cabe na tela (o conteúdo rola por dentro).
##
##  ┌ INVENTÁRIO ──────────── carga [■■■■□□] 9,4 / 34 kg ─────────── [X] ┐
##  │ EQUIPADO     │ INVENTÁRIO (por categoria)  │ [Chão/recipiente|Fabricar]│
##  │ costas/arma  │ cartões de item com ações   │ lista + Pegar tudo        │
##  │ status       │                             │ receitas                  │
##  └──────────────┴─────────────────────────────┴───────────────────────────┘
## Só mostra e pede; o servidor confirma tudo (respostas "inv" e "container").
signal take_requested(container_id: String, item: String, all: bool)
signal take_all_requested(container_id: String)
signal drop_requested(item: String, all: bool)
signal use_requested(item: String)
signal craft_requested(recipe: String)
signal equip_requested(item: String)
signal unequip_requested()

const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CAT_ORDER := ["weapon", "ammo", "melee", "medical", "food", "drink", "gear", "fuel", "material"]
const CAT_NAME := {"weapon": "Armas", "ammo": "Munição", "melee": "Armas brancas e ferramentas", "medical": "Cura", "food": "Comida", "drink": "Bebida", "gear": "Equipamento", "fuel": "Combustível", "material": "Materiais"}
const CAT_COLOR := {"weapon": Color("#d0574a"), "ammo": Color("#d6a23e"), "melee": Color("#b9824f"), "medical": Color("#e05a6a"), "food": Color("#8fbf5a"), "drink": Color("#4aa3d8"), "gear": Color("#7f9a5b"), "fuel": Color("#e08a2e"), "material": Color("#9a9389")}
const CAT_GLYPH := {"weapon": "A", "ammo": "M", "melee": "F", "medical": "+", "food": "C", "drink": "B", "gear": "E", "fuel": "G", "material": "•"}
# Paleta
const BG := Color("#14181c")
const PANEL := Color("#1c2228")
const CARD := Color("#232a31")
const CARD_HOVER := Color("#2b343c")
const LINE := Color("#323b44")
const TEXT := Color("#e8e6df")
const MUTED := Color("#8e979e")
const ACCENT := Color("#d9b44a")

var inv: Dictionary = {}
var weight := 0.0
var cap := 10.0
var back := "" # mochila equipada nas costas
var weapon := "" # arma na mão (só mostra)
var status: Dictionary = {"hp": 100.0, "hunger": 100.0, "thirst": 100.0}
var container_id := ""
var container_title := ""
var container_items: Dictionary = {}
var _tab := 0 # 0 = recipiente, 1 = fabricar

var _panel: PanelContainer
var _weight_bar: ProgressBar
var _weight_label: Label
var _equip_box: VBoxContainer
var _status_box: VBoxContainer
var _items: VBoxContainer
var _items_title: Label
var _side: VBoxContainer
var _side_title: Label
var _tab_box: Button
var _tab_craft: Button
var _take_all: Button

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

func _label(text: String, size_px: int = 14, color: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
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
	b.add_theme_font_size_override("font_size", 13)
	var base := Color("#3a4652") if not primary else ACCENT.darkened(0.15)
	b.add_theme_stylebox_override("normal", _style(base, 4, Color(0, 0, 0, 0), 8))
	b.add_theme_stylebox_override("hover", _style(base.lightened(0.15), 4, Color(0, 0, 0, 0), 8))
	b.add_theme_stylebox_override("pressed", _style(base.darkened(0.2), 4, Color(0, 0, 0, 0), 8))
	b.add_theme_stylebox_override("disabled", _style(Color("#262d33"), 4, Color(0, 0, 0, 0), 8))
	b.add_theme_color_override("font_color", Color("#101316") if primary else TEXT)
	b.add_theme_color_override("font_disabled_color", Color("#5b636a"))
	return b

func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 12, MUTED)
	l.add_theme_constant_override("line_spacing", 0)
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

# -------------------------------------------------------------- montagem ---

func _ready() -> void:
	name = "Inventory"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# O painel fica num MarginContainer: nunca passa das bordas da tela.
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
	_panel.add_theme_stylebox_override("panel", _style(BG, 10, LINE, 16))
	center.add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_panel.add_child(root)
	root.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_middle())
	body.add_child(_build_right())
	var footer := _label("TAB fecha   •   passe o mouse num item para ver detalhes   •   o servidor confirma cada ação", 12, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_refresh()

## Tamanho do painel: até 1180 x 640, sempre dentro da tela (com margem).
func _fit() -> void:
	var screen := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2(minf(1180.0, screen.x - 56.0), minf(640.0, screen.y - 56.0))

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var title := _label("INVENTÁRIO", 22, ACCENT)
	title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	title.custom_minimum_size.x = 170
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var carga := _label("CARGA", 12, MUTED)
	carga.size_flags_horizontal = Control.SIZE_SHRINK_END
	carga.custom_minimum_size.x = 50
	row.add_child(carga)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(220, 12)
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_weight_bar.add_theme_stylebox_override("background", _style(Color("#0c0f12"), 6, LINE, 0))
	row.add_child(_weight_bar)
	_weight_label = _label("", 14, TEXT)
	_weight_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_weight_label.custom_minimum_size.x = 120
	row.add_child(_weight_label)
	var close := _button("✕  Fechar")
	close.pressed.connect(close_inventory)
	row.add_child(close)
	return row

func _column(min_width: float, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(PANEL, 8, LINE, 12))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	panel.custom_minimum_size.x = min_width
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column

func _build_left() -> Control:
	var column := _column(220, 0.8)
	column.add_child(_section("Equipado"))
	_equip_box = VBoxContainer.new()
	_equip_box.add_theme_constant_override("separation", 6)
	column.add_child(_equip_box)
	column.add_child(HSeparator.new())
	column.add_child(_section("Estado"))
	_status_box = VBoxContainer.new()
	_status_box.add_theme_constant_override("separation", 6)
	column.add_child(_status_box)
	return column.get_parent()

func _build_middle() -> Control:
	var column := _column(360, 1.4)
	_items_title = _section("Inventário")
	column.add_child(_items_title)
	var scroll := _scroll()
	column.add_child(scroll[0])
	_items = scroll[1]
	return column.get_parent()

func _build_right() -> Control:
	var column := _column(300, 1.1)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	_tab_box = _button("Chão / recipiente")
	_tab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_box.pressed.connect(func():
		_tab = 0
		_refresh())
	tabs.add_child(_tab_box)
	_tab_craft = _button("Fabricar")
	_tab_craft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_craft.pressed.connect(func():
		_tab = 1
		_refresh())
	tabs.add_child(_tab_craft)
	var head := HBoxContainer.new()
	column.add_child(head)
	_side_title = _label("", 15, TEXT)
	head.add_child(_side_title)
	_take_all = _button("Pegar tudo", true)
	_take_all.pressed.connect(func(): take_all_requested.emit(container_id))
	head.add_child(_take_all)
	var scroll := _scroll()
	column.add_child(scroll[0])
	_side = scroll[1]
	return column.get_parent()

# ------------------------------------------------------------------- API ---

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not container_id.is_empty():
		_tab = 0
	_fit()
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func close_inventory() -> void:
	close()

func set_inventory(new_inv: Dictionary, new_weight: float, new_cap: float, new_back: String = "") -> void:
	inv = new_inv
	weight = new_weight
	cap = new_cap
	back = new_back
	_refresh()

func set_status(hp: float, hunger: float, thirst: float, weapon_name: String = "") -> void:
	status = {"hp": hp, "hunger": hunger, "thirst": thirst}
	weapon = weapon_name
	if visible:
		_refresh_left()

func show_container(id: String, title: String, items: Dictionary) -> void:
	container_id = id
	container_title = title
	container_items = items
	_tab = 0
	_refresh()

func clear_container() -> void:
	container_id = ""
	container_items = {}
	_refresh()

# ------------------------------------------------------------- conteúdo ---

func _sorted(items: Dictionary) -> Array:
	var list := items.keys()
	list.sort_custom(func(a, b):
		var ca := CAT_ORDER.find(str(SurvivalData.item(a).get("cat", "material")))
		var cb := CAT_ORDER.find(str(SurvivalData.item(b).get("cat", "material")))
		return ca < cb if ca != cb else SurvivalData.item_name(a) < SurvivalData.item_name(b))
	return list

func _describe(id: String) -> String:
	var entry := SurvivalData.item(id)
	var parts: Array[String] = []
	var use: Dictionary = entry.get("use", {})
	for key in use:
		parts.append("%s %+d" % [{"hp": "Vida", "hunger": "Fome", "thirst": "Sede"}.get(key, key), int(use[key])])
	if entry.has("melee"):
		parts.append("Dano %d" % int(entry["melee"]))
	if entry.has("tool"):
		parts.append("Rende mais em " + ("árvores" if str(entry["tool"]) == "wood" else "pedras e carros"))
	if entry.has("carry"):
		parts.append("+%d kg de carga (equipar nas costas)" % int(entry["carry"]))
	if entry.has("ammo"):
		parts.append("Usa " + SurvivalData.item_name(str(entry["ammo"])))
	if entry.has("fuel"):
		parts.append("+%d%% no tanque (T perto de um carro)" % int(entry["fuel"]))
	return "  •  ".join(parts)

## Ícone: quadrado na cor da categoria com uma letra.
func _icon(cat: String) -> Control:
	var icon := PanelContainer.new()
	icon.custom_minimum_size = Vector2(34, 34)
	icon.add_theme_stylebox_override("panel", _style(CAT_COLOR.get(cat, MUTED).darkened(0.35), 6, CAT_COLOR.get(cat, MUTED), 0))
	var glyph := Label.new()
	glyph.text = str(CAT_GLYPH.get(cat, "•"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 16)
	glyph.add_theme_color_override("font_color", CAT_COLOR.get(cat, MUTED).lightened(0.4))
	icon.add_child(glyph)
	return icon

## Cartão de item: ícone, nome, detalhe (qtd · peso · efeito) e botões.
func _card(id: String, n: int, buttons: Array) -> Control:
	var entry := SurvivalData.item(id)
	var cat := str(entry.get("cat", "material"))
	var card := PanelContainer.new()
	card.tooltip_text = "%s\n%s" % [SurvivalData.item_name(id), _describe(id)]
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var normal := _style(CARD, 6, Color(0, 0, 0, 0), 8)
	var hover := _style(CARD_HOVER, 6, Color(0, 0, 0, 0), 8)
	card.add_theme_stylebox_override("panel", normal)
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", normal))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(_icon(cat))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(_label(SurvivalData.item_name(id) + ("   ×%d" % n if n > 1 else ""), 14, TEXT))
	var detail := "%.2f kg" % (float(entry.get("weight", 0)) * n)
	var effect := _describe(id)
	text.add_child(_label(detail + ("   •   " + effect if not effect.is_empty() else ""), 11, MUTED))
	for spec in buttons:
		var b := _button(spec[0], spec.size() > 2 and bool(spec[2]))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(spec[1])
		row.add_child(b)
	return card

func _empty(text: String) -> Label:
	var l := _label(text, 13, MUTED, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _clear(box: Node) -> void:
	for child in box.get_children():
		child.queue_free()

func _refresh() -> void:
	if _items == null:
		return
	_weight_bar.max_value = cap
	_weight_bar.value = minf(weight, cap)
	var ratio := weight / maxf(cap, 0.1)
	var fill_color := Color("#7fbf5a") if ratio < 0.75 else (Color("#e0b03e") if ratio < 0.95 else Color("#e05a4a"))
	_weight_bar.add_theme_stylebox_override("fill", _style(fill_color, 6, Color(0, 0, 0, 0), 0))
	_weight_label.text = "%.1f / %.0f kg" % [weight, cap]
	_refresh_left()
	_refresh_items()
	_refresh_side()

func _refresh_left() -> void:
	_clear(_equip_box)
	_clear(_status_box)
	# Costas
	var back_card := PanelContainer.new()
	back_card.add_theme_stylebox_override("panel", _style(CARD, 6, Color(0, 0, 0, 0), 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	back_card.add_child(row)
	row.add_child(_icon("gear"))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(_label("Costas", 11, MUTED))
	if back.is_empty():
		text.add_child(_label("Só bolsos (%d kg)" % int(SurvivalData.catalog().get("carry_base", 10)), 13, TEXT))
	else:
		text.add_child(_label(SurvivalData.item_name(back), 13, TEXT))
		text.add_child(_label("+%d kg de carga" % int(SurvivalData.item(back).get("carry", 0)), 11, Color("#8fbf8a")))
		var off := _button("Tirar")
		off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		off.pressed.connect(func(): unequip_requested.emit())
		row.add_child(off)
	_equip_box.add_child(back_card)
	# Arma e ferramenta
	for spec in [["Arma na mão", weapon if not weapon.is_empty() else "Nenhuma", "weapon"], ["Melhor arma branca", _best_melee_name(), "melee"]]:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(CARD, 6, Color(0, 0, 0, 0), 8))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		card.add_child(r)
		r.add_child(_icon(spec[2]))
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_constant_override("separation", 0)
		r.add_child(t)
		t.add_child(_label(spec[0], 11, MUTED))
		t.add_child(_label(spec[1], 13, TEXT))
		_equip_box.add_child(card)
	for spec in [["Vida", "hp", Color("#d0574a")], ["Fome", "hunger", Color("#d6a23e")], ["Sede", "thirst", Color("#4aa3d8")]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := _label(spec[0], 12, MUTED)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		name_label.custom_minimum_size.x = 44
		line.add_child(name_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.value = float(status.get(spec[1], 100))
		bar.add_theme_stylebox_override("background", _style(Color("#0c0f12"), 5, Color(0, 0, 0, 0), 0))
		bar.add_theme_stylebox_override("fill", _style(spec[2], 5, Color(0, 0, 0, 0), 0))
		line.add_child(bar)
		var value := _label("%d" % int(float(status.get(spec[1], 100))), 12, TEXT)
		value.size_flags_horizontal = Control.SIZE_SHRINK_END
		value.custom_minimum_size.x = 28
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		_status_box.add_child(line)

func _best_melee_name() -> String:
	var best: Array = SurvivalData.best_melee(inv)
	return "Soco (%d)" % int(best[1]) if str(best[0]).is_empty() else "%s (%d)" % [SurvivalData.item_name(str(best[0])), int(best[1])]

func _refresh_items() -> void:
	_clear(_items)
	var count := 0
	for id in inv:
		count += int(inv[id])
	_items_title.text = "INVENTÁRIO  •  %d itens" % count
	if inv.is_empty():
		_items.add_child(_empty("Vazio. Revista armários, geladeiras, carros e mochilas no chão (E)."))
		return
	var last_cat := ""
	for id in _sorted(inv):
		var entry := SurvivalData.item(id)
		var cat := str(entry.get("cat", "material"))
		if cat != last_cat:
			last_cat = cat
			var header := _label(str(CAT_NAME.get(cat, cat)).to_upper(), 11, CAT_COLOR.get(cat, MUTED))
			_items.add_child(header)
		var buttons: Array = []
		if entry.has("use"):
			buttons.append(["Usar", func(): use_requested.emit(id), true])
		if str(entry.get("slot", "")) == "back":
			buttons.append(["Equipar", func(): equip_requested.emit(id), true])
		buttons.append(["Largar", func(): drop_requested.emit(id, false)])
		_items.add_child(_card(id, int(inv[id]), buttons))

func _refresh_side() -> void:
	_clear(_side)
	_tab_box.add_theme_stylebox_override("normal", _style(ACCENT.darkened(0.45) if _tab == 0 else Color("#3a4652"), 4, Color(0, 0, 0, 0), 8))
	_tab_craft.add_theme_stylebox_override("normal", _style(ACCENT.darkened(0.45) if _tab == 1 else Color("#3a4652"), 4, Color(0, 0, 0, 0), 8))
	if _tab == 0:
		_side_title.text = container_title if not container_id.is_empty() else "Nada aberto"
		_take_all.visible = not container_id.is_empty() and not container_items.is_empty()
		if container_id.is_empty():
			_side.add_child(_empty("Chegue perto de um armário, geladeira, porta-malas ou mochila no chão e aperte E para revistar."))
		elif container_items.is_empty():
			_side.add_child(_empty("Vazio."))
		for id in _sorted(container_items):
			_side.add_child(_card(id, int(container_items[id]), [["Pegar", func(): take_requested.emit(container_id, id, true), true]]))
		return
	_side_title.text = "Receitas"
	_take_all.visible = false
	for recipe in SurvivalData.recipes():
		var needs: Dictionary = recipe["needs"]
		var have_all := true
		var parts: Array[String] = []
		for item in needs:
			var have := int(inv.get(item, 0))
			have_all = have_all and have >= int(needs[item])
			parts.append("%s %d/%d" % [SurvivalData.item_name(item), have, int(needs[item])])
		var rid := str(recipe["id"])
		var gives: Array = recipe["gives"]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(CARD, 6, Color(0, 0, 0, 0), 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		row.add_child(_icon(str(SurvivalData.item(str(gives[0])).get("cat", "material"))))
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		row.add_child(text)
		text.add_child(_label(str(recipe["name"]), 14, TEXT))
		text.add_child(_label(", ".join(parts), 11, Color("#8fbf8a") if have_all else MUTED))
		var make := _button("Fabricar", true)
		make.disabled = not have_all
		make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		make.pressed.connect(func(): craft_requested.emit(rid))
		row.add_child(make)
		_side.add_child(card)
