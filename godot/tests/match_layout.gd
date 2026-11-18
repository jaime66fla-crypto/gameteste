extends SceneTree
## Validates data/match_layout.json against the real map collision:
## spawns are clear and indoors, loot crates fit, every building can be left
## through its door, and the map edge walls keep players inside.
## godot --headless --path godot --script res://tests/match_layout.gd
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	# "-- --online": monta o mapa do mata-mata / sala personalizada (120 m, só as bases).
	var online := "--online" in OS.get_cmdline_user_args()
	if online:
		root.get_node("Net").set("in_match", true)
	var layout: Dictionary = load("res://scripts/net/match_layout.gd").load_layout()
	_check(not layout.is_empty(), "match_layout.json must load")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	player.global_position = Vector3(0, -40, 0) # out of the way of the probes
	await physics_frame
	await process_frame
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	var crate := BoxShape3D.new()
	crate.size = Vector3(1.0, 0.8, 0.7)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	var buildings: Array = layout["buildings"]
	_check(buildings.size() == 8, "Eight buildings, one spawn per player")
	for building in buildings:
		var name: String = building["name"]
		var spawn := Vector3(building["spawn"][0], 0, building["spawn"][1])
		var loot := Vector3(building["loot"][0], 0, building["loot"][1])
		var door_in: Vector3 = building["door_in"]
		var door_out: Vector3 = building["door_out"]
		_check(_inside(building, spawn), name + ": spawn must be inside")
		_check(_inside(building, loot), name + ": loot must be inside")
		query.shape = capsule
		query.motion = Vector3.ZERO
		query.transform = Transform3D(Basis.IDENTITY, spawn + Vector3(0, 0.95, 0))
		_check(space.intersect_shape(query, 1).is_empty(), name + ": spawn blocked")
		# Walk spawn -> loot, spawn -> door_in -> door_out without hitting walls.
		for leg in [[spawn, loot], [spawn, door_in], [door_in, door_out]]:
			query.transform = Transform3D(Basis.IDENTITY, leg[0] + Vector3(0, 0.95, 0))
			query.motion = leg[1] - leg[0]
			_check(space.cast_motion(query)[0] >= 0.999, name + ": path blocked %s -> %s" % [leg[0], leg[1]])
		query.motion = Vector3.ZERO
		query.shape = crate
		query.transform = Transform3D(Basis.IDENTITY, loot + Vector3(0, 0.48, 0))
		_check(space.intersect_shape(query, 1).is_empty(), name + ": loot crate overlaps geometry")
	query.shape = crate
	_check(layout.get("medkits", []).size() > 0, "Map has medkits")
	for spot in layout["outdoor_loot"] + layout.get("medkits", []):
		var p := Vector3(spot[0], 0.48, spot[1]) # above the 4 cm pavement slabs
		query.transform = Transform3D(Basis.IDENTITY, p)
		_check(space.intersect_shape(query, 1).is_empty(), "Outdoor loot overlaps geometry at %s" % p)
		for building in buildings:
			_check(not _inside(building, Vector3(p.x, 0, p.z)), "Outdoor loot inside a building at %s" % p)
	# Edge walls: a player running outward is stopped before the ground ends.
	# Online o mapa tem map_half_size (60); o treino offline carregado aqui
	# tem o bairro de parkour e muros mais longe (world_polish.map_half).
	var half: float = scene.get_node("WorldPolish").get("map_half")
	_check(not online or is_equal_approx(half, float(layout["map_half_size"])), "Online map must match map_half_size")
	query.shape = capsule
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		query.transform = Transform3D(Basis.IDENTITY, direction * (half - 6.0) + Vector3(0, 0.95, 0))
		query.motion = direction * 12.0
		_check(space.cast_motion(query)[0] < 0.999, "Map edge must be walled toward %s" % direction)
	scene.queue_free()
	await process_frame
	for failure in failures:
		printerr(failure)
	print("MATCH LAYOUT: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _inside(building: Dictionary, point: Vector3) -> bool:
	var c: Array = building["center"]
	var s: Array = building["size"]
	return absf(point.x - c[0]) < s[0] * 0.5 - 0.2 and absf(point.z - c[1]) < s[1] * 0.5 - 0.2
