extends Node3D
const PointerMode = preload("res://scripts/pointer_mode.gd")
## Partida de Sobrevivência (mundo aberto, até 16 jogadores, zumbis).
## O servidor (src/godot-survival.js) é dono de vida, fome, sede, mochila,
## recipientes e recursos; este nó mostra o mundo, manda as ações e, no
## jogador anfitrião, move os zumbis.
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const CombatFeedbackScript = preload("res://scripts/net/combat_feedback.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const ZombieScript = preload("res://scripts/survival/zombie.gd")
const Melee = preload("res://scripts/melee.gd")
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")
const ManualUI = preload("res://scripts/survival/survival_manual.gd")
const DrivingScript = preload("res://scripts/survival/survival_driving.gd")
const BuildingScript = preload("res://scripts/survival/survival_building.gd")
const AnimalScript = preload("res://scripts/survival/animal.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const HandTorch = preload("res://scripts/survival/hand_torch.gd")
var death_title: Label
var torch_in_hand := false # tocha acesa na mão (os outros veem pelo "tc" do estado)
var animals: Dictionary = {} # id -> Animal
var driving_ctl: Node # carros (survival_driving.gd)
var building_ctl: Node # construção (survival_building.gd)
var bed_button: Button
const STATE_RATE := 1.0 / 10.0
const ZOMBIE_RATE := 1.0 / 6.0
const REACH := 2.8 # interação (o servidor aceita um pouco mais)
const SEARCH_TIME := 1.0
const MELEE_COOLDOWN := 0.6
const SWING_TIME := 0.55 # golpe de arma branca (igual ao ciclo "swing" do avatar)
const INFECTION_TIME := 120.0
const MapScript = preload("res://scripts/ui/world_map.gd")
var _swing_left := 0.0
var infected_left := 0.0 # segundos até virar zumbi (0 = saudável)
var infection_clock: Control
var world_map: Control

var main_node: Node
var player: CharacterBody3D
var world: Node3D # SurvivalWorld
var my_id := ""
var actors: Dictionary = {} # id -> NetActor (outros jogadores)
var names: Dictionary = {}
var zombies: Dictionary = {} # id -> Zombie
var bags: Dictionary = {} # id -> {node, pos, name, count}
var sleepers: Dictionary = {} # id -> NetActor deitado (jogador que saiu do jogo)
var inv: Dictionary = {}
var carried := 0.0 # kg (servidor)
var carry_cap := float(SurvivalData.catalog().get("carry_base", 20.0))
var _crafting_timer := 0.0
var my_hp := 100.0
var hunger := 100.0
var thirst := 100.0
var local_dead := false
var finished := false # compatibilidade com main.gd
var night := false
var online := 1
var zombie_count := 0
var _day_ms := 1440000.0
var _clock_ms := 0.0
var _state_timer := 0.0
var _zombie_timer := 0.0
var _melee_timer := 0.0
var _respawn_left := 0.0
var _ammo_known: Dictionary = {} # tipo de munição -> quantidade que o jogo já repassou às armas
var _open_container := ""
var _open_container_pos := Vector3.INF
var _target: Dictionary = {} # o que está ao alcance do E

var ui: CanvasLayer
var inventory: Control
var manual: Control # Manual de sobrevivência (L)
var bars: Dictionary = {}
var clock_label: Label
var prompt: Label
var feed: VBoxContainer
var toast_label: Label
var damage_flash: ColorRect
var death_panel: PanelContainer
var death_label: Label
var respawn_button: Button
var combat_feedback: Control
var sun: DirectionalLight3D
var env: Environment

func setup(main: Node, local_player: CharacterBody3D, survival_world: Node3D) -> void:
	main_node = main
	player = local_player
	world = survival_world

func _ready() -> void:
	name = "SurvivalController"
	my_id = Net.my_id
	sun = main_node.get_node_or_null("Sun")
	if sun:
		# Mundo aberto cheio de árvores: sombra mais curta e em 2 faixas (cada faixa redesenha tudo).
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 60.0
	# Modelos com níveis de detalhe (zumbis): troca para o mais leve um pouco antes.
	get_viewport().mesh_lod_threshold = 3.0
	var we := main_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	env = we.environment if we else null
	_build_ui()
	var info: Dictionary = Net.start_info
	player.call("start_unarmed")
	player.set("interact_handler", _interact)
	player.set("heal_handler", _quick_heal)
	player.set("melee_handler", _melee)
	player.set("grenade_check", func(): return false)
	var you: Dictionary = info.get("you", {})
	var p = _vec(you.get("p"))
	if p != null:
		player.global_position = p + Vector3(0, 0.1, 0)
	# Volta olhando para o mesmo lado de quando saiu.
	player.set("yaw", float(you.get("y", player.get("yaw"))))
	my_hp = float(you.get("hp", 100))
	hunger = float(you.get("hunger", 100))
	thirst = float(you.get("thirst", 100))
	_apply_inventory(you)
	for entry in info.get("roster", []):
		_add_actor(entry)
	_spawn_zombies(info.get("zombies", []))
	_spawn_animals(info.get("animals", []))
	driving_ctl = DrivingScript.new()
	driving_ctl.call("setup", self, main_node, player)
	add_child(driving_ctl)
	driving_ctl.call("spawn_all", info.get("vehicles", []))
	building_ctl = BuildingScript.new()
	building_ctl.call("setup", self, main_node, player)
	add_child(building_ctl)
	building_ctl.call("start", info)
	_update_crafting_context()
	for bag in info.get("bags", []):
		_set_bag(bag)
	for branch in info.get("branches", []):
		world.call("add_branch", branch)
	for fruit in info.get("fruits", []):
		world.call("add_fruit", fruit)
	for entry in info.get("sleepers", []):
		_add_sleeper(entry)
	for k in info.get("searched", []):
		world.call("set_container_empty", str(k), true)
	var depleted: Dictionary = info.get("depleted", {})
	for rid in depleted:
		_deplete(str(rid), float(depleted[rid]))
	_apply_clock(info.get("clock", {}))
	player.connect("shot_fired", _on_local_shot)
	Net.message.connect(_on_message)
	Net.connection_lost.connect(_on_connection_lost)
	_apply_host()
	Net.attach_consumer()
	_set_infected(float(you.get("infected", 0)))
	if bool(you.get("dead", false)):
		_on_local_death()
	_feed("Você acordou na floresta sem nada. Junte galhos, pedras e fibra e fabrique suas ferramentas.")
	_feed("E coletar/beber  •  TAB inventário  •  L manual  •  B construir  •  M mapa  •  CLIQUE golpe  •  F curativo")
	_feed("De dia a floresta é calma. À noite (20h–6h) os zumbis saem do mato. Nas 3 cidades abandonadas (pontas do mapa) há zumbis até de dia.")

func _exit_tree() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.connection_lost.is_connected(_on_connection_lost):
		Net.connection_lost.disconnect(_on_connection_lost)

func is_host() -> bool:
	return Net.host_id == my_id and not my_id.is_empty()

func _apply_host() -> void:
	for z in zombies.values():
		z.call("set_controlled", is_host())
	for a in animals.values():
		a.call("set_controlled", is_host())

## Jogadores vivos que os zumbis podem atacar (no anfitrião).
## "grass": dentro de grama alta; "crouch": agachado (os dois juntos = escondido).
func _targets() -> Array:
	var list: Array = []
	if not local_dead:
		list.append({"id": my_id, "node": player, "grass": world.call("in_tall_grass", player.global_position), "crouch": bool(player.get("crouching")) or bool(player.get("prone"))})
	for id in actors:
		var actor = actors[id]
		if not actor.dead:
			var state: Dictionary = actor.get("remote_state")
			list.append({"id": id, "node": actor, "grass": world.call("in_tall_grass", actor.global_position), "crouch": bool(state.get("c", false))})
	return list

# ------------------------------------------------------------------- rede ---

func _fauna_targets() -> Array:
	var list: Array = []
	for id in animals:
		var a = animals[id]
		if is_instance_valid(a) and not bool(a.get("dead")):
			list.append({"id": str(id), "node": a, "kind": str(a.get("kind"))})
	return list

func _fauna_food_sources(animal_kind: String, position: Vector3, water: bool) -> Array:
	var list: Array = []
	var data := SurvivalData.world()
	if water:
		var ponds: Array = data.get("ponds", [])
		for i in ponds.size():
			var pond: Dictionary = ponds[i]
			list.append({"id": "water:%d" % i, "pos": Vector3(float(pond.x), 0, float(pond.z)), "radius": float(pond.r)})
		return list
	var food := str(SurvivalData.catalog().get("animals", {}).get(animal_kind, {}).get("food", ""))
	if food == "grass":
		var patches: Array = data.get("grass", [])
		for i in patches.size():
			var patch: Dictionary = patches[i]
			list.append({"id": "grass:%d" % i, "pos": Vector3(float(patch.x), 0, float(patch.z)), "radius": float(patch.r)})
	else:
		var fruits: Dictionary = world.get("fallen_fruit")
		for id in fruits:
			var fruit: Dictionary = fruits[id]
			if str(fruit["kind"]) == food:
				list.append({"id": str(id), "pos": fruit["pos"], "radius": 0.0})
	return list

func _physics_process(delta: float) -> void:
	_melee_timer = maxf(0.0, _melee_timer - delta)
	_clock_ms += delta * 1000.0
	# O sol anda devagar: mexer na luz e no ambiente 4 vezes por segundo basta
	# (cada mudança no Environment é repassada ao servidor de renderização).
	_daylight_timer -= delta
	if _daylight_timer <= 0.0:
		_daylight_timer = 0.25
		_update_daylight()
	if local_dead:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		respawn_button.disabled = _respawn_left > 0.0
		respawn_button.text = "Renascer numa clareira" if _respawn_left <= 0.0 else "Renascer em %d s" % ceili(_respawn_left)
		if bed_button != null and bed_button.visible:
			var wait := maxf(_respawn_left, float(building_ctl.call("bed_wait")))
			bed_button.disabled = wait > 0.0
			bed_button.text = "Renascer na cama" if wait <= 0.0 else "Cama pronta em %d s" % ceili(wait)
		return
	_sync_ammo()
	_crafting_timer -= delta
	if _crafting_timer <= 0.0:
		_crafting_timer = 0.2
		_update_crafting_context()
	_swing_left = maxf(0.0, _swing_left - delta)
	# Saiu do lugar ou cancelou: para de golpear (o golpe do bastão dura SWING_TIME).
	if not action.is_empty() and float(player.get("channel_left")) <= 0.0 and _swing_left <= 0.0:
		_set_action("", "")
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_RATE
		var p := player.global_position
		var v := player.get_real_velocity() if not is_driving() else Vector3.ZERO
		Net.send({"t": "s", "p": [p.x, p.y, p.z], "y": player.call("network_yaw"), "pi": player.get("pitch"),
			"w": player.get("current_weapon"), "m": clampf(Vector2(v.x, v.z).length() / 5.0, 0.0, 1.0),
			"r": player.get("sprinting"), "c": player.get("crouching") or player.get("prone"), "pr": player.get("prone"), "a": player.get("aiming"),
			"f": not player.is_on_floor() and not is_driving(), "rl": player.get("reloading"), "h": player.get("weapon_holstered"), "v": [v.x, v.z],
			"act": ("bow_draw" if player.get("bow_controller").get("draw").drawing else "bow_carry") if player.call("has_bow") else action, "tool": "bow" if player.call("has_bow") else action_tool, "charge": player.get("bow_controller").get("draw").charge if player.call("has_bow") else 0.0, "ch": player.get("character_id"), "tc": torch_in_hand})
	_zombie_timer -= delta
	if _zombie_timer <= 0.0 and is_host():
		_zombie_timer = ZOMBIE_RATE
		var list: Array = []
		for z in zombies.values():
			if not z.dead and z.controlled:
				list.append(z.call("state"))
		if not list.is_empty():
			Net.send({"t": "z", "l": list})
		var herd: Array = []
		for a in animals.values():
			if not a.dead and a.controlled:
				herd.append(a.call("state"))
		if not herd.is_empty():
			Net.send({"t": "an", "l": herd})

func is_driving() -> bool:
	return driving_ctl != null and bool(driving_ctl.call("is_driving"))

## Modo de construção ligado (os controles de toque mostram os botões de construir).
func is_building() -> bool:
	return building_ctl != null and bool(building_ctl.get("building"))

## Controles de toque: arrastar o dedo dirigindo gira a câmera do carro.
func drive_look(relative: Vector2) -> void:
	if is_driving():
		driving_ctl.call("orbit_camera", relative.x)

func _on_message(data: Dictionary) -> void:
	if driving_ctl != null and bool(driving_ctl.call("on_message", data)):
		return
	if building_ctl != null and bool(building_ctl.call("on_message", data)):
		return
	match str(data.get("t", "")):
		"s":
			var actor = actors.get(str(data.get("id", "")))
			if actor != null:
				actor.call("apply_state", data)
				# Dirigindo: o corpo some (está dentro do carro).
				actor.visible = str(data.get("dv", "")).is_empty()
				actor.call("set_action", str(data.get("act", "")), str(data.get("tool", "")))
				_dress(actor.get("visual"), str(data.get("bp", "")))
		"join":
			_add_actor(data)
		"leave":
			var who := str(data.get("id", ""))
			if actors.has(who):
				_feed("%s saiu do mundo." % names.get(who, "?"))
				actors[who].queue_free()
				actors.erase(who)
		"host":
			_apply_host()
			if is_host():
				_feed("Você agora controla os zumbis deste mundo.")
		"z":
			for entry in data.get("l", []):
				var z = zombies.get(str(entry[0]))
				if z != null:
					z.call("apply_state", entry)
		"zspawn":
			_spawn_zombies(data.get("l", []))
		"zhp":
			var z = zombies.get(str(data.get("id", "")))
			if z != null:
				var new_hp := float(data.get("hp", 0))
				if new_hp < float(z.hp):
					z.call("pain_sound") # quem não atirou também ouve o zumbi gritar
					# Anfitrião: golpe de perto (soco, arma branca) faz o zumbi recuar e perder o bote.
					var by_node: Node3D = player if str(data.get("by", "")) == my_id else actors.get(str(data.get("by", "")))
					if bool(z.controlled) and by_node != null \
							and Vector2(by_node.global_position.x - z.global_position.x, by_node.global_position.z - z.global_position.z).length() < float(z.MELEE_STAGGER_RANGE):
						z.call("stagger", by_node.global_position)
				z.hp = new_hp
		"zdead":
			var z = zombies.get(str(data.get("id", "")))
			if z != null:
				z.call("die")
				zombies.erase(str(data["id"]))
			if str(data.get("by", "")) == my_id:
				combat_feedback.call("show_hit", str(data.get("zone", "")) == "head", true)
				player.get("sound_fx").call("kill_confirm")
		"an":
			for entry in data.get("l", []):
				var a = animals.get(str(entry[0]))
				if a != null:
					a.call("apply_state", entry)
		"aspawn":
			_spawn_animals(data.get("l", []))
		"afed":
			var a = animals.get(str(data.get("id", "")))
			if a != null:
				a.call("feed", float(data.get("left", 0.0)))
		"aneeds":
			for entry in data.get("l", []):
				var a = animals.get(str(entry.get("id", "")))
				if a != null:
					a.call("apply_needs", float(entry.get("hunger", 70)), float(entry.get("thirst", 75)))
					a.hp = float(entry.get("hp", a.hp))
		"fruit":
			world.call("add_fruit", data.get("r", {}), true)
		"fruit_gone":
			world.call("remove_fruit", str(data.get("id", "")))
		"ahp":
			var a = animals.get(str(data.get("id", "")))
			if a != null:
				var by := str(data.get("by", ""))
				var by_node: Node3D = player if by == my_id else actors.get(by, animals.get(by))
				if by_node != null:
					a.call("hurt", by, by_node)
				a.hp = float(data.get("hp", a.hp))
		"adead":
			var a = animals.get(str(data.get("id", "")))
			if a != null:
				a.call("die")
				animals.erase(str(data["id"]))
			if str(data.get("by", "")) == my_id:
				combat_feedback.call("show_hit", false, true)
				player.get("sound_fx").call("kill_confirm")
		"agone":
			for id in data.get("l", []):
				var a = animals.get(str(id))
				if a != null:
					a.queue_free()
					animals.erase(str(id))
		"zgone":
			for id in data.get("l", []):
				var z = zombies.get(str(id))
				if z != null:
					z.queue_free()
					zombies.erase(str(id))
		"shot":
			var o = _vec(data.get("o"))
			var e = _vec(data.get("e"))
			if o != null and e != null:
				if str(data.get("w", "")) != "bow":
					_tracer(o, e)
				_noise(o)
				var shooter = actors.get(str(data.get("id", "")))
				if shooter != null:
					if str(data.get("w", "")) == "bow":
						shooter.call("play_remote_arrow", o, e - o, str(data.get("a", "")))
					else:
						shooter.call("play_remote_shot", str(data.get("w", "pistol")))
		"hp":
			_on_health(data)
		"inv":
			_apply_inventory(data)
		"stats":
			my_hp = float(data.get("hp", my_hp))
			hunger = float(data.get("hunger", hunger))
			thirst = float(data.get("thirst", thirst))
			_update_bars()
		"container":
			_open_container = str(data.get("k", ""))
			var spot: Dictionary = world.containers.get(_open_container, {})
			_open_container_pos = spot.get("pos", bags.get(_open_container, {}).get("pos", player.global_position))
			var chest: Dictionary = building_ctl.get("rules").pieces.get(_open_container, {})
			if not chest.is_empty():
				_open_container_pos = building_ctl.get("rules").center(chest)
			var items: Dictionary = data.get("items", {})
			var title := str(data.get("title", "Recipiente"))
			if bool(data.get("store", false)):
				title += "  (%.0f / %.0f kg)" % [float(data.get("weight", 0)), float(data.get("cap", 0))]
			inventory.call("show_container", _open_container, title, items, bool(data.get("store", false)))
			if not inventory.visible:
				inventory.call("open")
			if world.containers.has(_open_container):
				world.call("set_container_empty", _open_container, items.is_empty())
		"emptied":
			world.call("set_container_empty", str(data.get("k", "")), true)
		"refilled":
			world.call("set_container_empty", str(data.get("k", "")), false)
		"bag":
			_set_bag(data.get("bag", {}))
		"bag_gone":
			var id := str(data.get("id", ""))
			if bags.has(id):
				bags[id]["node"].queue_free()
				bags.erase(id)
			if id == _open_container:
				inventory.call("clear_container")
				_open_container = ""
		"depleted":
			_deplete(str(data.get("r", "")), float(data.get("secs", 600)))
		"branch":
			world.call("add_branch", data.get("r", {}), true)
		"branch_gone":
			world.call("remove_branch", str(data.get("id", "")))
		"note":
			_toast(str(data.get("message", "")))
		"xp":
			_feed("+%d XP" % int(data.get("amount", 0)))
		"clock":
			_apply_clock(data)
			online = int(data.get("online", online))
			zombie_count = int(data.get("zombies", zombie_count))
		"respawned":
			_on_respawned(data)
		"infected":
			_set_infected(float(data.get("left", 0)))
		"sleep":
			_add_sleeper(data)
			_feed("%s está dormindo." % str(data.get("name", "?")))
		"wake":
			var sid := str(data.get("id", ""))
			if sleepers.has(sid):
				sleepers[sid].queue_free()
				sleepers.erase(sid)

func _on_connection_lost(reason: String) -> void:
	finished = true
	_show_death("Conexão perdida", reason + "\nSeu personagem fica guardado neste mundo.", false)

# ----------------------------------------------------------- personagens ---

func _add_actor(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if id.is_empty() or id == my_id:
		return
	if actors.has(id):
		actors[id].queue_free()
		actors.erase(id)
	names[id] = str(entry.get("name", "?"))
	if bool(entry.get("dead", false)):
		return
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", id, names[id], false)
	actor.set("tag_subtitle", str(entry.get("rank", "")))
	var p = _vec(entry.get("p"))
	actor.position = (p if p != null else Vector3.ZERO) + Vector3(0, 0.1, 0)
	actor.connect("damaged", _on_target_damaged)
	main_node.add_child(actor)
	actors[id] = actor

## Jogador que saiu do jogo: o corpo fica deitado, dormindo, onde ele estava.
func _add_sleeper(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	var p = _vec(entry.get("p"))
	if id.is_empty() or p == null:
		return
	if sleepers.has(id):
		sleepers[id].queue_free()
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", id, str(entry.get("name", "?")), false)
	actor.set("tag_subtitle", str(entry.get("rank", "")))
	actor.position = p
	main_node.add_child(actor)
	actor.call("sleep", float(entry.get("y", 0.0)))
	_dress(actor.get("visual"), str(entry.get("bp", "")))
	sleepers[id] = actor

func _spawn_zombies(list: Array) -> void:
	for entry in list:
		var id := str(entry.get("id", ""))
		if id.is_empty() or zombies.has(id):
			continue
		var z: CharacterBody3D = ZombieScript.new()
		z.call("setup", id, str(entry.get("kind", "walker")), float(entry.get("hp", 60)))
		var p = _vec(entry.get("p"))
		z.position = p if p != null else Vector3.ZERO
		z.set("targets", _targets)
		z.set("night", night)
		z.connect("damaged", _on_target_damaged)
		z.connect("attacked", _on_zombie_attack)
		z.connect("attacked_build", _on_zombie_build_attack)
		main_node.add_child(z)
		z.call("set_controlled", is_host())
		zombies[id] = z

func _spawn_animals(list: Array) -> void:
	for entry in list:
		var id := str(entry.get("id", ""))
		if id.is_empty() or animals.has(id):
			continue
		var a: CharacterBody3D = AnimalScript.new()
		a.call("setup", id, str(entry.get("kind", "deer")), float(entry.get("hp", 50)))
		var p = _vec(entry.get("p"))
		a.position = p if p != null else Vector3.ZERO
		a.set("targets", _targets)
		a.call("set_fauna_targets", _fauna_targets)
		a.call("set_food_sources", _fauna_food_sources)
		a.set("night", night)
		a.connect("damaged", _on_target_damaged)
		a.connect("attacked", func(aid: String, target_id: String):
			if is_host():
				Net.send({"t": "ahit", "a": aid, "target": target_id}))
		a.connect("forage_requested", func(aid: String, source_id: String, phase: String):
			if is_host():
				Net.send({"t": "aforage", "a": aid, "source": source_id, "phase": phase}))
		main_node.add_child(a)
		a.call("set_controlled", is_host())
		a.call("feed", float(entry.get("fed", 0.0)))
		a.call("apply_needs", float(entry.get("hunger", 70)), float(entry.get("thirst", 75)))
		animals[id] = a

func _on_zombie_attack(zombie_id: String, target_id: String) -> void:
	if is_host():
		Net.send({"t": "zhit", "z": zombie_id, "target": target_id})

## Zumbi batendo numa parede/porta no caminho (anfitrião): o servidor tira a vida da peça.
func _on_zombie_build_attack(zombie_id: String, build_id: String) -> void:
	if is_host():
		Net.send({"t": "zbhit", "z": zombie_id, "b": build_id})

## Tiro (meu ou de outro): zumbis por perto vão atrás do barulho.
func _noise(at: Vector3) -> void:
	if not is_host():
		return
	for z in zombies.values():
		z.call("hear", at)

func _on_local_shot(weapon_id: String, from: Vector3, to: Vector3) -> void:
	# A recarga pode terminar no mesmo quadro do tiro: registre o carregador antes.
	if weapon_id != "bow":
		_sync_ammo()
	var packet := {"t": "shot", "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]}
	if weapon_id == "bow":
		var v := to - from
		packet["v"] = [v.x, v.y, v.z]
		packet["a"] = player.get("bow_controller").get("last_arrow_id")
	Net.send(packet)
	_noise(from)

## Acerto de bala num zumbi ou jogador (hitbox): o servidor calcula o dano.
func _on_target_damaged(target_id: String, zone: String, point: Vector3, normal: Vector3, weapon: String) -> void:
	if local_dead:
		return
	if weapon.is_empty():
		weapon = str(player.get("current_weapon"))
	# pt = onde a bala bateu (o servidor confere se a cabeça estava ali).
	var packet := {"t": "hit", "target": target_id, "zone": zone, "w": weapon, "pt": [point.x, point.y, point.z]}
	if weapon == "bow":
		packet["a"] = player.get("bow_controller").get("last_hit_arrow_id")
	Net.send(packet)
	var headshot := zone == "head"
	combat_feedback.call("show_hit", headshot)
	player.get("sound_fx").call("hit_confirm", headshot)
	_blood(point, normal)

## Q: soco ou a melhor arma branca da mochila, em quem estiver na frente.
func _melee() -> void:
	if local_dead or _melee_timer > 0.0:
		return
	_melee_timer = MELEE_COOLDOWN
	var best_weapon: Array = SurvivalData.best_melee(inv)
	var reach := float(SurvivalData.item(str(best_weapon[0])).get("reach", 2.4))
	# Arma branca na mão: golpe de lado com as duas mãos (todos veem o movimento).
	if not str(best_weapon[0]).is_empty():
		_set_action("swing", str(best_weapon[0]))
		_swing_left = SWING_TIME
	player.get("sound_fx").call("melee_swing")
	# Sem mira: o alcance da arma a partir do corpo, para a frente do personagem.
	var hit := Melee.sweep(player, reach)
	if hit.is_empty():
		return
	var from: Vector3 = hit["from"]
	var forward: Vector3 = hit["dir"]
	var body: Object = hit["collider"]
	# Construção (parede, porta, baú...): o servidor tira a vida da peça.
	var build_id := BuildingScript.build_id_of(body)
	if not build_id.is_empty():
		Net.send({"t": "bhit", "b": build_id, "item": SurvivalData.best_melee(inv)[0]})
		player.get("sound_fx").call("melee_impact", false)
		return
	var target = body.get("actor") if body != null else null
	if target == null:
		return
	var target_id := str(target.get("zombie_id")) if target.get("zombie_id") != null else str(target.get("actor_id"))
	if target.get("animal_id") != null:
		target_id = str(target.get("animal_id"))
	var best: Array = SurvivalData.best_melee(inv)
	var zone := str(body.get("zone"))
	if body.has_method("resolve_ray"):
		# Casca do zumbi: a parte do corpo sai da conta (de perto, sem acerto exato = tronco).
		zone = str((body.call("resolve_ray", from, forward) as Dictionary).get("zone", "chest"))
	Net.send({"t": "melee", "target": target_id, "item": best[0], "zone": zone})
	combat_feedback.call("show_hit", zone == "head")
	player.get("sound_fx").call("melee_impact", zone == "head")
	_blood(hit["position"], hit["normal"])

func _on_health(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var hp := float(data.get("hp", 0))
	var killed := bool(data.get("killed", false))
	var by := str(data.get("by", ""))
	# Mordida: o zumbi que acertou faz o golpe (nos outros clientes, já no impacto).
	if str(data.get("w", "")) == "zombie" and zombies.has(by):
		zombies[by].call("strike", true)
	if str(data.get("w", "")).begins_with("a_") and animals.has(by) and not bool(animals[by].controlled):
		animals[by].call("strike")
	if id == my_id:
		if hp < my_hp:
			damage_flash.color.a = clampf(0.2 + (my_hp - hp) / 50.0, 0.2, 0.55)
			player.call("add_hit_shake", clampf((my_hp - hp) / 20.0, 0.25, 1.0))
			if str(data.get("w", "")) == "zombie":
				player.get("sound_fx").call("zombie_bite", my_hp - hp)
			else:
				player.get("sound_fx").call("hurt", my_hp - hp)
		my_hp = hp
		_update_bars()
		if killed:
			var cause: String = str({"fome": "de fome", "sede": "de sede", "zombie": "para os zumbis", "infection": "— a infecção venceu e você virou zumbi", "explosion": "na explosão do carro",
				"a_wolf": "para os lobos", "a_boar": "na chifrada do javali", "raw": "de tanto comer carne crua"}.get(str(data.get("w", "")), ""))
			if cause.is_empty():
				cause = "para " + str(names.get(by, "alguém"))
			_feed("Você morreu %s." % cause)
			_on_local_death()
	elif actors.has(id):
		actors[id].call("set_hp", hp, killed)
		if killed:
			_feed(("%s virou zumbi." if str(data.get("w", "")) == "infection" else "%s morreu.") % names.get(id, "?"))
	if killed and by == my_id and id != my_id:
		player.get("sound_fx").call("kill_confirm")
		_toast("ELIMINOU %s" % str(names.get(id, "")).to_upper())

func _on_local_death() -> void:
	if driving_ctl != null:
		driving_ctl.call("force_exit")
	_set_action("", "")
	_set_infected(0.0)
	local_dead = true
	set_torch(false)
	_respawn_left = 8.0
	inventory.call("close")
	if manual != null and manual.visible:
		manual.call("close")
	if building_ctl != null:
		building_ctl.call("set_building", false)
		if bool(building_ctl.call("ui_open")):
			building_ctl.call("close_auth")
	if bed_button != null:
		bed_button.visible = building_ctl != null and bool(building_ctl.call("has_bed"))
	player.set_physics_process(false)
	player.visible = false
	_show_death("VOCÊ MORREU", "Suas coisas ficaram numa mochila onde você caiu.\nVocê renasce de mãos vazias, numa clareira ou na sua cama.", true)
	PointerMode.release()

func _on_respawned(data: Dictionary) -> void:
	local_dead = false
	death_panel.visible = false
	var p = _vec(data.get("p"))
	if p != null:
		player.global_position = p + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	player.visible = true
	player.set_physics_process(true)
	player.call("start_unarmed")
	_ammo_known.clear()
	inv = {}
	my_hp = float(data.get("hp", 100))
	hunger = float(data.get("hunger", 85))
	thirst = float(data.get("thirst", 85))
	_apply_inventory(data)
	PointerMode.capture()

# --------------------------------------------------------------- mochila ---

## Mostra no personagem a mochila que o servidor mandou (capacete e colete não aparecem).
static func _dress(visual, back: String) -> void:
	if visual != null and visual.has_method("set_backpack"):
		visual.call("set_backpack", back)

## O servidor mandou a mochila: armas aparecem/somem e a munição vira reserva.
func _apply_inventory(data: Dictionary) -> void:
	var new_inv: Dictionary = data.get("inv", {})
	var weight := float(data.get("weight", 0))
	var cap := float(data.get("cap", SurvivalData.catalog().get("carry_base", 20)))
	var back := str(data.get("back", ""))
	var head := str(data.get("head", ""))
	var chest := str(data.get("chest", ""))
	inv = new_inv
	carried = weight
	carry_cap = cap
	inventory.call("set_inventory", inv, weight, cap, back, head, chest)
	if manual != null:
		manual.call("set_inventory", inv, data.get("known", []))
	inventory.set("known", data.get("known", []))
	if torch_in_hand and int(inv.get("torch", 0)) <= 0:
		set_torch(false) # fincou, guardou ou largou a última tocha
	_dress(player.get("humanoid_avatar"), back)
	var owned: Dictionary = player.get("owned_weapons")
	for item in inv:
		var w := SurvivalData.weapon_of(str(item))
		if not w.is_empty() and not owned.has(w):
			player.call("give_weapon", w, 0)
			# Ao reconectar, restaura o carregador salvo; saque novo continua vazio.
			var mags: Dictionary = player.get("magazines")
			var saved_mags: Dictionary = data.get("magazines", {})
			mags[w] = 0 if w == "bow" else clampi(int(saved_mags.get(w, 0)), 0, int(WeaponData.stats(w)["mag"]))
			if player.get("current_weapon") == w:
				player.set("ammo", mags[w])
			_toast("Arco na mochila — equipe e segure o esquerdo" if w == "bow" else "%s na mochila — R para carregar" % SurvivalData.item_name(str(item)))
	for w in owned.keys():
		var present := false
		for item in inv:
			if int(inv[item]) > 0 and SurvivalData.weapon_of(str(item)) == str(w):
				present = true
				break
		if not present:
			player.call("remove_weapon", w)
	# Reserva de cada arma = munição do tipo dela na mochila.
	var reserve: Dictionary = player.get("reserve_ammo")
	for w in player.get("owned_weapons"):
		var ammo_item := SurvivalData.ammo_for(str(w))
		reserve[w] = int(inv.get(ammo_item, 0))
	_ammo_known.clear()
	for w in player.get("owned_weapons"):
		_ammo_known[SurvivalData.ammo_for(str(w))] = int(inv.get(SurvivalData.ammo_for(str(w)), 0))
	_update_bars()
	if building_ctl != null:
		building_ctl.call("inventory_changed")
	_update_crafting_context()

func _update_crafting_context() -> void:
	if building_ctl == null or player == null:
		return
	var rules = building_ctl.get("rules")
	var stations := SurvivalData.nearby_stations(rules.pieces.values(), player.global_position)
	inventory.call("set_crafting_context", stations, carried, carry_cap)
	if manual != null:
		manual.call("set_crafting_context", stations, carried, carry_cap)

## A recarga tirou balas da reserva: avisa o servidor e iguala as armas do mesmo calibre.
func _sync_ammo() -> void:
	var reserve: Dictionary = player.get("reserve_ammo")
	for w in player.get("owned_weapons"):
		var ammo_item := SurvivalData.ammo_for(str(w))
		var known := int(_ammo_known.get(ammo_item, 0))
		var now := int(reserve.get(w, 0))
		if now < known:
			var packet := {"t": "consume", "ammo": ammo_item, "n": known - now}
			if w != "bow":
				packet["w"] = w
			Net.send(packet)
			_ammo_known[ammo_item] = now
			for other in player.get("owned_weapons"):
				if SurvivalData.ammo_for(str(other)) == ammo_item:
					reserve[other] = now

func _on_take(container_id: String, item: String, _all: bool) -> void:
	Net.send({"t": "take", "k": container_id, "item": item})

func _on_take_all(container_id: String) -> void:
	for item in inventory.get("container_items").keys():
		Net.send({"t": "take", "k": container_id, "item": item})

func _on_drop(item: String, _all: bool) -> void:
	Net.send({"t": "drop", "item": item})

## Acende/apaga a tocha da mão (só com uma tocha na mochila).
func set_torch(on: bool) -> void:
	torch_in_hand = on and int(inv.get("torch", 0)) > 0 and not local_dead
	HandTorch.set_on(player, torch_in_hand)
	inventory.set("torch_lit", torch_in_hand)
	if inventory.visible:
		inventory.call("_refresh")

## Tocha: fecha o inventário e entra no modo de colocar (chão ou parede).
func _on_place(item: String) -> void:
	if int(inv.get(item, 0)) <= 0 or local_dead or is_driving():
		return
	inventory.call("close")
	building_ctl.call("pick_bench", item)

func _on_use(item: String) -> void:
	var entry := SurvivalData.item(item)
	if item == "torch":
		set_torch(not torch_in_hand)
		_toast("TOCHA ACESA NA MÃO" if torch_in_hand else "TOCHA APAGADA")
		return
	if item == "repair_kit":
		var car := str(driving_ctl.call("repairable_near", player.global_position))
		if car.is_empty():
			_toast("CHEGUE PERTO DE UM CARRO BATIDO OU QUEBRADO")
			return
		inventory.call("close")
		driving_ctl.call("request_repair", car)
		return
	if entry.get("use", {}).has("cure") and infected_left <= 0.0:
		_toast("VOCÊ NÃO ESTÁ INFECTADO")
		return
	if entry.has("use_time"):
		var seconds := float(entry["use_time"])
		if player.call("start_channel", SurvivalData.item_name(item).to_upper(), seconds, func(): Net.send({"t": "use", "item": item})):
			Net.send({"t": "use_start", "item": item})
			_timed_action("consume", seconds)
		return
	Net.send({"t": "use", "item": item})
	_timed_action("consume", 1.1)
	player.get("sound_fx").call("reload")

func _on_craft(recipe: String) -> void:
	Net.send({"t": "craft", "recipe": recipe})

## F: bandagem de fibra (fabrique no TAB com 3 fibras).
func _quick_heal() -> void:
	if local_dead:
		return
	if my_hp >= 100.0:
		_toast("VIDA CHEIA")
		return
	for item in ["bandage"]:
		if inv.has(item):
			_on_use(item)
			return
	_toast("SEM BANDAGEM — FABRIQUE COM 3 FIBRAS (TAB)")

# --------------------------------------------------------- interação (E) ---

## O que está ao alcance: recipiente, mochila no chão ou recurso.
func _find_target() -> Dictionary:
	var best := {}
	var best_d := REACH
	var me := player.global_position
	for id in world.containers:
		var entry: Dictionary = world.containers[id]
		var pos: Vector3 = entry["pos"]
		var d := Vector2(pos.x - me.x, pos.z - me.z).length()
		if d < best_d and absf(pos.y - me.y) < 2.0:
			best_d = d
			best = {"type": "container", "id": id, "label": "[E] Revistar " + SurvivalData.container_name(str(entry["type"])) + (" (vazio)" if entry["empty"] else "")}
	for id in bags:
		var pos: Vector3 = bags[id]["pos"]
		var d := Vector2(pos.x - me.x, pos.z - me.z).length()
		if d < best_d:
			best_d = d
			var bag_title := str(bags[id].get("title", ""))
			best = {"type": "container", "id": id, "label": ("[E] Abrir " + bag_title.to_lower()) if bag_title != "" else "[E] Abrir mochila" + (" de " + str(bags[id]["name"]) if str(bags[id]["name"]) != "" else "")}
	for id in world.resources:
		var entry: Dictionary = world.resources[id]
		if entry["depleted"]:
			continue
		var pos: Vector3 = entry["pos"]
		var kind := str(entry["kind"])
		var reach := 3.2 if kind == "car" else REACH
		# Lago: conta a distância até a margem.
		var d := maxf(0.0, Vector2(pos.x - me.x, pos.z - me.z).length() - float(entry.get("r", 0.0)))
		if d < minf(best_d + 0.6, reach):
			best_d = d
			var rule := SurvivalData.resource_rule(kind)
			var needs := str(rule.get("needs", ""))
			var tool := _tool_for(needs if not needs.is_empty() else str(rule.get("tool", "")))
			var missing := not needs.is_empty() and tool.is_empty()
			var label := ""
			if rule.has("drink"):
				label = "[E] Beber água do lago"
			else:
				var verb: String = str({"tree": "Cortar", "rock": "Quebrar", "ore": "Quebrar", "saltpeter": "Quebrar", "car": "Desmontar", "bush": "Colher", "fiber": "Arrancar", "herb": "Colher"}.get(kind, "Pegar"))
				var tool_note := ""
				if missing:
					tool_note = "  —  precisa de " + SurvivalData.item_name(_tool_item(needs)).to_lower()
				elif not tool.is_empty():
					tool_note = "  —  com " + SurvivalData.item_name(tool)
				elif rule.has("tool"):
					tool_note = "  —  com " + SurvivalData.item_name(_tool_item(str(rule["tool"]))).to_lower() + " rende mais"
				label = "[E] %s %s (%s)%s" % [verb, str(rule.get("name", "")), SurvivalData.item_name(str(rule.get("gives", ""))), tool_note]
			best = {"type": "resource", "id": id, "kind": kind, "pos": pos, "tool": tool, "missing": missing, "needs": needs, "time": float(rule.get("time", 2.5)), "label": label}
	# Porta, baú ou fogueira: valem mais que um recurso do chão.
	if building_ctl != null and (best.is_empty() or best["type"] == "resource"):
		var piece: Dictionary = building_ctl.call("interact_target", me)
		if not piece.is_empty():
			best = piece
	# Carro que funciona: só se não houver nada mais perto.
	if driving_ctl != null and (best.is_empty() or best["type"] == "resource"):
		var car: Dictionary = driving_ctl.call("target_near", me)
		if not car.is_empty():
			best = car
	return best

## Item que faz esse tipo de coleta ("wood" -> machado de pedra), para os avisos.
func _tool_item(kind: String) -> String:
	var items: Dictionary = SurvivalData.catalog().get("items", {})
	for id in items:
		if str(items[id].get("tool", "")) == kind:
			return str(id)
	return ""

## Melhor ferramenta da mochila para o recurso ("wood" = machado, "stone" = picareta, "cut" = faca).
func _tool_for(kind: String) -> String:
	if kind.is_empty():
		return ""
	var best := ""
	var best_dmg := -1
	for item in inv:
		var entry := SurvivalData.item(str(item))
		if str(entry.get("tool", "")) == kind and int(entry.get("melee", 0)) > best_dmg:
			best = str(item)
			best_dmg = int(entry.get("melee", 0))
	return best

func _interact() -> bool:
	if local_dead:
		return false
	_target = _find_target()
	if _target.is_empty():
		return false
	var id := str(_target["id"])
	if _target["type"] == "build":
		building_ctl.call("interact", id)
	elif _target["type"] == "vehicle":
		driving_ctl.call("request_enter", id)
	elif _target["type"] == "repair":
		driving_ctl.call("request_repair", id)
	elif _target["type"] == "container":
		if player.call("start_channel", "REVISTANDO", SEARCH_TIME, func(): Net.send({"t": "search", "k": id})):
			_timed_action("open", SEARCH_TIME)
	else:
		if bool(_target.get("missing", false)):
			_toast("PRECISA DE " + SurvivalData.item_name(_tool_item(str(_target["needs"]))).to_upper() + " (L › MANUAL)")
			return true
		var seconds := float(_target["time"])
		var kind := str(_target["kind"])
		var label: String = str({"tree": "CORTANDO", "rock": "QUEBRANDO", "ore": "QUEBRANDO", "saltpeter": "QUEBRANDO", "car": "DESMONTANDO", "bush": "COLHENDO", "herb": "COLHENDO", "fiber": "ARRANCANDO", "pond": "BEBENDO"}.get(kind, "PEGANDO"))
		var done := func():
			Net.send({"t": "gather", "r": id})
			_set_action("", "")
		if player.call("start_channel", label, seconds, done):
			Net.send({"t": "gather_start", "r": id})
			# Vira para o recurso e golpeia com a ferramenta (machado na árvore, pé de cabra na pedra/carro).
			var to: Vector3 = (_target["pos"] as Vector3) - player.global_position
			to.y = 0.0
			player.set("yaw", atan2(-to.x, -to.z))
			# Chega perto do tronco para o golpe acertar (árvore: ~1,1 m do centro).
			var wanted := {"tree": 1.15, "rock": 1.3, "ore": 1.3, "saltpeter": 1.3, "car": 1.9}.get(kind, 0.0) as float
			if wanted > 0.0 and to.length() > wanted + 0.15:
				var spot: Vector3 = (_target["pos"] as Vector3) - to.normalized() * wanted
				spot.y = player.global_position.y
				create_tween().tween_property(player, "global_position", spot, 0.25)
			if kind in ["tree", "rock", "ore", "saltpeter", "car"]:
				_set_action("chop" if kind == "tree" else "pry", str(_target["tool"]))
			else:
				_timed_action("harvest", seconds)
	return true

## Ação curta vista por todos (revistar, colher, consumir): termina sozinha,
## mesmo se o canal for cancelado no meio.
func _timed_action(act: String, seconds: float) -> void:
	_set_action(act, "")
	var avatar = player.get("humanoid_avatar")
	if act == "consume" and avatar != null and avatar.has_method("play_action_for"):
		avatar.call("play_action_for", act, seconds)
	get_tree().create_timer(seconds + 0.2).timeout.connect(func():
		if action == act:
			_set_action("", ""))

## Ação de trabalho do personagem (vista por todos): "chop"/"pry" com a ferramenta, "" para.
var action := ""
var action_tool := ""
func _set_action(act: String, tool: String) -> void:
	action = act
	action_tool = tool
	var avatar = player.get("humanoid_avatar")
	if avatar != null and avatar.has_method("set_action"):
		avatar.call("set_action", act, tool)

func _deplete(rid: String, seconds: float) -> void:
	world.call("set_depleted", rid, true)
	get_tree().create_timer(maxf(1.0, seconds)).timeout.connect(func():
		if is_instance_valid(world):
			world.call("set_depleted", rid, false))

func _set_bag(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var p = _vec(data.get("p"))
	if id.is_empty() or p == null:
		return
	if bags.has(id):
		bags[id]["count"] = int(data.get("count", 0))
		return
	var node := Node3D.new()
	node.position = p
	main_node.add_child(node)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.35, 0.4)
	mesh.mesh = box
	mesh.position.y = 0.18
	var mat := StandardMaterial3D.new()
	# Carcaça de animal: monte marrom-avermelhado no lugar da mochila verde.
	mat.albedo_color = Color("#5a2f26") if str(data.get("title", "")).begins_with("Carca") else Color("#4b5a32")
	mesh.material_override = mat
	node.add_child(mesh)
	node.add_child(preload("res://scripts/survival/collectible_glow.gd").make_marker(Vector3(0, 0.65, 0)))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = str(data.get("title", "")) if str(data.get("title", "")) != "" else "Mochila" + (" de " + str(data.get("name", "")) if str(data.get("name", "")) != "" else "")
	label.font_size = 32
	label.outline_size = 8
	label.pixel_size = 0.004
	label.position.y = 0.8
	label.modulate = Color("#ff9a7a")
	node.add_child(label)
	bags[id] = {"node": node, "pos": p, "name": str(data.get("name", "")), "title": str(data.get("title", "")), "count": int(data.get("count", 0))}

# ------------------------------------------------------------- dia/noite ---

func _apply_clock(data: Dictionary) -> void:
	if data.is_empty():
		return
	_day_ms = float(data.get("day_ms", _day_ms))
	_clock_ms = float(data.get("time", _clock_ms))

## Hora do jogo: o dia começa às 6h. Noite das 20h às 6h.
func game_hour() -> float:
	return fmod(6.0 + fposmod(_clock_ms, _day_ms) / _day_ms * 24.0, 24.0)

func _update_daylight() -> void:
	var hour := game_hour()
	var was_night := night
	night = hour >= 20.0 or hour < 6.0
	if night != was_night:
		for z in zombies.values():
			z.set("night", night)
		for a in animals.values():
			a.set("night", night)
		_feed("A noite caiu. Os zumbis estão saindo do mato." if night else "Amanheceu. Os zumbis voltam para as sombras.")
	# Luz do sol: sobe às 6h, a pino ao meio-dia, se põe às 20h.
	var day_fraction := clampf((hour - 6.0) / 14.0, 0.0, 1.0)
	var light := sin(day_fraction * PI)
	if sun:
		sun.rotation_degrees.x = -lerpf(8.0, 172.0, day_fraction)
		sun.light_energy = 0.08 if night else 0.25 + light * 0.75
		sun.light_color = Color("#ffd2a0").lerp(Color("#fff1dc"), light)
	if env:
		env.ambient_light_energy = 0.07 if night else 0.12 + light * 0.2
		env.fog_density = 0.012 if night else 0.004
		env.fog_light_color = Color("#141b22") if night else Color("#879d9e")
		env.background_energy_multiplier = 0.15 if night else 0.4 + light * 0.6

# --------------------------------------------------------------------- HUD ---

var _scan_timer := 0.0
var _daylight_timer := 0.0

## Alguma janela da sobrevivência precisa do cursor (mochila aberta ou tela de morte).
func ui_open() -> bool:
	return (inventory != null and inventory.visible) or (manual != null and manual.visible) or (death_panel != null and death_panel.visible) \
		or (building_ctl != null and bool(building_ctl.call("ui_open")))

## Infecção (mordida de zumbi): `left` segundos até virar zumbi; 0 = curado.
func _set_infected(left: float) -> void:
	var was := infected_left > 0.0
	infected_left = maxf(0.0, left)
	if infection_clock != null:
		infection_clock.visible = infected_left > 0.0
		infection_clock.queue_redraw()
	if infected_left > 0.0 and not was:
		_feed("Você foi mordido e está infectado! Tome um remédio de ervas em até 2 minutos (3 ervas + 1 fibra).")
		_toast("INFECTADO — FAÇA UM REMÉDIO DE ERVAS")
	elif infected_left <= 0.0 and was and not local_dead:
		_feed("O remédio fez efeito: infecção curada.")
		_toast("INFECÇÃO CURADA")

## Relógio da infecção (topo da tela): disco que esvazia em 2 minutos + tempo restante.
func _draw_infection_clock() -> void:
	if infected_left <= 0.0:
		return
	var c := Vector2(infection_clock.size.x * 0.5, 62.0)
	var radius := 34.0
	var fraction := clampf(infected_left / INFECTION_TIME, 0.0, 1.0)
	var pulse := 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / (180.0 if infected_left < 30.0 else 420.0)))
	infection_clock.draw_circle(c, radius + 4.0, Color(0, 0, 0, 0.6))
	var points := PackedVector2Array([c])
	var steps := maxi(2, int(64 * fraction))
	for i in steps + 1:
		var angle := -PI * 0.5 + TAU * fraction * float(i) / steps
		points.append(c + Vector2(cos(angle), sin(angle)) * radius)
	if fraction > 0.0:
		infection_clock.draw_colored_polygon(points, Color(0.55, 0.85, 0.25, 0.85 * pulse).lerp(Color(0.9, 0.15, 0.1, 0.9 * pulse), 1.0 - fraction))
	infection_clock.draw_arc(c, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 2.0, true)
	# Ponteiro do relógio no tempo que falta.
	var hand := -PI * 0.5 + TAU * fraction
	infection_clock.draw_line(c, c + Vector2(cos(hand), sin(hand)) * radius * 0.85, Color(1, 1, 1), 2.5, true)
	var font := ThemeDB.fallback_font
	var secs := ceili(infected_left)
	var title := "INFECTADO  %d:%02d" % [secs / 60, secs % 60]
	var hint := "Tome um remédio de ervas (TAB) ou vira zumbi"
	for spec in [[title, 20, c.y + radius + 26.0, Color("#ff7a5c")], [hint, 14, c.y + radius + 46.0, Color(1, 1, 1, 0.9)]]:
		var w := font.get_string_size(spec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, spec[1]).x
		var at := Vector2(c.x - w * 0.5, spec[2])
		infection_clock.draw_string(font, at + Vector2(1, 1), spec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, spec[1], Color(0, 0, 0, 0.9))
		infection_clock.draw_string(font, at, spec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, spec[1], spec[3])

func _process(delta: float) -> void:
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 0.8)
	if infected_left > 0.0 and not local_dead:
		infected_left = maxf(0.0, infected_left - delta) # o servidor decide a hora exata
		infection_clock.queue_redraw()
	# Mochila aberta: o ponteiro tem que estar sempre visível para escolher os itens.
	if ui_open() and PointerMode.is_captured():
		PointerMode.release()
	# Procurar o que está perto percorre ~1500 coisas: 10 vezes por segundo basta.
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 0.1
	if not local_dead and not is_driving():
		var target := _find_target()
		prompt.visible = not target.is_empty() and not inventory.visible and not is_building()
		if prompt.visible:
			prompt.text = str(target["label"])
	else:
		prompt.visible = false
	# Fecha o recipiente ao se afastar.
	if not _open_container.is_empty() and _open_container_pos != Vector3.INF and player.global_position.distance_to(_open_container_pos) > 4.5:
		_open_container = ""
		inventory.call("clear_container")
	for id in world.containers:
		var entry: Dictionary = world.containers[id]
		entry["label"].visible = (entry["pos"] as Vector3).distance_squared_to(player.global_position) < 36.0
	var hour := game_hour()
	var day := int(floor(_clock_ms / _day_ms)) + 1
	clock_label.text = "Dia %d  •  %02d:%02d\n%d/16 online" % [day, int(hour), int(fmod(hour, 1.0) * 60.0), online]

func _unhandled_input(event: InputEvent) -> void:
	if driving_ctl != null and bool(driving_ctl.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if building_ctl != null and not local_dead and not is_driving() and not inventory.visible and not manual.visible and bool(building_ctl.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if _pressed(event, "refuel") and not local_dead:
		if bool(driving_ctl.call("request_refuel")):
			get_viewport().set_input_as_handled()
		return
	if _pressed(event, "map"):
		world_map.call("toggle")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and world_map.visible:
		world_map.call("toggle")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and inventory.visible:
		inventory.call("close")
		PointerMode.release() # ESC também libera o mouse (botão de menu)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE and manual.visible:
		manual.call("close")
		PointerMode.release()
		get_viewport().set_input_as_handled()
		return
	if _pressed(event, "manual"):
		if local_dead:
			return
		if inventory.visible:
			inventory.call("close")
		manual.call("toggle")
		get_viewport().set_input_as_handled()
		return
	if _pressed(event, "inventory"):
		if local_dead:
			return
		if manual.visible:
			manual.call("close")
		if inventory.visible:
			inventory.call("close")
		else:
			inventory.call("open")
		get_viewport().set_input_as_handled()

## Abre o manual (L) numa estação: chamado ao usar a bancada (E).
func open_manual(station: String = "") -> void:
	if local_dead or manual == null:
		return
	if inventory.visible:
		inventory.call("close")
	manual.call("open", station)

## Tecla/botão configurável (Configurações › Controles) apertado agora.
func _pressed(event: InputEvent, action: String) -> bool:
	return (event is InputEventKey or event is InputEventMouseButton or event is InputEventAction) and event.is_pressed() and not event.is_echo() and InputMap.has_action(action) and event.is_action(action)

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.6, 0, 0, 0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(damage_flash)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_feedback = CombatFeedbackScript.new()
	combat_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(combat_feedback)
	combat_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Barras: vida, fome, sede (canto inferior esquerdo).
	var box := VBoxContainer.new()
	box.position = Vector2(18, -150)
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.add_theme_constant_override("separation", 4)
	ui.add_child(box)
	for spec in [["hp", "VIDA", Color("#c8402f")], ["hunger", "FOME", Color("#d9a441")], ["thirst", "SEDE", Color("#4a9fd9")], ["weight", "PESO", Color("#8c8c7a")]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := UiTheme.caps(spec[1], 12, UiTheme.TEXT)
		label.custom_minimum_size.x = 52
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_y", 1)
		row.add_child(label)
		var bar := UiTheme.bar(ProgressBar.new(), spec[2], 12)
		bar.custom_minimum_size.x = 220
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		box.add_child(row)
		bars[spec[0]] = bar
	clock_label = Label.new()
	clock_label.anchor_left = 1.0
	clock_label.anchor_right = 1.0
	clock_label.offset_left = -330
	clock_label.offset_top = 64
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.offset_right = -20
	clock_label.add_theme_font_override("font", UiTheme.font(600))
	clock_label.add_theme_font_size_override("font_size", 16)
	clock_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ui.add_child(clock_label)
	prompt = Label.new()
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.62
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_font_override("font", UiTheme.font(600))
	prompt.add_theme_color_override("font_color", UiTheme.ACCENT)
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	ui.add_child(prompt)
	toast_label = Label.new()
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 0.3
	toast_label.offset_left = -360
	toast_label.offset_right = 360
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_override("font", UiTheme.font(700))
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast_label.modulate.a = 0.0
	ui.add_child(toast_label)
	feed = VBoxContainer.new()
	feed.position = Vector2(18, 212) # abaixo do minimapa
	feed.custom_minimum_size.x = 520
	ui.add_child(feed)
	infection_clock = Control.new()
	infection_clock.name = "InfectionClock"
	infection_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	infection_clock.visible = false
	ui.add_child(infection_clock)
	infection_clock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	infection_clock.draw.connect(_draw_infection_clock)
	world_map = MapScript.new()
	world_map.call("setup", player, self)
	ui.add_child(world_map)
	inventory = InventoryUI.new()
	ui.add_child(inventory)
	inventory.connect("take_requested", _on_take)
	inventory.connect("take_all_requested", _on_take_all)
	inventory.connect("drop_requested", _on_drop)
	inventory.connect("use_requested", _on_use)
	inventory.connect("craft_requested", _on_craft)
	inventory.connect("equip_requested", func(item): Net.send({"t": "equip", "item": item}))
	inventory.connect("unequip_requested", func(slot): Net.send({"t": "unequip", "slot": slot}))
	inventory.connect("store_requested", func(k, item): Net.send({"t": "store", "k": k, "item": item}))
	inventory.connect("place_requested", _on_place)
	manual = ManualUI.new()
	ui.add_child(manual)
	manual.connect("craft_requested", _on_craft)
	death_panel = PanelContainer.new()
	death_panel.visible = false
	death_panel.set_anchors_preset(Control.PRESET_CENTER)
	death_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_panel.custom_minimum_size = Vector2(480, 220)
	death_panel.add_theme_stylebox_override("panel", UiTheme.card(28))
	ui.add_child(death_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	death_panel.add_child(column)
	death_title = UiTheme.title("", 30, UiTheme.TEXT)
	death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(death_title)
	death_label = UiTheme.label("", 15, UiTheme.MUTED)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(death_label)
	respawn_button = Button.new()
	respawn_button.custom_minimum_size.y = 44
	UiTheme.primary(respawn_button, 16)
	respawn_button.pressed.connect(func(): Net.send({"t": "respawn"}))
	column.add_child(respawn_button)
	bed_button = Button.new()
	bed_button.custom_minimum_size.y = 44
	UiTheme.secondary(bed_button, 15)
	bed_button.visible = false
	bed_button.pressed.connect(func(): Net.send({"t": "respawn", "bed": true}))
	column.add_child(bed_button)
	_update_bars()

func _update_bars() -> void:
	if bars.is_empty():
		return
	bars["hp"].value = my_hp
	bars["hunger"].value = hunger
	bars["thirst"].value = thirst
	bars["weight"].max_value = carry_cap
	bars["weight"].value = minf(carried, carry_cap)
	if inventory != null:
		var owned: Dictionary = player.get("owned_weapons")
		var weapon_name := "" if owned.is_empty() else str(WeaponData.stats(str(player.get("current_weapon")))["name"]).capitalize()
		inventory.call("set_status", my_hp, hunger, thirst, weapon_name)

func _show_death(title: String, body: String, can_respawn: bool) -> void:
	death_title.text = title.to_upper()
	death_label.text = body
	respawn_button.visible = can_respawn
	death_panel.visible = true
	PointerMode.release()

func _feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	feed.add_child(label)
	while feed.get_child_count() > 6:
		feed.get_child(0).free()
	# Ligado ao próprio texto: se ele já saiu (feed cheio), a ligação some junto.
	get_tree().create_timer(9.0).timeout.connect(label.queue_free)

func _toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)

# ---------------------------------------------------------------- efeitos ---

func _blood(point: Vector3, normal: Vector3) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	particles.spread = 38.0
	particles.initial_velocity_min = 1.5
	particles.initial_velocity_max = 3.5
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.08
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#6b0f0c")
	mesh.material = mat
	particles.mesh = mesh
	main_node.add_child(particles)
	particles.global_position = point
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)

func _tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = length
	mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = mat
	main_node.add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.001:
		mesh.global_basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	get_tree().create_timer(0.06).timeout.connect(mesh.queue_free)

func _vec(value) -> Variant:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null
