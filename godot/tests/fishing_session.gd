extends SceneTree
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		printerr("FAIL: ", what)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var net := root.get_node("Net")
	net.set("in_match", true)
	net.set("my_id", "fish-test")
	net.set("host_id", "")
	net.set("start_info", {"survival": true, "you": {"id": "fish-test", "p": [0, 0.2, 0], "hp": 100, "inv": {"fishing_rod": 1}, "cap": 20}, "roster": [], "zombies": [], "animals": [], "vehicles": [], "bags": [], "buildings": []})
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in 1800:
		await process_frame
		if bool(main.get("match_ready")): break
	check(bool(main.get("match_ready")), "survival starts")
	var ctl = main.get("match_controller")
	if ctl == null:
		quit(1)
		return
	var player = main.get("player")
	player.set_physics_process(false)
	var fishing = ctl.get("fishing_ctl")
	check(fishing != null, "fishing component integrated")
	var pond: Dictionary = load("res://scripts/survival/survival_data.gd").world().get("ponds", [])[0]
	player.global_position = Vector3(float(pond.x), 0.2, float(pond.z))
	var shore_target: Dictionary = fishing.target()
	check(str(shore_target.get("label", "")).contains("Shift+E"), "freshwater offers drinking with rod")
	Input.action_press("sprint")
	ctl.call("_interact")
	check(not fishing.pending, "Shift+E preserves drink instead of casting")
	Input.action_release("sprint")
	player.global_position = Vector3(float(pond.x), 0.2, float(pond.z) + float(pond.r) + 0.5)
	player.set("yaw", 0.0)
	var cast := {"t": "fishing", "active": true, "p": [player.global_position.x, 0, player.global_position.z - 3.0], "wait_ms": 5000, "window_ms": 1800}
	ctl.call("_on_message", cast)
	check(fishing.active and player.fishing_active, "server starts combat input gate")
	check(ctl.action == "fish" and ctl.action_tool == "fishing_rod", "local fishing pose")
	check(is_instance_valid(fishing.bobber), "visible bobber")
	var avatar = player.get("humanoid_avatar")
	avatar.call("animate", 0.016, 0.0, false, false, false, false, false)
	var rod = avatar.get("_tool_node")
	check(is_instance_valid(rod) and rod.position.length() > 0.2, "rod held by animated hands instead of skeleton origin")
	if "--capture" in OS.get_cmdline_user_args():
		for frame in 12:
			avatar.call("animate", 0.016, 0.0, false, false, false, false, false)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/jaime/Documents/Codex/2026-11-21/files-mentioned-by-the-user-codex/work/fishing-preview.png")
	check("aguarde" in fishing.hint(), "waiting hint")
	fishing.elapsed = 5.1
	check("MORDEU" in fishing.hint(), "bite hint")
	var hook := InputEventMouseButton.new()
	hook.button_index = MOUSE_BUTTON_RIGHT
	hook.pressed = true
	Input.action_press("aim")
	fishing.call("_input", hook)
	check(not Input.is_action_pressed("aim"), "hook click cannot leave weapon aiming")
	check(not fishing.active and not player.fishing_active, "right mouse hooks and releases pose")
	player.get("bow_controller").call("equip")
	check(player.call("has_bow"), "bow equipped before fishing")
	ctl.call("_on_message", cast)
	check(not player.call("has_bow"), "bow put away during fishing")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	fishing.call("_input", esc)
	check(not fishing.active, "Escape cancels")
	check(player.call("has_bow"), "bow restored after cancellation")
	ctl.call("_on_message", cast)
	player.global_position += Vector3(1, 0, 0)
	fishing.call("_process", 0.01)
	check(not fishing.active, "movement cancels")
	main.queue_free()
	await process_frame
	print("FISHING SESSION: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
