extends SceneTree
## Foto de conferência da tela de Amigos (dados de exemplo só na memória).
## godot --path godot --script res://tools/capture_friends.gd -- --out=<pasta>

const SAMPLE := {
	"requests": ["Nina"],
	"friends": [
		{"name": "leo", "rank": "Capitão", "online": false, "status": "offline"},
		{"name": "pato222play", "rank": "General de Divisão", "online": true, "status": "menu"},
		{"name": "Ana", "rank": "Tenente", "online": true, "status": "room", "code": "K7P2Q"},
		{"name": "Rocha", "rank": "Sargento", "online": true, "status": "match"},
		{"name": "Zeca", "rank": "Soldado", "online": false, "status": "offline"},
	],
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
	net.set("session_token", "0".repeat(64))
	net.set("profile", {"name": "Jaime", "xp": 15320, "rank": "Sargento"})
	for case in [["cheia", SAMPLE], ["vazia", {"requests": [], "friends": []}]]:
		for size in [Vector2i(1280, 720), Vector2i(900, 700)]:
			net.set("friends_data", case[1])
			root.size = size
			var menu: Control = load("res://scenes/menu.tscn").instantiate()
			root.add_child(menu)
			await process_frame
			menu.call("_show_friends")
			for i in 30:
				await process_frame
			root.get_texture().get_image().save_png(out.path_join("amigos_%s_%dx%d.png" % [case[0], size.x, size.y]))
			menu.queue_free()
			await process_frame
	net.set("session_token", saved_token)
	print("salvo em " + out)
	quit(0)
