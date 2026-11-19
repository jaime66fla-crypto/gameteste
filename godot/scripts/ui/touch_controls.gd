extends Control
## Controles de toque (celular/tablet), no estilo dos shooters mobile:
## - metade esquerda: joystick flutuante (nasce onde o polegar encosta;
##   empurrado até o fim para a frente, corre);
## - resto da tela: arrastar o dedo gira a câmera (também arrastando sobre o
##   botão de atirar, para mirar enquanto atira);
## - botões que "apertam" as mesmas ações do teclado (fire, aim, jump...), então
##   o resto do jogo não precisa saber que é toque.
## Só aparece enquanto o jogo está "preso" (PointerMode.is_captured()). Posição
## e tamanho de cada botão, sensibilidade e transparência ficam em
## user://touch_layout.cfg (botão "Controles de toque" com o jogo pausado).
const PointerMode = preload("res://scripts/pointer_mode.gd")
const PATH := "user://touch_layout.cfg"

## [id, texto, ação, modo, centro (fração da tela), raio em px (tela 1280×720)]
## modo: "hold" = apertado enquanto o dedo está em cima; "toggle" = liga/desliga;
## "pause" = mesmo que Esc.
const BUTTONS := [
	["fire", "ATIRAR", "fire", "hold", Vector2(0.84, 0.62), 68.0],
	["fire_left", "FOGO", "fire", "hold", Vector2(0.07, 0.40), 40.0],
	["aim", "MIRA", "aim", "toggle", Vector2(0.71, 0.42), 40.0],
	["jump", "PULO", "jump", "hold", Vector2(0.95, 0.47), 38.0],
	["crouch", "AGACHA", "crouch", "hold", Vector2(0.95, 0.73), 36.0],
	["reload", "RECARGA", "reload", "hold", Vector2(0.71, 0.76), 32.0],
	["melee", "SOCO", "melee", "hold", Vector2(0.62, 0.62), 30.0],
	["grenade", "GRANADA", "grenade", "hold", Vector2(0.61, 0.86), 30.0],
	["heal", "CURAR", "heal", "hold", Vector2(0.52, 0.88), 30.0],
	["interact", "USAR", "interact", "hold", Vector2(0.60, 0.30), 32.0],
	["weapon_1", "1", "weapon_1", "hold", Vector2(0.39, 0.08), 24.0],
	["weapon_2", "2", "weapon_2", "hold", Vector2(0.45, 0.08), 24.0],
	["weapon_3", "3", "weapon_3", "hold", Vector2(0.51, 0.08), 24.0],
	["weapon_4", "4", "weapon_4", "hold", Vector2(0.57, 0.08), 24.0],
	["weapon_5", "5", "weapon_5", "hold", Vector2(0.63, 0.08), 24.0],
	["map", "MAPA", "map", "hold", Vector2(0.77, 0.08), 26.0],
	["inventory", "MOCHILA", "inventory", "hold", Vector2(0.84, 0.08), 26.0],
	["pause", "II", "", "pause", Vector2(0.95, 0.17), 24.0],
	# Dirigindo: só botões (sem joystick). Volante na esquerda, pedais na direita.
	["car_left", "◀", "move_left", "hold", Vector2(0.08, 0.72), 54.0],
	["car_right", "▶", "move_right", "hold", Vector2(0.23, 0.72), 54.0],
	["car_gas", "ACELERAR", "move_forward", "hold", Vector2(0.88, 0.66), 64.0],
	["car_brake", "FREIO / RÉ", "move_back", "hold", Vector2(0.73, 0.80), 48.0],
	["car_handbrake", "FREIO DE MÃO", "jump", "hold", Vector2(0.73, 0.52), 42.0],
	["car_exit", "SAIR", "interact", "hold", Vector2(0.95, 0.38), 34.0],
]
## Botões que só existem no modo sobrevivência.
const SURVIVAL_ONLY := ["map", "inventory"]
## Botões do carro; os outros (menos os de BOTH) são de quem está a pé.
const CAR_IDS := ["car_left", "car_right", "car_gas", "car_brake", "car_handbrake", "car_exit"]
const BOTH_IDS := ["map", "inventory", "pause"]
## Joystick: só nasce nesta área (fração da tela).
const JOY_ZONE := Rect2(0.0, 0.22, 0.42, 0.78)
const JOY_RADIUS := 72.0
const JOY_HINT := Vector2(0.17, 0.72)
const DEFAULTS := {"look": 1.5, "scope": 1.0, "opacity": 0.75, "size": 1.0}

var player: Node
var survival := false
## Devolve true quando o HUD deve sumir (cena do vencedor).
var hidden_check: Callable
## Sobrevivência: quem sabe se você está dirigindo (is_driving / drive_look).
var match_controller: Node
var _car := false # mostrando os botões do carro
var _edit_car := false # editor mostrando o layout do carro

var options: Dictionary = DEFAULTS.duplicate()
## id -> Vector3(x, y, escala) escolhido pelo jogador.
var custom: Dictionary = {}

var _active := false
var _fingers: Dictionary = {} # índice do dedo -> {kind, id, last}
var _held: Dictionary = {} # ação -> quantos dedos a seguram
var _pressed_ids: Dictionary = {}
var _joy_finger := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_finger := -1

var editing := false
var _selected := ""
var _settings_button: Button
var _settings_panel: PanelContainer
var _edit_bar: PanelContainer
var _edit_label: Label
var _font: Font

func _ready() -> void:
	name = "TouchControls"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_load()
	_build_settings_ui()

# ------------------------------------------------------------- geometria ---

func _visible_ids() -> Array:
	var ids := []
	var car := _edit_car if editing else _car
	for entry in BUTTONS:
		var id: String = entry[0]
		if not survival and (SURVIVAL_ONLY.has(id) or CAR_IDS.has(id)):
			continue
		if not BOTH_IDS.has(id) and CAR_IDS.has(id) != car:
			continue
		ids.append(id)
	return ids

func _is_driving() -> bool:
	return survival and match_controller != null and match_controller.has_method("is_driving") and bool(match_controller.call("is_driving"))

func _entry(id: String) -> Array:
	for entry in BUTTONS:
		if entry[0] == id:
			return entry
	return []

## Escala da tela em relação aos 720 px de altura de referência.
func _ui_scale() -> float:
	return size.y / 720.0 if size.y > 0.0 else 1.0

func _center(id: String) -> Vector2:
	var frac: Vector2 = _entry(id)[4]
	if custom.has(id):
		var c: Vector3 = custom[id]
		frac = Vector2(c.x, c.y)
	return frac * size

func _radius(id: String) -> float:
	var scale_one := 1.0
	if custom.has(id):
		scale_one = (custom[id] as Vector3).z
	return float(_entry(id)[5]) * scale_one * float(options["size"]) * _ui_scale()

func _button_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _visible_ids():
		var d := pos.distance_to(_center(id))
		# Um pouco de folga em volta: dedo não é tão preciso quanto o mouse.
		if d <= _radius(id) * 1.15 and d < best_d:
			best = id
			best_d = d
	return best

# --------------------------------------------------------------- estado ---

func _process(_delta: float) -> void:
	var hide_all: bool = hidden_check.is_valid() and bool(hidden_check.call())
	var should := PointerMode.is_captured() and not hide_all and not editing
	if should != _active:
		_active = should
		if not _active:
			_release_all()
	var car := _is_driving()
	if car != _car:
		# Entrou ou saiu do carro: solta tudo (o dedo no SAIR não vira PULO).
		_release_all()
		_car = car
	_settings_button.visible = not PointerMode.is_captured() and not editing and not hide_all and not _settings_panel.visible
	queue_redraw()

func _release_all() -> void:
	for action in _held.keys():
		if int(_held[action]) > 0:
			_send(action, false)
	_held.clear()
	_pressed_ids.clear()
	_fingers.clear()
	_joy_finger = -1
	_look_finger = -1
	_set_joystick(Vector2.ZERO)

func _send(action: String, pressed: bool) -> void:
	# Um evento de verdade (e não só Input.action_press): quem escuta eventos,
	# como a troca de arma e o "soltar granada", também recebe.
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func _hold(action: String, on: bool) -> void:
	var count := int(_held.get(action, 0))
	if on:
		if count == 0:
			_send(action, true)
		_held[action] = count + 1
	elif count > 0:
		_held[action] = count - 1
		if count == 1:
			_send(action, false)

func _press_button(id: String) -> void:
	var entry := _entry(id)
	match entry[3]:
		"hold":
			_hold(entry[2], true)
		"toggle":
			_send(entry[2], not Input.is_action_pressed(entry[2]))
		"pause":
			_release_all()
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.keycode = KEY_ESCAPE
				key.physical_keycode = KEY_ESCAPE
				key.pressed = pressed
				get_viewport().push_input(key)
	_pressed_ids[id] = true

func _release_button(id: String) -> void:
	var entry := _entry(id)
	if entry.is_empty():
		return
	if entry[3] == "hold":
		_hold(entry[2], false)
	_pressed_ids.erase(id)

func _set_joystick(vec: Vector2) -> void:
	_joy_vec = vec
	var pairs := [["move_right", vec.x], ["move_left", -vec.x], ["move_back", vec.y], ["move_forward", -vec.y]]
	for pair in pairs:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
	# Empurrado até o fim para a frente: corre.
	var run := vec.length() > 0.95 and -vec.y > 0.8
	if run and not Input.is_action_pressed("sprint"):
		Input.action_press("sprint")
	elif not run and Input.is_action_pressed("sprint"):
		Input.action_release("sprint")

func _look(relative: Vector2) -> void:
	if _car:
		# Dirigindo: o dedo gira a câmera em volta do carro.
		if match_controller != null and match_controller.has_method("drive_look"):
			match_controller.call("drive_look", relative / _ui_scale() * float(options["look"]))
		return
	if player == null or not player.has_method("_apply_mouse_look"):
		return
	var k := float(options["look"])
	if Input.is_action_pressed("aim") or (player.has_method("is_scope_active") and bool(player.call("is_scope_active"))):
		k *= float(options["scope"])
	# Toque em unidades da tela de 720 px: igual em qualquer resolução.
	player.call("_apply_mouse_look", relative / _ui_scale() * k)

# ---------------------------------------------------------------- toque ---

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if editing:
		_edit_input(event)
		return
	if not _active:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	else:
		_finger_drag(event.index, event.position, event.relative)
	get_viewport().set_input_as_handled()

func _finger_down(index: int, pos: Vector2) -> void:
	_finger_up(index) # dedo "perdido" (o sistema às vezes não manda o soltar)
	var id := _button_at(pos)
	if not id.is_empty():
		_fingers[index] = {"kind": "button", "id": id, "last": pos}
		_press_button(id)
		return
	var zone := Rect2(JOY_ZONE.position * size, JOY_ZONE.size * size)
	if not _car and _joy_finger < 0 and zone.has_point(pos):
		_joy_finger = index
		_joy_center = pos
		_fingers[index] = {"kind": "joy", "last": pos}
		return
	if _look_finger < 0:
		_look_finger = index
		_fingers[index] = {"kind": "look", "last": pos}

func _finger_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	finger["last"] = pos
	match finger["kind"]:
		"joy":
			var r := JOY_RADIUS * _ui_scale() * float(options["size"])
			var offset := pos - _joy_center
			if offset.length() > r:
				# A base acompanha o dedo: nunca "perde" o joystick.
				_joy_center = pos - offset.normalized() * r
				offset = pos - _joy_center
			_set_joystick(offset / r)
		"look":
			_look(relative)
		"button":
			# Arrastar em cima de atirar (ou mirar) também gira a câmera.
			if finger["id"] in ["fire", "fire_left", "aim"]:
				_look(relative)

func _finger_up(index: int) -> void:
	if not _fingers.has(index):
		return
	var finger: Dictionary = _fingers[index]
	_fingers.erase(index)
	match finger["kind"]:
		"button":
			_release_button(finger["id"])
		"joy":
			_joy_finger = -1
			_set_joystick(Vector2.ZERO)
		"look":
			_look_finger = -1

# --------------------------------------------------------------- desenho ---

func _draw() -> void:
	if not _active and not editing:
		return
	var alpha := float(options["opacity"])
	var s := _ui_scale()
	# Joystick: base onde o polegar está, ou uma dica apagada no lugar comum.
	var r := JOY_RADIUS * s * float(options["size"])
	if (_edit_car if editing else _car):
		pass # carro: só botões
	elif _joy_finger >= 0:
		draw_circle(_joy_center, r, Color(0, 0, 0, 0.28 * alpha))
		draw_arc(_joy_center, r, 0, TAU, 48, Color(1, 1, 1, 0.55 * alpha), 2.0 * s)
		var knob := _joy_center + _joy_vec * r
		var running := Input.is_action_pressed("sprint")
		draw_circle(knob, r * 0.45, Color(1, 0.75, 0.25, 0.8 * alpha) if running else Color(1, 1, 1, 0.55 * alpha))
	else:
		var hint := JOY_HINT * size
		draw_arc(hint, r, 0, TAU, 48, Color(1, 1, 1, 0.18 * alpha), 2.0 * s)
		draw_circle(hint, r * 0.45, Color(1, 1, 1, 0.12 * alpha))
	for id in _visible_ids():
		var entry := _entry(id)
		var c := _center(id)
		var br := _radius(id)
		var on: bool = _pressed_ids.has(id) or (entry[3] == "toggle" and Input.is_action_pressed(entry[2]))
		var fill := Color(1, 0.55, 0.15, 0.55 * alpha) if on else Color(0, 0, 0, 0.35 * alpha)
		if id == "fire" and not on:
			fill = Color(0.75, 0.12, 0.08, 0.45 * alpha)
		draw_circle(c, br, fill)
		var outline := Color(1, 0.85, 0.3, 0.95) if editing and id == _selected else Color(1, 1, 1, 0.6 * alpha)
		draw_arc(c, br, 0, TAU, 40, outline, (3.0 if editing and id == _selected else 2.0) * s)
		var text: String = entry[1]
		var font_size := int(clampf(br * 0.42, 11.0 * s, 20.0 * s))
		if text.length() <= 2:
			font_size = int(br * 0.75)
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		if w > br * 1.7:
			# Texto comprido ("FREIO DE MÃO"): encolhe para caber no círculo.
			font_size = maxi(8, int(font_size * br * 1.7 / w))
			w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		draw_string(_font, c + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95 * maxf(alpha, 0.5)))

# ------------------------------------------------------- editar posições ---

func _edit_input(event: InputEvent) -> void:
	var bar_rect := _edit_bar.get_global_rect()
	if event is InputEventScreenTouch:
		if event.pressed:
			if bar_rect.has_point(event.position):
				return
			var id := _button_at(event.position)
			_fingers[event.index] = {"kind": "edit", "id": id}
			if not id.is_empty():
				_select(id)
		else:
			_fingers.erase(event.index)
	elif _fingers.has(event.index):
		var id: String = _fingers[event.index]["id"]
		if id.is_empty():
			return
		var frac: Vector2 = (event.position / size).clamp(Vector2(0.02, 0.02), Vector2(0.98, 0.98))
		var scale_one := (custom[id] as Vector3).z if custom.has(id) else 1.0
		custom[id] = Vector3(frac.x, frac.y, scale_one)
	get_viewport().set_input_as_handled()

func _select(id: String) -> void:
	_selected = id
	var entry := _entry(id)
	_edit_label.text = "Botão: %s" % entry[1] if not entry.is_empty() else "Toque num botão e arraste"

func _resize_selected(step: float) -> void:
	if _selected.is_empty():
		return
	var c: Vector3 = custom.get(_selected, Vector3(_entry(_selected)[4].x, _entry(_selected)[4].y, 1.0))
	c.z = clampf(c.z + step, 0.5, 2.0)
	custom[_selected] = c

func start_editing() -> void:
	editing = true
	_release_all()
	_settings_panel.visible = false
	_edit_bar.visible = true
	# Os toques na tela são para mover os botões, não para voltar ao jogo.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_select("")

func stop_editing() -> void:
	editing = false
	_fingers.clear()
	_edit_bar.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save()

# ------------------------------------------------------------- ajustes ---

func _build_settings_ui() -> void:
	_settings_button = Button.new()
	_settings_button.text = "Controles de toque"
	_settings_button.custom_minimum_size = Vector2(190, 44)
	add_child(_settings_button)
	_settings_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_settings_button.offset_left = -210
	_settings_button.offset_right = -20
	_settings_button.offset_top = 66
	_settings_button.offset_bottom = 110
	_settings_button.pressed.connect(func():
		_settings_panel.visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP)

	_settings_panel = PanelContainer.new()
	_settings_panel.visible = false
	add_child(_settings_panel)
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings_panel.custom_minimum_size = Vector2(460, 0)
	_settings_panel.offset_left = -230
	_settings_panel.offset_right = 230
	_settings_panel.offset_top = -200
	_settings_panel.offset_bottom = 200
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_settings_panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	var title := Label.new()
	title.text = "Controles de toque"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)
	_add_slider(col, "Câmera", "look", 0.3, 4.0)
	_add_slider(col, "Câmera mirando / luneta", "scope", 0.3, 2.0)
	_add_slider(col, "Transparência dos botões", "opacity", 0.2, 1.0)
	_add_slider(col, "Tamanho dos botões", "size", 0.6, 1.6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var edit := Button.new()
	edit.text = "Mover botões"
	edit.custom_minimum_size = Vector2(0, 48)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.pressed.connect(start_editing)
	row.add_child(edit)
	var close := Button.new()
	close.text = "Fechar"
	close.custom_minimum_size = Vector2(0, 48)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func():
		_settings_panel.visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_save())
	row.add_child(close)

	_edit_bar = PanelContainer.new()
	_edit_bar.visible = false
	add_child(_edit_bar)
	_edit_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_edit_bar.offset_left = -390
	_edit_bar.offset_right = 390
	_edit_bar.offset_top = 120
	_edit_bar.offset_bottom = 180
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_edit_bar.add_child(bar)
	_edit_label = Label.new()
	_edit_label.custom_minimum_size = Vector2(220, 0)
	_edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_edit_label)
	for spec in [["Menor", -0.1], ["Maior", 0.1]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(80, 48)
		var step: float = spec[1]
		b.pressed.connect(func(): _resize_selected(step))
		bar.add_child(b)
	if survival:
		# Sobrevivência: o carro tem o próprio layout de botões.
		var which := Button.new()
		which.text = "Ver: carro"
		which.custom_minimum_size = Vector2(110, 48)
		which.pressed.connect(func():
			_edit_car = not _edit_car
			which.text = "Ver: a pé" if _edit_car else "Ver: carro"
			_select(""))
		bar.add_child(which)
	var reset := Button.new()
	reset.text = "Padrão"
	reset.custom_minimum_size = Vector2(90, 48)
	reset.pressed.connect(func():
		custom.clear()
		options = DEFAULTS.duplicate()
		_select(""))
	bar.add_child(reset)
	var done := Button.new()
	done.text = "Pronto"
	done.custom_minimum_size = Vector2(90, 48)
	done.pressed.connect(stop_editing)
	bar.add_child(done)

func _add_slider(parent: Control, text: String, key: String, lo: float, hi: float) -> void:
	var label := Label.new()
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(0, 32)
	slider.value = float(options[key])
	var refresh := func(v: float):
		options[key] = v
		label.text = "%s: %.2f" % [text, v]
	refresh.call(slider.value)
	slider.value_changed.connect(refresh)
	# "Padrão" na barra de edição volta os valores: o painel acompanha ao reabrir.
	_settings_panel.visibility_changed.connect(func():
		if _settings_panel.visible:
			slider.set_value_no_signal(float(options[key]))
			refresh.call(float(options[key])))
	parent.add_child(slider)

func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key in DEFAULTS:
		options[key] = float(file.get_value("options", key, DEFAULTS[key]))
	for entry in BUTTONS:
		var v = file.get_value("layout", entry[0], null)
		if v is Vector3:
			custom[entry[0]] = v

func _save() -> void:
	var file := ConfigFile.new()
	for key in options:
		file.set_value("options", key, options[key])
	for id in custom:
		file.set_value("layout", id, custom[id])
	file.save(PATH)
