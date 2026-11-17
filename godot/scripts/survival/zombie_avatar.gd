extends Node3D
## Visual do zumbi com o modelo Mixamo (assets/personagens/zumbi/zumbi_modelo.scn).
## Os movimentos do projeto (andar, correr, soco, parado) são adaptados ao
## esqueleto dele (mixamorig9 → mixamorig5) e, por cima, uma pose de zumbi:
## tronco curvado, cabeça caída e balançando, braços esticados para a frente.
## Áreas de acerto presas aos ossos (cabeça, peito, quadril, braços, pernas).
## Longe da câmera a animação roda menos vezes e a pose extra é desligada.
const MODEL := "res://assets/personagens/zumbi/zumbi_modelo.scn"
const SOURCE_HEIGHT := 1.775
const AVATAR_FBX := "res://assets/personagens/downloaded/avatar.fbx"
const CLIPS := {
	"idle": "res://assets/personagens/downloaded/movements/idle_with_rifle.tres",
	"walk": "res://assets/personagens/downloaded/movements/walk_with_rifle.tres",
	"attack": "res://assets/personagens/downloaded/movements/punch.tres",
}
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")
# [osso de, osso até, zona, raio]
const HITBOXES := [
	["Head", "HeadTop_End", "head", 0.12],
	["Neck", "Head", "chest", 0.08],
	["Spine2", "Neck", "chest", 0.17],
	["Spine", "Spine2", "chest", 0.16],
	["Hips", "Spine", "pelvis", 0.16],
	["LeftArm", "LeftForeArm", "arm", 0.065],
	["LeftForeArm", "LeftHand", "arm", 0.055],
	["RightArm", "RightForeArm", "arm", 0.065],
	["RightForeArm", "RightHand", "arm", 0.055],
	["LeftUpLeg", "LeftLeg", "leg", 0.09],
	["LeftLeg", "LeftFoot", "leg", 0.07],
	["RightUpLeg", "RightLeg", "leg", 0.09],
	["RightLeg", "RightFoot", "leg", 0.07],
]
enum Anim { IDLE, WALK, RUN, ATTACK }

static var _library: AnimationLibrary
static var _tinted: Dictionary = {} # tom de pele por tipo -> materiais

var actor: Node # o zumbi (recebe os acertos)
var tint := Color.WHITE
var hitboxes: Array[StaticBody3D] = []
var skeleton: Skeleton3D
var player: AnimationPlayer
var flinch := 0.0
var _clip := ""
var _phase := randf() * TAU
var _lod_accum := 0.0
var _frame := randi() % 4
var _mesh: MeshInstance3D

static func available() -> bool:
	return ResourceLoader.exists(MODEL)

func _ready() -> void:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	model.rotation.y = PI # o modelo Mixamo olha para +Z; o jogo usa -Z
	model.scale = Vector3.ONE * (1.8 / SOURCE_HEIGHT)
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_mesh = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_apply_tint()
	player = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("", _shared_library(skeleton))
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_play("idle", 1.0)
	player.seek(randf() * 2.0, true)
	_build_hitboxes()

## Variação por tipo (corredor mais pálido, brutamontes mais escuro): materiais por tom, compartilhados.
func _apply_tint() -> void:
	if tint == Color.WHITE or _mesh == null:
		return
	var key := tint.to_html()
	if not _tinted.has(key):
		var list: Array = []
		for s in _mesh.mesh.get_surface_count():
			var m := (_mesh.mesh.surface_get_material(s) as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_color = tint
			list.append(m)
		_tinted[key] = list
	var mats: Array = _tinted[key]
	for s in mats.size():
		_mesh.set_surface_override_material(s, mats[s])

## Biblioteca de animações adaptada ao esqueleto do zumbi (montada uma vez).
static func _shared_library(sk: Skeleton3D) -> AnimationLibrary:
	if _library != null:
		return _library
	var lib := AnimationLibrary.new()
	var hips := sk.find_bone("mixamorig5_Hips")
	var anchor: Vector3 = sk.get_bone_rest(hips).origin if hips >= 0 else Vector3.ZERO
	var sources := {}
	for name in CLIPS:
		sources[name] = load(CLIPS[name]) as Animation
	# Corrida: o ciclo "mixamo_com" que vem dentro do avatar.fbx.
	var avatar := load(AVATAR_FBX) as PackedScene
	if avatar != null:
		var tmp := avatar.instantiate()
		var ap := tmp.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty() and (ap[0] as AnimationPlayer).has_animation("mixamo_com"):
			sources["run"] = (ap[0] as AnimationPlayer).get_animation("mixamo_com")
		tmp.free()
	for name in sources:
		var src: Animation = sources[name]
		if src == null:
			continue
		var clip := src.duplicate(true) as Animation
		for t in range(clip.get_track_count() - 1, -1, -1):
			var path := str(clip.track_get_path(t))
			if not path.contains("mixamorig"):
				clip.remove_track(t)
				continue
			var bone := path.get_slice(":", 1)
			bone = "mixamorig5_" + bone.get_slice("_", bone.get_slice_count("_") - 1) if bone.contains("_") else bone.replace("mixamorig9:", "mixamorig5_").replace("mixamorig:", "mixamorig5_")
			clip.track_set_path(t, NodePath("%s:%s" % [sk.name, bone]))
			# No lugar: o quadril não anda para a frente (quem anda é o corpo físico).
			if clip.track_get_type(t) == Animation.TYPE_POSITION_3D and bone.ends_with("Hips"):
				for k in clip.track_get_key_count(t):
					var p: Vector3 = clip.track_get_key_value(t, k)
					clip.track_set_key_value(t, k, Vector3(anchor.x, p.y, anchor.z))
			elif clip.track_get_type(t) == Animation.TYPE_POSITION_3D:
				clip.remove_track(t) # só o quadril tem posição; o resto segue a proporção do zumbi
		clip.loop_mode = Animation.LOOP_NONE if name == "attack" else Animation.LOOP_LINEAR
		lib.add_animation(name, clip)
	_library = lib
	return lib

func _play(clip: String, rate: float) -> void:
	if not player.has_animation(clip):
		clip = "walk"
	if _clip != clip or (clip == "attack" and not player.is_playing()):
		_clip = clip
		player.play(clip, 0.25)
	player.speed_scale = rate

## Chamado pelo zumbi a cada quadro. `lod`: 0 perto (tudo), 1 médio (sem pose extra, 1 a cada 3 quadros), 2 longe (parado).
func animate(delta: float, state: int, move_rate: float, lod: int) -> void:
	if player == null:
		return
	match state:
		Anim.IDLE: _play("idle", 0.6)
		Anim.WALK: _play("walk", 0.55 * move_rate)
		Anim.RUN: _play("run" if player.has_animation("run") else "walk", 0.95 * move_rate)
		Anim.ATTACK: _play("idle", 1.0) # o bote é feito na pose (tronco e braços)
	_phase += delta
	flinch = move_toward(flinch, 0.0, delta * 4.0)
	if lod >= 2:
		return
	_lod_accum += delta
	_frame += 1
	if lod == 1 and _frame % 3 != 0:
		return
	player.advance(_lod_accum)
	_lod_accum = 0.0
	if lod == 0:
		_zombie_pose(state)

## Pose de zumbi por cima do clipe.
func _zombie_pose(state: int) -> void:
	var spine := _bone("Spine1")
	var neck := _bone("Neck")
	var head := _bone("Head")
	var forward := Vector3(0, 0, 1) # frente do modelo no espaço do esqueleto
	# Bote (ataque): o tronco avança e volta num ciclo rápido de agarrar.
	var lunge := (0.5 + 0.5 * sin(_phase * 7.0)) if state == Anim.ATTACK else 0.0
	if spine >= 0:
		var lean := 0.32 + (0.15 if state == Anim.RUN else 0.0) + lunge * 0.35 - flinch * 0.5
		Grip._set_global_rotation(skeleton, spine, Basis(Vector3.RIGHT, lean) * skeleton.get_bone_global_pose(spine).basis)
	if head >= 0:
		var wobble := Basis(Vector3.FORWARD, sin(_phase * 1.3) * 0.22) * Basis(Vector3.RIGHT, 0.25 + sin(_phase * 0.7) * 0.08)
		Grip._set_global_rotation(skeleton, head, wobble * skeleton.get_bone_global_pose(head).basis)
	var chest := _bone("Spine2")
	if chest < 0:
		return
	var torso := skeleton.get_bone_global_pose(chest).origin
	for side in ["Left", "Right"]:
		var upper := _bone(side + "Arm")
		var lower := _bone(side + "ForeArm")
		var hand := _bone(side + "Hand")
		if upper < 0 or lower < 0 or hand < 0:
			continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var lateral := shoulder - torso
		lateral.y = 0.0
		lateral = lateral.normalized()
		var reach := 0.55 if state != Anim.RUN else 0.48
		var sway := sin(_phase * 2.1 + (0.0 if side == "Left" else 1.7)) * 0.06
		if state == Anim.ATTACK:
			# Mãos sobem e descem alternadas, tentando agarrar.
			reach = 0.62
			sway = sin(_phase * 7.0 + (0.0 if side == "Left" else PI)) * 0.14 + 0.06
		var target := shoulder + forward * reach + lateral * (0.04 - lunge * 0.06) + Vector3(0, -0.06 + sway, 0)
		_two_bone_ik(upper, lower, hand, target, lateral * 0.5 + Vector3(0, -1, 0))
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_rest(hand).basis.get_rotation_quaternion())

func _two_bone_ik(upper: int, lower: int, end: int, target: Vector3, pole: Vector3) -> void:
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var upper_length := skeleton.get_bone_rest(lower).origin.length()
	var lower_length := skeleton.get_bone_rest(end).origin.length()
	var offset := target - upper_pose.origin
	var distance := clampf(offset.length(), 0.001, upper_length + lower_length - 0.0001)
	var direction := offset.normalized()
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.00001:
		return
	bend = bend.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var outward := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var elbow := upper_pose.origin + direction * along + bend * outward
	var upper_dir := (upper_pose.basis * skeleton.get_bone_rest(lower).origin).normalized()
	Grip._set_global_rotation(skeleton, upper, Basis(Quaternion(upper_dir, (elbow - upper_pose.origin).normalized())) * upper_pose.basis)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var lower_dir := (lower_pose.basis * skeleton.get_bone_rest(end).origin).normalized()
	var reach_point := upper_pose.origin + direction * distance
	Grip._set_global_rotation(skeleton, lower, Basis(Quaternion(lower_dir, (reach_point - lower_pose.origin).normalized())) * lower_pose.basis)

## Osso pelo nome sem prefixo ("RightArm" → "mixamorig5_RightArm"), com cache.
var _bones: Dictionary = {}
func _bone(suffix: String) -> int:
	if not _bones.has(suffix):
		_bones[suffix] = _find_bone(suffix)
	return _bones[suffix]

func _find_bone(suffix: String) -> int:
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if bone == suffix or bone.ends_with("_" + suffix) or bone.ends_with(":" + suffix):
			return i
	return -1

## Cápsulas de acerto de cada osso até o filho, seguindo o esqueleto animado.
func _build_hitboxes() -> void:
	var scale_factor := maxf(skeleton.global_basis.get_scale().x, 0.0001)
	for spec in HITBOXES:
		var from := _find_bone(spec[0])
		var to := _find_bone(spec[1])
		if from < 0 or to < 0:
			continue
		var from_rest := skeleton.get_bone_global_rest(from)
		var local_to: Vector3 = from_rest.affine_inverse() * skeleton.get_bone_global_rest(to).origin
		var length := local_to.length()
		if length < 0.001:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = skeleton.get_bone_name(from)
		skeleton.add_child(attachment)
		var body: StaticBody3D = HitboxScript.new()
		body.set("actor", actor)
		body.set("zone", spec[2])
		attachment.add_child(body)
		var shape := CapsuleShape3D.new()
		var radius: float = float(spec[3]) / scale_factor
		shape.radius = radius
		shape.height = length + radius * 2.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = local_to * 0.5
		collision.quaternion = Quaternion(Vector3.UP, local_to / length)
		body.add_child(collision)
		hitboxes.append(body)
