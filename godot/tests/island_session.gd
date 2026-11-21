extends Node
var failures := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",what)
func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	Net.my_id = "island"
	Net.host_id = "island"
	Net.in_match = true
	Net.start_info = {"survival":true,"you":{"id":"island","p":[0,0.2,300],"hp":100,"hunger":85,"thirst":85,"inv":{}},"clock":{"time":300000,"weather":{"elapsed":240000}},"roster":[],"vehicles":[],"animals":[],"zombies":[]}
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(15)
	var controller: Node = main.get_node("SurvivalController")
	var player: CharacterBody3D = main.get("player")
	var weather: Node3D = controller.get("weather")
	check(float(weather.get("rain")) > 0.8, "server snapshot starts the same rain phase")
	check(controller.world.find_children("EdgeFence","",true,false).is_empty(), "fences removed from actual world")
	var hydro = load("res://scripts/survival/hydrology.gd")
	for resource in controller.world.resources.values():
		var p: Vector3 = resource.pos
		check(absf(p.y-hydro.ground_height(p.x,p.z))<0.01,"resources grounded on sculpted terrain")
	var bridges: Array = controller.world.find_children("RiverBridge*","StaticBody3D",true,false)
	check(not bridges.is_empty(),"roads crossing the river have bridges")
	if not bridges.is_empty():
		var bridge: Node3D = bridges[0]
		var car = load("res://scripts/survival/vehicle.gd").new()
		car.setup({"id":"test_bridge","kind":"sedan","fuel":70})
		main.add_child(car)
		car.global_position = bridge.to_global(Vector3(0,0.6,5))
		car.rotation.y = bridge.rotation.y
		car.reset_visual()
		car.set_controlled(true)
		player.set_physics_process(false)
		Input.action_press("move_forward")
		await frames(120)
		Input.action_release("move_forward")
		check(bridge.to_local(car.global_position).z < -1,"drivable car crosses the river on the bridge")
		check(car.global_position.y > -0.15,"bridge supports the car above the river bed")
		car.queue_free()
		player.set_physics_process(true)
	player.global_position = Vector3(490,-1.2,0)
	player.velocity = Vector3.ZERO
	await frames(90)
	check(bool(player.get("swimming")), "player swims beyond old map border")
	check(player.global_position.y > -3 and player.global_position.y < -1.5, "buoyancy holds the player at the sea surface")
	var roof := StaticBody3D.new()
	roof.position = Vector3(490,3,0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(10,0.4,10)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	roof.add_child(collision)
	main.add_child(roof)
	await frames(30)
	check(bool(weather.get("sheltered")), "roof shelters the player from rain")
	roof.queue_free()
	player.global_position = Vector3(105,-1.8,-12)
	await frames(30)
	check(bool(player.get("swimming")), "river flood water affects player movement")
	weather.call("sync_weather", {"elapsed":719999})
	await frames(30)
	check(float(weather.get("rain")) < 0.001 and float(controller.world.wetness) < 0.01, "dry phase removes rain and drains seasonal water")
	var camera: Camera3D = Camera3D.new()
	main.add_child(camera)
	camera.far = 2500
	camera.position = Vector3(720,650,820)
	camera.look_at(Vector3(0,0,0))
	camera.current = true
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.substr(6)
	if not out.is_empty():
		await frames(10)
		get_viewport().get_texture().get_image().save_png(out.path_join("island-overview.png"))
		weather.call("sync_weather", {"elapsed":240000})
		player.global_position = Vector3(85,-0.8,-40)
		camera.position = Vector3(96,4,-32)
		camera.look_at(Vector3(83,1,-57))
		await frames(50)
		get_viewport().get_texture().get_image().save_png(out.path_join("river-rain.png"))
		if not bridges.is_empty():
			var bridge: Node3D = bridges[0]
			weather.call("sync_weather", {"elapsed":0})
			player.global_position = bridge.to_global(Vector3(0,1,0))
			camera.position = bridge.to_global(Vector3(14,8,20))
			camera.look_at(bridge.global_position + Vector3.UP * 0.4)
			await frames(30)
			get_viewport().get_texture().get_image().save_png(out.path_join("river-bridge.png"))
	Net.in_match = false
	main.queue_free()
	await frames(2)
	print("ISLAND SESSION failures: ",failures)
	get_tree().quit(1 if failures else 0)
