extends SceneTree
## Grenade aim: holding G shows the predicted arc and blast circle without
## throwing; releasing G throws, and the grenade explodes near the predicted spot.
var failures: Array[String] = []
var thrown: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _key(pressed: bool) -> void:
	var g := InputEventKey.new()
	g.physical_keycode = KEY_G
	g.pressed = pressed
	Input.parse_input_event(g)

func _run() -> void:
	root.get_node("Net").call("leave")
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await physics_frame
	var main := current_scene
	var player: CharacterBody3D = main.get_node("Jaime")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.global_position = Vector3(12, 0.2, -10)
	player.velocity = Vector3.ZERO
	player.set("yaw", PI * 0.5)
	player.set("pitch", 0.15)
	for i in 30:
		await physics_frame
	node_added.connect(func(node: Node):
		if node is RigidBody3D and node.has_signal("exploded"):
			thrown.append(node))
	_key(true)
	for i in 10:
		await physics_frame
	var preview: Node3D = main.find_child("GrenadeAimPreview", true, false)
	_check(bool(player.get("grenade_aiming")), "Holding G enters grenade aim")
	_check(preview != null and preview.visible, "Aim preview is visible while G is held")
	_check(thrown.is_empty(), "Holding G does not throw yet")
	var predicted := Vector3.ZERO
	if preview != null:
		var dots: MultiMeshInstance3D = preview.get_child(0)
		_check(dots.multimesh.visible_instance_count > 10, "Arc has dots (got %d)" % dots.multimesh.visible_instance_count)
		var ring: MeshInstance3D = preview.get_child(2)
		predicted = ring.global_position
	_key(false)
	await physics_frame
	await physics_frame
	_check(not bool(player.get("grenade_aiming")), "Releasing G leaves grenade aim")
	_check(preview == null or not preview.visible, "Preview hides after the throw")
	_check(thrown.size() == 1, "Releasing G throws one grenade (got %d)" % thrown.size())
	if thrown.size() == 1:
		var blast := [Vector3.INF]
		thrown[0].connect("exploded", func(_id: String, at: Vector3): blast[0] = at)
		for i in 60 * 3:
			await physics_frame
			if blast[0] != Vector3.INF:
				break
		var miss: float = blast[0].distance_to(predicted)
		print("predicted %s  real %s  miss %.2f m" % [predicted, blast[0], miss])
		_check(miss < 2.0, "Grenade explodes near the predicted circle (miss %.2f m)" % miss)
	# Esc cancels without throwing.
	for i in 70:
		await physics_frame # offline cooldown (1 s)
	_key(true)
	for i in 5:
		await physics_frame
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await physics_frame
	_key(false)
	await physics_frame
	await physics_frame
	_check(not bool(player.get("grenade_aiming")) and thrown.size() == 1, "Esc cancels the aim without throwing")
	for failure in failures:
		printerr(failure)
	print("GRENADE AIM: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
