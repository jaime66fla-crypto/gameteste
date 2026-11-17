extends Node3D
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
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")
const DrivingScript = preload("res://scripts/survival/survival_driving.gd")
var driving_ctl: Node # carros (survival_driving.gd)
const STATE_RATE := 1.0 / 10.0
const ZOMBIE_RATE := 1.0 / 6.0
const REACH := 2.8 # interação (o servidor aceita um pouco mais)
const SEARCH_TIME := 1.0
const MELEE_COOLDOWN := 0.6

var main_node: Node
var player: CharacterBody3D
var world: Node3D # SurvivalWorld
var my_id := ""
var actors: Dictionary = {} # id -> NetActor (outros jogadores)
var names: Dictionary = {}
var zombies: Dictionary = {} # id -> Zombie
var bags: Dictionary = {} # id -> {node, pos, name, count}
var inv: Dictionary = {}
var carried := 0.0 # kg (servidor)
var carry_cap := 10.0
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
	my_hp = float(you.get("hp", 100))
	hunger = float(you.get("hunger", 100))
	thirst = float(you.get("thirst", 100))
	_apply_inventory(you.get("inv", {}), float(you.get("weight", 0)), float(you.get("cap", 10)), str(you.get("back", "")))
	for entry in info.get("roster", []):
		_add_actor(entry)
	_spawn_zombies(info.get("zombies", []))
	driving_ctl = DrivingScript.new()
	driving_ctl.call("setup", self, main_node, player)
	add_child(driving_ctl)
	driving_ctl.call("spawn_all", info.get("vehicles", []))
	for bag in info.get("bags", []):
		_set_bag(bag)
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
	if bool(you.get("dead", false)):
		_on_local_death()
	_feed("Bem-vindo ao mundo aberto. Sobreviva: ache comida, água e armas.")
	_feed("E revistar/coletar/dirigir  •  TAB inventário  •  Q golpe  •  F curativo  •  T abastecer")
	_feed("Zumbis ouvem tiros. De noite enxergam menos — e você também.")

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

## Jogadores vivos que os zumbis podem atacar (no anfitrião).
## "grass": dentro de grama alta; "crouch": agachado (os dois juntos = escondido).
func _targets() -> Array:
	var list: Array = []
	if not local_dead:
		list.append({"id": my_id, "node": player, "grass": world.call("in_tall_grass", player.global_position), "crouch": bool(player.get("crouching"))})
	for id in actors:
		var actor = actors[id]
		if not actor.dead:
			var state: Dictionary = actor.get("remote_state")
			list.append({"id": id, "node": actor, "grass": world.call("in_tall_grass", actor.global_position), "crouch": bool(state.get("c", false))})
	return list

# ------------------------------------------------------------------- rede ---

func _physics_process(delta: float) -> void:
	_melee_timer = maxf(0.0, _melee_timer - delta)
	_clock_ms += delta * 1000.0
	_update_daylight()
	if local_dead:
		_respawn_left = maxf(0.0, _respawn_left - delta)
		respawn_button.disabled = _respawn_left > 0.0
		respawn_button.text = "Renascer" if _respawn_left <= 0.0 else "Renascer em %d s" % ceili(_respawn_left)
		return
	_sync_ammo()
	# Saiu do lugar ou cancelou: para de golpear.
	if not action.is_empty() and float(player.get("channel_left")) <= 0.0:
		_set_action("", "")
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_RATE
		var p := player.global_position
		var v := player.get_real_velocity() if not is_driving() else Vector3.ZERO
		Net.send({"t": "s", "p": [p.x, p.y, p.z], "y": player.get("yaw"), "pi": player.get("pitch"),
			"w": player.get("current_weapon"), "m": clampf(Vector2(v.x, v.z).length() / 5.0, 0.0, 1.0),
			"r": player.get("sprinting"), "c": player.get("crouching"), "a": player.get("aiming"),
			"f": not player.is_on_floor() and not is_driving(), "rl": player.get("reloading"), "h": player.get("weapon_holstered"), "v": [v.x, v.z],
			"act": action, "tool": action_tool})
	_zombie_timer -= delta
	if _zombie_timer <= 0.0 and is_host():
		_zombie_timer = ZOMBIE_RATE
		var list: Array = []
		for z in zombies.values():
			if not z.dead and z.controlled:
				list.append(z.call("state"))
		if not list.is_empty():
			Net.send({"t": "z", "l": list})

func is_driving() -> bool:
	return driving_ctl != null and bool(driving_ctl.call("is_driving"))

func _on_message(data: Dictionary) -> void:
	if driving_ctl != null and bool(driving_ctl.call("on_message", data)):
		return
	match str(data.get("t", "")):
		"s":
			var actor = actors.get(str(data.get("id", "")))
			if actor != null:
				actor.call("apply_state", data)
				# Dirigindo: o corpo some (está dentro do carro).
				actor.visible = str(data.get("dv", "")).is_empty()
				actor.call("set_action", str(data.get("act", "")), str(data.get("tool", "")))
				var visual = actor.get("visual")
				if visual != null and visual.has_method("set_backpack"):
					visual.call("set_backpack", str(data.get("bp", "")))
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
				z.hp = float(data.get("hp", 0))
		"zdead":
			var z = zombies.get(str(data.get("id", "")))
			if z != null:
				z.call("die")
				zombies.erase(str(data["id"]))
			if str(data.get("by", "")) == my_id:
				combat_feedback.call("show_hit", str(data.get("zone", "")) == "head", true)
				player.get("sound_fx").call("kill_confirm")
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
				_tracer(o, e)
				_noise(o)
				var shooter = actors.get(str(data.get("id", "")))
				if shooter != null:
					shooter.call("play_remote_shot", str(data.get("w", "pistol")))
		"hp":
			_on_health(data)
		"inv":
			_apply_inventory(data.get("inv", {}), float(data.get("weight", 0)), float(data.get("cap", 10)), str(data.get("back", "")))
		"stats":
			my_hp = float(data.get("hp", my_hp))
			hunger = float(data.get("hunger", hunger))
			thirst = float(data.get("thirst", thirst))
			_update_bars()
		"container":
			_open_container = str(data.get("k", ""))
			var spot: Dictionary = world.containers.get(_open_container, {})
			_open_container_pos = spot.get("pos", bags.get(_open_container, {}).get("pos", player.global_position))
			var items: Dictionary = data.get("items", {})
			inventory.call("show_container", _open_container, str(data.get("title", "Recipiente")), items)
			if not inventory.visible:
				inventory.call("open")
			if world.containers.has(_open_container):
				world.call("set_container_empty", _open_container, items.is_empty())
		"emptied":
			world.call("set_container_empty", str(data.get("k", "")), true)
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
		main_node.add_child(z)
		z.call("set_controlled", is_host())
		zombies[id] = z

func _on_zombie_attack(zombie_id: String, target_id: String) -> void:
	if is_host():
		Net.send({"t": "zhit", "z": zombie_id, "target": target_id})

## Tiro (meu ou de outro): zumbis por perto vão atrás do barulho.
func _noise(at: Vector3) -> void:
	if not is_host():
		return
	for z in zombies.values():
		z.call("hear", at)

func _on_local_shot(weapon_id: String, from: Vector3, to: Vector3) -> void:
	Net.send({"t": "shot", "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]})
	_noise(from)

## Acerto de bala num zumbi ou jogador (hitbox): o servidor calcula o dano.
func _on_target_damaged(target_id: String, zone: String, point: Vector3, normal: Vector3, weapon: String) -> void:
	if local_dead:
		return
	if weapon.is_empty():
		weapon = str(player.get("current_weapon"))
	Net.send({"t": "hit", "target": target_id, "zone": zone, "w": weapon})
	var headshot := zone == "head"
	combat_feedback.call("show_hit", headshot)
	player.get("sound_fx").call("hit_confirm", headshot)
	_blood(point, normal)

## Q: soco ou a melhor arma branca da mochila, em quem estiver na frente.
func _melee() -> void:
	if local_dead or _melee_timer > 0.0:
		return
	_melee_timer = MELEE_COOLDOWN
	var camera := get_viewport().get_camera_3d()
	var forward := -camera.global_basis.z
	var from := player.global_position + Vector3(0, 1.35, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * 2.4, HitboxScript.SHOT_MASK)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var body: Object = hit["collider"]
	var target = body.get("actor") if body != null else null
	if target == null:
		return
	var target_id := str(target.get("zombie_id")) if target.get("zombie_id") != null else str(target.get("actor_id"))
	var best: Array = SurvivalData.best_melee(inv)
	Net.send({"t": "melee", "target": target_id, "item": best[0], "zone": str(body.get("zone"))})
	combat_feedback.call("show_hit", str(body.get("zone")) == "head")
	player.get("sound_fx").call("hit_confirm", false)
	_blood(hit["position"], hit["normal"])

func _on_health(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var hp := float(data.get("hp", 0))
	var killed := bool(data.get("killed", false))
	var by := str(data.get("by", ""))
	if id == my_id:
		if hp < my_hp:
			damage_flash.color.a = clampf(0.2 + (my_hp - hp) / 50.0, 0.2, 0.55)
			player.call("add_hit_shake", clampf((my_hp - hp) / 20.0, 0.25, 1.0))
			player.get("sound_fx").call("hurt")
		my_hp = hp
		_update_bars()
		if killed:
			var cause: String = str({"fome": "de fome", "sede": "de sede", "zombie": "para os zumbis"}.get(str(data.get("w", "")), ""))
			if cause.is_empty():
				cause = "para " + str(names.get(by, "alguém"))
			_feed("Você morreu %s." % cause)
			_on_local_death()
	elif actors.has(id):
		actors[id].call("set_hp", hp, killed)
		if killed:
			_feed("%s morreu." % names.get(id, "?"))
	if killed and by == my_id and id != my_id:
		player.get("sound_fx").call("kill_confirm")
		_toast("ELIMINOU %s" % str(names.get(id, "")).to_upper())

func _on_local_death() -> void:
	if driving_ctl != null:
		driving_ctl.call("force_exit")
	_set_action("", "")
	local_dead = true
	_respawn_left = 8.0
	inventory.call("close")
	player.set_physics_process(false)
	player.visible = false
	_show_death("VOCÊ MORREU", "Suas coisas ficaram numa mochila onde você caiu.\nVocê renasce num ponto aleatório com o kit inicial.", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	_apply_inventory(data.get("inv", {}), float(data.get("weight", 0)), float(data.get("cap", 10)), str(data.get("back", "")))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --------------------------------------------------------------- mochila ---

## O servidor mandou a mochila: armas aparecem/somem e a munição vira reserva.
func _apply_inventory(new_inv: Dictionary, weight: float, cap: float, back: String = "") -> void:
	inv = new_inv
	carried = weight
	carry_cap = cap
	inventory.call("set_inventory", inv, weight, cap, back)
	var avatar = player.get("humanoid_avatar")
	if avatar != null and avatar.has_method("set_backpack"):
		avatar.call("set_backpack", back)
	var owned: Dictionary = player.get("owned_weapons")
	for item in inv:
		var w := SurvivalData.weapon_of(str(item))
		if not w.is_empty() and not owned.has(w):
			player.call("give_weapon", w, 0)
			# Arma nova vem descarregada: precisa de munição da mochila (R).
			var mags: Dictionary = player.get("magazines")
			mags[w] = 0
			if player.get("current_weapon") == w:
				player.set("ammo", 0)
			_toast("%s na mochila — R para carregar" % SurvivalData.item_name(str(item)))
	for w in owned.keys():
		if not inv.has("w_" + str(w)):
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

## A recarga tirou balas da reserva: avisa o servidor e iguala as armas do mesmo calibre.
func _sync_ammo() -> void:
	var reserve: Dictionary = player.get("reserve_ammo")
	for w in player.get("owned_weapons"):
		var ammo_item := SurvivalData.ammo_for(str(w))
		var known := int(_ammo_known.get(ammo_item, 0))
		var now := int(reserve.get(w, 0))
		if now < known:
			Net.send({"t": "consume", "ammo": ammo_item, "n": known - now})
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

func _on_use(item: String) -> void:
	var entry := SurvivalData.item(item)
	if entry.has("use_time"):
		var seconds := float(entry["use_time"])
		if player.call("start_channel", SurvivalData.item_name(item).to_upper(), seconds, func(): Net.send({"t": "use", "item": item})):
			Net.send({"t": "use_start", "item": item})
		return
	Net.send({"t": "use", "item": item})
	player.get("sound_fx").call("reload")

func _on_craft(recipe: String) -> void:
	Net.send({"t": "craft", "recipe": recipe})

## F: bandagem, depois analgésico, depois kit médico.
func _quick_heal() -> void:
	if local_dead:
		return
	if my_hp >= 100.0:
		_toast("VIDA CHEIA")
		return
	for item in ["bandage", "painkillers", "medkit"]:
		if inv.has(item):
			_on_use(item)
			return
	_toast("SEM CURATIVO NA MOCHILA")

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
			best = {"type": "container", "id": id, "label": "[E] Abrir mochila" + (" de " + str(bags[id]["name"]) if str(bags[id]["name"]) != "" else "")}
	for id in world.resources:
		var entry: Dictionary = world.resources[id]
		if entry["depleted"]:
			continue
		var pos: Vector3 = entry["pos"]
		var reach := 3.2 if str(entry["kind"]) == "car" else REACH
		var d := Vector2(pos.x - me.x, pos.z - me.z).length()
		if d < minf(best_d + 0.6, reach):
			best_d = d
			var rule := SurvivalData.resource_rule(str(entry["kind"]))
			var verb: String = str({"tree": "Cortar", "rock": "Quebrar", "car": "Desmontar", "bush": "Colher"}.get(str(entry["kind"]), "Coletar"))
			var tool := _tool_for(str(rule.get("tool", "")))
			var tool_note := ("  —  com " + SurvivalData.item_name(tool)) if not tool.is_empty() else ("  —  sem ferramenta rende pouco" if rule.has("tool") else "")
			best = {"type": "resource", "id": id, "kind": str(entry["kind"]), "pos": pos, "tool": tool, "time": float(rule.get("time", 2.5)), "label": "[E] %s %s (%s)%s" % [verb, str(rule.get("name", "")), SurvivalData.item_name(str(rule.get("gives", ""))), tool_note]}
	# Carro que funciona: só se não houver nada mais perto.
	if driving_ctl != null and (best.is_empty() or best["type"] == "resource"):
		var car: Dictionary = driving_ctl.call("target_near", me)
		if not car.is_empty():
			best = car
	return best

## Melhor ferramenta da mochila para o recurso ("wood" = machado, "scrap" = pé de cabra).
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
	if _target["type"] == "vehicle":
		driving_ctl.call("request_enter", id)
	elif _target["type"] == "container":
		player.call("start_channel", "REVISTANDO", SEARCH_TIME, func(): Net.send({"t": "search", "k": id}))
	else:
		var seconds := float(_target["time"])
		var kind := str(_target["kind"])
		var label: String = str({"tree": "CORTANDO", "rock": "QUEBRANDO", "car": "DESMONTANDO", "bush": "COLHENDO"}.get(kind, "COLETANDO"))
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
			var wanted := {"tree": 1.15, "rock": 1.3, "car": 1.9}.get(kind, 0.0) as float
			if wanted > 0.0 and to.length() > wanted + 0.15:
				var spot: Vector3 = (_target["pos"] as Vector3) - to.normalized() * wanted
				spot.y = player.global_position.y
				create_tween().tween_property(player, "global_position", spot, 0.25)
			if kind != "bush":
				_set_action("chop" if kind == "tree" else "pry", str(_target["tool"]))
	return true

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
	mat.albedo_color = Color("#4b5a32")
	mesh.material_override = mat
	node.add_child(mesh)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = "Mochila" + (" de " + str(data.get("name", "")) if str(data.get("name", "")) != "" else "")
	label.font_size = 32
	label.outline_size = 8
	label.pixel_size = 0.004
	label.position.y = 0.8
	label.modulate = Color("#ff9a7a")
	node.add_child(label)
	bags[id] = {"node": node, "pos": p, "name": str(data.get("name", "")), "count": int(data.get("count", 0))}

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
		_feed("A noite caiu. Os zumbis estão mais perigosos no escuro." if night else "Amanheceu.")
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

func _process(delta: float) -> void:
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 0.8)
	if not local_dead and not is_driving():
		var target := _find_target()
		prompt.visible = not target.is_empty() and not inventory.visible
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
		entry["label"].visible = (entry["pos"] as Vector3).distance_to(player.global_position) < 6.0
	var hour := game_hour()
	var day := int(floor(_clock_ms / _day_ms)) + 1
	clock_label.text = "Dia %d  •  %02d:%02d\n%d/16 online" % [day, int(hour), int(fmod(hour, 1.0) * 60.0), online]

func _unhandled_input(event: InputEvent) -> void:
	if driving_ctl != null and bool(driving_ctl.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_T and not local_dead:
		if bool(driving_ctl.call("request_refuel")):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_TAB or event.physical_keycode == KEY_I):
		if local_dead:
			return
		if inventory.visible:
			inventory.call("close")
		else:
			inventory.call("open")
		get_viewport().set_input_as_handled()

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
		var label := Label.new()
		label.text = spec[1]
		label.custom_minimum_size.x = 52
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		row.add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(220, 16)
		bar.show_percentage = false
		var fill := StyleBoxFlat.new()
		fill.bg_color = spec[2]
		bar.add_theme_stylebox_override("fill", fill)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.55)
		bar.add_theme_stylebox_override("background", bg)
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
	prompt.add_theme_color_override("font_color", Color("#ffe08a"))
	prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	ui.add_child(prompt)
	toast_label = Label.new()
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.anchor_top = 0.3
	toast_label.offset_left = -360
	toast_label.offset_right = 360
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast_label.modulate.a = 0.0
	ui.add_child(toast_label)
	feed = VBoxContainer.new()
	feed.position = Vector2(18, 212) # abaixo do minimapa
	feed.custom_minimum_size.x = 520
	ui.add_child(feed)
	inventory = InventoryUI.new()
	ui.add_child(inventory)
	inventory.connect("take_requested", _on_take)
	inventory.connect("take_all_requested", _on_take_all)
	inventory.connect("drop_requested", _on_drop)
	inventory.connect("use_requested", _on_use)
	inventory.connect("craft_requested", _on_craft)
	inventory.connect("equip_requested", func(item): Net.send({"t": "equip", "item": item}))
	inventory.connect("unequip_requested", func(): Net.send({"t": "unequip"}))
	death_panel = PanelContainer.new()
	death_panel.visible = false
	death_panel.set_anchors_preset(Control.PRESET_CENTER)
	death_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_panel.custom_minimum_size = Vector2(460, 200)
	ui.add_child(death_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	death_panel.add_child(column)
	death_label = Label.new()
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(death_label)
	respawn_button = Button.new()
	respawn_button.custom_minimum_size.y = 40
	respawn_button.pressed.connect(func(): Net.send({"t": "respawn"}))
	column.add_child(respawn_button)
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
	death_label.text = title + "\n\n" + body
	respawn_button.visible = can_respawn
	death_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	feed.add_child(label)
	while feed.get_child_count() > 6:
		feed.get_child(0).free()
	get_tree().create_timer(9.0).timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free())

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
