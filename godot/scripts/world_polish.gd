extends Node3D
## One authored 120 m neighborhood. Roads, plots and entrances share one layout.
var mat_cache: Dictionary = {}

func _ready() -> void:
    _tune_environment()
    _streets()
    _residential()
    _commercial()
    _industrial()
    _parks()
    _perimeter()

func _mat(hex_color: String) -> StandardMaterial3D:
    if not mat_cache.has(hex_color):
        var material := StandardMaterial3D.new()
        material.albedo_color = Color(hex_color)
        material.roughness = 0.92
        mat_cache[hex_color] = material
    return mat_cache[hex_color]

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
    _box(Vector3(center.x, top - 0.01, center.y), Vector3(size.x, 0.02, size.y), color)

func _tune_environment() -> void:
    var existing := get_parent().get_node("WorldEnvironment") as WorldEnvironment
    var env := existing.environment
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#89b6d1")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#b9c5c0")
    env.ambient_light_energy = 0.65
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#a7bdc1")
    env.fog_density = 0.004

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

func _perimeter() -> void:
    # Planted border follows the ring road; no random blocks inside plots.
    for coordinate in range(-54, 55, 12):
        _tree(Vector2(coordinate, -56), 3.4)
        _tree(Vector2(coordinate, 56), 3.4)
        if abs(coordinate) < 50:
            _tree(Vector2(-56, coordinate), 3.4)
            _tree(Vector2(56, coordinate), 3.4)
