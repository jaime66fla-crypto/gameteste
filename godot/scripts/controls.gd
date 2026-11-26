extends RefCounted
## Controles do jogador: cada ação do jogo, a tecla (ou botão do mouse) padrão
## e a escolhida pelo jogador em Configurações › Controles. Salvo em
## user://controls.cfg e aplicado no InputMap ao abrir o menu e o jogo.
## Código da tecla: positivo = tecla física (KEY_*); negativo = botão do mouse.
const PATH := "user://controls.cfg"

## [ação, nome na tela, grupo, padrão]
const ACTIONS := [
	["move_forward", "Andar para frente", "Movimento", KEY_W],
	["move_back", "Andar para trás", "Movimento", KEY_S],
	["move_left", "Andar para a esquerda", "Movimento", KEY_A],
	["move_right", "Andar para a direita", "Movimento", KEY_D],
	["jump", "Pular / freio de mão", "Movimento", KEY_SPACE],
	["sprint", "Correr", "Movimento", KEY_SHIFT],
	["walk", "Andar devagar", "Movimento", KEY_ALT],
	["crouch", "Agachar", "Movimento", KEY_CTRL],
	["fire", "Atirar / soco (mãos vazias)", "Combate", -MOUSE_BUTTON_LEFT],
	["aim", "Mirar", "Combate", -MOUSE_BUTTON_RIGHT],
	["reload", "Recarregar", "Combate", KEY_R],
	["grenade", "Granada (segure e solte)", "Combate", KEY_G],
	["heal", "Curar", "Combate", KEY_F],
	["holster", "Guardar a arma", "Combate", KEY_H],
	["shoulder_swap", "Alternar lado da mira", "Combate", KEY_Q],
	["lean_left", "Inclinar à esquerda (mirando)", "Combate", KEY_J],
	["lean_right", "Inclinar à direita (mirando)", "Combate", KEY_E],
	["shield", "Escudo: fixar / soltar a guarda (FIXA)", "Combate", -MOUSE_BUTTON_MIDDLE],
	["weapon_1", "Arma 1", "Armas", KEY_1],
	["weapon_2", "Arma 2", "Armas", KEY_2],
	["weapon_3", "Arma 3", "Armas", KEY_3],
	["weapon_4", "Arma 4", "Armas", KEY_4],
	["weapon_5", "Arma 5", "Armas", KEY_5],
	["weapon_6", "Arma 6", "Armas", KEY_6],
	["interact", "Interagir / entrar e sair do carro", "Geral", KEY_E],
	["inventory", "Inventário", "Sobrevivência", KEY_TAB],
	["map", "Mapa", "Sobrevivência", KEY_M],
	["manual", "Manual de sobrevivência", "Sobrevivência", KEY_L],
	["refuel", "Abastecer o carro", "Sobrevivência", KEY_T],
	["build", "Construir (abrir/fechar)", "Construção", KEY_B],
	["build_next", "Próxima peça", "Construção", KEY_C],
	["build_prev", "Peça anterior", "Construção", KEY_Z],
	["build_rotate", "Girar a peça", "Construção", KEY_R],
	["build_remove", "Desmontar (segure)", "Construção", KEY_X],
	["build_repair", "Consertar / liberar a base", "Construção", KEY_V],
]
## Pares que podem dividir a mesma tecla (mirando, E inclina; sem mirar, interage;
## construindo, R gira a peça em vez de recarregar). O soco é o clique esquerdo
## de mãos vazias (ação "fire"), não tem tecla própria.
const SHARED := [["lean_right", "interact"], ["build_rotate", "reload"]]
## Teclas que não podem ser usadas (abrem menus / ajuda).
const RESERVED := [KEY_ESCAPE, KEY_F1]

static var _bindings: Dictionary = {}

static func defaults() -> Dictionary:
	var result := {}
	for entry in ACTIONS:
		result[entry[0]] = int(entry[3])
	return result

static func label_of(action: String) -> String:
	for entry in ACTIONS:
		if entry[0] == action:
			return str(entry[1])
	return action

## Lê o arquivo e aplica no InputMap (chamado pelo menu e pelo jogo).
static func load_and_apply(path: String = PATH) -> void:
	_bindings = defaults()
	var file := ConfigFile.new()
	if file.load(path) == OK:
		for action in _bindings:
			var code := int(file.get_value("controls", action, _bindings[action]))
			if code != 0 and not RESERVED.has(code):
				_bindings[action] = code
		# Configurações antigas usavam Q para inclinar: migra só o padrão antigo.
		if not file.has_section_key("controls", "shoulder_swap"):
			if int(_bindings["lean_left"]) == KEY_Q:
				_bindings["lean_left"] = _unused_key(KEY_J, "lean_left")
			for action in _bindings:
				if action != "shoulder_swap" and int(_bindings[action]) == KEY_Q:
					_bindings["shoulder_swap"] = _unused_key(KEY_BRACKETLEFT, "shoulder_swap")
					break
	apply()

static func _unused_key(preferred: int, except_action: String) -> int:
	for candidate in [preferred, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH, KEY_SEMICOLON, KEY_APOSTROPHE]:
		var used := false
		for action in _bindings:
			if action != except_action and int(_bindings[action]) == int(candidate):
				used = true
		if not used:
			return int(candidate)
	return KEY_F8

static func save(path: String = PATH) -> Error:
	var file := ConfigFile.new()
	for action in _bindings:
		file.set_value("controls", action, _bindings[action])
	return file.save(path)

static func binding(action: String) -> int:
	if _bindings.is_empty():
		_bindings = defaults()
	return int(_bindings.get(action, 0))

static func _shares(a: String, b: String) -> bool:
	for pair in SHARED:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false

## Troca a tecla de uma ação. Se outra ação já usava essa tecla, as duas trocam
## (ninguém fica com duas ações na mesma tecla sem querer). Devolve o nome da
## ação que trocou, ou "".
static func set_binding(action: String, code: int) -> String:
	if _bindings.is_empty():
		_bindings = defaults()
	var old := binding(action)
	var swapped := ""
	for other in _bindings:
		if other != action and int(_bindings[other]) == code and not _shares(action, other):
			_bindings[other] = old
			swapped = label_of(other)
	_bindings[action] = code
	apply()
	return swapped

static func reset() -> void:
	_bindings = defaults()
	apply()

## Escreve as teclas no InputMap.
static func apply() -> void:
	if _bindings.is_empty():
		_bindings = defaults()
	for action in _bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event_for(int(_bindings[action])))

static func event_for(code: int) -> InputEvent:
	if code < 0:
		var mouse := InputEventMouseButton.new()
		mouse.button_index = -code
		return mouse
	var key := InputEventKey.new()
	key.physical_keycode = code
	return key

## Código de um evento apertado na tela "pressione uma tecla" (0 = não serve).
static func code_of(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return 0 if RESERVED.has(code) else code
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return 0
		return -int(event.button_index)
	return 0

## Nome curto da tecla para a tela ("Espaço", "Botão direito", "Q").
static func key_name(code: int) -> String:
	if code < 0:
		match -code:
			MOUSE_BUTTON_LEFT: return "Botão esquerdo"
			MOUSE_BUTTON_RIGHT: return "Botão direito"
			MOUSE_BUTTON_MIDDLE: return "Botão do meio"
			MOUSE_BUTTON_XBUTTON1: return "Botão lateral 1"
			MOUSE_BUTTON_XBUTTON2: return "Botão lateral 2"
		return "Mouse %d" % -code
	match code:
		KEY_SPACE: return "Espaço"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
		KEY_BACKSPACE: return "Backspace"
		KEY_CAPSLOCK: return "Caps Lock"
		KEY_UP: return "Seta ↑"
		KEY_DOWN: return "Seta ↓"
		KEY_LEFT: return "Seta ←"
		KEY_RIGHT: return "Seta →"
	var text := OS.get_keycode_string(code)
	return text if not text.is_empty() else "Tecla %d" % code

## Texto de ajuda (F1) com as teclas atuais.
static func help_text() -> String:
	var k := func(action: String) -> String: return key_name(binding(action))
	return "%s%s%s%s mover  %s andar devagar  %s correr  %s agachar  %s pular  |  %s mirar (+%s/%s inclinar)  %s alternar lado da mira  %s atirar (sem arma: soco)  %s recarregar  %s guardar arma\n%s-%s armas  %s interagir  %s curar  %s granada (segure)  |  Sobrevivência: %s inventário  %s mapa  %s construir  |  ESC liberar o mouse  ·  Teclas em Configurações › Controles" % [
		k.call("move_forward"), k.call("move_left"), k.call("move_back"), k.call("move_right"), k.call("walk"), k.call("sprint"), k.call("crouch"), k.call("jump"),
		k.call("aim"), k.call("lean_left"), k.call("lean_right"), k.call("shoulder_swap"), k.call("fire"), k.call("reload"), k.call("holster"),
		k.call("weapon_1"), k.call("weapon_5"), k.call("interact"), k.call("heal"), k.call("grenade"), k.call("inventory"), k.call("map"), k.call("build")]
