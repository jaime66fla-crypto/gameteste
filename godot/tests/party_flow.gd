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
		"shop": {"prices": {"pistol": 200, "smg": 1200, "shotgun": 1400, "rifle": 2200, "sniper": 3200, "medkit": 300, "grenade": 300}, "credits": 800, "window": 20000,
			"ammo": {"pistol": 45, "smg": 90, "rifle": 90, "shotgun": 18, "sniper": 15}, "maxMedkits": 5, "maxNades": 3},
		"crates": [],
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
		# Shop (Arsenal): open at the start, shows credits, buys only through the server.
		_check((controller.get("crates") as Dictionary).is_empty(), "No loot crates in team matches")
		var shop: Control = controller.get("shop")
		_check(shop != null and shop.visible, "Shop opens at the start")
		controller.call("_refresh_shop") # weapons given above
		_check(bool(controller.call("ui_open")), "Shop keeps the cursor free")
		var credits_label := shop.find_child("ShopCredits", true, false) as Label if shop != null else null
		_check(credits_label != null and credits_label.text == "$ 800", "Shop shows the credits")
		var rifle_card := shop.find_child("Buy_rifle", true, false) as Button if shop != null else null
		_check(rifle_card != null and rifle_card.disabled, "Too expensive weapon is disabled")
		var pistol_card := shop.find_child("Buy_pistol", true, false) as Button if shop != null else null
		_check(pistol_card != null and pistol_card.disabled and str(shop.call("card_status", "pistol")) == "COMPRADA", "Owned pistol shows as bought")
		_check(str(controller.call("hud_extra")).contains("$800") and str(controller.call("hud_extra")).contains("[B] LOJA"), "HUD shows credits and the shop key")
		controller.call("_on_message", {"t": "credits", "amount": 400, "total": 1200, "victim": "X", "head": false})
		_check(int(controller.get("credits")) == 1200, "Kill credits arrive")
		var smg_card := shop.find_child("Buy_smg", true, false) as Button if shop != null else null
		_check(smg_card != null and not smg_card.disabled and str(shop.call("card_status", "smg")) == "$1200", "Affordable weapon is enabled")
		controller.call("_on_message", {"t": "buy_denied", "item": "rifle", "message": "Créditos insuficientes", "credits": 1200})
		var note := shop.find_child("ShopNote", true, false) as Label if shop != null else null
		_check(note != null and note.text == "Créditos insuficientes", "Server refusal is shown in the shop")
		var b_key := InputEventKey.new()
		b_key.pressed = true
		b_key.physical_keycode = KEY_B
		controller.call("_unhandled_input", b_key)
		_check(shop != null and not shop.visible, "B closes the shop")
		controller.call("_unhandled_input", b_key)
		_check(shop != null and shop.visible, "B opens it again inside the window")
		# Medkit: bought in the shop into the inventory, used with F.
		controller.call("_close_shop")
		controller.call("_on_message", {"t": "bought", "by": "me", "item": "medkit", "ammo": 0, "credits": 500})
		controller.call("_on_message", {"t": "medkits", "id": "me", "count": 1})
		_check(int(controller.get("my_medkits")) == 1, "Medkit goes to the inventory")
		_check(int(controller.get("credits")) == 500, "Credits after buying")
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
		# Rounds (melhor de 5): fim do round mostra o placar; o próximo traz todos de volta.
		controller.call("_on_message", {"t": "round_end", "round": 1, "team": 1, "name": "Equipe Bravo", "reason": "eliminacao", "score": [0, 1], "total": 5, "last": false, "next": 5000})
		_check(bool(controller.get("round_break")), "Round break starts")
		var round_panel := controller.get("round_panel") as Control
		_check(round_panel.visible and not (controller.get("center_panel") as Control).visible, "Round result panel shows (not the old center panel)")
		var round_title := round_panel.find_child("RoundTitle", true, false) as Label
		_check(round_title != null and round_title.text == "DERROTA", "Round panel headline (got %s)" % (round_title.text if round_title != null else "nada"))
		var round_menu := round_panel.find_child("RoundMenuButton", true, false) as Button
		_check(round_menu != null and round_menu.get_combined_minimum_size().y <= 30.0, "Round panel has a small menu button")
		# TAB: placar ao vivo com abates e mortes.
		controller.call("_on_message", {"t": "hp", "id": "bot2", "hp": 0, "by": "me", "w": "pistol", "killed": true, "kills": 1, "alive": 3})
		var tab_key := InputEventKey.new()
		tab_key.physical_keycode = KEY_TAB
		tab_key.pressed = true
		controller.call("_input", tab_key)
		var board := controller.get("score_panel") as Control
		_check(board.visible, "TAB opens the scoreboard")
		var board_text := ""
		for label in board.find_children("*", "Label", true, false):
			board_text += (label as Label).text + "|"
		_check(board_text.contains("MORTES") and board_text.contains("ABATES"), "Scoreboard shows kills and deaths columns")
		tab_key.pressed = false
		controller.call("_input", tab_key)
		_check(not board.visible, "Releasing TAB closes the scoreboard")
		controller.call("_on_message", {"t": "round", "round": 2, "total": 5, "toWin": 3, "score": [0, 1], "host": "other", "alive": 4, "buy": 30000, "duration": 150000,
			"roster": [{"id": "me", "sp": [-32.8, 16], "spawn": 4, "revived": true, "medkits": 0, "nades": 0},
				{"id": "bot1", "sp": [-35.2, 16], "spawn": 4, "revived": false, "w": "pistol", "medkits": 1},
				{"id": "bot2", "sp": [30.8, -28], "spawn": 6, "revived": true, "w": "smg", "medkits": 1},
				{"id": "bot3", "sp": [33.2, -28], "spawn": 6, "revived": true, "w": "rifle", "medkits": 1}]})
		_check(not bool(controller.get("local_dead")), "Local player is back for the new round")
		_check(not bool(controller.get("round_break")) and not (controller.get("center_panel") as Control).visible, "Banner closes when the round starts")
		var back: Vector3 = me.global_position
		_check(Vector2(back.x, back.z).distance_to(Vector2(-32.8, 16)) < 0.5, "Back at the team base")
		_check(not bool(actors["bot2"].get("dead")) and str(actors["bot2"].get("weapon_id")) == "smg", "Fallen enemy bot back with its new weapon")
		controller.call("_process", 0.016)
		var status := str((controller.get("status_label") as Label).text)
		_check(status.contains("ROUND 2/5") and status.contains("ALFA 0  x  1 BRAVO"), "HUD shows round and score (got %s)" % status)
		controller.call("_on_local_death", "bot2") # (o fim da partida abaixo espera você fora de combate)
		net.set("party_code", "K7Q2M")
		controller.call("_on_message", {"t": "end", "winner": null, "team": 0, "name": "Equipe Alfa", "reason": "rounds", "score": [2, 0], "rounds": [3, 1], "round": 4,
			"board": [{"id": "me", "name": "Lider", "kills": 2, "bot": false, "rank": "Recruta", "xp": 70, "team": 0},
				{"id": "bot1", "name": "Cabo Rocha", "kills": 0, "bot": true, "rank": "", "xp": 0, "team": 0},
				{"id": "bot2", "name": "Sgt. Lima", "kills": 0, "bot": true, "rank": "", "xp": 0, "team": 1}]})
		# Primeiro a cena do vencedor (destaque da equipe que está de pé), depois o placar.
		var overlay := controller.find_child("VictoryOverlay", true, false) as Control
		var cam := controller.get("victory_camera") as Camera3D
		_check(overlay != null and cam != null and cam.current, "Winner mini-scene plays with its own camera")
		var shown_name := controller.find_child("VictoryName", true, false) as Label
		_check(shown_name != null and shown_name.text == "CABO ROCHA", "Scene shows the standing MVP of the winning team (got %s)" % (shown_name.text if shown_name else "-"))
		var kicker := controller.find_child("VictoryKicker", true, false) as Label
		_check(kicker != null and kicker.text == "SUA EQUIPE VENCEU!", "Scene says your team won")
		_check(not (controller.get("center_panel") as Control).visible, "Scoreboard waits for the scene")
		controller.set("_victory_time", 2.0)
		var any_key := InputEventKey.new()
		any_key.physical_keycode = KEY_SPACE
		any_key.pressed = true
		controller.call("_unhandled_input", any_key)
		var title: Label = controller.get("center_title")
		_check(title.text == "VITÓRIA DA EQUIPE!", "Team victory title (got %s)" % title.text)
		var results := controller.get("results_panel") as Control
		_check(results != null and results.visible, "New results panel shows")
		_check(controller.find_child("ResultsTeam_0", true, false) != null and controller.find_child("ResultsTeam_1", true, false) != null, "Scoreboard grouped by team")
		_check(controller.find_child("ResultsRow_me", true, false) != null and controller.find_child("ResultsRow_bot2", true, false) != null, "Every player has a row")
		var tiles := controller.find_child("ResultsTiles", true, false)
		var tile_text := ""
		if tiles != null:
			for label in tiles.find_children("*", "Label", true, false):
				tile_text += (label as Label).text + " | "
		_check(tile_text.contains("3  x  1"), "Final scoreboard shows the round score (got %s)" % tile_text)
		# XP confirmado pelo servidor aparece no placar.
		controller.call("_on_message", {"t": "profile", "gained": 70, "rankUp": true, "profile": {"name": "Lider", "xp": 370, "rank": "Soldado", "rankXp": 300, "nextRank": "Cabo", "nextRankXp": 800}})
		var xp_label := controller.find_child("ResultsXp", true, false) as Label
		_check(xp_label != null and xp_label.text.contains("PROMOVIDO") and xp_label.text.contains("faltam 430"), "Results show XP, promotion and what is left (got %s)" % (xp_label.text if xp_label else "-"))
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
