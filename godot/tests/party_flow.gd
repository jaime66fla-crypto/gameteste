extends SceneTree
## Custom team rooms: the "Equipes" tab, the room screen driven by server
## messages, and a 2x2 team match (allies, no friendly fire, team scoreboard).
## No server needed: messages are fed to the Net autoload directly.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var net: Node = root.get_node("Net")
	var saved_profile: Dictionary = net.get("profile")
	var saved_token: String = net.get("session_token")
	net.set("session_token", "test-token")
	net.set("profile", {"name": "Lider", "rank": "Recruta", "xp": 0})
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.call("_show_multiplayer")
	var tab := menu.find_child("TabTeams", true, false) as Button
	_check(tab != null, "Online screen has the teams tab")
	if tab != null:
		tab.pressed.emit()
	await process_frame
	_check(menu.find_child("CreatePartyButton", true, false) != null, "Teams tab can create a room")
	_check(menu.find_child("PartyCodeField", true, false) != null, "Teams tab has a code field")
	_check(menu.find_child("JoinPartyButton", true, false) != null, "Teams tab can join by code")
	# Simulate being connected to a room as its leader.
	menu.call("_connect_net")
	net.call("_handle", {"t": "welcome", "id": "me", "room": "K7Q2M", "party": true, "code": "K7Q2M"})
	net.call("_handle", {"t": "party", "code": "K7Q2M", "leader": "me", "size": 2, "bots": true, "teams": ["Alfa", "Bravo"],
		"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "team": 0}, {"id": "f1", "name": "Amigo", "rank": "Cabo", "team": 1}]})
	await process_frame
	var code := menu.find_child("PartyCode", true, false) as Label
	_check(code != null and code.text.contains("K7Q2M"), "Room screen shows the invite code")
	_check(menu.find_child("StartPartyButton", true, false) != null, "Leader can start")
	_check(menu.find_child("PartyModeSelect", true, false) != null, "Leader can choose 2x2/4x4")
	_check(menu.find_child("JoinTeam1", true, false) != null, "Can switch to the other team")
	_check(menu.find_child("JoinTeam0", true, false) == null, "No switch button for own team")
	_check(int(net.get("my_team")) == 0, "Own team tracked")
	# Not the leader: no start button.
	net.call("_handle", {"t": "party", "code": "K7Q2M", "leader": "f1", "size": 4, "bots": false, "teams": ["Alfa", "Bravo"],
		"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "team": 1}, {"id": "f1", "name": "Amigo", "rank": "Cabo", "team": 1}]})
	await process_frame
	_check(menu.find_child("StartPartyButton", true, false) == null, "Only the leader can start")
	_check(menu.find_child("ReadyButton", true, false) != null, "Players confirm ready")
	_check(int(net.get("my_team")) == 1, "Team switch tracked")
	# Public elimination room: no timer; leader's start waits for everyone ready.
	net.call("_handle", {"t": "party", "party": false, "code": "", "leader": "me", "capacity": 8, "allReady": false,
		"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "ready": true}, {"id": "f1", "name": "Amigo", "rank": "Cabo", "ready": false}]})
	await process_frame
	var start := menu.find_child("StartPartyButton", true, false) as Button
	_check(menu.find_child("RoomPlayers", true, false) != null, "Elimination room lists players")
	_check(start != null and start.disabled, "Leader cannot start before everyone is ready")
	_check(menu.find_child("PartyCode", true, false) == null, "Public room has no invite code")
	net.call("_handle", {"t": "party", "party": false, "code": "", "leader": "me", "capacity": 8, "allReady": true,
		"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "ready": true}, {"id": "f1", "name": "Amigo", "rank": "Cabo", "ready": true}]})
	await process_frame
	start = menu.find_child("StartPartyButton", true, false) as Button
	_check(start != null and not start.disabled, "Leader can start once all are ready")
	net.call("_handle", {"t": "party", "party": false, "code": "", "leader": "f1", "capacity": 8, "allReady": false,
		"players": [{"id": "f1", "name": "Amigo", "rank": "Cabo", "ready": true}, {"id": "me", "name": "Lider", "rank": "Recruta", "ready": false}]})
	await process_frame
	var ready_button := menu.find_child("ReadyButton", true, false) as Button
	_check(ready_button != null and ready_button.text == "Estou pronto", "Non-leader sees the ready button")
	menu.call("_disconnect_net")
	menu.queue_free()
	await process_frame
	# A 2x2 match: me + ally bot vs two enemy bots.
	net.set("my_id", "me")
	net.set("host_id", "other")
	net.set("in_match", true)
	net.set("start_info", {"t": "start", "host": "other", "alive": 4, "party": true, "teams": ["Alfa", "Bravo"],
		"crates": [{"id": "m0", "p": [-34.0, 0, 18.0], "items": {}, "med": true, "heal": 50, "open": false, "drop": false}],
		"roster": [
			{"id": "me", "name": "Lider", "bot": false, "spawn": 4, "rank": "Recruta", "team": 0, "sp": [-35.2, 16]},
			{"id": "bot1", "name": "Cabo Rocha", "bot": true, "spawn": 4, "rank": "", "team": 0, "sp": [-32.8, 16]},
			{"id": "bot2", "name": "Sgt. Lima", "bot": true, "spawn": 6, "rank": "", "team": 1, "sp": [30.8, -28]},
			{"id": "bot3", "name": "Recruta Dias", "bot": true, "spawn": 6, "rank": "", "team": 1, "sp": [33.2, -28]}]})
	var error := change_scene_to_file("res://scenes/main.tscn")
	_check(error == OK, "Match scene loads")
	for i in 4:
		await process_frame
	var controller := current_scene.find_child("MatchController", true, false) if current_scene != null else null
	_check(controller != null, "Match controller exists")
	if controller != null:
		_check(bool(controller.get("team_mode")), "Team mode on")
		_check(int(controller.get("my_team")) == 0, "Local team from roster")
		var actors: Dictionary = controller.get("actors")
		_check(actors.has("bot1") and bool(actors["bot1"].get("ally")), "Teammate marked as ally")
		_check(actors.has("bot2") and not bool(actors["bot2"].get("ally")), "Enemy not marked as ally")
		var me_pos: Vector3 = controller.get("player").global_position
		_check(Vector2(me_pos.x, me_pos.z).distance_to(Vector2(-35.2, 16)) < 0.5, "Player spawns at the team spot")
		var targets: Array = controller.call("_combatants")
		_check(targets.any(func(e): return e["id"] == "bot1" and e["team"] == 0), "Combatants carry teams")
		var sides: Array = controller.call("_team_alive")
		_check(sides == [2, 2], "Allies/enemies alive counted")
		# Shooting an ally sends nothing and shows no hit; ally bots ignore teammates.
		controller.call("_on_actor_damaged", "bot1", "chest", Vector3.ZERO, Vector3.UP, "rifle")
		var bot1 = actors.get("bot1")
		if bot1 != null:
			bot1.set("combatants", Callable(controller, "_combatants"))
			bot1.set("armed", true)
			var fallback: Dictionary = bot1.call("_pick_target")
			_check(fallback.is_empty() or int(fallback.get("team", -1)) == 1, "Bots never target teammates")
		# Keys follow pickup order: first weapon found is 1, the next 2.
		var me: Node = controller.get("player")
		me.call("give_weapon", "pistol", 30)
		me.call("give_weapon", "rifle", 60)
		var key := InputEventKey.new()
		key.pressed = true
		key.physical_keycode = KEY_2
		me.call("_unhandled_input", key)
		_check(str(me.get("current_weapon")) == "rifle", "Key 2 = second weapon picked (got %s)" % me.get("current_weapon"))
		key.physical_keycode = KEY_1
		me.call("_unhandled_input", key)
		_check(str(me.get("current_weapon")) == "pistol", "Key 1 = first weapon picked (got %s)" % me.get("current_weapon"))
		key.physical_keycode = KEY_3
		me.call("_unhandled_input", key)
		_check(str(me.get("current_weapon")) == "pistol", "Empty slot 3 does nothing")
		_check(str(me.call("status_text")).contains("[1] PISTOLA") and str(me.call("status_text")).contains("2 FUZIL"), "HUD lists pickup slots")
		# Medkit: collected with E into the inventory, used with F.
		var crates: Dictionary = controller.get("crates")
		_check(crates.has("m0") and bool(crates["m0"].get("is_med")), "Medkit crate created")
		if crates.has("m0"):
			_check(str(crates["m0"].call("contents_text")).contains("Kit médico"), "Medkit label")
		controller.call("_on_message", {"t": "looted", "crate": "m0", "by": "me", "items": {}, "med": true, "kits": 1})
		controller.call("_on_message", {"t": "medkits", "id": "me", "count": 1})
		_check(int(controller.get("my_medkits")) == 1, "Medkit goes to the inventory")
		_check(crates.has("m0") and bool(crates["m0"].get("opened")), "Collected medkit crate opens")
		await process_frame
		_check(str(controller.call("hud_extra")).contains("KITS 1"), "HUD shows carried kits (next to the ammo)")
		var heal_key := InputEventKey.new()
		heal_key.pressed = true
		heal_key.physical_keycode = KEY_F
		_check((me.get("heal_handler") as Callable).is_valid(), "F is wired to the medkit")
		me.call("_unhandled_input", heal_key) # full health: nothing sent, just a notice
		controller.set("my_hp", 40.0)
		controller.call("_on_message", {"t": "medkits", "id": "me", "count": 0, "healed": 50})
		controller.call("_on_message", {"t": "hp", "id": "me", "hp": 90, "by": "me", "w": "", "killed": false, "kills": 0, "alive": 4})
		_check(is_equal_approx(float(controller.get("my_hp")), 90.0), "Medkit heals the local player")
		_check(int(controller.get("my_medkits")) == 0, "Used medkit leaves the inventory")
		# Esc opens "Sair da partida?" alive and after being eliminated.
		var esc := InputEventKey.new()
		esc.pressed = true
		esc.keycode = KEY_ESCAPE
		var leave_panel: Control = controller.get("leave_panel")
		controller.call("_unhandled_input", esc)
		_check(leave_panel.visible, "Esc opens the leave panel while alive")
		var leave_button := leave_panel.find_child("LeaveMatchButton", true, false) as Button
		_check(leave_button != null and leave_button.pressed.get_connections().size() > 0, "Leave button is wired")
		controller.call("_unhandled_input", esc)
		_check(not leave_panel.visible, "Esc again closes it")
		controller.call("_on_local_death", "bot2")
		controller.call("_unhandled_input", esc)
		_check(leave_panel.visible, "Eliminated (spectating) players can leave too")
		_check(str(controller.get("leave_text").text).contains("XP"), "Leave panel explains XP is kept")
		controller.call("_unhandled_input", esc)
		net.set("party_code", "K7Q2M")
		controller.call("_on_message", {"t": "end", "winner": null, "team": 0, "name": "Equipe Alfa", "reason": "eliminacao", "score": [2, 0],
			"board": [{"id": "me", "name": "Lider", "kills": 2, "bot": false, "rank": "Recruta", "xp": 70, "team": 0},
				{"id": "bot1", "name": "Cabo Rocha", "kills": 0, "bot": true, "rank": "", "xp": 0, "team": 0},
				{"id": "bot2", "name": "Sgt. Lima", "kills": 0, "bot": true, "rank": "", "xp": 0, "team": 1}]})
		var title: Label = controller.get("center_title")
		_check(title.text == "VITÓRIA DA EQUIPE!", "Team victory title (got %s)" % title.text)
		var body: Label = controller.get("center_body")
		_check(body.text.contains("EQUIPE ALFA") and body.text.contains("EQUIPE BRAVO"), "Scoreboard grouped by team")
		var room_button := controller.get("room_button") as Button
		_check(room_button != null and room_button.visible and room_button.text.contains("K7Q2M"), "Custom room offers 'Voltar para a sala'")
		# The server's lobby message after the match ends the match state.
		net.call("_handle", {"t": "party", "party": true, "code": "K7Q2M", "leader": "me", "size": 2, "bots": true, "teams": ["Alfa", "Bravo"], "allReady": true,
			"players": [{"id": "me", "name": "Lider", "rank": "Recruta", "team": 0, "ready": true}]})
		_check(not bool(net.get("in_match")) and not (net.get("party_info") as Dictionary).is_empty(), "Back in the room lobby after the match")
	net.call("leave")
	net.set("session_token", saved_token)
	net.set("profile", saved_profile)
	for failure in failures:
		printerr(failure)
	print("PARTY FLOW: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
