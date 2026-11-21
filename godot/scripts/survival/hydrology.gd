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
	height += coast_height(x, z)
	var river := river_sample(x, z)
	var width := float(Data.world().get("hydrology", {}).get("river", {}).get("width", 9))
	if float(river.distance) < width + 13.0:
		height = minf(height, float(river.level) - 2.0 + 2.0 * pow(float(river.distance) / width, 2))
	for b in basins():
		var d := Vector2(x - float(b.x), z - float(b.z)).length() / float(b.r)
		if d < 1.4:
			height = minf(height, (-0.65 if bool(b.get("temporary", false)) else -1.4) + 1.55 * d * d)
	return height

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
