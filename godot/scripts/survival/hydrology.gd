extends RefCounted
## Same deterministic basin and weather formulas as src/godot-hydrology.js.
const Data = preload("res://scripts/survival/survival_data.gd")

static func weather_at(elapsed: float) -> Dictionary:
	var t := fposmod(elapsed / 1000.0, 720.0)
	var rain := 0.0
	if t >= 90.0 and t < 120.0: rain = smoothstep(90.0, 120.0, t)
	elif t >= 120.0 and t < 300.0: rain = 1.0
	elif t >= 300.0 and t < 360.0: rain = 1.0 - smoothstep(300.0, 360.0, t)
	var wet := 0.0
	if t >= 90.0 and t < 360.0: wet = smoothstep(90.0, 360.0, t)
	elif t >= 360.0: wet = 1.0 - smoothstep(360.0, 720.0, t)
	return {"elapsed": maxf(0, elapsed), "rain": rain, "wet": wet}

static func coast_height(x: float, z: float) -> float:
	var a := atan2(z, x)
	var edge := Vector2(x,z).length()
	var shift := sin(a * 3.0) * 7.0 + sin(a * 7.0) * 4.0
	var h := float(Data.world().get("half_size", 420))
	return -8.0 * smoothstep(h - 2.0 + shift, h + 75.0 + shift, edge)

static func river_sample(x: float, z: float) -> Dictionary:
	var pts: Array = Data.world().get("hydrology", {}).get("river", {}).get("points", [])
	var best := {"distance": INF, "level": -0.45}
	for i in maxi(0, pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var t := clampf((Vector2(x, z) - a).dot(b - a) / a.distance_squared_to(b), 0, 1)
		var d := Vector2(x, z).distance_to(a.lerp(b, t))
		if d < float(best.distance): best = {"distance": d, "level": -0.45 - 0.65 * (i + t) / (pts.size() - 1)}
	return best

static func basins() -> Array:
	return Data.world().get("ponds", []) + Data.world().get("hydrology", {}).get("floodplains", [])

static func basin_state(b: Dictionary, wet: float) -> Dictionary:
	var temporary := bool(b.get("temporary", false))
	var level := -0.95 + wet * 1.35 if temporary else -0.25 + wet * 0.85
	var bottom := -0.65 if temporary else -1.4
	var radius := 0.0 if level <= bottom else float(b.r) * sqrt((level - bottom) / 1.55)
	return {"surface": level, "radius": radius}

static func ground_height(x: float, z: float) -> float:
	var height := 0.0
	for m in Data.world().get("mountains", []):
		var distance := Vector2(x - float(m.x), z - float(m.z)).length()
		if distance < float(m.r): height = maxf(height, float(m.h) * 0.5 * (1.0 + cos(PI * distance / float(m.r))))
	var river := river_sample(x, z)
	height += coast_height(x, z) + relief(x, z, float(river.distance))
	var width := float(Data.world().get("hydrology", {}).get("river", {}).get("width", 9))
	if float(river.distance) < width + 13.0:
		height = minf(height, float(river.level) - 2.0 + 2.0 * pow(float(river.distance) / width, 2))
	for b in basins():
		var d := Vector2(x - float(b.x), z - float(b.z)).length() / float(b.r)
		if d < 1.4:
			height = minf(height, (-0.65 if bool(b.get("temporary", false)) else -1.4) + 1.55 * d * d)
	return height

## Ondulações suaves do terreno (colinas e baixadas). Planas nas cidades, nas
## estradas, perto dos lagos, do rio e da costa. Mesma conta de relief() em
## src/godot-hydrology.js: o servidor também precisa da altura do chão.
static var _relief: Dictionary = {} # estradas, cidades e lagos já prontos para relief_mask

static func relief_noise(x: float, z: float) -> float:
	return (0.45 * sin(0.021 * x + 0.7) * cos(0.017 * z - 1.3)
		+ 0.4 * sin(0.043 * (0.8 * x + 0.6 * z) + 2.1)
		+ 0.3 * cos(0.061 * (0.8 * z - 0.6 * x) - 0.4)
		+ 0.15 * sin(0.11 * x + 0.3) * sin(0.097 * z + 1.7))

static func _relief_data() -> Dictionary:
	if _relief.is_empty():
		var w := Data.world()
		var roads: Array = []
		for road in w.get("roads", []):
			var a := Vector2(float(road["from"][0]), float(road["from"][1]))
			var b := Vector2(float(road["to"][0]), float(road["to"][1]))
			var half := float(road.get("width", 6)) * 0.5
			roads.append([a, b, half, Rect2(a, Vector2.ZERO).expand(b).grow(half + 11.0)])
		var towns: Array[Vector2] = []
		for town in w.get("towns", []):
			towns.append(Vector2(float(town["center"][0]), float(town["center"][1])))
		var lakes: Array = []
		for b in basins():
			lakes.append([Vector2(float(b.x), float(b.z)), float(b.r) * 1.3])
		_relief = {"roads": roads, "towns": towns, "lakes": lakes, "half": float(w.get("half_size", 420)),
			"width": float(w.get("hydrology", {}).get("river", {}).get("width", 9))}
	return _relief

static func relief_mask(x: float, z: float, river_distance: float = -1.0) -> float:
	var d := _relief_data()
	var p := Vector2(x, z)
	var h: float = d.half
	var a := atan2(z, x)
	var shift := sin(a * 3.0) * 7.0 + sin(a * 7.0) * 4.0
	var mask := 1.0 - smoothstep(h - 40.0 + shift, h - 8.0 + shift, p.length())
	if mask <= 0.0: return 0.0
	for town: Vector2 in d.towns:
		mask = minf(mask, smoothstep(57.0, 82.0, p.distance_to(town)))
	if mask <= 0.0: return 0.0
	for road in d.roads:
		if not (road[3] as Rect2).has_point(p): continue # longe da estrada: não muda nada
		var half: float = road[2]
		mask = minf(mask, smoothstep(half + 1.5, half + 11.0, p.distance_to(Geometry2D.get_closest_point_to_segment(p, road[0], road[1]))))
	if mask <= 0.0: return 0.0
	var width: float = d.width
	if river_distance < 0.0: river_distance = float(river_sample(x, z).distance)
	mask = minf(mask, smoothstep(width + 8.0, width + 24.0, river_distance))
	for lake in d.lakes:
		var r: float = lake[1]
		var gap := p.distance_squared_to(lake[0])
		if gap < (r + 12.0) * (r + 12.0): mask = minf(mask, smoothstep(r, r + 12.0, sqrt(gap)))
	return mask

static func relief(x: float, z: float, river_distance: float = -1.0) -> float:
	var mask := relief_mask(x, z, river_distance)
	if mask <= 0.0: return 0.0
	var n := relief_noise(x, z) + 0.6
	# Baixadas rasas (o mar fica a -1,1 m embaixo de tudo) e colinas mais altas.
	return mask * (0.7 * n + (1.8 * n * n if n > 0.0 else 0.0))

static func water_at(x: float, z: float, wet: float) -> Dictionary:
	var result := {}
	if coast_height(x, z) < -1.1: result = {"surface": -1.1, "fresh": false}
	var river := river_sample(x, z)
	var width := float(Data.world().get("hydrology", {}).get("river", {}).get("width", 9)) * sqrt(1.0 + wet * 0.575)
	if result.is_empty() and float(river.distance) < width: result = {"surface": float(river.level) + wet * 1.15, "fresh": true}
	for b in basins():
		var state := basin_state(b, wet)
		if float(state.radius) > 0.0 and Vector2(x - float(b.x), z - float(b.z)).length() < float(state.radius):
			if result.is_empty() or float(state.surface) > float(result.surface): result = {"surface": state.surface, "fresh": true}
	return result
