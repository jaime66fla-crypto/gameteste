extends RefCounted
## Lightweight distinctive weapon silhouettes built without external models.
## Replace with imported GLB meshes later; this is the low-poly fallback.
static func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.metallic = metal
    result.roughness = 0.56 if metal > 0.5 else 0.84
    return result

static func _box(parent: Node3D, name: String, pos: Vector3, size: Vector3, material: Material) -> void:
    var mesh := MeshInstance3D.new()
    mesh.name = name
    var shape := BoxMesh.new()
    shape.size = size
    mesh.mesh = shape
    mesh.position = pos
    mesh.material_override = material
    parent.add_child(mesh)

static func _tube(parent: Node3D, name: String, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
    var axis := b - a
    if axis.length() < 0.001:
        return
    var mesh := MeshInstance3D.new()
    mesh.name = name
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = axis.length()
    cylinder.radial_segments = 10
    mesh.mesh = cylinder
    mesh.position = (a + b) * 0.5
    mesh.quaternion = Quaternion(Vector3.UP, axis.normalized())
    mesh.material_override = material
    parent.add_child(mesh)

static func build(parent: Node3D, weapon_id: String) -> float:
    var dark := _material(Color("#171b21"))
    var metal := _material(Color("#505963"), 0.73)
    var polymer := _material(Color("#303941"))
    var olive := _material(Color("#596147"))
    var tan := _material(Color("#846747"))
    var lens := _material(Color("#28556b"), 0.18)
    var end_z := -0.63
    if weapon_id == "pistol":
        _box(parent, "PistolFrame", Vector3(0, 0.0, -0.31), Vector3(0.18, 0.17, 0.47), polymer)
        _box(parent, "MachinedSlide", Vector3(0, 0.11, -0.34), Vector3(0.19, 0.12, 0.49), metal)
        _box(parent, "Grip", Vector3(0, -0.22, -0.13), Vector3(0.135, 0.38, 0.14), dark)
        _box(parent, "TriggerGuard", Vector3(0, -0.115, -0.33), Vector3(0.035, 0.17, 0.24), polymer)
        _box(parent, "FrontSight", Vector3(0, 0.19, -0.54), Vector3(0.08, 0.045, 0.045), dark)
        _box(parent, "RearSight", Vector3(0, 0.19, -0.16), Vector3(0.11, 0.045, 0.045), dark)
        _tube(parent, "Bore", Vector3(0, 0.08, -0.54), Vector3(0, 0.08, -0.66), 0.046, dark)
        end_z = -0.66
    else:
        var body_length := 0.60
        var barrel_length := 0.48
        var scope := false
        if weapon_id == "smg":
            body_length = 0.49
            barrel_length = 0.23
        elif weapon_id == "shotgun":
            body_length = 0.64
            barrel_length = 0.67
        elif weapon_id == "sniper":
            body_length = 0.67
            barrel_length = 0.86
            scope = true
        _box(parent, "Receiver", Vector3(0, 0.02, -0.35), Vector3(0.19, 0.23, body_length), metal)
        _box(parent, "UpperRail", Vector3(0, 0.17, -0.35), Vector3(0.14, 0.045, body_length * 0.8), dark)
        _box(parent, "PistolGrip", Vector3(0, -0.21, -0.18), Vector3(0.13, 0.34, 0.15), polymer)
        _box(parent, "ShoulderStock", Vector3(0, -0.035, 0.17), Vector3(0.16, 0.20, 0.37), tan if weapon_id == "shotgun" else olive)
        _tube(parent, "Barrel", Vector3(0, 0.045, -0.58), Vector3(0, 0.045, -0.58 - barrel_length), 0.055 if weapon_id == "shotgun" else 0.038, dark)
        end_z = -0.58 - barrel_length
        if weapon_id == "shotgun":
            _tube(parent, "PumpTube", Vector3(0, -0.073, -0.63), Vector3(0, -0.073, -0.99), 0.051, metal)
            _box(parent, "PumpGrip", Vector3(0, -0.085, -0.77), Vector3(0.15, 0.14, 0.29), tan)
        else:
            _box(parent, "Magazine", Vector3(0, -0.28, -0.46), Vector3(0.14, 0.35, 0.20), dark)
        if weapon_id == "rifle":
            _box(parent, "HandGuard", Vector3(0, 0.04, -0.72), Vector3(0.22, 0.19, 0.35), olive)
            _box(parent, "RailSight", Vector3(0, 0.22, -0.42), Vector3(0.11, 0.09, 0.18), dark)
        if scope:
            _tube(parent, "ScopeBody", Vector3(0, 0.26, -0.21), Vector3(0, 0.26, -0.69), 0.092, dark)
            _tube(parent, "ScopeLens", Vector3(0, 0.26, -0.70), Vector3(0, 0.26, -0.73), 0.082, lens)
            _box(parent, "ScopeMount", Vector3(0, 0.18, -0.43), Vector3(0.10, 0.12, 0.16), metal)
            _box(parent, "BipodFolded", Vector3(0, -0.10, -0.79), Vector3(0.13, 0.07, 0.30), dark)
    return end_z
