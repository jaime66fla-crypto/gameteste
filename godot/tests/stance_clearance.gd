extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player = load("res://scripts/player.gd").new()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.stance = 2
	for frame in 40:
		player._update_crouch(1.0 / 60.0)
	var ceiling := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 0.2, 4)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ceiling.add_child(collision)
	ceiling.position.y = 1.0 # 90 cm of clearance: only prone fits.
	world.add_child(ceiling)
	await physics_frame
	await process_frame
	player.stance = 0 # Ctrl after prone requests standing.
	for frame in 40:
		player._update_crouch(1.0 / 60.0)
	_check(player.prone and player.body_capsule.height < 0.9, "Standing request under a low roof must preserve prone clearance")
	ceiling.position.y = 1.75 # Enough to crouch, still too low to stand.
	await physics_frame
	await process_frame
	for frame in 40:
		player._update_crouch(1.0 / 60.0)
	_check(player.crouching and not player.prone, "Player can crouch when there is enough room")
	_check(player.body_capsule.height < 1.65, "Crouch capsule stays below the ceiling")
	ceiling.queue_free()
	await physics_frame
	await process_frame
	for frame in 40:
		player._update_crouch(1.0 / 60.0)
	_check(not player.crouching and not player.prone and is_equal_approx(player.body_capsule.height, 1.8), "Pending stand completes after the ceiling clears")
	world.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("STANCE CLEARANCE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
