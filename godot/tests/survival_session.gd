extends Node
## Sobrevivência sem servidor: abre a cena principal com um pacote "start"
## falso e simula mensagens do servidor (zumbis, mochila, recipiente, morte).
## godot --headless --path godot res://tests/survival_session.tscn
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _run() -> void:
	var spawn: Array = SurvivalData.world()["spawns"][0]
	Net.my_id = "me"
	Net.host_id = "me"
	Net.in_match = true
	Net.start_info = {
		"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 0},
		"you": {"id": "me", "p": [spawn[0], 0.2, spawn[1]], "hp": 100, "hunger": 85, "thirst": 85, "dead": false,
			"inv": {"water_bottle": 1, "bandage": 1}, "weight": 0.7, "cap": 20},
		"roster": [{"id": "p2", "name": "Amigo", "rank": "Recruta", "p": [spawn[0] + 4, 0.2, spawn[1]], "dead": false}],
		"zombies": [{"id": "z1", "kind": "walker", "hp": 60, "p": [spawn[0] + 15, 0.2, spawn[1]]}],
		"bags": [], "searched": [], "depleted": {},
		"vehicles": [{"id": "v0", "kind": "sedan", "color": "#8c1d18", "p": [spawn[0] + 6, 0, spawn[1]], "yaw": 0.0, "fuel": 30, "driver": null}],
	}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(20)
	var controller := main.get_node_or_null("SurvivalController")
	check(controller != null, "controlador da sobrevivência criado")
	if controller == null:
		get_tree().quit(1)
		return
	check(main.get_node_or_null("SurvivalWorld") != null, "mundo aberto montado")
	check(controller.zombies.has("z1") and controller.actors.has("p2"), "zumbi e outro jogador aparecem")
	check(controller.zombies["z1"].controlled, "anfitrião controla os zumbis")
	var player: CharacterBody3D = main.get("player")
	# Arma chega na mochila: aparece descarregada, com a munição como reserva.
	Net.message.emit({"t": "inv", "inv": {"w_pistol": 1, "a_9mm": 24, "water_bottle": 1}, "weight": 1.84, "cap": 20})
	await _frames(2)
	check(player.get("owned_weapons").has("pistol"), "pistola equipável")
	check(int(player.get("reserve_ammo")["pistol"]) == 24 and int(player.get("ammo")) == 0, "munição da mochila vira reserva, pente vazio")
	Net.message.emit({"t": "inv", "inv": {"water_bottle": 1}, "weight": 0.6, "cap": 20})
	await _frames(2)
	check(not player.get("owned_weapons").has("pistol"), "arma largada sai das mãos")
	Net.message.emit({"t": "container", "k": "k0", "title": "Geladeira", "items": {"soda": 2}})
	await _frames(2)
	check(controller.inventory.visible, "revistar abre o inventário")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and controller.call("ui_open"), "mochila aberta mostra o ponteiro")
	controller.inventory.call("close")
	# Quem sai do jogo fica deitado, dormindo, e some quando volta.
	Net.message.emit({"t": "sleep", "id": "sl1", "name": "Dorminhoco", "p": [spawn[0] + 3, 0.2, spawn[1]], "y": 0.5})
	await _frames(2)
	var sleeper = controller.sleepers.get("sl1")
	check(sleeper != null and bool(sleeper.get("sleeping")) and is_equal_approx(sleeper.get("visual").rotation.x, PI * 0.5), "quem saiu fica deitado dormindo")
	check(sleeper != null and int(sleeper.collision_layer) == 0, "corpo dormindo não bloqueia nem leva tiro")
	Net.message.emit({"t": "wake", "id": "sl1"})
	await _frames(2)
	check(not controller.sleepers.has("sl1"), "quem voltou não fica mais dormindo")
	Net.message.emit({"t": "zspawn", "l": [{"id": "z2", "kind": "brute", "hp": 150, "p": [spawn[0] - 20, 0.2, spawn[1]]}]})
	Net.message.emit({"t": "zdead", "id": "z1", "by": "me", "zone": "head"})
	await _frames(2)
	check(controller.zombies.has("z2") and not controller.zombies.has("z1"), "zumbis nascem e morrem")
	Net.message.emit({"t": "clock", "day_ms": 1440000, "time": 1300000, "online": 2, "zombies": 1})
	await _frames(2)
	check(controller.night, "relógio: 21h é noite")
	Net.message.emit({"t": "hp", "id": "me", "hp": 0, "by": "z2", "w": "zombie", "killed": true})
	await _frames(2)
	check(controller.local_dead and controller.death_panel.visible, "morte mostra a tela de renascer")
	Net.message.emit({"t": "respawned", "p": [spawn[0], 0.2, spawn[1]], "hp": 100, "hunger": 85, "thirst": 85, "inv": {"bandage": 1}, "weight": 0.1, "cap": 20})
	await _frames(2)
	check(not controller.local_dead and player.visible, "renasce")
	# Mochila nas costas: aparece no personagem e aumenta a carga.
	Net.message.emit({"t": "inv", "inv": {"bandage": 1}, "back": "backpack", "weight": 0.9, "cap": 34})
	await _frames(3)
	var avatar = player.get("humanoid_avatar")
	check(avatar != null and str(avatar.get("backpack_id")) == "backpack", "mochila equipada aparece nas costas")
	check(controller.inventory.get("back") == "backpack" and is_equal_approx(float(controller.inventory.get("cap")), 34.0), "inventário mostra o slot das costas")
	check(main.get_node_or_null("SurvivalWorld").call("in_tall_grass", Vector3(float(SurvivalData.world()["grass"][0]["x"]), 0, float(SurvivalData.world()["grass"][0]["z"]))), "grama alta reconhecida")
	var hud: CanvasLayer = main.get_node_or_null("Hud")
	check(hud != null and hud.get_node_or_null("Minimap") != null and hud.get_node_or_null("AmmoHud") != null, "HUD com minimapa e munição")
	var minimap: Node = hud.get_node_or_null("Minimap") if hud != null else null
	if minimap != null:
		var coords: Vector2i = minimap.call("coords_of", Vector3(0, 0, 0))
		var half := float(SurvivalData.world().get("half_size", 240))
		check(coords == Vector2i(int(half), int(half)), "coordenadas: centro do mapa = metade do tamanho")
		check(minimap.call("heading_of", 0.0) == [0, "N"] and minimap.call("heading_of", -PI * 0.5) == [90, "L"] and minimap.call("heading_of", PI * 0.5) == [270, "O"], "direção: norte, leste e oeste")
		var coords_text := minimap.find_child("CoordsText", true, false) as Label
		check(coords_text != null and coords_text.text.begins_with("X "), "coordenadas ao lado do minimapa")
	# Ping: o "pong" do servidor devolve o relógio; o contador fica embaixo do FPS.
	Net.call("_handle", {"t": "pong", "c": Time.get_ticks_msec() - 50})
	check(absf(float(Net.ping_ms) - 50.0) < 20.0, "ping medido pelo pong (%.0f ms)" % float(Net.ping_ms))
	main.call("_update_fps_label")
	var ping_label := main.get("ping_label") as Label
	check(ping_label != null and ping_label.text.ends_with(" ms") and ping_label.text != "— ms", "contador de ping embaixo do FPS")
	check(str(main.get("hud").text).find("ARMA:") < 0, "sem o bloco de texto antigo na tela")
	# Carro: entra (servidor confirma), dirige com W, sai.
	var driving: Node = controller.driving_ctl
	check(driving.vehicles.has("v0"), "carro do servidor aparece no mapa")
	player.global_position = driving.vehicles["v0"].global_position + Vector3(2, 0.1, 0)
	await _frames(2)
	check(str(controller.call("_find_target").get("type", "")) == "vehicle", "E perto do carro: dirigir")
	driving.call("request_enter", "v0")
	var vp: Vector3 = driving.vehicles["v0"].global_position
	Net.message.emit({"t": "veh", "id": "v0", "kind": "sedan", "color": "#8c1d18", "p": [vp.x, vp.y, vp.z], "yaw": 0.0, "fuel": 30, "driver": "me"})
	await _frames(2)
	check(controller.call("is_driving") and not player.visible, "dirigindo: personagem entra no carro")
	var car: Node3D = driving.vehicles["v0"]
	var start := car.global_position
	Input.action_press("move_forward")
	await _frames(90)
	Input.action_release("move_forward")
	check(car.global_position.distance_to(start) > 3.0, "W acelera o carro (andou %.1f m)" % car.global_position.distance_to(start))
	check(player.global_position.distance_to(car.global_position) < 1.0, "o jogador viaja junto com o carro")
	# Curva: as rodas da frente viram e o eixo traseiro segue sem escorregar de lado.
	var half_wb := float(load("res://scripts/survival/car_model.gd").KINDS["sedan"]["wb"]) * 0.5
	Input.action_press("move_forward")
	Input.action_press("move_left")
	var yaw0 := car.rotation.y
	var worst_slip := 0.0
	var front_steer := 0.0
	var rear_prev: Vector3 = car.global_transform * Vector3(0, 0, half_wb)
	for i in 50:
		await get_tree().physics_frame
		var rear_now: Vector3 = car.global_transform * Vector3(0, 0, half_wb)
		var move := rear_now - rear_prev
		move.y = 0.0
		var side := car.global_basis.x
		side.y = 0.0
		if move.length() > 0.02:
			worst_slip = maxf(worst_slip, absf(move.normalized().dot(side.normalized())))
		rear_prev = rear_now
		var wheel := car.find_child("Wheel_FL", true, false) as Node3D
		if wheel != null:
			front_steer = maxf(front_steer, wheel.rotation.y)
	Input.action_release("move_left")
	Input.action_release("move_forward")
	check(absf(wrapf(car.rotation.y - yaw0, -PI, PI)) > 0.15, "A/D fazem curva")
	check(front_steer > 0.1, "as rodas da frente viram na curva")
	check(worst_slip < 0.12, "eixo traseiro não escorrega de lado na curva (deslize %.2f)" % worst_slip)
	car.set("fuel", 0.0)
	var parked := car.global_position
	car.set("speed", 0.0)
	Input.action_press("move_forward")
	await _frames(60)
	Input.action_release("move_forward")
	check(car.global_position.distance_to(parked) < 0.5, "sem gasolina o carro não anda")
	car.set("fuel", 30.0) # motor ligado ao sair (o caso do bug)
	car.call("set_engine", true)
	var exit_key := InputEventKey.new()
	exit_key.physical_keycode = KEY_E
	exit_key.pressed = true
	controller.call("_unhandled_input", exit_key)
	await _frames(2)
	check(not controller.call("is_driving") and player.visible, "E sai do carro")
	# Sem a resposta do servidor ainda: o motor desliga e não religa sozinho.
	await _frames(60)
	var car_audio: Node = car.get("_audio")
	check(not bool(car.get("engine_on")) and car_audio != null and not bool(car_audio.get("running")), "ao sair, o motor desliga e não fica roncando")
	# Golpe de machado: a ferramenta aparece na mão do personagem.
	player.call("start_channel", "CORTANDO", 3.0, func(): pass) # o golpe dura enquanto a coleta corre
	controller.call("_set_action", "chop", "axe")
	await _frames(5)
	var av = player.get("humanoid_avatar")
	check(av != null and str(av.get("work_action")) == "chop" and av.get("_tool_node") != null, "machado na mão golpeando")
	controller.call("_set_action", "", "")
	player.set("channel_left", 0.0)
	# Bastão longo: Q faz o golpe lateral (e some depois do golpe).
	Net.message.emit({"t": "inv", "inv": {"long_bat": 1}, "weight": 1.7, "cap": 20})
	await _frames(2)
	controller.set("_melee_timer", 0.0)
	controller.call("_melee")
	await _frames(3)
	check(str(av.get("work_action")) == "swing" and av.get("_tool_node") != null, "bastão longo: golpe lateral com o bastão na mão")
	await _frames(50)
	check(str(av.get("work_action")).is_empty(), "o golpe termina sozinho")
	# Carro: batida forte avisa o servidor; quebrado = carcaça e E conserta (com kit).
	Net.message.emit({"t": "veh", "id": "v0", "kind": "sedan", "color": "#8c1d18", "p": [car.global_position.x, car.global_position.y, car.global_position.z], "yaw": 0.0, "fuel": 0, "driver": null, "hp": 20, "broken": false})
	await _frames(2)
	check(car.get("_smoke").emitting, "carro muito batido solta fumaça")
	Net.message.emit({"t": "boom", "id": "v0", "p": [car.global_position.x, 0, car.global_position.z]})
	Net.message.emit({"t": "veh", "id": "v0", "kind": "sedan", "color": "#8c1d18", "p": [car.global_position.x, car.global_position.y, car.global_position.z], "yaw": 0.0, "fuel": 0, "driver": null, "hp": 0, "broken": true})
	await _frames(2)
	check(bool(car.get("broken")) and not bool(car.get("engine_on")), "carro explode e fica quebrado")
	Net.message.emit({"t": "inv", "inv": {"repair_kit": 1}, "weight": 2.5, "cap": 20})
	player.global_position = car.global_position + Vector3(2, 0.1, 0)
	await _frames(2)
	var target: Dictionary = controller.call("_find_target")
	check(str(target.get("type", "")) == "repair" and str(target.get("label", "")).find("Consertar") >= 0, "E perto do carro quebrado: consertar com o kit")
	# Mordida: relógio da infecção de 2 minutos; vacina cura.
	Net.message.emit({"t": "infected", "left": 120})
	await _frames(2)
	check(controller.infection_clock.visible and controller.infected_left > 110.0, "mordida mostra o relógio da infecção")
	Net.message.emit({"t": "infected", "left": 0})
	await _frames(2)
	check(not controller.infection_clock.visible, "vacina tira o relógio")
	# Mapa (M).
	var m_key := InputEventKey.new()
	m_key.physical_keycode = KEY_M
	m_key.pressed = true
	controller.call("_unhandled_input", m_key)
	await _frames(2)
	check(controller.world_map.visible, "M abre o mapa")
	controller.call("_unhandled_input", m_key)
	check(not controller.world_map.visible, "M fecha o mapa")
	print("FALHAS: %d" % failures)
	Net.in_match = false
	get_tree().quit(1 if failures else 0)
