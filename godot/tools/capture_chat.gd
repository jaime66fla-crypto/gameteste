extends SceneTree
## Foto de conferência do chat do menu (global, lista de amigos e conversa).
## Dados de exemplo só na memória, sem servidor.
## godot --path godot --script res://tools/capture_chat.gd -- --out=<pasta>

func _initialize() -> void:
	_run.call_deferred()

func _shot(out: String, file: String) -> void:
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join(file))

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var net: Node = root.get_node("Net")
	net.set_process(false) # sem conexão de verdade: as mensagens são injetadas abaixo
	var saved_token: String = net.get("session_token")
	net.set("session_token", "0".repeat(64))
	net.set("profile", {"name": "Jaime", "xp": 15320, "rank": "Sargento", "rankXp": 12000, "nextRank": "Tenente", "nextRankXp": 20000, "kills": 214, "botKills": 532, "wins": 18, "matches": 97})
	net.set("friends_data", {"requests": [], "friends": [
		{"name": "pato222play", "rank": "General de Divisão", "online": true, "status": "menu"},
		{"name": "Ana", "rank": "Tenente", "online": true, "status": "room", "code": "K7P2Q"},
		{"name": "leo", "rank": "Capitão", "online": false, "status": "offline"}]})
	var now := Time.get_unix_time_from_system() * 1000.0
	net.call("_chat_handle", {"t": "chat_hello", "name": "Jaime", "recent": [], "global": [
		{"ch": "global", "from": "Falcao", "rank": "Capitão", "text": "alguém pra sobrevivência agora?", "at": now - 300000},
		{"ch": "global", "from": "Lia_77", "rank": "Tenente", "text": "bora! mundo 2 tá com vaga", "at": now - 240000},
		{"ch": "global", "from": "Jaime", "rank": "Sargento", "text": "tô entrando, me espera na base militar", "at": now - 180000}]})
	net.call("_chat_handle", {"t": "msg", "ch": "global", "from": "Rocha", "rank": "Sargento", "text": "cuidado com o brutamontes perto do hospital kkk", "at": now - 60000})
	net.call("_chat_handle", {"t": "msg", "ch": "dm", "from": "pato222play", "to": "Jaime", "rank": "General de Divisão", "text": "fecha uma 2x2 comigo?", "at": now - 30000})
	root.size = Vector2i(1280, 720)
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.set("leaderboard_cache", {"players": [], "me": {}})
	root.add_child(menu)
	for i in 30:
		await process_frame
	menu.call("_show_main")
	await _shot(out, "chat_fechado.png")
	var dock: Node = menu.get("chat_dock")
	dock.set("open", true)
	dock.set("tab", "global")
	dock.call("refresh")
	await _shot(out, "chat_global.png")
	dock.set("tab", "friends")
	dock.set("friend", "")
	dock.call("refresh")
	await _shot(out, "chat_amigos.png")
	dock.set("friend", "pato222play")
	net.call("_chat_handle", {"t": "history", "with": "pato222play", "messages": [
		{"ch": "dm", "from": "Jaime", "to": "pato222play", "text": "e aí, bora jogar mais tarde?", "at": now - 900000},
		{"ch": "dm", "from": "pato222play", "to": "Jaime", "text": "fecha uma 2x2 comigo?", "at": now - 30000}]})
	dock.call("refresh")
	await _shot(out, "chat_conversa.png")
	net.set("session_token", saved_token)
	net.call("chat_close")
	print("salvo em " + out)
	quit(0)
