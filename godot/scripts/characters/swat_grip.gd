extends RefCounted
## Pure visual hand solver, derived from the validated independent SWAT preview.
## `pole` (skeleton space, optional): direction the elbow bends towards; by
## default the elbow stays on the side the animation already put it.
static func solve(skeleton: Skeleton3D, rifle: Node3D, side: String, palm_contact: bool = false, pole: Vector3 = Vector3.ZERO) -> void:
    _solve_arm(skeleton, rifle, side, palm_contact, pole)
    _close_fingers(skeleton, side)

static func _solve_arm(skeleton: Skeleton3D, rifle: Node3D, side: String, palm_contact: bool = false, pole: Vector3 = Vector3.ZERO) -> void:
    var target := rifle.transform * (rifle.get_node(side + "Grip") as Marker3D).position
    var hand_basis := _grip_basis(skeleton, rifle, side)
    if palm_contact:
        target -= hand_basis * palm_offset(skeleton, side)
    _solve_to_target(skeleton, side, target, hand_basis, pole)

static func solve_to_target(skeleton: Skeleton3D, side: String, target: Vector3, hand_basis: Basis) -> void:
    _solve_to_target(skeleton, side, target, hand_basis)

static func _solve_to_target(skeleton: Skeleton3D, side: String, target: Vector3, hand_basis: Basis, pole_hint: Vector3 = Vector3.ZERO) -> void:
    var upper: int = _bone(skeleton, side + "Arm")
    var elbow: int = _bone(skeleton, side + "ForeArm")
    var hand: int = _bone(skeleton, side + "Hand")
    var upper_pose := skeleton.get_bone_global_pose(upper)
    var elbow_pose := skeleton.get_bone_global_pose(elbow)
    var upper_length := skeleton.get_bone_rest(elbow).origin.length()
    var lower_length := skeleton.get_bone_rest(hand).origin.length()
    var offset := target - upper_pose.origin
    var distance := clampf(offset.length(), 0.001, upper_length + lower_length - 0.0001)
    var direction := offset.normalized()
    var pole := elbow_pose.origin - upper_pose.origin if pole_hint == Vector3.ZERO else pole_hint
    var bend := pole - direction * pole.dot(direction)
    if bend.length_squared() < 0.00001:
        var fallback := Vector3(-1 if side == "Right" else 1, -0.8, -0.2)
        bend = fallback - direction * fallback.dot(direction)
    bend = bend.normalized()
    var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
    var outward := sqrt(maxf(0.0, upper_length * upper_length - along * along))
    var elbow_target := upper_pose.origin + direction * along + bend * outward
    var upper_direction := (upper_pose.basis * skeleton.get_bone_rest(elbow).origin).normalized()
    var upper_basis := Basis(Quaternion(upper_direction, (elbow_target - upper_pose.origin).normalized())) * upper_pose.basis
    _set_global_rotation(skeleton, upper, upper_basis)
    elbow_pose = skeleton.get_bone_global_pose(elbow)
    var lower_direction := (elbow_pose.basis * skeleton.get_bone_rest(hand).origin).normalized()
    var reachable_target := upper_pose.origin + direction * distance
    var lower_basis := Basis(Quaternion(lower_direction, (reachable_target - elbow_pose.origin).normalized())) * elbow_pose.basis
    _set_global_rotation(skeleton, elbow, lower_basis)
    _set_global_rotation(skeleton, hand, hand_basis)

static func _grip_basis(skeleton: Skeleton3D, rifle: Node3D, side: String) -> Basis:
    # Calibrate palm/finger axes against the imported weapon, rather than carrying
    # the source rig's wrist roll into a differently oriented Mixamo hand.
    var middle: int = _bone(skeleton, side + "HandMiddle1")
    var index: int = _bone(skeleton, side + "HandIndex1")
    var pinky: int = _bone(skeleton, side + "HandPinky1")
    var rest_fingers := skeleton.get_bone_rest(middle).origin.normalized()
    var rest_across := skeleton.get_bone_rest(index).origin - skeleton.get_bone_rest(pinky).origin
    var rest_x := (rest_across - rest_fingers * rest_across.dot(rest_fingers)).normalized()
    var rest_frame := Basis(rest_x, rest_fingers, rest_x.cross(rest_fingers).normalized())
    var pistol: bool = rifle.get_meta("weapon_id", "") == "pistol"
    var fingers := Vector3(-0.9, 0.2, 0).normalized() if side == "Right" and pistol else (Vector3(-0.8, 0.4, 0).normalized() if side == "Right" else Vector3(0.8, 0.6, 0).normalized())
    if pistol and side == "Left":
        fingers = Vector3(0.98, 0.20, 0).normalized()
    var across := Vector3.UP if side == "Right" or pistol else Vector3.FORWARD
    var x := (across - fingers * across.dot(fingers)).normalized()
    return rifle.basis.orthonormalized() * Basis(x, fingers, x.cross(fingers).normalized()) * rest_frame.inverse()

static func palm_offset(skeleton: Skeleton3D, side: String) -> Vector3:
    return skeleton.get_bone_rest(_bone(skeleton, side + "HandMiddle1")).origin * 0.45

static func palm_position(skeleton: Skeleton3D, side: String) -> Vector3:
    var hand: int = _bone(skeleton, side + "Hand")
    return skeleton.to_global(skeleton.get_bone_global_pose(hand) * palm_offset(skeleton, side))

static func wrist_target(skeleton: Skeleton3D, rifle: Node3D, side: String) -> Vector3:
    return rifle.transform * (rifle.get_node(side + "Grip") as Marker3D).position - _grip_basis(skeleton, rifle, side) * palm_offset(skeleton, side)

static func _set_global_rotation(skeleton: Skeleton3D, bone: int, desired: Basis) -> void:
    var parent := skeleton.get_bone_parent(bone)
    var parent_basis := skeleton.get_bone_global_pose(parent).basis
    skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized())

static func _close_fingers(skeleton: Skeleton3D, side: String) -> void:
    var middle: int = _bone(skeleton, side + "HandMiddle1")
    var index: int = _bone(skeleton, side + "HandIndex1")
    var pinky: int = _bone(skeleton, side + "HandPinky1")
    var direction := skeleton.get_bone_rest(middle).origin.normalized()
    var across := skeleton.get_bone_rest(index).origin - skeleton.get_bone_rest(pinky).origin
    var hinge := (across - direction * across.dot(direction)).normalized()
    for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
        for segment in range(1, 4):
            var bone: int = _bone(skeleton, side + "Hand" + finger + str(segment))
            var angle: float = [0.55, 0.95, 0.70][segment - 1]
            if side == "Right" and finger == "Index":
                angle = [0.12, 0.35, 0.3][segment - 1]
            var rotation := Quaternion(hinge, angle)
            if finger == "Thumb" and segment == 1:
                rotation = Quaternion(hinge.cross(direction).normalized(), -0.65) * rotation
            skeleton.set_bone_pose_rotation(bone, rotation)

static func _bone(skeleton: Skeleton3D, suffix: String) -> int:
    var bone: int = skeleton.find_bone("mixamorig" + suffix)
    if bone < 0:
        bone = skeleton.find_bone("mixamorig9_" + suffix)
    if bone >= 0:
        return bone
    # Other Mixamo exports use another prefix ("mixamorig_", "mixamorig1_",
    # "mixamorig:"): the prefix is whatever precedes "Hips", cached per skeleton.
    var prefix := str(skeleton.get_meta("_mixamo_prefix", ""))
    if not skeleton.has_meta("_mixamo_prefix"):
        for i in skeleton.get_bone_count():
            var name := String(skeleton.get_bone_name(i))
            if name.ends_with("Hips"):
                prefix = name.trim_suffix("Hips")
                break
        skeleton.set_meta("_mixamo_prefix", prefix)
    return skeleton.find_bone(prefix + suffix)
