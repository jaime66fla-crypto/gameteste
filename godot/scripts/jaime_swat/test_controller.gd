extends Node3D
## Standalone animation preview; no dependency on the main player, camera or combat.
const RifleModel = preload("res://assets/personagens/jaime/animacoes/Models/Weapons/Human_AssaultRifle.fbx")
var skeleton: Skeleton3D
var rifle: Node3D
var aiming := false
var aim_weight := 0.0
var playback: AnimationNodeStateMachinePlayback
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
    skeleton = $Soldier/Node/Skeleton3D
    var original_player := $Soldier.find_child("AnimationPlayer", true, false) as AnimationPlayer
    if original_player:
        original_player.active = false
    rifle = Node3D.new()
    rifle.name = "TestRifle"
    skeleton.add_child(rifle)
    var rifle_model := RifleModel.instantiate() as Node3D
    rifle_model.name = "ImportedRifle"
    rifle_model.rotation.y = PI
    rifle_model.scale = Vector3.ONE * 1.5
    rifle_model.position = Vector3(0, -0.105, -0.18)
    rifle.add_child(rifle_model)
    var rifle_material := StandardMaterial3D.new()
    rifle_material.albedo_color = Color("#303b43")
    rifle_material.metallic = 0.65
    rifle_material.roughness = 0.5
    for mesh in rifle_model.find_children("*", "MeshInstance3D", true, false):
        mesh.material_override = rifle_material
    for item in [["RightGrip", Vector3(0.05, -0.18, -0.18)], ["LeftGrip", Vector3(-0.06, -0.04, -0.58)]]:
        var marker := Marker3D.new()
        marker.name = item[0]
        marker.position = item[1]
        rifle.add_child(marker)
    animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    animation_tree.active = true
    playback = animation_tree.get("parameters/playback")
    playback.start("Normal")
    set_view(false)
    advance_preview(0.001)

func _process(delta: float) -> void:
    advance_preview(delta)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_RIGHT:
            set_aiming(event.pressed)
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            request_shot()
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_1:
            set_view(false)
        elif event.physical_keycode == KEY_2:
            set_view(true)

func set_view(side: bool) -> void:
    $PreviewCamera.position = Vector3(3.4, 1.35, -0.3) if side else Vector3(2.4, 1.5, -3.6)
    $PreviewCamera.look_at(Vector3(0, 1.0, 0))

func set_aiming(value: bool) -> void:
    aiming = value
    playback.travel("Mira" if aiming else "Normal")

func request_shot() -> void:
    if aiming and current_state() != "Disparo":
        playback.travel("Disparo")

func current_state() -> String:
    return String(playback.get_current_node())

func advance_preview(delta: float) -> void:
    if not animation_tree.active:
        return
    animation_tree.advance(delta)
    aim_weight = move_toward(aim_weight, 1.0 if aiming else 0.0, delta * 5.0)
    _update_rifle_and_grip()
    $Instructions/Panel/State.text = "ESTADO: " + current_state()

func preview_clip(clip: String, time: float) -> void:
    animation_tree.active = false
    animation_player.play(clip)
    animation_player.seek(time, true)
    animation_player.pause()
    aim_weight = 0.0 if clip == "normal" else 1.0
    _update_rifle_and_grip()
    $Instructions/Panel/State.text = "AMOSTRA: " + {"normal": "Normal", "aim": "Mira", "fire": "Disparo"}.get(clip, clip)

func resume_preview() -> void:
    animation_player.stop()
    aiming = false
    aim_weight = 0.0
    animation_tree.active = true
    playback.start("Normal", true)
    advance_preview(0.001)

func _update_rifle_and_grip() -> void:
    var chest := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorigSpine2"))
    var offset := Vector3(-0.01, 0.07, -0.015).lerp(Vector3(-0.025, 0.14, 0.01), aim_weight)
    var orientation := Basis(Vector3.RIGHT, lerpf(0.50, 0.0, aim_weight)) * Basis(Vector3.UP, PI)
    rifle.transform = chest * Transform3D(orientation.scaled(Vector3.ONE * 0.36), offset)
    _solve_arm("Right")
    _solve_arm("Left")
    _close_fingers("Right")
    _close_fingers("Left")

func _close_fingers(side: String) -> void:
    var middle := skeleton.find_bone("mixamorig" + side + "HandMiddle1")
    var index := skeleton.find_bone("mixamorig" + side + "HandIndex1")
    var pinky := skeleton.find_bone("mixamorig" + side + "HandPinky1")
    var direction := skeleton.get_bone_rest(middle).origin.normalized()
    var across := skeleton.get_bone_rest(index).origin - skeleton.get_bone_rest(pinky).origin
    var hinge := (across - direction * across.dot(direction)).normalized()
    for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
        for segment in range(1, 4):
            var bone := skeleton.find_bone("mixamorig" + side + "Hand" + finger + str(segment))
            var angle: float = [0.55, 0.95, 0.70][segment - 1]
            if side == "Right" and finger == "Index":
                angle = [0.12, 0.35, 0.3][segment - 1]
            var rotation := Quaternion(hinge, angle)
            if finger == "Thumb" and segment == 1:
                rotation = Quaternion(hinge.cross(direction).normalized(), -0.65) * rotation
            skeleton.set_bone_pose_rotation(bone, rotation)

func _solve_arm(side: String) -> void:
    var upper := skeleton.find_bone("mixamorig" + side + "Arm")
    var elbow := skeleton.find_bone("mixamorig" + side + "ForeArm")
    var hand := skeleton.find_bone("mixamorig" + side + "Hand")
    var target := rifle.transform * (rifle.get_node(side + "Grip") as Marker3D).position
    var upper_pose := skeleton.get_bone_global_pose(upper)
    var elbow_pose := skeleton.get_bone_global_pose(elbow)
    var hand_basis := _grip_basis(side)
    var upper_length := skeleton.get_bone_rest(elbow).origin.length()
    var lower_length := skeleton.get_bone_rest(hand).origin.length()
    var offset := target - upper_pose.origin
    var distance := clampf(offset.length(), 0.001, upper_length + lower_length - 0.0001)
    var direction := offset.normalized()
    var pole := elbow_pose.origin - upper_pose.origin
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
    _set_global_rotation(upper, upper_basis)
    elbow_pose = skeleton.get_bone_global_pose(elbow)
    var lower_direction := (elbow_pose.basis * skeleton.get_bone_rest(hand).origin).normalized()
    var reachable_target := upper_pose.origin + direction * distance
    var lower_basis := Basis(Quaternion(lower_direction, (reachable_target - elbow_pose.origin).normalized())) * elbow_pose.basis
    _set_global_rotation(elbow, lower_basis)
    _set_global_rotation(hand, hand_basis)

func _grip_basis(side: String) -> Basis:
    # Calibrate palm/finger axes against the imported weapon, rather than carrying
    # the source rig's wrist roll into a differently oriented Mixamo hand.
    var middle := skeleton.find_bone("mixamorig" + side + "HandMiddle1")
    var index := skeleton.find_bone("mixamorig" + side + "HandIndex1")
    var pinky := skeleton.find_bone("mixamorig" + side + "HandPinky1")
    var rest_fingers := skeleton.get_bone_rest(middle).origin.normalized()
    var rest_across := skeleton.get_bone_rest(index).origin - skeleton.get_bone_rest(pinky).origin
    var rest_x := (rest_across - rest_fingers * rest_across.dot(rest_fingers)).normalized()
    var rest_frame := Basis(rest_x, rest_fingers, rest_x.cross(rest_fingers).normalized())
    var fingers := Vector3(-0.8, 0.4, 0).normalized() if side == "Right" else Vector3(0.8, 0.6, 0).normalized()
    var across := Vector3.UP if side == "Right" else Vector3.FORWARD
    var x := (across - fingers * across.dot(fingers)).normalized()
    return rifle.basis.orthonormalized() * Basis(x, fingers, x.cross(fingers).normalized()) * rest_frame.inverse()

func _set_global_rotation(bone: int, desired: Basis) -> void:
    var parent := skeleton.get_bone_parent(bone)
    var parent_basis := skeleton.get_bone_global_pose(parent).basis
    skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * desired).orthonormalized().get_rotation_quaternion().normalized())

func grip_error(side: String) -> float:
    var hand := skeleton.find_bone("mixamorig" + side + "Hand")
    var hand_world := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
    return hand_world.distance_to((rifle.get_node(side + "Grip") as Marker3D).global_position)
