extends SceneTree
## Controles de toque no treino offline: joystick anda (e corre empurrado até o
## fim), arrastar gira a câmera, botões apertam as ações, mira liga/desliga,
## pausa solta o jogo. Rodar com:  godot --headless --path . -s res://tests/touch_controls.gd -- --touch
const PointerMode = preload("res://scripts/pointer_mode.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	root.push_input(ev, true) # coordenadas já da tela 2D; headless não entrega Input.parse_input_event às janelas

func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = relative
	root.push_input(ev, true) # coordenadas já da tela 2D; headless não entrega Input.parse_input_event às janelas

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	_check(PointerMode.touch_mode(), "Modo toque ligado com --touch")
	root.get_node("Net").call("leave")
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await physics_frame
	var main := current_scene
	var player: CharacterBody3D = main.get_node("Jaime")
	var touch: Control = main.find_child("TouchControls", true, false)
	_check(touch != null, "Controles de toque criados no jogo")
	if touch == null:
		_finish()
		return
	PointerMode.capture()
	_check(not Input.emulate_mouse_from_touch, "Jogando, toque não vira clique")
	await _frames(2)
	var s: Vector2 = touch.size

	# Joystick: polegar na esquerda, arrasta para a frente.
	var start := s * Vector2(0.18, 0.7)
	_touch(0, start, true)
	_drag(0, start + Vector2(0, -80), Vector2(0, -80))
	await _frames(1)
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.3, "Joystick anda para a frente")
	_check(not Input.is_action_pressed("sprint"), "Meio joystick não corre")
	_drag(0, start + Vector2(0, -300), Vector2(0, -220))
	await _frames(1)
	_check(Input.is_action_pressed("sprint"), "Joystick no fim para a frente corre")

	# Segundo dedo: câmera.
	var yaw_before := float(player.get("yaw"))
	var look := s * Vector2(0.5, 0.35)
	_touch(1, look, true)
	_drag(1, look + Vector2(60, 0), Vector2(60, 0))
	await _frames(1)
	_check(float(player.get("yaw")) < yaw_before - 0.05, "Arrastar à direita gira a câmera")
	_touch(1, look + Vector2(60, 0), false)

	# Atirar: segurar aperta, soltar solta; arrastar em cima também mira.
	var fire: Vector2 = touch.call("_center", "fire")
	_touch(2, fire, true)
	await _frames(1)
	_check(Input.is_action_pressed("fire"), "Botão atirar aperta fire")
	yaw_before = float(player.get("yaw"))
	_drag(2, fire + Vector2(-30, 0), Vector2(-30, 0))
	await _frames(1)
	_check(float(player.get("yaw")) > yaw_before + 0.02, "Arrastar sobre atirar gira a câmera")
	_touch(2, fire, false)
	await _frames(1)
	_check(not Input.is_action_pressed("fire"), "Soltar atirar solta fire")

	# Nenhuma ação tem dois botões na tela (a pé).
	var seen := {}
	for id in touch.call("_visible_ids"):
		var entry: Array = touch.call("_entry", id)
		var action: String = entry[2]
		if action.is_empty():
			continue
		_check(not seen.has(action), "Ação %s com dois botões (%s e %s)" % [action, seen.get(action, ""), id])
		seen[action] = id

	# Seletor de armas: só os slots que existem; tocar troca a arma.
	var slots: int = touch.call("_slot_count")
	_check(slots >= 2, "Seletor mostra as armas do treino (got %d)" % slots)
	var slot2: Vector2 = touch.call("_center", "weapon_2")
	_touch(3, slot2, true)
	await _frames(2)
	_touch(3, slot2, false)
	await _frames(20)
	_check(bool((touch.call("_slot_info", 1) as Array)[1]), "Tocar no slot 2 põe a arma 2 na mão")

	# Agachar só segurando: agacha com o dedo em cima, levanta ao soltar.
	var opts: Dictionary = touch.get("options")
	opts["crouch_hold"] = 1.0
	var crouch_btn: Vector2 = touch.call("_center", "crouch")
	_touch(3, crouch_btn, true)
	await _frames(2)
	_check(int(player.get("stance")) == 1, "AGACHA segurando agacha")
	_touch(3, crouch_btn, false)
	await _frames(2)
	_check(int(player.get("stance")) == 0, "Soltar AGACHA (segurando) levanta")
	opts["crouch_hold"] = 0.0
	_touch(3, crouch_btn, true)
	_touch(3, crouch_btn, false)
	await _frames(2)
	_check(int(player.get("stance")) == 1, "AGACHA alternando: um toque agacha e fica")
	player.set("stance", 0)
	await _frames(2)

	# Mira liga/desliga.
	var aim: Vector2 = touch.call("_center", "aim")
	_touch(2, aim, true)
	_touch(2, aim, false)
	await _frames(1)
	_check(Input.is_action_pressed("aim"), "Toque na mira liga")
	_touch(2, aim, true)
	_touch(2, aim, false)
	await _frames(1)
	_check(not Input.is_action_pressed("aim"), "Segundo toque na mira desliga")

	# Soltar o polegar para de andar.
	_touch(0, start, false)
	await _frames(1)
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO, "Soltar o joystick para")
	_check(not Input.is_action_pressed("sprint"), "Soltar o joystick para de correr")

	# CORRER liga a corrida: meio joystick já corre; desligar volta a andar.
	var sprint_btn: Vector2 = touch.call("_center", "sprint")
	_touch(6, sprint_btn, true)
	_touch(6, sprint_btn, false)
	_touch(0, start, true)
	_drag(0, start + Vector2(30, -40), Vector2(30, -40))
	await _frames(1)
	_check(Input.is_action_pressed("sprint"), "CORRER ligado: andando já corre")
	_touch(6, sprint_btn, true)
	_touch(6, sprint_btn, false)
	await _frames(1)
	_check(not Input.is_action_pressed("sprint"), "CORRER desligado: volta a andar")
	_touch(0, start, false)
	await _frames(1)

	# Editor: Cancelar desfaz o que foi mexido.
	var crouch_before: Vector2 = touch.call("_center", "crouch")
	touch.call("start_editing")
	_touch(7, crouch_before, true)
	_drag(7, s * Vector2(0.4, 0.4), Vector2.ZERO)
	_touch(7, s * Vector2(0.4, 0.4), false)
	touch.call("cancel_editing")
	_check((touch.call("_center", "crouch") as Vector2).distance_to(crouch_before) < 1.0, "Cancelar no editor desfaz a mudança")
	PointerMode.capture()
	await _frames(2)

	# Botão de toque (InputEventAction) chega nas ações do jogador, como a tecla.
	var healed := [false]
	player.set("heal_handler", func(): healed[0] = true)
	var heal_ev := InputEventAction.new()
	heal_ev.action = "heal"
	heal_ev.pressed = true
	root.push_input(heal_ev)
	_check(healed[0], "Botão CURAR (ação de toque) chega no jogador")

	# Carro (sobrevivência): só botões, sem joystick; arrastar gira a câmera do carro.
	var fake := GDScript.new()
	fake.source_code = "extends Node\nvar driving := true\nvar looked := Vector2.ZERO\nfunc is_driving() -> bool:\n\treturn driving\nfunc drive_look(r: Vector2) -> void:\n\tlooked += r\n"
	fake.reload()
	var ctl := Node.new()
	ctl.set_script(fake)
	main.add_child(ctl)
	touch.set("survival", true)
	touch.set("match_controller", ctl)
	await _frames(2)
	var ids: Array = touch.call("_visible_ids")
	_check(ids.has("car_gas") and ids.has("car_left") and not ids.has("fire") and not ids.has("jump"), "Dirigindo mostra só os botões do carro (got %s)" % [ids])
	_touch(0, s * Vector2(0.18, 0.5), true) # onde nasceria o joystick
	_drag(0, s * Vector2(0.18, 0.3), Vector2(0, -150))
	await _frames(1)
	_check(not Input.is_action_pressed("move_forward"), "Dirigindo não tem joystick")
	_check(float(ctl.get("looked").length()) > 0.0, "Arrastar dirigindo gira a câmera do carro")
	_touch(0, s * Vector2(0.18, 0.3), false)
	var gas: Vector2 = touch.call("_center", "car_gas")
	var left: Vector2 = touch.call("_center", "car_left")
	_touch(0, gas, true)
	_touch(1, left, true)
	await _frames(1)
	_check(Input.is_action_pressed("move_forward") and Input.is_action_pressed("move_left"), "ACELERAR e ◀ juntos")
	_touch(0, gas, false)
	_touch(1, left, false)
	await _frames(1)
	_check(not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("move_left"), "Soltar os botões do carro solta")
	ctl.set("driving", false)
	await _frames(2)
	_check((touch.call("_visible_ids") as Array).has("fire"), "Saiu do carro: volta o layout a pé")
	touch.set("survival", false)

	# Pausa: igual Esc, solta o jogo e os controles somem.
	var pause: Vector2 = touch.call("_center", "pause")
	_touch(4, pause, true)
	_touch(4, pause, false)
	await _frames(2)
	_check(not PointerMode.is_captured(), "Pausa solta o jogo")
	_check(Input.emulate_mouse_from_touch, "Pausado, toque vira clique nos menus")
	_check(not bool(touch.get("_active")), "Controles somem pausado")

	# Editar posição: arrastar um botão muda o lugar e salva.
	touch.call("start_editing")
	var jump: Vector2 = touch.call("_center", "jump")
	_touch(5, jump, true)
	_drag(5, s * Vector2(0.5, 0.5), Vector2.ZERO)
	_touch(5, s * Vector2(0.5, 0.5), false)
	touch.call("stop_editing")
	var moved: Vector2 = touch.call("_center", "jump")
	_check(moved.distance_to(s * Vector2(0.5, 0.5)) < 2.0, "Botão arrastado no editor muda de lugar")
	var cfg := ConfigFile.new()
	_check(cfg.load("user://touch_layout.cfg") == OK and cfg.has_section_key("layout", "jump"), "Posição salva em touch_layout.cfg")

	# Preset 4 dedos: tiro vai para o alto à esquerda, mira/pulo para o alto à
	# direita; posições mexidas voltam ao padrão; o preset fica salvo.
	touch.call("apply_preset", "4")
	var fire4: Vector2 = touch.call("_center", "fire")
	_check(fire4.x < s.x * 0.4 and fire4.y < s.y * 0.5, "Preset 4 dedos: ATIRAR no alto à esquerda (got %s)" % fire4)
	_check((touch.call("_center", "jump") as Vector2).y < s.y * 0.5, "Preset 4 dedos: PULO no alto")
	_check((touch.get("custom") as Dictionary).is_empty(), "Trocar de preset volta as posições ao padrão")
	cfg = ConfigFile.new()
	cfg.load("user://touch_layout.cfg")
	_check(str(cfg.get_value("meta", "preset", "")) == "4", "Preset salvo no arquivo")
	touch.call("apply_preset", "2")

	# Área segura (notch à esquerda): nada fica embaixo dela.
	touch.set("safe_override", Rect2(Vector2(80, 0), s - Vector2(80, 0)))
	touch.call("_update_safe")
	for id in touch.call("_visible_ids"):
		var c: Vector2 = touch.call("_center", id)
		_check(c.x - float(touch.call("_radius", id)) >= 79.0 or (touch.call("_entry", id) as Array)[4].x < 0.05, "Botão %s fora da área segura" % id)
	_check((touch.call("_center", "interact") as Vector2).x > 80.0, "USAR (na borda) respeita a área segura")
	touch.set("safe_override", Rect2())
	touch.call("_update_safe")

	# Zona morta: movimento pequeno não anda; depois dela começa do zero.
	var Joy = load("res://scripts/ui/touch/virtual_joystick.gd")
	_check(Joy.apply_deadzone(Vector2(0.1, 0), 0.12) == Vector2.ZERO, "Dentro da zona morta não anda")
	_check(Joy.apply_deadzone(Vector2(0.13, 0), 0.12).x < 0.05, "Logo depois da zona morta começa devagar")
	_check(is_equal_approx(Joy.apply_deadzone(Vector2(1, 0), 0.12).x, 1.0), "Joystick no fim = 1")
	var fixed_joy = Joy.new()
	fixed_joy.fixed = true
	fixed_joy.rest = Vector2(100, 500)
	fixed_joy.radius = 70.0
	_check(not fixed_joy.press(0, Vector2(400, 500)), "Joystick fixo ignora dedo longe dele")
	_check(fixed_joy.press(0, Vector2(120, 500)) and fixed_joy.base == Vector2(100, 500), "Joystick fixo pega o dedo perto e não sai do lugar")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://touch_layout.cfg"))
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("TOUCH CONTROLS OK")
		quit(0)
	else:
		for f in failures:
			printerr("FALHOU: " + f)
		quit(1)
