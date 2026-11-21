extends Node3D
const Hydro = preload("res://scripts/survival/hydrology.gd")
const Lake = preload("res://scripts/survival/lake_water.gd")
const Hitbox = preload("res://scripts/net/hitbox.gd")
var wet := -1.0
var _basins: Array = []
var _river: MeshInstance3D
var _material: ShaderMaterial

func _ready() -> void:
	name = "IslandWater"
	_material = Lake.material()
	var ocean := MeshInstance3D.new()
	ocean.name = "Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	ocean.mesh = plane
	ocean.position.y = -1.1
	var sea := Lake.material()
	sea.shader = load("res://scripts/survival/ocean_water.gdshader")
	ocean.material_override = sea
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ocean)
	_river = MeshInstance3D.new()
	_river.name = "RioDasPedras"
	var flowing := ShaderMaterial.new()
	flowing.shader = sea.shader
	flowing.set_shader_parameter("deep_color", Color("#154c53"))
	flowing.set_shader_parameter("shallow_color", Color("#4a807c"))
	_river.material_override = flowing
	_river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_river)
	var disk := Lake.mesh()
	for b in Hydro.basins():
		var water := MeshInstance3D.new()
		water.name = "TemporaryLake" if b.get("temporary", false) else "Lake"
		water.mesh = disk
		water.material_override = _material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		_basins.append({"data": b, "node": water})
	_bridges()
	apply_wetness(0.0)

func apply_wetness(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if absf(value - wet) < 0.002: return
	wet = value
	for entry in _basins:
		var state := Hydro.basin_state(entry.data, wet)
		var water: MeshInstance3D = entry.node
		water.visible = float(state.radius) > 0.1
		water.position = Vector3(float(entry.data.x), float(state.surface), float(entry.data.z))
		water.scale = Vector3(maxf(0.01, float(state.radius)), 1, maxf(0.01, float(state.radius)))
	_river.mesh = _river_mesh()

func _river_mesh() -> ArrayMesh:
	var points: Array = Hydro.Data.world().hydrology.river.points
	var width := float(Hydro.Data.world().hydrology.river.width) * sqrt(1.0 + wet * 0.575)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size() - 1:
		var a := Vector2(float(points[i][0]), float(points[i][1]))
		var b := Vector2(float(points[i+1][0]), float(points[i+1][1]))
		var direction := (b - a).normalized()
		var side := Vector2(-direction.y, direction.x) * width
		var steps := maxi(1, int(ceil(a.distance_to(b) / 5.0)))
		for step in steps:
			var t0 := float(step) / steps
			var t1 := float(step+1) / steps
			var middle := a.lerp(b, (t0+t1)*0.5)
			if Hydro.coast_height(middle.x,middle.y) < -1.1: continue
			var corners: Array[Vector3] = []
			for spec in [[t0, -1.0], [t0, 1.0], [t1, -1.0], [t1, 1.0]]:
				var t: float = spec[0]
				var p := a.lerp(b, t) + side * float(spec[1])
				var y := -0.45 - 0.65 * (i + t) / (points.size()-1) + wet * 1.15
				corners.append(Vector3(p.x, y + 0.012, p.y))
			for index in [0, 2, 1, 1, 2, 3]:
				var p := corners[index]
				tool.set_normal(Vector3.UP)
				tool.set_uv(Vector2(p.x, p.z) * 0.06)
				tool.add_vertex(p)
	# Circular joins close the outside of each bend and match the capsule query.
	for i in points.size():
		var center := Vector3(float(points[i][0]), -0.45 - 0.65 * i / (points.size()-1) + wet * 1.15 + 0.013, float(points[i][1]))
		if Hydro.coast_height(center.x,center.z) < -1.1: continue
		for segment in 24:
			var a := TAU * float(segment) / 24.0
			var b := TAU * float(segment+1) / 24.0
			for p in [center, center + Vector3(cos(b),0,sin(b))*width, center + Vector3(cos(a),0,sin(a))*width]:
				tool.set_normal(Vector3.UP)
				tool.set_uv(Vector2(p.x,p.z)*0.06)
				tool.add_vertex(p)
	return tool.commit()

func _bridges() -> void:
	var points: Array = Hydro.Data.world().hydrology.river.points
	var bridge_index := 0
	for road in Hydro.Data.world().get("roads", []):
		var a := Vector2(float(road.from[0]), float(road.from[1]))
		var b := Vector2(float(road.to[0]), float(road.to[1]))
		for i in points.size()-1:
			var c := Vector2(float(points[i][0]), float(points[i][1]))
			var d := Vector2(float(points[i+1][0]), float(points[i+1][1]))
			var crossing = Geometry2D.segment_intersects_segment(a, b, c, d)
			if crossing == null: continue
			var direction := (b - a).normalized()
			var span := 30.0 / maxf(0.2, absf(direction.cross((d-c).normalized())))
			span = minf(span, a.distance_to(b))
			var body := StaticBody3D.new()
			bridge_index += 1
			body.name = "RiverBridge_%d" % bridge_index
			body.collision_layer = Hitbox.LAYER_WORLD
			body.position = Vector3(crossing.x, -0.135, crossing.y) # deck top at 0.04, flush with the road
			body.rotation.y = atan2(direction.x, direction.y)
			var box := BoxMesh.new()
			box.size = Vector3(float(road.get("width", 6)) + 0.5, 0.35, span)
			var mesh := MeshInstance3D.new()
			mesh.mesh = box
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("#77766b")
			mesh.material_override = mat
			body.add_child(mesh)
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			collision.shape = shape
			body.add_child(collision)
			var rail_mat := StandardMaterial3D.new()
			rail_mat.albedo_color = Color("#58645f")
			rail_mat.roughness = 0.7
			for side in [-1.0, 1.0]:
				var x: float = side * (box.size.x * 0.5 - 0.08)
				var rail := MeshInstance3D.new()
				var rail_box := BoxMesh.new()
				rail_box.size = Vector3(0.12, 0.12, span)
				rail.mesh = rail_box
				rail.material_override = rail_mat
				rail.position = Vector3(x, 1.1, 0)
				body.add_child(rail)
				var rail_collision := CollisionShape3D.new()
				var rail_shape := BoxShape3D.new()
				rail_shape.size = Vector3(0.12, 1.0, span)
				rail_collision.shape = rail_shape
				rail_collision.position = Vector3(x, 0.65, 0)
				body.add_child(rail_collision)
				for post_index in maxi(2, int(span / 4.0) + 1):
					var post := MeshInstance3D.new()
					var post_box := BoxMesh.new()
					post_box.size = Vector3(0.14, 1.0, 0.14)
					post.mesh = post_box
					post.material_override = rail_mat
					post.position = Vector3(x, 0.65, -span * 0.5 + post_index * span / maxi(1, int(span/4.0)))
					body.add_child(post)
				for z in [-span * 0.28, span * 0.28]:
					var pier := MeshInstance3D.new()
					var pier_box := BoxMesh.new()
					pier_box.size = Vector3(0.45, 3.0, 0.6)
					pier.mesh = pier_box
					pier.material_override = mat
					pier.position = Vector3(side * (box.size.x * 0.5 - 0.4), -1.5, z)
					body.add_child(pier)
			add_child(body)
