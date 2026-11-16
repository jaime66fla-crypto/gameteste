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

func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    settings = Settings.load_settings()
    Settings.apply(settings,get_viewport())
    var gradient := Gradient.new()
    gradient.colors = PackedColorArray([Color("#101b20"),Color("#29413e")])
    var texture := GradientTexture2D.new()
    texture.gradient = gradient
    texture.fill_from = Vector2.ZERO
    texture.fill_to = Vector2.ONE
    var background := TextureRect.new()
    background.texture = texture
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var margin := MarginContainer.new()
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
    resized.connect(func(): card.custom_minimum_size.x = minf(page_width,get_viewport_rect().size.x - 48))
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color("#142328")
    panel.border_color = Color("#49615b")
    panel.set_border_width_all(1)
    panel.set_corner_radius_all(14)
    panel.content_margin_left = 28
    panel.content_margin_right = 28
    panel.content_margin_top = 30
    panel.content_margin_bottom = 28
    card.add_theme_stylebox_override("panel",panel)
    center.add_child(card)
    content = VBoxContainer.new()
    content.add_theme_constant_override("separation",14)
    card.add_child(content)
    _show_main()

func _clear() -> void:
    for child in content.get_children():
        content.remove_child(child)
        child.queue_free()

func _label(text: String, font_size: int = 16, color: Color = Color("#d6dfd9")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size",font_size)
    label.add_theme_color_override("font_color",color)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(label)
    return label

func _button(text: String, node_name: String, action: Callable, primary: bool = false) -> Button:
    var button := Button.new()
    button.name = node_name
    button.text = text
    button.custom_minimum_size.y = 50
    button.add_theme_font_size_override("font_size",18)
    for state in ["normal","hover","pressed","focus"]:
        var box := StyleBoxFlat.new()
        box.bg_color = Color("#b8ca91") if primary else Color("#23383c")
        if state == "hover" or state == "focus":
            box.bg_color = box.bg_color.lightened(0.12)
        elif state == "pressed":
            box.bg_color = box.bg_color.darkened(0.10)
        box.set_corner_radius_all(7)
        if state == "focus":
            box.border_color = Color("#e5eedc")
            box.set_border_width_all(2)
        button.add_theme_stylebox_override(state,box)
    for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
        button.add_theme_color_override(state,Color("#15241e") if primary else Color("#e2e9e4"))
    button.pressed.connect(action)
    content.add_child(button)
    return button

func _show_main() -> void:
    _clear()
    _set_page_width(430.0)
    _label("CAMPO DE FOGO",32,Color("#f0f2e9"))
    _label("PARTIDA EXPERIMENTAL",13,Color("#9bad9f"))
    _button("Iniciar partida teste","StartButton",_start_match,true).grab_focus()
    _button("Personagens","CharactersButton",_show_characters)
    _button("Multiplayer","MultiplayerButton",_show_multiplayer)
    _button("Configurações","ConfigButton",_show_config)
    _button("Sair","ExitButton",func(): get_tree().quit())
    _label("versão " + Net.game_version(),12,Color("#6f8278")).name = "VersionLabel"

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

func _show_multiplayer() -> void:
    _clear()
    _set_page_width(430.0)
    _label("Multiplayer",28)
    _label("Eliminatória online para 8 jogadores. A partida começa 20 s após a sala abrir; vagas livres são completadas com bots. Uma vida só: vence o último vivo.",15,Color("#9bad9f"))
    var name_field := LineEdit.new()
    name_field.name = "PlayerName"
    name_field.placeholder_text = "Seu nome"
    name_field.max_length = 16
    name_field.text = Net.load_name()
    name_field.custom_minimum_size.y = 44
    name_field.add_theme_font_size_override("font_size",18)
    content.add_child(name_field)
    var note := _label("",16)
    note.name = "MultiplayerStatus"
    status = note
    var find := _button("Procurar partida","FindMatchButton",func():
        Net.save_name(name_field.text.strip_edges())
        _show_lobby(name_field.text)
    ,true)
    find.grab_focus()
    _button("Voltar","BackButton",_show_main)

func _show_lobby(player_name: String) -> void:
    _clear()
    _label("Procurando partida",28)
    status = _label("Conectando ao servidor...",17)
    status.name = "MultiplayerStatus"
    var players := _label("",15,Color("#9bad9f"))
    players.name = "LobbyPlayers"
    _button("Cancelar","CancelButton",func():
        _disconnect_net()
        Net.leave()
        _show_multiplayer()
    )
    Net.lobby_joined.connect(_on_lobby_joined)
    Net.lobby_updated.connect(_on_lobby_updated)
    Net.match_started.connect(_on_match_started)
    Net.connection_lost.connect(_on_connection_lost)
    Net.update_required.connect(_on_update_required)
    if Net.find_match(player_name) != OK:
        _on_connection_lost("Não foi possível conectar ao servidor.")

func _disconnect_net() -> void:
    for pair in [[Net.lobby_joined,_on_lobby_joined],[Net.lobby_updated,_on_lobby_updated],[Net.match_started,_on_match_started],[Net.connection_lost,_on_connection_lost],[Net.update_required,_on_update_required]]:
        if pair[0].is_connected(pair[1]):
            pair[0].disconnect(pair[1])

func _exit_tree() -> void:
    _disconnect_net()

func _on_lobby_joined(info: Dictionary) -> void:
    status.text = "Sala encontrada! Começa em %d s" % int(info.get("seconds",20))

func _on_lobby_updated(info: Dictionary) -> void:
    var count := int(info.get("count",1))
    var capacity := int(info.get("capacity",8))
    status.text = "Jogadores: %d/%d  •  Começa em %d s" % [count,capacity,int(info.get("seconds",0))]
    var label := content.get_node_or_null("LobbyPlayers") as Label
    if label:
        var names: Array = info.get("names",[])
        label.text = ", ".join(PackedStringArray(names)) + ("\n%d vaga(s) serão completadas com bots" % (capacity-count) if count < capacity else "")

func _on_match_started(_info: Dictionary) -> void:
    _disconnect_net()
    status.text = "Iniciando partida..."
    get_tree().change_scene_to_file("res://scenes/main.tscn")

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
