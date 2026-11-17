extends SceneTree
## Offline training dummies, grenades, lean (Q/E while aiming) and the
## watchtower ramp, in the real map with real physics.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	root.get_node("Net").call("leave")
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await physics_frame
	var main := current_scene
	var player: CharacterBody3D = main.get_node("Jaime")
	var dummies := get_nodes_in_group("training_dummy")
	_check(dummies.size() == 3, "Offline practice has 3 training dummies (got %d)" % dummies.size())
	if not dummies.is_empty():
		var dummy: Node3D = dummies[0]
		var head: Node = null
		for hitbox in dummy.find_children("Hitbox", "StaticBody3D", true, false):
			if str(hitbox.get("zone")) == "head":
				head = hitbox
		_check(head != null, "Dummy has body-part hitboxes")
		if head != null:
			head.call("take_hit", 27.0, dummy.global_position + Vector3(0, 1.7, 0), Vector3.BACK, "rifle")
			var board: Label3D = dummy.get("board")
			_check(board.text.contains("54") and board.text.contains("FUZIL") and board.text.contains("CABEÇA"), "Dummy shows rifle headshot damage (got %s)" % board.text)
			_check(board.text.contains("2 acertos"), "Dummy shows shots to kill")
		# Offline grenade next to the dummy.
		var grenade: RigidBody3D = player.call("throw_grenade", "")
		grenade.set("offline_damage", true)
		grenade.call("explode", dummy.global_position + Vector3(0, 1.0, 0))
		var board2: Label3D = dummy.get("board")
		_check(board2.text.contains("GRANADA") and board2.text.contains("100"), "Grenade blast damages the dummy (got %s)" % board2.text)
		_check(main.find_child("Explosion", true, false) != null, "Explosion effect spawned")
	# Lean: hold aim + Q.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set("weapon_holstered", false)
	Input.action_press("aim")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	Input.parse_input_event(q)
	for i in 30:
		await physics_frame
	var arm: Node3D = player.get("arm_pivot")
	_check(float(player.get("lean")) < -0.9, "Holding Q while aiming leans left (lean %.2f)" % float(player.get("lean")))
	_check(arm.position.x < -0.15 and arm.rotation.z > 0.1, "View slides and rolls left (x %.2f, roll %.2f)" % [arm.position.x, arm.rotation.z])
	q.pressed = false
	Input.parse_input_event(q)
	Input.action_release("aim")
	for i in 30:
		await physics_frame
	_check(absf(float(player.get("lean"))) < 0.05, "Lean returns to centre")
	# Watchtower: walk up the ramp from the west to the 6 m platform.
	player.global_position = Vector3(24.0, 0.2, 18.0)
	player.velocity = Vector3.ZERO
	player.set("yaw", -PI * 0.5) # facing +X
	player.set("pitch", 0.0)
	Input.action_press("move_forward")
	var top_y := 0.0
	for i in 60 * 7:
		await physics_frame
		top_y = maxf(top_y, player.global_position.y)
		if player.global_position.x > 39.0:
			break
	Input.action_release("move_forward")
	var p := player.global_position
	_check(top_y > 5.7 and p.x > 37.5, "Player walks up the ramp onto the tower (y %.2f, x %.2f)" % [top_y, p.x])
	# Reload and medkit take 3 s with the clock under the crosshair.
	player.global_position = Vector3(12, 0.2, -10)
	player.call("_equip_weapon", "rifle")
	player.set("ammo", 5)
	(player.get("reserve_ammo") as Dictionary)["rifle"] = 60
	player.call("_reload")
	await process_frame
	await process_frame
	var clock: Control = main.get("action_clock")
	var progress: Dictionary = player.call("action_progress")
	_check(progress.get("label", "") == "RECARREGANDO" and clock.visible, "Reload shows the clock")
	for i in 60 * 2:
		await physics_frame
	_check(bool(player.get("reloading")), "Reload still running after 2 s (takes 3 s)")
	for i in 75:
		await physics_frame
	_check(not bool(player.get("reloading")) and int(player.get("ammo")) == 30, "Reload done after 3 s")
	var healed := [false]
	player.call("start_channel", "KIT MÉDICO", 3.0, func(): healed[0] = true)
	await process_frame
	await process_frame
	_check(clock.visible and str(player.call("action_progress").get("label", "")) == "KIT MÉDICO", "Medkit shows the clock")
	for i in 60 * 3 + 15:
		await physics_frame
	await process_frame
	_check(healed[0] and not clock.visible, "Medkit finishes after 3 s and the clock hides")
	# Roaming bots pick random walkable spots across the map.
	var nav = load("res://scripts/net/bot_nav.gd")
	var grid: AStarGrid2D = nav.grid_for(main.get_world_3d())
	var spread := Rect2()
	for i in 30:
		var spot: Vector3 = nav.random_point(main.get_world_3d())
		_check(not grid.is_point_solid(nav.cell_of(spot)), "Roaming spot is walkable")
		spread = Rect2(Vector2(spot.x, spot.z), Vector2.ZERO) if i == 0 else spread.expand(Vector2(spot.x, spot.z))
	_check(spread.size.x > 50 and spread.size.y > 50, "Roaming spots cover the map (%s)" % spread.size)
	var layout: Dictionary = load("res://scripts/net/match_layout.gd").load_layout()
	_check(layout.has("tower") and float(layout["tower"]["loot"][1]) >= 5.9, "Layout has the roof sniper crate")
	for failure in failures:
		printerr(failure)
	print("COMBAT EXTRAS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
