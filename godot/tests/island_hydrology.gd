extends SceneTree
const Hydro = preload("res://scripts/survival/hydrology.gd")
const Terrain = preload("res://scripts/survival/island_terrain.gd")
const Waters = preload("res://scripts/survival/island_water.gd")
var failures := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", what)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	check(Hydro.weather_at(240000).rain > 0.8, "storm rains")
	check(Hydro.weather_at(360000).wet > 0.9, "water accumulates during rain")
	check(Hydro.weather_at(719999).wet < 0.001, "dry weather drains basins")
	var basin: Dictionary = Hydro.basins().back()
	check(Hydro.basin_state(basin, 0).radius == 0, "temporary lake is dry initially")
	check(Hydro.basin_state(basin, 1).radius > 10, "rain forms a temporary lake")
	for p in [Vector2(490,0), Vector2(-490,0), Vector2(0,490), Vector2(0,-490)]:
		check(Hydro.ground_height(p.x,p.y) < -1.1, "sea floor beyond every old border")
		check(not Hydro.water_at(p.x,p.y,0).fresh, "sea water is salty")
	var scene := Node3D.new()
	root.add_child(scene)
	var started := Time.get_ticks_msec()
	Terrain.build(scene, 420)
	print("TERRAIN BUILD MS: ", Time.get_ticks_msec() - started)
	var water := Waters.new()
	scene.add_child(water)
	water.apply_wetness(1)
	check(scene.find_children("EdgeFence", "", true, false).is_empty(), "no boundary walls")
	await physics_frame
	await physics_frame
	for p in [Vector2(0,300), Vector2(84,-40), Vector2(490,0), Vector2(-490,0)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x,80,p.y),Vector3(p.x,-30,p.y),1)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "terrain collision exists")
		if not hit.is_empty(): check(absf(hit.position.y-Hydro.ground_height(p.x,p.y)) < 0.5, "terrain collision matches authoritative height")
	var samples := []
	for p in [Vector2(85,-40),Vector2(105,-12),Vector2(490,0),Vector2(0,300)]:
		samples.append([p.x,p.y,Hydro.ground_height(p.x,p.y),Hydro.water_at(p.x,p.y,1)])
	print("PARITY_SAMPLES: ", JSON.stringify(samples))
	scene.free()
	print("ISLAND HYDROLOGY failures: ", failures)
	quit(1 if failures else 0)
