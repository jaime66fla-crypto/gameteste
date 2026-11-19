extends Node3D
## Visual do zumbi com o modelo Mixamo (assets/personagens/zumbi/zumbi_modelo.scn).
## Os movimentos do projeto (andar, correr, soco, parado) são adaptados ao
## esqueleto dele (mixamorig9 → mixamorig5) e, por cima, uma pose de zumbi:
## tronco curvado, cabeça caída e balançando, braços esticados para a frente.
## Áreas de acerto presas aos ossos (cabeça, peito, quadril, braços, pernas).
## Longe da câmera a animação roda menos vezes e a pose extra é desligada.
const MODEL := "res://assets/personagens/zumbi/zumbi_modelo.scn"
const SOURCE_HEIGHT := 1.775
## Pernas: andar arrastado e parado de zumbi (UAL2, Quaternius, CC0); o tronco,
## a cabeça e os braços são da pose de zumbi abaixo. Corrida: o ciclo do Ch31.
const CLIPS := {
	"idle": "res://assets/personagens/ual2/clips/zombie_idle.tres",
	"walk": "res://assets/personagens/ual2/clips/zombie_walk_fwd.tres",
	"run": "res://assets/personagens/downloaded/movements/run_in_place.tres",
	"attack": "res://assets/personagens/downloaded/movements/punch.tres",
}
## Velocidade de chão do andar de zumbi (m/s a 1×), medida em build_ual2_clips.gd.
const WALK_GROUND_SPEED := 0.63
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")
# [osso de, osso até, zona, raio]
const HITBOXES := [
	["Head", "HeadTop_End", "head", 0.12],
	["Neck", "Head", "chest", 0.07],
	["Spine2", "Neck", "chest", 0.15],
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
var strike := -1.0 # progresso do golpe 0..1 (o zumbi informa); < 0 = sem golpe
var _clip := ""
var _phase := randf() * TAU
var _lod_accum := 0.0
var _frame := randi() % 4
var _mesh: MeshInstance3D
var _last_lod := -1

static func available() -> bool:
	return ResourceLoader.exists(MODEL)

## Curva do golpe para o progresso `s` (0..1): x = preparação (braços sobem,
## corpo recua), y = bote (avança e desce os braços), z = recuperação,
## w = inclinação do tronco (negativa = para trás, positiva = para a frente).
static func strike_curve(s: float) -> Vector4:
	var w := smoothstep(0.0, 0.4, s)
	var p := smoothstep(0.4, 0.56, s)
	var r := smoothstep(0.56, 1.0, s)
	var lean := -0.25 * w * (1.0 - p) + 0.55 * p * (1.0 - r)
	return Vector4(w, p, r, lean)

## Passo à frente do corpo no bote (metros), recuando um pouco na preparação.
static func strike_lunge(s: float) -> float:
	var c := strike_curve(s)
	return -0.08 * c.x * (1.0 - c.y) + 0.38 * c.y * (1.0 - c.z)

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
	_build_caps()

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
		if ResourceLoader.exists(CLIPS[name]):
			sources[name] = load(CLIPS[name]) as Animation
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
## `frozen`: fora da tela — mantém a pose atual sem avançar o esqueleto.
func animate(delta: float, state: int, move_rate: float, lod: int, frozen: bool = false) -> void:
	if player == null:
		return
	match state:
		Anim.IDLE: _play("idle", 0.6)
		# move_rate = velocidade / 2,4 (zombie.gd); o arrasto anda 0,63 m/s por ciclo.
		Anim.WALK: _play("walk", clampf(move_rate * 2.4 / WALK_GROUND_SPEED * 0.8, 0.7, 1.9))
		Anim.RUN: _play("run" if player.has_animation("run") else "walk", 0.95 * move_rate)
		Anim.ATTACK: _play("idle", 1.0) # o bote é feito na pose (tronco e braços)
	_phase += delta
	flinch = move_toward(flinch, 0.0, delta * 4.0)
	# O corpo todo dá o passo do bote (até de longe, para ler a ameaça).
	position.z = -strike_lunge(strike) if strike >= 0.0 else move_toward(position.z, 0.0, delta * 2.0)
	if lod != _last_lod and _mesh != null:
		_last_lod = lod
		# Sombra só de perto (de longe ninguém nota e custa redesenhar o corpo).
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if lod >= 2 or frozen:
		return
	_lod_accum += delta
	_frame += 1
	if lod == 1 and _frame % 3 != 0:
		return
	player.advance(_lod_accum)
	_lod_accum = 0.0
	_zombie_pose(state) # barato agora: também no médio, para os braços não voltarem à pose de fuzil

## Pose de zumbi por cima do clipe. Só rotações locais já calculadas (sem ler
## a pose global do esqueleto, que recalculava os 65 ossos várias vezes por quadro).
func _zombie_pose(state: int) -> void:
	if _pose.is_empty():
		_bake_pose()
	# Parado no alcance sem golpe: balança tentando agarrar, mais contido.
	var lunge := (0.5 + 0.5 * sin(_phase * 4.0)) * 0.4 if state == Anim.ATTACK else 0.0
	var striking := strike >= 0.0
	var curve := strike_curve(strike) if striking else Vector4.ZERO
	# Tronco do zumbi no lugar do tronco do clipe (que segura um fuzil e gira o peito).
	for bone in _pose["upper_body"]:
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion())
	var hips: int = _pose["hips"]
	var spine0: int = _pose["spine0"]
	if hips >= 0 and spine0 >= 0 and skeleton.get_bone_parent(spine0) == hips:
		var hips_global := skeleton.get_bone_pose_rotation(hips)
		var up := skeleton.get_bone_parent(hips)
		if up >= 0:
			hips_global = skeleton.get_bone_global_pose(up).basis.get_rotation_quaternion() * hips_global
		skeleton.set_bone_pose_rotation(spine0, hips_global.inverse() * (_pose["spine0_rest"] as Quaternion))
	var spine: int = _pose["spine"]
	if spine >= 0:
		var lean := (0.15 if state == Anim.RUN else 0.0) + lunge * 0.35 - flinch * 0.5
		var chest_undo := -lean
		if striking:
			# No golpe o peito acompanha (o peso do corpo vai junto com os braços).
			lean = curve.w - flinch * 0.5
			chest_undo = -lean * 0.3
		skeleton.set_bone_pose_rotation(spine, Quaternion(_pose["spine_axis"], BASE_LEAN + lean) * skeleton.get_bone_rest(spine).basis.get_rotation_quaternion())
		# O peito desfaz a inclinação extra: o corpo avança, os braços seguem retos para a frente.
		var chest_bone := _bone("Spine2")
		if chest_bone >= 0 and skeleton.get_bone_parent(chest_bone) == spine:
			skeleton.set_bone_pose_rotation(chest_bone, Quaternion(_pose["spine_axis"], chest_undo) * skeleton.get_bone_rest(chest_bone).basis.get_rotation_quaternion())
	var head: int = _pose["head"]
	if head >= 0:
		# No bote a cabeça projeta para a frente (a mordida).
		var bite := curve.y * (1.0 - curve.z) * 0.35 - curve.x * (1.0 - curve.y) * 0.15
		var wobble := Quaternion(_pose["head_roll"], sin(_phase * 1.3) * 0.22 * (1.0 - curve.x)) * Quaternion(_pose["head_axis"], 0.25 + bite + sin(_phase * 0.7) * 0.08)
		skeleton.set_bone_pose_rotation(head, wobble * skeleton.get_bone_rest(head).basis.get_rotation_quaternion())
	for side in ["Left", "Right"]:
		var arm: Dictionary = _pose.get(side, {})
		if arm.is_empty():
			continue
		var k := 0.5 + 0.5 * sin(_phase * 2.1 + (0.0 if side == "Left" else 1.7)) * 0.35
		if state == Anim.ATTACK:
			# Mãos sobem e descem alternadas, tentando agarrar.
			k = 0.5 + 0.5 * sin(_phase * 7.0 + (0.0 if side == "Left" else PI))
		var low: Array = arm["low"]
		var high: Array = arm["high"]
		if striking and arm.has("raise"):
			# Golpe: do meio sobe (prepara), desce de cima para baixo (bote) e volta ao meio.
			# O braço direito vem um tiquinho depois, para não parecer robô.
			var c := strike_curve(maxf(0.0, strike - (0.0 if side == "Left" else 0.035)))
			var raise: Array = arm["raise"]
			for j in 2:
				var mid := (low[j] as Quaternion).slerp(high[j], 0.5)
				var q := mid.slerp(raise[j], c.x).slerp(low[j], c.y).slerp(mid, c.z)
				skeleton.set_bone_pose_rotation(arm["upper"] if j == 0 else arm["lower"], q)
		else:
			skeleton.set_bone_pose_rotation(arm["upper"], (low[0] as Quaternion).slerp(high[0], k))
			skeleton.set_bone_pose_rotation(arm["lower"], (low[1] as Quaternion).slerp(high[1], k))
		skeleton.set_bone_pose_rotation(arm["hand"], arm["hand_q"])

var _pose: Dictionary = {}
static var _pose_cache: Dictionary = {}
const BASE_LEAN := 0.32 # tronco curvado para a frente (radianos)

## Calcula uma vez (na pose de descanso) as rotações locais dos braços esticados
## para a frente, mais alto e mais baixo, e os eixos de inclinação do tronco e da cabeça.
func _bake_pose() -> void:
	if _pose_cache.has("pose"):
		_pose = _pose_cache["pose"]
		return
	var saved: Array = []
	for i in skeleton.get_bone_count():
		saved.append([skeleton.get_bone_pose_position(i), skeleton.get_bone_pose_rotation(i), skeleton.get_bone_pose_scale(i)])
	skeleton.reset_bone_poses()
	var pose := {"spine": _bone("Spine1"), "head": _bone("Head"), "upper_body": []}
	for name in ["Spine2", "Neck", "LeftShoulder", "RightShoulder"]:
		if _bone(name) >= 0:
			pose["upper_body"].append(_bone(name))
	# Base da coluna: desfaz o giro do quadril do clipe (postura de fuzil de lado).
	pose["hips"] = _bone("Hips")
	pose["spine0"] = _bone("Spine")
	if pose["spine0"] >= 0:
		pose["spine0_rest"] = skeleton.get_bone_global_rest(pose["spine0"]).basis.get_rotation_quaternion()
	var forward := Vector3(0, 0, 1) # frente do modelo no espaço do esqueleto
	for key in [["spine", "spine_axis", Vector3.RIGHT], ["head", "head_axis", Vector3.RIGHT], ["head", "head_roll", Vector3.FORWARD]]:
		var bone: int = pose[key[0]]
		var parent := skeleton.get_bone_parent(bone) if bone >= 0 else -1
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
		pose[key[1]] = (parent_basis.inverse() * (key[2] as Vector3)).normalized()
	# Braços calculados com o tronco já curvado, para ficarem na horizontal.
	var lean_bone: int = pose["spine"]
	if lean_bone >= 0:
		skeleton.set_bone_pose_rotation(lean_bone, Quaternion(pose["spine_axis"], BASE_LEAN) * skeleton.get_bone_rest(lean_bone).basis.get_rotation_quaternion())
	var chest := _bone("Spine2")
	var torso := skeleton.get_bone_global_pose(chest).origin if chest >= 0 else Vector3.ZERO
	for side in ["Left", "Right"]:
		var upper := _bone(side + "Arm")
		var lower := _bone(side + "ForeArm")
		var hand := _bone(side + "Hand")
		if upper < 0 or lower < 0 or hand < 0 or chest < 0:
			continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var lateral := shoulder - torso
		lateral.y = 0.0
		lateral = lateral.normalized()
		var arm := {"upper": upper, "lower": lower, "hand": hand, "hand_q": skeleton.get_bone_rest(hand).basis.get_rotation_quaternion()}
		# [nome, altura, alcance à frente, abertura]: "raise" = braços erguidos para o golpe.
		for spec in [["low", -0.16, 0.56, 0.03], ["high", 0.12, 0.56, 0.03], ["raise", 0.42, 0.3, 0.1]]:
			var target := shoulder + forward * float(spec[2]) + lateral * float(spec[3]) + Vector3(0, float(spec[1]), 0)
			_two_bone_ik(upper, lower, hand, target, lateral * 0.5 + Vector3(0, -1, 0))
			arm[spec[0]] = [skeleton.get_bone_pose_rotation(upper), skeleton.get_bone_pose_rotation(lower)]
			skeleton.reset_bone_pose(upper)
			skeleton.reset_bone_pose(lower)
		pose[side] = arm
	for i in saved.size():
		skeleton.set_bone_pose_position(i, saved[i][0])
		skeleton.set_bone_pose_rotation(i, saved[i][1])
		skeleton.set_bone_pose_scale(i, saved[i][2])
	_pose = pose
	_pose_cache["pose"] = pose

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

## Partes do corpo [osso de, osso até, zona, raio] para a conta do tiro.
var _caps: Array = []

func _build_caps() -> void:
	for spec in HITBOXES:
		var from := _find_bone(spec[0])
		var to := _find_bone(spec[1])
		if from >= 0 and to >= 0:
			_caps.append([from, to, spec[2], float(spec[3])])

## Raio contra as cápsulas dos ossos (pose atual): a mais próxima de quem atira.
func resolve_ray(origin: Vector3, direction: Vector3) -> Dictionary:
	if skeleton == null:
		return {}
	var dir := direction.normalized()
	var to_world := skeleton.global_transform
	var size := global_basis.get_scale().y
	var best_t := INF
	var best := {}
	for cap in _caps:
		var a: Vector3 = to_world * skeleton.get_bone_global_pose(cap[0]).origin
		var b: Vector3 = to_world * skeleton.get_bone_global_pose(cap[1]).origin
		var radius: float = float(cap[3]) * size
		# Pontos mais próximos entre o raio (origin + dir*t) e o segmento a-b.
		var ab := b - a
		var w := origin - a
		var aa := ab.dot(ab)
		var bd := ab.dot(dir)
		var denom := aa - bd * bd
		var s := 0.0
		if aa > 0.000001 and absf(denom) > 0.000001:
			s = clampf((ab.dot(w) - bd * dir.dot(w)) / denom, 0.0, 1.0)
		var on_bone := a + ab * s
		var t := maxf(0.0, (on_bone - origin).dot(dir))
		var on_ray := origin + dir * t
		var d := on_ray.distance_to(on_bone)
		if d > radius:
			continue
		var entry := t - sqrt(maxf(0.0, radius * radius - d * d))
		if entry < best_t:
			best_t = entry
			var point := origin + dir * maxf(entry, 0.0)
			var normal := (point - on_bone)
			best = {"zone": cap[2], "position": point, "normal": normal.normalized() if normal.length_squared() > 0.0001 else -dir}
	return best
