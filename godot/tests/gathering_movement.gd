extends SceneTree

var failures: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _check(ok: bool, text: String) -> void:
	if not ok:
		failures.append(text)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 80)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var player = load("res://scripts/player.gd").new()
	world.add_child(player)
	var controller = load(get_script().resource_path.get_base_dir().path_join("gathering_fixture.gd")).new()
	controller.player = player
	world.add_child(controller)
	await _frames(10)
	for kind in ["bush", "tree"]:
		Input.action_press("move_forward")
		await _frames(15)
		controller.target_fixture = {"id": "test_resource", "type": "resource", "kind": kind, "time": 0.8, "pos": player.global_position + Vector3(0, 0, -1), "tool": "stone_axe"}
		_check(controller._interact(), kind + ": collection starts")
		var start: Vector3 = player.global_position
		await _frames(12)
		_check(player.global_position.distance_to(start) < 0.02, kind + ": holding movement cannot move during collection")
		Input.action_press("jump")
		await _frames(2)
		Input.action_release("jump")
		_check(player.is_on_floor(), kind + ": jump cannot interrupt collection")
		for i in 90:
			if player.channel_left <= 0.0:
				break
			await _frames(1)
		_check(player.channel_left <= 0.0 and controller.action == "", kind + ": collection finishes and clears the animation")
		var finished: Vector3 = player.global_position
		await _frames(15)
		_check(player.global_position.distance_to(finished) > 0.1, kind + ": movement resumes when finished")
		controller._interact()
		player.cancel_channel()
		var canceled: Vector3 = player.global_position
		await _frames(15)
		_check(player.global_position.distance_to(canceled) > 0.1, kind + ": cancellation releases movement")
		Input.action_release("move_forward")
		await _frames(60)
	world.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("GATHERING MOVEMENT: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
