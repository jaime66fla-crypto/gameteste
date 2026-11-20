extends RefCounted
## Tema do menu principal para o jogo inteiro: as mesmas cores, a fonte Inter
## (pesos 400/600/700) e os mesmos botões e painéis de scripts/menu.gd.
## main.gd põe `UiTheme.theme()` na janela raiz, então todo controle sem estilo
## próprio já sai igual ao menu; as telas com estilo próprio usam os ajudantes
## daqui (box, card, primary, secondary, caps, title).
const ACCENT := Color("#f0a23b")
const ACCENT_HOT := Color("#e8622c")
const TEXT := Color("#eef1ec")
const MUTED := Color("#8d9a98")
const DIM := Color("#5f6d6c")
const PANEL := Color(0.045, 0.065, 0.075, 0.94)
const PANEL_SOLID := Color("#0e1518")
const LINE := Color(1, 1, 1, 0.09)
const GOOD := Color("#7ccf8a")
const DANGER := Color("#e0705e")
const INK := Color("#1a1208") # texto sobre o laranja
const INTER_PATH := "res://assets/fonts/InterVariable.ttf"

static var _fonts: Dictionary = {}
static var _theme: Theme

## Inter no peso pedido (400 normal, 600 semi, 700 título); `caps` = letras espaçadas.
static func font(weight: int = 400, caps: bool = false) -> Font:
	var key := "%d%s" % [weight, "c" if caps else ""]
	if _fonts.has(key):
		return _fonts[key]
	var base := load(INTER_PATH) as Font
	if base == null:
		var fallback := SystemFont.new()
		fallback.font_names = PackedStringArray(["Inter", "Segoe UI", "Roboto", "Arial"])
		base = fallback
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if caps:
		f.spacing_glyph = 1
	_fonts[key] = f
	return f

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_width: int = 0, radius: int = 4) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(border_width)
	b.set_corner_radius_all(radius)
	b.anti_aliasing = true
	return b

static func _pad(b: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b

## Painel/janela do jogo: fundo escuro translúcido, linha clara fina, cantos de 10.
static func card(pad: float = 18.0, bg: Color = PANEL) -> StyleBoxFlat:
	var b := _pad(box(bg, LINE, 1, 10), pad, pad - 4)
	b.shadow_color = Color(0, 0, 0, 0.45)
	b.shadow_size = 18
	return b

## Bloco dentro de um painel (lista, cartão).
static func inset(pad: float = 12.0, highlight: bool = false) -> StyleBoxFlat:
	return _pad(box(Color(ACCENT, 0.08) if highlight else Color(1, 1, 1, 0.035), Color(ACCENT, 0.55) if highlight else LINE, 1, 8), pad, pad * 0.7)

## Botão principal do menu: laranja chapado, inclinado, texto escuro em negrito.
static func primary(b: Button, size_px: int = 15) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(700))
	b.add_theme_font_size_override("font_size", size_px)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := _pad(box(ACCENT, ACCENT, 0, 2), 18, 7)
		s.skew = Vector2(-0.16, 0)
		match state:
			"hover", "focus":
				s.bg_color = ACCENT.lightened(0.14)
				s.shadow_color = Color(ACCENT, 0.3)
				s.shadow_size = 10
			"pressed":
				s.bg_color = ACCENT_HOT
			"disabled":
				s.bg_color = Color(1, 1, 1, 0.05)
		b.add_theme_stylebox_override(state, s)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_disabled_color", DIM)
	return b

## Botão secundário do menu: quase transparente, faixa à esquerda que acende em laranja.
static func secondary(b: Button, size_px: int = 14) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(600))
	b.add_theme_font_size_override("font_size", size_px)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := _pad(box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.16), 0, 2), 16, 7)
		s.skew = Vector2(-0.16, 0)
		s.border_width_left = 3
		match state:
			"hover", "focus":
				s.bg_color = Color(ACCENT, 0.14)
				s.border_color = ACCENT
				s.border_width_left = 4
			"pressed":
				s.bg_color = Color(ACCENT, 0.26)
				s.border_color = ACCENT
			"disabled":
				s.bg_color = Color(1, 1, 1, 0.02)
				s.border_color = Color(1, 1, 1, 0.05)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DIM)
	return b

## Aba/filtro: ligada = laranja translúcido com borda laranja.
static func tab(b: Button, on: bool, size_px: int = 13) -> Button:
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(600, true))
	b.add_theme_font_size_override("font_size", size_px)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := _pad(box(Color(ACCENT, 0.18) if on else Color(1, 1, 1, 0.04), ACCENT if on else Color(1, 1, 1, 0.12), 1, 4), 12, 5)
		if state == "hover" and not on:
			s.bg_color = Color(ACCENT, 0.1)
			s.border_color = Color(ACCENT, 0.6)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", ACCENT if on else MUTED)
	b.add_theme_color_override("font_hover_color", ACCENT if on else TEXT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	return b

static func label(text: String, size_px: int = 14, color: Color = TEXT, weight: int = 400) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l

## Título de seção do menu: maiúsculas pequenas e espaçadas, cinza.
static func caps(text: String, size_px: int = 12, color: Color = MUTED) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font(600, true))
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l

## Título grande (negrito, maiúsculas).
static func title(text: String, size_px: int = 24, color: Color = TEXT) -> Label:
	var l := label(text.to_upper(), size_px, color, 700)
	return l

## Barra (vida, carga...) no estilo do menu: trilho escuro, preenchimento colorido.
static func bar(b: ProgressBar, fill: Color, height: float = 6.0) -> ProgressBar:
	b.show_percentage = false
	b.custom_minimum_size.y = height
	b.add_theme_stylebox_override("background", box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.06), 1, 3))
	b.add_theme_stylebox_override("fill", box(fill, Color.TRANSPARENT, 0, 3))
	return b

## Tema padrão (o mesmo de menu.gd _build_theme) para os controles sem estilo próprio.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 16
	t.set_color("font_color", "Label", Color("#d6dfd9"))
	var field := _pad(box(Color(0.02, 0.03, 0.035, 0.75), Color(1, 1, 1, 0.12), 1, 4), 14, 4)
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	field_focus.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", DIM)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))
	for type in ["Button", "OptionButton"]:
		var normal := _pad(box(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), 1, 4), 14, 6)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(ACCENT, 0.16)
		hover.border_color = ACCENT
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(ACCENT, 0.28)
		pressed.border_color = ACCENT
		var disabled := normal.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(1, 1, 1, 0.03)
		disabled.border_color = Color(1, 1, 1, 0.05)
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("focus", type, hover)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, DIM)
		t.set_font("font", type, font(600))
	for type in ["CheckBox", "CheckButton"]:
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_stylebox("normal", type, StyleBoxEmpty.new())
		t.set_stylebox("hover", type, StyleBoxEmpty.new())
		t.set_stylebox("pressed", type, StyleBoxEmpty.new())
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", card())
	# Janelas de diálogo (Sair da partida?): mesmo painel do menu, título em laranja.
	t.set_stylebox("panel", "AcceptDialog", _pad(box(Color("#0e1518"), Color.TRANSPARENT, 0, 0), 20, 16))
	var frame := box(Color("#0e1518"), Color(ACCENT, 0.6), 1, 10)
	frame.expand_margin_top = 34
	frame.expand_margin_left = 8
	frame.expand_margin_right = 8
	frame.expand_margin_bottom = 8
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 24
	t.set_stylebox("embedded_border", "Window", frame)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_color("title_color", "Window", ACCENT)
	t.set_font("title_font", "Window", font(700))
	t.set_font_size("title_font_size", "Window", 16)
	t.set_stylebox("panel", "PopupMenu", box(Color("#10171a"), Color(1, 1, 1, 0.12), 1, 4))
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.2), Color.TRANSPARENT, 0, 2))
	t.set_stylebox("panel", "TooltipPanel", _pad(box(Color("#10171a"), Color(ACCENT, 0.5), 1, 4), 10, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("background", "ProgressBar", box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.06), 1, 3))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 0, 3))
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.10), Color.TRANSPARENT, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, Color.TRANSPARENT, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT.lightened(0.15), Color.TRANSPARENT, 0, 2))
	for bar_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar_type, box(Color(0, 0, 0, 0.0), Color.TRANSPARENT, 0, 3))
		t.set_stylebox("grabber", bar_type, box(Color(1, 1, 1, 0.14), Color.TRANSPARENT, 0, 3))
		t.set_stylebox("grabber_highlight", bar_type, box(Color(ACCENT, 0.6), Color.TRANSPARENT, 0, 3))
		t.set_stylebox("grabber_pressed", bar_type, box(ACCENT, Color.TRANSPARENT, 0, 3))
	_theme = t
	return t
