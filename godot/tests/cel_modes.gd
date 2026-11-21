extends SceneTree
## Visual smoke test: real mode scenes, local fixtures, no server connection.
const Layout = preload("res://scripts/net/match_layout.gd")
var failures: Array[String] = []
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.substr(6)
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func frames(count: int) -> void:
	for index in count:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var net := root.get_node("Net")
	for fixture in [["treino", "", false, 0], ["eliminatoria", "elim", false, 4], ["mata-mata", "dm", false, 4], ["equipes-2x2", "elim", true, 4], ["equipes-4x4", "elim", true, 8]]:
		var title: String = fixture[0]
		net.set("my_id", "me")
		net.set("host_id", "offline")
		net.set("in_match", fixture[3] > 0)
		var roster: Array = []
		for index in int(fixture[3]):
			roster.append({"id": "me" if index == 0 else "actor%d" % index, "name": "Jogador %d" % (index + 1), "bot": false, "spawn": index, "team": index % 2})
		net.set("start_info", {"host": "offline", "mode": fixture[1], "party": fixture[2], "alive": fixture[3], "roster": roster, "crates": [], "teams": ["Alfa", "Bravo"], "kit": {"pistol": 45}})
		var scene: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		await frames(40)
		check(scene.has_node("CelStyle"), title + ": cel adapter present")
		if fixture[3] > 0:
			var map := scene.get_node("MatchMap")
			var expected := "equipes" if fixture[2] else ("cruz" if fixture[1] == "dm" else "praca")
			check(map.get("map_id") == expected, title + ": correct map")
			var styled := 0
			for child in map.get_children():
				if child is MeshInstance3D and child.material_override != null and child.material_override.has_meta("cel_styled"):
					styled += 1
			check(styled > 0, title + ": map materials styled")
			var controller := scene.get_node("MatchController")
			check(controller.get("actors").size() == fixture[3] - 1, title + ": all remote characters present")
			check(controller.get("team_mode") == fixture[2], title + ": teams preserved")
			check(controller.get("dm_mode") == (fixture[1] == "dm"), title + ": rules preserved")
		else:
			check(scene.get("training_ground") != null, "treino: training ground present")
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(title + ".png"))
			var player: Node3D = scene.get("player")
			player.set_physics_process(false)
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.make_current()
			camera.global_position = Vector3(35, 35, 40) if fixture[3] > 0 else Vector3(28, 25, 24)
			camera.look_at(Vector3.ZERO if fixture[3] > 0 else Vector3(0, 0, -10))
			await frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(title + "-panorama.png"))
		print("CEL MODE CHECKED: ", title)
		current_scene = null
		scene.queue_free()
		await frames(3)
	net.set("in_match", false)
	for message in failures:
		printerr(message)
	print("CEL MODES: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
