extends Control
## Loja das salas de Equipes (2x2 e 4x4). B abre/fecha durante a janela de
## compra do início da partida. Eliminatória e Mata-mata usam caixas no mapa.
## Mesmo visual do menu principal (painel escuro, laranja de destaque) e as
## armas aparecem com os modelos 3D do jogo (assets/weapons/polyy).
## Só mostra e pede: o servidor confere créditos, tempo e limites ("bought" /
## "buy_denied") e o controlador da partida chama refresh().
signal buy_requested(item: String)
signal close_requested

const WeaponData = preload("res://scripts/weapon_data.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const INTER_PATH := "res://assets/fonts/InterVariable.ttf"
const WEAPONS := ["pistol", "smg", "shotgun", "rifle", "sniper", "bow"]
const GEAR := {"medkit": "Kit médico", "grenade": "Granada"}
const GEAR_NOTE := {"medkit": "+50 de vida  ·  usar com F", "grenade": "Dano em área  ·  lançar com G"}
const ROLE := {"pistol": "Arma curta", "smg": "Submetralhadora", "shotgun": "Curto alcance", "rifle": "Fuzil", "sniper": "Precisão", "bow": "Arco e flecha"}
# Same palette as the main menu (scripts/menu.gd).
const ACCENT := Color("#f0a23b")
const ACCENT_HOT := Color("#e8622c")
const TEXT := Color("#eef1ec")
const MUTED := Color("#8d9a98")
const DIM := Color("#5f6d6c")
const PANEL := Color(0.045, 0.065, 0.075, 0.96)
const LINE := Color(1, 1, 1, 0.09)
const CARD := Color(1, 1, 1, 0.035)
const OWNED := Color("#7ccf8a")
const DANGER := Color("#e0705e")
const INK := Color("#1a1208") # dark text on orange

var prices: Dictionary = {}
var ammo: Dictionary = {}
var max_medkits := 5
var max_nades := 3
var window_ms := 120000
var credits_label: Label
var timer_label: Label
var timer_fill: ColorRect
var note_label: Label
var _cards: Dictionary = {} # item -> Button
var _parts: Dictionary = {} # item -> {price, price_label, content, pips}
var _status: Dictionary = {} # item -> "COMPRADA" / "CHEIO" / "$300" (also for tests)
var _semi: Font
var _bold: Font
var _caps: Font

func setup(shop: Dictionary) -> void:
	prices = shop.get("prices", {})
	ammo = shop.get("ammo", {})
	max_medkits = int(shop.get("maxMedkits", 5))
	max_nades = int(shop.get("maxNades", 3))
	window_ms = maxi(1, int(shop.get("window", 120000)))

func _ready() -> void:
	name = "ShopPanel"
	visible = false
	_load_fonts()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.025, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ShopFrame"
	panel.custom_minimum_size = Vector2(900, 0)
	var frame := _box(PANEL, LINE, 1, 14)
	frame.set_content_margin_all(26)
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 24
	panel.add_theme_stylebox_override("panel", frame)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(_header())
	column.add_child(_timer_bar())
	column.add_child(_section("Armas"))
	var weapons := HBoxContainer.new()
	weapons.add_theme_constant_override("separation", 10)
	column.add_child(weapons)
	for i in WEAPONS.size():
		if WEAPONS[i] == "bow" and not prices.has("bow"):
			continue # availability and price come from this room's server
		weapons.add_child(_weapon_card(WEAPONS[i], i + 1))
	column.add_child(_section("Equipamento"))
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 10)
	column.add_child(gear)
	for item in GEAR:
		gear.add_child(_gear_card(item))
	note_label = _label("", 14, DANGER, _semi)
	note_label.name = "ShopNote"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.custom_minimum_size.y = 18
	column.add_child(note_label)
	column.add_child(_footer())

# ---------------------------------------------------------------- layout ---

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("FASE DE COMPRA  ·  EQUIPES", 12, ACCENT, _caps))
	titles.add_child(_label("Loja", 30, TEXT, _bold))
	var money := _chip("CRÉDITOS", "$ 0", ACCENT)
	credits_label = money.find_child("Value", true, false) as Label
	credits_label.name = "ShopCredits"
	header.add_child(money)
	var clock := _chip("TEMPO", "2:00", TEXT)
	timer_label = clock.find_child("Value", true, false) as Label
	timer_label.name = "ShopTimer"
	timer_label.custom_minimum_size.x = 64
	header.add_child(clock)
	return header

## Small card with a caps caption over a big value (credits, time).
func _chip(caption: String, value: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var box := _box(CARD, LINE, 1, 10)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	chip.add_theme_stylebox_override("panel", box)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", -2)
	chip.add_child(block)
	block.add_child(_label(caption, 10, MUTED, _caps))
	var big := _label(value, 24, color, _bold)
	big.name = "Value"
	block.add_child(big)
	return chip

## Thin bar that empties as buy time runs out.
func _timer_bar() -> Control:
	var track := Panel.new()
	track.custom_minimum_size.y = 4
	track.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.07), Color.TRANSPARENT, 0, 2))
	timer_fill = ColorRect.new()
	timer_fill.color = ACCENT
	track.add_child(timer_fill)
	timer_fill.anchor_bottom = 1.0
	return track

## Caps caption with a line, like the menu's section titles.
func _section(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_label(text.to_upper(), 12, MUTED, _caps))
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row

func _footer() -> Control:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var keys := _label("B ou ESC fecha   ·   abates dão créditos: jogador +$400, bot +$200, na cabeça +$100", 12, DIM)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(keys)
	var close := Button.new()
	close.name = "ShopClose"
	close.text = "Fechar"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(132, 44)
	UiTheme.secondary(close, 15) # mesmo visual do menu principal
	close.pressed.connect(func(): close_requested.emit())
	footer.add_child(close)
	return footer

## Tall card: role and slot, the weapon's 3D model, name, stat bars, price.
func _weapon_card(item: String, slot: int) -> Button:
	var button := _card_button(item, Vector2(140 if prices.has("bow") else 162, 272))
	var stats: Dictionary = WeaponData.stats(item)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	_fill_card(button, content, 12)
	var top := HBoxContainer.new()
	content.add_child(top)
	var role := _pill(ROLE.get(item, ""), ACCENT)
	top.add_child(role)
	var spacer_top := Control.new()
	spacer_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer_top)
	var key := _label(str(slot), 11, DIM, _caps)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(key)
	var stage := Stage.new()
	stage.custom_minimum_size.y = 84
	content.add_child(stage)
	var view := WeaponView.new()
	view.weapon_id = item
	stage.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_label(str(stats["name"]), 18, TEXT, _bold))
	var per_shot := float(stats["damage"]) * int(stats["pellets"])
	content.add_child(_stat_row("Dano", clampf(per_shot / 95.0, 0.05, 1.0)))
	content.add_child(_stat_row("Cadência", clampf(0.085 / float(stats["interval"]), 0.05, 1.0)))
	content.add_child(_stat_row("Alcance", clampf(sqrt(float(stats["range"]) / 700.0), 0.05, 1.0)))
	var ammunition := "%d flechas · segure e solte" % int(ammo.get(item, 0)) if item == "bow" else "Pente %d  ·  +%d balas" % [int(stats["mag"]), int(ammo.get(item, 0))]
	var ammunition_label := _label(ammunition, 11, MUTED)
	ammunition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(ammunition_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var price := _price_tag()
	content.add_child(price)
	_parts[item] = {"price": price, "price_label": price.get_child(0), "content": content}
	return button

## Wide card: drawing, name, what it does, carried count as pips, price.
func _gear_card(item: String) -> Button:
	var button := _card_button(item, Vector2(0, 80))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	_fill_card(button, content, 12)
	var stage := Stage.new()
	stage.custom_minimum_size = Vector2(86, 0)
	content.add_child(stage)
	var icon := GearIcon.new()
	icon.kind = item
	stage.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 3)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(text)
	text.add_child(_label(str(GEAR[item]), 17, TEXT, _bold))
	text.add_child(_label(GEAR_NOTE[item], 12, MUTED))
	var pips := Pips.new()
	pips.custom_minimum_size = Vector2(0, 8)
	pips.color = ACCENT
	text.add_child(pips)
	var price := _price_tag()
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(price)
	_parts[item] = {"price": price, "price_label": price.get_child(0), "content": content, "pips": pips}
	return button

## Rounded tag for the price ("$1200", "COMPRADA").
func _price_tag() -> PanelContainer:
	var tag := PanelContainer.new()
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_child(_label("$0", 16, INK, _bold))
	return tag

func _pill(text: String, color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var box := _box(Color(color, 0.14), Color.TRANSPARENT, 0, 10)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", box)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(_label(text.to_upper(), 9, color, _caps))
	return pill

func _card_button(item: String, min_size: Vector2) -> Button:
	var button := Button.new()
	button.name = "Buy_" + item
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.text = ""
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_card(button, CARD, LINE)
	button.pressed.connect(func(): buy_requested.emit(item))
	_cards[item] = button
	return button

func _fill_card(button: Button, content: Control, pad: int) -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(content)
	_ignore_mouse(margin)

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _stat_row(caption: String, value: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(caption.to_upper(), 9, MUTED, _caps)
	name_label.custom_minimum_size.x = 60
	row.add_child(name_label)
	var bar := StatBar.new()
	bar.value = value
	bar.color = ACCENT
	bar.custom_minimum_size.y = 5
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return row

# --------------------------------------------------------------- refresh ---

## Rebuilds every card: owned weapons, what you can afford, carry limits.
func refresh(credits: int, owned: Dictionary, medkits: int, nades: int, seconds_left: float) -> void:
	if credits_label == null:
		return
	credits_label.text = "$ %d" % credits
	var left := maxi(0, ceili(seconds_left))
	timer_label.text = "%d:%02d" % [floori(left / 60.0), left % 60]
	var urgent := left <= 5
	timer_label.add_theme_color_override("font_color", ACCENT_HOT if urgent else TEXT)
	timer_fill.anchor_right = clampf(seconds_left * 1000.0 / window_ms, 0.0, 1.0)
	timer_fill.offset_right = 0
	timer_fill.color = ACCENT_HOT if urgent else ACCENT
	for item in _cards:
		var button: Button = _cards[item]
		var parts: Dictionary = _parts[item]
		var price := int(prices.get(item, 0))
		var state := "buy"
		var text := "$%d" % price
		if item in WEAPONS:
			if owned.has(item):
				state = "owned"
				text = "COMPRADA"
		else:
			var count := medkits if item == "medkit" else nades
			var limit := max_medkits if item == "medkit" else max_nades
			(parts["pips"] as Pips).set_count(count, limit)
			if count >= limit:
				state = "owned"
				text = "CHEIO"
		if state == "buy" and credits < price:
			state = "poor"
		_status[item] = text
		button.disabled = state != "buy"
		var tag: PanelContainer = parts["price"]
		var tag_label: Label = parts["price_label"]
		tag_label.text = text
		var content: Control = parts["content"]
		match state:
			"owned":
				tag.add_theme_stylebox_override("panel", _tag_box(Color(OWNED, 0.16)))
				tag_label.add_theme_color_override("font_color", OWNED)
				tag_label.add_theme_font_size_override("font_size", 12)
				_style_card(button, Color(OWNED, 0.05), Color(OWNED, 0.35))
				content.modulate = Color.WHITE
			"poor":
				tag.add_theme_stylebox_override("panel", _tag_box(Color(1, 1, 1, 0.06)))
				tag_label.add_theme_color_override("font_color", DANGER)
				tag_label.add_theme_font_size_override("font_size", 16)
				_style_card(button, CARD, LINE)
				content.modulate = Color(1, 1, 1, 0.62)
			_:
				tag.add_theme_stylebox_override("panel", _tag_box(ACCENT))
				tag_label.add_theme_color_override("font_color", INK)
				tag_label.add_theme_font_size_override("font_size", 16)
				_style_card(button, CARD, LINE)
				content.modulate = Color.WHITE

## What a card shows as its price/status ("$300", "COMPRADA", "CHEIO").
func card_status(item: String) -> String:
	return str(_status.get(item, ""))

func show_note(text: String) -> void:
	if note_label != null:
		note_label.text = text

# --------------------------------------------------------------- helpers ---

func _tag_box(bg: Color) -> StyleBoxFlat:
	var box := _box(bg, Color.TRANSPARENT, 0, 8)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box

## Card states follow the menu buttons: orange tint and border on hover.
func _style_card(button: Button, bg: Color, border: Color) -> void:
	button.add_theme_stylebox_override("normal", _box(bg, border, 1, 10))
	button.add_theme_stylebox_override("disabled", _box(bg, border, 1, 10))
	button.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 10))
	var hover := _box(Color(ACCENT, 0.10), ACCENT, 2, 10)
	hover.shadow_color = Color(ACCENT, 0.18)
	hover.shadow_size = 10
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.2), ACCENT, 2, 10))

func _load_fonts() -> void:
	var inter := load(INTER_PATH) as Font
	if inter == null:
		return
	_semi = _weighted(inter, 600)
	_bold = _weighted(inter, 700)
	_caps = _weighted(inter, 600)
	(_caps as FontVariation).spacing_glyph = 1

func _weighted(base: Font, weight_value: int) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = base
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight_value}
	return font

func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Same rounded box helper as the menu: background, border width, radius.
func _box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box

# -------------------------------------------------------------- visuals ---

## Dark rounded backdrop with a soft orange spotlight behind the item.
class Stage extends Control:
	static var _glow: GradientTexture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.28)
		box.set_corner_radius_all(8)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		if _glow == null:
			var gradient := Gradient.new()
			gradient.set_color(0, Color(1.0, 0.68, 0.3, 0.16))
			gradient.set_color(1, Color(1.0, 0.68, 0.3, 0.0))
			_glow = GradientTexture2D.new()
			_glow.gradient = gradient
			_glow.fill = GradientTexture2D.FILL_RADIAL
			_glow.fill_from = Vector2(0.5, 0.6)
			_glow.fill_to = Vector2(1.0, 0.6)
			_glow.width = 128
			_glow.height = 64
		draw_texture_rect(_glow, Rect2(Vector2.ZERO, size), false)
		draw_line(Vector2(size.x * 0.12, size.y * 0.86), Vector2(size.x * 0.88, size.y * 0.86), Color(1, 1, 1, 0.05), 1.0)

## The weapon's real 3D model (same GLB as in the hands), side view with a
## slight turn, rendered in a small transparent viewport.
class WeaponView extends SubViewportContainer:
	const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
	const TURN := deg_to_rad(-18.0) # a little 3/4 so it reads as 3D
	const FLIP := {} # models whose muzzle would point left after laying them along X
	const ZOOM := 1.1 # camera framing: 1 = the model touches the edges
	var weapon_id := "pistol"
	var _viewport: SubViewport

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		stretch = true

	func _ready() -> void:
		_viewport = SubViewport.new()
		_viewport.transparent_bg = true
		_viewport.own_world_3d = true
		_viewport.msaa_3d = Viewport.MSAA_4X
		_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(_viewport)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.78, 0.82)
		env.ambient_light_energy = 1.1
		var world := WorldEnvironment.new()
		world.environment = env
		_viewport.add_child(world)
		var key := DirectionalLight3D.new()
		key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(25), 0)
		key.light_energy = 1.7
		_viewport.add_child(key)
		var rim := DirectionalLight3D.new()
		rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
		rim.light_energy = 0.6
		rim.light_color = Color(1.0, 0.8, 0.55)
		_viewport.add_child(rim)
		var pivot := Node3D.new()
		_viewport.add_child(pivot)
		var profile: Dictionary = WeaponProportions.PROFILES.get(weapon_id, {})
		var scene := load(WeaponProportions.BASE + str(profile.get("file", ""))) as PackedScene if not profile.is_empty() else null
		if weapon_id == "bow":
			scene = load("res://assets/weapons/bow/recurve_bow.glb") as PackedScene
		if scene == null:
			return
		var model := scene.instantiate() as Node3D
		pivot.add_child(model)
		# Lay the gun along X with the muzzle to the right, then turn it a bit.
		var box := _bounds(pivot)
		if box.size.z > box.size.x:
			model.rotate_y(PI / 2.0)
		if FLIP.has(weapon_id):
			model.rotate_y(PI)
		pivot.rotate_y(TURN)
		box = _bounds(pivot)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		var aspect := maxf(0.5, size.x / maxf(1.0, size.y)) if size.y > 0 else 2.0
		camera.size = maxf(box.size.y, box.size.x / aspect) * ZOOM
		camera.position = box.get_center() + Vector3(0, 0, 5)
		camera.near = 0.05
		camera.far = 20.0
		_viewport.add_child(camera)
		camera.current = true
		resized.connect(func(): camera.size = maxf(box.size.y, box.size.x / maxf(0.5, size.x / maxf(1.0, size.y))) * ZOOM)

	func _bounds(root: Node3D) -> AABB:
		var out := AABB()
		var first := true
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var part: AABB = mesh.global_transform * mesh.get_aabb()
			out = part if first else out.merge(part)
			first = false
		return out

## Medkit and grenade, drawn flat in the menu palette.
class GearIcon extends Control:
	var kind := "medkit"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x / 60.0, size.y / 40.0) * 0.8
		draw_set_transform(size * 0.5 - Vector2(30, 20) * s, 0.0, Vector2(s, s))
		var shade := Color(0, 0, 0, 0.3)
		if kind == "medkit":
			var case_box := StyleBoxFlat.new()
			case_box.bg_color = Color("#e9ece6")
			case_box.set_corner_radius_all(3)
			draw_rect(Rect2(10, 11, 40, 26).grow(0.5), shade)
			draw_style_box(case_box, Rect2(9, 10, 40, 26))
			draw_polyline(PackedVector2Array([Vector2(22, 10), Vector2(22, 5), Vector2(36, 5), Vector2(36, 10)]), Color("#c9ccc5"), 2.5)
			draw_rect(Rect2(9, 16, 40, 1.2), Color(0, 0, 0, 0.15))
			draw_rect(Rect2(26, 19, 6, 15), Color("#d9443a"))
			draw_rect(Rect2(21.5, 23.5, 15, 6), Color("#d9443a"))
		else:
			draw_circle(Vector2(31, 26), 11.5, shade)
			draw_circle(Vector2(30, 25), 11.5, Color("#6f7d4c"))
			draw_circle(Vector2(26.5, 21.5), 4.0, Color(1, 1, 1, 0.15))
			for y in [20.0, 25.0, 30.0]:
				draw_rect(Rect2(19, y, 22, 1.2), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(25, 9, 10, 6), Color("#9aa0a3"))
			draw_colored_polygon(PackedVector2Array([Vector2(35, 9), Vector2(43, 11), Vector2(40, 29), Vector2(38, 29), Vector2(38, 13)]), Color("#b5bbbe"))
			draw_arc(Vector2(22, 10), 3.5, 0.0, TAU, 20, ACCENT_COLOR, 1.8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	const ACCENT_COLOR := Color("#f0a23b")

## Segmented bar (5 notches) for a 0..1 weapon stat.
class StatBar extends Control:
	var value := 0.5
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 2.0
		var w := (size.x - gap * 4.0) / 5.0
		for i in 5:
			var rect := Rect2(i * (w + gap), 0, w, size.y)
			draw_rect(rect, Color(1, 1, 1, 0.08))
			var fill := clampf(value * 5.0 - i, 0.0, 1.0)
			if fill > 0.0:
				draw_rect(Rect2(rect.position, Vector2(w * fill, size.y)), color)

## Carried count as small rounded squares (filled = carried).
class Pips extends Control:
	var count := 0
	var limit := 5
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_count(value: int, max_value: int) -> void:
		count = value
		limit = max_value
		queue_redraw()

	func _draw() -> void:
		for i in limit:
			var rect := Rect2(i * 14.0, 0, 10, minf(size.y, 8.0))
			if i < count:
				draw_rect(rect, color)
			else:
				draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)
