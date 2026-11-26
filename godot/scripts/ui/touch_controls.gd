extends Control
## Controles de toque (celular/tablet) para o FPS.
##
## Zonas da tela (dentro da área segura do aparelho: notch e câmera ficam de fora):
## - esquerda: joystick (flutuante ou fixo, com zona morta) — veja touch/virtual_joystick.gd;
## - qualquer lugar livre: arrastar gira a câmera (cada dedo é rastreado pelo
##   índice, então andar, mirar e atirar ao mesmo tempo não se atrapalham);
## - direita: cluster de combate (ATIRAR grande com arrastar-para-mirar, MIRA,
##   PULO, AGACHA, RECARGA longe do tiro);
## - topo: armas que você tem (a da mão acesa), placar, loja e pausa.
##
## Cada função tem UM botão só. Os presets mudam onde ficam:
## - "2" (2 dedos, polegares): tiro grande embaixo à direita;
## - "4" (4 dedos, garra): tiro no alto à esquerda (indicador esquerdo), mira,
##   pulo e agacha no alto à direita (indicador direito) — o polegar direito
##   não sai da câmera.
##
## Os botões "apertam" as mesmas ações do teclado (InputEventAction), então o
## jogador (player.gd) funciona igual no PC e no celular sem nenhum if de toque.
## Só aparece enquanto o jogo está "preso" (PointerMode.is_captured()).
## Preset, posição/tamanho/transparência de cada botão e as opções ficam em
## user://touch_layout.cfg (botão "Controles de toque" com o jogo pausado).
const PointerMode = preload("res://scripts/pointer_mode.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const Joystick = preload("res://scripts/ui/touch/virtual_joystick.gd")
const PATH := "user://touch_layout.cfg"

## [id, texto, ação, modo, centro (fração da área segura), raio em px (tela 720 de altura)]
## Modos: "hold" = apertado enquanto o dedo está em cima; "toggle" = liga/desliga;
## "crouch" = alterna (como o Ctrl) ou só segurando (opção); "sprint" = corrida
## ligada/desligada; "pause" = Esc; "key_hold"/"key_tap" = tecla (placar/loja);
## "slot" = troca de arma (texto vem da arma).
## Os centros aqui são do preset "2" (2 dedos).
const BUTTONS := [
	["fire", "ATIRAR", "fire", "hold", Vector2(0.83, 0.70), 64.0],
	["aim", "MIRA", "aim", "toggle", Vector2(0.945, 0.46), 34.0],
	["jump", "PULO", "jump", "hold", Vector2(0.955, 0.70), 34.0],
	["crouch", "AGACHA", "crouch", "crouch", Vector2(0.92, 0.89), 32.0],
	["reload", "RECARGA", "reload", "hold", Vector2(0.71, 0.50), 28.0],
	["heal", "CURAR", "heal", "hold", Vector2(0.70, 0.88), 26.0],
	# Escudo no braço: toque levanta/abaixa a guarda (só aparece com escudo).
	["shield", "FIXA", "shield", "hold", Vector2(0.83, 0.43), 30.0],
	["sprint", "CORRER", "sprint", "sprint", Vector2(0.27, 0.50), 28.0],
	["interact", "USAR", "interact", "hold", Vector2(0.05, 0.44), 28.0],
	["grenade", "GRANADA", "grenade", "hold", Vector2(0.05, 0.58), 28.0],
	["inventory", "MOCHILA", "inventory", "hold", Vector2(0.05, 0.72), 28.0],
	["map", "MAPA", "map", "hold", Vector2(0.30, 0.36), 24.0],
	["weapon_1", "1", "weapon_1", "slot", Vector2(0.36, 0.075), 24.0],
	["weapon_2", "2", "weapon_2", "slot", Vector2(0.416, 0.075), 24.0],
	["weapon_3", "3", "weapon_3", "slot", Vector2(0.472, 0.075), 24.0],
	["weapon_4", "4", "weapon_4", "slot", Vector2(0.528, 0.075), 24.0],
	["weapon_5", "5", "weapon_5", "slot", Vector2(0.584, 0.075), 24.0],
	["weapon_6", "6", "weapon_6", "slot", Vector2(0.64, 0.075), 24.0],
	["score", "PLACAR", "", "key_hold", Vector2(0.87, 0.065), 20.0],
	["shop", "LOJA", "", "key_tap", Vector2(0.92, 0.065), 20.0],
	["pause", "II", "", "pause", Vector2(0.97, 0.065), 20.0],
	# Dirigindo: só botões (sem joystick). Volante na esquerda, pedais na direita.
	["car_left", "◀", "move_left", "hold", Vector2(0.08, 0.72), 54.0],
	["car_right", "▶", "move_right", "hold", Vector2(0.23, 0.72), 54.0],
	["car_gas", "ACELERAR", "move_forward", "hold", Vector2(0.88, 0.66), 64.0],
	["car_brake", "FREIO / RÉ", "move_back", "hold", Vector2(0.73, 0.80), 48.0],
	["car_handbrake", "FREIO DE MÃO", "jump", "hold", Vector2(0.73, 0.52), 42.0],
	["car_exit", "SAIR", "interact", "hold", Vector2(0.95, 0.38), 34.0],
]
## Preset "4" (garra): só o que muda em relação à tabela. id -> [centro, raio].
const PRESET_4 := {
	"fire": [Vector2(0.19, 0.40), 46.0],
	"sprint": [Vector2(0.30, 0.56), 28.0],
	"aim": [Vector2(0.76, 0.38), 36.0],
	"jump": [Vector2(0.94, 0.40), 36.0],
	"crouch": [Vector2(0.86, 0.56), 32.0],
	"reload": [Vector2(0.64, 0.30), 28.0],
	"heal": [Vector2(0.94, 0.88), 26.0],
	"shield": [Vector2(0.75, 0.55), 30.0],
}
const PRESETS := {"2": "2 dedos (polegares)", "4": "4 dedos (garra)"}
## Teclas dos botões de tecla (quem escuta é o match_controller).
const KEYS := {"score": KEY_TAB, "shop": KEY_B}
## Botões que só existem no modo sobrevivência.
const SURVIVAL_ONLY := ["map", "inventory"]
## Botões do carro; os outros (menos os de BOTH) são de quem está a pé.
const CAR_IDS := ["car_left", "car_right", "car_gas", "car_brake", "car_handbrake", "car_exit"]
const BOTH_IDS := ["map", "inventory", "pause"]
## Desenhados como quadrado (itens e armas), os outros como círculo.
const SQUARE_IDS := ["inventory", "interact", "grenade", "weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5", "weapon_6"]
## Botões em que arrastar o dedo também gira a câmera.
const DRAG_LOOK_IDS := ["fire", "aim"]
## Sobe quando o layout padrão muda: posições salvas do layout antigo são descartadas.
const LAYOUT_VERSION := 3
## Joystick: só nasce nesta área (fração da área segura). Fica onde o polegar
## esquerdo descansa; o resto da tela é câmera.
const JOY_ZONE := Rect2(0.0, 0.30, 0.42, 0.70)
const JOY_RADIUS := 72.0
const JOY_REST := Vector2(0.16, 0.74)
## Opções (todas numéricas para caber no ConfigFile do mesmo jeito):
## look/scope = sensibilidade da câmera; opacity/size = todos os botões;
## deadzone = zona morta do joystick; joy_fixed/crouch_hold/fire_drag = 0 ou 1.
const DEFAULTS := {"look": 1.5, "scope": 1.0, "opacity": 0.75, "size": 1.0, "deadzone": 0.12, "joy_fixed": 0.0, "crouch_hold": 0.0, "fire_drag": 1.0}

var player: Node
var survival := false
## Devolve true quando o HUD deve sumir (cena do vencedor).
var hidden_check: Callable
## Partida/sobrevivência: is_driving / drive_look, loja e placar.
var match_controller: Node
## Teste: força a área segura (em pixels do Control). Vazio = a do aparelho.
var safe_override := Rect2()
var _car := false # mostrando os botões do carro
var _edit_car := false # editor mostrando o layout do carro

var preset := "2"
var options: Dictionary = DEFAULTS.duplicate()
## id -> Vector3(x, y, escala) escolhido pelo jogador ("joystick" também).
var custom: Dictionary = {}
## id -> transparência própria (multiplica a geral).
var custom_alpha: Dictionary = {}

var _active := false
var _safe := Rect2()
var _fingers: Dictionary = {} # índice do dedo -> {kind, id, last}
var _held: Dictionary = {} # ação -> quantos dedos a seguram
var _pressed_ids: Dictionary = {}
var _joy := Joystick.new()
var _look_finger := -1
var _sprint_on := false # botão CORRER ligado
var _crouch_from_hold := false # AGACHA segurando: foi este dedo que agachou

var editing := false
var _edit_backup: Array = [] # [custom, options, custom_alpha, preset] ao abrir o editor
var _selected := ""
var _settings_button: Button
var _settings_panel: PanelContainer
var _preset_buttons: Dictionary = {}
var _edit_bar: PanelContainer
var _edit_label: Label
var _font: Font

func _ready() -> void:
	name = "TouchControls"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.font(600)
	_load()
	_build_settings_ui()
	_update_safe()

# ------------------------------------------------------------- geometria ---

## Área segura em pixels deste Control: no celular tira notch/câmera/barras;
## no PC é a tela toda.
func _compute_safe() -> Rect2:
	var full := Rect2(Vector2.ZERO, size)
	if safe_override.has_area():
		return safe_override
	if not OS.has_feature("mobile"):
		return full
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return full
	var safe := DisplayServer.get_display_safe_area()
	var local := Rect2(Vector2(safe.position - DisplayServer.window_get_position()), Vector2(safe.size))
	local = local.intersection(Rect2(Vector2.ZERO, win))
	if not local.has_area():
		return full
	var k := size / win
	return Rect2(local.position * k, local.size * k)

func _update_safe() -> void:
	_safe = _compute_safe()

func _to_screen(frac: Vector2) -> Vector2:
	return _safe.position + frac * _safe.size

func _to_frac(pos: Vector2) -> Vector2:
	return ((pos - _safe.position) / _safe.size).clamp(Vector2(0.02, 0.02), Vector2(0.98, 0.98))

func _visible_ids() -> Array:
	var ids := []
	var car := _edit_car if editing else _car
	var slots := 6 if editing else _slot_count()
	for entry in BUTTONS:
		var id: String = entry[0]
		if not survival and (SURVIVAL_ONLY.has(id) or CAR_IDS.has(id)):
			continue
		if not BOTH_IDS.has(id) and CAR_IDS.has(id) != car:
			continue
		if id == "shop" and not _has_shop():
			continue
		if id == "score" and not _has_scoreboard():
			continue
		if id == "shield" and not editing and not _has_shield():
			continue
		if entry[3] == "slot" and int(id.trim_prefix("weapon_")) > slots:
			continue
		ids.append(id)
	return ids

func _is_driving() -> bool:
	return survival and match_controller != null and match_controller.has_method("is_driving") and bool(match_controller.call("is_driving"))

func _has_shield() -> bool:
	return player != null and is_instance_valid(player) and not str(player.get("shield_id")).is_empty()

func _has_shop() -> bool:
	return match_controller != null and is_instance_valid(match_controller) and match_controller.get("shop") != null

func _has_scoreboard() -> bool:
	return match_controller != null and is_instance_valid(match_controller) and match_controller.get("score_panel") != null

func _entry(id: String) -> Array:
	for entry in BUTTONS:
		if entry[0] == id:
			return entry
	return []

## Escala da tela em relação aos 720 px de altura de referência.
func _ui_scale() -> float:
	return size.y / 720.0 if size.y > 0.0 else 1.0

## Centro e raio do preset atual (antes do que o jogador mexeu).
func _default_center(id: String) -> Vector2:
	if id == "joystick":
		return JOY_REST
	if preset == "4" and PRESET_4.has(id):
		return PRESET_4[id][0]
	return _entry(id)[4]

func _default_radius(id: String) -> float:
	if id == "joystick":
		return JOY_RADIUS
	if preset == "4" and PRESET_4.has(id):
		return PRESET_4[id][1]
	return float(_entry(id)[5])

func _center(id: String) -> Vector2:
	var frac := _default_center(id)
	if custom.has(id):
		var c: Vector3 = custom[id]
		frac = Vector2(c.x, c.y)
	return _to_screen(frac)

func _radius(id: String) -> float:
	var scale_one := 1.0
	if custom.has(id):
		scale_one = (custom[id] as Vector3).z
	return _default_radius(id) * scale_one * float(options["size"]) * _ui_scale()

func _alpha(id: String) -> float:
	return float(options["opacity"]) * float(custom_alpha.get(id, 1.0))

func _button_at(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _visible_ids():
		var delta := pos - _center(id)
		var d := delta.length()
		# Um pouco de folga em volta: dedo não é tão preciso quanto o mouse.
		var reach := _radius(id) * 1.15
		var inside := maxf(absf(delta.x), absf(delta.y)) <= reach if SQUARE_IDS.has(id) else d <= reach
		if inside and d < best_d:
			best = id
			best_d = d
	return best

# ------------------------------------------------------------ armas ---

## Quantas armas existem para trocar (slots 1..6).
func _slot_count() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	if bool(player.get("loadout_limited")):
		var order = player.get("slot_order")
		return mini((order as Array).size(), 6) if order is Array else 0
	return mini(WeaponData.ORDER.size(), 6)

## [nome curto, está na mão] do slot i (0..5), como no HUD de munição.
func _slot_info(i: int) -> Array:
	if player == null or not is_instance_valid(player):
		return ["", false]
	var id := ""
	var held := false
	if bool(player.get("loadout_limited")):
		var order = player.get("slot_order")
		if not (order is Array) or i >= (order as Array).size():
			return ["", false]
		id = str(order[i])
		held = bool(player.call("slot_in_hand", id)) if player.has_method("slot_in_hand") else false
	else:
		if i >= WeaponData.ORDER.size():
			return ["", false]
		id = WeaponData.ORDER[i]
		held = str(player.get("current_weapon")) == id
	var label := str(player.call("slot_label", id)) if player.has_method("slot_label") else str(WeaponData.stats(id)["name"])
	return [label.split(" ")[0].left(7).to_upper(), held]

# --------------------------------------------------------------- estado ---

func _process(delta: float) -> void:
	_update_safe()
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
	_joy.rest = _center("joystick")
	_joy.radius = _radius("joystick")
	_joy.deadzone = float(options["deadzone"])
	_joy.fixed = float(options["joy_fixed"]) > 0.5
	_joy.update(delta)
	_settings_button.visible = not PointerMode.is_captured() and not editing and not hide_all and not _settings_panel.visible
	queue_redraw()

func _release_all() -> void:
	for action in _held.keys():
		if int(_held[action]) > 0:
			_send(action, false)
	_held.clear()
	for id in _pressed_ids.keys():
		if KEYS.has(id):
			_send_key(KEYS[id], false)
	_pressed_ids.clear()
	_fingers.clear()
	_joy.release()
	_look_finger = -1
	_sprint_on = false
	_crouch_from_hold = false
	_set_joystick(Vector2.ZERO)

func _send(action: String, pressed: bool) -> void:
	# Um evento de verdade (e não só Input.action_press): quem escuta eventos,
	# como a troca de arma e o "soltar granada", também recebe.
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)

func _send_key(code: int, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code as Key
	key.physical_keycode = code as Key
	key.pressed = pressed
	get_viewport().push_input(key)

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

func _stance() -> int:
	return int(player.get("stance")) if player != null and is_instance_valid(player) and player.get("stance") != null else 0

func _press_button(id: String) -> void:
	var entry := _entry(id)
	match entry[3]:
		"hold", "slot":
			_hold(entry[2], true)
		"toggle":
			_send(entry[2], not Input.is_action_pressed(entry[2]))
		"crouch":
			if float(options["crouch_hold"]) > 0.5:
				# Segurando: agacha enquanto o dedo está em cima.
				_crouch_from_hold = _stance() == 0
				if _crouch_from_hold:
					player.set("stance", 1)
			else:
				# Alternar: igual ao Ctrl (agacha, deita, levanta).
				_hold("crouch", true)
		"sprint":
			_sprint_on = not _sprint_on
			_set_joystick(_joy.value)
		"key_hold":
			_send_key(KEYS[id], true)
		"key_tap":
			_release_all()
			_send_key(KEYS[id], true)
			_send_key(KEYS[id], false)
			return
		"pause":
			_release_all()
			_send_key(KEY_ESCAPE, true)
			_send_key(KEY_ESCAPE, false)
			return
	_pressed_ids[id] = true

func _release_button(id: String) -> void:
	var entry := _entry(id)
	if entry.is_empty():
		return
	match entry[3]:
		"hold", "slot":
			_hold(entry[2], false)
		"crouch":
			if _crouch_from_hold:
				_crouch_from_hold = false
				if _stance() == 1:
					player.set("stance", 0)
			else:
				_hold("crouch", false)
		"key_hold":
			_send_key(KEYS[id], false)
	_pressed_ids.erase(id)

func _set_joystick(vec: Vector2) -> void:
	var pairs := [["move_right", vec.x], ["move_left", -vec.x], ["move_back", vec.y], ["move_forward", -vec.y]]
	for pair in pairs:
		if float(pair[1]) > 0.01:
			Input.action_press(pair[0], float(pair[1]))
		else:
			Input.action_release(pair[0])
	# Empurrado até o fim para a frente (ou CORRER ligado e andando): corre.
	var run := (vec.length() > 0.95 and -vec.y > 0.8) or (_sprint_on and vec.length() > 0.1)
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

## Troca o preset (2 ou 4 dedos): volta as posições ao padrão dele e salva.
func apply_preset(name_id: String) -> void:
	if not PRESETS.has(name_id):
		return
	preset = name_id
	custom.clear()
	custom_alpha.clear()
	_release_all()
	_refresh_preset_buttons()
	if not editing:
		_save()

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
	var zone := Rect2(_to_screen(JOY_ZONE.position), JOY_ZONE.size * _safe.size)
	if not _car and zone.has_point(pos) and _joy.press(index, pos):
		_fingers[index] = {"kind": "joy", "last": pos}
		_set_joystick(_joy.value)
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
			_set_joystick(_joy.drag(pos))
		"look":
			_look(relative)
		"button":
			# Arrastar em cima de atirar (ou mirar) também gira a câmera.
			if finger["id"] in DRAG_LOOK_IDS and float(options["fire_drag"]) > 0.5:
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
			_joy.release()
			_set_joystick(Vector2.ZERO)
		"look":
			_look_finger = -1

# --------------------------------------------------------------- desenho ---

func _draw() -> void:
	if not _active and not editing:
		return
	var s := _ui_scale()
	if not (_edit_car if editing else _car):
		var joy_alpha := _alpha("joystick")
		_joy.draw(self, joy_alpha, s, Input.is_action_pressed("sprint"), UiTheme.ACCENT)
		if editing and _selected == "joystick":
			draw_arc(_joy.rest, _joy.radius + 4.0 * s, 0, TAU, 48, Color(UiTheme.ACCENT, 0.95), 3.0 * s)
	for id in _visible_ids():
		_draw_button(id, s)

func _draw_button(id: String, s: float) -> void:
	var entry := _entry(id)
	var alpha := _alpha(id)
	var c := _center(id)
	var br := _radius(id)
	var text: String = entry[1]
	var held_slot := false
	if entry[3] == "slot":
		var info := _slot_info(int(id.trim_prefix("weapon_")) - 1)
		held_slot = bool(info[1])
		if not str(info[0]).is_empty():
			text = str(info[0])
	var crouched: bool = entry[3] == "crouch" and _stance() > 0
	var on: bool = _pressed_ids.has(id) or (entry[3] == "toggle" and Input.is_action_pressed(entry[2])) or (entry[3] == "sprint" and _sprint_on) or crouched
	var fill := Color(UiTheme.ACCENT, 0.55 * alpha) if on else Color(0, 0, 0, 0.38 * alpha)
	if id == "fire" and not on:
		fill = Color(UiTheme.ACCENT_HOT.darkened(0.35), 0.5 * alpha)
	var outline := Color(1, 1, 1, 0.6 * alpha)
	if held_slot:
		outline = Color(UiTheme.ACCENT, 0.95 * maxf(alpha, 0.6))
	var width := (2.5 if held_slot else 2.0) * s
	if editing and id == _selected:
		outline = Color(UiTheme.ACCENT, 0.95)
		width = 3.0 * s
	if SQUARE_IDS.has(id):
		var box := Rect2(c - Vector2(br, br), Vector2(br, br) * 2.0)
		draw_rect(box, fill)
		draw_rect(box, outline, false, width)
	else:
		draw_circle(c, br, fill)
		draw_arc(c, br, 0, TAU, 40, outline, width)
	var text_color := Color(1, 1, 1, 0.95 * maxf(alpha, 0.5))
	if entry[3] == "slot":
		# Número no canto, nome curto embaixo.
		var number: String = entry[1]
		draw_string(_font, c + Vector2(-br + 4.0 * s, -br + 13.0 * s), number, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12 * s), Color(text_color, text_color.a * 0.8))
		if text == number:
			return
		var fs := int(10 * s)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		if tw > br * 1.85:
			fs = maxi(7, int(fs * br * 1.85 / tw))
			tw = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, c + Vector2(-tw * 0.5, br * 0.55), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)
		return
	var font_size := int(clampf(br * 0.42, 11.0 * s, 20.0 * s))
	if text.length() <= 2:
		font_size = int(br * 0.75)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	if w > br * 1.7:
		# Texto comprido ("FREIO DE MÃO"): encolhe para caber no círculo.
		font_size = maxi(8, int(font_size * br * 1.7 / w))
		w = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	draw_string(_font, c + Vector2(-w * 0.5, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

# ------------------------------------------------------- editar posições ---

func _edit_input(event: InputEvent) -> void:
	var bar_rect := _edit_bar.get_global_rect()
	if event is InputEventScreenTouch:
		if event.pressed:
			if bar_rect.has_point(event.position):
				return
			var id := _button_at(event.position)
			if id.is_empty() and not _edit_car and event.position.distance_to(_center("joystick")) <= _radius("joystick"):
				id = "joystick"
			_fingers[event.index] = {"kind": "edit", "id": id}
			if not id.is_empty():
				_select(id)
		else:
			_fingers.erase(event.index)
	elif _fingers.has(event.index):
		var id: String = _fingers[event.index]["id"]
		if id.is_empty():
			return
		var frac := _to_frac(event.position)
		var scale_one := (custom[id] as Vector3).z if custom.has(id) else 1.0
		custom[id] = Vector3(frac.x, frac.y, scale_one)
	get_viewport().set_input_as_handled()

func _select(id: String) -> void:
	_selected = id
	if id == "joystick":
		_edit_label.text = "Joystick"
		return
	var entry := _entry(id)
	_edit_label.text = "Botão: %s" % entry[1] if not entry.is_empty() else "Toque num botão e arraste"

func _resize_selected(step: float) -> void:
	if _selected.is_empty():
		return
	var d := _default_center(_selected)
	var c: Vector3 = custom.get(_selected, Vector3(d.x, d.y, 1.0))
	c.z = clampf(c.z + step, 0.5, 2.0)
	custom[_selected] = c

func _fade_selected(step: float) -> void:
	if _selected.is_empty():
		return
	custom_alpha[_selected] = clampf(float(custom_alpha.get(_selected, 1.0)) + step, 0.2, 1.4)

func start_editing() -> void:
	editing = true
	_edit_backup = [custom.duplicate(), options.duplicate(), custom_alpha.duplicate(), preset]
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

## Sai do editor desfazendo o que foi mexido desde que abriu.
func cancel_editing() -> void:
	if _edit_backup.size() == 4:
		custom = _edit_backup[0]
		options = _edit_backup[1]
		custom_alpha = _edit_backup[2]
		preset = _edit_backup[3]
		_refresh_preset_buttons()
	stop_editing()

# ------------------------------------------------------------- ajustes ---

func _build_settings_ui() -> void:
	_settings_button = Button.new()
	_settings_button.text = "Controles de toque"
	UiTheme.secondary(_settings_button, 14)
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
	_settings_panel.add_theme_stylebox_override("panel", UiTheme.card(20.0))
	add_child(_settings_panel)
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings_panel.custom_minimum_size = Vector2(760, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_settings_panel.add_child(col)
	col.add_child(UiTheme.title("Controles de toque", 22))

	# Preset: 2 ou 4 dedos (volta as posições ao padrão dele).
	var presets_row := HBoxContainer.new()
	presets_row.add_theme_constant_override("separation", 8)
	col.add_child(presets_row)
	for key in PRESETS:
		var b := Button.new()
		b.text = PRESETS[key]
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var preset_id: String = key
		b.pressed.connect(func(): apply_preset(preset_id))
		presets_row.add_child(b)
		_preset_buttons[key] = b
	_refresh_preset_buttons()

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	col.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	columns.add_child(left)
	_add_slider(left, "Câmera", "look", 0.3, 4.0)
	_add_slider(left, "Câmera mirando / luneta", "scope", 0.3, 2.0)
	_add_slider(left, "Zona morta do joystick", "deadzone", 0.0, 0.4)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	columns.add_child(right)
	_add_slider(right, "Transparência dos botões", "opacity", 0.2, 1.0)
	_add_slider(right, "Tamanho dos botões", "size", 0.6, 1.6)
	_add_check(right, "Joystick fixo (não segue o polegar)", "joy_fixed")
	_add_check(right, "Agachar só segurando", "crouch_hold")
	_add_check(right, "Arrastar no ATIRAR gira a câmera", "fire_drag")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var edit := Button.new()
	edit.text = "Mover botões"
	UiTheme.secondary(edit, 15)
	edit.custom_minimum_size = Vector2(0, 48)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.pressed.connect(start_editing)
	row.add_child(edit)
	var close := Button.new()
	close.text = "Fechar"
	UiTheme.primary(close, 15)
	close.custom_minimum_size = Vector2(0, 48)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(func():
		_settings_panel.visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_save())
	row.add_child(close)

	_edit_bar = PanelContainer.new()
	_edit_bar.visible = false
	_edit_bar.add_theme_stylebox_override("panel", UiTheme.card(8.0))
	add_child(_edit_bar)
	_edit_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_edit_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edit_bar.offset_top = 120
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	_edit_bar.add_child(bar)
	_edit_label = Label.new()
	_edit_label.custom_minimum_size = Vector2(170, 0)
	_edit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_edit_label)
	for spec in [["Menor", -0.1, false], ["Maior", 0.1, false], ["Mais claro", -0.15, true], ["Mais forte", 0.15, true]]:
		var b := Button.new()
		b.text = spec[0]
		UiTheme.secondary(b, 13)
		b.custom_minimum_size = Vector2(76, 46)
		var step: float = spec[1]
		var fade: bool = spec[2]
		b.pressed.connect(func():
			if fade:
				_fade_selected(step)
			else:
				_resize_selected(step))
		bar.add_child(b)
	if survival:
		# Sobrevivência: o carro tem o próprio layout de botões.
		var which := Button.new()
		which.text = "Ver: carro"
		UiTheme.secondary(which, 13)
		which.custom_minimum_size = Vector2(96, 46)
		which.pressed.connect(func():
			_edit_car = not _edit_car
			which.text = "Ver: a pé" if _edit_car else "Ver: carro"
			_select(""))
		bar.add_child(which)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	UiTheme.secondary(cancel, 13)
	cancel.custom_minimum_size = Vector2(88, 46)
	cancel.pressed.connect(cancel_editing)
	bar.add_child(cancel)
	var reset := Button.new()
	reset.text = "Padrão"
	UiTheme.secondary(reset, 13)
	reset.custom_minimum_size = Vector2(80, 46)
	reset.pressed.connect(func():
		custom.clear()
		custom_alpha.clear()
		options = DEFAULTS.duplicate()
		_select(""))
	bar.add_child(reset)
	var done := Button.new()
	done.text = "Salvar"
	UiTheme.primary(done, 13)
	done.custom_minimum_size = Vector2(88, 46)
	done.pressed.connect(stop_editing)
	bar.add_child(done)

func _refresh_preset_buttons() -> void:
	for key in _preset_buttons:
		UiTheme.tab(_preset_buttons[key], key == preset, 14)

func _add_slider(parent: Control, text: String, key: String, lo: float, hi: float) -> void:
	var label := UiTheme.label("", 14)
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = 0.01 if hi <= 0.5 else 0.05
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

func _add_check(parent: Control, text: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = text
	check.custom_minimum_size = Vector2(0, 40)
	check.button_pressed = float(options[key]) > 0.5
	check.toggled.connect(func(on: bool): options[key] = 1.0 if on else 0.0)
	_settings_panel.visibility_changed.connect(func():
		if _settings_panel.visible:
			check.set_pressed_no_signal(float(options[key]) > 0.5))
	parent.add_child(check)

func _load() -> void:
	var file := ConfigFile.new()
	if file.load(PATH) != OK:
		return
	for key in DEFAULTS:
		options[key] = float(file.get_value("options", key, DEFAULTS[key]))
	if int(file.get_value("meta", "version", 1)) < LAYOUT_VERSION:
		return # posições do layout antigo não servem no novo
	var saved_preset := str(file.get_value("meta", "preset", "2"))
	preset = saved_preset if PRESETS.has(saved_preset) else "2"
	var ids := ["joystick"]
	for entry in BUTTONS:
		ids.append(entry[0])
	for id in ids:
		var v = file.get_value("layout", id, null)
		if v is Vector3:
			custom[id] = v
		var a = file.get_value("alpha", id, null)
		if a is float or a is int:
			custom_alpha[id] = float(a)

func _save() -> void:
	var file := ConfigFile.new()
	file.set_value("meta", "version", LAYOUT_VERSION)
	file.set_value("meta", "preset", preset)
	for key in options:
		file.set_value("options", key, options[key])
	for id in custom:
		file.set_value("layout", id, custom[id])
	for id in custom_alpha:
		file.set_value("alpha", id, custom_alpha[id])
	file.save(PATH)
