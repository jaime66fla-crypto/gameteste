extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var registry = load("res://scripts/characters/character_registry.gd")
	var errors := 0
	for definition in registry.all_characters():
		var avatar = registry.create_visual(definition.id)
		root.add_child(avatar)
		for tool in ["stone_axe", "stone_pick"]:
			avatar.set_bow_state(true, 0.0, false, Vector3.ZERO)
			avatar.set_action("chop" if tool == "stone_axe" else "pry", tool)
			avatar.animate(0.1, 0.0, false, false, false, false, false)
			var before: Transform3D = avatar.get("_tool_node").transform
			avatar.animate(0.35, 0.0, false, false, false, false, false)
			var after: Transform3D = avatar.get("_tool_node").transform
			if before.is_equal_approx(after):
				printerr("FAIL: no tool movement ", definition.id, " ", tool)
				errors += 1
		avatar.free()
	print("WORK ANIMATION failures: ", errors)
	quit(1 if errors else 0)
