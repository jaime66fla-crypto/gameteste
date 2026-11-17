extends PanelContainer
## Inventário da Sobrevivência (TAB): mochila, recipiente aberto/chão e fabricação.
## Só mostra e pede; o servidor confirma tudo (respostas "inv" e "container").
signal take_requested(container_id: String, item: String, all: bool)
signal take_all_requested(container_id: String)
signal drop_requested(item: String, all: bool)
signal use_requested(item: String)
signal craft_requested(recipe: String)

const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CAT_ORDER := ["weapon", "ammo", "melee", "medical", "food", "drink", "gear", "material"]
const CAT_NAME := {"weapon": "Arma", "ammo": "Munição", "melee": "Arma branca", "medical": "Cura", "food": "Comida", "drink": "Bebida", "gear": "Equipamento", "material": "Material"}

var inv: Dictionary = {}
var weight := 0.0
var cap := 20.0
var container_id := ""
var container_title := ""
var container_items: Dictionary = {}

var _bag_list: VBoxContainer
var _bag_title: Label
var _box_list: VBoxContainer
var _box_title: Label
var _take_all: Button
var _craft_list: VBoxContainer
var _weight_bar: ProgressBar

func _ready() -> void:
	name = "Inventory"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.07, 0.94)
	style.border_color = Color("#6f7d5c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", style)
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(980, 520)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var header := Label.new()
	header.text = "INVENTÁRIO   (TAB fecha  •  clique fora para voltar a mirar)"
	header.add_theme_color_override("font_color", Color("#d9c98a"))
	root.add_child(header)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var bag := _column(columns, "Mochila")
	_bag_title = bag[0]
	_bag_list = bag[1]
	_weight_bar = ProgressBar.new()
	_weight_bar.custom_minimum_size.y = 14
	_weight_bar.show_percentage = false
	_bag_title.get_parent().add_child(_weight_bar)
	_bag_title.get_parent().move_child(_weight_bar, 1)
	var box := _column(columns, "Chão / recipiente")
	_box_title = box[0]
	_box_list = box[1]
	_take_all = Button.new()
	_take_all.text = "Pegar tudo"
	_take_all.pressed.connect(func(): take_all_requested.emit(container_id))
	_box_title.get_parent().add_child(_take_all)
	_box_title.get_parent().move_child(_take_all, 1)
	var craft := _column(columns, "Fabricar")
	_craft_list = craft[1]
	_refresh()

func _column(parent: Control, title: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	col.add_child(label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	return [label, list]

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()

func close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_inventory(new_inv: Dictionary, new_weight: float, new_cap: float) -> void:
	inv = new_inv
	weight = new_weight
	cap = new_cap
	_refresh()

func show_container(id: String, title: String, items: Dictionary) -> void:
	container_id = id
	container_title = title
	container_items = items
	_refresh()

func clear_container() -> void:
	container_id = ""
	container_items = {}
	_refresh()

func _sorted(items: Dictionary) -> Array:
	var list := items.keys()
	list.sort_custom(func(a, b):
		var ca := CAT_ORDER.find(str(SurvivalData.item(a).get("cat", "material")))
		var cb := CAT_ORDER.find(str(SurvivalData.item(b).get("cat", "material")))
		return ca < cb if ca != cb else SurvivalData.item_name(a) < SurvivalData.item_name(b))
	return list

func _row(list: VBoxContainer, text: String, tip: String, buttons: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = text
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	for spec in buttons:
		var b := Button.new()
		b.text = spec[0]
		b.disabled = spec.size() > 2 and bool(spec[2])
		b.pressed.connect(spec[1])
		row.add_child(b)
	list.add_child(row)

func _describe(id: String) -> String:
	var entry := SurvivalData.item(id)
	var parts: Array[String] = [str(CAT_NAME.get(entry.get("cat", ""), ""))]
	var use: Dictionary = entry.get("use", {})
	for key in use:
		parts.append("%s %+d" % [{"hp": "vida", "hunger": "fome", "thirst": "sede"}.get(key, key), int(use[key])])
	if entry.has("melee"):
		parts.append("dano %d" % int(entry["melee"]))
	if entry.has("carry"):
		parts.append("+%d kg de carga" % int(entry["carry"]))
	if entry.has("ammo"):
		parts.append("usa " + SurvivalData.item_name(str(entry["ammo"])))
	parts.append("%.2f kg" % float(entry.get("weight", 0)))
	return "  •  ".join(parts)

func _refresh() -> void:
	if _bag_list == null:
		return
	for list in [_bag_list, _box_list, _craft_list]:
		for child in list.get_children():
			child.queue_free()
	_bag_title.text = "Mochila  —  %.1f / %.0f kg" % [weight, cap]
	_weight_bar.max_value = cap
	_weight_bar.value = minf(weight, cap)
	for id in _sorted(inv):
		var n := int(inv[id])
		var entry := SurvivalData.item(id)
		var buttons: Array = []
		if entry.has("use"):
			buttons.append(["Usar", func(): use_requested.emit(id)])
		buttons.append(["Largar", func(): drop_requested.emit(id, false)])
		_row(_bag_list, "%s  ×%d" % [SurvivalData.item_name(id), n], _describe(id), buttons)
	if inv.is_empty():
		_row(_bag_list, "(vazia)", "", [])
	_box_title.text = container_title if not container_id.is_empty() else "Chão / recipiente"
	_take_all.visible = not container_id.is_empty() and not container_items.is_empty()
	if container_id.is_empty():
		_row(_box_list, "Chegue perto de um armário, geladeira,", "", [])
		_row(_box_list, "carro ou mochila e aperte E para revistar.", "", [])
	elif container_items.is_empty():
		_row(_box_list, "(vazio)", "", [])
	for id in _sorted(container_items):
		var n := int(container_items[id])
		_row(_box_list, "%s  ×%d" % [SurvivalData.item_name(id), n], _describe(id), [["Pegar", func(): take_requested.emit(container_id, id, true)]])
	for recipe in SurvivalData.recipes():
		var needs: Dictionary = recipe["needs"]
		var have_all := true
		var parts: Array[String] = []
		for item in needs:
			var have := int(inv.get(item, 0))
			have_all = have_all and have >= int(needs[item])
			parts.append("%s %d/%d" % [SurvivalData.item_name(item), have, int(needs[item])])
		var rid := str(recipe["id"])
		_row(_craft_list, str(recipe["name"]), ", ".join(parts), [["Fabricar", func(): craft_requested.emit(rid), not have_all]])
		var need_label := Label.new()
		need_label.text = "   " + ", ".join(parts)
		need_label.add_theme_font_size_override("font_size", 12)
		need_label.add_theme_color_override("font_color", Color("#8fbf8a") if have_all else Color("#9a8f80"))
		_craft_list.add_child(need_label)
