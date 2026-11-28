extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player = load("res://scripts/player.gd").new()
	root.add_child(player)
	player.set_physics_process(false)
	var visual: Node = player.get("humanoid_avatar")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	player._unhandled_input(event)
	_check(visual.get("current_clip") != "elbow_punch", "E without a target must not punch")
	var calls := [0]
	player.interact_handler = func():
		calls[0] += 1
		return false
	player._unhandled_input(event)
	_check(calls[0] == 1, "E still requests interaction")
	_check(visual.get("current_clip") != "elbow_punch", "Failed interaction must not punch")
	var hits := [0]
	player.melee_handler = func(): hits[0] += 1
	player._punch()
	_check(hits[0] == 1 and visual.get("current_clip") == "punch", "Explicit punch still animates and hits")
	player.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("INTERACT WITHOUT PUNCH: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
