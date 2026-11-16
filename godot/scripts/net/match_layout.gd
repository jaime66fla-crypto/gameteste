extends RefCounted
## Loads data/match_layout.json (shared with the server) and derives door
## waypoints. Buildings have their door on the +Z wall (world_polish.gd).
const PATH := "res://data/match_layout.json"
static var _cache: Dictionary = {}

static func load_layout() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("Missing " + PATH)
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Invalid " + PATH)
		return {}
	for building in data["buildings"]:
		var c: Array = building["center"]
		var s: Array = building["size"]
		var front: float = float(c[1]) + float(s[1]) * 0.5
		building["door_in"] = Vector3(c[0], 0, front - 1.4)
		building["door_out"] = Vector3(c[0], 0, front + 2.6)
	_cache = data
	return _cache

static func spawn_point(index: int) -> Vector3:
	var buildings: Array = load_layout().get("buildings", [])
	if buildings.is_empty():
		return Vector3.ZERO
	var spot: Array = buildings[index % buildings.size()]["spawn"]
	return Vector3(spot[0], 0, spot[1])

## Building whose interior contains `point` (ground plane), or {}.
static func building_at(point: Vector3) -> Dictionary:
	for building in load_layout().get("buildings", []):
		var c: Array = building["center"]
		var s: Array = building["size"]
		if absf(point.x - float(c[0])) < float(s[0]) * 0.5 and absf(point.z - float(c[1])) < float(s[1]) * 0.5:
			return building
	return {}
