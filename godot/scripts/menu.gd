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

## Name, rank and XP progress at the top of the main menu.
func _profile_header() -> void:
    var profile: Dictionary = Net.profile
    var xp := int(profile.get("xp",0))
    _label("%s  •  %s" % [profile.get("name",""), profile.get("rank","Recruta")],19,Color("#ffe08a")).name = "ProfileName"
    var bar := ProgressBar.new()
    bar.name = "XpBar"
    bar.show_percentage = false
    bar.custom_minimum_size.y = 10
    var next_xp = profile.get("nextRankXp")
    var rank_xp := int(profile.get("rankXp",0))
    if next_xp == null:
        bar.max_value = 1
        bar.value = 1
    else:
        bar.max_value = maxf(1.0,float(int(next_xp) - rank_xp))
        bar.value = xp - rank_xp
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color("#d9b44a")
    fill.set_corner_radius_all(4)
    var back := StyleBoxFlat.new()
    back.bg_color = Color(0,0,0,0.4)
    back.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("fill",fill)
    bar.add_theme_stylebox_override("background",back)
    content.add_child(bar)
    var progress := "%d XP  —  patente máxima" % xp if next_xp == null else "%d / %d XP  —  próxima: %s" % [xp,int(next_xp),profile.get("nextRank","")]
    _label(progress,13,Color("#9bad9f")).name = "XpLabel"
    _label("Abates: %d jogadores, %d bots  •  Vitórias: %d  •  Partidas: %d" % [int(profile.get("kills",0)),int(profile.get("botKills",0)),int(profile.get("wins",0)),int(profile.get("matches",0))],12,Color("#7f9187"))
    _rank_ladder(str(profile.get("rank","")))

## Every rank with its XP, in small print; the player's current one highlighted.
func _rank_ladder(current: String) -> void:
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
            parts.append("[color=#ffe08a][b]%s[/b][/color]" % text)
        else:
            parts.append("[color=#6f8278]%s[/color]" % text)
    ladder.text = "[center]PATENTES (XP): " + "  •  ".join(parts) + "[/center]"
    content.add_child(ladder)

func _clear() -> void:
    friends_screen_open = false
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
    if action.is_valid():
        button.pressed.connect(action)
    content.add_child(button)
    return button

func _show_main(notice: String = "") -> void:
    _clear()
    _set_page_width(430.0)
    _logo()
    _label("CAMPO DE FOGO",32,Color("#f0f2e9"))
    if Net.is_logged_in():
        _profile_header()
    else:
        _label("MODO OFFLINE  •  entre na conta para jogar online e ganhar XP",13,Color("#9bad9f"))
    if not notice.is_empty():
        _label(notice,14,Color("#f0a08a"))
    if Net.is_logged_in():
        _button("Jogar online","MultiplayerButton",_show_multiplayer,true).grab_focus()
        _button("Treino offline","StartButton",_start_match)
    else:
        _button("Entrar / criar conta","LoginButton",func(): _show_login(false),true).grab_focus()
        _button("Treino offline","StartButton",_start_match)
    if Net.is_logged_in():
        var requests: int = Net.friends_data.get("requests",[]).size()
        _button("Amigos" + (" (%d pedido%s)" % [requests,"s" if requests > 1 else ""] if requests > 0 else ""),"FriendsButton",_show_friends)
    _button("Personagens","CharactersButton",_show_characters)
    _button("Configurações","ConfigButton",_show_config)
    if Net.is_logged_in():
        _button("Sair da conta","LogoutButton",func():
            Net.logout()
            _show_login(false))
    _button("Sair do jogo","ExitButton",func(): get_tree().quit())
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
    _label("Fome e sede caem com o tempo. Tiros atraem zumbis. De noite eles enxergam menos — e você também. Ao morrer, suas coisas ficam numa mochila no chão. Ao sair, seu personagem fica guardado no mundo.",14,Color("#d9b44a"))
    _label("Jogando como %s (%s)" % [Net.profile.get("name",""), Net.profile.get("rank","")],16)
    var note := _label("",16)
    note.name = "MultiplayerStatus"
    status = note
    _button("Entrar no mundo","JoinSurvivalButton",func():
        _clear()
        _label("Sobrevivência",28)
        status = _label("Procurando um mundo com vaga...",17)
        status.name = "MultiplayerStatus"
        _button("Cancelar","CancelButton",func():
            _disconnect_net()
            Net.leave()
            _show_survival_tab()
        )
        _connect_net()
        if Net.find_survival(str(Net.profile.get("name",""))) != OK:
            _on_connection_lost("Não foi possível conectar ao servidor.")
    ,true).grab_focus()
    _button("Voltar","BackButton",_show_main)

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
        ready_tag = "✓ inicia a partida"
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
