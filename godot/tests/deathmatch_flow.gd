extends SceneTree
## Mata-mata: the menu tab, the public room screen, and a match where the
## local player and a bot die and come back (respawn), crates refill and the
## first to the kill goal wins. No server: messages are fed to Net directly.
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
	net.set("profile", {"name": "Eu", "rank": "Recruta", "xp": 0})
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.call("_show_multiplayer")
	var tab := menu.find_child("TabDeathmatch", true, false) as Button
	_check(tab != null, "Online screen has the Mata-mata tab")
	_check(menu.find_child("TabTeams", true, false) != null and menu.find_child("TabSurvival", true, false) != null, "Other tabs still there")
	if tab != null:
		tab.pressed.emit()
	await process_frame
	_check(menu.find_child("FindDeathmatchButton", true, false) != null, "Mata-mata tab can look for a room")
	# Public mata-mata room screen.
	net.set("my_id", "me")
	net.call("_handle", {"t": "party", "party": false, "mode": "dm", "goal": 15, "code": "", "leader": "me", "capacity": 8, "allReady": true,
		"players": [{"id": "me", "name": "Eu", "rank": "Recruta", "ready": true}]})
	menu.call("_on_party_updated", net.get("party_info"))
	await process_frame
	_check(str(net.get("room_mode")) == "dm", "Net remembers the room mode")
	var header_found := false
	for label in menu.find_children("*", "Label", true, false):
		if (label as Label).text.contains("15 abates"):
			header_found = true
	_check(header_found, "Room screen shows the kill goal")
	menu.call("_disconnect_net")
	menu.queue_free()
	await process_frame
	# The match: me + 3 bots, everyone with a pistol.
	net.set("host_id", "me")
	net.set("in_match", true)
	net.set("start_info", {"t": "start", "host": "me", "alive": 4, "party": false, "mode": "dm", "goal": 15, "duration": 360000, "respawn": 3000,
		"kit": {"pistol": 45},
		"crates": [
			{"id": "c0", "p": [0.0, 0.0, 0.0], "items": {"smg": 90}, "nades": 1, "open": false, "drop": false},
			{"id": "m0", "p": [6.0, 0.0, 0.0], "items": {}, "med": true, "heal": 50, "open": false, "drop": false}],
		"roster": [
			{"id": "me", "name": "Eu", "bot": false, "spawn": 0, "rank": "Recruta"},
			{"id": "bot1", "name": "Cabo Rocha", "bot": true, "spawn": 1, "rank": ""},
			{"id": "bot2", "name": "Sgt. Lima", "bot": true, "spawn": 2, "rank": ""},
			{"id": "bot3", "name": "Recruta Dias", "bot": true, "spawn": 3, "rank": ""}]})
	var error := change_scene_to_file("res://scenes/main.tscn")
	_check(error == OK, "Match scene loads")
	for i in 4:
		await process_frame
	var controller := current_scene.find_child("MatchController", true, false) if current_scene != null else null
	_check(controller != null, "Match controller exists")
	if controller != null:
		var me: Node = controller.get("player")
		var actors: Dictionary = controller.get("actors")
		_check(bool(controller.get("dm_mode")), "Mata-mata mode on")
		_check(not bool(controller.get("team_mode")), "Not a team match")
		_check((me.get("owned_weapons") as Dictionary).has("pistol") and str(me.get("current_weapon")) == "pistol", "Local player starts with the pistol in hand")
		_check(bool(actors["bot1"].get("armed")) and str(actors["bot1"].get("weapon_id")) == "pistol", "Bots start with the pistol")
		# No shop in mata-mata: small loot crates on the map instead.
		_check(controller.get("shop") == null, "No shop in mata-mata")
		_check(not bool(controller.call("ui_open")), "No shop UI holding the cursor")
		_check(not str(controller.call("hud_extra")).contains("LOJA"), "HUD has no shop key")
		var crates: Dictionary = controller.get("crates")
		_check(crates.size() == 2 and crates.has("c0") and bool(crates["m0"].get("is_med")), "Map crates are placed")
		_check(float(crates["c0"].SIZE.x) < 0.7, "Crates are the compact size")
		_check(str(crates["c0"].call("contents_text")).contains("SMG") and str(crates["c0"].call("contents_text")).contains("Granada"), "Crate label lists weapon and grenade")
		controller.call("_on_message", {"t": "looted", "crate": "c0", "by": "me", "items": {"smg": 90}, "med": false, "kits": 0, "nades": 1})
		controller.call("_on_message", {"t": "nades", "id": "me", "count": 1})
		_check((me.get("owned_weapons") as Dictionary).has("smg") and bool(crates["c0"].get("opened")), "Looting gives the weapon and opens the crate")
		_check(int(controller.get("my_nades")) == 1, "Looted grenade is carried")
		controller.call("_on_message", {"t": "refill", "crate": {"id": "c0", "p": [0.0, 0.0, 0.0], "items": {"rifle": 90}, "nades": 0, "open": false, "drop": false}})
		_check(not bool(crates["c0"].get("opened")) and str(crates["c0"].call("contents_text")).contains("FUZIL"), "Crate refills with new contents")
		await process_frame
		var status: Label = controller.get("status_label")
		_check(status.text.contains("ABATES 0/15"), "HUD shows kills / goal (got %s)" % status.text)
		# I kill bot1: score and leader update.
		controller.call("_on_message", {"t": "hp", "id": "bot1", "hp": 0, "by": "me", "w": "pistol", "zone": "chest", "killed": true, "kills": 1, "alive": 3, "respawn": 3000, "deaths": 1})
		await process_frame
		_check(bool(actors["bot1"].get("dead")), "Bot died")
		_check(status.text.contains("ABATES 1/15") and status.text.contains("LÍDER: VOCÊ"), "Kill counted, I lead (got %s)" % status.text)
		# bot1 comes back elsewhere, armed, simulated by this (host) client.
		controller.call("_on_message", {"t": "respawn", "id": "bot1", "spawn": 5, "p": [10.0, 0, -10.0], "w": "pistol", "ammo": 45, "safe": 1500, "alive": 4})
		await process_frame
		var bot1: Node3D = actors["bot1"]
		_check(not bool(bot1.get("dead")) and bot1.visible, "Bot respawned and is visible")
		_check(bot1.global_position.distance_to(Vector3(10, 0.1, -10)) < 0.6, "Bot respawned at the server spot")
		_check(bool(bot1.get("controlled")), "Host keeps simulating the respawned bot")
		_check(bot1.collision_layer != 0, "Respawned bot collides again")
		var hitboxes: Array = bot1.get("hitboxes")
		_check(hitboxes.is_empty() or (hitboxes[0] as CollisionObject3D).collision_layer != 0, "Respawned bot can be shot again")
		# I die: countdown, then I come back with only the pistol.
		me.call("give_weapon", "rifle", 60)
		controller.call("_on_message", {"t": "hp", "id": "me", "hp": 0, "by": "bot2", "w": "pistol", "zone": "chest", "killed": true, "kills": 1, "alive": 3, "respawn": 3000, "deaths": 1})
		await process_frame
		_check(bool(controller.get("local_dead")), "Local player died")
		_check(status.text.contains("RENASCENDO EM"), "HUD shows the respawn countdown (got %s)" % status.text)
		controller.call("_on_message", {"t": "respawn", "id": "me", "spawn": 6, "p": [30.0, 0, -28.0], "w": "pistol", "ammo": 45, "safe": 1500, "alive": 4, "medkits": 0})
		await process_frame
		_check(not bool(controller.get("local_dead")), "Local player respawned")
		_check(is_equal_approx(float(controller.get("my_hp")), 100.0), "Full health after respawning")
		_check(me.process_mode != Node.PROCESS_MODE_DISABLED, "Player controls work again")
		_check(me.collision_layer != 0, "Player collides again")
		_check(controller.get("spectate_camera") == null and (me.get("camera") as Camera3D).current, "Back to the player's own camera")
		var owned: Dictionary = me.get("owned_weapons")
		_check(owned.size() == 1 and owned.has("pistol") and str(me.get("current_weapon")) == "pistol", "Respawn gives only the pistol (got %s)" % str(owned.keys()))
		_check(Vector2(me.global_position.x, me.global_position.z).distance_to(Vector2(30, -28)) < 0.6, "Respawned at the server spot")
		_check(not bool(controller.call("ui_open")), "Respawn opens no shop")
		# The end: first to 15.
		controller.call("_on_message", {"t": "end", "winner": "me", "name": "Eu", "reason": "abates", "mode": "dm", "goal": 15,
			"board": [{"id": "me", "name": "Eu", "kills": 15, "deaths": 1, "bot": false, "rank": "Recruta", "xp": 400},
				{"id": "bot2", "name": "Sgt. Lima", "kills": 3, "deaths": 4, "bot": true, "rank": "", "xp": 0}]})
		controller.set("_victory_time", 2.0)
		var any_key := InputEventKey.new()
		any_key.physical_keycode = KEY_SPACE
		any_key.pressed = true
		controller.call("_unhandled_input", any_key)
		var title: Label = controller.get("center_title")
		_check(title.text == "VITÓRIA!", "Victory title (got %s)" % title.text)
		var mode_found := false
		for label in controller.find_children("*", "Label", true, false):
			if (label as Label).text.contains("MATA-MATA"):
				mode_found = true
		_check(mode_found, "Results say MATA-MATA")
	net.call("leave")
	net.set("session_token", saved_token)
	net.set("profile", saved_profile)
	for failure in failures:
		printerr(failure)
	print("DEATHMATCH FLOW: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
