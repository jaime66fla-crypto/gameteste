extends SceneTree
const Controls = preload("res://scripts/controls.gd")
var failures: Array[String] = []

func _initialize() -> void:
	Controls.reset()
	Controls.set_binding("interact", KEY_F)
	_check(Controls.binding("heal") == KEY_E, "Healing receives the previous interact key")
	_check_conflicts("swapping interact and heal")
	Controls.reset()
	Controls.set_binding("reload", KEY_E)
	_check(Controls.binding("interact") == KEY_R, "Interact receives the previous reload key")
	_check_conflicts("swapping two shared key groups")
	Controls.reset()
	Controls.set_binding("interact", KEY_K)
	_check(Controls.binding("lean_right") == KEY_E, "A free key leaves the other action unchanged")
	_check_conflicts("using a free key")
	Controls.reset()
	for failure in failures:
		printerr(failure)
	print("CONTROLS CONFLICTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _check_conflicts(context: String) -> void:
	for i in Controls.ACTIONS.size():
		for j in range(i + 1, Controls.ACTIONS.size()):
			var a: String = Controls.ACTIONS[i][0]
			var b: String = Controls.ACTIONS[j][0]
			var allowed := [a, b] in [["lean_right", "interact"], ["reload", "build_rotate"]]
			_check(Controls.binding(a) != Controls.binding(b) or allowed, "%s: %s conflicts with %s" % [context, a, b])
