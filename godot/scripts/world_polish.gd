extends Node3D
## One authored 120 m neighborhood. Roads, plots and entrances share one layout.
const SurfaceMaterials = preload("res://scripts/surface_materials.gd")
const ParkourDistrictScript = preload("res://scripts/parkour_district.gd")
## Metade do mapa com o bairro de parkour (só no treino offline).
const MAP_HALF := 100.0
## Treino offline: bairro de parkour em volta da cidade (mapa de 200 m).
## Mata-mata, equipes e sala personalizada ficam no mapa de 120 m.
var parkour_district := false
## Metade do mapa fechado, onde ficam os muros da borda.
var map_half := 60.0
var mat_cache: Dictionary = {}
## Sobrevivência: a cidade fica no meio do mundo aberto, sem os muros da borda.
var open_world := false

func _ready() -> void:
    if parkour_district and not open_world:
        map_half = MAP_HALF
    _tune_environment()
    _streets()
    _residential()
    _commercial()
    _industrial()
    _parks()
    _watchtower()
    _cover_walls()
    _perimeter()
    if not open_world:
        # Bases de parkour na faixa entre o anel e o muro (todos os modos da
        # cidade); o bairro com os sobrados só no treino offline.
        var district := ParkourDistrictScript.new()
        district.set("full", parkour_district)
        add_child(district)

func _mat(hex_color: String) -> StandardMaterial3D:
    if mat_cache.has(hex_color):
        return mat_cache[hex_color]
    var kinds := {
        "#414950": "asphalt", "#495057": "asphalt", "#6f7472": "asphalt",
        "#a9aaa1": "concrete", "#bcb8a5": "concrete", "#a99f88": "concrete",
        "#b4ae9c": "concrete", "#a49e8c": "concrete", "#719168": "grass",
        "#535b5b": "roof", "#68503c": "bark", "#487347": "leaf",
        "#7e684b": "wood", "#7c6c54": "wood", "#8b765b": "wood",
        "#58646a": "metal", "#3b4949": "metal", "#344747": "metal",
        "#dbcb96": "paint", "#dfdfd4": "paint", "#ded8bd": "paint", "#d4d0bd": "paint"
    }
    var material: StandardMaterial3D
    if hex_color == "#587985":
        material = StandardMaterial3D.new()
        material.albedo_color = Color(hex_color)
        material.roughness = 0.25
        material.metallic = 0.15
    else:
        material = SurfaceMaterials.make(kinds.get(hex_color, "plaster"), Color(hex_color))
    mat_cache[hex_color] = material
    return material

func _box(pos: Vector3, size: Vector3, color: String, solid: bool = false, parent: Node3D = null) -> Node3D:
    var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
    body.position = pos
    (self if parent == null else parent).add_child(body)
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.material_override = _mat(color)
    body.add_child(instance)
    if solid:
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        body.add_child(collider)
    return body

func _surface(center: Vector2, size: Vector2, color: String, top: float = 0.025) -> void:
    # Pavement and grass must support the player at their visible height.
    # Road markings remain cosmetic overlays, without redundant colliders.
    var solid := color not in ["#dbcb96", "#dfdfd4", "#ded8bd"]
    _box(Vector3(center.x, top - 0.01, center.y), Vector3(size.x, 0.02, size.y), color, solid)

func _tune_environment() -> void:
    var existing := get_parent().get_node("WorldEnvironment") as WorldEnvironment
    var env := existing.environment
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color("#326787")
    sky_material.sky_horizon_color = Color("#9aafb0")
    sky_material.ground_bottom_color = Color("#354537")
    sky_material.ground_horizon_color = Color("#929e94")
    sky_material.sky_energy_multiplier = 0.75
    sky_material.ground_energy_multiplier = 0.55
    sky_material.sun_angle_max = 2.0
    var sky := Sky.new()
    sky.sky_material = sky_material
    sky.radiance_size = Sky.RADIANCE_SIZE_128
    env.sky = sky
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#a6b4bd")
    env.ambient_light_energy = 0.30
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.tonemap_exposure = 0.95
    env.fog_enabled = true
    env.fog_light_color = Color("#879d9e")
    env.fog_density = 0.0015
    var sun := get_parent().get_node("Sun") as DirectionalLight3D
    sun.light_energy = 0.85
    sun.light_color = Color("#fff1dc")
    sun.directional_shadow_max_distance = 90.0

func _streets() -> void:
    # Ring and central cross use adjacent tiles, never coplanar overlapping slabs.
    for x in [-48, 0, 48]:
        for z in [-48, 0, 48]:
            _surface(Vector2(x, z), Vector2(8, 8), "#414950")
    for middle in [-24, 24]:
        for lane in [-48, 0, 48]:
            _surface(Vector2(lane, middle), Vector2(8, 40), "#414950")
            _surface(Vector2(middle, lane), Vector2(40, 8), "#414950")
    # Frontage streets serve the houses and storefronts on the west side.
    for z in [-24, 28]:
        _surface(Vector2(-24, z), Vector2(40, 4), "#495057")
    for lane in [-48, 0, 48]:
        for side in [-1, 1]:
            for middle in [-24, 24]:
                # Sidewalk strips stop at crossings and local-street mouths.
                for interval in [[-44.0, -27.0], [-21.0, -4.0], [4.0, 25.0], [31.0, 44.0]]:
                    if middle == -24 and float(interval[0]) > 0 or middle == 24 and float(interval[0]) < 0:
                        continue
                    var start: float = interval[0]
                    var finish: float = interval[1]
                    _surface(Vector2(lane + side * 5.0, (start + finish) * 0.5), Vector2(2, finish - start), "#a9aaa1", 0.04)
                _surface(Vector2(middle, lane + side * 5.0), Vector2(40, 2), "#a9aaa1", 0.04)
        for along in range(-40, 41, 6):
            if abs(along) < 7:
                continue
            _surface(Vector2(lane, along), Vector2(0.12, 2.2), "#dbcb96", 0.032)
            _surface(Vector2(along, lane), Vector2(2.2, 0.12), "#dbcb96", 0.032)
    for offset in range(-3, 4):
        for side in [-1.0, 1.0]:
            _surface(Vector2(offset, side * 7), Vector2(0.55, 2), "#dfdfd4", 0.034)
            _surface(Vector2(side * 7, offset), Vector2(2, 0.55), "#dfdfd4", 0.034)

func _building(title: String, center: Vector2, size: Vector2, height: float, color: String) -> Node3D:
    var building := Node3D.new()
    building.name = title.replace(" ", "_")
    building.position = Vector3(center.x, 0, center.y)
    add_child(building)
    building.add_to_group("map_building")
    building.set_meta("entrance", Vector3(center.x, 0, center.y + size.y * 0.5))
    var width := size.x
    var depth := size.y
    _box(Vector3(0, height * 0.5, -depth * 0.5), Vector3(width, height, 0.25), color, true, building)
    for side in [-1.0, 1.0]:
        _box(Vector3(side * width * 0.5, height * 0.5, 0), Vector3(0.25, height, depth), color, true, building)
        _box(Vector3(side * (width + 2) * 0.25, height * 0.5, depth * 0.5), Vector3((width - 2) * 0.5, height, 0.25), color, true, building)
        _box(Vector3(side * width * 0.30, 1.7, depth * 0.5 + 0.14), Vector3(1.5, 1.15, 0.035), "#587985", false, building)
        _box(Vector3(side * width * 0.30, 1.7, depth * 0.5 + 0.17), Vector3(0.055, 1.2, 0.025), "#d4d0bd", false, building)
    _box(Vector3(0, (height + 2.5) * 0.5, depth * 0.5), Vector3(2, height - 2.5, 0.25), color, true, building)
    _box(Vector3(0, height + 0.06, 0), Vector3(width + 0.55, 0.22, depth + 0.55), "#535b5b", true, building)
    _box(Vector3(0, 0.005, 0), Vector3(width - 0.3, 0.02, depth - 0.3), "#a49e8c", false, building)
    # Sign is fixed to the lintel, with the doorway open underneath.
    _box(Vector3(0, 2.9, depth * 0.5 + 0.18), Vector3(minf(width - 1, 5), 0.45, 0.12), "#344747", false, building)
    var label := Label3D.new()
    label.text = title
    label.font_size = 42
    label.pixel_size = 0.006
    label.position = Vector3(0, 2.9, depth * 0.5 + 0.25)
    label.modulate = Color("#eee5c7")
    building.add_child(label)
    return building

func _residential() -> void:
    var colors := ["#c7b596", "#acb6af", "#cabd9f", "#a2acb4"]
    var index := 0
    for z in [-34, -16]:
        for x in [-34, -16]:
            _building("CASA %02d" % (index + 1), Vector2(x, z), Vector2(10, 10), 3.5, colors[index])
            var front: float = z + 5.0
            var end := -26.0 if z == -34 else -6.0
            _surface(Vector2(x, (front + end) * 0.5), Vector2(2, end - front), "#bcb8a5", 0.035)
            index += 1
    for x in [-40, -10]:
        _tree(Vector2(x, -38), 2.8)
        _tree(Vector2(x, -12), 2.7)

func _commercial() -> void:
    _building("MERCADO", Vector2(-34, 16), Vector2(12, 10), 3.8, "#c5bba3")
    _building("OFICINA", Vector2(-16, 16), Vector2(10, 10), 3.8, "#9ca9ab")
    for x in [-34, -16]:
        _surface(Vector2(x, 23.5), Vector2(4, 5), "#bcb8a5", 0.035)
    _surface(Vector2(-25, 37), Vector2(30, 10), "#a99f88", 0.03)
    for x in [-36, -14]:
        _bench(Vector2(x, 38))
        _tree(Vector2(x, 42), 2.9)
    # Workshop stock is in its own interior, not scattered in public streets.
    _box(Vector3(-19, 0.6, 14), Vector3(1.6, 1.2, 1.3), "#7c6c54", true)
    _box(Vector3(-13, 0.9, 12), Vector3(1.6, 1.8, 1.1), "#58646a", true)

func _industrial() -> void:
    _building("GALPAO", Vector2(32, -32), Vector2(20, 16), 5.5, "#9ba8a5")
    _building("ESCRITORIO", Vector2(14, -38), Vector2(8, 8), 3.5, "#bfb7a3")
    _surface(Vector2(32, -14), Vector2(8, 20), "#6f7472")
    _surface(Vector2(14, -27), Vector2(2, 14), "#bcb8a5", 0.035)
    _surface(Vector2(22, -20), Vector2(18, 2), "#bcb8a5", 0.035)
    _surface(Vector2(40, -12), Vector2(8, 12), "#6f7472")
    for z in [-16, -12, -8]:
        _surface(Vector2(40, z), Vector2(7, 0.10), "#ded8bd", 0.033)
    for x in [27, 37]:
        for z in [-36, -32]:
            _box(Vector3(x, 0.75, z), Vector3(2.2, 1.5, 2), "#8b765b", true)
    # Initial plaza has clear pedestrian access to the central avenues.
    _surface(Vector2(12, -10), Vector2(12, 12), "#b4ae9c", 0.035)
    _surface(Vector2(5, -10), Vector2(2, 2), "#b4ae9c", 0.035)
    _bench(Vector2(12, -15))
    _tree(Vector2(20, -16), 3.0)

func _bench(center: Vector2) -> void:
    _box(Vector3(center.x, 0.52, center.y), Vector3(2, 0.14, 0.6), "#7e684b", true)
    _box(Vector3(center.x, 0.94, center.y + 0.26), Vector3(2, 0.75, 0.12), "#7e684b", true)
    for side in [-1.0, 1.0]:
        _box(Vector3(center.x + side * 0.72, 0.23, center.y), Vector3(0.12, 0.46, 0.5), "#3b4949")

func _tree(center: Vector2, height: float) -> void:
    var body := StaticBody3D.new()
    body.position = Vector3(center.x, 0, center.y)
    add_child(body)
    var mesh := MeshInstance3D.new()
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.12
    trunk.bottom_radius = 0.20
    trunk.height = height
    trunk.radial_segments = 8
    mesh.mesh = trunk
    mesh.position.y = height * 0.5
    mesh.material_override = _mat("#68503c")
    body.add_child(mesh)
    var collider := CollisionShape3D.new()
    var shape := CylinderShape3D.new()
    shape.radius = 0.2
    shape.height = height
    collider.shape = shape
    collider.position.y = height * 0.5
    body.add_child(collider)
    var crown := MeshInstance3D.new()
    var leaves := SphereMesh.new()
    leaves.radius = 1.35
    leaves.height = 2.5
    leaves.radial_segments = 10
    leaves.rings = 5
    crown.mesh = leaves
    crown.position.y = height + 0.45
    crown.material_override = _mat("#487347")
    body.add_child(crown)

func _parks() -> void:
    _surface(Vector2(24, 24), Vector2(36, 36), "#719168", 0.03)
    _surface(Vector2(24, 24), Vector2(2.5, 36), "#b4ae9c", 0.04)
    _surface(Vector2(14.375, 24), Vector2(16.75, 2.5), "#b4ae9c", 0.04)
    _surface(Vector2(33.625, 24), Vector2(16.75, 2.5), "#b4ae9c", 0.04)
    for x in [10, 18, 30, 38]:
        for z in [10, 38]:
            _tree(Vector2(x, z), 2.8 + x * 0.012)
    for z in [16, 32]:
        _bench(Vector2(18, z))
        _bench(Vector2(30, z))
    _surface(Vector2(24, 5), Vector2(2.5, 2), "#b4ae9c", 0.04)
    _surface(Vector2(5, 24), Vector2(2, 2.5), "#b4ae9c", 0.04)

## Watchtower at the east edge of the park: a 5 x 5 m platform 6 m up with a
## parapet, reached by a 12 m walkable ramp (26.6°) from the west. The sniper
## crate sits on the roof (data/match_layout.json "tower"; tests/tower_climb.gd).
const TOWER_CENTER := Vector2(40, 18)
const TOWER_HEIGHT := 6.0
const TOWER_SIZE := 5.0
const RAMP_RUN := 12.0
const RAMP_WIDTH := 2.5

func _watchtower() -> void:
    var tower := Node3D.new()
    tower.name = "Watchtower"
    tower.add_to_group("watchtower")
    add_child(tower)
    var c := TOWER_CENTER
    var half := TOWER_SIZE * 0.5
    var top := TOWER_HEIGHT
    var concrete := "#a9aaa1"
    var steel := "#58646a"
    # Platform (walk surface exactly at `top`) and four corner pillars.
    _box(Vector3(c.x, top - 0.15, c.y), Vector3(TOWER_SIZE, 0.3, TOWER_SIZE), concrete, true, tower)
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            _box(Vector3(c.x + sx * (half - 0.3), (top - 0.3) * 0.5, c.y + sz * (half - 0.3)), Vector3(0.4, top - 0.3, 0.4), steel, true, tower)
    # Parapet (1.1 m): cover for the sniper; open on the west where the ramp arrives.
    var wall_h := 1.1
    var y := top + wall_h * 0.5
    _box(Vector3(c.x, y, c.y - half + 0.1), Vector3(TOWER_SIZE, wall_h, 0.2), concrete, true, tower)
    _box(Vector3(c.x, y, c.y + half - 0.1), Vector3(TOWER_SIZE, wall_h, 0.2), concrete, true, tower)
    _box(Vector3(c.x + half - 0.1, y, c.y), Vector3(0.2, wall_h, TOWER_SIZE), concrete, true, tower)
    var gap := RAMP_WIDTH * 0.5 + 0.05
    var side_len := half - gap
    for sz in [-1.0, 1.0]:
        _box(Vector3(c.x - half + 0.1, y, c.y + sz * (gap + side_len * 0.5)), Vector3(0.2, wall_h, side_len), concrete, true, tower)
    # Ramp: its top surface runs from the ground at the west to the platform edge.
    var thickness := 0.3
    var angle := atan2(top, RAMP_RUN)
    var along := Vector3(cos(angle), sin(angle), 0)
    var normal := Vector3(-sin(angle), cos(angle), 0)
    var start := Vector3(c.x - half - RAMP_RUN, 0, c.y) # bottom of the walk surface
    var length := Vector2(RAMP_RUN, top).length()
    var extra := 0.5 # dug into the ground at the bottom end
    var mid := start + along * (length - extra) * 0.5 - normal * (thickness * 0.5)
    var ramp := _box(mid, Vector3(length + extra, thickness, RAMP_WIDTH), "#8f918a", true, tower)
    ramp.name = "TowerRamp"
    ramp.rotation.z = angle
    # Railings start 1 m up the ramp: a rail end at ground level snagged walkers.
    var rail_from := 1.0
    var rail_mid := start + along * (length + rail_from) * 0.5 + normal * 0.5
    for sz in [-1.0, 1.0]:
        var rail := _box(rail_mid + Vector3(0, 0, sz * (RAMP_WIDTH * 0.5 + 0.06)), Vector3(length - rail_from, 1.0, 0.1), steel, true, tower)
        rail.rotation.z = angle
    var tower_sign := Label3D.new()
    tower_sign.text = "TORRE"
    tower_sign.font_size = 48
    tower_sign.pixel_size = 0.006
    tower_sign.modulate = Color("#eee5c7")
    tower_sign.position = Vector3(c.x - half - 0.05, top - 0.9, c.y)
    tower_sign.rotation.y = -PI * 0.5
    tower.add_child(tower_sign)

## Concrete cover in the open areas: low walls (1.2 m, cover when crouched,
## shoot over them) and tall walls (2.2 m, full cover). All stay clear of the
## main avenues, doorways, loot spots and medkits (tests/map_layout.gd and
## tests/match_layout.gd check roads, entrances and crate spots).
const COVER_WALLS := [
    # [x, z, length, along_x, height]
    # Houses (north-west): between the rows and toward the avenue.
    [-25.0, -34.0, 4.0, false, 2.2], [-25.0, -16.0, 3.5, false, 1.2], [-25.0, -7.0, 4.0, true, 1.2], [-7.0, -34.0, 4.0, false, 1.2],
    # Market / workshop (south-west): gap between the shops, front yards, plaza.
    [-24.5, 13.0, 4.0, false, 2.2], [-34.0, 7.5, 4.0, true, 1.2], [-16.0, 7.5, 4.0, true, 1.2], [-31.0, 34.5, 3.5, true, 1.2], [-19.0, 39.5, 3.5, true, 1.2],
    # Park (south-east).
    [12.0, 18.0, 4.0, false, 1.2], [36.0, 30.0, 4.0, false, 1.2], [20.0, 28.5, 3.5, true, 2.2],
    # Industrial (north-east): parking lot, beside the plaza, west of the office.
    [32.0, -12.0, 3.5, true, 1.2], [24.0, -10.0, 3.5, false, 2.2], [6.5, -28.0, 4.0, false, 1.2],
]

func _cover_walls() -> void:
    for spec in COVER_WALLS:
        var length: float = spec[2]
        var height: float = spec[4]
        var thickness := 0.45
        var size := Vector3(length, height, thickness) if spec[3] else Vector3(thickness, height, length)
        var wall := _box(Vector3(spec[0], height * 0.5, spec[1]), size, "#a9aaa1", true)
        wall.name = "CoverWall"
        wall.add_to_group("cover_wall")
        # Darker coping on top so the wall reads at a distance.
        _box(Vector3(0, height * 0.5 + 0.04, 0), size + Vector3(0.08, -height + 0.08, 0.08), "#7d7f78", false, wall)

func _perimeter() -> void:
    # Planted border follows the ring road; no random blocks inside plots.
    for coordinate in range(-54, 55, 12):
        _tree(Vector2(coordinate, -56), 3.4)
        _tree(Vector2(coordinate, 56), 3.4)
        if abs(coordinate) < 50:
            _tree(Vector2(-56, coordinate), 3.4)
            _tree(Vector2(56, coordinate), 3.4)
    if not open_world:
        _boundary_walls()

func _boundary_walls() -> void:
    # The ground ends at +/-map_half (60, or 100 with the parkour district):
    # a visible 3 m concrete wall on every edge, plus a tall invisible barrier
    # so nobody can jump or climb out (parkour roofs reach 7 m, barrier 30 m).
    var half := map_half - 0.4
    var thickness := 0.8
    for side in [-1.0, 1.0]:
        _box(Vector3(side * half, 1.5, 0), Vector3(thickness, 3.0, half * 2 + thickness), "#9a9a92", true)
        _box(Vector3(0, 1.5, side * half), Vector3(half * 2 + thickness, 3.0, thickness), "#9a9a92", true)
        for along in [Vector3(side * half, 15.0, 0), Vector3(0, 15.0, side * half)]:
            var barrier := StaticBody3D.new()
            barrier.name = "EdgeBarrier"
            barrier.position = along
            add_child(barrier)
            var collider := CollisionShape3D.new()
            var shape := BoxShape3D.new()
            shape.size = Vector3(thickness, 30.0, half * 2 + thickness) if absf(along.x) > 1.0 else Vector3(half * 2 + thickness, 30.0, thickness)
            collider.shape = shape
            barrier.add_child(collider)
