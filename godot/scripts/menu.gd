extends Control
const PointerMode = preload("res://scripts/pointer_mode.gd")
const Settings = preload("res://scripts/game_settings.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const CharacterCard = preload("res://scripts/characters/character_card.gd")
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const Controls = preload("res://scripts/controls.gd")
var settings: Dictionary
var content: VBoxContainer
var status: Label
var menu_card: PanelContainer
var page_width := 430.0
var selection_feedback: Label

# ---------------------------------------------------------------- visual ---
const ACCENT := Color("#f0a23b")
const ACCENT_HOT := Color("#e8622c")
const TEXT := Color("#eef1ec")
const MUTED := Color("#8d9a98")
const DIM := Color("#5f6d6c")
const PANEL := Color(0.045, 0.065, 0.075, 0.88)
const LINE := Color(1, 1, 1, 0.09)
const COMPACT_WIDTH := 980.0

## Animated smoke, warm glow from below, scanlines and vignette.
const BACKGROUND_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color = vec4(0.035, 0.05, 0.06, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.09, 0.065, 0.05, 1.0);
uniform vec4 glow_color : source_color = vec4(0.95, 0.42, 0.14, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0; float a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
    return v;
}
void fragment() {
    vec2 uv = UV;
    vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, uv.y));
    float t = TIME * 0.025;
    float warp = fbm(uv * vec2(2.6, 1.8) + vec2(t, -t * 0.7));
    float smoke = fbm(uv * 3.2 + warp * 1.6 + vec2(-t * 0.6, t * 0.25));
    col += vec3(0.07, 0.075, 0.075) * smoke * smoke * 1.6;
    float glow = smoothstep(1.25, 0.0, distance(uv * vec2(1.0, 1.3), vec2(0.78, 1.38)));
    col += glow_color.rgb * glow * glow * (0.32 + 0.18 * smoke);
    col *= 0.975 + 0.025 * sin(FRAGCOORD.y * 1.6);
    float vig = length((uv - 0.5) * vec2(1.15, 1.0));
    col *= 1.0 - 0.6 * vig * vig;
    COLOR = vec4(col, 1.0);
}
"""

var shell: MarginContainer
var hub: Control
var hub_compact := false
var main_notice := ""
var embers: CPUParticles2D
const INTER_PATH := "res://assets/fonts/InterVariable.ttf"
var base_font: FontVariation
var semi_font: FontVariation
var title_font: FontVariation
var caps_font: FontVariation
var code_font: FontVariation

func _ready() -> void:
    PointerMode.setup_window(get_tree())
    PointerMode.release()
    settings = Settings.load_settings()
    Settings.apply(settings,get_viewport())
    Controls.load_and_apply()
    Net.avatar_loaded.connect(_on_avatar_loaded)
    _build_fonts()
    theme = _build_theme()
    _build_background()
    var margin := MarginContainer.new()
    shell = margin
    resized.connect(_on_menu_resized)
    add_child(margin)
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left","right","top","bottom"]:
        margin.add_theme_constant_override("margin_"+edge,24)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)
    var center := CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(center)
    var card := PanelContainer.new()
    menu_card = card
    card.custom_minimum_size.x = minf(430.0,get_viewport_rect().size.x - 48)
    var panel := _box(PANEL, LINE, 1, 6)
    panel.border_width_top = 3
    panel.border_color = LINE
    panel.shadow_color = Color(0, 0, 0, 0.45)
    panel.shadow_size = 24
    panel.content_margin_left = 28
    panel.content_margin_right = 28
    panel.content_margin_top = 30
    panel.content_margin_bottom = 28
    card.add_theme_stylebox_override("panel",panel)
    center.add_child(card)
    content = VBoxContainer.new()
    content.add_theme_constant_override("separation",14)
    card.add_child(content)
    _build_invite_banner()
    Net.friend_invite.connect(_on_friend_invite)
    Net.friends_updated.connect(_on_friends_updated)
    if not Net.pending_invite.is_empty():
        _on_friend_invite(str(Net.pending_invite["from"]), str(Net.pending_invite["code"]))
    if Net.in_room_lobby():
        _return_to_room()
        return
    _start_session()

## Back from a custom-room match: same room, same code (the server keeps it).
func _return_to_room() -> void:
    _connect_net()
    if not Net.party_info.is_empty() and not Net.in_match:
        _on_party_updated(Net.party_info)
        return
    _clear()
    _label("Sala personalizada",28)
    status = _label("Voltando para a sala %s..." % Net.party_code,17)
    status.name = "MultiplayerStatus"
    _button("Sair da sala","LeavePartyButton",_leave_party)

## New players see the login screen; a saved session goes straight to the menu.
func _start_session() -> void:
    if Net.is_logged_in():
        _show_main()
        return
    if Net.session_token.is_empty():
        _show_login(false)
        return
    _clear()
    _logo()
    _label("CAMPO DE FOGO",32,Color("#f0f2e9"))
    _label("Entrando na sua conta...",16)
    var error: String = await Net.refresh_profile()
    if not is_inside_tree():
        return
    if error.is_empty():
        _show_main()
    elif Net.session_token.is_empty():
        _show_login(false, error)
    else:
        # Server unreachable: offline practice still works.
        _show_main(error)

## Game logo (icon.png) centred above the title.
func _logo(size: float = 110.0) -> void:
    var texture := load("res://icon.png") as Texture2D
    if texture == null:
        return
    var logo := TextureRect.new()
    logo.name = "GameLogo"
    logo.texture = texture
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    logo.custom_minimum_size = Vector2(size, size)
    logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
    content.add_child(logo)

func _field(placeholder: String, node_name: String, secret: bool = false) -> LineEdit:
    var field := LineEdit.new()
    field.name = node_name
    field.placeholder_text = placeholder
    field.secret = secret
    field.max_length = 72 if secret else 16
    field.custom_minimum_size.y = 44
    field.add_theme_font_size_override("font_size",18)
    content.add_child(field)
    return field

func _show_login(create: bool, message: String = "") -> void:
    _clear()
    _set_page_width(430.0)
    _logo()
    _label("CAMPO DE FOGO",32,Color("#f0f2e9"))
    _label("CRIAR CONTA" if create else "ENTRAR",15,Color("#9bad9f"))
    var name_field := _field("Nome de jogador (3 a 16 letras)","AccountName")
    name_field.text = Net.load_name()
    var password := _field("Senha (mínimo 6 caracteres)","AccountPassword",true)
    var confirm: LineEdit = _field("Repita a senha","AccountPasswordConfirm",true) if create else null
    var feedback := _label(message,15,Color("#f0a08a"))
    feedback.name = "LoginFeedback"
    var submit := _button("Criar conta e entrar" if create else "Entrar","LoginSubmit",Callable(),true)
    submit.pressed.connect(func():
        if confirm != null and confirm.text != password.text:
            feedback.text = "As senhas não são iguais."
            return
        submit.disabled = true
        feedback.add_theme_color_override("font_color",Color("#d6dfd9"))
        feedback.text = "Conectando..."
        var error: String = await Net.authenticate(name_field.text,password.text,create)
        if not is_inside_tree():
            return
        if error.is_empty():
            Net.save_name(name_field.text.strip_edges())
            _show_main()
        else:
            submit.disabled = false
            feedback.add_theme_color_override("font_color",Color("#f0a08a"))
            feedback.text = error)
    for field in [name_field, password, confirm]:
        if field != null:
            field.text_submitted.connect(func(_text): submit.pressed.emit())
    (password if not name_field.text.is_empty() else name_field).grab_focus()
    if create:
        _button("Já tenho conta","SwitchToLogin",func(): _show_login(false))
    else:
        _button("Sou novo: criar conta","SwitchToCreate",func(): _show_login(true))
    _button("Treinar offline sem conta","OfflineButton",func(): _show_main())

const UI_STATE_PATH := "user://ui.cfg"

## Lista de patentes aberta ou fechada (lembrada entre sessões).
func _ranks_open() -> bool:
    var file := ConfigFile.new()
    return bool(file.get_value("menu", "ranks_open", true)) if file.load(UI_STATE_PATH) == OK else true

var _suppress_ui_save := false # testes: não mexe no arquivo do jogador

func _save_ranks_open(open: bool) -> void:
    if _suppress_ui_save:
        return
    var file := ConfigFile.new()
    file.load(UI_STATE_PATH)
    file.set_value("menu", "ranks_open", open)
    file.save(UI_STATE_PATH)

## Every rank with its XP, in small print; the player's current one highlighted.
## O título é um botão que esconde/mostra a lista.
func _rank_ladder(current: String, parent: Node) -> void:
    var open := _ranks_open()
    var toggle := Button.new()
    toggle.name = "RankLadderToggle"
    toggle.flat = true
    toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
    toggle.focus_mode = Control.FOCUS_NONE
    toggle.add_theme_font_size_override("font_size", 10)
    if caps_font != null:
        toggle.add_theme_font_override("font", caps_font)
    for state in ["font_color", "font_pressed_color", "font_focus_color"]:
        toggle.add_theme_color_override(state, MUTED)
    toggle.add_theme_color_override("font_hover_color", ACCENT)
    toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    toggle.tooltip_text = "Mostrar ou esconder a lista de patentes"
    parent.add_child(toggle)
    var ladder := RichTextLabel.new()
    ladder.name = "RankLadder"
    ladder.bbcode_enabled = true
    ladder.fit_content = true
    ladder.scroll_active = false
    ladder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ladder.add_theme_font_size_override("normal_font_size",10)
    ladder.add_theme_font_size_override("bold_font_size",10)
    var parts: Array[String] = []
    for entry in Net.rank_table().get("ranks",[]):
        var text := "%s %d" % [entry.get("name",""),int(entry.get("xp",0))]
        if str(entry.get("name","")) == current:
            parts.append("[color=#f0a23b][b]%s[/b][/color]" % text)
        else:
            parts.append("[color=#5f6d6c]%s[/color]" % text)
    ladder.text = "  •  ".join(parts)
    ladder.visible = open
    parent.add_child(ladder)
    var label_for := func(is_open: bool) -> String: return ("▾  " if is_open else "▸  ") + "PATENTES (XP)" + ("" if is_open else "  ·  mostrar")
    toggle.text = label_for.call(open)
    toggle.pressed.connect(func():
        ladder.visible = not ladder.visible
        toggle.text = label_for.call(ladder.visible)
        _save_ranks_open(ladder.visible))

func _clear() -> void:
    friends_screen_open = false
    if chat_dock != null:
        chat_dock.set("shown", false) # o chat só fica na tela principal
        chat_dock.call("refresh")
    if invite_side != null:
        invite_side.visible = false # a lista lateral só existe na tela da sala
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()
    if hub != null:
        remove_child(hub)
        hub.queue_free()
        hub = null
    if shell != null:
        shell.visible = true

func _label(text: String, font_size: int = 16, color: Color = Color("#d6dfd9"), parent: Node = null) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    if font_size >= 24 and title_font != null:
        label.add_theme_font_override("font",title_font)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    (parent if parent != null else content).add_child(label)
    return label

func _button(text: String, node_name: String, action: Callable, primary: bool = false, parent: Node = null) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.custom_minimum_size.y = 48
    button.add_theme_font_size_override("font_size",16)
    if semi_font != null:
        button.add_theme_font_override("font",semi_font)
    for state in ["normal","hover","pressed","focus","disabled"]:
        var box := _box(ACCENT if primary else Color(1,1,1,0.05), Color(1,1,1,0.10), 0 if primary else 1, 8)
        box.content_margin_left = 18
        box.content_margin_right = 18
        if state == "hover" or state == "focus":
            box.bg_color = ACCENT.lightened(0.12) if primary else Color(ACCENT, 0.14)
            box.border_color = ACCENT
        elif state == "pressed":
            box.bg_color = ACCENT.darkened(0.12) if primary else Color(ACCENT, 0.24)
        elif state == "disabled":
            box.bg_color = Color(1,1,1,0.04)
        if state == "focus":
            box.set_border_width_all(2)
            box.border_color = TEXT if primary else ACCENT
        button.add_theme_stylebox_override(state,box)
    for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
        button.add_theme_color_override(state,Color("#1a1208") if primary else TEXT)
    button.add_theme_color_override("font_disabled_color",DIM)
    if action.is_valid():
        button.pressed.connect(action)
    (parent if parent != null else content).add_child(button)
    return button

# ------------------------------------------------------------ main hub ---

## Full-screen main menu: brand + navigation on the left, profile on the right.
func _show_main(notice: String = "") -> void:
    _clear()
    main_notice = notice
    shell.visible = false
    var view := get_viewport_rect().size
    hub_compact = view.x < COMPACT_WIDTH
    var root := MarginContainer.new()
    root.name = "MainHub"
    hub = root
    add_child(root)
    move_child(root, shell.get_index() + 1)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var side_margin := 24 if hub_compact else int(clampf(view.x * 0.055, 40, 96))
    var top_margin := 20 if hub_compact else int(clampf(view.y * 0.06, 28, 64))
    for edge in ["left","right"]:
        root.add_theme_constant_override("margin_" + edge, side_margin)
    for edge in ["top","bottom"]:
        root.add_theme_constant_override("margin_" + edge, top_margin)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    root.add_child(scroll)
    var columns: BoxContainer
    if hub_compact:
        columns = VBoxContainer.new()
    else:
        columns = HBoxContainer.new()
    columns.add_theme_constant_override("separation", 28 if hub_compact else 56)
    columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(columns)

    var left := VBoxContainer.new()
    left.name = "MainLeft"
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_theme_constant_override("separation", 0)
    columns.add_child(left)
    _brand(left)
    _spacer(left, 28.0, not hub_compact)

    var nav := VBoxContainer.new()
    nav.name = "MainNav"
    nav.add_theme_constant_override("separation", 8)
    nav.custom_minimum_size.x = 0.0 if hub_compact else 440.0
    nav.size_flags_horizontal = Control.SIZE_FILL if hub_compact else Control.SIZE_SHRINK_BEGIN
    left.add_child(nav)
    var logged := Net.is_logged_in()
    var first: Button
    if logged:
        first = _nav_button(nav, "Jogar online", "MultiplayerButton", _show_multiplayer, true, "4 modos de jogo")
    else:
        first = _nav_button(nav, "Entrar / criar conta", "LoginButton", func(): _show_login(false), true)
    _nav_button(nav, "Treino offline", "StartButton", _start_match, false, "Bonecos de teste")
    _nav_divider(nav)
    if logged:
        var requests: int = Net.friends_data.get("requests",[]).size()
        var friends := _nav_button(nav, "Amigos", "FriendsButton", _show_friends)
        if requests > 0:
            _nav_badge(friends, "%d pedido%s" % [requests, "s" if requests > 1 else ""])
    _nav_button(nav, "Personagens", "CharactersButton", _show_characters, false, _selected_character_name())
    _nav_button(nav, "Configurações", "ConfigButton", _show_config)
    _nav_divider(nav)
    var quiet := HBoxContainer.new()
    quiet.add_theme_constant_override("separation", 8)
    nav.add_child(quiet)
    if logged:
        _quiet_button(quiet, "Sair da conta", "LogoutButton", func():
            Net.logout()
            _show_login(false))
    _quiet_button(quiet, "Sair do jogo", "ExitButton", func(): get_tree().quit())

    if not notice.is_empty():
        _spacer(left, 14.0, false)
        var warn := _label(notice, 14, Color("#f0a08a"), left)
        warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        warn.custom_minimum_size.x = 0.0 if hub_compact else 440.0
        warn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if not hub_compact else Control.SIZE_FILL
    _spacer(left, 24.0, not hub_compact)
    _footer(left)

    var side := VBoxContainer.new()
    side.name = "MainSide"
    side.alignment = BoxContainer.ALIGNMENT_CENTER
    side.custom_minimum_size.x = 0.0 if hub_compact else clampf(view.x * 0.3, 360, 440)
    side.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(side)
    side.add_theme_constant_override("separation", 16)
    if logged:
        _profile_panel(side)
    else:
        _offline_panel(side)
    _leaderboard_panel(side)
    first.grab_focus()
    _animate_in(nav.get_children() + [side])
    _show_chat_dock()

## Chat global e com amigos no canto inferior direito (scripts/ui/chat_dock.gd).
## O mesmo painel é reaproveitado: aberto/fechado e a conversa continuam.
const ChatDockScript = preload("res://scripts/ui/chat_dock.gd")
var chat_dock: PanelContainer

func _show_chat_dock() -> void:
    if chat_dock == null:
        chat_dock = ChatDockScript.new()
        chat_dock.call("setup", self)
        add_child(chat_dock)
    move_child(chat_dock, get_child_count() - 1)
    chat_dock.set("shown", true)
    chat_dock.call("refresh")

func _on_menu_resized() -> void:
    if menu_card:
        menu_card.custom_minimum_size.x = minf(page_width, get_viewport_rect().size.x - 48)
    if embers:
        embers.position = Vector2(size.x * 0.5, size.y + 12)
        embers.emission_rect_extents = Vector2(size.x * 0.55, 8)
    if hub != null and (get_viewport_rect().size.x < COMPACT_WIDTH) != hub_compact:
        _show_main.call_deferred(main_notice)

func _spacer(parent: Node, height: float, expand: bool) -> void:
    var gap := Control.new()
    gap.custom_minimum_size.y = height
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if expand:
        gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(gap)

## Logo, small kicker, big title and an accent bar.
func _brand(parent: Node) -> void:
    var row := HBoxContainer.new()
    row.name = "Brand"
    row.add_theme_constant_override("separation", 20)
    parent.add_child(row)
    var texture := load("res://icon.png") as Texture2D
    if texture != null:
        var logo := TextureRect.new()
        logo.name = "GameLogo"
        logo.texture = texture
        logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        var side := 64.0 if hub_compact else 92.0
        logo.custom_minimum_size = Vector2(side, side)
        logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(logo)
    var words := VBoxContainer.new()
    words.add_theme_constant_override("separation", 2)
    words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(words)
    var kicker := _plain("SHOOTER TÁTICO ONLINE", 13, ACCENT, caps_font)
    words.add_child(kicker)
    var title := _plain("CAMPO DE FOGO", 40 if hub_compact else 62, TEXT, title_font)
    title.name = "GameTitle"
    title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
    title.add_theme_constant_override("shadow_offset_y", 4)
    title.add_theme_constant_override("shadow_outline_size", 6)
    words.add_child(title)
    var bars := HBoxContainer.new()
    bars.add_theme_constant_override("separation", 6)
    words.add_child(bars)
    for spec in [[72.0, ACCENT], [22.0, ACCENT_HOT], [10.0, Color(1,1,1,0.25)]]:
        var bar := ColorRect.new()
        bar.custom_minimum_size = Vector2(spec[0], 4)
        bar.color = spec[1]
        bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bars.add_child(bar)

## Left-aligned label that does not wrap (brand, captions, footer).
func _plain(text: String, font_size: int, color: Color, font: Font = null) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    if font != null:
        label.add_theme_font_override("font", font)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label

## Big angled menu entry; the hint sits on the right in small caps.
func _nav_button(parent: Node, text: String, node_name: String, action: Callable, primary: bool = false, hint: String = "") -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text.to_upper()
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.custom_minimum_size.y = 62.0 if primary else 50.0
    button.add_theme_font_size_override("font_size", 22 if primary else 18)
    button.add_theme_font_override("font", title_font)
    button.focus_mode = Control.FOCUS_ALL
    var skew := Vector2(-0.16, 0)
    for state in ["normal","hover","pressed","focus"]:
        var box: StyleBoxFlat
        if primary:
            box = _box(ACCENT, ACCENT, 0, 2)
            if state == "hover" or state == "focus":
                box.bg_color = ACCENT.lightened(0.14)
                box.shadow_color = Color(ACCENT, 0.35)
                box.shadow_size = 14
            elif state == "pressed":
                box.bg_color = ACCENT_HOT
        else:
            box = _box(Color(1,1,1,0.035), Color(1,1,1,0.14), 0, 2)
            box.border_width_left = 3
            if state == "hover" or state == "focus":
                box.bg_color = Color(ACCENT, 0.13)
                box.border_color = ACCENT
                box.border_width_left = 5
            elif state == "pressed":
                box.bg_color = Color(ACCENT, 0.24)
                box.border_color = ACCENT
        box.skew = skew
        box.content_margin_left = 30
        box.content_margin_right = 24
        button.add_theme_stylebox_override(state, box)
    var ink := Color("#1a1208") if primary else TEXT
    for state in ["font_color","font_focus_color","font_pressed_color"]:
        button.add_theme_color_override(state, ink)
    button.add_theme_color_override("font_hover_color", Color("#1a1208") if primary else Color("#ffffff"))
    if not hint.is_empty():
        var tip := _plain(hint.to_upper(), 11, Color(0.1, 0.07, 0.03, 0.75) if primary else DIM, caps_font)
        tip.name = "Hint"
        tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        button.add_child(tip)
        tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        tip.offset_right = -26
        if not primary:
            button.mouse_entered.connect(func(): tip.add_theme_color_override("font_color", ACCENT))
            button.mouse_exited.connect(func(): tip.add_theme_color_override("font_color", DIM))
    if action.is_valid():
        button.pressed.connect(action)
    parent.add_child(button)
    return button

## Small pill on the right of a nav entry (e.g. pending friend requests).
func _nav_badge(button: Button, text: String) -> void:
    var pill := PanelContainer.new()
    pill.name = "Badge"
    pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var box := _box(ACCENT_HOT, ACCENT_HOT, 0, 10)
    box.content_margin_left = 10
    box.content_margin_right = 10
    box.content_margin_top = 2
    box.content_margin_bottom = 2
    pill.add_theme_stylebox_override("panel", box)
    pill.add_child(_plain(text.to_upper(), 11, Color.WHITE, caps_font))
    button.add_child(pill)
    pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
    pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    pill.offset_right = -24

func _nav_divider(parent: Node) -> void:
    var line := ColorRect.new()
    line.custom_minimum_size.y = 1
    line.color = LINE
    line.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var wrap := MarginContainer.new()
    wrap.add_theme_constant_override("margin_top", 6)
    wrap.add_theme_constant_override("margin_bottom", 6)
    wrap.add_child(line)
    parent.add_child(wrap)

## Low-emphasis text button for logout / quit.
func _quiet_button(parent: Node, text: String, node_name: String, action: Callable) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text.to_upper()
    button.custom_minimum_size = Vector2(0, 38)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_override("font", caps_font)
    button.add_theme_font_size_override("font_size", 13)
    for state in ["normal","hover","pressed","focus"]:
        var box := _box(Color(0,0,0,0.0), Color(1,1,1,0.12), 1, 2)
        if state != "normal":
            box.bg_color = Color(ACCENT_HOT, 0.14)
            box.border_color = ACCENT_HOT
        box.skew = Vector2(-0.16, 0)
        button.add_theme_stylebox_override(state, box)
    button.add_theme_color_override("font_color", MUTED)
    for state in ["font_hover_color","font_focus_color","font_pressed_color"]:
        button.add_theme_color_override(state, TEXT)
    button.pressed.connect(action)
    parent.add_child(button)
    return button

## Connection status on the left, version on the right.
func _footer(parent: Node) -> void:
    var row := HBoxContainer.new()
    row.name = "MainFooter"
    row.add_theme_constant_override("separation", 10)
    parent.add_child(row)
    var online := Net.is_logged_in()
    var dot := Panel.new()
    dot.custom_minimum_size = Vector2(8, 8)
    dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    dot.add_theme_stylebox_override("panel", _box(Color("#7fd35c") if online else ACCENT, Color.TRANSPARENT, 0, 4))
    row.add_child(dot)
    row.add_child(_plain("CONECTADO" if online else "MODO OFFLINE", 12, MUTED, caps_font))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(gap)
    var version := _plain("VERSÃO " + Net.game_version(), 12, DIM, caps_font)
    version.name = "VersionLabel"
    row.add_child(version)

## Dark card with a thin accent strip on top; returns the column to fill.
func _side_panel(parent: Node, panel_name: String) -> VBoxContainer:
    var holder := VBoxContainer.new()
    holder.name = panel_name
    holder.add_theme_constant_override("separation", 0)
    parent.add_child(holder)
    var strip := ColorRect.new()
    strip.color = ACCENT
    strip.custom_minimum_size = Vector2(0, 3)
    strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(strip)
    var panel := PanelContainer.new()
    var box := _box(PANEL, LINE, 1, 0)
    box.border_width_top = 0
    box.corner_radius_bottom_left = 4
    box.corner_radius_bottom_right = 4
    box.shadow_color = Color(0, 0, 0, 0.4)
    box.shadow_size = 22
    for side in ["left","right"]:
        box.set("content_margin_" + side, 22)
    for side in ["top","bottom"]:
        box.set("content_margin_" + side, 18)
    panel.add_theme_stylebox_override("panel", box)
    holder.add_child(panel)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 12)
    panel.add_child(stack)
    return stack

## Player card: avatar initial, name, rank, XP progress, stats and rank ladder.
func _profile_panel(parent: Node) -> void:
    var profile: Dictionary = Net.profile
    var stack := _side_panel(parent, "ProfilePanel")
    stack.add_child(_plain("PERFIL DO OPERADOR", 12, MUTED, caps_font))
    var who := HBoxContainer.new()
    who.add_theme_constant_override("separation", 14)
    stack.add_child(who)
    var player_name := str(profile.get("name", ""))
    who.add_child(_profile_photo(player_name, int(profile.get("avatar", 0)), 56.0))
    var names := VBoxContainer.new()
    names.add_theme_constant_override("separation", 0)
    names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    who.add_child(names)
    var name_label := _plain(player_name, 26, TEXT, title_font)
    name_label.name = "ProfileName"
    name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    names.add_child(name_label)
    names.add_child(_plain(str(profile.get("rank","Recruta")).to_upper(), 13, ACCENT, caps_font))
    var edit := Button.new()
    edit.name = "EditProfileButton"
    edit.text = "✎  Editar"
    edit.tooltip_text = "Trocar nick e foto"
    edit.flat = true
    edit.focus_mode = Control.FOCUS_NONE
    edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    edit.add_theme_font_size_override("font_size", 12)
    if caps_font != null:
        edit.add_theme_font_override("font", caps_font)
    edit.add_theme_color_override("font_color", MUTED)
    edit.add_theme_color_override("font_hover_color", ACCENT)
    edit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    edit.pressed.connect(func(): _show_profile_editor())
    who.add_child(edit)

    var xp := int(profile.get("xp",0))
    var next_xp = profile.get("nextRankXp")
    var rank_xp := int(profile.get("rankXp",0))
    var bar := ProgressBar.new()
    bar.name = "XpBar"
    bar.show_percentage = false
    bar.custom_minimum_size.y = 8
    if next_xp == null:
        bar.max_value = 1
        bar.value = 1
    else:
        bar.max_value = maxf(1.0, float(int(next_xp) - rank_xp))
        bar.value = xp - rank_xp
    bar.add_theme_stylebox_override("fill", _box(ACCENT, ACCENT, 0, 2))
    bar.add_theme_stylebox_override("background", _box(Color(1,1,1,0.07), Color.TRANSPARENT, 0, 2))
    stack.add_child(bar)
    var progress := "%s XP  •  PATENTE MÁXIMA" % _thousands(xp) if next_xp == null else "%s / %s XP  •  PRÓXIMA: %s" % [_thousands(xp), _thousands(int(next_xp)), str(profile.get("nextRank","")).to_upper()]
    var xp_label := _plain(progress, 12, MUTED, caps_font)
    xp_label.name = "XpLabel"
    xp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    stack.add_child(xp_label)

    var grid := GridContainer.new()
    grid.name = "ProfileStats"
    grid.columns = 4
    grid.add_theme_constant_override("h_separation", 8)
    grid.add_theme_constant_override("v_separation", 8)
    stack.add_child(grid)
    for stat in [["Abates", profile.get("kills",0)], ["Bots", profile.get("botKills",0)], ["Vitórias", profile.get("wins",0)], ["Partidas", profile.get("matches",0)]]:
        grid.add_child(_stat_tile(str(stat[0]), int(stat[1])))
    _rank_ladder(str(profile.get("rank","")), stack)

func _stat_tile(caption: String, value: int) -> PanelContainer:
    var tile := PanelContainer.new()
    tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := _box(Color(1,1,1,0.035), Color(1,1,1,0.06), 1, 3)
    for side in ["left","right"]:
        box.set("content_margin_" + side, 8)
    for side in ["top","bottom"]:
        box.set("content_margin_" + side, 6)
    tile.add_theme_stylebox_override("panel", box)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", -2)
    tile.add_child(column)
    var number := _plain(_thousands(value), 20, TEXT, title_font)
    number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(number)
    var label := _plain(caption.to_upper(), 10, MUTED, caps_font)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(label)
    return tile

func _selected_character_name() -> String:
    var definition: Resource = CharacterRegistry.definition(CharacterRegistry.load_selection())
    if definition == null:
        return ""
    return str(definition.get("display_name"))

func _character_row(parent: Node) -> void:
    var character := _selected_character_name()
    if character.is_empty():
        return
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    parent.add_child(row)
    row.add_child(_plain("PERSONAGEM", 12, MUTED, caps_font))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(gap)
    row.add_child(_plain(character.to_upper(), 13, TEXT, caps_font))

## Shown instead of the profile when nobody is logged in.
func _offline_panel(parent: Node) -> void:
    var stack := _side_panel(parent, "OfflinePanel")
    stack.add_child(_plain("MODO OFFLINE", 12, ACCENT, caps_font))
    stack.add_child(_plain("Sem conta conectada", 26, TEXT, title_font))
    for line in ["Entre na conta para jogar online, ganhar XP e subir de patente.", "No treino offline, bonecos mostram o dano de cada acerto por arma e parte do corpo."]:
        var text := Label.new()
        text.text = line
        text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        text.add_theme_color_override("font_color", MUTED)
        text.add_theme_font_size_override("font_size", 15)
        stack.add_child(text)
    _character_row(stack)

# --------------------------------------------------------- leaderboard ---

const LEADERBOARD_ROWS := 10
const MEDALS := [Color("#f0c24b"), Color("#c9d1d6"), Color("#d08a52")]
var leaderboard_cache: Dictionary = {}
var leaderboard_compact := false
var leaderboard_rows := LEADERBOARD_ROWS

## Top players by XP, loaded from the server; last result shown while it refreshes.
## Sempre o top 10; telas baixas usam linhas finas (uma linha só) para caber sem rolar.
func _leaderboard_panel(parent: Node) -> void:
    leaderboard_compact = get_viewport_rect().size.y < 860.0
    leaderboard_rows = LEADERBOARD_ROWS
    var stack := _side_panel(parent, "LeaderboardPanel")
    stack.add_theme_constant_override("separation", 8)
    var head := HBoxContainer.new()
    stack.add_child(head)
    head.add_child(_plain("RANKING DOS JOGADORES", 12, MUTED, caps_font))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    head.add_child(_plain("TOP %d  •  XP" % leaderboard_rows, 11, DIM, caps_font))
    var list := VBoxContainer.new()
    list.name = "LeaderboardList"
    list.add_theme_constant_override("separation", 4)
    stack.add_child(list)
    if leaderboard_cache.is_empty():
        list.add_child(_plain("Carregando ranking...", 13, DIM))
    else:
        _fill_leaderboard(list, leaderboard_cache)
    _refresh_leaderboard(list)

func _refresh_leaderboard(list: VBoxContainer) -> void:
    var data: Dictionary = await Net.fetch_leaderboard(LEADERBOARD_ROWS)
    if not is_instance_valid(list) or not list.is_inside_tree():
        return
    if data.has("error"):
        if leaderboard_cache.is_empty():
            _fill_leaderboard(list, data)
        return
    leaderboard_cache = data
    _fill_leaderboard(list, data)

func _fill_leaderboard(list: VBoxContainer, data: Dictionary) -> void:
    for child in list.get_children():
        list.remove_child(child)
        child.queue_free()
    if data.has("error"):
        list.add_child(_plain("Ranking indisponível sem conexão.", 13, DIM))
        return
    var players: Array = data.get("players", []).slice(0, leaderboard_rows)
    if players.is_empty():
        list.add_child(_plain("Ninguém pontuou ainda. Seja o primeiro!", 13, DIM))
        return
    var me = data.get("me")
    # A cached "me" line belongs to whoever was logged in when it was fetched.
    if not (me is Dictionary) or not Net.is_logged_in() or str(me.get("name", "")) != str(Net.profile.get("name", "")):
        me = null
    var my_name := str(me.get("name", "")) if me is Dictionary else ""
    var me_listed := false
    for entry in players:
        var mine: bool = not my_name.is_empty() and str(entry.get("name", "")) == my_name
        me_listed = me_listed or mine
        list.add_child(_leaderboard_row(entry, mine))
    if me is Dictionary and not me_listed:
        var line := ColorRect.new()
        line.custom_minimum_size.y = 1
        line.color = LINE
        list.add_child(line)
        list.add_child(_leaderboard_row(me, true))

## "#1  Nome   Patente   1.250 XP" with medal colours for the podium.
func _leaderboard_row(entry: Dictionary, mine: bool) -> PanelContainer:
    var row := PanelContainer.new()
    row.name = "LeaderRow_" + str(entry.get("name", ""))
    var box := _box(Color(ACCENT, 0.14) if mine else Color(1, 1, 1, 0.025), ACCENT if mine else Color.TRANSPARENT, 1 if mine else 0, 3)
    box.content_margin_left = 10
    box.content_margin_right = 12
    box.content_margin_top = 1 if leaderboard_compact else 5
    box.content_margin_bottom = 1 if leaderboard_compact else 5
    row.add_theme_stylebox_override("panel", box)
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", 10)
    row.add_child(line)
    var board_position = entry.get("position")
    var place := int(board_position) if board_position != null else 0
    var place_text := "#%d" % place if place > 0 else "100+"
    var place_color: Color = MEDALS[place - 1] if place >= 1 and place <= 3 else DIM
    var place_label := _plain(place_text, 13 if leaderboard_compact else 15, place_color, title_font)
    place_label.custom_minimum_size.x = 44
    line.add_child(place_label)
    line.add_child(_avatar_badge(str(entry.get("name", "")), true, 20.0 if leaderboard_compact else 26.0, int(entry.get("avatar", 0)), false))
    var names := VBoxContainer.new()
    names.add_theme_constant_override("separation", -2)
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.add_child(names)
    names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var player := _plain(str(entry.get("name", "")) + ("  (você)" if mine else ""), 13 if leaderboard_compact else 15, ACCENT if mine else TEXT, title_font)
    player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    player.clip_text = true
    names.add_child(player)
    if not leaderboard_compact:
        names.add_child(_plain("%s  •  %d vitória%s" % [str(entry.get("rank", "")).to_upper(), int(entry.get("wins", 0)), "" if int(entry.get("wins", 0)) == 1 else "s"], 10, DIM, caps_font))
    var xp := _plain(_thousands(int(entry.get("xp", 0))) + " XP", 12 if leaderboard_compact else 14, TEXT if place >= 1 and place <= 3 else MUTED, title_font)
    xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    line.add_child(xp)
    return row

## 12500 -> "12.500"
func _thousands(value: int) -> String:
    var digits := str(absi(value))
    var out := ""
    while digits.length() > 3:
        out = "." + digits.right(3) + out
        digits = digits.left(digits.length() - 3)
    return ("-" if value < 0 else "") + digits + out

## Staggered fade-in of the menu entries.
func _animate_in(nodes: Array) -> void:
    var delay := 0.0
    for node in nodes:
        if not node is CanvasItem:
            continue
        node.modulate.a = 0.0
        var tween := create_tween()
        tween.tween_interval(delay)
        tween.tween_property(node, "modulate:a", 1.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
        delay += 0.035

# --------------------------------------------------------- shared style ---

func _box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = border
    box.set_border_width_all(border_width)
    box.set_corner_radius_all(radius)
    box.anti_aliasing = true
    return box

## Inter (variable, 100–900) for the whole menu; the project default font is the same file.
func _build_fonts() -> void:
    var inter := load(INTER_PATH) as Font
    if inter == null:
        var fallback := SystemFont.new()
        fallback.font_names = PackedStringArray(["Inter", "Segoe UI", "Roboto", "Arial"])
        inter = fallback
    base_font = _weighted(inter, 400)
    semi_font = _weighted(inter, 600)
    title_font = _weighted(inter, 700)
    caps_font = _weighted(inter, 600)
    caps_font.spacing_glyph = 1
    code_font = _weighted(inter, 700)
    code_font.spacing_glyph = 8

func _weighted(base: Font, weight_value: int) -> FontVariation:
    var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
    var font := FontVariation.new()
    font.base_font = base
    font.variation_opentype = {weight: weight_value}
    return font

## Defaults for the plain controls used on the other screens.
func _build_theme() -> Theme:
    var t := Theme.new()
    t.default_font = base_font
    t.default_font_size = 16
    t.set_color("font_color", "Label", Color("#d6dfd9"))
    var field := _box(Color(0.02, 0.03, 0.035, 0.75), Color(1,1,1,0.12), 1, 4)
    for side in ["left","right"]:
        field.set("content_margin_" + side, 14)
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
        var normal := _box(Color(1,1,1,0.06), Color(1,1,1,0.12), 1, 4)
        for side in ["left","right"]:
            normal.set("content_margin_" + side, 14)
        for side in ["top","bottom"]:
            normal.set("content_margin_" + side, 6)
        var hover := normal.duplicate() as StyleBoxFlat
        hover.bg_color = Color(ACCENT, 0.16)
        hover.border_color = ACCENT
        var pressed := normal.duplicate() as StyleBoxFlat
        pressed.bg_color = Color(ACCENT, 0.28)
        pressed.border_color = ACCENT
        var disabled := normal.duplicate() as StyleBoxFlat
        disabled.bg_color = Color(1,1,1,0.03)
        disabled.border_color = Color(1,1,1,0.05)
        t.set_stylebox("normal", type, normal)
        t.set_stylebox("hover", type, hover)
        t.set_stylebox("pressed", type, pressed)
        t.set_stylebox("focus", type, hover)
        t.set_stylebox("disabled", type, disabled)
        t.set_color("font_color", type, TEXT)
        t.set_color("font_hover_color", type, Color.WHITE)
        t.set_color("font_disabled_color", type, DIM)
    t.set_color("font_color", "CheckButton", TEXT)
    t.set_color("font_hover_color", "CheckButton", Color.WHITE)
    t.set_color("font_pressed_color", "CheckButton", TEXT)
    var popup := _box(Color("#10171a"), Color(1,1,1,0.12), 1, 4)
    t.set_stylebox("panel", "PopupMenu", popup)
    t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.2), Color.TRANSPARENT, 0, 2))
    t.set_stylebox("slider", "HSlider", _box(Color(1,1,1,0.10), Color.TRANSPARENT, 0, 2))
    t.set_stylebox("grabber_area", "HSlider", _box(ACCENT, Color.TRANSPARENT, 0, 2))
    t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT.lightened(0.15), Color.TRANSPARENT, 0, 2))
    for bar_type in ["VScrollBar", "HScrollBar"]:
        t.set_stylebox("scroll", bar_type, _box(Color(0,0,0,0.0), Color.TRANSPARENT, 0, 3))
        t.set_stylebox("grabber", bar_type, _box(Color(1,1,1,0.14), Color.TRANSPARENT, 0, 3))
        t.set_stylebox("grabber_highlight", bar_type, _box(Color(ACCENT, 0.6), Color.TRANSPARENT, 0, 3))
        t.set_stylebox("grabber_pressed", bar_type, _box(ACCENT, Color.TRANSPARENT, 0, 3))
    return t

func _build_background() -> void:
    var shader := Shader.new()
    shader.code = BACKGROUND_SHADER
    var shader_material := ShaderMaterial.new()
    shader_material.shader = shader
    var background := ColorRect.new()
    background.name = "MenuBackground"
    background.color = Color("#0b1013")
    background.material = shader_material
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var texture := load("res://icon.png") as Texture2D
    if texture != null:
        var mark := TextureRect.new()
        mark.name = "Watermark"
        mark.texture = texture
        mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        mark.modulate = Color(1, 1, 1, 0.045)
        mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(mark)
        mark.anchor_left = 0.48
        mark.anchor_right = 1.08
        mark.anchor_top = 0.05
        mark.anchor_bottom = 1.05
    embers = CPUParticles2D.new()
    embers.name = "Embers"
    embers.amount = 70
    embers.lifetime = 8.0
    embers.preprocess = 8.0
    embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
    embers.direction = Vector2(0.2, -1)
    embers.spread = 18.0
    embers.gravity = Vector2(4, -8)
    embers.initial_velocity_min = 22.0
    embers.initial_velocity_max = 60.0
    embers.scale_amount_min = 1.2
    embers.scale_amount_max = 3.2
    var ramp := Gradient.new()
    ramp.colors = PackedColorArray([Color(1, 0.7, 0.35, 0.0), Color(1, 0.7, 0.35, 0.9), Color(1, 0.42, 0.15, 0.55), Color(1, 0.3, 0.1, 0.0)])
    ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
    embers.color_ramp = ramp
    var glow := CanvasItemMaterial.new()
    glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    embers.material = glow
    add_child(embers)
    embers.position = Vector2(size.x * 0.5, size.y + 12)
    embers.emission_rect_extents = Vector2(size.x * 0.55, 8)

func _set_page_width(width: float) -> void:
    page_width = width
    if menu_card:
        menu_card.custom_minimum_size.x = minf(width, get_viewport_rect().size.x - 48)

func _show_characters() -> void:
    _clear()
    _set_page_width(940.0)
    _label("PERSONAGENS", 28, Color("#f0f2e9"))
    _label("Escolha seu personagem. A seleção fica salva para a próxima partida.", 15)
    var cards := HFlowContainer.new()
    cards.name = "CharacterCards"
    cards.add_theme_constant_override("h_separation", 20)
    cards.add_theme_constant_override("v_separation", 16)
    content.add_child(cards)
    var selected_id := CharacterRegistry.load_selection()
    for definition in CharacterRegistry.all_characters():
        var card := CharacterCard.new()
        card.name = "CharacterCard_" + definition.id
        card.definition = definition
        card.selected = definition.id == selected_id
        card.selection_requested.connect(_select_character)
        cards.add_child(card)
    selection_feedback = _label("", 14)
    selection_feedback.name = "SelectionFeedback"
    _button("Voltar", "BackButton", _show_main)

func _select_character(id: String) -> void:
    var error := CharacterRegistry.select_character(id)
    if error != OK:
        selection_feedback.text = "Não foi possível salvar a seleção. A escolha anterior foi preservada."
        return
    _show_characters()

func _start_match() -> void:
    Net.leave() # offline practice match
    var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
    if error != OK:
        _label("Não foi possível iniciar a partida.",15)

# ------------------------------------------------- card screen pieces ---

const ONLINE_PAGE_WIDTH := 560.0

## Small accent kicker + big title (+ optional subtitle), centred.
func _screen_header(kicker: String, title: String, subtitle: String = "") -> void:
    var head := VBoxContainer.new()
    head.name = "ScreenHeader"
    head.add_theme_constant_override("separation", 2)
    content.add_child(head)
    for part in [[kicker.to_upper(), 12, ACCENT, caps_font], [title, 30, TEXT, title_font]]:
        var label := _plain(part[0], part[1], part[2], part[3])
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        head.add_child(label)
    if not subtitle.is_empty():
        var sub := _wrap(subtitle, 14, MUTED)
        sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        head.add_child(sub)

## Wrapping, left-aligned paragraph.
func _wrap(text: String, font_size: int, color: Color, font: Font = null) -> Label:
    var label := _plain(text, font_size, color, font)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_constant_override("line_spacing", 3)
    return label

## Rounded panel with padding; returns the inner VBox.
func _card(parent: Node, card_name: String, bg: Color = Color(1, 1, 1, 0.035), border: Color = LINE, pad: int = 18) -> VBoxContainer:
    var panel := PanelContainer.new()
    panel.name = card_name
    var box := _box(bg, border, 1, 10)
    box.content_margin_left = pad
    box.content_margin_right = pad
    box.content_margin_top = pad - 4
    box.content_margin_bottom = pad - 2
    panel.add_theme_stylebox_override("panel", box)
    parent.add_child(panel)
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 10)
    panel.add_child(stack)
    return stack

## Small rounded tag ("8 JOGADORES", "SEU PERSONAGEM"...).
func _pill(text: String, color: Color, filled: bool = false) -> PanelContainer:
    var pill := PanelContainer.new()
    var box := _box(color if filled else Color(color, 0.14), Color.TRANSPARENT, 0, 10)
    box.content_margin_left = 9
    box.content_margin_right = 9
    box.content_margin_top = 3
    box.content_margin_bottom = 3
    pill.add_theme_stylebox_override("panel", box)
    pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pill.add_child(_plain(text.to_upper(), 11, Color("#1a1208") if filled else color, caps_font))
    return pill

## Caps caption on the left, optional control on the right.
func _section_title(text: String, right: Control = null) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    content.add_child(row)
    var label := _plain(text.to_upper(), 12, MUTED, caps_font)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(label)
    if right != null:
        row.add_child(right)
    return row

## "──── TEXT ────" separator.
func _divider_text(text: String) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    content.add_child(row)
    for i in 3:
        if i == 1:
            row.add_child(_plain(text.to_upper(), 11, DIM, caps_font))
            continue
        var line := ColorRect.new()
        line.color = LINE
        line.custom_minimum_size.y = 1
        line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        line.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(line)

## Low-emphasis button (Voltar, Atualizar): no fill until hovered.
func _ghost(button: Button, height: float = 44.0) -> Button:
    button.custom_minimum_size.y = height
    for state in ["normal","hover","pressed","focus","disabled"]:
        var box := _box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.0), 1, 8)
        box.content_margin_left = 14
        box.content_margin_right = 14
        if state == "hover" or state == "focus":
            box.bg_color = Color(1, 1, 1, 0.05)
            box.border_color = LINE
        elif state == "pressed":
            box.bg_color = Color(1, 1, 1, 0.09)
        button.add_theme_stylebox_override(state, box)
    button.add_theme_color_override("font_color", MUTED)
    for state in ["font_hover_color","font_pressed_color","font_focus_color"]:
        button.add_theme_color_override(state, TEXT)
    return button

## Mode summary: name + capacity tag, description and the key rules as a list.
func _mode_card(title: String, tag: String, description: String, facts: Array = [], fact_color: Color = TEXT) -> void:
    var stack := _card(content, "ModeCard")
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 10)
    stack.add_child(top)
    var name_label := _plain(title, 18, TEXT, title_font)
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(name_label)
    top.add_child(_pill(tag, ACCENT))
    stack.add_child(_wrap(description, 14, MUTED))
    if facts.is_empty():
        return
    var list := VBoxContainer.new()
    list.add_theme_constant_override("separation", 6)
    stack.add_child(list)
    for fact in facts:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 10)
        list.add_child(row)
        var dot := Panel.new()
        dot.custom_minimum_size = Vector2(6, 6)
        dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
        dot.add_theme_stylebox_override("panel", _box(ACCENT, Color.TRANSPARENT, 0, 3))
        row.add_child(dot)
        row.add_child(_wrap(str(fact), 13, fact_color))

## "Jogando como" strip: initial avatar, name, rank tag.
func _player_strip() -> void:
    var panel := PanelContainer.new()
    panel.name = "PlayerStrip"
    var box := _box(Color(0, 0, 0, 0.28), LINE, 1, 10)
    box.content_margin_left = 12
    box.content_margin_right = 14
    box.content_margin_top = 10
    box.content_margin_bottom = 10
    panel.add_theme_stylebox_override("panel", box)
    content.add_child(panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    panel.add_child(row)
    var player_name := str(Net.profile.get("name", ""))
    var avatar := PanelContainer.new()
    avatar.custom_minimum_size = Vector2(38, 38)
    avatar.add_theme_stylebox_override("panel", _box(Color(ACCENT, 0.14), Color(ACCENT, 0.6), 1, 19))
    row.add_child(avatar)
    var initial := _plain(player_name.left(1).to_upper() if not player_name.is_empty() else "?", 17, ACCENT, title_font)
    initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    avatar.add_child(initial)
    var names := VBoxContainer.new()
    names.add_theme_constant_override("separation", -2)
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    names.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_child(names)
    names.add_child(_plain("JOGANDO COMO", 10, DIM, caps_font))
    names.add_child(_plain(player_name, 16, TEXT, semi_font))
    row.add_child(_pill(str(Net.profile.get("rank", "Recruta")), ACCENT))

## Header + login check + tabs shared by the three online tabs. False = sent to login.
func _online_screen(active: int) -> bool:
    _clear()
    _set_page_width(ONLINE_PAGE_WIDTH)
    _screen_header("Jogar online", "Multiplayer")
    if not Net.is_logged_in():
        _show_login(false,"Entre na sua conta para jogar online.")
        return false
    _online_tabs(active)
    return true

## Segmented control at the top of the online screen.
func _online_tabs(active: int) -> void:
    var bar := PanelContainer.new()
    bar.name = "OnlineTabs"
    var bg := _box(Color(0, 0, 0, 0.35), LINE, 1, 10)
    bg.set_content_margin_all(4)
    bar.add_theme_stylebox_override("panel", bg)
    content.add_child(bar)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    bar.add_child(row)
    var titles := ["Eliminatória","Mata-mata","Equipes","Sobrevivência"]
    var names := ["TabElimination","TabDeathmatch","TabTeams","TabSurvival"]
    var actions := [_show_multiplayer,_show_deathmatch_tab,_show_teams_tab,_show_survival_tab]
    for i in titles.size():
        var on: bool = i == active
        var tab := Button.new()
        tab.name = names[i]
        tab.text = titles[i]
        tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tab.custom_minimum_size.y = 38
        tab.add_theme_font_override("font", semi_font)
        tab.add_theme_font_size_override("font_size", 14)
        for state in ["normal","hover","pressed","focus"]:
            var box := _box(ACCENT if on else Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 7)
            if not on and (state == "hover" or state == "focus"):
                box.bg_color = Color(1, 1, 1, 0.06)
            elif not on and state == "pressed":
                box.bg_color = Color(1, 1, 1, 0.10)
            tab.add_theme_stylebox_override(state, box)
        tab.add_theme_color_override("font_color", Color("#1a1208") if on else MUTED)
        for state in ["font_hover_color","font_pressed_color","font_focus_color"]:
            tab.add_theme_color_override(state, Color("#1a1208") if on else TEXT)
        if not on:
            tab.pressed.connect(actions[i])
        row.add_child(tab)

func _status_note() -> void:
    var note := _label("",14,MUTED)
    note.name = "MultiplayerStatus"
    note.visible = false # nothing writes here on the tabs; avoids an empty gap
    status = note

func _back_row() -> void:
    _ghost(_button("Voltar","BackButton",_show_main))

func _show_multiplayer() -> void:
    if not _online_screen(0):
        return
    _mode_card("Eliminatória", "8 jogadores",
        "Entre numa sala e confirme que está pronto. O primeiro jogador da sala (líder) inicia quando todos estiverem prontos.",
        ["Vagas livres são completadas com bots", "Uma vida só: vence o último vivo",
        "Loja nos primeiros 20 s: comece com $800 e compre armas (B)"])
    var xp_head := _section_title("Recompensas de XP")
    xp_head.name = "XpTitle"
    var rewards := HFlowContainer.new()
    rewards.name = "XpRewards"
    rewards.add_theme_constant_override("h_separation", 6)
    rewards.add_theme_constant_override("v_separation", 6)
    content.add_child(rewards)
    for reward in [["Abate", "+100"], ["Bot", "+25"], ["Na cabeça", "+15"], ["Vitória", "+150"], ["Partida", "+20"]]:
        var chip := PanelContainer.new()
        var box := _box(Color(1, 1, 1, 0.05), LINE, 1, 8)
        box.content_margin_left = 10
        box.content_margin_right = 10
        box.content_margin_top = 5
        box.content_margin_bottom = 5
        chip.add_theme_stylebox_override("panel", box)
        var line := HBoxContainer.new()
        line.add_theme_constant_override("separation", 6)
        chip.add_child(line)
        line.add_child(_plain(reward[0], 13, MUTED))
        line.add_child(_plain(reward[1], 13, ACCENT, semi_font))
        rewards.add_child(chip)
    _player_strip()
    _status_note()
    var find := _button("Procurar sala","FindMatchButton",func():
        _show_lobby(str(Net.profile.get("name","")))
    ,true)
    find.grab_focus()
    _back_row()

# ----------------------------------------------------------- mata-mata ---

## Aba "Mata-mata": salas públicas de 8, todos contra todos, renasce ao morrer.
func _show_deathmatch_tab() -> void:
    if not _online_screen(1):
        return
    _mode_card("Mata-mata", "8 jogadores",
        "Todos contra todos sem pausa: morreu, volta em 3 segundos com uma pistola, longe de quem está vivo. O primeiro a chegar a 15 abates vence — ou quem tiver mais abates quando os 6 minutos acabarem.",
        ["Pistola grátis; a loja abre por 20 s no início e a cada renascimento",
        "Morrer não tira XP aqui; cada abate vale o mesmo da Eliminatória",
        "Proteção de 1,5 s ao renascer (acaba se você atirar)",
        "Vagas livres são completadas com bots"], Color("#ff9a6a"))
    _player_strip()
    _status_note()
    var find := _button("Procurar sala","FindDeathmatchButton",func():
        _show_lobby(str(Net.profile.get("name","")), true)
    ,true)
    find.grab_focus()
    _back_row()

# ------------------------------------------------------- sobrevivência ---

## Aba "Sobrevivência": mundo aberto com zumbis, até 16 jogadores, sem sala de espera.
func _show_survival_tab() -> void:
    if not _online_screen(3):
        return
    _mode_card("Sobrevivência", "Até 16 jogadores",
        "Mundo aberto infestado de zumbis. Você nasce no mato com quase nada: revista casas, mercados, o hospital e a base militar atrás de comida, água, remédios e armas. Corte árvores, quebre pedras e desmonte carros para fabricar bandagens, machado, mochila e munição.",
        ["Fome e sede caem com o tempo; tiros atraem zumbis",
        "Mordida infecta: sem vacina em 2 minutos você vira zumbi",
        "Ao morrer, suas coisas ficam numa mochila no chão",
        "Ao sair, seu personagem fica dormindo no mundo"], Color("#e6c98a"))
    _player_strip()
    _status_note()
    var refresh := _ghost(_button("Atualizar","RefreshWorldsButton",_show_survival_tab), 32)
    content.remove_child(refresh)
    refresh.add_theme_font_size_override("font_size", 13)
    _section_title("Mundos ativos", refresh)
    var hint := _wrap("Cada mundo guarda o seu próprio personagem.", 12, DIM)
    content.add_child(hint)
    var list := VBoxContainer.new()
    list.name = "SurvivalWorlds"
    list.add_theme_constant_override("separation",8)
    content.add_child(list)
    list.add_child(_wrap("Carregando mundos...", 14, MUTED))
    _back_row()
    _fill_survival_worlds(list)

## Preenche a lista: mundos com gente online, o mundo do seu personagem e um mundo vazio para começar do zero.
func _fill_survival_worlds(list: VBoxContainer) -> void:
    var data: Dictionary = await Net.fetch_survival_worlds()
    if not is_instance_valid(list):
        return # saiu da tela enquanto carregava
    for child in list.get_children():
        child.queue_free()
    var worlds: Array = data.get("worlds", [])
    if worlds.is_empty():
        list.add_child(_wrap(str(data.get("error", "Nenhum mundo disponível agora.")), 14, Color("#f0a08a")))
        _world_button(list, "Entrar num mundo com vaga", "O servidor escolhe um mundo com espaço", "", "", true, false)
        return
    var shown := 0
    var fresh_shown := false
    for w in worlds:
        var online := int(w.get("online",0))
        var capacity := int(w.get("capacity",16))
        var mine := bool(w.get("mine",false))
        var fresh := online == 0 and not mine
        if fresh and fresh_shown:
            continue # só um mundo vazio na lista
        fresh_shown = fresh_shown or fresh
        var title := "Mundo %d" % int(w.get("number",0))
        var detail := "%d/%d online  ·  dia %d" % [online, capacity, int(w.get("day",1))]
        var tag := ""
        if mine:
            tag = "Seu personagem"
        elif fresh:
            detail = "Vazio — começar do zero"
            tag = "Novo"
        var full := online >= capacity
        if full:
            tag = "Cheio"
        _world_button(list, title, detail, tag, str(w.get("id","")), not full, mine)
        shown += 1
    if shown == 0:
        _world_button(list, "Entrar num mundo com vaga", "O servidor escolhe um mundo com espaço", "", "", true, false)

## One world as a wide card: name + details on the left, tag and arrow on the right.
func _world_button(list: VBoxContainer, title: String, detail: String, tag: String, world_id: String, enabled: bool, mine: bool) -> void:
    var b := Button.new()
    b.name = "World_" + world_id.replace(":", "_")
    b.custom_minimum_size.y = 62
    b.disabled = not enabled
    b.pressed.connect(func(): _join_survival(world_id))
    for state in ["normal","hover","pressed","focus","disabled"]:
        var box := _box(Color(ACCENT, 0.09) if mine else Color(1, 1, 1, 0.04), Color(ACCENT, 0.55) if mine else LINE, 1, 10)
        if state == "hover" or state == "focus":
            box.bg_color = Color(ACCENT, 0.15)
            box.border_color = ACCENT
        elif state == "pressed":
            box.bg_color = Color(ACCENT, 0.24)
            box.border_color = ACCENT
        elif state == "disabled":
            box.bg_color = Color(1, 1, 1, 0.02)
            box.border_color = Color(1, 1, 1, 0.05)
        b.add_theme_stylebox_override(state, box)
    list.add_child(b)
    var pad := MarginContainer.new()
    pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for edge in ["left","right"]:
        pad.add_theme_constant_override("margin_" + edge, 16)
    b.add_child(pad)
    pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_theme_constant_override("separation", 12)
    pad.add_child(row)
    var words := VBoxContainer.new()
    words.mouse_filter = Control.MOUSE_FILTER_IGNORE
    words.alignment = BoxContainer.ALIGNMENT_CENTER
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    words.add_theme_constant_override("separation", 0)
    row.add_child(words)
    words.add_child(_plain(title, 16, TEXT if enabled else DIM, semi_font))
    words.add_child(_plain(detail, 12, MUTED if enabled else DIM))
    if not tag.is_empty():
        row.add_child(_pill(tag, ACCENT if enabled else DIM, mine))
    var arrow := _plain("›", 24, ACCENT if mine else MUTED, semi_font)
    arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    arrow.visible = enabled
    row.add_child(arrow)

func _join_survival(world_id: String) -> void:
    _clear()
    _label("Sobrevivência",28)
    status = _label("Entrando no mundo..." if not world_id.is_empty() else "Procurando um mundo com vaga...",17)
    status.name = "MultiplayerStatus"
    _button("Cancelar","CancelButton",func():
        _disconnect_net()
        Net.leave()
        _show_survival_tab()
    )
    _connect_net()
    if Net.find_survival(str(Net.profile.get("name","")), world_id) != OK:
        _on_connection_lost("Não foi possível conectar ao servidor.")

# ------------------------------------------------- custom team rooms ---

## "Equipes" tab: create a room or join a friend's with the code.
func _show_teams_tab(message: String = "") -> void:
    if not _online_screen(2):
        return
    _mode_card("Equipes", "2x2 ou 4x4",
        "Partida personalizada em equipes. Crie uma sala e mande o código para seus amigos.",
        ["Vagas livres podem ser completadas com bots", "Vence a equipe que eliminar a outra",
        "Loja nos primeiros 20 s: comece com $800 e compre armas (B)"])
    var feedback := _label(message,14,Color("#f0a08a"))
    feedback.name = "PartyFeedback"
    feedback.visible = not message.is_empty()
    _button("Criar sala","CreatePartyButton",func(): _connect_party(""),true).grab_focus()
    _divider_text("ou entre na sala de um amigo")
    var row := HBoxContainer.new()
    row.name = "JoinRow"
    row.add_theme_constant_override("separation", 8)
    content.add_child(row)
    var code := _field("Código da sala (ex.: K7Q2M)","PartyCodeField")
    content.remove_child(code)
    code.max_length = 5
    code.custom_minimum_size.y = 48
    code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(code)
    var join := _button("Entrar","JoinPartyButton",func():
        if code.text.strip_edges().length() != 5:
            feedback.text = "O código tem 5 letras/números."
            feedback.visible = true
            return
        _connect_party(code.text)
    )
    content.remove_child(join)
    join.custom_minimum_size.x = 120
    row.add_child(join)
    code.text_submitted.connect(func(_text): join.pressed.emit())
    _back_row()

## Empty code creates a new room.
func _connect_party(code: String) -> void:
    _clear()
    _label("Sala personalizada",28)
    status = _label("Criando sala..." if code.is_empty() else "Entrando na sala %s..." % code.strip_edges().to_upper(),17)
    status.name = "MultiplayerStatus"
    _button("Cancelar","CancelButton",_leave_party)
    _connect_net()
    var error: Error = Net.create_party() if code.is_empty() else Net.join_party(code)
    if error != OK:
        _on_connection_lost("Não foi possível conectar ao servidor.")

func _leave_party() -> void:
    var was_team_room := bool(Net.party_info.get("party", true))
    _disconnect_net()
    Net.leave()
    if was_team_room:
        _show_teams_tab()
    else:
        _show_multiplayer()

func _on_party_error(message: String) -> void:
    _disconnect_net()
    Net.leave()
    if _joining_elimination:
        _joining_elimination = false
        _show_multiplayer()
        if status != null:
            status.text = message
        return
    _show_teams_tab(message)

var _joining_elimination := false

## Convite aceito para uma eliminatória: entra na sala de espera do amigo.
func _connect_elimination(room_id: String) -> void:
    _clear()
    _label("Eliminatória",28)
    status = _label("Entrando na sala do seu amigo...",17)
    status.name = "MultiplayerStatus"
    _button("Cancelar","CancelButton",func():
        _joining_elimination = false
        _disconnect_net()
        Net.leave()
        _show_multiplayer())
    _joining_elimination = true
    _connect_net()
    if Net.join_elimination(room_id) != OK:
        _joining_elimination = false
        _on_connection_lost("Não foi possível conectar ao servidor.")

func _on_party_notice(message: String) -> void:
    var note := content.get_node_or_null("PartyNote") as Label
    if note:
        note.text = message
        note.visible = not message.is_empty()

## Room screen (public elimination or team room), rebuilt on every update.
## Everyone confirms "ready"; the first player in the room (leader) starts.
func _on_party_updated(info: Dictionary) -> void:
    _joining_elimination = false
    _clear()
    var team_room := bool(info.get("party",true))
    _set_page_width(720.0 if team_room else 520.0)
    var leader := Net.is_party_leader()
    var team_size := int(info.get("size",2))
    var bots := bool(info.get("bots",true))
    var team_names: Array = info.get("teams",["Alfa","Bravo"])
    if not team_room:
        _show_elimination_room(info, leader)
        return
    _screen_header("Sala personalizada", "Equipes %dx%d" % [team_size,team_size])
    # Invite code: caption + big spaced code on the left, copy on the right.
    var code_card := PanelContainer.new()
    code_card.name = "PartyCodeCard"
    var code_box := _box(Color(0, 0, 0, 0.32), Color(ACCENT, 0.45), 1, 10)
    code_box.content_margin_left = 18
    code_box.content_margin_right = 12
    code_box.content_margin_top = 10
    code_box.content_margin_bottom = 10
    code_card.add_theme_stylebox_override("panel", code_box)
    content.add_child(code_card)
    var code_row := HBoxContainer.new()
    code_row.add_theme_constant_override("separation",12)
    code_card.add_child(code_row)
    var code_words := VBoxContainer.new()
    code_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    code_words.add_theme_constant_override("separation", 0)
    code_row.add_child(code_words)
    code_words.add_child(_plain("CÓDIGO DA SALA", 11, MUTED, caps_font))
    var code_label := _plain(Net.party_code, 30, Color("#ffd27a"), code_font)
    code_label.name = "PartyCode"
    code_words.add_child(code_label)
    var copy := _button("Copiar","CopyCodeButton",Callable())
    content.remove_child(copy)
    copy.custom_minimum_size = Vector2(110,44)
    copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    copy.pressed.connect(func():
        DisplayServer.clipboard_set(Net.party_code)
        copy.text = "Copiado!")
    code_row.add_child(copy)
    var invite_hint := _wrap("Seus amigos entram em Jogar online › Equipes › Entrar com o código.", 12, DIM)
    invite_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    content.add_child(invite_hint)
    # Mode and bots: the leader edits, everyone else sees the current choice.
    if leader:
        var settings_row := HBoxContainer.new()
        settings_row.name = "PartySettings"
        settings_row.add_theme_constant_override("separation",12)
        content.add_child(settings_row)
        var mode := OptionButton.new()
        mode.name = "PartyModeSelect"
        mode.add_item("2 contra 2")
        mode.add_item("4 contra 4")
        mode.select(0 if team_size == 2 else 1)
        mode.custom_minimum_size = Vector2(170,42)
        mode.add_theme_font_override("font", semi_font)
        settings_row.add_child(mode)
        var fill := CheckButton.new()
        fill.name = "PartyBotsToggle"
        fill.text = "Completar vagas com bots"
        fill.button_pressed = bots
        fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        fill.alignment = HORIZONTAL_ALIGNMENT_LEFT
        settings_row.add_child(fill)
        mode.item_selected.connect(func(index: int): Net.party_configure(2 if index == 0 else 4, fill.button_pressed))
        fill.toggled.connect(func(on: bool): Net.party_configure(team_size, on))
    else:
        var mode_info := HBoxContainer.new()
        mode_info.alignment = BoxContainer.ALIGNMENT_CENTER
        mode_info.add_theme_constant_override("separation", 8)
        content.add_child(mode_info)
        mode_info.add_child(_pill("Modo %dx%d" % [team_size,team_size], ACCENT))
        mode_info.add_child(_pill("Vagas com bots" if bots else "Sem bots", MUTED))
    # The two teams side by side.
    var columns := HBoxContainer.new()
    columns.name = "PartyTeams"
    columns.add_theme_constant_override("separation",16)
    content.add_child(columns)
    for team in [0,1]:
        columns.add_child(_team_column(info,team,str(team_names[team]) if team < team_names.size() else "Equipe",team_size,bots))
    _invite_friends_section()
    _ready_controls(info, leader)

## Public elimination room: one list of players with their ready state.
func _show_elimination_room(info: Dictionary, leader: bool) -> void:
    var players: Array = info.get("players",[])
    var capacity := int(info.get("capacity",8))
    var deathmatch := str(info.get("mode","elim")) == "dm"
    var detail := "%d/%d jogadores  ·  vagas livres viram bots" % [players.size(),capacity]
    if deathmatch:
        detail += "  ·  %d abates para vencer" % int(info.get("goal",15))
    _screen_header("Mata-mata" if deathmatch else "Eliminatória", "Sala de espera", detail)
    var list := _card(content, "RoomPlayersCard", Color(0, 0, 0, 0.25), LINE, 16)
    list.name = "RoomPlayers"
    list.add_theme_constant_override("separation",8)
    for entry in players:
        list.add_child(_player_row(info,entry))
    for _slot in range(players.size(),capacity):
        list.add_child(_plain("—   Vaga livre  ·  bot", 14, DIM))
    _invite_friends_section() # convidar amigos para esta eliminatória (antes de começar)
    _ready_controls(info, leader)

## "★ líder / (você) / ✓ PRONTO" row used by both room screens.
func _player_row(info: Dictionary, entry: Dictionary) -> Label:
    var row := Label.new()
    var id := str(entry.get("id",""))
    var is_leader := id == str(info.get("leader",""))
    var tags := ""
    if is_leader:
        tags += "  ★ líder"
    if id == Net.my_id:
        tags += "  (você)"
    var ready_tag := "✓ pronto" if bool(entry.get("ready",false)) else "aguardando…"
    if is_leader:
        ready_tag = "inicia a partida"
    row.text = "%s  ·  %s%s  ·  %s" % [entry.get("name",""),entry.get("rank",""),tags,ready_tag]
    row.add_theme_font_size_override("font_size",14)
    row.add_theme_font_override("font",semi_font)
    row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var color := Color("#e2e9e4")
    if bool(entry.get("ready",false)):
        color = Color("#a8e08c")
    if id == Net.my_id:
        color = Color("#ffe08a")
    row.add_theme_color_override("font_color",color)
    return row

## Bottom of the room: ready toggle for players, confirm-start for the leader.
func _ready_controls(info: Dictionary, leader: bool) -> void:
    var note := _label("",14,Color("#f0a08a"))
    note.name = "PartyNote"
    note.visible = false
    var all_ready := bool(info.get("allReady",false))
    if leader:
        var waiting: Array[String] = []
        for entry in info.get("players",[]):
            if not bool(entry.get("ready",false)):
                waiting.append(str(entry.get("name","")))
        var start := _button("Iniciar partida","StartPartyButton",Net.party_start,true)
        start.disabled = not all_ready
        if all_ready:
            start.grab_focus()
            _label("Todos prontos. Você é o líder: confirme para criar a partida.",14,Color("#a8e08c"))
        else:
            _label("Aguardando confirmar pronto: " + ", ".join(waiting),14,Color("#9bad9f"))
    else:
        var confirmed := Net.is_ready()
        var toggle := _button("Cancelar pronto" if confirmed else "Estou pronto","ReadyButton",func(): Net.party_ready(not confirmed),not confirmed)
        toggle.grab_focus()
        _label("Aguardando o líder iniciar a partida..." if confirmed else "Confirme que está pronto. O líder inicia quando todos estiverem prontos.",14,Color("#9bad9f"))
    _ghost(_button("Sair da sala","LeavePartyButton",_leave_party))

func _team_column(info: Dictionary, team: int, title: String, team_size: int, bots: bool) -> PanelContainer:
    var tint := Color("#5ea8d0") if team == 0 else Color("#d07a5e")
    var panel := PanelContainer.new()
    panel.name = "Team%d" % team
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := _box(Color(tint, 0.08), Color(tint, 0.35), 1, 10)
    box.border_width_top = 3
    box.border_color = Color(tint, 0.35)
    for side in ["left","right","top","bottom"]:
        box.set("content_margin_" + side,14)
    panel.add_theme_stylebox_override("panel",box)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation",8)
    panel.add_child(column)
    var heading := _plain("EQUIPE %s" % title.to_upper(), 13, tint.lightened(0.35), caps_font)
    column.add_child(heading)
    var members := 0
    for entry in info.get("players",[]):
        if int(entry.get("team",0)) != team:
            continue
        members += 1
        var row := _player_row(info,entry)
        row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        column.add_child(row)
    for _slot in range(members,team_size):
        column.add_child(_plain("—   Vaga livre  ·  bot" if bots else "—   Vaga livre", 14, DIM))
    if Net.my_team != team:
        var switch := Button.new()
        switch.name = "JoinTeam%d" % team
        switch.text = "Entrar nesta equipe" if members < team_size else "Equipe cheia"
        switch.disabled = members >= team_size
        switch.custom_minimum_size.y = 38
        switch.pressed.connect(func(): Net.party_choose_team(team))
        column.add_child(switch)
    return panel

func _connect_net() -> void:
    Net.lobby_joined.connect(_on_lobby_joined)
    Net.lobby_updated.connect(_on_lobby_updated)
    Net.match_started.connect(_on_match_started)
    Net.connection_lost.connect(_on_connection_lost)
    Net.update_required.connect(_on_update_required)
    Net.login_required.connect(_on_login_required)
    Net.party_updated.connect(_on_party_updated)
    Net.party_error.connect(_on_party_error)
    Net.party_notice.connect(_on_party_notice)

func _show_lobby(player_name: String, deathmatch: bool = false) -> void:
    _clear()
    _label("Procurando sala de mata-mata" if deathmatch else "Procurando sala",28)
    status = _label("Conectando ao servidor...",17)
    status.name = "MultiplayerStatus"
    var players := _label("",15,Color("#9bad9f"))
    players.name = "LobbyPlayers"
    _button("Cancelar","CancelButton",func():
        _disconnect_net()
        Net.leave()
        if deathmatch:
            _show_deathmatch_tab()
        else:
            _show_multiplayer()
    )
    _connect_net()
    var opened := Net.find_deathmatch(player_name) if deathmatch else Net.find_match(player_name)
    if opened != OK:
        _on_connection_lost("Não foi possível conectar ao servidor.")

func _disconnect_net() -> void:
    for pair in [[Net.lobby_joined,_on_lobby_joined],[Net.lobby_updated,_on_lobby_updated],[Net.match_started,_on_match_started],[Net.connection_lost,_on_connection_lost],[Net.update_required,_on_update_required],[Net.login_required,_on_login_required],[Net.party_updated,_on_party_updated],[Net.party_error,_on_party_error],[Net.party_notice,_on_party_notice]]:
        if pair[0].is_connected(pair[1]):
            pair[0].disconnect(pair[1])

func _exit_tree() -> void:
    _disconnect_net()
    for pair in [[Net.friend_invite,_on_friend_invite],[Net.friends_updated,_on_friends_updated],[Net.avatar_loaded,_on_avatar_loaded]]:
        if pair[0].is_connected(pair[1]):
            pair[0].disconnect(pair[1])

# ------------------------------------------------------------- friends ---

var invite_banner: PanelContainer
var invite_label: Label
var invite_sub: Label
var invite_avatar_slot: Control
var invite_timer_bar: ProgressBar
var invite_code := ""
var friends_screen_open := false
var _invite_tween: Tween
var _invite_sound: AudioStreamPlayer
const INVITE_SHOW_SECONDS := 60.0 # o card some sozinho (o servidor guarda o convite por 2 min)
const INVITE_COOLDOWN_MS := 30000 # depois de convidar, "Convidar de novo" só após 30 s
const ONLINE_GREEN := Color("#7ccf8a")
var _invited_at: Dictionary = {} # nome do amigo -> quando foi convidado (sobrevive às atualizações da sala)
var _invite_filter := ""

# ----------------------------------------------------------- fotos e perfil ---

static var _circle_shader: Shader

## Foto recortada em círculo (shader simples: descarta fora do raio, borda suave).
func _circle_photo(texture: Texture2D, diameter: float) -> TextureRect:
    if _circle_shader == null:
        _circle_shader = Shader.new()
        _circle_shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat d = distance(UV, vec2(0.5));\n\tCOLOR = texture(TEXTURE, UV);\n\tCOLOR.a *= 1.0 - smoothstep(0.47, 0.5, d);\n}\n"
    var rect := TextureRect.new()
    rect.name = "Photo"
    rect.texture = texture
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    rect.custom_minimum_size = Vector2(diameter, diameter)
    rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var material := ShaderMaterial.new()
    material.shader = _circle_shader
    rect.material = material
    return rect

## Coloca a foto por cima das iniciais quando ela já foi baixada (e de novo
## quando o download termina: Net.avatar_loaded).
func _apply_photo(holder: Control) -> void:
    if not is_instance_valid(holder) or holder.get_node_or_null("Photo") != null:
        return
    var texture := Net.avatar_texture(str(holder.get_meta("avatar_name", "")), int(holder.get_meta("avatar_version", 0)))
    if texture == null:
        return
    var photo := _circle_photo(texture, holder.custom_minimum_size.x)
    holder.add_child(photo)
    holder.move_child(photo, mini(1, holder.get_child_count() - 1)) # acima do círculo, abaixo da bolinha de status
    var letters := holder.get_node_or_null("Initials")
    if letters != null:
        letters.visible = false

func _on_avatar_loaded(player_name: String) -> void:
    for node in get_tree().get_nodes_in_group("avatar_badges"):
        if str(node.get_meta("avatar_name", "")) == player_name:
            _apply_photo(node)

## Foto grande do cartão de perfil: anel laranja e a foto (ou a inicial).
func _profile_photo(player_name: String, version: int, diameter: float) -> Control:
    var holder := Control.new()
    holder.name = "ProfilePhoto"
    holder.custom_minimum_size = Vector2(diameter, diameter)
    holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ring := Panel.new()
    ring.add_theme_stylebox_override("panel", _box(Color(ACCENT, 0.16), ACCENT, 2, int(diameter / 2.0)))
    ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(ring)
    var initial := _plain(player_name.left(1).to_upper() if not player_name.is_empty() else "?", int(diameter * 0.46), ACCENT, title_font)
    initial.name = "Initials"
    initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    holder.add_child(initial)
    holder.set_meta("avatar_name", player_name)
    holder.set_meta("avatar_version", version)
    holder.add_to_group("avatar_badges")
    _apply_photo(holder)
    return holder

## Editar perfil: foto (do computador, recortada em quadrado e reduzida) e nick.
func _show_profile_editor(message: String = "") -> void:
    _clear()
    _set_page_width(520.0)
    var profile: Dictionary = Net.profile
    var player_name := str(profile.get("name", ""))
    _screen_header("Perfil", "Editar perfil")
    var feedback := _wrap(message, 14, ACCENT)
    feedback.name = "ProfileFeedback"
    feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    content.add_child(feedback)
    # Foto
    var photo_card := _card(content, "ProfilePhotoCard", Color(0, 0, 0, 0.25), LINE, 16)
    photo_card.add_child(_plain("FOTO", 12, ACCENT, caps_font))
    var photo_row := HBoxContainer.new()
    photo_row.add_theme_constant_override("separation", 18)
    photo_card.add_child(photo_row)
    photo_row.add_child(_profile_photo(player_name, int(profile.get("avatar", 0)), 96.0))
    var photo_actions := VBoxContainer.new()
    photo_actions.add_theme_constant_override("separation", 8)
    photo_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    photo_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    photo_row.add_child(photo_actions)
    var choose := _button("Escolher foto…", "ChoosePhotoButton", _pick_photo, true, photo_actions)
    choose.custom_minimum_size.y = 40
    var remove := _button("Remover foto", "RemovePhotoButton", Callable(), false, photo_actions)
    remove.custom_minimum_size.y = 36
    remove.disabled = int(profile.get("avatar", 0)) <= 0
    remove.pressed.connect(func():
        remove.disabled = true
        var result: String = await Net.set_avatar(PackedByteArray())
        _show_profile_editor(result))
    photo_actions.add_child(_wrap("JPG ou PNG. A foto é recortada em quadrado e aparece para seus amigos e no ranking.", 12, MUTED))
    # Nick
    var name_card := _card(content, "ProfileNameCard", Color(0, 0, 0, 0.25), LINE, 16)
    name_card.add_child(_plain("NICK", 12, ACCENT, caps_font))
    var name_row := HBoxContainer.new()
    name_row.add_theme_constant_override("separation", 8)
    name_card.add_child(name_row)
    var field := LineEdit.new()
    field.name = "NickField"
    field.text = player_name
    field.max_length = 16
    field.custom_minimum_size.y = 42
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_row.add_child(field)
    var save := _button("Salvar nick", "SaveNickButton", Callable(), true, name_row)
    save.custom_minimum_size = Vector2(150, 42)
    var renamed_at := int(profile.get("renamedAt", 0))
    var wait_h := ceili((renamed_at + 24 * 3600 * 1000 - Time.get_unix_time_from_system() * 1000.0) / 3600000.0) if renamed_at > 0 else 0
    var hint := "De 3 a 16 letras, números, ponto, traço ou sublinhado. Dá para trocar 1 vez por dia."
    if wait_h > 0:
        hint = "Você trocou de nick há pouco: a próxima troca fica liberada em %d h." % wait_h
        save.disabled = true
    name_card.add_child(_wrap(hint, 12, MUTED))
    save.pressed.connect(func():
        save.disabled = true
        var result: String = await Net.rename(field.text)
        _show_profile_editor(result))
    field.text_submitted.connect(func(_text):
        if not save.disabled:
            save.pressed.emit())
    _button("Voltar", "ProfileBackButton", _show_main)

## Abre o seletor de arquivos do sistema para escolher a foto.
func _pick_photo() -> void:
    var dialog := FileDialog.new()
    dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.use_native_dialog = true
    dialog.title = "Escolha sua foto"
    dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Imagens"])
    add_child(dialog)
    dialog.file_selected.connect(func(path: String):
        dialog.queue_free()
        _upload_photo(path))
    dialog.canceled.connect(dialog.queue_free)
    dialog.popup_centered_ratio(0.6)

## Recorta o centro em quadrado, reduz para 128 px, comprime em JPEG e envia.
func _upload_photo(path: String) -> void:
    var image := Image.load_from_file(path)
    if image == null or image.is_empty():
        _show_profile_editor("Não foi possível abrir essa imagem.")
        return
    var bytes := photo_bytes(image)
    var feedback := content.get_node_or_null("ProfileFeedback") as Label
    if feedback != null:
        feedback.text = "Enviando foto…"
    var result: String = await Net.set_avatar(bytes)
    _show_profile_editor(result)

## Foto pronta para enviar: quadrado do centro, 128×128, JPEG.
static func photo_bytes(image: Image) -> PackedByteArray:
    var side := mini(image.get_width(), image.get_height())
    var square := image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
    square.convert(Image.FORMAT_RGB8)
    square.resize(128, 128, Image.INTERPOLATE_LANCZOS)
    return square.save_jpg_to_buffer(0.85)

## Círculo com as iniciais do jogador (cor fixa por nome) e a bolinha de status.
## Com foto (versão > 0), a foto aparece por cima assim que é baixada.
func _avatar_badge(player_name: String, online: bool, diameter: float = 38.0, version: int = 0, show_status: bool = true) -> Control:
    var holder := Control.new()
    holder.custom_minimum_size = Vector2(diameter, diameter)
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var circle := PanelContainer.new()
    var hue := float(absi(hash(player_name)) % 360) / 360.0
    circle.add_theme_stylebox_override("panel", _box(Color.from_hsv(hue, 0.42, 0.52 if online else 0.3), Color(1, 1, 1, 0.12), 1, int(diameter / 2.0)))
    circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(circle)
    var initials := player_name.substr(0, 2).to_upper() if not player_name.is_empty() else "?"
    var letters := _plain(initials, int(diameter * 0.36), TEXT if online else MUTED, semi_font)
    letters.name = "Initials"
    letters.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    letters.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    letters.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    holder.add_child(letters)
    var dot := Panel.new()
    var dot_size := maxf(9.0, diameter * 0.28)
    dot.add_theme_stylebox_override("panel", _box(ONLINE_GREEN if online else DIM, Color(0.04, 0.06, 0.07), 2, int(dot_size / 2.0)))
    dot.size = Vector2(dot_size, dot_size)
    dot.position = Vector2(diameter - dot_size + 1, diameter - dot_size + 1)
    dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
    dot.visible = show_status
    holder.add_child(dot)
    holder.set_meta("avatar_name", player_name)
    holder.set_meta("avatar_version", version)
    holder.add_to_group("avatar_badges")
    _apply_photo(holder)
    return holder

## Card de convite recebido: entra deslizando no canto, mostra quem convidou,
## a sala, uma barra de tempo e [Entrar na sala] [Recusar].
func _build_invite_banner() -> void:
    invite_banner = PanelContainer.new()
    invite_banner.name = "InviteBanner"
    invite_banner.visible = false
    var box := _box(Color(0.05, 0.075, 0.085, 0.97), Color(ACCENT, 0.7), 1, 12)
    box.border_width_left = 4
    box.shadow_color = Color(0, 0, 0, 0.55)
    box.shadow_size = 18
    for side in ["left","right","top","bottom"]:
        box.set("content_margin_" + side, 16)
    invite_banner.add_theme_stylebox_override("panel", box)
    add_child(invite_banner)
    invite_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    invite_banner.offset_left = -404
    invite_banner.offset_right = -24
    invite_banner.offset_top = 24
    invite_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 12)
    invite_banner.add_child(stack)
    var head := HBoxContainer.new()
    head.add_theme_constant_override("separation", 12)
    stack.add_child(head)
    invite_avatar_slot = Control.new()
    invite_avatar_slot.custom_minimum_size = Vector2(46, 46)
    invite_avatar_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(invite_avatar_slot)
    var words := VBoxContainer.new()
    words.add_theme_constant_override("separation", 1)
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(words)
    words.add_child(_plain("CONVITE PARA SALA", 11, ACCENT, caps_font))
    invite_label = _plain("", 17, TEXT, semi_font)
    invite_label.name = "InviteText"
    invite_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    words.add_child(invite_label)
    invite_sub = _plain("", 13, MUTED)
    words.add_child(invite_sub)
    invite_timer_bar = ProgressBar.new()
    invite_timer_bar.name = "InviteTimer"
    invite_timer_bar.show_percentage = false
    invite_timer_bar.custom_minimum_size.y = 4
    invite_timer_bar.max_value = 1.0
    invite_timer_bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.07), Color.TRANSPARENT, 0, 2))
    invite_timer_bar.add_theme_stylebox_override("fill", _box(ACCENT, Color.TRANSPARENT, 0, 2))
    stack.add_child(invite_timer_bar)
    var buttons := HBoxContainer.new()
    buttons.add_theme_constant_override("separation", 10)
    stack.add_child(buttons)
    var accept := _button("Entrar na sala", "AcceptInviteButton", _accept_invite, true, buttons)
    accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    accept.custom_minimum_size.y = 42
    var ignore := _button("Recusar", "IgnoreInviteButton", _dismiss_invite, false, buttons)
    ignore.custom_minimum_size = Vector2(110, 42)
    _invite_sound = AudioStreamPlayer.new()
    _invite_sound.stream = SfxBank.notify()
    _invite_sound.volume_db = -8.0
    add_child(_invite_sound)

var invite_kind := "party"

func _on_friend_invite(from: String, code: String, kind: String = "party") -> void:
    if code == Net.invite_code():
        Net.pending_invite = {}
        return # already in that room
    invite_code = code
    invite_kind = kind
    var rank := ""
    var photo_version := 0
    for friend in Net.friends_data.get("friends", []):
        if str(friend.get("name", "")) == from:
            rank = str(friend.get("rank", ""))
            photo_version = int(friend.get("avatar", 0))
    invite_label.text = "%s convidou você" % from
    var where := "Eliminatória  ·  sala de espera" if kind == "elim" else "Sala %s  ·  Equipes" % code
    invite_sub.text = ("%s  ·  " % rank if not rank.is_empty() else "") + where
    for child in invite_avatar_slot.get_children():
        child.queue_free()
    invite_avatar_slot.add_child(_avatar_badge(from, true, 46.0, photo_version))
    # Entra deslizando da direita, com um "plim"; a barra mostra quanto tempo resta.
    if _invite_tween != null and _invite_tween.is_valid():
        _invite_tween.kill()
    invite_banner.visible = true
    invite_banner.modulate.a = 0.0
    invite_banner.offset_left = -364
    invite_banner.offset_right = 16
    invite_timer_bar.value = 1.0
    _invite_tween = create_tween()
    _invite_tween.set_parallel(true)
    _invite_tween.tween_property(invite_banner, "modulate:a", 1.0, 0.22)
    _invite_tween.tween_property(invite_banner, "offset_left", -404.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _invite_tween.tween_property(invite_banner, "offset_right", -24.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _invite_tween.tween_property(invite_timer_bar, "value", 0.0, INVITE_SHOW_SECONDS)
    _invite_tween.chain().tween_callback(_dismiss_invite)
    if _invite_sound != null and _invite_sound.is_inside_tree():
        _invite_sound.play()
    var accept := invite_banner.find_child("AcceptInviteButton", true, false) as Button
    if accept != null:
        accept.grab_focus()

func _dismiss_invite() -> void:
    Net.pending_invite = {}
    if _invite_tween != null and _invite_tween.is_valid():
        _invite_tween.kill()
    invite_banner.visible = false

func _accept_invite() -> void:
    _dismiss_invite()
    if Net.is_online():
        _disconnect_net()
        Net.leave()
    if invite_kind == "elim":
        _connect_elimination(invite_code)
    else:
        _connect_party(invite_code)

func _on_friends_updated(_data: Dictionary) -> void:
    if friends_screen_open:
        _fill_friends()
        return
    # Na sala: só a lista de convite se atualiza (a tela inteira não pisca e a busca não perde o foco).
    if invite_side != null and invite_side.visible and not Net.party_info.is_empty():
        _fill_invite_list()

const FRIEND_DANGER := Color("#e0705e")

## Friends screen: add by name, answer requests, see who is online / in a room.
## Cartão de adicionar no topo; lista em seções (pedidos, online, offline) com
## avatar, nome, patente e estado; rola quando passa da tela.
func _show_friends(message: String = "") -> void:
    _clear()
    _set_page_width(ONLINE_PAGE_WIDTH)
    _screen_header("Social", "Amigos", "Adicione pelo nome e convide para a sua sala.")
    var add_card := _card(content, "FriendAddCard")
    add_card.add_theme_constant_override("separation", 8)
    add_card.add_child(_plain("ADICIONAR AMIGO", 12, MUTED, caps_font))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    add_card.add_child(row)
    var field := LineEdit.new()
    field.name = "FriendNameField"
    field.placeholder_text = "Nome do jogador"
    field.max_length = 16
    field.clear_button_enabled = true
    field.custom_minimum_size.y = 44
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(field)
    var add := _button("Adicionar", "AddFriendButton", Callable(), true, row)
    add.custom_minimum_size = Vector2(128, 44)
    var feedback := _wrap("", 13, ACCENT)
    feedback.name = "FriendsFeedback"
    add_card.add_child(feedback)
    _friends_feedback(feedback, message)
    add.pressed.connect(func():
        if field.text.strip_edges().length() < 3:
            _friends_feedback(feedback, "Digite o nome do jogador (3 letras ou mais).")
            return
        add.disabled = true
        var result: String = await Net.friend_action("add", field.text)
        if is_instance_valid(feedback):
            _friends_feedback(feedback, result)
            add.disabled = false
            field.text = "")
    field.text_submitted.connect(func(_text): add.pressed.emit())
    var scroll := ScrollContainer.new()
    scroll.name = "FriendsScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    content.add_child(scroll)
    var list := VBoxContainer.new()
    list.name = "FriendsList"
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 6)
    scroll.add_child(list)
    _button("Voltar", "BackButton", func():
        friends_screen_open = false
        _show_main())
    friends_screen_open = true
    _fill_friends()
    Net.poll_friends()

## Mensagem do cartão de adicionar: some quando vazia (sem buraco na tela).
func _friends_feedback(label: Label, text: String) -> void:
    if label == null or not is_instance_valid(label):
        return
    label.text = text
    label.visible = not text.is_empty()

## Linha da lista: cartão com avatar, nome, patente · estado e botões à direita.
func _friend_row(row_name: String, player_name: String, online: bool, avatar: int, detail: String, detail_color: Color) -> HBoxContainer:
    var panel := PanelContainer.new()
    panel.name = row_name
    var box := _box(Color(1, 1, 1, 0.04 if online else 0.02), LINE, 1, 8)
    box.content_margin_left = 10
    box.content_margin_right = 8
    box.content_margin_top = 7
    box.content_margin_bottom = 7
    panel.add_theme_stylebox_override("panel", box)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    panel.add_child(row)
    row.add_child(_avatar_badge(player_name, online, 36.0, avatar))
    var words := VBoxContainer.new()
    words.add_theme_constant_override("separation", 0)
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(words)
    var name_label := _plain(player_name, 15, TEXT if online else MUTED, semi_font)
    name_label.clip_text = true
    name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    words.add_child(name_label)
    var detail_label := _plain(detail, 12, detail_color)
    detail_label.clip_text = true
    detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    words.add_child(detail_label)
    var list := content.get_node_or_null("FriendsScroll/FriendsList")
    if list != null:
        list.add_child(panel)
    return row

## Título de seção da lista ("PEDIDOS · 1", "ONLINE · 2"...).
func _friends_section(list: VBoxContainer, text: String, count: int, color: Color) -> void:
    var label := _plain("%s  ·  %d" % [text.to_upper(), count], 11, color, caps_font)
    if list.get_child_count() > 0:
        var gap := Control.new()
        gap.custom_minimum_size.y = 6
        list.add_child(gap)
    list.add_child(label)

func _status_text(friend: Dictionary) -> String:
    match str(friend.get("status","offline")):
        "room":
            var room_code := str(friend.get("code",""))
            return "numa eliminatória" if room_code.length() == 6 else "na sala %s" % room_code
        "match":
            return "em partida"
        "menu":
            return "online"
    return "offline"

func _fill_friends() -> void:
    var list := content.get_node_or_null("FriendsScroll/FriendsList") as VBoxContainer
    var scroll := content.get_node_or_null("FriendsScroll") as ScrollContainer
    if list == null:
        return
    for child in list.get_children():
        list.remove_child(child)
        child.queue_free()
    var feedback := content.find_child("FriendsFeedback", true, false) as Label
    var data: Dictionary = Net.friends_data
    var requests: Array = data.get("requests", [])
    var friends: Array = (data.get("friends", []) as Array).duplicate()
    friends.sort_custom(func(a, b):
        var oa := bool(a.get("online", false))
        var ob := bool(b.get("online", false))
        return oa if oa != ob else str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
    var rows := 0
    # Pedidos de amizade primeiro (com Aceitar em destaque).
    if not requests.is_empty():
        _friends_section(list, "Pedidos", requests.size(), ACCENT)
        for requester in requests:
            var row := _friend_row("FriendRequest_" + str(requester), str(requester), true, 0, "quer ser seu amigo", ACCENT)
            for action in [["accept", "Aceitar", true], ["decline", "Recusar", false]]:
                var button := _small_button(action[1], "Request_%s_%s" % [action[0], requester], action[2], row)
                button.custom_minimum_size = Vector2(84, 32)
                button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                button.pressed.connect(func():
                    button.disabled = true
                    var result: String = await Net.friend_action(action[0], requester)
                    _friends_feedback(feedback, result))
            rows += 1
    var online_count := 0
    for friend in friends:
        if bool(friend.get("online", false)):
            online_count += 1
    if friends.is_empty():
        if requests.is_empty():
            var empty := _wrap("Você ainda não tem amigos. Digite o nome de um jogador acima e clique em Adicionar: ele recebe o pedido no menu.", 13, MUTED)
            empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            list.add_child(empty)
            rows += 1
    else:
        var section_done := {}
        for friend in friends:
            var online := bool(friend.get("online", false))
            var key := "online" if online else "offline"
            if not section_done.has(key):
                section_done[key] = true
                if online:
                    _friends_section(list, "Online", online_count, ONLINE_GREEN)
                else:
                    _friends_section(list, "Offline", friends.size() - online_count, DIM)
            var friend_name := str(friend.get("name", ""))
            var status := _status_text(friend)
            var status_color := ONLINE_GREEN if str(friend.get("status", "")) == "menu" else (ACCENT if online else DIM)
            var rank := str(friend.get("rank", ""))
            var detail := "%s  ·  %s" % [rank, status] if not rank.is_empty() else status
            var row := _friend_row("Friend_" + friend_name, friend_name, online, int(friend.get("avatar", 0)), detail, status_color)
            var code := str(friend.get("code", ""))
            if not code.is_empty():
                var join := _small_button("Entrar na sala", "JoinFriend_" + friend_name, true, row)
                join.custom_minimum_size.y = 32
                join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                join.pressed.connect(func():
                    friends_screen_open = false
                    _connect_party(code))
            _friend_remove_button(row, friend_name, feedback)
            rows += 1
    # A lista cresce até caber na janela (título, cartão e Voltar sempre visíveis); depois rola.
    if scroll != null:
        var room := clampf(get_viewport_rect().size.y - 470.0, 150.0, 420.0)
        scroll.custom_minimum_size.y = clampf(rows * 60.0 + 30.0, 60.0, room)

## "Remover" pede confirmação: o primeiro clique vira "Confirmar?" por 3 s.
func _friend_remove_button(row: HBoxContainer, friend_name: String, feedback: Label) -> void:
    var remove := _small_button("Remover", "RemoveFriend_" + friend_name, false, row)
    remove.custom_minimum_size = Vector2(92, 32)
    remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    remove.tooltip_text = "Remover %s da lista de amigos" % friend_name
    remove.add_theme_color_override("font_color", MUTED)
    remove.add_theme_color_override("font_hover_color", FRIEND_DANGER)
    var armed := [false]
    remove.pressed.connect(func():
        if not armed[0]:
            armed[0] = true
            remove.text = "Confirmar?"
            remove.add_theme_color_override("font_color", FRIEND_DANGER)
            get_tree().create_timer(3.0).timeout.connect(func():
                if is_instance_valid(remove):
                    armed[0] = false
                    remove.text = "Remover"
                    remove.add_theme_color_override("font_color", MUTED))
            return
        remove.disabled = true
        var result: String = await Net.friend_action("remove", friend_name)
        _friends_feedback(feedback, result))

## Lista de amigos compacta na lateral direita da sala personalizada (fora do
## cartão da sala, que fica só com código, equipes e "pronto"). Online primeiro,
## convite com um clique e estado ("…", "✓"), busca quando a lista é grande e
## adicionar amigo pelo nome sem sair da sala.
const INVITE_SIDE_WIDTH := 252.0
var invite_side: PanelContainer

func _invite_friends_section() -> void:
    if invite_side == null:
        _build_invite_side()
    invite_side.visible = true
    if invite_banner != null:
        invite_banner.move_to_front() # o card de convite recebido fica por cima
    _fill_invite_list()

func _build_invite_side() -> void:
    invite_side = PanelContainer.new()
    invite_side.name = "InviteFriendsCard"
    var box := _box(Color(0.045, 0.065, 0.075, 0.92), LINE, 1, 12)
    for side in ["left", "right"]:
        box.set("content_margin_" + side, 12)
    for side in ["top", "bottom"]:
        box.set("content_margin_" + side, 12)
    invite_side.add_theme_stylebox_override("panel", box)
    add_child(invite_side)
    invite_side.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    invite_side.offset_right = -16
    invite_side.offset_left = -16 - INVITE_SIDE_WIDTH
    invite_side.offset_top = 96
    invite_side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    var stack := VBoxContainer.new()
    stack.add_theme_constant_override("separation", 8)
    invite_side.add_child(stack)
    var head := HBoxContainer.new()
    head.name = "InviteHeader"
    head.add_theme_constant_override("separation", 6)
    stack.add_child(head)
    var title := _plain("AMIGOS", 12, ACCENT, caps_font)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    head.add_child(title)
    var count_slot := HBoxContainer.new()
    count_slot.name = "InviteOnlineCount"
    head.add_child(count_slot)
    var search := LineEdit.new()
    search.name = "InviteSearch"
    search.placeholder_text = "Buscar"
    search.text = _invite_filter
    search.clear_button_enabled = true
    search.custom_minimum_size.y = 32
    search.add_theme_font_size_override("font_size", 13)
    search.text_changed.connect(func(text: String):
        _invite_filter = text
        _fill_invite_list())
    stack.add_child(search)
    var scroll := ScrollContainer.new()
    scroll.name = "InviteScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    stack.add_child(scroll)
    var list := VBoxContainer.new()
    list.name = "InviteFriendsList"
    list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    list.add_theme_constant_override("separation", 2)
    scroll.add_child(list)
    stack.add_child(HSeparator.new())
    # Adicionar amigo sem sair da sala (manda o pedido de amizade).
    var add_row := HBoxContainer.new()
    add_row.name = "InviteAddRow"
    add_row.add_theme_constant_override("separation", 6)
    stack.add_child(add_row)
    var field := LineEdit.new()
    field.name = "InviteAddField"
    field.placeholder_text = "Adicionar pelo nome"
    field.max_length = 16
    field.custom_minimum_size.y = 32
    field.add_theme_font_size_override("font_size", 13)
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_row.add_child(field)
    var add := _small_button("+", "InviteAddButton", false, add_row)
    add.custom_minimum_size = Vector2(34, 32)
    add.tooltip_text = "Enviar pedido de amizade"
    add.pressed.connect(func():
        if field.text.strip_edges().length() < 3:
            _on_party_notice("Digite o nome do jogador.")
            return
        add.disabled = true
        var result: String = await Net.friend_action("add", field.text)
        if is_instance_valid(add):
            add.disabled = false
            field.text = ""
        _on_party_notice(result))
    field.text_submitted.connect(func(_text): add.pressed.emit())

## Botão pequeno do painel lateral (mesmo estilo dos botões do menu, compacto).
func _small_button(text: String, node_name: String, primary: bool, parent: Node) -> Button:
    var button := _button(text, node_name, Callable(), primary, parent)
    button.add_theme_font_size_override("font_size", 13)
    for state in ["normal", "hover", "pressed", "focus", "disabled"]:
        var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
        if style != null:
            style.content_margin_left = 8
            style.content_margin_right = 8
            style.content_margin_top = 2
            style.content_margin_bottom = 2
            button.add_theme_stylebox_override(state, style)
    return button

## Ordem: online e livres (menu, outra sala, em partida), já na sala, offline.
func _invite_sort_key(friend: Dictionary) -> int:
    if not bool(friend.get("online", false)):
        return 4
    if str(friend.get("code", "")) == Net.invite_code() and not Net.invite_code().is_empty():
        return 3
    return {"menu": 0, "room": 1, "match": 2}.get(str(friend.get("status", "menu")), 0)

func _fill_invite_list() -> void:
    if invite_side == null or not invite_side.visible:
        return
    var list := invite_side.find_child("InviteFriendsList", true, false) as VBoxContainer
    var scroll := invite_side.find_child("InviteScroll", true, false) as ScrollContainer
    var search := invite_side.find_child("InviteSearch", true, false) as LineEdit
    var count_slot := invite_side.find_child("InviteOnlineCount", true, false) as HBoxContainer
    for child in list.get_children():
        list.remove_child(child)
        child.queue_free()
    var friends: Array = (Net.friends_data.get("friends", []) as Array).duplicate()
    friends.sort_custom(func(a, b):
        var ka := _invite_sort_key(a)
        var kb := _invite_sort_key(b)
        return ka < kb if ka != kb else str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
    var online := 0
    for friend in friends:
        if bool(friend.get("online", false)):
            online += 1
    for child in count_slot.get_children():
        count_slot.remove_child(child)
        child.queue_free()
    count_slot.add_child(_pill("%d online" % online, ONLINE_GREEN if online > 0 else MUTED))
    search.visible = friends.size() > 8
    var shown := 0
    var needle := _invite_filter.strip_edges().to_lower()
    for friend in friends:
        if not needle.is_empty() and not str(friend.get("name", "")).to_lower().contains(needle):
            continue
        list.add_child(_invite_row(friend))
        shown += 1
    if friends.is_empty():
        list.add_child(_wrap("Sem amigos ainda. Adicione pelo nome aqui embaixo.", 12, MUTED))
    elif shown == 0:
        list.add_child(_wrap("Ninguém com esse nome.", 12, MUTED))
    # Linhas de 40 px: até 8 visíveis; mais que isso rola.
    scroll.custom_minimum_size.y = clampf(maxf(shown, 1) * 39.5, 40.0, 316.0)

func _invite_row(friend: Dictionary) -> PanelContainer:
    var friend_name := str(friend.get("name", ""))
    var online := bool(friend.get("online", false))
    var here := online and str(friend.get("code", "")) == Net.invite_code() and not Net.invite_code().is_empty()
    var panel := PanelContainer.new()
    panel.name = "InviteRow_" + friend_name
    var box := _box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 6)
    for side in ["left", "right"]:
        box.set("content_margin_" + side, 4)
    for side in ["top", "bottom"]:
        box.set("content_margin_" + side, 3)
    panel.add_theme_stylebox_override("panel", box)
    panel.tooltip_text = "%s  ·  %s  ·  %s" % [friend_name, friend.get("rank", ""), "nesta sala" if here else _status_text(friend)]
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    panel.add_child(row)
    row.add_child(_avatar_badge(friend_name, online, 28.0, int(friend.get("avatar", 0))))
    var words := VBoxContainer.new()
    words.add_theme_constant_override("separation", -2)
    words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(words)
    var name_label := _plain(friend_name, 13, TEXT if online else MUTED, semi_font)
    name_label.clip_text = true
    name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    words.add_child(name_label)
    var status_text := "nesta sala" if here else _status_text(friend)
    var status_color := ONLINE_GREEN if online and (here or str(friend.get("status", "")) == "menu") else (ACCENT if online else DIM)
    var status_label := _plain(status_text, 11, status_color)
    status_label.clip_text = true
    status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    words.add_child(status_label)
    if here or not online:
        return panel # na sala ou offline: só a linha, sem botão
    var invited_ago := Time.get_ticks_msec() - int(_invited_at.get(friend_name, -INVITE_COOLDOWN_MS))
    var cooling := invited_ago < INVITE_COOLDOWN_MS
    var invite := _small_button("✓" if cooling else "Convidar", "Invite_" + friend_name, not cooling, row)
    invite.custom_minimum_size = Vector2(76, 28)
    invite.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    invite.tooltip_text = "Convite enviado" if cooling else "Convidar %s para esta sala" % friend_name
    invite.disabled = cooling
    if cooling:
        _reenable_invite(invite, INVITE_COOLDOWN_MS - invited_ago)
    invite.pressed.connect(func():
        invite.disabled = true
        invite.text = "…"
        var result: String = await Net.friend_action("invite", friend_name, Net.invite_code(), Net.invite_kind())
        var sent := result.begins_with("Convite enviado")
        if sent:
            _invited_at[friend_name] = Time.get_ticks_msec()
        if is_instance_valid(invite):
            invite.text = "✓" if sent else "Convidar"
            invite.tooltip_text = "Convite enviado" if sent else invite.tooltip_text
            invite.disabled = sent
            if sent:
                _reenable_invite(invite, INVITE_COOLDOWN_MS)
        _on_party_notice(result))
    return panel

## Depois do intervalo, o botão volta a "Convidar".
func _reenable_invite(button: Button, wait_ms: int) -> void:
    get_tree().create_timer(maxf(0.1, wait_ms / 1000.0)).timeout.connect(func():
        if is_instance_valid(button):
            button.disabled = false
            button.text = "Convidar")

func _on_lobby_joined(info: Dictionary) -> void:
    if bool(info.get("party",false)) or bool(info.get("lobby",false)):
        return # the room screen arrives right after (party_updated)
    if bool(info.get("survival",false)):
        status.text = "Mundo encontrado! Entrando..."
        return
    status.text = "Sala encontrada! Começa em %d s" % int(info.get("seconds",20))

func _on_lobby_updated(info: Dictionary) -> void:
    var count := int(info.get("count",1))
    var capacity := int(info.get("capacity",8))
    status.text = "Jogadores: %d/%d  •  Começa em %d s" % [count,capacity,int(info.get("seconds",0))]
    var label := content.get_node_or_null("LobbyPlayers") as Label
    if label:
        var names := PackedStringArray()
        for entry in info.get("players",[]):
            names.append("%s (%s)" % [entry.get("name",""), entry.get("rank","")])
        if names.is_empty():
            names = PackedStringArray(info.get("names",[]))
        label.text = ", ".join(names) + ("\n%d vaga(s) serão completadas com bots" % (capacity-count) if count < capacity else "")

func _on_match_started(_info: Dictionary) -> void:
    _disconnect_net()
    if is_instance_valid(status):
        status.text = "Iniciando partida..."
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_login_required(message: String) -> void:
    _disconnect_net()
    Net.logout()
    _show_login(false,message)

func _on_update_required(message: String, url: String) -> void:
    _disconnect_net()
    Net.leave()
    _clear()
    _label("Atualização disponível",28,Color("#f0f2e9"))
    _label(message,17)
    _label("Sua versão: " + Net.game_version(),14,Color("#9bad9f"))
    if not url.is_empty():
        _button("Baixar no itch.io","DownloadUpdateButton",func(): OS.shell_open(url),true).grab_focus()
    _label("Se instalou pelo app do itch.io, ele atualiza sozinho: abra o app e clique em Atualizar.",13,Color("#9bad9f"))
    _button("Voltar","BackButton",_show_main)

func _on_connection_lost(reason: String) -> void:
    _disconnect_net()
    _clear()
    _label("Multiplayer",28)
    _label(reason,17)
    _button("Tentar novamente","RetryButton",_show_multiplayer,true)
    _button("Voltar","BackButton",_show_main)

func _slider(title: String, node_name: String, low: float, high: float, value: float) -> HSlider:
    var caption := _label(title + "  %d%%" % roundi(value),16)
    var slider := HSlider.new()
    slider.name = node_name
    slider.min_value = low
    slider.max_value = high
    slider.step = 1
    slider.value = value
    slider.custom_minimum_size.y = 28
    slider.value_changed.connect(func(current: float): caption.text = title + "  %d%%" % roundi(current))
    content.add_child(slider)
    return slider

# ------------------------------------------------------------ controles ---

var _capturing_action := "" # ação esperando a nova tecla ("" = nenhuma)

## Configurações › Controles: cada ação com a tecla atual; clique e aperte a
## nova tecla (ou botão do mouse). Tecla já usada por outra ação = as duas trocam.
func _show_controls(message: String = "") -> void:
    _clear()
    _capturing_action = ""
    _set_page_width(620.0)
    _screen_header("Configurações", "Controles", "Clique numa ação e aperte a nova tecla ou botão do mouse. ESC cancela.")
    var feedback := _wrap(message, 14, ACCENT)
    feedback.name = "ControlsFeedback"
    feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    feedback.visible = not message.is_empty()
    content.add_child(feedback)
    var scroll := ScrollContainer.new()
    scroll.name = "ControlsScroll"
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.custom_minimum_size.y = minf(440.0, get_viewport_rect().size.y - 300.0)
    content.add_child(scroll)
    var groups := VBoxContainer.new()
    groups.name = "ControlsList"
    groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    groups.add_theme_constant_override("separation", 14)
    scroll.add_child(groups)
    var current_group := ""
    var card: VBoxContainer = null
    for entry in Controls.ACTIONS:
        if str(entry[2]) != current_group:
            current_group = str(entry[2])
            card = _card(groups, "ControlsGroup_" + current_group, Color(0, 0, 0, 0.25), LINE, 14)
            card.add_theme_constant_override("separation", 4)
            card.add_child(_plain(current_group.to_upper(), 12, ACCENT, caps_font))
        card.add_child(_control_row(str(entry[0]), str(entry[1])))
    var bottom := HBoxContainer.new()
    bottom.add_theme_constant_override("separation", 10)
    content.add_child(bottom)
    var reset := _button("Restaurar padrão", "ResetControlsButton", Callable(), false, bottom)
    reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reset.pressed.connect(_reset_controls)
    var back := _button("Voltar", "ControlsBackButton", _show_config, true, bottom)
    back.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _reset_controls() -> void:
    Controls.reset()
    Controls.save()
    _show_controls("Teclas voltaram ao padrão.")

## Linha: nome da ação à esquerda, "tecla" à direita (botão com cara de tecla).
func _control_row(action: String, title: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "ControlRow_" + action
    row.add_theme_constant_override("separation", 10)
    var label := _plain(title, 14, TEXT)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(label)
    var key := Button.new()
    key.name = "Bind_" + action
    key.text = Controls.key_name(Controls.binding(action))
    key.custom_minimum_size = Vector2(170, 34)
    key.add_theme_font_size_override("font_size", 14)
    if semi_font != null:
        key.add_theme_font_override("font", semi_font)
    for state in ["normal", "hover", "pressed", "focus"]:
        var box := _box(Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.16), 1, 6)
        box.border_width_bottom = 3 # cara de tecla
        if state == "hover" or state == "focus":
            box.border_color = ACCENT
        key.add_theme_stylebox_override(state, box)
    key.add_theme_color_override("font_color", TEXT)
    key.add_theme_color_override("font_hover_color", TEXT)
    key.pressed.connect(func():
        _capturing_action = action
        key.text = "Aperte uma tecla…"
        var waiting := _box(Color(ACCENT, 0.18), ACCENT, 2, 6)
        key.add_theme_stylebox_override("normal", waiting)
        key.add_theme_stylebox_override("hover", waiting)
        key.add_theme_stylebox_override("focus", waiting)
        key.release_focus())
    row.add_child(key)
    return row

## Captura a nova tecla enquanto uma ação espera (antes de qualquer outro uso do evento).
func _input(event: InputEvent) -> void:
    if _capturing_action.is_empty():
        return
    if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
        get_viewport().set_input_as_handled()
        _show_controls()
        return
    var code := Controls.code_of(event)
    if code == 0:
        return
    get_viewport().set_input_as_handled()
    var action := _capturing_action
    _capturing_action = ""
    var swapped := Controls.set_binding(action, code)
    var message := "%s: %s" % [Controls.label_of(action), Controls.key_name(code)]
    if not swapped.is_empty():
        message += "   ·   trocou com \"%s\"" % swapped
    if Controls.save() != OK:
        message = "Não foi possível salvar os controles."
    # Recria a tela no próximo quadro (o clique que escolheu o botão do mouse não aperta nada).
    call_deferred("_show_controls", message)

func _show_config() -> void:
    _clear()
    _label("Configurações",28)
    var sensitivity := _slider("Sensibilidade do mouse","SensitivitySlider",20,200,float(settings["sensitivity"]) * 100)
    var volume := _slider("Volume geral","VolumeSlider",0,100,float(settings["volume"]) * 100)
    _label("Suavização das bordas",16)
    var aa := OptionButton.new()
    aa.name = "AASelect"
    aa.add_item("Desligada")
    aa.add_item("2× — equilibrada")
    aa.add_item("4× — maior qualidade")
    aa.select(int(settings["msaa"]))
    aa.custom_minimum_size.y = 40
    content.add_child(aa)
    var fullscreen := CheckButton.new()
    fullscreen.name = "FullscreenToggle"
    fullscreen.text = "Tela cheia"
    fullscreen.button_pressed = settings["fullscreen"]
    content.add_child(fullscreen)
    _button("Controles (teclas e mouse)","ControlsButton",_show_controls)
    status = _label("",14)
    _button("Salvar","SaveButton",func():
        var values := {"sensitivity": sensitivity.value/100.0,"volume": volume.value/100.0,"msaa": aa.selected,"fullscreen": fullscreen.button_pressed}
        if Settings.save_settings(values) != OK:
            status.text = "Não foi possível salvar as configurações."
            return
        settings = values
        Settings.apply(settings,get_viewport())
        _show_main()
    ,true)
    _button("Voltar","BackButton",_show_main)
