extends Node
## Mede o custo da Sobrevivência sem servidor: chamadas de desenho, objetos,
## triângulos e tempo de quadro com 30 zumbis em volta.
## godot --path godot res://tools/survival/perf_probe.tscn
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _measure() -> float:
	await _frames(10)
	var start := Time.get_ticks_usec()
	await _frames(40)
	return float(Time.get_ticks_usec() - start) / 40000.0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var spawn: Array = SurvivalData.world()["spawns"][2]
	var spot := Vector3(float(spawn[0]), 0.2, float(spawn[1]))
	var zombies: Array = []
	for i in int(OS.get_environment("PROBE_Z") if OS.has_environment("PROBE_Z") else "30"):
		var a := TAU * i / 30.0
		var r := 8.0 + float(i % 6) * 9.0
		zombies.append({"id": "z%d" % i, "kind": ["walker", "runner", "brute"][i % 3], "hp": 60, "p": [spot.x + cos(a) * r, 0.2, spot.z + sin(a) * r]})
	Net.my_id = "me"
	Net.host_id = "me"
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 400000},
		"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 100, "hunger": 80, "thirst": 80,
			"inv": {"w_rifle": 1, "a_556": 60}, "back": "", "weight": 4, "cap": 10},
		"roster": [], "zombies": zombies, "bags": [], "searched": [], "depleted": {}, "vehicles": []}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(60)
	var player: CharacterBody3D = main.get("player")
	for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
		player.set("yaw", yaw)
		player.set("pitch", -0.05)
		await _frames(40)
		var start := Time.get_ticks_usec()
		await _frames(60)
		var ms := float(Time.get_ticks_usec() - start) / 60000.0
		print("yaw %.1f: %.2f ms/quadro (%.0f fps) | draw %d | objetos %d | tris %dk | process %.2f ms | physics %.2f ms" % [yaw, ms, 1000.0 / ms,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	print("nós: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var groups := {}
	for g in main.find_children("*", "GeometryInstance3D", true, false):
		var top: Node = g
		while top.get_parent() != main and top.get_parent() != null:
			top = top.get_parent()
		var key := str(top.name).left(18)
		var child_top: Node = g
		if top.get_parent() == main and top.name == "SurvivalWorld":
			while child_top.get_parent() != top:
				child_top = child_top.get_parent()
			key = "SW/" + str(child_top.name).left(14).rstrip("0123456789_")
		groups[key] = int(groups.get(key, 0)) + 1
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a] > groups[b])
	for k in keys.slice(0, 14):
		print("geometria %s: %d" % [k, groups[k]])
	if OS.has_environment("PROBE_NODES"):
		# Quem pesa: desliga o _process/_physics_process de cada nó e mede de novo.
		var base := await _measure()
		var found: Array = []
		for node in main.find_children("*", "", true, false):
			if node.get_script() != null and (node.is_processing() or node.is_physics_processing()):
				found.append(node)
		var scripts := {}
		for node in found:
			var path: String = node.get_script().resource_path
			if not scripts.has(path):
				scripts[path] = []
			scripts[path].append(node)
		for path in scripts:
			for node in scripts[path]:
				node.set_process(false)
				node.set_physics_process(false)
			var ms := await _measure()
			for node in scripts[path]:
				node.set_process(true)
				node.set_physics_process(true)
			print("sem %s (%d): %.2f ms (base %.2f)" % [path.get_file(), scripts[path].size(), ms, base])
	Net.in_match = false
	get_tree().quit(0)
