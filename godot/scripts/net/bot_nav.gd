extends RefCounted
## Walkable grid for bots, built once per map from the real collision
## (buildings, crates, benches, trees, barriers) and searched with AStarGrid2D.
## Replaces the old door/road heuristics, which walked bots into walls when the
## straight line was blocked (inside the GALPAO behind its crates, or around
## the building to reach something behind it).
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const CELL := 0.5
# Bot capsule radius is 0.34; a 1 m probe per 0.5 m cell keeps 0.25 m of
# clearance and still leaves two free columns in every 2 m doorway.
const PROBE_HALF := 0.5
const PROBE_LOW := 0.3 # ignore kerbs and floor slabs
const PROBE_HIGH := 1.7

static var _grid: AStarGrid2D
static var _world_id := 0
static var _half := 60
static var _half_x := 60.0 # mapas retangulares (Equipes): limites reais de cada eixo
static var _half_z := 60.0

## Forget the grid: the scenes share the root World3D, so a new map (match_map.gd)
## must not reuse the previous map's grid.
static func reset() -> void:
	_grid = null
	_world_id = 0

## Grid for this world, built on first use.
static func grid_for(world: World3D) -> AStarGrid2D:
	if _grid != null and _world_id == world.get_instance_id():
		return _grid
	var layout := MatchLayout.load_layout()
	_half = int(ceil(float(layout.get("map_half_size", 60))))
	_half_x = float(layout.get("half_x", _half))
	_half_z = float(layout.get("half_z", _half))
	var cells := int(_half * 2 / CELL)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, cells, cells)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var space := world.direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(PROBE_HALF * 2.0, PROBE_HIGH - PROBE_LOW, PROBE_HALF * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = HitboxScript.LAYER_WORLD
	var solid := 0
	for x in cells:
		for z in cells:
			var center := cell_center(Vector2i(x, z))
			query.transform = Transform3D(Basis.IDENTITY, Vector3(center.x, (PROBE_LOW + PROBE_HIGH) * 0.5, center.z))
			if not space.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(Vector2i(x, z), true)
				solid += 1
	# Sem nenhuma parede = a fÃ­sica ainda nÃ£o registrou o mapa (montado neste mesmo
	# frame). NÃ£o guarda essa grade vazia: a prÃ³xima chamada monta de novo. Antes ela
	# ficava a partida inteira e os bots traÃ§avam rotas atravessando casas e muretas.
	if solid == 0:
		return grid
	_grid = grid
	_world_id = world.get_instance_id()
	return _grid

## JÃ¡ existe uma grade vÃ¡lida (com paredes) para este mundo?
static func ready_for(world: World3D) -> bool:
	return _grid != null and _world_id == world.get_instance_id()

static func cell_of(point: Vector3) -> Vector2i:
	var cells := int(_half * 2 / CELL)
	return Vector2i(clampi(int(floor((point.x + _half) / CELL)), 0, cells - 1), clampi(int(floor((point.z + _half) / CELL)), 0, cells - 1))

static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(-_half + (cell.x + 0.5) * CELL, 0, -_half + (cell.y + 0.5) * CELL)

## Nearest walkable cell (spiral search), for goals inside a crate or a bot
## pressed against a wall.
static func free_cell(grid: AStarGrid2D, cell: Vector2i) -> Vector2i:
	if not grid.is_point_solid(cell):
		return cell
	for radius in range(1, 8):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue # ring only
				var candidate := Vector2i(cell.x + dx, cell.y + dz)
				if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate):
					return candidate
	return cell

## Random walkable spot anywhere on the map (for roaming bots).
static func random_point(world: World3D) -> Vector3:
	var grid := grid_for(world)
	var size := grid.region.size
	for attempt in 40:
		var cell := Vector2i(randi() % size.x, randi() % size.y)
		var center := cell_center(cell)
		# Stay a few metres inside the boundary walls.
		if absf(center.x) > _half_x - 4 or absf(center.z) > _half_z - 4:
			continue
		if not grid.is_point_solid(cell):
			return center
	return Vector3.ZERO

## Path from `from` to `to` as world points (ground level), or [] when unreachable.
static func path(world: World3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var grid := grid_for(world)
	var start := free_cell(grid, cell_of(from))
	var goal := free_cell(grid, cell_of(to))
	var result := PackedVector3Array()
	if grid.is_point_solid(start) or grid.is_point_solid(goal):
		return result
	for cell in grid.get_id_path(start, goal, true):
		result.append(cell_center(cell))
	return result
