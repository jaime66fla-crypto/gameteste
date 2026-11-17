extends Control
const Settings = preload("res://scripts/game_settings.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const CharacterCard = preload("res://scripts/characters/character_card.gd")
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
var base_font: SystemFont
var title_font: FontVariation
var caps_font: FontVariation

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    settings = Settings.load_settings()
    Settings.apply(settings,get_viewport())
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

## Every rank with its XP, in small print; the player's current one highlighted.
func _rank_ladder(current: String, parent: Node) -> void:
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
    ladder.text = "[color=#8d9a98]PATENTES (XP):[/color] " + "  •  ".join(parts)
    parent.add_child(ladder)

func _clear() -> void:
    friends_screen_open = false
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
    button.custom_minimum_size.y = 50
    button.add_theme_font_size_override("font_size",18)
    if title_font != null:
        button.add_theme_font_override("font",title_font)
    for state in ["normal","hover","pressed","focus","disabled"]:
        var box := _box(ACCENT if primary else Color(1,1,1,0.05), Color(1,1,1,0.10), 0 if primary else 1, 5)
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
        first = _nav_button(nav, "Jogar online", "MultiplayerButton", _show_multiplayer, true, "3 modos de jogo")
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
    var avatar := PanelContainer.new()
    avatar.custom_minimum_size = Vector2(56, 56)
    var ring := _box(Color(ACCENT, 0.16), ACCENT, 2, 28)
    avatar.add_theme_stylebox_override("panel", ring)
    var initial := _plain(player_name.left(1).to_upper() if not player_name.is_empty() else "?", 26, ACCENT, title_font)
    initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    avatar.add_child(initial)
    who.add_child(avatar)
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

const LEADERBOARD_ROWS := 8
const MEDALS := [Color("#f0c24b"), Color("#c9d1d6"), Color("#d08a52")]
var leaderboard_cache: Dictionary = {}
var leaderboard_compact := false
var leaderboard_rows := LEADERBOARD_ROWS

## Top players by XP, loaded from the server; last result shown while it refreshes.
## Short screens show 5 single-line rows so the whole menu fits without scrolling.
func _leaderboard_panel(parent: Node) -> void:
    leaderboard_compact = get_viewport_rect().size.y < 860.0
    leaderboard_rows = 5 if leaderboard_compact else LEADERBOARD_ROWS
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
    box.content_margin_top = 3 if leaderboard_compact else 5
    box.content_margin_bottom = 3 if leaderboard_compact else 5
    row.add_theme_stylebox_override("panel", box)
    var line := HBoxContainer.new()
    line.add_theme_constant_override("separation", 10)
    row.add_child(line)
    var board_position = entry.get("position")
    var place := int(board_position) if board_position != null else 0
    var place_text := "#%d" % place if place > 0 else "100+"
    var place_color: Color = MEDALS[place - 1] if place >= 1 and place <= 3 else DIM
    var place_label := _plain(place_text, 15, place_color, title_font)
    place_label.custom_minimum_size.x = 44
    line.add_child(place_label)
    var names := VBoxContainer.new()
    names.add_theme_constant_override("separation", -2)
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    line.add_child(names)
    names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var player := _plain(str(entry.get("name", "")) + ("  (você)" if mine else ""), 15, ACCENT if mine else TEXT, title_font)
    player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    player.clip_text = true
    names.add_child(player)
    if not leaderboard_compact:
        names.add_child(_plain("%s  •  %d vitória%s" % [str(entry.get("rank", "")).to_upper(), int(entry.get("wins", 0)), "" if int(entry.get("wins", 0)) == 1 else "s"], 10, DIM, caps_font))
    var xp := _plain(_thousands(int(entry.get("xp", 0))) + " XP", 14, TEXT if place >= 1 and place <= 3 else MUTED, title_font)
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

func _build_fonts() -> void:
    base_font = SystemFont.new()
    base_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Arial"])
    var bold := SystemFont.new()
    bold.font_names = base_font.font_names
    bold.font_weight = 700
    var weight := TextServerManager.get_primary_interface().name_to_tag("wght")
    title_font = FontVariation.new()
    title_font.base_font = bold
    title_font.variation_opentype = {weight: 700}
    caps_font = FontVariation.new()
    caps_font.base_font = bold
    caps_font.variation_opentype = {weight: 600}
    caps_font.spacing_glyph = 2

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

## Tabs at the top of the online screen: public elimination or custom team room.
func _online_tabs(active: int) -> void:
    var row := HBoxContainer.new()
    row.name = "OnlineTabs"
    row.add_theme_constant_override("separation",8)
    content.add_child(row)
    var titles := ["Eliminatória","Equipes 2x2 / 4x4","Sobrevivência"]
    var names := ["TabElimination","TabTeams","TabSurvival"]
    var actions := [_show_multiplayer,_show_teams_tab,_show_survival_tab]
    for i in titles.size():
        var tab := _button(titles[i],names[i],Callable(),i == active)
        content.remove_child(tab)
        tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        tab.custom_minimum_size.y = 42
        tab.add_theme_font_size_override("font_size",16)
        if i != active:
            tab.pressed.connect(actions[i])
        row.add_child(tab)

func _show_multiplayer() -> void:
    _clear()
    _set_page_width(480.0)
    _label("Multiplayer",28)
    if not Net.is_logged_in():
        _show_login(false,"Entre na sua conta para jogar online.")
        return
    _online_tabs(0)
    _label("Eliminatória online para 8 jogadores. Entre numa sala, confirme que está pronto e o primeiro jogador da sala (líder) inicia a partida quando todos estiverem prontos. Vagas livres são completadas com bots. Uma vida só: vence o último vivo.",15,Color("#9bad9f"))
    _label("XP: abate de jogador 100  •  abate de bot 25  •  na cabeça +15  •  vitória 150  •  partida 20",13,Color("#d9b44a"))
    _label("Jogando como %s (%s)" % [Net.profile.get("name",""), Net.profile.get("rank","")],16)
    var note := _label("",16)
    note.name = "MultiplayerStatus"
    status = note
    var find := _button("Procurar sala","FindMatchButton",func():
        _show_lobby(str(Net.profile.get("name","")))
    ,true)
    find.grab_focus()
    _button("Voltar","BackButton",_show_main)

# ------------------------------------------------------- sobrevivência ---

## Aba "Sobrevivência": mundo aberto com zumbis, até 16 jogadores, sem sala de espera.
func _show_survival_tab() -> void:
    _clear()
    _set_page_width(520.0)
    _label("Multiplayer",28)
    if not Net.is_logged_in():
        _show_login(false,"Entre na sua conta para jogar online.")
        return
    _online_tabs(2)
    _label("Mundo aberto infestado de zumbis, para até 16 jogadores. Você nasce no mato com quase nada: revista casas, mercados, o hospital e a base militar atrás de comida, água, remédios e armas. Corte árvores, quebre pedras e desmonte carros para fabricar bandagens, machado, mochila e munição.",15,Color("#9bad9f"))
    _label("Fome e sede caem com o tempo. Tiros atraem zumbis. Mordida de zumbi infecta: sem vacina em 2 minutos você vira zumbi. Ao morrer, suas coisas ficam numa mochila no chão. Ao sair, seu personagem fica dormindo no mundo.",14,Color("#d9b44a"))
    _label("Jogando como %s (%s)" % [Net.profile.get("name",""), Net.profile.get("rank","")],16)
    var note := _label("",16)
    note.name = "MultiplayerStatus"
    status = note
    _label("Mundos ativos — cada mundo guarda o seu próprio personagem",17)
    var list := VBoxContainer.new()
    list.name = "SurvivalWorlds"
    list.add_theme_constant_override("separation",6)
    content.add_child(list)
    var loading := _label("Carregando mundos...",14,Color("#9bad9f"))
    content.remove_child(loading)
    list.add_child(loading)
    _button("Atualizar lista","RefreshWorldsButton",_show_survival_tab)
    _button("Voltar","BackButton",_show_main)
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
        var error := _label(str(data.get("error", "Nenhum mundo disponível agora.")),14,Color("#f0a08a"))
        content.remove_child(error)
        list.add_child(error)
        _world_button(list, "Entrar num mundo com vaga", "", true, false)
        return
    var shown := 0
    var fresh_shown := false
    for w in worlds:
        var online := int(w.get("online",0))
        var mine := bool(w.get("mine",false))
        var fresh := online == 0 and not mine
        if fresh and fresh_shown:
            continue # só um mundo vazio na lista
        fresh_shown = fresh_shown or fresh
        var text := "Mundo %d   •   %d/%d online   •   dia %d" % [int(w.get("number",0)), online, int(w.get("capacity",16)), int(w.get("day",1))]
        if mine:
            text += "   ★ seu personagem"
        elif fresh:
            text = "Mundo %d   •   vazio — começar do zero" % int(w.get("number",0))
        var full := online >= int(w.get("capacity",16))
        _world_button(list, text + ("   (cheio)" if full else ""), str(w.get("id","")), not full, mine)
        shown += 1
    if shown == 0:
        _world_button(list, "Entrar num mundo com vaga", "", true, false)

func _world_button(list: VBoxContainer, text: String, world_id: String, enabled: bool, primary: bool) -> void:
    var b := _button(text, "World_" + world_id.replace(":", "_"), func(): _join_survival(world_id), primary)
    content.remove_child(b)
    b.disabled = not enabled
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    list.add_child(b)

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
    _clear()
    _set_page_width(480.0)
    _label("Multiplayer",28)
    if not Net.is_logged_in():
        _show_login(false,"Entre na sua conta para jogar online.")
        return
    _online_tabs(1)
    _label("Partida personalizada em equipes: 2 contra 2 ou 4 contra 4. Crie uma sala e mande o código para seus amigos. Vagas livres podem ser completadas com bots. Vence a equipe que eliminar a outra.",15,Color("#9bad9f"))
    var feedback := _label(message,15,Color("#f0a08a"))
    feedback.name = "PartyFeedback"
    _button("Criar sala","CreatePartyButton",func(): _connect_party(""),true).grab_focus()
    _label("ou entre na sala de um amigo",13,Color("#7f9187"))
    var code := _field("Código da sala (ex.: K7Q2M)","PartyCodeField")
    code.max_length = 5
    var join := _button("Entrar com código","JoinPartyButton",func():
        if code.text.strip_edges().length() != 5:
            feedback.text = "O código tem 5 letras/números."
            return
        _connect_party(code.text)
    )
    code.text_submitted.connect(func(_text): join.pressed.emit())
    _button("Voltar","BackButton",_show_main)

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
    _show_teams_tab(message)

func _on_party_notice(message: String) -> void:
    var note := content.get_node_or_null("PartyNote") as Label
    if note:
        note.text = message

## Room screen (public elimination or team room), rebuilt on every update.
## Everyone confirms "ready"; the first player in the room (leader) starts.
func _on_party_updated(info: Dictionary) -> void:
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
    _label("SALA PERSONALIZADA  •  %dx%d" % [team_size,team_size],26,Color("#f0f2e9"))
    var code_row := HBoxContainer.new()
    code_row.alignment = BoxContainer.ALIGNMENT_CENTER
    code_row.add_theme_constant_override("separation",12)
    content.add_child(code_row)
    var code_label := _label("Código:  %s" % Net.party_code,30,Color("#ffe08a"))
    code_label.name = "PartyCode"
    content.remove_child(code_label)
    code_row.add_child(code_label)
    var copy := _button("Copiar","CopyCodeButton",Callable())
    content.remove_child(copy)
    copy.custom_minimum_size = Vector2(110,44)
    copy.pressed.connect(func():
        DisplayServer.clipboard_set(Net.party_code)
        copy.text = "Copiado!")
    code_row.add_child(copy)
    _label("Convide seus amigos: eles abrem Jogar online > Equipes 2x2 / 4x4 > Entrar com código.",13,Color("#9bad9f"))
    # Mode and bots: the leader edits, everyone else sees the current choice.
    if leader:
        var settings_row := HBoxContainer.new()
        settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
        settings_row.add_theme_constant_override("separation",18)
        content.add_child(settings_row)
        var mode := OptionButton.new()
        mode.name = "PartyModeSelect"
        mode.add_item("2 contra 2")
        mode.add_item("4 contra 4")
        mode.select(0 if team_size == 2 else 1)
        mode.custom_minimum_size = Vector2(180,40)
        settings_row.add_child(mode)
        var fill := CheckButton.new()
        fill.name = "PartyBotsToggle"
        fill.text = "Completar vagas com bots"
        fill.button_pressed = bots
        settings_row.add_child(fill)
        mode.item_selected.connect(func(index: int): Net.party_configure(2 if index == 0 else 4, fill.button_pressed))
        fill.toggled.connect(func(on: bool): Net.party_configure(team_size, on))
    else:
        _label("Modo %dx%d  •  %s" % [team_size,team_size,"vagas completadas com bots" if bots else "sem bots"],15)
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
    _label("ELIMINATÓRIA  •  SALA",26,Color("#f0f2e9"))
    _label("Jogadores: %d/%d  •  vagas livres viram bots" % [players.size(),capacity],15,Color("#9bad9f"))
    var list := VBoxContainer.new()
    list.name = "RoomPlayers"
    list.add_theme_constant_override("separation",6)
    content.add_child(list)
    for entry in players:
        list.add_child(_player_row(info,entry))
    for _slot in range(players.size(),capacity):
        var empty := Label.new()
        empty.text = "—  vaga (bot)"
        empty.add_theme_color_override("font_color",Color("#6f8278"))
        list.add_child(empty)
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
    var ready_tag := "✓ PRONTO" if bool(entry.get("ready",false)) else "… aguardando"
    if is_leader:
        ready_tag = "âœ“ inicia a partida"
    row.text = "%s  [%s]%s   %s" % [entry.get("name",""),entry.get("rank",""),tags,ready_tag]
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
    _button("Sair da sala","LeavePartyButton",_leave_party)

func _team_column(info: Dictionary, team: int, title: String, team_size: int, bots: bool) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.name = "Team%d" % team
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var box := StyleBoxFlat.new()
    box.bg_color = Color("#1b3036") if team == 0 else Color("#33231f")
    box.border_color = Color("#5d9fc0") if team == 0 else Color("#c0715d")
    box.set_border_width_all(1)
    box.set_corner_radius_all(10)
    for side in ["left","right","top","bottom"]:
        box.set("content_margin_" + side,14)
    panel.add_theme_stylebox_override("panel",box)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation",6)
    panel.add_child(column)
    var heading := Label.new()
    heading.text = "EQUIPE %s" % title.to_upper()
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    heading.add_theme_font_size_override("font_size",19)
    heading.add_theme_color_override("font_color",Color("#9fd4ee") if team == 0 else Color("#f0b0a0"))
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
        var empty := Label.new()
        empty.text = "—  vaga (bot)" if bots else "—  vaga livre"
        empty.add_theme_color_override("font_color",Color("#6f8278"))
        column.add_child(empty)
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

func _show_lobby(player_name: String) -> void:
    _clear()
    _label("Procurando sala",28)
    status = _label("Conectando ao servidor...",17)
    status.name = "MultiplayerStatus"
    var players := _label("",15,Color("#9bad9f"))
    players.name = "LobbyPlayers"
    _button("Cancelar","CancelButton",func():
        _disconnect_net()
        Net.leave()
        _show_multiplayer()
    )
    _connect_net()
    if Net.find_match(player_name) != OK:
        _on_connection_lost("Não foi possível conectar ao servidor.")

func _disconnect_net() -> void:
    for pair in [[Net.lobby_joined,_on_lobby_joined],[Net.lobby_updated,_on_lobby_updated],[Net.match_started,_on_match_started],[Net.connection_lost,_on_connection_lost],[Net.update_required,_on_update_required],[Net.login_required,_on_login_required],[Net.party_updated,_on_party_updated],[Net.party_error,_on_party_error],[Net.party_notice,_on_party_notice]]:
        if pair[0].is_connected(pair[1]):
            pair[0].disconnect(pair[1])

func _exit_tree() -> void:
    _disconnect_net()
    for pair in [[Net.friend_invite,_on_friend_invite],[Net.friends_updated,_on_friends_updated]]:
        if pair[0].is_connected(pair[1]):
            pair[0].disconnect(pair[1])

# ------------------------------------------------------------- friends ---

var invite_banner: PanelContainer
var invite_label: Label
var invite_code := ""
var friends_screen_open := false

## Banner at the top of the menu: "X convidou você para a sala CODE" [Entrar] [Ignorar].
func _build_invite_banner() -> void:
    invite_banner = PanelContainer.new()
    invite_banner.name = "InviteBanner"
    invite_banner.visible = false
    var box := StyleBoxFlat.new()
    box.bg_color = Color("#2d4a3a")
    box.border_color = Color("#a8e08c")
    box.set_border_width_all(1)
    box.set_corner_radius_all(10)
    for side in ["left","right","top","bottom"]:
        box.set("content_margin_" + side,12)
    invite_banner.add_theme_stylebox_override("panel",box)
    add_child(invite_banner)
    invite_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    invite_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
    invite_banner.offset_top = 14
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation",12)
    invite_banner.add_child(row)
    invite_label = Label.new()
    invite_label.add_theme_font_size_override("font_size",17)
    row.add_child(invite_label)
    var accept := Button.new()
    accept.name = "AcceptInviteButton"
    accept.text = "Entrar"
    accept.custom_minimum_size = Vector2(100,38)
    accept.pressed.connect(_accept_invite)
    row.add_child(accept)
    var ignore := Button.new()
    ignore.name = "IgnoreInviteButton"
    ignore.text = "Ignorar"
    ignore.custom_minimum_size = Vector2(100,38)
    ignore.pressed.connect(func():
        Net.pending_invite = {}
        invite_banner.visible = false)
    row.add_child(ignore)

func _on_friend_invite(from: String, code: String) -> void:
    if code == Net.party_code and Net.is_online():
        Net.pending_invite = {}
        return # already in that room
    invite_code = code
    invite_label.text = "%s convidou você para a sala %s" % [from, code]
    invite_banner.visible = true

func _accept_invite() -> void:
    Net.pending_invite = {}
    invite_banner.visible = false
    if Net.is_online():
        _disconnect_net()
        Net.leave()
    _connect_party(invite_code)

func _on_friends_updated(_data: Dictionary) -> void:
    if friends_screen_open:
        _fill_friends()
    elif content.get_node_or_null("InviteFriendsList") != null and not Net.party_info.is_empty():
        _on_party_updated(Net.party_info) # refresh who can be invited

## Friends screen: add by name, answer requests, see who is online / in a room.
func _show_friends(message: String = "") -> void:
    _clear()
    _set_page_width(560.0)
    _label("AMIGOS",28,Color("#f0f2e9"))
    _label("Adicione pelo nome de jogador. Na sala personalizada aparece a lista para convidar.",13,Color("#9bad9f"))
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation",8)
    content.add_child(row)
    var field := LineEdit.new()
    field.name = "FriendNameField"
    field.placeholder_text = "Nome do jogador"
    field.max_length = 16
    field.custom_minimum_size.y = 42
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(field)
    var add := Button.new()
    add.name = "AddFriendButton"
    add.text = "Adicionar"
    add.custom_minimum_size = Vector2(120,42)
    row.add_child(add)
    var feedback := _label(message,14,Color("#ffe08a"))
    feedback.name = "FriendsFeedback"
    add.pressed.connect(func():
        if field.text.strip_edges().length() < 3:
            feedback.text = "Digite o nome do jogador."
            return
        add.disabled = true
        var result: String = await Net.friend_action("add",field.text)
        if is_instance_valid(feedback):
            feedback.text = result
            add.disabled = false
            field.text = "")
    field.text_submitted.connect(func(_text): add.pressed.emit())
    var list := VBoxContainer.new()
    list.name = "FriendsList"
    list.add_theme_constant_override("separation",6)
    content.add_child(list)
    _button("Voltar","BackButton",func():
        friends_screen_open = false
        _show_main())
    friends_screen_open = true
    _fill_friends()
    Net.poll_friends()

func _status_text(friend: Dictionary) -> String:
    match str(friend.get("status","offline")):
        "room":
            return "na sala %s" % friend.get("code","")
        "match":
            return "em partida"
        "menu":
            return "online"
    return "offline"

func _fill_friends() -> void:
    var list := content.get_node_or_null("FriendsList") as VBoxContainer
    if list == null:
        return
    for child in list.get_children():
        child.queue_free()
    var feedback := content.get_node_or_null("FriendsFeedback") as Label
    var data: Dictionary = Net.friends_data
    for requester in data.get("requests",[]):
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation",8)
        var label := Label.new()
        label.text = "%s quer ser seu amigo" % requester
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.add_theme_color_override("font_color",Color("#ffe08a"))
        row.add_child(label)
        for action in [["accept","Aceitar"],["decline","Recusar"]]:
            var button := Button.new()
            button.text = action[1]
            button.name = "Request_%s_%s" % [action[0],requester]
            button.pressed.connect(func():
                var result: String = await Net.friend_action(action[0],requester)
                if feedback != null and is_instance_valid(feedback):
                    feedback.text = result)
            row.add_child(button)
        list.add_child(row)
    var friends: Array = data.get("friends",[])
    if friends.is_empty():
        var empty := Label.new()
        empty.text = "Você ainda não tem amigos adicionados."
        empty.add_theme_color_override("font_color",Color("#7f9187"))
        list.add_child(empty)
    for friend in friends:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation",8)
        var label := Label.new()
        var online := bool(friend.get("online",false))
        label.text = "%s  [%s]  •  %s" % [friend.get("name",""),friend.get("rank",""),_status_text(friend)]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        label.add_theme_color_override("font_color",Color("#a8e08c") if online else Color("#7f9187"))
        row.add_child(label)
        var friend_name := str(friend.get("name",""))
        var code := str(friend.get("code",""))
        if not code.is_empty():
            var join := Button.new()
            join.text = "Entrar na sala"
            join.name = "JoinFriend_" + friend_name
            join.pressed.connect(func():
                friends_screen_open = false
                _connect_party(code))
            row.add_child(join)
        var remove := Button.new()
        remove.text = "Remover"
        remove.name = "RemoveFriend_" + friend_name
        remove.pressed.connect(func():
            var result: String = await Net.friend_action("remove",friend_name)
            if feedback != null and is_instance_valid(feedback):
                feedback.text = result)
        row.add_child(remove)
        list.add_child(row)

## Room lobby section: online friends not in this room, each with "Convidar".
func _invite_friends_section() -> void:
    var friends: Array = Net.friends_data.get("friends",[])
    var candidates: Array = []
    for friend in friends:
        if bool(friend.get("online",false)) and str(friend.get("code","")) != Net.party_code:
            candidates.append(friend)
    _label("CONVIDAR AMIGOS" if not candidates.is_empty() else "Nenhum amigo online para convidar (adicione em Menu > Amigos).",14,Color("#9bad9f"))
    var list := VBoxContainer.new()
    list.name = "InviteFriendsList"
    content.add_child(list)
    for friend in candidates:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation",8)
        var label := Label.new()
        label.text = "%s  •  %s" % [friend.get("name",""),_status_text(friend)]
        label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(label)
        var friend_name := str(friend.get("name",""))
        var invite := Button.new()
        invite.text = "Convidar"
        invite.name = "Invite_" + friend_name
        invite.pressed.connect(func():
            invite.disabled = true
            var result: String = await Net.friend_action("invite",friend_name,Net.party_code)
            _on_party_notice(result))
        row.add_child(invite)
        list.add_child(row)

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
