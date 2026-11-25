extends Node3D
const PointerMode = preload("res://scripts/pointer_mode.gd")
## Runs an online elimination match inside main.tscn (added by main.gd when
## Net.in_match is set). The server owns health; this node mirrors it.
const NetActorScript = preload("res://scripts/net/net_actor.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const Melee = preload("res://scripts/melee.gd")
const CombatFeedbackScript = preload("res://scripts/net/combat_feedback.gd")
const STATE_RATE := 1.0 / 15.0
const BOT_RATE := 1.0 / 10.0
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const LootCrateScript = preload("res://scripts/net/loot_crate.gd")
const BotNav = preload("res://scripts/net/bot_nav.gd")
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const LOOT_REACH := 2.4 # metres; the server allows a little more for latency
const LABEL_RANGE := 9.0

var main_node: Node
var player: CharacterBody3D
var actors: Dictionary = {} # id -> NetActor
var crates: Dictionary = {} # id -> LootCrate
var loot_prompt: Label
var _pending_loot := ""
var names: Dictionary = {} # id -> display name
var my_id := ""
var alive_count := 8
var my_hp := 100.0
var my_medkits := 0 # carried; F uses one (the server confirms)
const MAX_MEDKITS := 5
var my_nades := 0 # grenades carried; G throws one
var remote_nades: Dictionary = {} # "by:id" -> grenade copy flying on this client
const GrenadeScript = preload("res://scripts/weapons/grenade.gd")
var my_kills := 0
var local_dead := false
var finished := false
var _state_timer := 0.0
var _bot_timer := 0.0
# Spectator camera after death.
var spectate_camera: Camera3D
var spectate_id := "" # who the eliminated player is watching (starts with the killer)
var bots: Dictionary = {} # id -> true for bots
var ranks: Dictionary = {} # id -> rank name (players)
# Team matches (custom 2x2 / 4x4 rooms).
var team_mode := false
## Mata-mata: renasce depois de alguns segundos; vence quem chegar a kill_goal abates.
var dm_mode := false
var kill_goal := 15
var kill_counts: Dictionary = {} # id -> abates (placar ao vivo)
var respawn_left := 0.0 # segundos até renascer (jogador local morto)
var match_ends_msec := 0 # Time.get_ticks_msec() em que o tempo acaba
var dm_kit: Dictionary = {"pistol": 90}
## Loja: créditos (servidor confirma) e a janela de compra (início / renascer).
const ShopPanelScript = preload("res://scripts/net/shop_panel.gd")
var credits := 0
var buy_window_ms := 120000
var buy_until_msec := 0
var shop: Control
var my_team := -1
var teams: Dictionary = {} # id -> 0/1
var team_names: Array = ["Alfa", "Bravo"]
## Rounds da sala personalizada (melhor de 5): placar de rounds por equipe.
var round_number := 1
var round_total := 5
var round_to_win := 3
var round_score: Array = [0, 0]
var round_break := false # pausa entre rounds (o servidor ignora tiros e movimento)
var round_history: Array = [] # vencedor de cada round já jogado (0/1, -1 = empate)
var round_panel: PanelContainer
var _round_next_msec := 0
var _round_break_ms := 5000
var _round_countdown: Label
var _round_drain: ProgressBar
## Placar ao vivo (segurar TAB): mortes e quem saiu, além de kill_counts.
var deaths: Dictionary = {} # id -> mortes
var left_ids: Dictionary = {} # id -> true (saiu da partida)
var score_panel: PanelContainer
var _score_refresh := 0.0
var match_xp := 0
var killer_panel: PanelContainer
var killer_title: Label
var killer_subtitle: Label
var xp_feed: VBoxContainer
# UI
var ui: CanvasLayer
var status_label: Label
var health_bar: ProgressBar
var feed: VBoxContainer
var center_panel: PanelContainer
var center_title: Label
var center_body: Label
var damage_flash: ColorRect
var leave_panel: PanelContainer
var room_button: Button
var leave_text: Label
var combat_feedback: Control

func setup(main: Node, local_player: CharacterBody3D) -> void:
	main_node = main
	player = local_player

func _ready() -> void:
	name = "MatchController"
	my_id = Net.my_id
	_build_ui()
	var info: Dictionary = Net.start_info
	alive_count = int(info.get("alive", 8))
	for crate_data in info.get("crates", []):
		_add_crate(crate_data)
	player.call("start_unarmed")
	player.set("interact_handler", _try_loot)
	player.set("heal_handler", _use_medkit)
	player.set("melee_handler", _punch)
	player.set("grenade_handler", _throw_grenade)
	player.set("grenade_check", _can_throw_grenade)
	team_mode = bool(info.get("party", false))
	dm_mode = str(info.get("mode", "")) == "dm"
	kill_goal = int(info.get("goal", kill_goal))
	if info.get("kit") is Dictionary and not (info["kit"] as Dictionary).is_empty():
		dm_kit = info["kit"]
	if info.has("duration"):
		match_ends_msec = Time.get_ticks_msec() + int(info["duration"])
	var shop_info: Dictionary = info.get("shop", {}) if info.get("shop") is Dictionary else {}
	if not shop_info.is_empty():
		credits = int(shop_info.get("credits", 0))
		buy_window_ms = int(shop_info.get("window", buy_window_ms))
		buy_until_msec = Time.get_ticks_msec() + buy_window_ms
		shop = ShopPanelScript.new()
		shop.call("setup", shop_info)
		ui.add_child(shop)
		shop.connect("buy_requested", _request_buy)
		shop.connect("close_requested", _close_shop)
	if info.get("teams") is Array:
		team_names = info["teams"]
	if info.get("rounds") is Dictionary:
		_read_rounds(info["rounds"])
	for entry in info.get("roster", []):
		teams[str(entry["id"])] = int(entry.get("team", -1))
	my_team = int(teams.get(my_id, -1))
	for entry in info.get("roster", []):
		var id := str(entry["id"])
		names[id] = str(entry["name"])
		bots[id] = bool(entry.get("bot", false))
		ranks[id] = str(entry.get("rank", ""))
		# Everyone starts at a spawn of the map, facing the middle of the map.
		var spawn: Vector3 = MatchLayout.spawn_point(int(entry.get("spawn", 0)))
		var sp = entry.get("sp")
		if sp is Array and sp.size() == 2:
			spawn = Vector3(float(sp[0]), 0, float(sp[1])) # team matches: exact spot from the server
		var facing := MatchLayout.spawn_yaw(spawn)
		if id == my_id:
			player.global_position = spawn + Vector3(0, 0.1, 0)
			player.set("yaw", facing)
			player.rotation.y = facing
			continue
		var actor: CharacterBody3D = NetActorScript.new()
		actor.call("setup", id, str(entry["name"]), bool(entry.get("bot", false)))
		actor.set("tag_subtitle", "BOT" if bots[id] else ranks[id])
		actor.set("team", teams[id])
		actor.set("ally", team_mode and teams[id] == my_team)
		actor.position = spawn + Vector3(0, 0.1, 0)
		actor.rotation.y = facing
		actor.set("combatants", _combatants)
		actor.set("crate_targets", _crate_targets)
		actor.connect("damaged", _on_actor_damaged)
		actor.connect("bot_fired", _on_bot_fired)
		actor.connect("bot_hit", _on_bot_hit)
		actor.connect("bot_loot", _on_bot_loot)
		actor.connect("bot_heal", _on_bot_heal)
		main_node.add_child(actor)
		actors[id] = actor
		if bots[id] and entry.has("w"):
			actor.call("give_weapon", str(entry["w"])) # bots spawn armed (the server picks)
			actor.set("medkits", int(entry.get("medkits", 0)))
		elif dm_mode:
			for weapon_id in dm_kit:
				actor.call("give_weapon", weapon_id)
	if dm_mode:
		for weapon_id in dm_kit:
			player.call("give_weapon", weapon_id, int(dm_kit[weapon_id]))
	# Bot navigation grid (~0.2 s): build it while the match loads, not on the
	# first bot step (any client may become the bot host later). Waits two physics
	# frames: the map's walls only reach the physics space after a step.
	_build_bot_grid.call_deferred()
	player.connect("shot_fired", _on_local_shot)
	Net.message.connect(_on_message)
	Net.connection_lost.connect(_on_connection_lost)
	_apply_host()
	Net.attach_consumer()
	if team_mode:
		var team_size := int(alive_count / 2.0)
		_feed("Partida em equipes %dx%d! Você está na equipe %s — elimine a equipe adversária." % [team_size, team_size, _team_name(my_team)])
		_feed("Melhor de %d rounds: a primeira equipe a vencer %d leva a partida." % [round_total, round_to_win])
		_feed("Aliados têm o nome em azul (visível através das paredes). Não há fogo amigo.")
	elif dm_mode:
		_feed("Mata-mata! %d combatentes — o primeiro a fazer %d abates vence." % [alive_count, kill_goal])
		_feed("Morreu? Você renasce em poucos segundos com uma pistola. As caixas se reabastecem.")
	else:
		_feed("Partida iniciada! %d combatentes — o último vivo vence." % alive_count)
	if shop == null and not crates.is_empty():
		_feed("Procure caixas de suprimentos pelo mapa: [E] coleta armas, kits e granadas.")
	if shop != null:
		var secs := int(buy_window_ms / 1000.0)
		var window_text := ("%d min" % (secs / 60)) if secs % 60 == 0 else ("%d s" % secs)
		_feed("Loja aberta: %s para comprar com seus $%d (B abre/fecha). Abates dão créditos." % [window_text, credits])
		_open_shop()

func _build_bot_grid() -> void:
	var world: World3D = main_node.get_world_3d()
	for i in 2:
		await get_tree().physics_frame
	if is_inside_tree() and not BotNav.ready_for(world):
		BotNav.grid_for(world)

func _exit_tree() -> void:
	if Net.message.is_connected(_on_message):
		Net.message.disconnect(_on_message)
	if Net.connection_lost.is_connected(_on_connection_lost):
		Net.connection_lost.disconnect(_on_connection_lost)

func is_host() -> bool:
	return Net.host_id == my_id and not my_id.is_empty()

func _apply_host() -> void:
	for actor in actors.values():
		actor.call("set_controlled", is_host() and actor.is_bot)

## Everyone still alive, as targets for the bots this client simulates.
func _combatants() -> Array:
	var list: Array = []
	if not local_dead:
		list.append({"id": my_id, "node": player, "team": my_team})
	for id in actors:
		var actor = actors[id]
		if not actor.dead:
			list.append({"id": id, "node": actor, "team": teams.get(id, -1)})
	return list

## Linha curta acima da munição (HUD): créditos, loja, kits e granadas.
func hud_extra() -> String:
	if local_dead or finished:
		return ""
	var line := "KITS %d [F]   GRANADAS %d [G]" % [my_medkits, my_nades]
	if shop != null:
		line = "$%d   " % credits + line
		if can_shop():
			line += "   [B] LOJA %ds" % ceili(_buy_seconds_left())
	return line

# ------------------------------------------------------------------ loja ---

func _buy_seconds_left() -> float:
	return maxf(0.0, (buy_until_msec - Time.get_ticks_msec()) / 1000.0)

func can_shop() -> bool:
	return shop != null and not local_dead and not finished and _buy_seconds_left() > 0.0

## Main/player: the cursor stays free while the shop is open.
func ui_open() -> bool:
	return shop != null and shop.visible

func _open_shop() -> void:
	if not can_shop():
		if shop != null and not local_dead and not finished:
			_toast("TEMPO DE COMPRA ENCERRADO")
		return
	Input.action_release("fire")
	Input.action_release("aim")
	player.set("aiming", false)
	shop.call("show_note", "")
	_refresh_shop()
	if not shop.visible:
		UiSfx.play(&"open")
	shop.visible = true
	PointerMode.release()

func _close_shop() -> void:
	if shop == null or not shop.visible:
		return
	UiSfx.play(&"close")
	shop.visible = false
	if not local_dead and not finished and not leave_panel.visible:
		PointerMode.capture()

func _refresh_shop() -> void:
	if shop != null:
		shop.call("refresh", credits, player.get("owned_weapons"), my_medkits, my_nades, _buy_seconds_left())

func _request_buy(item: String) -> void:
	if can_shop():
		Net.send({"t": "buy", "item": item})

func _on_bought(data: Dictionary) -> void:
	var by := str(data.get("by", ""))
	var item := str(data.get("item", ""))
	var is_weapon := WeaponData.DATA.has(item)
	if by == my_id:
		credits = int(data.get("credits", credits))
		if is_weapon:
			var was_armed := not bool(player.get("weapon_holstered"))
			player.call("give_weapon", item, int(data.get("ammo", 0)))
			if was_armed:
				player.call("_equip_weapon", item) # a compra vai direto para a mão
			_toast("COMPROU %s" % str(WeaponData.stats(item)["name"]).to_upper())
		else:
			_toast("COMPROU %s" % ("KIT MÉDICO" if item == "medkit" else "GRANADA"))
		player.get("sound_fx").call("reload")
		_refresh_shop()
	elif actors.has(by) and is_weapon:
		actors[by].call("give_weapon", item)

func _on_credits(data: Dictionary) -> void:
	credits = int(data.get("total", credits))
	var tag := "  (cabeça)" if bool(data.get("head", false)) else ""
	if bool(data.get("round", false)):
		tag = "  (fim do round)"
	_xp_toast("+$%d  créditos%s" % [int(data.get("amount", 0)), tag])
	_refresh_shop()

## Aliados vivos, para o minimapa (só em equipes).
func ally_nodes() -> Array:
	var list: Array = []
	if not team_mode:
		return list
	for id in actors:
		if is_ally(id) and not actors[id].dead:
			list.append(actors[id])
	return list

func _team_name(team: int) -> String:
	return str(team_names[team]) if team >= 0 and team < team_names.size() else "?"

func is_ally(id: String) -> bool:
	return team_mode and int(teams.get(id, -2)) == my_team

## Living combatants per side: [allies, enemies] (local player included in allies).
func _team_alive() -> Array:
	var counts := [0 if local_dead else 1, 0]
	for id in actors:
		if not actors[id].dead:
			counts[0 if is_ally(id) else 1] += 1
	return counts

# ------------------------------------------------------------ networking ---

func _physics_process(delta: float) -> void:
	if finished:
		return
	_state_timer -= delta
	if _state_timer <= 0.0 and not local_dead:
		_state_timer = STATE_RATE
		var p := player.global_position
		var v := player.get_real_velocity()
		var move := clampf(Vector2(v.x, v.z).length() / 5.0, 0.0, 1.0)
		var state := {"t": "s", "p": [p.x, p.y, p.z], "y": player.call("network_yaw"), "pi": player.get("pitch"),
			"w": player.get("current_weapon"), "m": move, "r": player.get("sprinting"),
			"c": player.get("crouching"), "pr": player.get("prone"), "a": player.get("aiming"), "f": not player.is_on_floor(),
			"rl": player.get("reloading"), "h": player.get("weapon_holstered"), "v": [v.x, v.z], "l": player.get("lean"),
			"ch": player.get("character_id")}
		if player.has_method("has_bow") and bool(player.call("has_bow")):
			var bow: Node = player.get("bow_controller")
			state["tool"] = "bow"
			state["act"] = "bow_draw" if bool(bow.get("draw").drawing) else "bow_carry"
			state["charge"] = float(bow.get("draw").charge)
		Net.send(state)
	_bot_timer -= delta
	if _bot_timer <= 0.0 and is_host():
		_bot_timer = BOT_RATE
		# Só bots vivos (todos os jogadores morreram ou saíram): modo caçada, para a
		# partida não se arrastar com bots passeando pelo mapa.
		# Mata-mata: quem morre volta em segundos, então nunca entra em caçada.
		var humans_alive := not local_dead or dm_mode
		for actor in actors.values():
			if not actor.is_bot and not actor.dead:
				humans_alive = true
		var list: Array = []
		for actor in actors.values():
			if actor.is_bot and actor.controlled and not actor.dead:
				actor.set("hunt_mode", not humans_alive)
				list.append(actor.call("bot_state"))
		if not list.is_empty():
			Net.send({"t": "b", "l": list})

func _on_message(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"s":
			var actor = actors.get(str(data.get("id", "")))
			if actor != null:
				actor.call("apply_state", data)
		"b":
			for entry in data.get("l", []):
				var actor = actors.get(str(entry.get("id", "")))
				if actor != null:
					actor.call("apply_state", entry)
		"shot":
			var origin = _vec(data.get("o"))
			var end = _vec(data.get("e"))
			if origin != null and end != null:
				var shooter = actors.get(str(data.get("id", "")))
				var weapon := str(data.get("w", "rifle"))
				if weapon == "bow":
					var speed = _vec(data.get("v"))
					if shooter != null and speed != null:
						shooter.call("play_remote_arrow", origin, speed, str(data.get("a", "")))
				else:
					_tracer(origin, end)
					if shooter != null:
						shooter.call("play_remote_shot", weapon)
		"hp":
			_on_health(data)
		"host":
			_apply_host()
			if is_host():
				_feed("Você agora controla os bots desta partida.")
		"leave":
			var who := str(data.get("id", ""))
			if names.has(who):
				left_ids[who] = true
				_feed("%s saiu da partida." % names[who])
		"end":
			_on_end(data)
		"round_end":
			_on_round_end(data)
		"round":
			_on_round(data)
		"looted":
			_on_looted(data)
		"respawn":
			_on_respawn(data)
		"bought":
			_on_bought(data)
		"buy_denied":
			credits = int(data.get("credits", credits))
			if shop != null:
				shop.call("show_note", str(data.get("message", "")))
			_toast(str(data.get("message", "")).to_upper())
			_refresh_shop()
		"credits":
			_on_credits(data)
		"refill":
			var refilled: Dictionary = data.get("crate", {})
			var crate = crates.get(str(refilled.get("id", "")))
			if crate != null:
				crate.call("refill", refilled)
		"loot_denied":
			if str(data.get("by", "")) == my_id:
				_toast(str(data.get("message", "")).to_upper())
				_pending_loot = ""
		"medkits":
			_on_medkits(data)
		"nades":
			if str(data.get("id", "")) == my_id:
				my_nades = int(data.get("count", 0))
		"nade":
			_on_remote_nade(data)
		"boom":
			_on_boom(data)
		"xp":
			_on_xp(data)
		"profile":
			_on_profile(data)
		"crate":
			_add_crate(data.get("crate", {}))
			var crate_data: Dictionary = data.get("crate", {})
			if bool(crate_data.get("drop", false)):
				_feed("%s deixou uma caixa com as armas." % str(crate_data.get("name", "")))

# ------------------------------------------------------------------ loot ---

func _add_crate(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	if id.is_empty() or crates.has(id):
		return
	var p: Array = data.get("p", [0, 0, 0])
	var crate: StaticBody3D = LootCrateScript.new()
	crate.call("setup", data)
	crate.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	main_node.add_child(crate)
	crates[id] = crate
	if bool(data.get("open", false)):
		crate.call("mark_opened")

## Unopened crates, for the bots this client simulates.
func _crate_targets() -> Array:
	var list: Array = []
	for id in crates:
		var crate = crates[id]
		# Bots walk on the ground only: the tower roof crate is for players.
		if not crate.opened and crate.global_position.y < 1.5:
			list.append({"id": id, "pos": crate.global_position, "med": crate.is_med})
	return list

func _closest_crate(reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for crate in crates.values():
		if crate.opened:
			continue
		var offset: Vector3 = crate.global_position - player.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance and absf(offset.y) < 2.0:
			best_distance = distance
			best = crate
	return best

## Player pressed E. Returns true when a crate was in reach (no elbow strike).
func _try_loot() -> bool:
	if local_dead or finished:
		return false
	var crate := _closest_crate(LOOT_REACH)
	if crate == null:
		return false
	if crate.is_med and my_medkits >= MAX_MEDKITS:
		_toast("LIMITE DE %d KITS" % MAX_MEDKITS)
		return true
	_pending_loot = crate.get("crate_id")
	Net.send({"t": "loot", "crate": _pending_loot})
	return true

func _on_bot_loot(actor_id: String, crate_id: String) -> void:
	if is_host():
		Net.send({"t": "loot", "crate": crate_id, "bot": actor_id})

## F: use one carried medkit (+50 health, server-confirmed).
func _use_medkit() -> void:
	if local_dead or finished:
		return
	if my_medkits <= 0:
		_toast("SEM KIT MÉDICO")
	elif my_hp >= 100.0:
		_toast("VIDA CHEIA")
	elif float(player.get("channel_left")) <= 0.0:
		# 3 s with the on-screen clock; the server checks the time too.
		if player.call("start_channel", "KIT MÉDICO", 3.0, func(): Net.send({"t": "heal"})):
			Net.send({"t": "heal_start"})

## Holding G only shows the aim preview when there is a grenade to throw.
func _can_throw_grenade() -> bool:
	if local_dead or finished:
		return false
	if my_nades <= 0:
		_toast("SEM GRANADA")
		return false
	return true

## G released: throw a grenade. This client flies it and reports the blast position.
func _throw_grenade() -> void:
	if local_dead or finished:
		return
	if my_nades <= 0:
		_toast("SEM GRANADA")
		return
	my_nades -= 1 # the server confirms with "nades"
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var grenade_id := ""
	for i in 6:
		grenade_id += chars[randi() % chars.length()]
	var grenade: RigidBody3D = player.call("throw_grenade", grenade_id)
	grenade.connect("exploded", _on_my_grenade_exploded)
	var o := grenade.global_position
	var v := grenade.linear_velocity
	Net.send({"t": "throw", "id": grenade_id, "o": [o.x, o.y, o.z], "v": [v.x, v.y, v.z]})

func _on_my_grenade_exploded(grenade_id: String, at: Vector3) -> void:
	Net.send({"t": "boom", "id": grenade_id, "p": [at.x, at.y, at.z]})

## Someone else's grenade: fly a copy until the server reports the blast.
func _on_remote_nade(data: Dictionary) -> void:
	var o = _vec(data.get("o"))
	var v = _vec(data.get("v"))
	if o == null or v == null:
		return
	var grenade: RigidBody3D = GrenadeScript.new()
	grenade.set("live", false)
	main_node.add_child(grenade)
	grenade.global_position = o
	grenade.linear_velocity = v
	remote_nades[str(data.get("by", "")) + ":" + str(data.get("id", ""))] = grenade
	# The thrower's body does the overhand throw on everyone's screen.
	var thrower = actors.get(str(data.get("by", "")))
	if thrower != null and thrower.get("visual") != null and thrower.visual.has_method("play_action"):
		thrower.visual.call("play_action", "throw")

func _on_boom(data: Dictionary) -> void:
	var by := str(data.get("by", ""))
	var at = _vec(data.get("p"))
	if by == my_id or at == null:
		return # our own grenade already exploded here
	var key := by + ":" + str(data.get("id", ""))
	var copy = remote_nades.get(key)
	remote_nades.erase(key)
	if copy != null and is_instance_valid(copy):
		copy.call("explode", at)
	else:
		GrenadeScript.spawn_explosion(main_node, at)

func _on_bot_heal(actor_id: String) -> void:
	if not is_host():
		return
	Net.send({"t": "heal_start", "bot": actor_id})
	get_tree().create_timer(3.05).timeout.connect(func():
		if is_host() and not finished:
			Net.send({"t": "heal", "bot": actor_id}))

func _on_medkits(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var count := int(data.get("count", 0))
	if id == my_id:
		my_medkits = count
		if data.has("healed"):
			player.get("sound_fx").call("reload")
			_toast("VIDA +%d  (KITS: %d)" % [int(data["healed"]), count])
	elif actors.has(id):
		actors[id].set("medkits", count)

func _on_looted(data: Dictionary) -> void:
	var crate_id := str(data.get("crate", ""))
	var by := str(data.get("by", ""))
	var items: Dictionary = data.get("items", {})
	if crates.has(crate_id):
		crates[crate_id].call("mark_opened")
	if by == my_id:
		var picked: Array[String] = []
		for weapon_id in items:
			player.call("give_weapon", weapon_id, int(items[weapon_id]))
			picked.append("%s +%d" % [WeaponData.stats(weapon_id)["name"], int(items[weapon_id])])
		if int(data.get("kits", 0)) > 0:
			picked.append("KIT MÉDICO +%d (F usar)" % int(data["kits"]))
		if int(data.get("nades", 0)) > 0:
			picked.append("GRANADA +%d (G lançar)" % int(data["nades"]))
		player.get("sound_fx").call("reload")
		_toast("PEGOU " + ", ".join(picked))
	elif actors.has(by):
		for weapon_id in items:
			actors[by].call("give_weapon", weapon_id)
	elif crate_id == _pending_loot:
		_toast("Alguém pegou primeiro")
	if crate_id == _pending_loot:
		_pending_loot = ""

func _update_loot_ui() -> void:
	var nearest := _closest_crate(LOOT_REACH) if not local_dead and not finished else null
	for crate in crates.values():
		var distance: float = crate.global_position.distance_to(player.global_position)
		crate.call("show_label", distance < LABEL_RANGE and not local_dead)
	if nearest != null:
		loot_prompt.text = "[E] Coletar: " + str(nearest.call("contents_text")).replace("\n", " — ")
		loot_prompt.visible = true
	else:
		loot_prompt.visible = false

func _vec(value) -> Variant:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return null

func _on_health(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var hp := float(data.get("hp", 0))
	var killed := bool(data.get("killed", false))
	var by := str(data.get("by", ""))
	alive_count = int(data.get("alive", alive_count))
	if killed and names.has(by) and by != id:
		kill_counts[by] = int(data.get("kills", int(kill_counts.get(by, 0)) + 1))
	if killed:
		if by == "saiu":
			left_ids[id] = true
		else:
			deaths[id] = int(data.get("deaths", int(deaths.get(id, 0)) + 1))
	if id == my_id:
		if hp < my_hp:
			_on_local_damaged(my_hp - hp, by)
		my_hp = hp
		if killed:
			if data.has("respawn"):
				respawn_left = float(data["respawn"]) / 1000.0
			_on_local_death(by)
	elif actors.has(id):
		actors[id].call("set_hp", hp, killed)
		if killed:
			_on_watched_killed(id, by)
	if by == my_id and killed and id != my_id:
		my_kills = int(data.get("kills", my_kills + 1))
		combat_feedback.call("show_hit", false, true)
		player.get("sound_fx").call("kill_confirm")
		_toast("ELIMINOU %s" % str(names.get(id, "")).to_upper())
	if killed:
		var killer: String = names.get(by, "") if by != "saiu" else ""
		var victim: String = names.get(id, "?")
		if by == "saiu":
			_feed("%s desconectou." % victim)
		else:
			var weapon := str(data.get("w", ""))
			var weapon_name := str(WeaponData.stats(weapon)["name"]) if not weapon.is_empty() else "BOT"
			if weapon == "grenade":
				weapon_name = "GRANADA"
			var head_tag := "  (CABEÇA)" if str(data.get("zone", "")) == "head" else ""
			_feed("%s  [%s]  %s%s" % [killer, weapon_name, victim, head_tag])

func _on_actor_damaged(actor_id: String, zone: String, point: Vector3, normal: Vector3, weapon: String) -> void:
	if local_dead or finished:
		return
	if is_ally(actor_id):
		return # no friendly fire (the server ignores it too)
	if weapon.is_empty():
		weapon = str(player.get("current_weapon"))
	var base := float(WeaponData.stats(weapon)["damage"])
	var damage := base * float(HitboxScript.MULTIPLIER.get(zone, 1.0))
	# pt = onde a bala bateu (o servidor confere se a cabeça estava ali).
	var hit := {"t": "hit", "target": actor_id, "zone": zone, "dmg": damage, "w": weapon, "pt": [point.x, point.y, point.z]}
	if weapon == "bow":
		var bow: Node = player.get("bow_controller")
		if not is_instance_valid(bow):
			return
		hit["a"] = str(bow.get("last_hit_arrow_id"))
		if str(hit["a"]).is_empty():
			return
	Net.send(hit)
	# Immediate feedback (the server confirms health a moment later).
	var headshot := zone == "head"
	combat_feedback.call("show_hit", headshot)
	player.get("sound_fx").call("hit_confirm", headshot)
	_blood_burst(point, normal, headshot)
	_damage_number(point, damage, headshot)

func _on_local_damaged(amount: float, attacker_id: String) -> void:
	damage_flash.color.a = clampf(0.18 + amount / 60.0, 0.2, 0.55)
	player.call("add_hit_shake", clampf(amount / 25.0, 0.25, 1.0))
	player.get("sound_fx").call("hurt", amount)
	# Heavy blows make the body recoil (upper body only; legs keep their stride).
	var body = player.get("humanoid_avatar")
	if amount >= 20.0 and body != null and body.has_method("play_action"):
		body.call("play_action", "hit")
	var attacker = actors.get(attacker_id)
	if attacker != null:
		var camera := get_viewport().get_camera_3d()
		var forward := -camera.global_basis.z
		forward.y = 0.0
		var right := camera.global_basis.x
		right.y = 0.0
		var to: Vector3 = attacker.global_position - player.global_position
		to.y = 0.0
		combat_feedback.call("show_damage_from", atan2(to.dot(right.normalized()), to.dot(forward.normalized())))

## Soco (sem arma branca nas partidas): acerta quem está logo à frente; o
## servidor confere a distância e aplica o dano.
const PUNCH_REACH := 2.2
const PUNCH_COOLDOWN := 0.55
var _punch_timer := 0.0

func _punch() -> void:
	if local_dead or finished:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _punch_timer:
		return
	_punch_timer = now + PUNCH_COOLDOWN
	player.get("sound_fx").call("melee_swing")
	# Sem mira: o alcance do soco a partir do corpo, para a frente do personagem.
	var hit := Melee.sweep(player, PUNCH_REACH)
	if hit.is_empty():
		return
	var body: Object = hit["collider"]
	var target = body.get("actor") if body != null else null
	if target == null or target.get("actor_id") == null:
		return
	var target_id := str(target.get("actor_id"))
	if target_id == my_id or bool(target.get("dead")) or is_ally(target_id):
		return
	var zone := str(body.get("zone")) if body.get("zone") != null else "chest"
	Net.send({"t": "melee", "target": target_id, "zone": zone})
	combat_feedback.call("show_hit", zone == "head")
	player.get("sound_fx").call("melee_impact", zone == "head")
	_blood_burst(hit["position"], hit["normal"], zone == "head")

# Gota de sangue e traçante: um mesh/material só, reaproveitado em todo tiro
# (antes cada acerto criava recursos novos — custo e travadas no celular).
static var _shared_blood_drop: SphereMesh
static var _shared_tracer_mesh: CylinderMesh
static var _shared_tracer_material: StandardMaterial3D

static func _blood_drop_mesh() -> SphereMesh:
	if _shared_blood_drop == null:
		var drop := SphereMesh.new()
		drop.radius = 0.022
		drop.height = 0.044
		drop.radial_segments = 6
		drop.rings = 3
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#7a0b0b")
		material.roughness = 0.4
		drop.material = material
		_shared_blood_drop = drop
	return _shared_blood_drop

## Cilindro de 1 m de altura: cada traçante estica no eixo Y até o comprimento.
static func _tracer_resources() -> void:
	if _shared_tracer_mesh != null:
		return
	_shared_tracer_mesh = CylinderMesh.new()
	_shared_tracer_mesh.top_radius = 0.012
	_shared_tracer_mesh.bottom_radius = 0.012
	_shared_tracer_mesh.height = 1.0
	_shared_tracer_mesh.radial_segments = 5
	_shared_tracer_material = StandardMaterial3D.new()
	_shared_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_tracer_material.albedo_color = Color("#ffd08c")

func _blood_burst(point: Vector3, normal: Vector3, headshot: bool) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.amount = 22 if headshot else 12
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	particles.spread = 38.0
	particles.initial_velocity_min = 1.2
	particles.initial_velocity_max = 3.4 if headshot else 2.4
	particles.gravity = Vector3(0, -9.0, 0)
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.2
	particles.mesh = _blood_drop_mesh()
	main_node.add_child(particles)
	particles.global_position = point
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)

func _damage_number(point: Vector3, damage: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = ("%d" % roundi(damage)) + ("!" if headshot else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 64 if headshot else 46
	label.outline_size = 12
	label.modulate = Color("#ff4d3d") if headshot else Color("#ffe08a")
	main_node.add_child(label)
	label.global_position = point + Vector3(randf_range(-0.15, 0.15), 0.2, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.7, 0), 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)

func _xp_toast(text: String, loss: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("#ff6a55") if loss else Color("#ffd24a")) # perda em vermelho
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 2)
	xp_feed.add_child(label)
	var tween := label.create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)

func _toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#ff6a55"))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -260
	label.offset_right = 260
	label.offset_top = 48
	label.offset_bottom = 80
	var tween := label.create_tween()
	tween.tween_interval(1.1)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func _on_local_shot(weapon_id: String, from: Vector3, to: Vector3) -> void:
	var shot := {"t": "shot", "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]}
	if weapon_id == "bow":
		var bow: Node = player.get("bow_controller")
		if not is_instance_valid(bow):
			return
		var speed := to - from
		shot["v"] = [speed.x, speed.y, speed.z]
		shot["a"] = str(bow.get("last_arrow_id"))
		if str(shot["a"]).is_empty():
			return
	Net.send(shot)

func _on_bot_fired(actor_id: String, weapon_id: String, from: Vector3, to: Vector3) -> void:
	_tracer(from, to)
	Net.send({"t": "shot", "bot": actor_id, "w": weapon_id, "o": [from.x, from.y, from.z], "e": [to.x, to.y, to.z]})

func _on_bot_hit(actor_id: String, target_id: String, zone: String) -> void:
	var bot = actors.get(actor_id)
	var weapon: String = bot.weapon_id if bot != null else "rifle"
	Net.send({"t": "hit", "bot": actor_id, "target": target_id, "zone": zone, "w": weapon})

func _on_connection_lost(reason: String) -> void:
	if finished:
		return
	finished = true
	_show_center("CONEXÃO PERDIDA", reason)

# ------------------------------------------------------- death / ending ---

## "jogador • Cabo" or "bot", for the killer banner and spectator label.
func _describe(id: String) -> String:
	var side := ""
	if team_mode:
		side = ("aliado" if is_ally(id) else "inimigo") + "  •  "
	if bots.get(id, false):
		return side + "bot"
	var rank: String = ranks.get(id, "")
	return side + "jogador" + ("  •  " + rank if not rank.is_empty() else "")

func _on_local_death(killer_id: String) -> void:
	if local_dead:
		return
	local_dead = true
	player.call("cancel_channel")
	player.call("cancel_grenade_aim")
	player.set("aiming", false)
	Input.action_release("aim")
	Input.action_release("fire")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.collision_layer = 0
	(player.get("avatar") as Node3D).visible = false
	var viewmodel := player.get("viewmodel") as Node3D
	if viewmodel != null:
		viewmodel.visible = false
	spectate_camera = Camera3D.new()
	spectate_camera.fov = 72
	add_child(spectate_camera)
	spectate_camera.current = true
	# Watch whoever eliminated us, if they are still standing.
	spectate_id = killer_id if actors.has(killer_id) and not actors[killer_id].dead else ""
	if killer_id == "saiu" or not names.has(killer_id):
		_killer_banner("VOCÊ FOI ELIMINADO", "")
	else:
		_killer_banner("ELIMINADO POR %s" % str(names[killer_id]).to_upper(), _describe(killer_id))
	if dm_mode:
		return # renasce em instantes (status mostra a contagem)
	_feed("Assistindo quem te eliminou. Clique para trocar de câmera  •  ESC: sair da partida.")

## Mata-mata: alguém renasceu (o servidor escolhe o lugar e dá a pistola).
func _on_respawn(data: Dictionary) -> void:
	var id := str(data.get("id", ""))
	var at = _vec(data.get("p"))
	if at == null:
		return
	var weapon := str(data.get("w", "pistol"))
	alive_count = int(data.get("alive", alive_count))
	if id == my_id:
		_revive_local(at, weapon, int(data.get("ammo", 90)), int(data.get("buy", 0)))
	elif actors.has(id):
		var actor = actors[id]
		actor.call("revive", at + Vector3(0, 0.1, 0), weapon)
		actor.set("medkits", int(data.get("medkits", 0)))
		actor.call("set_controlled", is_host() and actor.is_bot)

# --------------------------------------------------------------- rounds ---

func _read_rounds(info: Dictionary) -> void:
	round_number = int(info.get("round", round_number))
	round_total = int(info.get("total", round_total))
	round_to_win = int(info.get("toWin", round_to_win))
	var score = info.get("score")
	if score is Array and score.size() == 2:
		round_score = [int(score[0]), int(score[1])]

## "ALFA 1 x 0 BRAVO" (sempre Alfa à esquerda, igual para as duas equipes).
func _round_score_text() -> String:
	return "%s %d  x  %d %s" % [_team_name(0).to_upper(), int(round_score[0]), int(round_score[1]), _team_name(1).to_upper()]

func _clock_text() -> String:
	var left := maxi(0, int(ceil((match_ends_msec - Time.get_ticks_msec()) / 1000.0))) if match_ends_msec > 0 else 0
	return "%d:%02d" % [floori(left / 60.0), left % 60]

## Fim de um round: placar na tela e uma pausa curta (todos parados).
func _on_round_end(data: Dictionary) -> void:
	var score = data.get("score")
	if score is Array and score.size() == 2:
		round_score = [int(score[0]), int(score[1])]
	if bool(data.get("last", false)):
		return # o "end" chega em seguida, com a cena do vencedor e o placar final
	round_break = true
	_close_shop()
	killer_panel.visible = false
	Input.action_release("fire")
	Input.action_release("aim")
	if not local_dead:
		player.call("cancel_channel")
		player.call("cancel_grenade_aim")
		player.set("aiming", false)
		player.velocity = Vector3.ZERO
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var winner = data.get("team")
	var round_done := int(data.get("round", round_number))
	var why := "Tempo esgotado" if str(data.get("reason", "")) == "tempo" else ""
	round_history.append(-1 if winner == null else int(winner))
	_show_round_panel(round_done, winner, why, int(data.get("next", 5000)))
	_feed("Round %d: %s. Placar %s." % [round_done, "empate" if winner == null else "Equipe " + _team_name(int(winner)), _round_score_text()])
	player.get("sound_fx").call("kill_confirm" if winner != null and int(winner) == my_team else "reload")

## Novo round: todos de volta à base com vida cheia; quem sobreviveu segue armado.
func _on_round(data: Dictionary) -> void:
	_read_rounds(data)
	round_break = false
	center_panel.visible = false
	round_panel.visible = false
	alive_count = int(data.get("alive", alive_count))
	match_ends_msec = Time.get_ticks_msec() + int(data.get("duration", 150000))
	_apply_host()
	var buy_ms := int(data.get("buy", 0))
	for entry in data.get("roster", []):
		var id := str(entry.get("id", ""))
		var sp = entry.get("sp")
		if not (sp is Array and sp.size() == 2):
			continue
		var at := Vector3(float(sp[0]), 0, float(sp[1]))
		if id == my_id:
			_round_reset_local(at, buy_ms, int(entry.get("medkits", 0)), int(entry.get("nades", 0)))
		elif actors.has(id):
			var actor = actors[id]
			actor.call("revive", at + Vector3(0, 0.1, 0), str(entry.get("w", "")))
			actor.set("medkits", int(entry.get("medkits", 0)))
			actor.rotation.y = MatchLayout.spawn_yaw(at)
			actor.call("set_controlled", is_host() and actor.is_bot)
	_toast("ROUND %d" % round_number)
	_feed("Round %d de %d  ·  %s" % [round_number, round_total, _round_score_text()])

func _round_reset_local(at: Vector3, buy_ms: int, medkits: int, nades: int) -> void:
	if finished:
		return
	if local_dead:
		_revive_local(at, "", 0, buy_ms, "ROUND %d" % round_number)
	else:
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.global_position = at + Vector3(0, 0.1, 0)
		player.velocity = Vector3.ZERO
		var facing := MatchLayout.spawn_yaw(at)
		player.set("yaw", facing)
		player.rotation.y = facing
		my_hp = 100.0
		if not leave_panel.visible:
			PointerMode.capture()
		if shop != null and buy_ms > 0:
			buy_until_msec = Time.get_ticks_msec() + buy_ms
			_open_shop()
	my_medkits = medkits
	my_nades = nades

func _revive_local(at: Vector3, weapon: String, reserve: int, data_buy_ms: int = 0, banner: String = "DE VOLTA AO COMBATE") -> void:
	if not local_dead or finished:
		return
	local_dead = false
	respawn_left = 0.0
	my_hp = 100.0
	my_medkits = 0
	my_nades = 0
	_pending_loot = ""
	if spectate_camera != null:
		spectate_camera.queue_free()
		spectate_camera = null
	spectate_id = ""
	player.collision_layer = HitboxScript.LAYER_CHARACTERS
	player.global_position = at + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	var facing := MatchLayout.spawn_yaw(at)
	player.set("yaw", facing)
	player.rotation.y = facing
	(player.get("avatar") as Node3D).visible = true # the player re-decides avatar/viewmodel every frame
	player.process_mode = Node.PROCESS_MODE_INHERIT
	(player.get("camera") as Camera3D).current = true
	player.call("start_unarmed")
	if not weapon.is_empty():
		player.call("give_weapon", weapon, reserve)
	killer_panel.visible = false
	if not leave_panel.visible:
		PointerMode.capture()
	_toast(banner)
	if shop != null and data_buy_ms > 0:
		buy_until_msec = Time.get_ticks_msec() + data_buy_ms
		_open_shop()

func _killer_banner(title: String, subtitle: String) -> void:
	killer_title.text = title
	killer_subtitle.text = subtitle
	killer_panel.visible = true
	killer_panel.modulate.a = 1.0
	var tween := killer_panel.create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(killer_panel, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func(): killer_panel.visible = false)

## When the player we watch is eliminated, follow their killer (or anyone alive).
func _on_watched_killed(victim_id: String, killer_id: String) -> void:
	if not local_dead or victim_id != spectate_id:
		return
	if actors.has(killer_id) and not actors[killer_id].dead:
		spectate_id = killer_id
		_feed("%s foi eliminado. Assistindo %s (%s)." % [names.get(victim_id, "?"), names.get(killer_id, "?"), _describe(killer_id)])
	else:
		spectate_id = ""

func _process(delta: float) -> void:
	damage_flash.color.a = move_toward(damage_flash.color.a, 0.0, delta * 1.2)
	if _victory_target != null and victory_camera != null:
		_victory_time += delta
		_place_victory_camera(delta)
		if not _victory_finished and _victory_time >= VICTORY_SECONDS:
			_finish_victory()
	_update_loot_ui()
	if round_panel.visible:
		_tick_round_panel()
	if score_panel.visible:
		_score_refresh -= delta
		if finished:
			score_panel.visible = false
		elif _score_refresh <= 0.0:
			_refresh_scoreboard()
	if shop != null and shop.visible:
		if can_shop():
			_refresh_shop() # relógio da loja
		else:
			_close_shop() # acabou o tempo (ou morreu / fim da partida)
	if local_dead and dm_mode:
		respawn_left = maxf(0.0, respawn_left - delta)
	if finished:
		status_label.text = ""
	elif dm_mode:
		status_label.text = _dm_status()
	elif local_dead:
		var target := _spectate_target()
		var watched := "—"
		if target != null:
			var id: String = target.get("actor_id")
			watched = "%s (%s)" % [names.get(id, "?"), _describe(id)]
		if team_mode:
			var sides := _team_alive()
			status_label.text = "ROUND %d/%d  •  %s\nELIMINADO  |  ALIADOS: %d  x  INIMIGOS: %d  |  ASSISTINDO: %s" % [round_number, round_total, _round_score_text(), sides[0], sides[1], watched]
		else:
			status_label.text = "ELIMINADO  |  VIVOS: %d  |  ASSISTINDO: %s" % [alive_count, watched]
	elif team_mode:
		var sides := _team_alive()
		var clock := "PAUSA" if round_break else _clock_text()
		status_label.text = "ROUND %d/%d  •  %s  •  %s\n%s  %d  x  %d  •  ABATES %d" % [round_number, round_total, _round_score_text(), clock, _team_name(my_team).to_upper(), sides[0], sides[1], my_kills]
	else:
		status_label.text = "VIVOS %d  •  ABATES %d" % [alive_count, my_kills]
	health_bar.value = my_hp
	health_bar.visible = not local_dead and not finished
	if local_dead and spectate_camera != null:
		var target := _spectate_target()
		if target != null:
			var back := target.global_basis.z.normalized()
			var goal: Vector3 = target.global_position + back * 3.6 + Vector3(0, 2.4, 0)
			spectate_camera.global_position = spectate_camera.global_position.lerp(goal, minf(1.0, delta * 5.0))
			spectate_camera.look_at(target.global_position + Vector3(0, 1.4, 0))

## Mata-mata HUD line: your kills / goal, the leader and the clock (or the respawn countdown).
func _dm_status() -> String:
	var leader := ""
	var best := 0
	for id in kill_counts:
		if int(kill_counts[id]) > best:
			best = int(kill_counts[id])
			leader = id
	var left := maxi(0, int(ceil((match_ends_msec - Time.get_ticks_msec()) / 1000.0))) if match_ends_msec > 0 else 0
	var clock := "%d:%02d" % [floori(left / 60.0), left % 60]
	var lead := "LÍDER: VOCÊ" if leader == my_id else ("LÍDER: %s %d" % [str(names.get(leader, "")).to_upper(), best] if not leader.is_empty() else "LÍDER: —")
	var mine := int(kill_counts.get(my_id, my_kills))
	if local_dead:
		return "RENASCENDO EM %d…  |  ABATES %d/%d  •  %s  •  %s" % [int(ceil(respawn_left)), mine, kill_goal, lead, clock]
	return "ABATES %d/%d  •  %s  •  %s" % [mine, kill_goal, lead, clock]

## Who an eliminated player can watch. In team matches, teammates come first.
func _living_ids() -> Array:
	var ids: Array = []
	var allies: Array = []
	for id in actors:
		if not actors[id].dead:
			ids.append(id)
			if is_ally(id):
				allies.append(id)
	if not allies.is_empty():
		ids = allies
	ids.sort()
	return ids

func _spectate_target() -> Node3D:
	if actors.has(spectate_id) and not actors[spectate_id].dead:
		return actors[spectate_id]
	var ids := _living_ids()
	if ids.is_empty():
		return null
	spectate_id = ids[0]
	return actors[spectate_id]

## TAB (segurar): placar da partida. Em _input para o foco da GUI não engolir a tecla.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_TAB and not event.echo:
		var open_board: bool = event.pressed and not finished
		if open_board:
			_refresh_scoreboard()
		score_panel.visible = open_board
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# Cena do vencedor: qualquer tecla/clique pula para o placar (depois de 1 s).
	if _victory_target != null and not _victory_finished and _victory_time > 1.0 and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_finish_victory()
		get_viewport().set_input_as_handled()
		return
	# B: loja (só na janela de compra). Esc fecha a loja antes de abrir "sair".
	if event is InputEventKey and event.pressed and not event.echo and shop != null and not finished and not leave_panel.visible:
		if event.physical_keycode == KEY_B or (event.keycode == KEY_ESCAPE and shop.visible):
			if shop.visible:
				_close_shop()
			elif event.physical_keycode == KEY_B:
				_open_shop()
			get_viewport().set_input_as_handled()
			return
	# Esc: leave the match at any time (alive or spectating). The player node
	# is disabled after death, so its own Esc handler no longer runs.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not finished:
		if leave_panel.visible:
			_close_leave_panel()
		else:
			_open_leave_panel()
		get_viewport().set_input_as_handled()
		return
	if leave_panel.visible:
		# Clicks outside the panel must not recapture the mouse or fire.
		if event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	if local_dead and not finished and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ids := _living_ids()
		if not ids.is_empty():
			spectate_id = ids[(ids.find(spectate_id) + 1) % ids.size()]

func _on_xp(data: Dictionary) -> void:
	var amount := int(data.get("amount", 0))
	match_xp = int(data.get("total", match_xp + amount))
	var reasons := {"kill_player": "abate de jogador", "kill_bot": "abate de bot", "headshot": "na cabeça", "win": "vitória", "match": "partida", "death": "você morreu", "quit": "saiu da partida"}
	var reason := str(data.get("reason", ""))
	var text := "%+d XP  %s" % [amount, reasons.get(reason, "")]
	var victim := str(data.get("victim", ""))
	if not victim.is_empty() and reason != "headshot":
		text += (" (por %s)" if reason == "death" else " (%s)") % victim
	_xp_toast(text, amount < 0)

func _on_profile(data: Dictionary) -> void:
	var profile: Dictionary = data.get("profile", {})
	var lines := "\nXP da partida: %+d   •   Total: %d XP\nPatente: %s" % [int(data.get("gained", 0)), int(profile.get("xp", 0)), profile.get("rank", "")]
	if profile.get("nextRankXp") != null:
		lines += "   (faltam %d XP para %s)" % [int(profile["nextRankXp"]) - int(profile.get("xp", 0)), profile.get("nextRank", "")]
	if bool(data.get("rankUp", false)):
		lines += "\nPROMOVIDO A %s!" % str(profile.get("rank", "")).to_upper()
		player.get("sound_fx").call("kill_confirm")
	elif bool(data.get("rankDown", false)):
		lines += "\nRebaixado para %s." % str(profile.get("rank", ""))
	center_body.text += lines
	_fill_results_profile(data) # placar novo (ou guarda até ele aparecer, depois da cena)

func _on_end(data: Dictionary) -> void:
	finished = true
	killer_panel.visible = false
	round_panel.visible = false
	score_panel.visible = false
	Input.action_release("fire")
	PointerMode.release()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	if team_mode:
		_on_team_end(data)
		return
	var won := str(data.get("winner", "")) == my_id
	var title := "VITÓRIA!" if won else "%s VENCEU" % str(data.get("name", "")).to_upper()
	var winner_id := str(data.get("winner", ""))
	var winner_name := str(data.get("name", names.get(winner_id, "")))
	var reason := "Tempo esgotado: venceu quem tinha mais abates." if str(data.get("reason", "")) == "tempo" else ("Você foi o último de pé." if won else "%s foi o último de pé." % winner_name)
	if str(data.get("reason", "")) == "abates":
		var goal := int(data.get("goal", kill_goal))
		reason = ("Você chegou a %d abates primeiro." % goal) if won else ("%s chegou a %d abates primeiro." % [winner_name, goal])
	_play_victory(_node_for(winner_id), "VOCÊ VENCEU!" if won else "VENCEDOR", winner_name, _winner_line(data, winner_id), ACCENT_GOLD,
		func(): _show_results(data, title, reason, "win" if won else "lose"))

## Team scoreboard: one block per team with each member's kills.
func _on_team_end(data: Dictionary) -> void:
	var winner = data.get("team")
	var title := "EMPATE"
	if winner != null:
		title = "VITÓRIA DA EQUIPE!" if int(winner) == my_team else "DERROTA — EQUIPE %s VENCEU" % _team_name(int(winner)).to_upper()
	var outcome := "draw" if winner == null else ("win" if int(winner) == my_team else "lose")
	var reason := "Tempo esgotado: venceu a equipe com mais abates." if str(data.get("reason", "")) == "tempo" else ("Ninguém venceu." if winner == null else "A equipe %s eliminou a outra." % _team_name(int(winner)))
	var rounds = data.get("rounds")
	if rounds is Array and rounds.size() == 2:
		round_score = [int(rounds[0]), int(rounds[1])]
		reason = "Placar de rounds: %s  ·  %d rounds jogados." % [_round_score_text(), int(data.get("round", round_number))]
		if winner == null:
			reason = "Empate nos rounds e nos abates: %s." % _round_score_text()
	if str(data.get("reason", "")) == "wo" and winner != null:
		reason = "W.O.: a equipe %s ficou sem ninguém na partida  ·  rounds %s." % [_team_name(1 - int(winner)), _round_score_text()]
	var show_board := func():
		_show_results(data, title, reason, outcome)
		if not Net.party_code.is_empty():
			room_button.visible = true
			room_button.text = "Voltar para a sala %s" % Net.party_code
			room_button.grab_focus()
	if winner == null:
		show_board.call() # empate: sem cena de vencedor
		return
	# Cena: o melhor da equipe vencedora (mais abates), preferindo quem está de pé.
	var mvp := ""
	var mvp_kills := -1
	for row in data.get("board", []):
		if int(row.get("team", -1)) != int(winner):
			continue
		var id := str(row.get("id", ""))
		var node := _node_for(id)
		var standing := node != null and (not local_dead if id == my_id else not bool(node.get("dead")))
		var kills := int(row.get("kills", 0)) + (1000 if standing else 0)
		if kills > mvp_kills:
			mvp_kills = kills
			mvp = id
	var team_color := Color("#5ea8d0") if int(winner) == 0 else Color("#d07a5e")
	var kicker := ("SUA EQUIPE VENCEU!" if int(winner) == my_team else "EQUIPE %s VENCEU" % _team_name(int(winner)).to_upper())
	_play_victory(_node_for(mvp), kicker, str(names.get(mvp, "")), "Destaque da equipe  ·  " + _winner_line(data, mvp), team_color.lightened(0.25), show_board)

# ------------------------------------------------------------ cena do vencedor ---

const ACCENT_GOLD := Color("#ffc94a")
const VICTORY_SECONDS := 5.5
var victory_camera: Camera3D
var victory_layer: Control
var _victory_target: Node3D
var _victory_time := 0.0
var _victory_angle := 0.0
var _victory_done: Callable
var _victory_finished := false

## Nó do jogador/bot pelo id (o próprio jogador local ou um ator da partida).
func _node_for(id: String) -> Node3D:
	if id.is_empty():
		return null
	if id == my_id:
		return player
	return actors.get(id)

## Esconde o HUD do jogo (minimapa, botão de menu, mensagens) durante a cena.
func _set_cinematic(on: bool) -> void:
	var main := get_parent()
	if main != null and "cinematic" in main:
		main.set("cinematic", on)
	if feed != null:
		feed.visible = not on

## "7 abates  ·  Sargento" (ou "bot") do placar final.
func _winner_line(data: Dictionary, id: String) -> String:
	for row in data.get("board", []):
		if str(row.get("id", "")) == id:
			var kills := int(row.get("kills", 0))
			var who := "bot" if row.get("bot", false) else str(row.get("rank", ""))
			return "%d abate%s  ·  %s" % [kills, "" if kills == 1 else "s", who]
	return ""

## Mini-cena de fim de partida: câmera de cinema girando em volta do vencedor,
## faixas pretas, o nome dele grande com uma linha dourada, confete e fanfarra.
## Depois de VICTORY_SECONDS (ou qualquer tecla após 1 s) chama `done` (o placar)
## e a câmera continua girando devagar ao fundo.
func _play_victory(target: Node3D, kicker: String, headline: String, subtitle: String, color: Color, done: Callable) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		done.call()
		return
	_victory_target = target
	_victory_done = done
	_victory_time = 0.0
	_victory_finished = false
	killer_panel.visible = false
	_set_cinematic(true)
	victory_camera = Camera3D.new()
	victory_camera.name = "VictoryCamera"
	victory_camera.fov = 48.0
	add_child(victory_camera)
	var front := -target.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length_squared() > 0.001 else Vector3.FORWARD
	_victory_angle = atan2(front.x, front.z) - 0.6 # começa de frente, um pouco de lado
	_place_victory_camera(0.0)
	victory_camera.current = true
	_build_victory_overlay(kicker, headline, subtitle, color)
	_victory_confetti(target.global_position + Vector3(0, 3.2, 0))
	var fanfare := AudioStreamPlayer.new()
	fanfare.stream = SfxBank.victory()
	fanfare.volume_db = -4.0
	add_child(fanfare)
	fanfare.play()

func _place_victory_camera(delta: float) -> void:
	if victory_camera == null or not is_instance_valid(_victory_target):
		return
	var speed := 0.42 if not _victory_finished else 0.12 # depois do placar, gira bem devagar
	_victory_angle += delta * speed
	var k := smoothstep(0.0, VICTORY_SECONDS, _victory_time)
	var radius := lerpf(5.6, 3.6, k)
	var center := _victory_target.global_position
	var goal := center + Vector3(sin(_victory_angle) * radius, 1.45 + 0.35 * (1.0 - k), cos(_victory_angle) * radius)
	victory_camera.global_position = goal if delta == 0.0 else victory_camera.global_position.lerp(goal, 1.0 - exp(-6.0 * delta))
	victory_camera.look_at(center + Vector3(0, 1.25, 0))

func _build_victory_overlay(kicker: String, headline: String, subtitle: String, color: Color) -> void:
	victory_layer = Control.new()
	victory_layer.name = "VictoryOverlay"
	victory_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(victory_layer)
	victory_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Faixas de cinema (descem/sobem).
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		victory_layer.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.custom_minimum_size.y = 0.0
		bar.offset_bottom = 0.0 if top else 0.0
		var height := 86.0
		var tween := bar.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if top:
			bar.offset_bottom = 0.0
			tween.tween_property(bar, "offset_bottom", height, 0.6)
		else:
			bar.offset_top = 0.0
			tween.tween_property(bar, "offset_top", -height, 0.6)
	# Bloco do nome, no terço de baixo da tela.
	var block := VBoxContainer.new()
	block.name = "VictoryBlock"
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_theme_constant_override("separation", 6)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory_layer.add_child(block)
	block.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	block.grow_horizontal = Control.GROW_DIRECTION_BOTH
	block.grow_vertical = Control.GROW_DIRECTION_BEGIN
	block.offset_bottom = -120.0
	var kicker_label := _victory_label(kicker, 20, color)
	kicker_label.name = "VictoryKicker"
	block.add_child(kicker_label)
	var name_label := _victory_label(headline.to_upper(), 76, Color.WHITE)
	name_label.name = "VictoryName"
	name_label.add_theme_constant_override("outline_size", 10)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	block.add_child(name_label)
	var line_holder := CenterContainer.new()
	line_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(line_holder)
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(0, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_holder.add_child(line)
	var sub_label := _victory_label(subtitle, 20, Color(0.92, 0.94, 0.9, 0.9))
	sub_label.name = "VictorySubtitle"
	block.add_child(sub_label)
	var skip := _victory_label("qualquer tecla para pular", 12, Color(1, 1, 1, 0.35))
	block.add_child(skip)
	# Entrada: título, nome (encolhendo de 1,25× para 1×), linha abrindo, subtítulo.
	for node in [kicker_label, name_label, sub_label, skip]:
		node.modulate.a = 0.0
	var t := victory_layer.create_tween()
	t.tween_interval(0.35)
	t.tween_property(kicker_label, "modulate:a", 1.0, 0.35)
	t.tween_callback(func():
		name_label.pivot_offset = name_label.size * 0.5
		name_label.scale = Vector2(1.25, 1.25))
	t.parallel().tween_property(name_label, "modulate:a", 1.0, 0.45)
	t.parallel().tween_property(name_label, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(line, "custom_minimum_size:x", 440.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(sub_label, "modulate:a", 1.0, 0.4)
	t.tween_property(skip, "modulate:a", 1.0, 0.6)

func _victory_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Confete dourado/laranja/branco caindo sobre o vencedor.
func _victory_confetti(at: Vector3) -> void:
	var confetti := CPUParticles3D.new()
	confetti.name = "VictoryConfetti"
	confetti.amount = 180
	confetti.lifetime = 4.5
	confetti.one_shot = true
	confetti.explosiveness = 0.85
	confetti.direction = Vector3.UP
	confetti.spread = 70.0
	confetti.initial_velocity_min = 3.5
	confetti.initial_velocity_max = 7.0
	confetti.gravity = Vector3(0, -4.5, 0)
	confetti.damping_min = 1.5
	confetti.damping_max = 3.0
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = 0.6
	confetti.scale_amount_max = 1.2
	var piece := QuadMesh.new()
	piece.size = Vector2(0.09, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	piece.material = material
	confetti.mesh = piece
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	colors.colors = PackedColorArray([Color("#ffc94a"), Color("#f0a23b"), Color("#ffffff"), Color("#e8622c")])
	confetti.color_initial_ramp = colors
	add_child(confetti)
	confetti.global_position = at
	confetti.emitting = true
	get_tree().create_timer(6.0).timeout.connect(confetti.queue_free)

## Fim da cena: o nome some, entra o placar; a câmera segue girando devagar.
func _finish_victory() -> void:
	if _victory_finished:
		return
	_victory_finished = true
	_set_cinematic(false)
	if victory_layer != null and is_instance_valid(victory_layer):
		var layer := victory_layer
		var t := layer.create_tween()
		t.tween_property(layer, "modulate:a", 0.0, 0.45)
		t.tween_callback(layer.queue_free)
	if _victory_done.is_valid():
		_victory_done.call()


# -------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	damage_flash = ColorRect.new()
	damage_flash.color = Color(0.75, 0.05, 0.05, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(damage_flash)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	combat_feedback = CombatFeedbackScript.new()
	ui.add_child(combat_feedback)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(status_label)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status_label.offset_left = -300
	status_label.offset_right = 300
	status_label.offset_top = 14
	health_bar = ProgressBar.new()
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(260, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#c7e08c")
	fill.set_corner_radius_all(4)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	back.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_bar.add_theme_stylebox_override("background", back)
	ui.add_child(health_bar)
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	health_bar.offset_left = -130
	health_bar.offset_right = 130
	health_bar.offset_top = -46
	health_bar.offset_bottom = -28
	# "ELIMINADO POR ..." banner shown when the local player dies.
	killer_panel = PanelContainer.new()
	killer_panel.visible = false
	killer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var killer_box := StyleBoxFlat.new()
	killer_box.bg_color = Color(0.35, 0.04, 0.03, 0.82)
	killer_box.set_corner_radius_all(10)
	killer_box.content_margin_left = 28
	killer_box.content_margin_right = 28
	killer_box.content_margin_top = 12
	killer_box.content_margin_bottom = 12
	killer_panel.add_theme_stylebox_override("panel", killer_box)
	ui.add_child(killer_panel)
	killer_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	killer_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	killer_panel.offset_top = 70
	var killer_column := VBoxContainer.new()
	killer_panel.add_child(killer_column)
	killer_title = Label.new()
	killer_title.add_theme_font_size_override("font_size", 30)
	killer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killer_column.add_child(killer_title)
	killer_subtitle = Label.new()
	killer_subtitle.add_theme_font_size_override("font_size", 17)
	killer_subtitle.add_theme_color_override("font_color", Color("#ffd0c4"))
	killer_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killer_column.add_child(killer_subtitle)
	# XP gains stack on the right side.
	xp_feed = VBoxContainer.new()
	xp_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(xp_feed)
	xp_feed.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	xp_feed.offset_left = -560
	xp_feed.offset_right = -40
	xp_feed.offset_top = -60
	xp_feed.offset_bottom = 120
	loot_prompt = Label.new()
	loot_prompt.visible = false
	loot_prompt.add_theme_font_size_override("font_size", 19)
	loot_prompt.add_theme_color_override("font_color", Color("#ffe08a"))
	loot_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	loot_prompt.add_theme_constant_override("shadow_offset_y", 2)
	loot_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(loot_prompt)
	loot_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loot_prompt.offset_left = -320
	loot_prompt.offset_right = 320
	loot_prompt.offset_top = 90
	loot_prompt.offset_bottom = 120
	feed = VBoxContainer.new()
	feed.alignment = BoxContainer.ALIGNMENT_END
	ui.add_child(feed)
	feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	feed.offset_left = 18
	feed.offset_right = 560
	feed.offset_top = -240
	feed.offset_bottom = -18
	center_panel = PanelContainer.new()
	center_panel.visible = false
	center_panel.add_theme_stylebox_override("panel", UiTheme.card(30))
	ui.add_child(center_panel)
	center_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	center_panel.add_child(column)
	center_title = Label.new()
	center_title.add_theme_font_override("font", UiTheme.font(700))
	center_title.add_theme_font_size_override("font_size", 34)
	center_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(center_title)
	center_body = Label.new()
	center_body.add_theme_font_size_override("font_size", 17)
	column.add_child(center_body)
	var back_button := Button.new()
	back_button.text = "Voltar ao menu"
	back_button.custom_minimum_size = Vector2(220, 46)
	UiTheme.primary(back_button, 16).focus_mode = Control.FOCUS_ALL
	back_button.pressed.connect(_back_to_menu)
	column.add_child(back_button)
	# Custom rooms survive the match: back to the same lobby and code.
	room_button = Button.new()
	room_button.name = "BackToRoomButton"
	room_button.text = "Voltar para a sala"
	room_button.custom_minimum_size = Vector2(220, 46)
	UiTheme.secondary(room_button, 15).focus_mode = Control.FOCUS_ALL
	room_button.visible = false
	room_button.pressed.connect(_back_to_room)
	column.add_child(room_button)
	column.move_child(room_button, back_button.get_index())
	_build_leave_panel()
	_build_round_panel()
	score_panel = PanelContainer.new()
	score_panel.name = "ScorePanel"
	score_panel.visible = false
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score_box := _res_box(Color(0.035, 0.05, 0.06, 0.95), Color(1, 1, 1, 0.09), 0, 4)
	score_box.border_width_top = 3
	score_box.shadow_color = Color(0, 0, 0, 0.5)
	score_box.shadow_size = 18
	score_box.border_color = MENU_ACCENT
	for side in ["left", "right"]:
		score_box.set("content_margin_" + side, 22)
	score_box.content_margin_top = 16
	score_box.content_margin_bottom = 14
	score_panel.add_theme_stylebox_override("panel", score_box)
	score_panel.custom_minimum_size.x = 560
	ui.add_child(score_panel)
	score_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

# ------------------------------------------------ fim de round (tema do menu) ---

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const MENU_ACCENT := Color("#f0a23b")
const MENU_HOT := Color("#e0705e")
const TEAM_TINTS := [Color("#5ea8d0"), Color("#d07a5e")]

## Painel do intervalo entre rounds: resultado grande, placar Alfa x Bravo,
## marcadores dos 5 rounds, contagem regressiva e um botão pequeno de menu.
func _build_round_panel() -> void:
	round_panel = PanelContainer.new()
	round_panel.name = "RoundPanel"
	round_panel.visible = false
	round_panel.custom_minimum_size.x = 440
	ui.add_child(round_panel)
	round_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	round_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	round_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	round_panel.offset_top = -40 # um pouco acima do centro: o aviso "ROUND N" fica livre embaixo
	round_panel.offset_bottom = -40

func _show_round_panel(round_done: int, winner, why: String, next_ms: int) -> void:
	center_panel.visible = false
	for child in round_panel.get_children():
		child.queue_free()
	var outcome := "draw" if winner == null else ("win" if int(winner) == my_team else "lose")
	var accent: Color = MENU_ACCENT if outcome == "win" else (MENU_HOT if outcome == "lose" else RES_MUTED)
	var box := _res_box(Color(0.035, 0.05, 0.06, 0.94), accent, 0, 4)
	box.border_width_top = 3
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 18
	for side in ["left", "right"]:
		box.set("content_margin_" + side, 26)
	box.content_margin_top = 18
	box.content_margin_bottom = 14
	round_panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	round_panel.add_child(column)
	var kicker := _res_label("ROUND %d DE %d  ·  MELHOR DE %d" % [round_done, round_total, round_total], 11, accent, true)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)
	var headline := {"win": "VITÓRIA", "lose": "DERROTA", "draw": "EMPATE"}[outcome] as String
	var title := _res_label(headline, 44, RES_TEXT, true)
	title.name = "RoundTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var line := "Sua equipe venceu o round" if outcome == "win" else ("Equipe %s venceu o round" % _team_name(int(winner)) if outcome == "lose" else "Ninguém levou o round")
	if not why.is_empty():
		line += "  ·  " + why
	var sub := _res_label(line, 13, RES_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	# Placar: ALFA  1 — 1  BRAVO (a sua equipe marcada).
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 14)
	column.add_child(score_row)
	for team in [0, 1]:
		var tag := _team_name(team).to_upper() + ("  (VOCÊ)" if team == my_team else "")
		var name_label := _res_label(tag, 13, TEAM_TINTS[team].lightened(0.25), true)
		name_label.custom_minimum_size.x = 120
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if team == 0 else HORIZONTAL_ALIGNMENT_LEFT
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var number := _res_label(str(int(round_score[team])), 38, RES_TEXT, true)
		if team == 0:
			score_row.add_child(name_label)
			score_row.add_child(number)
			score_row.add_child(_res_label("—", 24, RES_DIM, true))
		else:
			score_row.add_child(number)
			score_row.add_child(name_label)
	# Marcadores dos rounds: cor da equipe que venceu, cinza = empate, apagado = a jogar.
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 6)
	column.add_child(pips)
	for i in round_total:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(34, 6)
		var color := Color(1, 1, 1, 0.08)
		if i < round_history.size():
			var who := int(round_history[i])
			color = TEAM_TINTS[who] if who >= 0 else RES_MUTED
		var pip_box := _res_box(color, Color.TRANSPARENT, 0, 1)
		pip_box.skew = Vector2(-0.3, 0)
		pip.add_theme_stylebox_override("panel", pip_box)
		pips.add_child(pip)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	column.add_child(gap)
	# Rodapé: contagem regressiva + botão pequeno de menu.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_round_countdown = _res_label("", 11, RES_MUTED, true)
	_round_countdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_round_countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(_round_countdown)
	var menu_button := Button.new()
	menu_button.name = "RoundMenuButton"
	menu_button.text = "SAIR PARA O MENU"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.custom_minimum_size = Vector2(0, 24)
	menu_button.pressed.connect(_back_to_menu)
	for state in ["normal", "hover", "pressed", "focus"]:
		var b := _res_box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.14), 0, 2)
		b.border_width_left = 2
		b.skew = Vector2(-0.16, 0)
		b.content_margin_left = 12
		b.content_margin_right = 10
		if state == "hover" or state == "pressed":
			b.bg_color = Color(MENU_ACCENT, 0.16)
			b.border_color = MENU_ACCENT
		menu_button.add_theme_stylebox_override(state, b)
	menu_button.add_theme_font_override("font", _bold())
	menu_button.add_theme_font_size_override("font_size", 10)
	menu_button.add_theme_color_override("font_color", RES_MUTED)
	menu_button.add_theme_color_override("font_hover_color", RES_TEXT)
	footer.add_child(menu_button)
	_round_drain = ProgressBar.new()
	_round_drain.show_percentage = false
	_round_drain.custom_minimum_size.y = 3
	_round_drain.max_value = 1.0
	_round_drain.add_theme_stylebox_override("background", _res_box(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 0, 1))
	_round_drain.add_theme_stylebox_override("fill", _res_box(accent, Color.TRANSPARENT, 0, 1))
	column.add_child(_round_drain)
	_round_break_ms = maxi(1, next_ms)
	_round_next_msec = Time.get_ticks_msec() + next_ms
	_tick_round_panel()
	round_panel.visible = true
	round_panel.modulate.a = 0.0
	var t := round_panel.create_tween()
	t.tween_property(round_panel, "modulate:a", 1.0, 0.25)
	PointerMode.release()

func _tick_round_panel() -> void:
	if _round_countdown == null or not is_instance_valid(_round_countdown):
		return
	var left_ms := maxi(0, _round_next_msec - Time.get_ticks_msec())
	_round_countdown.text = "PRÓXIMO ROUND EM %d s" % ceili(left_ms / 1000.0)
	_round_drain.value = float(left_ms) / float(_round_break_ms)

# ------------------------------------------------------ placar TAB (ao vivo) ---

func _refresh_scoreboard() -> void:
	_score_refresh = 0.5
	for child in score_panel.get_children():
		score_panel.remove_child(child)
		child.queue_free()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	score_panel.add_child(column)
	var mode := "EQUIPES" if team_mode else ("MATA-MATA" if dm_mode else "ELIMINATÓRIA")
	var head := HBoxContainer.new()
	column.add_child(head)
	var kicker := _res_label("PLACAR DA PARTIDA  ·  " + mode, 11, MENU_ACCENT, true)
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kicker)
	var info := ""
	if team_mode:
		info = "ROUND %d/%d  ·  %s" % [round_number, round_total, "PAUSA" if round_break else _clock_text()]
	elif dm_mode:
		info = "META %d ABATES  ·  %s" % [kill_goal, _clock_text()]
	else:
		info = "VIVOS %d" % alive_count
	head.add_child(_res_label(info, 11, RES_MUTED, true))
	if team_mode:
		var title := _res_label(_round_score_text(), 26, RES_TEXT, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
	var ids: Array = names.keys()
	ids.sort_custom(func(a, b):
		var ka := int(kill_counts.get(a, 0))
		var kb := int(kill_counts.get(b, 0))
		if ka != kb:
			return ka > kb
		return int(deaths.get(a, 0)) < int(deaths.get(b, 0)))
	if team_mode:
		for team in [0, 1]:
			var members := ids.filter(func(id): return int(teams.get(id, -1)) == team)
			var alive_n := members.filter(func(id): return _is_alive(id)).size()
			var team_head := HBoxContainer.new()
			column.add_child(team_head)
			var team_label := _res_label("EQUIPE %s%s" % [_team_name(team).to_upper(), "  ·  SUA" if team == my_team else ""], 12, TEAM_TINTS[team].lightened(0.3), true)
			team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			team_head.add_child(team_label)
			var wins := int(round_score[team])
			team_head.add_child(_res_label("%d ROUND%s  ·  %d VIVO%s" % [wins, "" if wins == 1 else "S", alive_n, "" if alive_n == 1 else "S"], 10, RES_MUTED, true))
			column.add_child(_score_header())
			for id in members:
				column.add_child(_score_row(id, TEAM_TINTS[team]))
	else:
		column.add_child(_score_header())
		for id in ids:
			column.add_child(_score_row(id, Color.TRANSPARENT))
	var hint := _res_label("SOLTE TAB PARA FECHAR", 9, RES_DIM, true)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)

func _is_alive(id: String) -> bool:
	if left_ids.has(id):
		return false
	if id == my_id:
		return not local_dead
	return actors.has(id) and not actors[id].dead

func _score_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for spec in [["JOGADOR", 0], ["ABATES", 56], ["MORTES", 56], ["", 64]]:
		var l := _res_label(str(spec[0]), 9, RES_DIM, true)
		if int(spec[1]) > 0:
			l.custom_minimum_size.x = int(spec[1])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	return row

func _score_row(id: String, tint: Color) -> PanelContainer:
	var mine := id == my_id
	var alive := _is_alive(id)
	var panel := PanelContainer.new()
	var b := _res_box(Color(MENU_ACCENT, 0.12) if mine else Color(1, 1, 1, 0.03), MENU_ACCENT if mine else Color.TRANSPARENT, 1 if mine else 0, 3)
	if tint.a > 0.0 and not mine:
		b.border_width_left = 3
		b.border_color = Color(tint, 0.6)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 3
	b.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", b)
	if not alive:
		panel.modulate.a = 0.55
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(who)
	var name_label := _res_label(str(names.get(id, "?")) + ("  (você)" if mine else ""), 13, MENU_ACCENT if mine else RES_TEXT, true)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 100
	who.add_child(name_label)
	var bot := bool(bots.get(id, false))
	var tag := _res_label("BOT" if bot else str(ranks.get(id, "")).to_upper(), 9, RES_DIM if bot else RES_MUTED, true)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(tag)
	for value in [int(kill_counts.get(id, my_kills if mine else 0)), int(deaths.get(id, 0))]:
		var l := _res_label(str(value), 13, RES_TEXT, true)
		l.custom_minimum_size.x = 56
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(l)
	var state := "SAIU" if left_ids.has(id) else ("VIVO" if alive else "MORTO")
	var state_color := RES_DIM if left_ids.has(id) else (Color("#8fe08a") if alive else MENU_HOT)
	var status := _res_label(state, 10, state_color, true)
	status.custom_minimum_size.x = 64
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(status)
	return panel

## "Sair da partida?" panel: leave now (counts as elimination, earned XP is
## kept) or keep playing.
func _build_leave_panel() -> void:
	leave_panel = PanelContainer.new()
	leave_panel.name = "LeavePanel"
	leave_panel.visible = false
	leave_panel.add_theme_stylebox_override("panel", UiTheme.card(28))
	ui.add_child(leave_panel)
	leave_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	leave_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	leave_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	leave_panel.add_child(column)
	var title := Label.new()
	title.text = "SAIR DA PARTIDA?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.font(700))
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	leave_text = Label.new()
	leave_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leave_text.add_theme_font_size_override("font_size", 16)
	leave_text.add_theme_color_override("font_color", UiTheme.MUTED)
	column.add_child(leave_text)
	var leave_button := Button.new()
	leave_button.name = "LeaveMatchButton"
	leave_button.text = "Sair para o menu"
	leave_button.custom_minimum_size = Vector2(260, 46)
	UiTheme.primary(leave_button, 16).focus_mode = Control.FOCUS_ALL
	leave_button.pressed.connect(_back_to_menu)
	column.add_child(leave_button)
	var stay := Button.new()
	stay.name = "StayInMatchButton"
	stay.text = "Continuar na partida"
	stay.custom_minimum_size = Vector2(260, 46)
	UiTheme.secondary(stay, 15).focus_mode = Control.FOCUS_ALL
	stay.pressed.connect(_close_leave_panel)
	column.add_child(stay)

func _open_leave_panel() -> void:
	var lines := "Você volta ao menu e o XP já ganho fica salvo."
	if not local_dead:
		lines = "Você será eliminado desta partida e perde %d XP por sair.\n" % absi(int(Net.rank_table().get("xp", {}).get("quit", -100))) + lines
		if team_mode:
			lines += "\nSua equipe continua sem você."
	leave_text.text = lines
	UiSfx.play(&"open")
	leave_panel.visible = true
	Input.action_release("fire")
	Input.action_release("aim")
	PointerMode.release()
	(leave_panel.find_child("StayInMatchButton", true, false) as Button).grab_focus()

func _close_leave_panel() -> void:
	if leave_panel.visible:
		UiSfx.play(&"close")
	leave_panel.visible = false
	PointerMode.capture()

# ------------------------------------------------------------ placar final ---

const RESULT_WIN := Color("#ffc94a")
const RESULT_LOSE := Color("#ff7a5c")
const RESULT_DRAW := Color("#9fb0ad")
const RES_TEXT := Color("#eef1ec")
const RES_MUTED := Color("#8d9a98")
const RES_DIM := Color("#5f6d6c")
const MEDALS := [Color("#f0c24b"), Color("#c9d1d6"), Color("#d08a52")]
var results_panel: PanelContainer
var results_xp: Label
var results_bar: ProgressBar
var _bold_font: FontVariation

func _bold() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		var base = load("res://assets/fonts/InterVariable.ttf")
		if base is Font:
			_bold_font.base_font = base
		# Engrossar funciona com qualquer fonte (o eixo "wght" da variável não pegava aqui).
		_bold_font.variation_embolden = 0.75
	return _bold_font

func _res_label(text: String, size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold())
	return label

func _res_box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box

## Placar profissional do fim da partida: cabeçalho com o resultado, o seu
## desempenho em destaque, a tabela (por equipe nas partidas de equipe), o XP
## e a patente (preenchidos quando o servidor confirma) e os botões.
func _show_results(data: Dictionary, title: String, subtitle: String, outcome: String) -> void:
	center_panel.visible = false
	_set_cinematic(true) # o placar ocupa a tela: sem minimapa nem mensagens da partida atrás
	if results_panel != null:
		results_panel.queue_free()
	var accent: Color = RESULT_WIN if outcome == "win" else (RESULT_LOSE if outcome == "lose" else RESULT_DRAW)
	results_panel = PanelContainer.new()
	results_panel.name = "ResultsPanel"
	var box := _res_box(Color(0.035, 0.05, 0.06, 0.95), accent, 0, 14)
	box.border_width_top = 4 # só a faixa de cima na cor do resultado
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 20
	for side in ["left", "right"]:
		box.set("content_margin_" + side, 20)
	box.content_margin_top = 16
	box.content_margin_bottom = 16
	results_panel.add_theme_stylebox_override("panel", box)
	results_panel.custom_minimum_size.x = 500
	ui.add_child(results_panel)
	results_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	results_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	results_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	results_panel.add_child(column)
	# Cabeçalho.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	column.add_child(head)
	var mode := "EQUIPES" if team_mode else ("MATA-MATA" if dm_mode else "ELIMINATÓRIA")
	var kicker := _res_label("FIM DA PARTIDA  ·  " + mode, 10, RES_MUTED, true)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(kicker)
	var title_label := _res_label(title, 30, accent, true)
	title_label.name = "ResultsTitle"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title_label)
	var sub := _res_label(subtitle, 12, RES_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(sub)
	center_title.text = title # (compatível com quem lê o título antigo)
	# Seu desempenho.
	var board: Array = data.get("board", [])
	var my_row: Dictionary = {}
	var my_place := 0
	for i in board.size():
		if str(board[i].get("id", "")) == my_id:
			my_row = board[i]
			my_place = i + 1
	var tiles := HBoxContainer.new()
	tiles.name = "ResultsTiles"
	tiles.add_theme_constant_override("separation", 6)
	column.add_child(tiles)
	var place_text := "#%d de %d" % [my_place, board.size()] if my_place > 0 else "—"
	if team_mode:
		# Placar de rounds (Alfa x Bravo); servidores antigos mandam só os abates.
		var score: Array = data.get("rounds", data.get("score", [0, 0]))
		place_text = "%d  x  %d" % [int(score[0]) if score.size() > 0 else 0, int(score[1]) if score.size() > 1 else 0]
	for tile in [["PLACAR" if team_mode else "POSIÇÃO", place_text], ["ABATES", str(int(my_row.get("kills", my_kills)))], ["XP DA PARTIDA", "%+d" % int(my_row.get("xp", match_xp))]]:
		tiles.add_child(_result_tile(str(tile[0]), str(tile[1]), accent if tile[0] == "XP DA PARTIDA" else RES_TEXT))
	# Tabela.
	var table := VBoxContainer.new()
	table.name = "ResultsTable"
	table.add_theme_constant_override("separation", 1)
	column.add_child(table)
	if team_mode:
		var winner = data.get("team")
		var score: Array = data.get("score", [0, 0])
		for team in [0, 1]:
			var tint := Color("#5ea8d0") if team == 0 else Color("#d07a5e")
			var won_team: bool = winner != null and int(winner) == team
			var header := HBoxContainer.new()
			header.name = "ResultsTeam_%d" % team
			table.add_child(header)
			var team_label := _res_label("EQUIPE %s" % _team_name(team).to_upper(), 11, tint.lightened(0.3), true)
			team_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header.add_child(team_label)
			if won_team:
				header.add_child(_res_label("VENCEDORA  ", 9, RESULT_WIN, true))
			header.add_child(_res_label("%d abates" % (int(score[team]) if team < score.size() else 0), 10, RES_MUTED))
			var place := 0
			for row in board:
				if int(row.get("team", -1)) == team:
					place += 1
					table.add_child(_result_row(row, place, tint))
			if team == 0:
				var gap := Control.new()
				gap.custom_minimum_size.y = 4
				table.add_child(gap)
	else:
		table.add_child(_result_header())
		var place := 0
		for row in board:
			place += 1
			table.add_child(_result_row(row, place, Color.TRANSPARENT))
	# XP e patente (o servidor manda logo depois: _on_profile).
	var progress := VBoxContainer.new()
	progress.add_theme_constant_override("separation", 6)
	column.add_child(progress)
	results_xp = _res_label("Salvando seu XP…", 11, RES_MUTED)
	results_xp.name = "ResultsXp"
	results_xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress.add_child(results_xp)
	results_bar = ProgressBar.new()
	results_bar.show_percentage = false
	results_bar.custom_minimum_size.y = 4
	results_bar.max_value = 1.0
	results_bar.value = 0.0
	results_bar.visible = false
	results_bar.add_theme_stylebox_override("background", _res_box(Color(1, 1, 1, 0.07), Color.TRANSPARENT, 0, 3))
	results_bar.add_theme_stylebox_override("fill", _res_box(accent, Color.TRANSPARENT, 0, 3))
	progress.add_child(results_bar)
	if not _pending_profile.is_empty():
		_fill_results_profile(_pending_profile)
	# Botões (os mesmos de antes, trazidos para o placar).
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	for button in [room_button, _menu_button_ref()]:
		if button == null:
			continue
		if button.get_parent() != null:
			button.get_parent().remove_child(button)
		buttons.add_child(button)
		button.custom_minimum_size = Vector2(180, 34)
		_style_result_button(button, button == room_button, accent)
	# Entrada suave.
	results_panel.modulate.a = 0.0
	results_panel.scale = Vector2(0.96, 0.96)
	var t := results_panel.create_tween().set_parallel(true)
	t.tween_property(results_panel, "modulate:a", 1.0, 0.3)
	t.tween_callback(func(): results_panel.pivot_offset = results_panel.size * 0.5)
	t.tween_property(results_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	PointerMode.release()

var _back_button: Button
func _menu_button_ref() -> Button:
	if _back_button == null:
		for child in center_panel.find_children("*", "Button", true, false):
			if (child as Button).text == "Voltar ao menu":
				_back_button = child
	return _back_button

func _style_result_button(button: Button, primary: bool, accent: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var b := _res_box(accent if primary else Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12) if not primary else Color.TRANSPARENT, 0 if primary else 1, 8)
		if state == "hover" or state == "focus":
			b.bg_color = accent.lightened(0.12) if primary else Color(accent, 0.16)
			b.border_color = accent
		button.add_theme_stylebox_override(state, b)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(c, Color("#1a1208") if primary else RES_TEXT)
	button.add_theme_font_override("font", _bold())
	button.add_theme_font_size_override("font_size", 13)

func _result_tile(caption: String, value: String, color: Color) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := _res_box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.07), 1, 8)
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", b)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	tile.add_child(stack)
	var v := _res_label(value, 17, color, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(v)
	var c := _res_label(caption, 9, RES_MUTED, true)
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(c)
	return tile

func _result_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for spec in [["#", 24, HORIZONTAL_ALIGNMENT_LEFT], ["JOGADOR", 0, HORIZONTAL_ALIGNMENT_LEFT], ["ABATES", 50, HORIZONTAL_ALIGNMENT_RIGHT], ["XP", 50, HORIZONTAL_ALIGNMENT_RIGHT]]:
		var l := _res_label(str(spec[0]), 9, RES_DIM, true)
		l.horizontal_alignment = spec[2]
		if int(spec[1]) > 0:
			l.custom_minimum_size.x = int(spec[1])
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	return row

## Linha: posição (medalha no pódio), nome + patente/BOT, abates e XP; a sua em destaque.
func _result_row(row: Dictionary, place: int, team_tint: Color) -> PanelContainer:
	var mine := str(row.get("id", "")) == my_id
	var panel := PanelContainer.new()
	panel.name = "ResultsRow_" + str(row.get("id", "")) # id: nome de nó não aceita "." ("Sgt. Lima")
	var b := _res_box(Color(ACCENT_GOLD, 0.12) if mine else Color(1, 1, 1, 0.025 if place % 2 == 1 else 0.0), ACCENT_GOLD if mine else Color.TRANSPARENT, 1 if mine else 0, 6)
	if team_tint.a > 0.0 and not mine:
		b.border_width_left = 3
		b.border_color = Color(team_tint, 0.6)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 2
	b.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", b)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	panel.add_child(line)
	var place_color: Color = MEDALS[place - 1] if place >= 1 and place <= 3 and not team_mode else RES_DIM
	var pos := _res_label("%d" % place, 13, place_color, true)
	pos.custom_minimum_size.x = 24
	line.add_child(pos)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(who)
	var name_label := _res_label(str(row.get("name", "")) + ("  (você)" if mine else ""), 12, ACCENT_GOLD if mine else RES_TEXT, true)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL # sem isso o nome encolhia a zero
	name_label.custom_minimum_size.x = 90
	who.add_child(name_label)
	var bot := bool(row.get("bot", false))
	var tag := _res_label("BOT" if bot else str(row.get("rank", "")).to_upper(), 8, RES_DIM if bot else RES_MUTED, true)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.add_child(tag)
	var kills := _res_label(str(int(row.get("kills", 0))), 12, RES_TEXT, true)
	kills.custom_minimum_size.x = 50
	kills.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(kills)
	var xp_value := int(row.get("xp", 0))
	var xp := _res_label("—" if bot else "%+d" % xp_value, 12, RES_DIM if bot else (RESULT_LOSE if xp_value < 0 else Color("#8fe08a")), true)
	xp.custom_minimum_size.x = 50
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(xp)
	return panel

## Perfil confirmado pelo servidor: total, patente e quanto falta para a próxima.
var _pending_profile: Dictionary = {}
func _fill_results_profile(data: Dictionary) -> void:
	_pending_profile = data
	if results_xp == null or not is_instance_valid(results_xp):
		return
	var profile: Dictionary = data.get("profile", {})
	var xp := int(profile.get("xp", 0))
	var text := "%s  ·  %s XP" % [str(profile.get("rank", "")).to_upper(), _thousands(xp)]
	if profile.get("nextRankXp") != null:
		var next_xp := int(profile["nextRankXp"])
		var base_xp := int(profile.get("rankXp", 0))
		text += "  ·  faltam %s para %s" % [_thousands(next_xp - xp), profile.get("nextRank", "")]
		results_bar.visible = true
		results_bar.value = 0.0
		var target := clampf(float(xp - base_xp) / maxf(1.0, float(next_xp - base_xp)), 0.0, 1.0)
		results_bar.create_tween().tween_property(results_bar, "value", target, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	results_xp.text = text
	results_xp.add_theme_color_override("font_color", RES_TEXT)
	if bool(data.get("rankUp", false)):
		results_xp.text = "PROMOVIDO A %s!   " % str(profile.get("rank", "")).to_upper() + text
		results_xp.add_theme_color_override("font_color", RESULT_WIN)
	elif bool(data.get("rankDown", false)):
		results_xp.text = "Rebaixado para %s   " % str(profile.get("rank", "")) + text

func _thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if value < 0 else "") + s + out

func _show_center(title: String, body: String) -> void:
	center_title.text = title
	center_body.text = body
	center_panel.visible = true
	PointerMode.release()

func _back_to_menu() -> void:
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

## Keep the connection: the menu reopens the same custom room's lobby.
func _back_to_room() -> void:
	PointerMode.release()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_y", 1)
	feed.add_child(label)
	while feed.get_child_count() > 6:
		var oldest := feed.get_child(0)
		feed.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free())

func _tracer(from: Vector3, to: Vector3) -> void:
	var delta_pos := to - from
	var length := minf(delta_pos.length(), 60.0)
	if length < 0.1:
		return
	_tracer_resources()
	var tracer := MeshInstance3D.new()
	tracer.mesh = _shared_tracer_mesh
	tracer.material_override = _shared_tracer_material
	main_node.add_child(tracer)
	tracer.global_position = from + delta_pos.normalized() * length * 0.5
	tracer.basis = Basis(Quaternion(Vector3.UP, delta_pos.normalized())) * Basis.from_scale(Vector3(1.0, length, 1.0))
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "transparency", 1.0, 0.09)
	tween.tween_callback(tracer.queue_free)
