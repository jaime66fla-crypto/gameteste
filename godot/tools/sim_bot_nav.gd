extends SceneTree
## Simula bots passeando por um mapa online e lista onde eles ficam presos.
## Todos na mesma equipe (sem combate): só andam até pontos aleatórios, entrando
## e saindo das casas. Uso:
##   godot --headless --path . --fixed-fps 60 --script tools/sim_bot_nav.gd -- equipes 120
## (mapa: praca | cruz | equipes; segundos de jogo simulados)
const STUCK_SECONDS := 4.0
const STUCK_DISTANCE := 0.8

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := args[0] if args.size() > 0 else "equipes"
	var seconds := float(args[1]) if args.size() > 1 else 120.0
	var net: Node = root.get_node("Net")
	net.set("session_token", "test-token")
	net.set("my_id", "me")
	net.set("host_id", "me")
	net.set("in_match", true)
	var roster := [{"id": "me", "name": "Eu", "bot": false, "spawn": 0, "rank": "", "team": 0, "sp": [0, -60]}]
	for i in 7:
		roster.append({"id": "bot%d" % i, "name": "Bot %d" % i, "bot": true, "spawn": i, "rank": "", "team": 0, "w": "rifle"})
	net.set("start_info", {"t": "start", "host": "me", "alive": 8, "party": true, "map": map_id, "teams": ["Alfa", "Bravo"], "crates": [], "roster": roster})
	change_scene_to_file("res://scenes/main.tscn")
	for i in 6:
		await process_frame
	var controller := current_scene.find_child("MatchController", true, false)
	var player: Node3D = controller.get("player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, -50, 0) # fora do caminho (e fora do alcance de visão)
	var actors: Dictionary = controller.get("actors")
	var track := {} # id -> {anchor, since}
	var events: Array = []
	var walked := {}
	var reached := {}
	var slow: Array = []
	var trace: Array = []
	var trace_id := ""
	var trace_left := 0
	var frames := int(seconds * 60.0)
	for frame in frames:
		await physics_frame
		if frame % 30 != 0:
			continue
		var now := frame / 60.0
		for id in actors:
			var bot: Node3D = actors[id]
			var p := bot.global_position
			var t: Dictionary = track.get(id, {"anchor": p, "since": now, "last": p})
			walked[id] = float(walked.get(id, 0.0)) + Vector2(p.x - t["last"].x, p.z - t["last"].z).length()
			t["last"] = p
			if Vector2(p.x - t["anchor"].x, p.z - t["anchor"].z).length() > STUCK_DISTANCE:
				t["anchor"] = p
				t["since"] = now
			elif now - float(t["since"]) >= STUCK_SECONDS:
				var wp: Vector3 = bot.get("_waypoint")
				var goal: Vector3 = bot.get("_wander_goal")
				events.append("%5.1fs %s preso em (%.1f, %.1f) waypoint (%.1f, %.1f) objetivo (%.1f, %.1f)" % [now, id, p.x, p.z, wp.x, wp.z, goal.x, goal.z])
				t["since"] = now # conta de novo (um evento a cada 4 s parado)
			track[id] = t
			# Progresso: objetivos alcançados (o objetivo troca ao chegar perto) e trechos lentos.
			var goal_now: Vector3 = bot.get("_wander_goal")
			if goal_now != t.get("goal", goal_now) and Vector2(p.x - t["goal"].x, p.z - t["goal"].z).length() < 3.0:
				reached[id] = int(reached.get(id, 0)) + 1
			t["goal"] = goal_now
			var hist: Array = t.get("hist", [])
			hist.append(p)
			if hist.size() > 16: # 8 s
				var old: Vector3 = hist.pop_front()
				if Vector2(p.x - old.x, p.z - old.z).length() < 4.0 and frame % 480 == 0:
					slow.append("%5.1fs %s lento perto de (%.1f, %.1f)" % [now, id, p.x, p.z])
					if trace_id.is_empty():
						trace_id = id
						trace_left = 24
			if id == trace_id and trace_left > 0:
				trace_left -= 1
				var w: Vector3 = bot.get("_waypoint")
				var g: Vector3 = bot.get("_wander_goal")
				var detour := int(bot.get("_detour_until")) > Time.get_ticks_msec()
				trace.append("%5.1fs %s p(%.2f, %.2f) wp(%.2f, %.2f) goal(%.1f, %.1f)%s" % [now, id, p.x, p.z, w.x, w.z, g.x, g.z, "  DESVIO" if detour else ""])
			t["hist"] = hist
	print("MAPA %s  %d s simulados" % [map_id, int(seconds)])
	for id in walked:
		print("  %s andou %.0f m, chegou a %d objetivos" % [id, walked[id], int(reached.get(id, 0))])
	print("TRACE (primeiro bot lento):")
	for line in trace:
		print("  " + line)
	print("TRECHOS LENTOS (<4 m em 8 s): %d" % slow.size())
	for line in slow:
		print("  " + line)
	print("EVENTOS DE TRAVAMENTO: %d" % events.size())
	for line in events:
		print("  " + line)
	quit()
