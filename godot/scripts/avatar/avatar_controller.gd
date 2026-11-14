extends Node3D
## Campo de Fogo: self-contained stylized humanoid rig for Godot 4.
## Mesh primitives are cosmetic only: physics remains in Player CharacterBody3D.
var weapon_mount: Node3D
var hips: Node3D
var torso: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var head: Node3D
var locomotion_time := 0.0
var smoothed_move := 0.0
var long_weapon := false
var right_grip := Vector3(0, -0.15, -0.08)
var left_grip := Vector3(-0.065, -0.14, -0.09)

func _ready() -> void:
    _assemble()

func _mat(color: Color, metallic: float = 0.0, roughness: float = 0.84) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.metallic = metallic
    m.roughness = roughness
    return m

func _capsule(parent: Node3D, part_name: String, radius: float, total_height: float, position: Vector3, mat: Material) -> void:
    var instance := MeshInstance3D.new()
    instance.name = part_name
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = maxf(total_height, radius * 2.02)
    mesh.radial_segments = 12
    mesh.rings = 4
    instance.mesh = mesh
    instance.position = position
    instance.material_override = mat
    parent.add_child(instance)

func _sphere(parent: Node3D, part_name: String, radius: float, position: Vector3, mat: Material, scale_factor: Vector3 = Vector3.ONE) -> void:
    var instance := MeshInstance3D.new()
    instance.name = part_name
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 14
    mesh.rings = 8
    instance.mesh = mesh
    instance.position = position
    instance.scale = scale_factor
    instance.material_override = mat
    parent.add_child(instance)

func _box(parent: Node3D, part_name: String, size: Vector3, position: Vector3, mat: Material) -> void:
    var instance := MeshInstance3D.new()
    instance.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.position = position
    instance.material_override = mat
    parent.add_child(instance)

func _loft(parent: Node3D, part_name: String, rings: Array, mat: Material) -> void:
    # Elliptical cross-sections give the chest, waist and face their silhouette.
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    const SIDES := 16
    for layer in range(rings.size() - 1):
        var lower: Vector3 = rings[layer]
        var upper: Vector3 = rings[layer + 1]
        for side in range(SIDES):
            var angle := TAU * side / SIDES
            var next_angle := TAU * (side + 1) / SIDES
            var a := Vector3(cos(angle) * lower.y, lower.x, sin(angle) * lower.z)
            var b := Vector3(cos(angle) * upper.y, upper.x, sin(angle) * upper.z)
            var c := Vector3(cos(next_angle) * upper.y, upper.x, sin(next_angle) * upper.z)
            var d := Vector3(cos(next_angle) * lower.y, lower.x, sin(next_angle) * lower.z)
            for vertex in [a, c, b, a, d, c]:
                surface.add_vertex(vertex)
    for end in [0, rings.size() - 1]:
        var ring: Vector3 = rings[end]
        for side in range(SIDES):
            var angle := TAU * side / SIDES
            var next_angle := TAU * (side + 1) / SIDES
            var a := Vector3(cos(angle) * ring.y, ring.x, sin(angle) * ring.z)
            var b := Vector3(cos(next_angle) * ring.y, ring.x, sin(next_angle) * ring.z)
            for vertex in [Vector3(0, ring.x, 0), b if end == 0 else a, a if end == 0 else b]:
                surface.add_vertex(vertex)
    surface.generate_normals()
    var instance := MeshInstance3D.new()
    instance.name = part_name
    instance.mesh = surface.commit()
    instance.material_override = mat
    parent.add_child(instance)

func _assemble() -> void:
    var cloth := _mat(Color("#394748"))
    var pants := _mat(Color("#414b43"))
    var skin := _mat(Color("#b98b6c"))
    var hair := _mat(Color("#282522"))
    var boots := _mat(Color("#202526"))
    var armor := _mat(Color("#293638"))
    var webbing := _mat(Color("#697264"))
    var eyes := _mat(Color("#202625"))
    var whites := _mat(Color("#c4bcb0"))
    hips = Node3D.new()
    hips.name = "Hips"
    hips.position.y = 0.96
    add_child(hips)
    _loft(hips, "Pelvis", [Vector3(-0.12, 0.19, 0.12), Vector3(0.01, 0.245, 0.145), Vector3(0.14, 0.205, 0.125)], pants)
    _box(hips, "Belt", Vector3(0.45, 0.065, 0.29), Vector3(0, 0.10, 0), boots)
    _box(hips, "Buckle", Vector3(0.065, 0.055, 0.023), Vector3(0, 0.10, -0.158), webbing)
    torso = Node3D.new()
    torso.name = "Torso"
    torso.position = Vector3(0, 0.18, 0)
    hips.add_child(torso)
    _loft(torso, "Chest", [Vector3(-0.09, 0.19, 0.12), Vector3(0.10, 0.225, 0.14), Vector3(0.34, 0.285, 0.15), Vector3(0.47, 0.27, 0.135), Vector3(0.53, 0.15, 0.105)], cloth)
    _box(torso, "FrontPlate", Vector3(0.39, 0.34, 0.065), Vector3(0, 0.27, -0.153), armor)
    _box(torso, "BackPlate", Vector3(0.39, 0.37, 0.055), Vector3(0, 0.28, 0.15), armor)
    for side in [-1.0, 1.0]:
        _box(torso, "ShoulderStrap", Vector3(0.065, 0.17, 0.32), Vector3(side * 0.17, 0.47, 0), webbing)
        _box(torso, "SideStrap", Vector3(0.055, 0.065, 0.29), Vector3(side * 0.23, 0.10, 0), webbing)
    for slot in range(3):
        _box(torso, "MagazinePouch", Vector3(0.105, 0.16, 0.075), Vector3((slot - 1) * 0.125, 0.075, -0.20), webbing)
        _box(torso, "PouchFlap", Vector3(0.108, 0.035, 0.016), Vector3((slot - 1) * 0.125, 0.14, -0.245), armor)
    _box(torso, "BackSeam", Vector3(0.025, 0.26, 0.01), Vector3(0, 0.28, 0.183), webbing)
    _capsule(torso, "Neck", 0.078, 0.16, Vector3(0, 0.59, 0), skin)
    head = Node3D.new()
    head.name = "Head"
    head.position = Vector3(0, 0.76, 0)
    torso.add_child(head)
    _loft(head, "Face", [Vector3(-0.16, 0.065, 0.075), Vector3(-0.10, 0.115, 0.115), Vector3(0.0, 0.145, 0.137), Vector3(0.115, 0.14, 0.13), Vector3(0.17, 0.09, 0.085)], skin)
    _loft(head, "Hair", [Vector3(0.08, 0.147, 0.139), Vector3(0.13, 0.145, 0.135), Vector3(0.19, 0.07, 0.07)], hair)
    _sphere(head, "Nose", 0.028, Vector3(0, -0.015, -0.143), skin, Vector3(0.70, 1.30, 1.35))
    _box(head, "Mouth", Vector3(0.057, 0.009, 0.009), Vector3(0, -0.095, -0.123), _mat(Color("#79554a")))
    for side in [-1.0, 1.0]:
        _sphere(head, "Ear", 0.033, Vector3(side * 0.145, -0.02, 0.01), skin, Vector3(0.58, 1.20, 0.72))
        _box(head, "Eye", Vector3(0.045, 0.018, 0.012), Vector3(side * 0.06, 0.025, -0.128), whites)
        _box(head, "Pupil", Vector3(0.014, 0.018, 0.006), Vector3(side * 0.06, 0.025, -0.136), eyes)
        _box(head, "Brow", Vector3(0.055, 0.013, 0.013), Vector3(side * 0.06, 0.054, -0.128), hair)
    left_leg = _build_leg("LeftLeg", -0.145, pants, boots)
    right_leg = _build_leg("RightLeg", 0.145, pants, boots)
    left_arm = _build_arm("LeftArm", -0.37, cloth, skin)
    right_arm = _build_arm("RightArm", 0.37, cloth, skin)
    left_arm.position = Vector3(-0.31, 0.45, -0.10)
    weapon_mount = Node3D.new()
    weapon_mount.name = "WeaponMount"
    weapon_mount.position = Vector3(0.18, 1.44, -0.42)
    add_child(weapon_mount)

func configure_weapon(weapon_id: String, model_scale: float = 1.0) -> void:
    long_weapon = weapon_id in ["rifle", "sniper"]
    if long_weapon:
        weapon_mount.position.x = 0.28
        weapon_mount.position.z = -0.16
        left_arm.position = Vector3(-0.24, 0.45, -0.20)
        right_grip = Vector3(0, -0.18, -0.21) * model_scale
        left_grip = (Vector3(-0.05, -0.035, -0.6355) if weapon_id == "sniper" else Vector3(-0.05, -0.14, -0.68)) * model_scale
    else:
        weapon_mount.position.x = 0.18
        weapon_mount.position.z = -0.42
        left_arm.position = Vector3(-0.31, 0.45, -0.10)
        right_grip = Vector3(0, -0.15, -0.08)
        left_grip = Vector3(-0.065, -0.14, -0.09)

func _build_leg(part_name: String, x: float, pants: Material, boots: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = part_name
    pivot.position = Vector3(x, -0.08, 0)
    hips.add_child(pivot)
    _capsule(pivot, "Thigh", 0.108, 0.48, Vector3(0, -0.22, 0), pants)
    _box(pivot, "CargoPocket", Vector3(0.055, 0.18, 0.15), Vector3(-0.12 if x < 0 else 0.12, -0.20, 0.015), pants)
    _box(pivot, "KneePad", Vector3(0.16, 0.16, 0.055), Vector3(0, -0.45, -0.085), boots)
    _capsule(pivot, "Shin", 0.085, 0.43, Vector3(0, -0.63, 0), pants)
    _box(pivot, "Boot", Vector3(0.18, 0.17, 0.29), Vector3(0, -0.79, -0.055), boots)
    _box(pivot, "BootSole", Vector3(0.19, 0.035, 0.30), Vector3(0, -0.865, -0.055), boots)
    return pivot

func _build_arm(part_name: String, x: float, cloth: Material, skin: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = part_name
    pivot.position = Vector3(x, 0.45, 0)
    torso.add_child(pivot)
    _capsule(pivot, "UpperArm", 0.085, 0.36, Vector3(0, -0.17, 0), cloth)
    _sphere(pivot, "ShoulderSleeve", 0.10, Vector3(0, -0.025, 0), cloth, Vector3(1.0, 0.85, 0.90))
    var elbow := Node3D.new()
    elbow.name = "Elbow"
    elbow.position = Vector3(0, -0.34, 0)
    pivot.add_child(elbow)
    _capsule(elbow, "Forearm", 0.068, 0.34, Vector3(0, -0.16, 0), cloth)
    var glove := _mat(Color("#252d2c"))
    _box(elbow, "ElbowPad", Vector3(0.13, 0.10, 0.045), Vector3(0, 0.0, 0.055), glove)
    # Keep the wrist anchor fixed: weapon IK targets this node's origin.
    var hand := Node3D.new()
    hand.name = "Hand"
    hand.position = Vector3(0, -0.34, 0)
    elbow.add_child(hand)
    _box(hand, "GlovePalm", Vector3(0.085, 0.105, 0.055), Vector3(0, -0.01, 0), glove)
    _box(hand, "Knuckles", Vector3(0.088, 0.035, 0.025), Vector3(0, -0.04, -0.035), glove)
    _sphere(hand, "Thumb", 0.021, Vector3(-0.043 if x > 0 else 0.043, 0.008, -0.025), skin, Vector3(0.8, 1.35, 0.9))
    return pivot

func animate(delta: float, move_amount: float, running: bool, crouched: bool, aiming: bool, airborne: bool, reloading: bool) -> void:
    var blend := minf(1.0, delta * 10.0)
    smoothed_move = lerpf(smoothed_move, clampf(move_amount, 0.0, 1.0), blend)
    if smoothed_move > 0.06 and not airborne:
        locomotion_time += delta * (12.0 if running else (5.4 if crouched else 7.9))
    var stride := sin(locomotion_time) * smoothed_move
    var amplitude := 0.51 if running else (0.24 if crouched else 0.36)
    left_leg.rotation.x = lerpf(left_leg.rotation.x, stride * amplitude if not airborne else -0.19, blend)
    right_leg.rotation.x = lerpf(right_leg.rotation.x, -stride * amplitude if not airborne else 0.24, blend)
    if reloading:
        left_arm.quaternion = left_arm.quaternion.slerp(Quaternion.from_euler(Vector3(0.54, 0, 0.28)), blend)
        right_arm.quaternion = right_arm.quaternion.slerp(Quaternion.from_euler(Vector3(0.99, 0, -0.09)), blend)
        var left_elbow := left_arm.get_node("Elbow") as Node3D
        var right_elbow := right_arm.get_node("Elbow") as Node3D
        left_elbow.quaternion = left_elbow.quaternion.slerp(Quaternion.from_euler(Vector3(-0.18, 0, 0)), blend)
        right_elbow.quaternion = right_elbow.quaternion.slerp(Quaternion.from_euler(Vector3(-0.12, 0, 0)), blend)
    torso.rotation.z = lerpf(torso.rotation.z, 0.035 * stride, blend)
    torso.rotation.x = lerpf(torso.rotation.x, 0.08 if running else (0.045 if aiming else 0.0), blend)
    hips.position.y = lerpf(hips.position.y, 0.70 if crouched else 0.96, blend)
    head.rotation.x = lerpf(head.rotation.x, -0.06 if aiming else 0.0, blend)
    var hold_height := (1.54 if aiming else 1.50) if long_weapon else (1.48 if aiming else 1.44)
    weapon_mount.position.y = lerpf(weapon_mount.position.y, hold_height - (0.26 if crouched else 0.0), blend)
    weapon_mount.rotation.x = lerpf(weapon_mount.rotation.x, -0.08 if aiming else 0.0, blend)
    # Solve after torso, crouch and mount changes so the hands follow the gun.
    if not reloading:
        _align_hand(right_arm, right_grip, 1.0, blend)
        _align_hand(left_arm, left_grip, -1.0, blend)

func _align_hand(shoulder: Node3D, grip: Vector3, side: float, blend: float) -> void:
    var elbow := shoulder.get_node("Elbow") as Node3D
    var target := torso.to_local(weapon_mount.to_global(grip))
    var offset := target - shoulder.position
    var upper_length := elbow.position.length()
    var lower_length := 0.34
    var distance := clampf(offset.length(), 0.001, upper_length + lower_length - 0.001)
    var direction := offset.normalized()
    # Bend outwards and down, keeping a stable elbow plane across locomotion.
    var pole := Vector3(side * 0.6, -1.0, 0.15)
    var bend := (pole - direction * pole.dot(direction)).normalized()
    var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
    var outward := sqrt(maxf(0.0, upper_length * upper_length - along * along))
    var upper_direction := (direction * along + bend * outward).normalized()
    shoulder.quaternion = shoulder.quaternion.slerp(Quaternion(Vector3.DOWN, upper_direction), blend)
    var forearm_direction := (shoulder.to_local(torso.to_global(target)) - elbow.position).normalized()
    elbow.quaternion = elbow.quaternion.slerp(Quaternion(Vector3.DOWN, forearm_direction), blend)
