extends Node
## Correcao de postura T para avatares humanoides no Godot 4.
## Adicione este Node como filho do Skeleton3D do Avatar CH3.
## Ajuste os nomes dos ossos no Inspector se a deteccao automatica falhar.
## IMPORTANTE: desligue a correcao ao tocar animacoes que ja tenham pose de bracos,
## principalmente Aim, Reload, Walk e Run, usando set_posture_weight(0.0).

@export_range(0.0, 1.0, 0.01) var posture_weight: float = 1.0
@export_range(0.0, 85.0, 1.0) var arm_drop_degrees: float = 65.0
@export var left_upper_arm_bone: String = ""
@export var right_upper_arm_bone: String = ""
@export var show_diagnostics: bool = true

var _skeleton: Skeleton3D
var _left_arm: int = -1
var _right_arm: int = -1

func _ready() -> void:
    _skeleton = get_parent() as Skeleton3D
    if _skeleton == null:
        push_warning("AvatarCH3Posture: coloque este node como filho de Skeleton3D.")
        set_process(false)
        return
    _left_arm = _find_upper_arm(left_upper_arm_bone, "left")
    _right_arm = _find_upper_arm(right_upper_arm_bone, "right")
    if _left_arm < 0 or _right_arm < 0 or _left_arm == _right_arm:
        push_warning("AvatarCH3Posture: ossos dos bracos nao encontrados. Defina os nomes no Inspector.")
        set_process(false)
        return
    if show_diagnostics:
        print("AvatarCH3Posture: esquerda=", _skeleton.get_bone_name(_left_arm),
            ", direita=", _skeleton.get_bone_name(_right_arm))

func _process(_delta: float) -> void:
    if _skeleton == null:
        return
    # Os overrides nao devem congelar animacoes existentes:
    # weight=0 remove a correcao e deixa AnimationPlayer/AnimationTree atuar.
    if posture_weight <= 0.001:
        _skeleton.clear_bones_global_pose_override()
        return
    _apply_arm(_left_arm, true)
    _apply_arm(_right_arm, false)

func set_posture_weight(value: float) -> void:
    posture_weight = clampf(value, 0.0, 1.0)
    if _skeleton != null and posture_weight <= 0.001:
        _skeleton.clear_bones_global_pose_override()

func _apply_arm(bone_idx: int, is_left: bool) -> void:
    # Usa a pose base atual (sem override), para nao acumular rotacao a cada frame.
    var base_pose: Transform3D = _skeleton.get_bone_global_pose_no_override(bone_idx)
    var angle: float = deg_to_rad(arm_drop_degrees)
    if not is_left:
        angle = -angle
    # Espaco do esqueleto: giro em Z abaixa o braco estendido horizontalmente.
    var target: Transform3D = base_pose
    target.basis = Basis(Vector3.FORWARD, angle) * base_pose.basis
    _skeleton.set_bone_global_pose_override(bone_idx, target, posture_weight, true)

func _find_upper_arm(explicit_name: String, side: String) -> int:
    if explicit_name != "":
        return _skeleton.find_bone(explicit_name)
    for idx in _skeleton.get_bone_count():
        var raw: String = _skeleton.get_bone_name(idx).to_lower()
        var name: String = raw.replace("_", "").replace("-", "").replace(":", "").replace(" ", "")
        var side_match: bool = name.contains(side)
        if not side_match:
            # Variantes frequentes em rig de jogos: upperarm_l / upperarm_r.
            side_match = name.ends_with("arm" + ("l" if side == "left" else "r"))
        var upper_match: bool = name.contains("upperarm") or name.contains(side + "arm") or name.contains("arm" + ("l" if side == "left" else "r"))
        var lower_match: bool = name.contains("forearm") or name.contains("lowerarm") or name.contains("hand") or name.contains("twist")
        if side_match and upper_match and not lower_match:
            return idx
    return -1
