extends Control
## Loja das partidas (Eliminatória, Mata-mata, Equipes). B abre/fecha durante a
## janela de compra (início da partida e cada renascimento no mata-mata).
## Só mostra e pede: o servidor confere créditos, tempo e limites ("bought" /
## "buy_denied") e o controlador da partida chama refresh().
##
##  ┌ LOJA ───────────────────────── $ 800 ── 0:14 ┐
##  │ ARMAS                                          │
##  │ [Pistola  22 dano · 15 tiros      $200]  ...   │
##  │ EQUIPAMENTO                                    │
##  │ [Kit médico  0/5  $300] [Granada 0/3  $300]    │
##  │ B ou ESC fecha  ·  sem créditos? abata alguém  │
##  └────────────────────────────────────────────────┘
signal buy_requested(item: String)
signal close_requested

const WeaponData = preload("res://scripts/weapon_data.gd")
const WEAPONS := ["pistol", "smg", "shotgun", "rifle", "sniper"]
const GEAR := {"medkit": "Kit médico", "grenade": "Granada"}
const GEAR_NOTE := {"medkit": "+50 de vida (F)", "grenade": "Lança com G"}
const PANEL := Color(0.07, 0.085, 0.1, 0.94)
const CARD := Color(1, 1, 1, 0.05)
const CARD_HOVER := Color(1, 1, 1, 0.1)
const LINE := Color(1, 1, 1, 0.1)
const TEXT := Color("#eef1ec")
const MUTED := Color("#8d9a98")
const ACCENT := Color("#ffc94a")
const OWNED := Color("#8fd18a")
const DENIED := Color("#ff7a5c")

var prices: Dictionary = {}
var ammo: Dictionary = {}
var max_medkits := 5
var max_nades := 3
var credits_label: Label
var timer_label: Label
var note_label: Label
var _cards: Dictionary = {} # item -> Button

func setup(shop: Dictionary) -> void:
	prices = shop.get("prices", {})
	ammo = shop.get("ammo", {})
	max_medkits = int(shop.get("maxMedkits", 5))
	max_nades = int(shop.get("maxNades", 3))

func _ready() -> void:
	name = "ShopPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", _box(PANEL, Color(ACCENT, 0.35), 12, 22))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	# Header: title, credits and the time left to buy.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var title := _label("LOJA", 26, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	credits_label = _label("$ 0", 26, ACCENT)
	credits_label.name = "ShopCredits"
	header.add_child(credits_label)
	timer_label = _label("0:20", 18, MUTED)
	timer_label.name = "ShopTimer"
	timer_label.custom_minimum_size.x = 64
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(timer_label)
	column.add_child(_label("ARMAS", 12, MUTED))
	var weapons := GridContainer.new()
	weapons.columns = 2
	weapons.add_theme_constant_override("h_separation", 10)
	weapons.add_theme_constant_override("v_separation", 10)
	column.add_child(weapons)
	for item in WEAPONS:
		weapons.add_child(_card(item))
	column.add_child(_label("EQUIPAMENTO", 12, MUTED))
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 10)
	column.add_child(gear)
	for item in GEAR:
		var card := _card(item)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gear.add_child(card)
	note_label = _label("", 14, DENIED)
	note_label.name = "ShopNote"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(note_label)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var hint := _label("B ou ESC fecha  ·  abates dão créditos: jogador +400, bot +200, cabeça +100", 13, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(hint)
	var close := Button.new()
	close.name = "ShopClose"
	close.text = "Fechar"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(110, 38)
	close.pressed.connect(func(): close_requested.emit())
	footer.add_child(close)

func _card(item: String) -> Button:
	var button := Button.new()
	button.name = "Buy_" + item
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(300, 62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, _box(CARD_HOVER if state == "hover" else CARD, LINE, 8, 12))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color(TEXT, 0.4))
	button.pressed.connect(func(): buy_requested.emit(item))
	_cards[item] = button
	return button

## Rebuilds every card: owned weapons, what you can afford, carry limits.
func refresh(credits: int, owned: Dictionary, medkits: int, nades: int, seconds_left: float) -> void:
	if credits_label == null:
		return
	credits_label.text = "$ %d" % credits
	var left := maxi(0, ceili(seconds_left))
	timer_label.text = "%d:%02d" % [floori(left / 60.0), left % 60]
	timer_label.add_theme_color_override("font_color", DENIED if left <= 5 else MUTED)
	for item in _cards:
		var button: Button = _cards[item]
		var price := int(prices.get(item, 0))
		var line1 := ""
		var line2 := ""
		var status := "$%d" % price
		var blocked := false
		if item in WEAPONS:
			var stats: Dictionary = WeaponData.stats(item)
			line1 = str(stats["name"])
			line2 = "%d de dano  ·  pente %d  ·  +%d balas" % [int(stats["damage"]), int(stats["mag"]), int(ammo.get(item, 0))]
			if owned.has(item):
				status = "COMPRADA"
				blocked = true
		else:
			var count := medkits if item == "medkit" else nades
			var limit := max_medkits if item == "medkit" else max_nades
			line1 = "%s  %d/%d" % [GEAR[item], count, limit]
			line2 = GEAR_NOTE[item]
			if count >= limit:
				status = "CHEIO"
				blocked = true
		if not blocked and credits < price:
			blocked = true
		button.text = "%s   —   %s\n%s" % [line1, status, line2]
		button.disabled = blocked
		var color := OWNED if status in ["COMPRADA", "CHEIO"] else (ACCENT if credits >= price else DENIED)
		button.add_theme_color_override("font_disabled_color", Color(color, 0.75) if status in ["COMPRADA", "CHEIO"] else Color(TEXT, 0.4))
		button.add_theme_color_override("font_color", TEXT)

func show_note(text: String) -> void:
	if note_label != null:
		note_label.text = text

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _box(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(pad)
	return box
