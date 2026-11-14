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

func _assemble() -> void:
    var cloth := _mat(Color("#323f44"))
    var pants := _mat(Color("#414744"))
    var skin := _mat(Color("#b98b6c"))
    var hair := _mat(Color("#25211f"))
    var boots := _mat(Color("#222628"))
    var highlights := _mat(Color("#69766b"))
    hips = Node3D.new()
    hips.name = "Hips"
    hips.position.y = 0.96
    add_child(hips)
    _capsule(hips, "Pelvis", 0.25, 0.38, Vector3(0, 0, 0), pants)
    torso = Node3D.new()
    torso.name = "Torso"
    torso.position = Vector3(0, 0.18, 0)
    hips.add_child(torso)
    _capsule(torso, "Chest", 0.32, 0.65, Vector3(0, 0.20, 0), cloth)
    _box(torso, "FrontHarness", Vector3(0.52, 0.11, 0.035), Vector3(0, 0.11, -0.29), highlights)
    _capsule(torso, "Neck", 0.09, 0.18, Vector3(0, 0.58, 0), skin)
    head = Node3D.new()
    head.name = "Head"
    head.position = Vector3(0, 0.76, 0)
    torso.add_child(head)
    _sphere(head, "Face", 0.18, Vector3.ZERO, skin, Vector3(0.87, 1.08, 0.87))
    _sphere(head, "Hair", 0.18, Vector3(0, 0.105, 0.02), hair, Vector3(0.94, 0.52, 0.90))
    for side in [-1.0, 1.0]:
        _sphere(head, "Ear", 0.047, Vector3(side * 0.165, -0.015, 0), skin)
    left_leg = _build_leg("LeftLeg", -0.16, pants, boots)
    right_leg = _build_leg("RightLeg", 0.16, pants, boots)
    left_arm = _build_arm("LeftArm", -0.37, cloth, skin)
    right_arm = _build_arm("RightArm", 0.37, cloth, skin)
    weapon_mount = Node3D.new()
    weapon_mount.name = "WeaponMount"
    weapon_mount.position = Vector3(0.22, 1.38, -0.40)
    add_child(weapon_mount)

func _build_leg(part_name: String, x: float, pants: Material, boots: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = part_name
    pivot.position = Vector3(x, -0.08, 0)
    hips.add_child(pivot)
    _capsule(pivot, "Thigh", 0.126, 0.48, Vector3(0, -0.22, 0), pants)
    _capsule(pivot, "Shin", 0.103, 0.43, Vector3(0, -0.63, 0), pants)
    _box(pivot, "Boot", Vector3(0.22, 0.19, 0.32), Vector3(0, -0.86, -0.075), boots)
    return pivot

func _build_arm(part_name: String, x: float, cloth: Material, skin: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = part_name
    pivot.position = Vector3(x, 0.45, 0)
    torso.add_child(pivot)
    _capsule(pivot, "UpperArm", 0.11, 0.36, Vector3(0, -0.17, 0), cloth)
    _capsule(pivot, "Forearm", 0.087, 0.33, Vector3(0, -0.45, -0.07), cloth)
    _sphere(pivot, "Hand", 0.086, Vector3(0, -0.63, -0.09), skin)
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
    var left_arm_target := (-0.65 if aiming else -0.30) - stride * (0.05 if aiming else 0.23)
    var right_arm_target := (-0.71 if aiming else -0.29) + stride * (0.05 if aiming else 0.23)
    if reloading:
        left_arm_target = -0.96
        right_arm_target = -0.48
    left_arm.rotation.x = lerpf(left_arm.rotation.x, left_arm_target, blend)
    right_arm.rotation.x = lerpf(right_arm.rotation.x, right_arm_target, blend)
    left_arm.rotation.z = lerpf(left_arm.rotation.z, -0.15 if aiming else 0.07, blend)
    right_arm.rotation.z = lerpf(right_arm.rotation.z, 0.15 if aiming else -0.07, blend)
    torso.rotation.z = lerpf(torso.rotation.z, 0.035 * stride, blend)
    torso.rotation.x = lerpf(torso.rotation.x, 0.08 if running else (0.045 if aiming else 0.0), blend)
    hips.position.y = lerpf(hips.position.y, 0.70 if crouched else 0.96, blend)
    head.rotation.x = lerpf(head.rotation.x, -0.06 if aiming else 0.0, blend)
    weapon_mount.position.y = lerpf(weapon_mount.position.y, 1.12 if crouched else 1.38, blend)
    weapon_mount.rotation.x = lerpf(weapon_mount.rotation.x, -0.08 if aiming else 0.0, blend)
