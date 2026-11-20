extends SceneTree
## Fotografa o painel de fim de round e o placar TAB de uma partida 2x2 simulada.
## Uso (com janela, não headless): godot --path . --script tools/capture_round_ui.gd
## Saída: user://round_panel.png e user://scoreboard.png

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net: Node = root.get_node("Net")
	net.set("session_token", "test-token")
	net.set("my_id", "me")
	net.set("host_id", "other")
	net.set("in_match", true)
	net.set("start_info", {"t": "start", "host": "other", "alive": 4, "party": true, "teams": ["Alfa", "Bravo"], "crates": [],
		"rounds": {"round": 2, "total": 5, "toWin": 3, "score": [0, 1]},
		"roster": [
			{"id": "me", "name": "Jaimexzz.dev", "bot": false, "spawn": 4, "rank": "Cabo", "team": 0, "sp": [-35.2, 16]},
			{"id": "bot1", "name": "Cabo Rocha", "bot": true, "spawn": 4, "rank": "", "team": 0, "sp": [-32.8, 16]},
			{"id": "p2", "name": "pato222play", "bot": false, "spawn": 6, "rank": "Recruta", "team": 1, "sp": [30.8, -28]},
			{"id": "bot3", "name": "Recruta Dias", "bot": true, "spawn": 6, "rank": "", "team": 1, "sp": [33.2, -28]}]})
	change_scene_to_file("res://scenes/main.tscn")
	for i in 6:
		await process_frame
	var controller := current_scene.find_child("MatchController", true, false)
	controller.set("round_history", [1])
	controller.call("_on_message", {"t": "hp", "id": "me", "hp": 0, "by": "p2", "w": "pistol", "zone": "head", "killed": true, "kills": 1, "alive": 3})
	controller.call("_on_message", {"t": "hp", "id": "p2", "hp": 0, "by": "bot1", "w": "rifle", "killed": true, "kills": 1, "alive": 2})
	controller.call("_on_message", {"t": "hp", "id": "bot3", "hp": 0, "by": "bot1", "w": "rifle", "killed": true, "kills": 2, "alive": 1})
	controller.call("_on_message", {"t": "round_end", "round": 2, "team": 0, "reason": "eliminacao", "score": [1, 1], "total": 5, "last": false, "next": 5000})
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://round_panel.png")
	(controller.get("round_panel") as Control).visible = false
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	controller.call("_input", tab)
	for i in 10:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("user://scoreboard.png")
	print("saved to ", ProjectSettings.globalize_path("user://"))
	quit()
