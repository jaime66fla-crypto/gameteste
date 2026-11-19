extends SceneTree
## Validates the three online maps (data/match_maps.json) against their real
## collision: every map builds, spawns are clear and inside the walls, every
## spawn can walk to the centre and to every other spawn (A* grid), the edge
## walls keep players inside, and each mode gets its map.
## godot --headless --path godot --script res://tests/match_layout.gd
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const BotNav = preload("res://scripts/net/bot_nav.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	_check(MatchLayout.map_for({"mode": "elim"}) == "praca", "Eliminatória uses Praça central")
	_check(MatchLayout.map_for({"mode": "dm"}) == "cruz", "Mata-mata uses Cruz")
	_check(MatchLayout.map_for({"party": true, "mode": "elim"}) == "equipes", "Team rooms use Equipes")
	_check(MatchLayout.map_for({"party": true, "map": "cruz"}) == "cruz", "Server map wins over the mode")
	var ids := MatchLayout.map_ids()
	_check(ids.size() == 3, "Three online maps (got %d)" % ids.size())
	root.get_node("Net").set("in_match", true)
	for id in ids:
		await _check_map(str(id))
	root.get_node("Net").set("in_match", false)
	for failure in failures.slice(0, 20):
		printerr(failure)
	print("MATCH LAYOUT: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_map(id: String) -> void:
	root.get_node("Net").set("start_info", {"map": id})
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	player.global_position = Vector3(0, -40, 0) # out of the way of the probes
	await physics_frame
	await process_frame
	var map: Node = scene.get_node_or_null("MatchMap")
	_check(map != null and str(map.get("map_id")) == id, id + ": MatchMap built")
	_check(scene.get_node_or_null("WorldPolish") == null, id + ": the old city is not built in matches")
	var layout := MatchLayout.load_layout()
	var spawns: Array = layout.get("spawns", [])
	_check(spawns.size() == 8, id + ": 8 spawns (got %d)" % spawns.size())
	if id == "equipes":
		var teams: Array = layout.get("team_spawns", [])
		_check(teams.size() == 2 and teams[0].size() == 4 and teams[1].size() == 4, id + ": two bases with 4 spots")
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = capsule
	var hx := float(layout["half_x"])
	var hz := float(layout["half_z"])
	for spot in spawns:
		var p := Vector3(spot[0], 0, spot[1])
		_check(absf(p.x) < hx - 1.0 and absf(p.z) < hz - 1.0, id + ": spawn %s inside the walls" % p)
		query.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.97, 0))
		_check(space.intersect_shape(query, 1).is_empty(), id + ": spawn %s blocked" % p)
	# Everyone can reach the centre and every other spawn on foot.
	var grid := BotNav.grid_for(player.get_world_3d())
	var centre := Vector3.ZERO
	for spot in spawns:
		var p := Vector3(spot[0], 0, spot[1])
		_check(BotNav.path(player.get_world_3d(), p, centre).size() > 1, id + ": no path from spawn %s to the centre" % p)
		var first := Vector3(spawns[0][0], 0, spawns[0][1])
		if p != first:
			_check(BotNav.path(player.get_world_3d(), first, p).size() > 1, id + ": no path between spawns %s and %s" % [first, p])
	_check(grid != null, id + ": nav grid")
	# Edge walls: a player running outward is stopped before the ground ends.
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var half := hx if absf(direction.x) > 0.5 else hz
		query.transform = Transform3D(Basis.IDENTITY, direction * (half - 5.0) + Vector3(0, 0.97, 0))
		query.motion = direction * 12.0
		_check(space.cast_motion(query)[0] < 0.999, id + ": map edge must be walled toward %s" % direction)
		query.motion = Vector3.ZERO
	scene.queue_free()
	await process_frame
	await process_frame
