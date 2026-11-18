extends PanelContainer
## Chat do menu principal (canto inferior direito), em tempo real:
##  - fechado: um botão "CHAT" com a bolinha de conexão e as não lidas;
##  - aberto: abas Global e Amigos. Em Amigos, a lista (online primeiro, com as
##    não lidas de cada um) e, clicando, a conversa com aquele amigo.
## As mensagens vêm de Net (chat_message / chat_history); aqui só mostra e envia.
## Usa os estilos do menu (cores, fontes, botões) através de `menu`.

const ACCENT := Color("#f0a23b")
const TEXT := Color("#eef1ec")
const MUTED := Color("#8d9a98")
const DIM := Color("#5f6d6c")
const ONLINE := Color("#7ccf8a")
const ALERT := Color("#e8622c")
const WIDTH := 380.0

var menu: Control
var shown := true # o menu esconde fora da tela principal
var open := false
var tab := "global" # "global" ou "friends"
var friend := "" # conversa aberta na aba Amigos ("" = lista)

var _toggle: Button
var _toggle_badge: Label
var _toggle_dot: Panel
var _panel: VBoxContainer
var _tab_global: Button
var _tab_friends: Button
var _status: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _input_row: HBoxContainer
var _input: LineEdit
var _send: Button
var _conv_head: HBoxContainer

func setup(owner_menu: Control) -> void:
	menu = owner_menu

func _ready() -> void:
	name = "ChatDock"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	stack.alignment = BoxContainer.ALIGNMENT_END
	add_child(stack)
	_panel = VBoxContainer.new()
	_panel.name = "ChatPanel"
	stack.add_child(_panel)
	_build_panel()
	var toggle_row := HBoxContainer.new()
	toggle_row.alignment = BoxContainer.ALIGNMENT_END
	stack.add_child(toggle_row)
	_build_toggle(toggle_row)
	Net.chat_message.connect(_on_message)
	Net.chat_history.connect(_on_history)
	Net.chat_state.connect(func(_online): refresh())
	Net.chat_error.connect(_on_error)
	Net.friends_updated.connect(func(_data):
		if open and tab == "friends" and friend.is_empty():
			_fill())
	refresh()

func _process(_delta: float) -> void:
	# Fica no canto inferior direito, por cima do menu.
	var view := get_viewport_rect().size
	var wanted := Vector2(WIDTH if open else 0.0, 0.0)
	size = Vector2(maxf(get_combined_minimum_size().x, wanted.x), get_combined_minimum_size().y)
	position = Vector2(view.x - size.x - 16.0, view.y - size.y - 16.0)

# ---------------------------------------------------------------- partes ---

func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	return menu.call("_box", bg, border, width, radius) if menu != null else StyleBoxFlat.new()

func _plain(text: String, font_size: int, color: Color, font_name: String = "") -> Label:
	var font: Font = menu.get(font_name) if menu != null and not font_name.is_empty() else null
	return menu.call("_plain", text, font_size, color, font) if menu != null else Label.new()

func _build_toggle(parent: Control) -> void:
	_toggle = Button.new()
	_toggle.name = "ChatToggle"
	_toggle.custom_minimum_size = Vector2(132, 40)
	_toggle.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := _box(Color(0.045, 0.065, 0.075, 0.94), ACCENT if state == "hover" else Color(1, 1, 1, 0.12), 1, 20)
		box.content_margin_left = 34
		box.content_margin_right = 16
		_toggle.add_theme_stylebox_override(state, box)
	_toggle.add_theme_font_size_override("font_size", 14)
	if menu != null and menu.get("caps_font") != null:
		_toggle.add_theme_font_override("font", menu.get("caps_font"))
	_toggle.text = "CHAT"
	_toggle.pressed.connect(func():
		open = not open
		refresh())
	parent.add_child(_toggle)
	_toggle_dot = Panel.new()
	_toggle_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle_dot.size = Vector2(10, 10)
	_toggle_dot.position = Vector2(16, 15)
	_toggle.add_child(_toggle_dot)
	_toggle_badge = Label.new()
	_toggle_badge.name = "ChatUnread"
	_toggle_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle_badge.add_theme_font_size_override("font_size", 11)
	_toggle_badge.add_theme_color_override("font_color", Color.WHITE)
	_toggle_badge.add_theme_stylebox_override("normal", _badge_box())
	_toggle_badge.position = Vector2(104, -6)
	_toggle.add_child(_toggle_badge)

func _badge_box() -> StyleBoxFlat:
	var box := _box(ALERT, ALERT, 0, 9)
	box.content_margin_left = 6
	box.content_margin_right = 6
	return box

func _build_panel() -> void:
	var card := PanelContainer.new()
	card.name = "ChatCard"
	var box := _box(Color(0.045, 0.065, 0.075, 1.0), Color(1, 1, 1, 0.10), 1, 12)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 12
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", box)
	card.custom_minimum_size.x = WIDTH
	_panel.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	card.add_child(stack)
	# Abas + minimizar.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	stack.add_child(head)
	_tab_global = _tab_button("Global", "ChatTabGlobal", head, "global")
	_tab_friends = _tab_button("Amigos", "ChatTabFriends", head, "friends")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var close := menu.call("_small_button", "—", "ChatMinimize", false, head) as Button
	close.custom_minimum_size = Vector2(34, 30)
	close.tooltip_text = "Minimizar o chat"
	close.pressed.connect(func():
		open = false
		refresh())
	_status = _plain("", 11, MUTED)
	_status.name = "ChatStatus"
	stack.add_child(_status)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	stack.add_child(_body)
	_conv_head = HBoxContainer.new()
	_conv_head.add_theme_constant_override("separation", 8)
	_body.add_child(_conv_head)
	_scroll = ScrollContainer.new()
	_scroll.name = "ChatScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "ChatList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 6)
	_body.add_child(_input_row)
	_input = LineEdit.new()
	_input.name = "ChatInput"
	_input.max_length = 200
	_input.custom_minimum_size.y = 36
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 14)
	_input.text_submitted.connect(func(_t): _submit())
	_input_row.add_child(_input)
	_send = menu.call("_small_button", "Enviar", "ChatSend", true, _input_row) as Button
	_send.custom_minimum_size = Vector2(74, 36)
	_send.pressed.connect(_submit)

func _tab_button(text: String, node_name: String, parent: Control, which: String) -> Button:
	var button := menu.call("_small_button", text, node_name, false, parent) as Button
	button.custom_minimum_size = Vector2(0, 30)
	button.toggle_mode = false
	button.pressed.connect(func():
		tab = which
		if which == "global":
			friend = ""
		refresh())
	return button

# ------------------------------------------------------------- conteúdo ---

## Redesenha tudo conforme o estado (aberto, aba, conversa, conexão).
func refresh() -> void:
	if _panel == null:
		return
	visible = shown and Net.is_logged_in()
	_panel.visible = open
	var total := Net.chat_unread_total()
	if open:
		_mark_read()
		total = Net.chat_unread_total()
	_toggle_badge.text = str(total)
	_toggle_badge.visible = total > 0
	_toggle_dot.add_theme_stylebox_override("panel", _box(ONLINE if Net.chat_online else DIM, Color.TRANSPARENT, 0, 5))
	_toggle.tooltip_text = "Chat conectado" if Net.chat_online else "Chat conectando…"
	if not open:
		return
	_style_tab(_tab_global, tab == "global", int(Net.chat_unread.get("global", 0)))
	var friends_unread := 0
	for key in Net.chat_unread:
		if key != "global":
			friends_unread += int(Net.chat_unread[key])
	_style_tab(_tab_friends, tab == "friends", friends_unread)
	if not Net.chat_online:
		_status.text = "Conectando ao chat…"
	elif tab == "global":
		_status.text = "Todos os jogadores online veem. Seja gentil."
	elif friend.is_empty():
		_status.text = "Conversa particular: só você e o amigo veem."
	else:
		_status.text = ""
	_status.visible = not _status.text.is_empty()
	_input_row.visible = tab == "global" or not friend.is_empty()
	_input.editable = Net.chat_online
	_send.disabled = not Net.chat_online
	_input.placeholder_text = "Mensagem para todos" if tab == "global" else "Mensagem para %s" % friend
	_fill()

func _style_tab(button: Button, active: bool, unread: int) -> void:
	var label := button.name.trim_prefix("ChatTab")
	label = "Global" if label == "Global" else "Amigos"
	button.text = label + ("  •  %d" % unread if unread > 0 else "")
	button.add_theme_color_override("font_color", TEXT if active else MUTED)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := _box(Color(ACCENT, 0.18) if active else Color(1, 1, 1, 0.04), ACCENT if active else Color(1, 1, 1, 0.08), 1, 8)
		box.content_margin_left = 12
		box.content_margin_right = 12
		button.add_theme_stylebox_override(state, box)

func _panel_height() -> float:
	return clampf(get_viewport_rect().size.y * 0.5, 220.0, 420.0)

func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for child in _conv_head.get_children():
		_conv_head.remove_child(child)
		child.queue_free()
	_conv_head.visible = tab == "friends" and not friend.is_empty()
	_scroll.custom_minimum_size.y = _panel_height()
	if tab == "global":
		_fill_messages(Net.chat_global, "Ninguém falou ainda. Diga oi!")
	elif friend.is_empty():
		_fill_friends()
	else:
		var back := menu.call("_small_button", "‹", "ChatBack", false, _conv_head) as Button
		back.custom_minimum_size = Vector2(32, 30)
		back.tooltip_text = "Voltar para a lista de amigos"
		back.pressed.connect(func():
			friend = ""
			refresh())
		var info := _friend_info(friend)
		_conv_head.add_child(menu.call("_avatar_badge", friend, bool(info.get("online", false)), 28.0, int(info.get("avatar", 0))))
		var title := _plain(friend, 14, TEXT, "semi_font")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_conv_head.add_child(title)
		_conv_head.add_child(_plain(menu.call("_status_text", info) if not info.is_empty() else "", 11, ONLINE if bool(info.get("online", false)) else DIM))
		_fill_messages(Net.chat_dms.get(friend, []), "Comece a conversa com %s." % friend)

func _friend_info(friend_name: String) -> Dictionary:
	for f in Net.friends_data.get("friends", []):
		if str(f.get("name", "")) == friend_name:
			return f
	return {}

func _fill_messages(messages: Array, empty_text: String) -> void:
	if messages.is_empty():
		var empty := _plain(empty_text, 13, MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(empty)
		return
	var me := str(Net.profile.get("name", ""))
	for msg in messages:
		_list.add_child(_message_row(msg, str(msg.get("from", "")) == me))
	_scroll_to_end()

func _message_row(msg: Dictionary, own: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	row.add_child(head)
	head.add_child(_plain("Você" if own else str(msg.get("from", "?")), 13, ACCENT if own else TEXT, "semi_font"))
	var rank := str(msg.get("rank", ""))
	if not rank.is_empty() and str(msg.get("ch", "")) == "global":
		head.add_child(_plain(rank, 11, DIM))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_plain(clock_text(float(msg.get("at", 0))), 11, DIM))
	var text := _plain(str(msg.get("text", "")), 14, Color("#d6dfd9"))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = WIDTH - 40.0
	row.add_child(text)
	return row

## Horário local "HH:MM" de um instante do servidor (ms desde 1970).
static func clock_text(at_ms: float) -> String:
	if at_ms <= 0.0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(int(at_ms / 1000.0) + bias)
	return "%02d:%02d" % [int(t["hour"]), int(t["minute"])]

func _fill_friends() -> void:
	var friends: Array = (Net.friends_data.get("friends", []) as Array).duplicate()
	if friends.is_empty():
		var empty := _plain("Adicione amigos em Amigos (menu à esquerda) para conversar em particular.", 13, MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(empty)
		return
	# Não lidas primeiro, depois online, depois por nome.
	friends.sort_custom(func(a, b):
		var ua := int(Net.chat_unread.get(str(a.get("name", "")), 0))
		var ub := int(Net.chat_unread.get(str(b.get("name", "")), 0))
		if (ua > 0) != (ub > 0):
			return ua > 0
		var oa := bool(a.get("online", false))
		var ob := bool(b.get("online", false))
		return oa if oa != ob else str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)
	for f in friends:
		_list.add_child(_friend_row(f))

func _friend_row(f: Dictionary) -> Control:
	var friend_name := str(f.get("name", ""))
	var online := bool(f.get("online", false))
	var button := Button.new()
	button.name = "ChatFriend_" + friend_name
	button.custom_minimum_size.y = 46
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := _box(Color(1, 1, 1, 0.07 if state == "hover" else 0.03), Color(ACCENT, 0.6) if state == "hover" else Color(1, 1, 1, 0.06), 1, 8)
		button.add_theme_stylebox_override(state, box)
	button.pressed.connect(func():
		tab = "friends"
		friend = friend_name
		Net.chat_open_dm(friend_name)
		refresh())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	button.add_child(row)
	row.add_child(menu.call("_avatar_badge", friend_name, online, 30.0, int(f.get("avatar", 0))))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	words.add_child(_plain(friend_name, 14, TEXT if online else MUTED, "semi_font"))
	words.add_child(_plain(menu.call("_status_text", f), 11, ONLINE if online else DIM))
	var unread := int(Net.chat_unread.get(friend_name, 0))
	if unread > 0:
		var badge := Label.new()
		badge.text = str(unread)
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_stylebox_override("normal", _badge_box())
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	return button

func _scroll_to_end() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)

# --------------------------------------------------------------- eventos ---

func _submit() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	var sent := Net.chat_say(text) if tab == "global" else Net.chat_dm(friend, text)
	if sent:
		_input.text = ""
	_input.grab_focus()

## O que está na tela conta como lido.
func _mark_read() -> void:
	if tab == "global":
		Net.chat_mark_read("global")
	elif not friend.is_empty():
		Net.chat_mark_read(friend)

func _on_message(_msg: Dictionary) -> void:
	refresh()

func _on_history(with_name: String, _messages: Array) -> void:
	if open and tab == "friends" and friend == with_name:
		refresh()

func _on_error(message: String) -> void:
	if not open:
		return
	_status.text = message
	_status.add_theme_color_override("font_color", Color("#f0a08a"))
	_status.visible = true
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(_status):
			_status.add_theme_color_override("font_color", MUTED)
			refresh())
