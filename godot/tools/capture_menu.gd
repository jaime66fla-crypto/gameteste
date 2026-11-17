extends SceneTree
## Foto de conferência do menu principal (com conta de exemplo e offline) em várias resoluções.
## godot --path godot --script res://tools/capture_menu.gd -- --out=<pasta>
## Usa dados de exemplo só na memória: não altera a sessão salva do jogador.

const SAMPLE_BOARD := {
	"players": [
		{"position": 1, "name": "Falcao", "rank": "Capitão", "xp": 48250, "wins": 61},
		{"position": 2, "name": "Lia_77", "rank": "Tenente", "xp": 31900, "wins": 40},
		{"position": 3, "name": "Rocha", "rank": "Tenente", "xp": 27410, "wins": 33},
		{"position": 4, "name": "Jaime", "rank": "Sargento", "xp": 15320, "wins": 18},
		{"position": 5, "name": "Mira.Fina", "rank": "Sargento", "xp": 12005, "wins": 9},
		{"position": 6, "name": "Tatu", "rank": "Cabo", "xp": 8800, "wins": 7},
		{"position": 7, "name": "Nina", "rank": "Cabo", "xp": 6120, "wins": 4},
		{"position": 8, "name": "Zeca", "rank": "Soldado", "xp": 3075, "wins": 1},
	],
	"me": {"position": 4, "name": "Jaime", "rank": "Sargento", "xp": 15320, "wins": 18},
}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var net: Node = root.get_node("Net")
	var saved_token: String = net.get("session_token")
	for logged in [true, false]:
		if logged:
			net.set("session_token", "0".repeat(64))
			net.set("profile", {"name": "Jaime", "xp": 15320, "rank": "Sargento", "rankXp": 12000, "nextRank": "Tenente", "nextRankXp": 20000, "kills": 214, "botKills": 532, "wins": 18, "matches": 97})
			net.set("friends_data", {"requests": ["Nina"], "friends": []})
		else:
			net.set("session_token", "")
			net.set("profile", {})
			net.set("friends_data", {})
		for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(900, 700)]:
			root.size = size
			var menu: Control = load("res://scenes/menu.tscn").instantiate()
			menu.set("leaderboard_cache", SAMPLE_BOARD)
			root.add_child(menu)
			if not logged:
				menu.call("_show_main")
			for i in 40:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join("menu_%s_%dx%d.png" % ["conta" if logged else "offline", size.x, size.y]))
			menu.queue_free()
			await process_frame
	net.set("session_token", saved_token)
	print("salvo em " + out)
	quit(0)
