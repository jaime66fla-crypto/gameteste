extends Node3D
## Campo de Fogo - visual polish module for the Godot 4 prototype.
## Deterministic decoration, no external assets, no changes to combat or player physics.
const SEED_VALUE := 20261114
var rng := RandomNumberGenerator.new()
var mat_cache: Dictionary = {}

func _ready() -> void:
    rng.seed = SEED_VALUE
    _tune_environment()
    _roads()
    _landmarks()
    _vegetation()
    _rocks()

func _tune_environment() -> void:
    var existing := get_parent().get_node_or_null("WorldEnvironment")
    if existing == null:
        existing = WorldEnvironment.new()
        existing.name = "WorldEnvironment"
        get_parent().add_child(existing)
    var env: Environment = existing.environment
    if env == null:
        env = Environment.new()
        existing.environment = env
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#89b6d1")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#b9c5c0")
    env.ambient_light_energy = 0.65
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = Color("#a7bdc1")
    env.fog_density = 0.008
    var sun := DirectionalLight3D.new()
    sun.name = "WarmFillLight"
    sun.rotation_degrees = Vector3(-32, 132, 0)
    sun.light_color = Color("#ffe1a9")
    sun.light_energy = 0.35
    sun.shadow_enabled = false
    add_child(sun)

func _mat(hex_color: String, roughness: float = 0.9) -> StandardMaterial3D:
    if mat_cache.has(hex_color):
        return mat_cache[hex_color]
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(hex_color)
    mat.roughness = roughness
    mat_cache[hex_color] = mat
    return mat

func _box(pos: Vector3, size: Vector3, material: Material, solid: bool = false) -> Node3D:
    var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
    root.position = pos
    add_child(root)
    var mesh := MeshInstance3D.new()
    var cube := BoxMesh.new()
    cube.size = size
    mesh.mesh = cube
    mesh.material_override = material
    root.add_child(mesh)
    if solid:
        var collider := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collider.shape = shape
        root.add_child(collider)
    return root

func _cylinder(pos: Vector3, radius: float, height: float, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    var shape := CylinderMesh.new()
    shape.top_radius = radius * 0.82
    shape.bottom_radius = radius
    shape.height = height
    shape.radial_segments = 7
    mesh.mesh = shape
    mesh.position = pos
    mesh.material_override = material
    add_child(mesh)

func _roads() -> void:
    var asphalt := _mat("#414950")
    var line := _mat("#dfc58a")
    # Slight elevation separation avoids z-fighting / stripe artifacts.
    # Horizontal road ends flush with its crossing; vertical road is a single higher surface.
    _box(Vector3(0, 0.04, 18), Vector3(110, 0.08, 7), asphalt)
    _box(Vector3(18, 0.09, 0), Vector3(7, 0.08, 110), asphalt)
    for i in range(-10, 11):
        if absf(i * 5.0 - 18.0) > 5.0:
            _box(Vector3(i * 5.0, 0.10, 18), Vector3(2.1, 0.018, 0.12), line)
        if absf(i * 5.0 - 18.0) > 5.0:
            _box(Vector3(18, 0.15, i * 5.0), Vector3(0.12, 0.018, 2.1), line)

func _landmarks() -> void:
    # A few recognizable zones, leaving the spawn and main crossing unobstructed.
    var walls := ["#a4a091", "#9e8971", "#79848a", "#bdab92"]
    for i in range(12):
        var x := -42.0 + float(i % 4) * 8.0
        var z := -42.0 + float(i / 4) * 9.0
        var height := rng.randf_range(3.2, 7.0)
        _box(Vector3(x, height / 2.0, z), Vector3(5.0, height, 5.2), _mat(walls[i % walls.size()]), true)
        _box(Vector3(x, height + 0.2, z), Vector3(5.5, 0.3, 5.7), _mat("#4a4a49"))
        for floor_index in range(1, 3):
            if height > float(floor_index) * 2.1 + 0.6:
                _box(Vector3(x, float(floor_index) * 2.1, z + 2.64), Vector3(1.1, 1.15, 0.07), _mat("#526d78"))
    for i in range(10):
        var x := 30.0 + float(i % 2) * 6.0
        var z := -38.0 + float(i / 2) * 7.0
        _box(Vector3(x, 0.8, z), Vector3(3, 1.6, 4), _mat("#8b745f"), true)

func _vegetation() -> void:
    var leaves := ["#285c3a", "#3e7140", "#527d3b", "#617c3a"]
    for i in range(90):
        var x := rng.randf_range(-53, 53)
        var z := rng.randf_range(-53, 53)
        # Prevent planting trees in the roads, the spawn zone and building zones.
        if absf(z - 18) < 5 or absf(x - 18) < 5:
            continue
        if absf(x) < 10 and absf(z) < 10:
            continue
        if x < -15 and z < -13:
            continue
        if x > 26 and x < 41 and z < 2:
            continue
        var height := rng.randf_range(2.1, 3.7)
        _cylinder(Vector3(x, height * 0.5, z), 0.19, height, _mat("#5f4935"))
        var foliage := MeshInstance3D.new()
        var crown := SphereMesh.new()
        crown.radius = rng.randf_range(1.05, 1.65)
        crown.height = 2.5
        crown.radial_segments = 8
        crown.rings = 4
        foliage.mesh = crown
        foliage.material_override = _mat(leaves[i % leaves.size()])
        foliage.position = Vector3(x, height + 0.55, z)
        add_child(foliage)

func _rocks() -> void:
    for i in range(35):
        var x := rng.randf_range(-54, 54)
        var z := rng.randf_range(-54, 54)
        if absf(z - 18) < 5 or absf(x - 18) < 5 or (absf(x) < 9 and absf(z) < 9):
            continue
        var scale_factor := rng.randf_range(0.35, 1.15)
        _box(Vector3(x, scale_factor * 0.25, z), Vector3(scale_factor, scale_factor * 0.5, scale_factor * 0.8), _mat("#777d76"))
