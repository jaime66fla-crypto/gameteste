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

## Construção: peças do servidor aparecem com colisão, a porta abre, a prévia
## encaixa na grade e a peça destruída some.
func _building(controller: Node, player: CharacterBody3D) -> void:
	var b: Node = controller.building_ctl
	check(b != null, "construção ligada ao controlador")
	var rules = b.get("rules")
	var S: float = rules.S
	# Um canto sem árvore/rocha perto do jogador (só para não atrapalhar a colisão).
	var i := floori(player.global_position.x / S) + 2
	var j := floori(player.global_position.z / S) + 2
	b.set("my_tag", "me")
	var pieces := [
		{"id": "P1", "kind": "foundation", "i": i, "j": j, "k": 0, "hp": 800, "ow": "me"},
		{"id": "P2", "kind": "wall", "i": i, "j": j, "k": 0, "o": "h", "hp": 500, "ow": "me"},
		{"id": "P3", "kind": "doorway", "i": i, "j": j, "k": 0, "o": "v", "hp": 450, "ow": "me"},
		{"id": "P4", "kind": "door", "i": i, "j": j, "k": 0, "o": "v", "hp": 300, "ow": "me", "open": false},
		{"id": "P5", "kind": "window", "i": i + 1, "j": j, "k": 0, "o": "v", "hp": 450, "ow": "me"},
		{"id": "P6", "kind": "floor", "i": i, "j": j, "k": 1, "hp": 400, "ow": "me"},
		{"id": "P7", "kind": "roof", "i": i, "j": j, "k": 2, "r": 1, "hp": 400, "ow": "x"},
		{"id": "P8", "kind": "stairs", "i": i, "j": j, "k": 0, "r": 2, "hp": 350, "ow": "me"},
		{"id": "P9", "kind": "campfire", "p": [(i + 0.3) * S, rules.base, (j + 0.3) * S], "y": 0.0, "hp": 120, "ow": "me", "on": true},
		{"id": "P10", "kind": "chest", "p": [(i + 0.7) * S, rules.base, (j + 0.7) * S], "y": 1.0, "hp": 200, "ow": "me"},
		{"id": "P11", "kind": "bed", "p": [(i - 1.0) * S, 0.0, (j + 0.5) * S], "y": 0.0, "hp": 150, "ow": "me", "cd": 0},
	]
	for p in pieces:
		Net.message.emit({"t": "bp", "b": p})
	await _frames(3)
	var nodes: Dictionary = b.get("nodes")
	check(nodes.size() == pieces.size(), "todas as peças aparecem (%d)" % nodes.size())
	var wall: Node3D = nodes.get("P2")
	var bodies := wall.find_children("*", "StaticBody3D", true, false) if wall != null else []
	check(not bodies.is_empty() and str(bodies[0].get_meta("build_id", "")) == "P2", "parede tem colisão marcada com o id")
	# Raio de cima atinge o piso do primeiro andar.
	var space := player.get_world_3d().direct_space_state
	var c := Vector3((i + 0.5) * S, 10, (j + 0.25) * S)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(c, c + Vector3.DOWN * 20))
	check(not hit.is_empty() and str(b.call("build_id_of", hit["collider"])) in ["P6", "P7"], "teto/telhado bloqueia de cima")
	check(nodes["P9"].get_node_or_null("FireLight") != null, "fogueira acesa tem luz")
	Net.message.emit({"t": "bp", "b": {"id": "P9", "kind": "campfire", "p": pieces[8]["p"], "y": 0.0, "hp": 120, "ow": "me", "on": false}})
	await _frames(2)
	check(nodes["P9"].get_node_or_null("FireLight") == null or nodes["P9"].get_node("FireLight").is_queued_for_deletion(), "apagar a fogueira tira a luz")
	# Porta: E perto dela abre (o servidor confirma com "bp").
	var door_c: Vector3 = rules.center(pieces[3])
	player.global_position = Vector3(door_c.x - 1.2, rules.base + 0.1, door_c.z)
	await _frames(2)
	var t: Dictionary = controller.call("_find_target")
	check(str(t.get("type", "")) == "build" and str(t.get("label", "")).find("Abrir a porta") >= 0, "E perto da porta: abrir")
	var piece4: Dictionary = pieces[3].duplicate()
	piece4["open"] = true
	Net.message.emit({"t": "bp", "b": piece4})
	await _frames(30)
	var hinge := nodes["P4"].get_node("Hinge") as Node3D
	check(absf(hinge.rotation.y) > 1.2, "porta abre girando na dobradiça")
	check(controller.call("is_building") == false, "modo de construção começa desligado")
	# Modo de construção: prévia da fundação na célula vizinha, verde com material.
	Net.message.emit({"t": "inv", "inv": {"wood": 50, "stone": 50, "fiber": 20, "rope": 5}, "weight": 9, "cap": 60})
	var bkey := InputEventKey.new()
	bkey.physical_keycode = KEY_B
	bkey.pressed = true
	controller.call("_unhandled_input", bkey)
	check(controller.call("is_building"), "B liga o modo de construção")
	var cand: Dictionary = b.call("_candidate_for", "foundation", {"point": Vector3((i + 0.9) * S, rules.base + 0.05, (j + 0.5) * S), "surface": Vector3.ZERO, "normal": Vector3.UP, "build": "P1", "hit": true})
	check(int(cand.get("i", -99)) == i + 1 and int(cand.get("j", -99)) == j, "fundação mirando a beira de outra: célula vizinha")
	check(str(rules.check(cand, b.owns)) == "", "fundação vizinha pode")
	var bad: Dictionary = {"kind": "wall", "i": i + 5, "j": j + 5, "k": 0, "o": "h"}
	check(str(rules.check(bad, b.owns)).find("Precisa") >= 0, "parede no nada não pode")
	var on_roof: Dictionary = {"kind": "floor", "i": i + 1, "j": j, "k": 2}
	check(str(rules.check({"kind": "wall", "i": i, "j": j, "k": 1, "o": "h"}, b.owns)) == "", "parede no primeiro andar em cima do piso")
	check(str(rules.check(on_roof, b.owns)) != "", "piso sem parede embaixo não pode")
	await _frames(6)
	check(b.get("_bar").visible, "barra de peças aparece")
	controller.call("_unhandled_input", bkey)
	check(not controller.call("is_building"), "B desliga")
	# Fundação quebrada: some ela e tudo o que ela segurava (o servidor manda a lista).
	Net.message.emit({"t": "bgone", "l": ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10"], "by": "z1"})
	await _frames(2)
	check(nodes.size() == 1 and nodes.has("P11"), "peças destruídas somem (sobra a cama no chão)")
	check(b.call("has_bed"), "cama conta como ponto de renascer")

## Animais: nascem com modelo, o anfitrião manda a posição, coelho foge de
## quem chega perto, lobo persegue e morde, morto vira carcaça.
func _animals(controller: Node, player: CharacterBody3D) -> void:
	var base := player.global_position + Vector3(0, 0, 0)
	Net.message.emit({"t": "aspawn", "l": [
		{"id": "a1", "kind": "rabbit", "hp": 15, "p": [base.x + 5, 0.2, base.z]},
		{"id": "a2", "kind": "deer", "hp": 80, "p": [base.x + 40, 0.2, base.z]},
		{"id": "a3", "kind": "boar", "hp": 110, "p": [base.x - 40, 0.2, base.z]},
		{"id": "a4", "kind": "wolf", "hp": 70, "p": [base.x, 0.2, base.z + 12]},
	]})
	await _frames(3)
	check(controller.animals.size() == 4, "4 animais aparecem")
	var all_have_model := true
	for a in controller.animals.values():
		all_have_model = all_have_model and a.visual != null and not a.visual.find_children("*", "MeshInstance3D", true, false).is_empty()
	check(all_have_model, "cada animal tem modelo 3D")
	check(controller.animals["a4"].controlled, "anfitrião controla os animais")
	var rabbit: Node3D = controller.animals["a1"]
	var r0 := rabbit.global_position.distance_to(player.global_position)
	var wolf: Node3D = controller.animals["a4"]
	wolf.call("apply_needs", 30.0, 80.0) # hungry wolves hunt; satiated wolves rest
	var w0 := wolf.global_position.distance_to(player.global_position)
	var bites := [0]
	controller.animals["a4"].attacked.connect(func(_a, _t): bites[0] += 1)
	player.set_physics_process(false) # parado, para o lobo chegar
	await _frames(150)
	check(rabbit.global_position.distance_to(player.global_position) > r0 + 3.0, "coelho foge de quem chega perto (%.1f → %.1f m)" % [r0, rabbit.global_position.distance_to(player.global_position)])
	check(wolf.global_position.distance_to(player.global_position) < w0 - 5.0, "lobo vem atrás (%.1f → %.1f m)" % [w0, wolf.global_position.distance_to(player.global_position)])
	wolf.global_position = player.global_position + Vector3(0, 0, 1.2)
	wolf.call("hurt", "me", player) # isolate retaliation from hunting the nearby rabbit
	await _frames(90)
	check(bites[0] > 0, "lobo morde quem alcança")
	player.set_physics_process(true)
	Net.message.emit({"t": "adead", "id": "a4", "by": "me", "zone": "chest"})
	Net.message.emit({"t": "bag", "bag": {"id": "bz", "p": [wolf.global_position.x, 0, wolf.global_position.z], "name": "", "title": "Carcaça de lobo", "count": 3}})
	await _frames(3)
	check(not controller.animals.has("a4"), "lobo morto sai da lista")
	player.global_position = wolf.global_position + Vector3(0.8, 0.1, 0)
	await _frames(3)
	var t: Dictionary = controller.call("_find_target")
	check(str(t.get("label", "")).find("carcaça de lobo") >= 0, "E perto da carcaça: abrir (%s)" % str(t.get("label", "")))
	Net.message.emit({"t": "agone", "l": ["a1", "a2", "a3"]})
	await _frames(2)
	check(controller.animals.is_empty(), "animais longe somem")

func _run() -> void:
	var spawn: Array = SurvivalData.world()["spawns"][0]
	# Carro de teste no meio do maior lago: chão plano e sem árvore para a curva.
	var big: Dictionary = {}
	for p in SurvivalData.world().get("ponds", []):
		if big.is_empty() or float(p["r"]) > float(big["r"]):
			big = p
	var car_at := [float(big["x"]), 0, float(big["z"]) + float(big["r"]) * 0.7] if not big.is_empty() else [spawn[0] + 6, 0, spawn[1]]
	Net.my_id = "me"
	Net.host_id = "me"
	Net.in_match = true
	Net.start_info = {
		"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 0},
		"you": {"id": "me", "p": [spawn[0], 0.2, spawn[1]], "hp": 100, "hunger": 85, "thirst": 85, "dead": false,
			"inv": {"berries": 1, "bandage": 1}, "weight": 0.2, "cap": 10},
		"roster": [{"id": "p2", "name": "Amigo", "rank": "Recruta", "p": [spawn[0] + 4, 0.2, spawn[1]], "dead": false}],
		"zombies": [{"id": "z1", "kind": "walker", "hp": 60, "p": [spawn[0] + 15, 0.2, spawn[1]]}],
		"bags": [], "searched": [], "depleted": {},
		"vehicles": [{"id": "v0", "kind": "sedan", "color": "#8c1d18", "p": car_at, "yaw": 0.0, "fuel": 30, "driver": null}],
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
	check(main.get_node_or_null("WorldPolish") == null, "sem a cidade antiga no meio")
	check(player.get("owned_weapons").is_empty(), "começa sem arma de fogo")
	# Coleta na floresta: galho sem ferramenta; árvore pede o machado de pedra; lago dá água.
	var world_node: Node3D = main.get_node_or_null("SurvivalWorld")
	# Um de cada tipo sem outro recurso a menos de 4,5 m (o E pega o mais perto).
	var first := {}
	for kind in ["stick", "tree", "pond"]:
		for id in world_node.resources:
			var entry: Dictionary = world_node.resources[id]
			if str(entry["kind"]) != kind:
				continue
			var alone := true
			if kind != "pond":
				for other in world_node.resources:
					var o: Dictionary = world_node.resources[other]
					if other != id and (o["pos"] as Vector3).distance_to(entry["pos"]) < 4.5 + float(o.get("r", 0.0)):
						alone = false
						break
			if alone:
				first[kind] = entry
				break
	player.global_position = (first["stick"]["pos"] as Vector3) + Vector3(0.8, 0.1, 0)
	await _frames(2)
	var t: Dictionary = controller.call("_find_target")
	check(str(t.get("kind", "")) == "stick" and str(t.get("label", "")).find("Galho") >= 0 and not bool(t.get("missing", true)), "E perto do galho: pegar sem ferramenta")
	player.global_position = (first["tree"]["pos"] as Vector3) + Vector3(1.2, 0.1, 0)
	await _frames(2)
	t = controller.call("_find_target")
	check(str(t.get("kind", "")) == "tree" and bool(t.get("missing", false)) and str(t.get("label", "")).find("machado de pedra") >= 0, "árvore sem machado: avisa que precisa do machado de pedra")
	Net.message.emit({"t": "inv", "inv": {"stone_axe": 1}, "weight": 1.6, "cap": 10})
	await _frames(2)
	t = controller.call("_find_target")
	check(not bool(t.get("missing", true)) and str(t.get("tool", "")) == "stone_axe", "com o machado de pedra corta a árvore")
	var pond: Dictionary = first["pond"]
	# Ponto da margem sem galho/capim por perto.
	var shore := (pond["pos"] as Vector3) + Vector3(float(pond["r"]) + 1.0, 0, 0)
	for step in 24:
		var a := TAU * step / 24.0
		var spot := (pond["pos"] as Vector3) + Vector3(cos(a), 0, sin(a)) * (float(pond["r"]) + 1.0)
		var clear := true
		for other in world_node.resources:
			var o: Dictionary = world_node.resources[other]
			if str(o["kind"]) != "pond" and (o["pos"] as Vector3).distance_to(spot) < 4.0:
				clear = false
				break
		if clear:
			shore = spot
			break
	player.global_position = shore + Vector3(0, 0.1, 0)
	await _frames(2)
	t = controller.call("_find_target")
	check(str(t.get("kind", "")) == "pond" and str(t.get("label", "")).find("Beber") >= 0, "na margem do lago: beber água")
	check(world_node.call("in_pond", pond["pos"]), "lago reconhecido")
	player.global_position = Vector3(float(spawn[0]), 0.3, float(spawn[1]))
	controller.inventory.call("open")
	await _frames(2)
	check(int(controller.inventory.get("_tab")) == 1, "TAB abre direto nas receitas")
	controller.inventory.call("close")
	Net.message.emit({"t": "container", "k": "b1", "title": "Mochila de Amigo", "items": {"wood": 2}})
	await _frames(2)
	check(controller.inventory.visible, "abrir mochila do chão abre o inventário")
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
	await _frames(20) # a luz do dia é atualizada 4 vezes por segundo
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
	var side_position := player.global_position
	var parked_car: Node3D = driving.vehicles["v0"]
	player.global_position = parked_car.to_global(Vector3(0, 0.1, 3.0))
	check(str(driving.call("target_near", player.global_position).get("type", "")) == "trunk", "E atrás do carro: abrir porta-malas")
	player.global_position = side_position
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
	controller.call("_set_action", "chop", "stone_axe")
	await _frames(5)
	var av = player.get("humanoid_avatar")
	check(av != null and str(av.get("work_action")) == "chop" and av.get("_tool_node") != null, "machado de pedra na mão golpeando")
	controller.call("_set_action", "pry", "stone_pick")
	await _frames(3)
	check(av.get("_tool_node") != null, "picareta de pedra na mão")
	controller.call("_set_action", "", "")
	player.set("channel_left", 0.0)
	# Clava: ganha um slot; pega no slot, segura na mão e o clique faz o golpe lateral.
	Net.message.emit({"t": "inv", "inv": {"club": 1}, "weight": 1.4, "cap": 10})
	await _frames(2)
	var club_slot := (player.get("slot_order") as Array).find("club") + 1
	check(club_slot > 0, "clava ganha um slot")
	player.call("select_melee", "club")
	await _frames(2)
	check(str(av.get("work_action")) == "hold" and str(av.get("work_tool")) == "club", "clava do slot aparece na mão")
	controller.set("_melee_timer", 0.0)
	controller.call("_melee")
	await _frames(3)
	check(str(av.get("work_action")) == "swing" and av.get("_tool_node") != null, "clava: golpe lateral com a clava na mão")
	await _frames(50)
	check(str(av.get("work_action")) == "hold", "o golpe termina sozinho e volta a segurar")
	player.call("select_melee", "club")
	await _frames(2)
	check(str(av.get("work_action")).is_empty(), "apertar o slot de novo guarda a clava")
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
	check(not controller.infection_clock.visible, "remédio de ervas tira o relógio")
	# Mapa (M).
	var m_key := InputEventKey.new()
	m_key.physical_keycode = KEY_M
	m_key.pressed = true
	controller.call("_unhandled_input", m_key)
	await _frames(2)
	check(controller.world_map.visible, "M abre o mapa")
	controller.call("_unhandled_input", m_key)
	check(not controller.world_map.visible, "M fecha o mapa")
	await _building(controller, player)
	await _animals(controller, player)
	print("FALHAS: %d" % failures)
	Net.in_match = false
	get_tree().quit(1 if failures else 0)
