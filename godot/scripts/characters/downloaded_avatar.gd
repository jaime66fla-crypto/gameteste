extends Node3D
## Adapter for Mixamo-rigged avatars (default: the 65-bone Ch31).
## Other Mixamo characters reuse every clip, IK and pose layer here: a subclass
## sets `model_path` / `source_height` in _init() and the clips (authored on the
## Ch31 "mixamorig9_" rig) are remapped to the model's own bone prefix.
## Ch31 rig the shared clips were authored on.
const CLIP_PREFIX := "mixamorig9_"
const CLIP_HIPS_HEIGHT := 0.957042 # Ch31 Hips rest height (m), tools/characters/export_shared_run.gd
const RUN_IN_PLACE := preload("res://assets/personagens/downloaded/movements/run_in_place.tres")
var model_path := "res://assets/personagens/downloaded/avatar.fbx"
## Height of the source mesh (m); the model is scaled to the 1.8 m player.
var source_height := 1.782
## Mixamo models face +Z; the game character faces -Z.
var model_yaw := PI
var bone_prefix := CLIP_PREFIX
const WALK_WITH_RIFLE := preload("res://assets/personagens/downloaded/movements/walk_with_rifle.tres")
const RUN_TO_STOP := preload("res://assets/personagens/downloaded/movements/run_to_stop.tres")
const PUNCH := preload("res://assets/personagens/downloaded/movements/punch.tres")
const ELBOW_PUNCH := preload("res://assets/personagens/downloaded/movements/elbow_punch.tres")
const IDLE_WITH_RIFLE := preload("res://assets/personagens/downloaded/movements/idle_with_rifle.tres")
# Unarmed (GTA-style) locomotion, retargeted by tools/characters/build_unarmed_locomotion.gd.
const IDLE_UNARMED := preload("res://assets/personagens/downloaded/movements/idle_unarmed.tres")
const UNARMED_DIR := "res://assets/personagens/downloaded/movements/"
## 8-way unarmed cycles, by movement angle (0 = forward, +90 = right): the
## forward clip has no suffix ("walk_unarmed"), the others do ("walk_unarmed_left").
const DIRECTION_SUFFIXES := ["", "_forward_right", "_right", "_backward_right", "_backward", "_backward_left", "_left", "_forward_left"]
## Extra degrees past a sector edge before switching (stops flicker on diagonals).
const DIRECTION_HYSTERESIS := 8.0
## Unarmed: below this speed (m/s) the character walks, above it jogs.
const UNARMED_JOG_SPEED := 2.3
## Playback rate limits: past them the stride slides a little instead of the
## legs turning over unnaturally fast (the game moves at 5 m/s, a fast jog).
const UNARMED_RATE_MIN := 0.75
const UNARMED_RATE_MAX := 1.45
## Clips whose own arm swing is kept (no procedural "relaxed arms" on top).
const NATURAL_ARM_CLIPS := ["run_in_place", "run_to_stop", "idle_unarmed"]

static func _has_natural_arms(clip: String) -> bool:
	return clip in NATURAL_ARM_CLIPS or clip.begins_with("walk_unarmed") or clip.begins_with("jog_unarmed")
const Grip = preload("res://scripts/characters/swat_grip.gd")
const BackpackModel = preload("res://scripts/survival/backpack_model.gd")
const StaffModel = preload("res://scripts/weapons/staff_model.gd")
## Bones every pose layer needs; a model missing one is rejected (not ready).
const REQUIRED_BONES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "RightHandMiddle1", "RightHandIndex1", "RightHandPinky1", "LeftHandMiddle1", "LeftHandIndex1", "LeftHandPinky1"]
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var weapon_mount: Node3D
var bound_weapon: Node3D
var weapon_id := "pistol"
var current_clip := ""
var armed := true
var ready_ok := false
var locomotion_active := false
# Aim: the rifle clips hold the gun ~20° right and ~17° down from the body's
# facing (low ready), so the barrel never matched the crosshair. The owner sets
# the world point under the crosshair; the mount turns the barrel onto it
# (pivoting on the trigger hand) and the arm IK follows.
const MAX_AIM_CORRECTION := deg_to_rad(70.0)
var aim_target := Vector3.ZERO
var aim_active := false
var aim_weight := 0.0

func _ready() -> void:
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	model.name = "Avatar"
	model.rotation.y = model_yaw
	# Scale the source mesh to the 1.8 m player height (real-size weapons depend on it).
	model.scale = Vector3.ONE * (1.8 / source_height)
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null:
		return
	if animation_player == null:
		# Static T-pose exports carry no AnimationPlayer: add one beside the skeleton.
		animation_player = AnimationPlayer.new()
		animation_player.name = "AnimationPlayer"
		model.add_child(animation_player)
	for bone_name in REQUIRED_BONES:
		if Grip._bone(skeleton, bone_name) < 0:
			push_warning("Avatar %s sem o osso %s" % [model_path, bone_name])
			return
	var hip_bone := Grip._bone(skeleton, "Hips")
	bone_prefix = String(skeleton.get_bone_name(hip_bone)).trim_suffix("Hips")
	var skeleton_path := String(animation_player.get_node(animation_player.root_node).get_path_to(skeleton))
	var hip_scale := skeleton.get_bone_rest(hip_bone).origin.y / CLIP_HIPS_HEIGHT
	var retarget := bone_prefix != CLIP_PREFIX or skeleton_path != "Skeleton3D" or absf(hip_scale - 1.0) > 0.01
	var library := AnimationLibrary.new()
	# Anchor every clip's Hips horizontally at the skeleton rest position, so the
	# visible body stays centred on the character origin (collision, camera,
	# network position). The recorded clips drift up to ~0.76 m forward;
	# vertical bob is kept. CharacterBody3D owns horizontal movement.
	var hip_anchor: Vector3 = skeleton.get_bone_rest(hip_bone).origin
	# Shared run cycle (exported from Ch31's FBX): ~2.8 m per 0.7 s cycle (4 m/s).
	var clips := {"run_in_place": RUN_IN_PLACE, "idle_with_rifle": IDLE_WITH_RIFLE, "walk_with_rifle": WALK_WITH_RIFLE, "run_to_stop": RUN_TO_STOP, "punch": PUNCH, "elbow_punch": ELBOW_PUNCH, "idle_unarmed": IDLE_UNARMED}
	for gait in ["walk_unarmed", "jog_unarmed"]:
		for suffix in DIRECTION_SUFFIXES:
			var unarmed_clip := load(UNARMED_DIR + gait + suffix + ".tres") as Animation
			if unarmed_clip != null:
				clips[gait + suffix] = unarmed_clip
	for clip_name in clips:
		# Duplicate: the preloaded resources are shared between avatars.
		var clip := (clips[clip_name] as Animation).duplicate() as Animation
		if retarget:
			_retarget_clip(clip, skeleton_path, hip_scale)
		if clip_name == "run_in_place":
			clip.loop_mode = Animation.LOOP_LINEAR
		_make_in_place(clip, hip_anchor)
		library.add_animation(clip_name, clip)
	if animation_player.has_animation_library(""):
		animation_player.remove_animation_library("")
	animation_player.add_animation_library("", library)
	_load_ual_clips(skeleton_path, hip_scale, retarget, hip_anchor)
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	skeleton.add_child(weapon_mount)
	for side in ["Right", "Left"]:
		var marker := Marker3D.new()
		marker.name = side + "Grip"
		weapon_mount.add_child(marker)
	ready_ok = true
	_play_clip("idle_with_rifle", 1.0)

func is_visual_ready() -> bool:
	return ready_ok

## Moves a Ch31 clip onto this model's rig: bone names get the model prefix,
## the skeleton path follows the model hierarchy, and only the Hips keeps its
## position track (scaled to this rig's hip height). Other position/scale
## tracks would force Ch31's bone lengths onto a differently built body.
## Rotations transfer as-is: Mixamo rigs share the T-pose rest orientation.
func _retarget_clip(clip: Animation, skeleton_path: String, hip_scale: float) -> void:
	for track in range(clip.get_track_count() - 1, -1, -1):
		var bone := String(clip.track_get_path(track)).get_slice(":", 1)
		var suffix := bone.trim_prefix(CLIP_PREFIX)
		if suffix.begins_with("mixamorig"):
			suffix = suffix.get_slice(":", 1) if suffix.contains(":") else suffix.substr(suffix.find("_") + 1)
		var target := bone_prefix + suffix
		var type := clip.track_get_type(track)
		if skeleton.find_bone(target) < 0 or type == Animation.TYPE_SCALE_3D or (type == Animation.TYPE_POSITION_3D and suffix != "Hips"):
			clip.remove_track(track)
			continue
		clip.track_set_path(track, NodePath(skeleton_path + ":" + target))
		if type == Animation.TYPE_POSITION_3D:
			for key in clip.track_get_key_count(track):
				clip.track_set_key_value(track, key, (clip.track_get_key_value(track, key) as Vector3) * hip_scale)

func _make_in_place(clip: Animation, hip_anchor: Vector3) -> void:
	var hips_name := bone_prefix + "Hips"
	for track in range(clip.get_track_count() - 1, -1, -1):
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not String(clip.track_get_path(track)).ends_with(":" + hips_name):
			continue
		for key in clip.track_get_key_count(track):
			var position: Vector3 = clip.track_get_key_value(track, key)
			clip.track_set_key_value(track, key, Vector3(hip_anchor.x, position.y, hip_anchor.z))

func configure_weapon(id: String, _model_scale: float = 1.0) -> void:
	weapon_id = id

func bind_weapon(model: Node3D) -> void:
	bound_weapon = model
	if bound_weapon != null:
		bound_weapon.set_meta("weapon_id", weapon_id)
		_update_weapon_mount()

func set_armed(value: bool) -> void:
	armed = value

## World point the barrel should point at; inactive while sprinting/reloading.
func set_aim_target(point: Vector3, active: bool) -> void:
	aim_target = point
	aim_active = active

func animate(delta: float, move_amount: float, running: bool, crouched: bool, _aiming: bool, airborne: bool, _reloading: bool, _movement_direction: Vector2 = Vector2(0, -1), planar_velocity: Vector3 = Vector3.ZERO) -> void:
	if not ready_ok:
		return
	aim_weight = move_toward(aim_weight, 1.0 if aim_active else 0.0, delta * 7.0)
	_last_delta = delta
	_airborne = airborne
	_planar_speed = Vector2(planar_velocity.x, planar_velocity.z).length()
	prone_weight = move_toward(prone_weight, 1.0 if prone_requested and not airborne else 0.0, delta * 3.0)
	crouch_weight = move_toward(crouch_weight, 1.0 if crouched and not airborne and prone_weight < 0.01 and not prone_requested else 0.0, delta * 6.0)
	unarmed_weight = move_toward(unarmed_weight, 0.0 if armed else 1.0, delta * 6.0)
	animation_player.advance(delta)
	var moving := move_amount > 0.08 and not airborne
	locomotion_active = moving
	_move_amount = move_amount if moving else 0.0
	_update_idle_fidget(moving)
	if current_clip in ["punch", "elbow_punch"] and animation_player.is_playing():
		_apply_crouch()
		_update_weapon_mount()
		_update_backpack()
		return
	if current_clip in ["punch", "elbow_punch"] and not animation_player.is_playing():
		current_clip = ""
	if current_clip == "run_to_stop" and animation_player.is_playing() and not moving:
		_finish_pose()
		return
	var clip := "idle_with_rifle"
	if prone_weight > 0.5:
		# Deitado: pernas paradas do clipe; o rastejar é feito na pose.
		_crawl_time += delta * (6.0 * _move_amount)
		_play_clip("idle_with_rifle", 1.0)
		_finish_pose()
		return
	if not armed:
		_play_unarmed(moving, running, planar_velocity)
		_finish_pose()
		return
	if moving:
		# Agachado não corre: anda devagar com as pernas dobradas.
		clip = "run_in_place" if running and crouch_weight < 0.5 else "walk_with_rifle"
	elif current_clip == "run_in_place":
		clip = "run_to_stop"
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	var gait_rate := clampf(speed / (4.0 if running else 2.8), 0.75, 2.2) if moving else 1.0
	_play_clip(clip, gait_rate)
	_finish_pose()

## Sem arma (estilo GTA): parado respira solto, devagar anda, normal trota e
## Shift corre. Cada ciclo toca na velocidade do chão medida no clipe, para o
## pé não deslizar (dentro dos limites de UNARMED_RATE_*).
func _play_unarmed(moving: bool, running: bool, planar_velocity: Vector3) -> void:
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	if not moving:
		# Stopping from a sprint plays the brake clip first (handled in animate()).
		_play_clip("run_to_stop" if current_clip == "run_in_place" else "idle_unarmed", 1.0)
		return
	# Movement angle in the character's frame (forward is -Z): 0 forward, +90 right.
	var angle := rad_to_deg(atan2(planar_velocity.x, -planar_velocity.z))
	_direction_sector = _pick_sector(angle)
	var suffix: String = DIRECTION_SUFFIXES[_direction_sector]
	# The sprint clip only runs forward; sideways/backward sprints jog that way.
	if running and crouch_weight < 0.5 and absf(angle) <= 60.0:
		_play_clip("run_in_place", clampf(speed / 4.0, 0.75, 2.2))
		return
	# Hysteresis so the gait does not flicker around the threshold.
	var jog_threshold := UNARMED_JOG_SPEED - (0.3 if current_clip.begins_with("jog_unarmed") else 0.0)
	var gait := "jog_unarmed" if speed > jog_threshold and crouch_weight < 0.5 else "walk_unarmed"
	var clip := gait + suffix
	if not animation_player.has_animation(clip):
		clip = gait
	var ground := float(animation_player.get_animation(clip).get_meta("ground_speed", 1.5))
	_play_cycle(clip, clampf(speed / maxf(ground, 0.1), UNARMED_RATE_MIN, UNARMED_RATE_MAX))

var _direction_sector := 0

## 45° sector for the movement angle, kept until the angle is clearly past it.
func _pick_sector(angle: float) -> int:
	var centre := _direction_sector * 45.0
	if absf(wrapf(angle - centre, -180.0, 180.0)) <= 22.5 + DIRECTION_HYSTERESIS:
		return _direction_sector
	return posmod(int(round(angle / 45.0)), 8)

## Switches between cycles of the same gait at the same phase of the step, so
## changing direction does not restart the stride (no foot pop).
func _play_cycle(clip: String, rate: float) -> void:
	if current_clip != clip:
		var same_gait := current_clip.get_slice("_", 0) == clip.get_slice("_", 0) and _has_natural_arms(current_clip) and current_clip != "idle_unarmed"
		var phase := 0.0
		if same_gait and animation_player.current_animation_length > 0.0:
			phase = animation_player.current_animation_position / animation_player.current_animation_length
		current_clip = clip
		animation_player.play(clip, 0.2)
		if same_gait:
			animation_player.seek(phase * animation_player.current_animation_length, false)
	animation_player.speed_scale = rate

## Depois do clipe: agachar (pernas), arma nas mãos ou braços soltos.
func _finish_pose() -> void:
	_advance_overlay()
	_apply_crouch()
	_apply_stand_pose()
	_apply_foot_ik()
	_apply_prone()
	_apply_body_dynamics()
	if not work_action.is_empty():
		_apply_work()
		_apply_overlay()
		_update_backpack()
		return
	# An action that uses the hands puts the gun away while it plays.
	var hands_busy := _overlay_arm_weight() > 0.3
	if is_instance_valid(bound_weapon):
		bound_weapon.visible = armed and not hands_busy
	_update_weapon_mount()
	# Correndo desarmado, o próprio clipe de corrida já balança os braços
	# naturalmente: só andando/parado os braços descem para o lado do corpo.
	var running_clip := _has_natural_arms(current_clip)
	_run_arms = move_toward(_run_arms, 1.0 if running_clip else 0.0, _last_delta * 5.0)
	if prone_weight > 0.01 and unarmed_weight > 0.01:
		_prone_arms(unarmed_weight)
	elif unarmed_weight * (1.0 - _run_arms) > 0.01:
		_relax_arms(unarmed_weight * (1.0 - _run_arms))
	_apply_overlay()
	_update_backpack()

# ------------------------------------------------------ dinâmica do corpo ---
# Camada por cima do clipe que dá peso ao movimento:
# - armado, nas curvas o tronco inclina para dentro (giro × velocidade);
#   desarmado quem inclina é o player.gd (turn_lean, o corpo todo);
# - ao acelerar o tronco vai um pouco para a frente, ao frear volta para trás;
# - mirando, a coluna divide a inclinação vertical da mira (cima/baixo) e a
#   cabeça completa o resto, então a arma não sobe só com os braços;
# - sem mirar, a cabeça acompanha de leve o ponto da mira.
# Tudo amortecido de forma independente do FPS (1 - exp(-k·dt)).
const BANK_MAX := 0.11 # rad de inclinação lateral nas curvas (só armado)
const BANK_GAIN := 0.035 # rad por (rad/s × m/s)
const ACCEL_LEAN_MAX := 0.09 # rad para a frente/trás
const ACCEL_LEAN_GAIN := 0.018 # rad por m/s²
const AIM_PITCH_MAX := deg_to_rad(55.0)
const SPINE_AIM_SHARE := [0.22, 0.24, 0.26] # Spine, Spine1, Spine2 (o resto vai para a cabeça e a arma)
const HEAD_LOOK_SHARE := 0.35
var _planar_speed := 0.0
var _last_yaw := 0.0
var _has_last_yaw := false
var _last_speed := 0.0
var _bank := 0.0
var _accel_lean := 0.0
var _aim_pitch := 0.0
var _look_weight := 0.0

func _damp(current: float, target: float, rate: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * _last_delta))

func _apply_body_dynamics() -> void:
	if not is_inside_tree() or _last_delta <= 0.0:
		return
	var yaw := global_basis.get_euler().y
	var turn_rate := 0.0
	if _has_last_yaw:
		turn_rate = wrapf(yaw - _last_yaw, -PI, PI) / _last_delta
	_last_yaw = yaw
	_has_last_yaw = true
	var speed := _planar_speed
	var accel := (speed - _last_speed) / _last_delta
	_last_speed = speed
	var grounded := not _airborne and prone_weight < 0.01 and work_action.is_empty()
	# Unarmed, player.gd already rolls the whole avatar into turns (turn_lean):
	# the spine bank only covers the armed case, where the body follows the camera.
	var bank_target := clampf(turn_rate * speed * BANK_GAIN, -BANK_MAX, BANK_MAX) * (1.0 - unarmed_weight) if grounded else 0.0
	var lean_target := clampf(accel * ACCEL_LEAN_GAIN, -ACCEL_LEAN_MAX, ACCEL_LEAN_MAX) if grounded else 0.0
	_bank = _damp(_bank, bank_target, 6.0)
	_accel_lean = _damp(_accel_lean, lean_target, 4.0)
	# Aim pitch in skeleton space (model faces +Z, up +Y): positive = target above the chest.
	var chest := Grip._bone(skeleton, "Spine2")
	var pitch_target := 0.0
	var aiming := aim_weight > 0.001 and armed and grounded and current_clip not in ["punch", "elbow_punch"]
	var look_valid := aim_active and aim_target != Vector3.ZERO
	if look_valid and chest >= 0:
		var local_target := skeleton.to_local(aim_target) - skeleton.get_bone_global_pose(chest).origin
		var horizontal := Vector2(local_target.x, local_target.z).length()
		if horizontal > 0.3:
			pitch_target = clampf(atan2(local_target.y, horizontal), -AIM_PITCH_MAX, AIM_PITCH_MAX)
	_aim_pitch = _damp(_aim_pitch, pitch_target, 10.0)
	_look_weight = _damp(_look_weight, 1.0 if look_valid and grounded else 0.0, 4.0)
	var spine_bones := ["Spine", "Spine1", "Spine2"]
	for i in spine_bones.size():
		var bone := Grip._bone(skeleton, spine_bones[i])
		if bone < 0:
			continue
		# +X rotation tips the top forward; the model's forward axis is +Z.
		var pitch := -_aim_pitch * float(SPINE_AIM_SHARE[i]) * aim_weight if aiming else 0.0
		var forward_lean := _accel_lean / 3.0
		# Turning left (yaw grows) leans to the model's left (+X): about -Z by +bank.
		var roll := _bank / 3.0
		if absf(pitch + forward_lean) + absf(roll) < 0.0005:
			continue
		var turn := Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch + forward_lean)
		Grip._set_global_rotation(skeleton, bone, turn * skeleton.get_bone_global_pose(bone).basis)
	var head := Grip._bone(skeleton, "Head")
	if head >= 0 and _look_weight > 0.001:
		var spine_share := 0.72 * aim_weight if aiming else 0.0
		var head_pitch := -_aim_pitch * clampf(1.0 - spine_share, 0.0, 1.0) * HEAD_LOOK_SHARE * _look_weight
		Grip._set_global_rotation(skeleton, head, Basis(Vector3.RIGHT, head_pitch) * skeleton.get_bone_global_pose(head).basis)

# -------------------------------------------------------------- deitado ---
# Deitado de bruços: o quadril gira 90° (cabeça para a frente, rosto para o
# chão) e desce até o chão; o peito levanta apoiado nos cotovelos e a cabeça
# olha para a frente. Armado, a arma aponta para a mira e as mãos seguem a arma.
# Andando deitado, rasteja: o quadril balança e os joelhos dobram alternados.
const PRONE_HIPS_HEIGHT := 0.17
var prone_requested := false
var prone_weight := 0.0
var _crawl_time := 0.0

func set_prone(value: bool) -> void:
	prone_requested = value

func _apply_prone() -> void:
	if prone_weight <= 0.001:
		return
	var w := _ease_in_out(prone_weight)
	var hips := Grip._bone(skeleton, "Hips")
	if hips < 0:
		return
	var crawl := sin(_crawl_time) * _move_amount
	var hips_global := skeleton.get_bone_global_pose(hips)
	var turn := Basis(Vector3.RIGHT, PI * 0.5 * w) * Basis(Vector3.FORWARD, crawl * 0.12 * w)
	Grip._set_global_rotation(skeleton, hips, turn * hips_global.basis)
	# Quadril desce até o chão (no espaço do esqueleto, Y para cima).
	var hips_now := skeleton.get_bone_global_pose(hips).origin
	var drop := Vector3(0, (PRONE_HIPS_HEIGHT - hips_now.y) * w, 0)
	var parent := skeleton.get_bone_parent(hips)
	if parent >= 0:
		drop = skeleton.get_bone_global_pose(parent).basis.inverse() * drop
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + drop)
	# Coluna e cabeça levantam (girar em X negativo leva a frente para cima).
	for spec in [["Spine", -0.18], ["Spine1", -0.2], ["Spine2", -0.18], ["Neck", -0.25], ["Head", -0.3]]:
		var bone := Grip._bone(skeleton, spec[0])
		if bone >= 0:
			Grip._set_global_rotation(skeleton, bone, Basis(Vector3.RIGHT, float(spec[1]) * w) * skeleton.get_bone_global_pose(bone).basis)
	# Pernas esticadas para trás, um pouco abertas; ao rastejar, um joelho sobe de cada vez.
	for side in ["Left", "Right"]:
		var up_leg := Grip._bone(skeleton, side + "UpLeg")
		var leg := Grip._bone(skeleton, side + "Leg")
		var sign := -1.0 if side == "Left" else 1.0
		if up_leg >= 0:
			skeleton.set_bone_pose_rotation(up_leg, skeleton.get_bone_pose_rotation(up_leg).slerp(skeleton.get_bone_rest(up_leg).basis.get_rotation_quaternion(), w))
			var bend := maxf(0.0, crawl * sign) * 0.9 * w
			# Perna deitada aponta para trás (-Z): abrir = girar no eixo vertical.
			Grip._set_global_rotation(skeleton, up_leg, Basis(Vector3.UP, sign * (0.12 + bend * 0.5) * w) * skeleton.get_bone_global_pose(up_leg).basis)
		if leg >= 0:
			skeleton.set_bone_pose_rotation(leg, skeleton.get_bone_pose_rotation(leg).slerp(skeleton.get_bone_rest(leg).basis.get_rotation_quaternion(), w))
			var knee := maxf(0.0, crawl * sign) * 0.9 * w
			if knee > 0.001:
				Grip._set_global_rotation(skeleton, leg, Basis(Vector3.RIGHT, knee) * skeleton.get_bone_global_pose(leg).basis) # pé sobe

## Deitado sem arma: antebraços no chão à frente dos ombros (apoiado nos cotovelos).
func _prone_arms(weight: float) -> void:
	var chest := Grip._bone(skeleton, "Spine2")
	if chest < 0:
		return
	var torso := skeleton.get_bone_global_pose(chest).origin
	var crawl := sin(_crawl_time) * _move_amount
	for side in ["Left", "Right"]:
		var upper := Grip._bone(skeleton, side + "Arm")
		var hand := Grip._bone(skeleton, side + "Hand")
		if upper < 0 or hand < 0:
			continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var lateral := shoulder - torso
		lateral.y = 0.0
		lateral = lateral.normalized()
		var reach := 0.32 + (crawl if side == "Left" else -crawl) * 0.12
		var target := Vector3(shoulder.x, 0.08, shoulder.z) + Vector3(0, 0, reach) - lateral * 0.06
		var current := skeleton.get_bone_global_pose(hand).origin
		_two_bone_ik(upper, Grip._bone(skeleton, side + "ForeArm"), hand, current.lerp(target, weight * prone_weight), lateral * 0.6 + Vector3(0, -1, 0))

# ------------------------------------------------- trabalho (machado etc.) ---
# Golpes com as duas mãos no cabo: levanta devagar por cima do ombro direito e
# desce rápido na frente (machado na árvore); "pry" é um golpe mais baixo
# (pé de cabra na pedra ou no carro). As mãos seguem o cabo por IK.
const WORK_CYCLE := 0.95
const TOOL_LOOK := {
	"axe": {"handle": 0.78, "color": Color("#8a6238"), "head": "axe"},
	"improvised_axe": {"handle": 0.70, "color": Color("#6e5236"), "head": "stone"},
	"crowbar": {"handle": 0.80, "color": Color("#2f3b52"), "head": "hook"},
	"bat": {"handle": 0.82, "color": Color("#b08a5a"), "head": "bat"},
	"long_bat": {"handle": 1.12, "color": Color("#7a5634"), "head": "bat"},
	# Ferramentas primitivas da floresta (cabo de galho, cabeça de pedra amarrada com fibra).
	"stone_axe": {"handle": 0.66, "color": Color("#6b5034"), "head": "stone"},
	"stone_pick": {"handle": 0.72, "color": Color("#6b5034"), "head": "pick"},
	"club": {"handle": 0.78, "color": Color("#5e4630"), "head": "bat"},
	"stone_knife": {"handle": 0.16, "color": Color("#6b5034"), "head": "blade"},
	# Era do metal (forja).
	"iron_axe": {"handle": 0.74, "color": Color("#5c4128"), "head": "axe"},
	"iron_pick": {"handle": 0.76, "color": Color("#5c4128"), "head": "pick"},
	"iron_knife": {"handle": 0.16, "color": Color("#3e3226"), "head": "blade"},
	"machete": {"handle": 0.14, "color": Color("#3e3226"), "head": "machete"},
	"wood_spear": {"handle": 1.1, "color": Color("#6b5034"), "head": "blade"},
	"nail_bat": {"handle": 0.82, "color": Color("#6a5238"), "head": "bat"},
}
# Golpe de arma branca (Q): "swing" arma atrás do ombro direito e varre de lado
# na frente do corpo, uma vez só (SWING_CYCLE segundos), girando o tronco.
const SWING_CYCLE := 0.55
var work_action := ""
var work_tool := ""
var _last_delta := 1.0 / 60.0
var _work_time := 0.0
var _tool_node: Node3D

## Acts sent over the network that play a UAL2 clip once instead of a tool loop.
const OVERLAY_ACTS := {"open": "open", "harvest": "harvest", "consume": "consume"}
var _overlay_act := ""

func set_action(act: String, tool: String) -> void:
	if OVERLAY_ACTS.has(act):
		if act != _overlay_act:
			_overlay_act = act
			play_action(OVERLAY_ACTS[act])
		act = ""
		tool = ""
	else:
		_overlay_act = ""
	if act == work_action and tool == work_tool:
		return
	work_action = act
	work_tool = tool
	_work_time = 0.0
	if _tool_node != null:
		_tool_node.queue_free()
		_tool_node = null
	if is_instance_valid(bound_weapon):
		bound_weapon.visible = act.is_empty() and armed
	if not act.is_empty() and TOOL_LOOK.has(tool) and skeleton != null:
		_tool_node = _build_tool(tool)
		skeleton.add_child(_tool_node)

func _tool_mat(color: Color, metal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.85 if metal else 0.0
	m.roughness = 0.3 if metal else 0.8
	return m

func _tool_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.rotation = rot
	mesh.material_override = mat
	parent.add_child(mesh)

## Ferramenta com o cabo ao longo de +Y (base em 0) e a lâmina para -Z.
func _build_tool(tool: String) -> Node3D:
	if tool == "long_bat":
		var staff := StaffModel.build(float(TOOL_LOOK[tool]["handle"]))
		staff.name = "WorkTool"
		return staff
	var look: Dictionary = TOOL_LOOK[tool]
	var node := Node3D.new()
	node.name = "WorkTool"
	var length := float(look["handle"])
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.022
	cyl.height = length
	cyl.radial_segments = 8
	handle.mesh = cyl
	handle.position.y = length * 0.5
	handle.material_override = _tool_mat(look["color"], tool == "crowbar")
	node.add_child(handle)
	var steel := _tool_mat(Color("#9aa0a4"), true)
	match str(look["head"]):
		"axe":
			_tool_box(node, Vector3(0, length - 0.05, -0.05), Vector3(0.03, 0.09, 0.16), steel)
			_tool_box(node, Vector3(0, length - 0.05, -0.15), Vector3(0.012, 0.17, 0.06), steel) # gume
			_tool_box(node, Vector3(0, length - 0.05, 0.05), Vector3(0.04, 0.06, 0.05), steel) # olho/martelo
		"stone":
			_tool_box(node, Vector3(0, length - 0.06, -0.07), Vector3(0.05, 0.1, 0.16), _tool_mat(Color("#77746c"), false), Vector3(0.2, 0, 0))
			_tool_box(node, Vector3(0, length - 0.06, 0.0), Vector3(0.06, 0.07, 0.06), _tool_mat(Color("#c9b98a"), false)) # amarração de corda
		"hook":
			_tool_box(node, Vector3(0, length + 0.03, -0.04), Vector3(0.022, 0.022, 0.1), handle.material_override)
			_tool_box(node, Vector3(0, -0.02, -0.03), Vector3(0.02, 0.02, 0.07), handle.material_override, Vector3(0.6, 0, 0))
		"bat":
			handle.mesh = cyl.duplicate()
			(handle.mesh as CylinderMesh).top_radius = 0.035
		"pick":
			# Pedra comprida atravessada no cabo (ponta para os dois lados), amarrada com fibra.
			var rock := _tool_mat(Color("#6f6c64"), false)
			_tool_box(node, Vector3(0, length - 0.05, -0.1), Vector3(0.045, 0.06, 0.16), rock, Vector3(0.25, 0, 0))
			_tool_box(node, Vector3(0, length - 0.05, 0.08), Vector3(0.04, 0.05, 0.1), rock, Vector3(-0.25, 0, 0))
			_tool_box(node, Vector3(0, length - 0.05, 0.0), Vector3(0.06, 0.07, 0.06), _tool_mat(Color("#c9b98a"), false))
		"blade":
			# Lasca de pedra afiada presa num cabo curto.
			_tool_box(node, Vector3(0, length + 0.07, 0), Vector3(0.012, 0.15, 0.045), _tool_mat(Color("#5d5b55"), false))
			_tool_box(node, Vector3(0, length, 0), Vector3(0.035, 0.035, 0.035), _tool_mat(Color("#c9b98a"), false))
		"machete":
			# Lâmina longa de ferro, mais larga perto da ponta, gume para -Z.
			var iron := _tool_mat(Color("#8c9094"), true)
			_tool_box(node, Vector3(0, length + 0.2, -0.005), Vector3(0.008, 0.4, 0.045), iron)
			_tool_box(node, Vector3(0, length + 0.34, -0.012), Vector3(0.008, 0.14, 0.06), iron)
			_tool_box(node, Vector3(0, length + 0.005, 0), Vector3(0.03, 0.012, 0.07), iron) # guarda
	return node

func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _apply_work() -> void:
	var hips := Grip._bone(skeleton, "Hips")
	var chest := Grip._bone(skeleton, "Spine2")
	var spine := Grip._bone(skeleton, "Spine")
	var right_arm := Grip._bone(skeleton, "RightArm")
	if hips < 0 or chest < 0 or right_arm < 0:
		return
	_work_time += _last_delta
	var right := Vector3(signf(skeleton.get_bone_global_pose(right_arm).origin.x), 0, 0)
	var family := tool_family(work_tool)
	if work_action == "hold":
		_apply_hold(chest, right_arm)
		return
	if work_action == "swing":
		match family:
			"axe", "pick":
				_apply_heavy_attack(family, chest, spine, right)
			"knife":
				_apply_stab(chest, spine, right)
			"machete":
				_apply_slash(chest, spine, right)
			"spear":
				_apply_thrust(chest, spine, right)
			_:
				_apply_swing(chest, spine, right_arm)
		return
	# Trabalho em loop (WORK_CYCLE): 0–50% prepara devagar, 50–64% golpe
	# acelerando, 64–100% tranco do impacto e volta um pouco.
	var t := fmod(_work_time, WORK_CYCLE) / WORK_CYCLE
	var p: Dictionary = WORK_STROKES["mine" if work_action == "pry" and family == "pick" else ("chop" if work_action == "chop" else "pry")]
	var raised := float(p["raised"])
	var struck := float(p["struck"])
	var theta := 0.0
	var impact := 0.0 # 0 preparando → 1 no impacto
	if t < 0.5:
		var k := _ease_in_out(t / 0.5)
		theta = lerpf(struck - 0.25, raised, k)
		impact = 0.0
	elif t < 0.64:
		var k := (t - 0.5) / 0.14
		theta = lerpf(raised, struck, k * k)
		impact = k * k
	else:
		var k := (t - 0.64) / 0.36
		# Tranco: a ferramenta para no alvo, quica um pouco e vai voltando.
		theta = struck - 0.08 * sin(PI * minf(k * 3.0, 1.0)) - 0.25 * _ease_in_out(k)
		impact = 1.0 - _ease_in_out(k)
	_stroke_two_hands(p, theta, impact, chest, spine, right)

## Como cada ferramenta é usada: "axe" e "pick" com as duas mãos, "knife" e
## "machete" com uma mão, "spear" estocando; o resto (bastões) varre de lado.
static func tool_family(tool: String) -> String:
	if tool in ["axe", "improvised_axe", "stone_axe", "iron_axe"]:
		return "axe"
	if tool in ["stone_pick", "iron_pick"]:
		return "pick"
	if tool in ["stone_knife", "iron_knife"]:
		return "knife"
	if tool == "machete":
		return "machete"
	if tool == "wood_spear":
		return "spear"
	return "blunt"

# Golpes de trabalho com as duas mãos no cabo, num plano inclinado por `tilt`
# (0 = de cima para baixo; ~1.3 = quase de lado). `theta` gira o cabo nesse
# plano: negativo = para trás do ombro direito, ~1.6 = apontando para a frente.
#  chop: machadada lateral no tronco, vindo do ombro direito para a cintura;
#  mine: picareta levantada acima da cabeça, desce na pedra com os joelhos dobrados;
#  pry: pé de cabra baixo (pedra/carro).
const WORK_STROKES := {
	"chop": {"tilt_raised": 0.8, "tilt_struck": 1.3, "raised": -0.75, "struck": 1.62,
		"reach_raised": 0.30, "reach_struck": 0.47, "twist_raised": 0.55, "twist_struck": -0.2,
		"lean": 0.15, "dip": 0.22, "pivot_up": -0.2},
	"mine": {"tilt_raised": 0.12, "tilt_struck": 0.05, "raised": -0.35, "struck": 2.5,
		"reach_raised": 0.30, "reach_struck": 0.5, "twist_raised": 0.15, "twist_struck": 0.0,
		"lean": 0.45, "dip": 0.42, "pivot_up": 0.02},
	"pry": {"tilt_raised": 0.0, "tilt_struck": 0.0, "raised": 0.7, "struck": 2.5,
		"reach_raised": 0.28, "reach_struck": 0.46, "twist_raised": 0.0, "twist_struck": 0.0,
		"lean": 0.3, "dip": 0.1, "pivot_up": 0.02},
}
var _work_dip := 0.0 # joelhos dobrando no golpe (somado ao agachar no quadro seguinte)

## Corpo + mãos + ferramenta para um golpe de duas mãos. `impact` 0..1 dá o
## peso do corpo: tronco inclina, gira para a esquerda e os joelhos dobram.
func _stroke_two_hands(p: Dictionary, theta: float, impact: float, chest: int, spine: int, right: Vector3) -> void:
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1) # frente do modelo no espaço do esqueleto
	var raised := float(p["raised"])
	var struck := float(p["struck"])
	var progress := clampf((theta - raised) / (struck - raised), 0.0, 1.0)
	var tilt := lerpf(float(p["tilt_raised"]), float(p["tilt_struck"]), progress)
	var twist := lerpf(float(p["twist_raised"]), float(p["twist_struck"]), progress)
	_work_dip = float(p["dip"]) * impact
	_turn_spine(spine, twist * signf(right.x), float(p["lean"]) * maxf(impact, progress * 0.5))
	var torso := skeleton.get_bone_global_pose(chest).origin
	var pivot := torso + right * 0.12 + up * float(p["pivot_up"]) + forward * 0.14
	var a := (up * cos(tilt) + right * sin(tilt)).normalized()
	var h := (a * cos(theta) + forward * sin(theta)).normalized()
	var swing := (-a * sin(theta) + forward * cos(theta)).normalized()
	# No alto as mãos ficam junto ao ombro; no impacto os braços esticam.
	var reach := lerpf(float(p["reach_raised"]), float(p["reach_struck"]), progress)
	var right_hand := pivot + h * reach
	var left_hand := pivot + h * (reach - 0.17)
	for spec in [["Right", right_hand, right], ["Left", left_hand, -right]]:
		var pole: Vector3 = (spec[2] as Vector3) * 0.6 - forward * 0.3 - up * 0.4
		_grip_on_staff(spec[0], spec[1], h, -swing, pole)
	_place_tool(h, -swing, pivot + h * (reach - 0.24))

## Gira o tronco (Spine) em volta do eixo vertical e inclina para a frente.
func _turn_spine(spine: int, yaw: float, lean: float) -> void:
	if spine < 0:
		return
	var basis := skeleton.get_bone_global_pose(spine).basis
	Grip._set_global_rotation(skeleton, spine, Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * basis)

## Ferramenta com o cabo em `axis` (base em `base`) e a lâmina/ponta virada para `edge`.
func _place_tool(axis: Vector3, edge: Vector3, base: Vector3) -> void:
	if _tool_node == null:
		return
	var y := axis.normalized()
	var z := -(edge - y * edge.dot(y)).normalized()
	if z.length_squared() < 0.01:
		z = Vector3(0, 0, 1)
	var x := y.cross(z).normalized()
	_tool_node.transform = Transform3D(Basis(x, y, z), base)

## Mão esquerda em guarda na frente do peito (golpes de uma mão).
func _left_guard(torso: Vector3, right: Vector3, amount: float) -> void:
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var target := torso - right * 0.14 + forward * lerpf(0.22, 0.3, amount) - up * lerpf(0.12, 0.05, amount)
	var hand := Grip._bone(skeleton, "LeftHand")
	_two_bone_ik(Grip._bone(skeleton, "LeftArm"), Grip._bone(skeleton, "LeftForeArm"), hand, target, -right * 0.6 - up * 0.5)
	if hand >= 0:
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_rest(hand).basis.get_rotation_quaternion())

## Machadada de ataque (machado/picareta no Q): um golpe só, diagonal de cima do
## ombro direito até a altura da cintura do alvo; picareta mais de cima para baixo.
func _apply_heavy_attack(family: String, chest: int, spine: int, right: Vector3) -> void:
	var t := clampf(_work_time / SWING_CYCLE, 0.0, 1.0)
	var p := {"tilt_raised": 0.75, "tilt_struck": 0.95, "raised": -0.8, "struck": 1.95,
		"reach_raised": 0.3, "reach_struck": 0.48, "twist_raised": 0.5, "twist_struck": -0.35,
		"lean": 0.25, "dip": 0.2, "pivot_up": 0.0}
	if family == "pick":
		p = {"tilt_raised": 0.2, "tilt_struck": 0.1, "raised": -0.4, "struck": 2.1,
			"reach_raised": 0.3, "reach_struck": 0.5, "twist_raised": 0.2, "twist_struck": -0.05,
			"lean": 0.35, "dip": 0.25, "pivot_up": 0.02}
	var rest := 1.2 # cabo apontando para a frente/baixo antes e depois do golpe
	var theta := 0.0
	var impact := 0.0
	if t < 0.4:
		theta = lerpf(rest, float(p["raised"]), _ease_in_out(t / 0.4))
	elif t < 0.58:
		var k := (t - 0.4) / 0.18
		theta = lerpf(float(p["raised"]), float(p["struck"]), k * k)
		impact = k * k
	else:
		var k := (t - 0.58) / 0.42
		theta = lerpf(float(p["struck"]), rest + 0.3, _ease_in_out(k))
		impact = 1.0 - _ease_in_out(k)
	_stroke_two_hands(p, theta, impact, chest, spine, right)

## Facada: puxa a faca para o quadril direito, estoca reto para a frente na
## altura do peito (o ombro vai junto) e volta para a guarda.
func _apply_stab(chest: int, spine: int, right: Vector3) -> void:
	var t := clampf(_work_time / SWING_CYCLE, 0.0, 1.0)
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var draw := 0.0 # 0 guarda, -1 puxada, 1 estocada
	if t < 0.3:
		draw = -_ease_in_out(t / 0.3)
	elif t < 0.48:
		var k := (t - 0.3) / 0.18
		draw = lerpf(-1.0, 1.0, k * k * (3.0 - 2.0 * k))
	else:
		draw = 1.0 - _ease_in_out((t - 0.48) / 0.52)
	var thrust := maxf(draw, 0.0)
	var back := maxf(-draw, 0.0)
	_work_dip = 0.15 * thrust
	_turn_spine(spine, (0.3 * back - 0.35 * thrust) * signf(right.x), 0.2 * thrust)
	var torso := skeleton.get_bone_global_pose(chest).origin
	var hand_pos := torso + right * lerpf(0.2, 0.06, thrust) + right * 0.04 * back \
		+ forward * (0.26 + 0.32 * thrust - 0.18 * back) - up * (0.12 + 0.08 * back - 0.04 * thrust)
	var axis := (forward + up * 0.08 - right * 0.1 * thrust).normalized()
	_grip_on_staff("Right", hand_pos, axis, -up, right * 0.6 - up * 0.5 - forward * 0.2)
	_left_guard(torso, right, thrust)
	_place_tool(axis, up, hand_pos - axis * 0.08)

## Golpe de facão com uma mão: lâmina sobe por cima do ombro direito e corta
## em diagonal até a frente do quadril esquerdo.
func _apply_slash(chest: int, spine: int, right: Vector3) -> void:
	var t := clampf(_work_time / SWING_CYCLE, 0.0, 1.0)
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var raised := -0.5
	var struck := 2.3
	var rest := 1.3
	var theta := 0.0
	var impact := 0.0
	if t < 0.35:
		theta = lerpf(rest, raised, _ease_in_out(t / 0.35))
	elif t < 0.55:
		var k := (t - 0.35) / 0.2
		theta = lerpf(raised, struck, k * k)
		impact = k * k
	else:
		var k := (t - 0.55) / 0.45
		theta = lerpf(struck, rest, _ease_in_out(k))
		impact = 1.0 - _ease_in_out(k)
	var progress := clampf((theta - raised) / (struck - raised), 0.0, 1.0)
	_work_dip = 0.12 * impact
	_turn_spine(spine, lerpf(0.45, -0.4, progress) * signf(right.x), 0.2 * impact)
	var torso := skeleton.get_bone_global_pose(chest).origin
	var shoulder := torso + right * 0.2 + up * 0.08
	var tilt := 0.8
	var a := (up * cos(tilt) + right * sin(tilt)).normalized()
	var h := (a * cos(theta) + forward * sin(theta)).normalized()
	var swing := (-a * sin(theta) + forward * cos(theta)).normalized()
	var hand_pos := shoulder + h * lerpf(0.36, 0.5, progress) + forward * 0.1
	_grip_on_staff("Right", hand_pos, h, -swing, right * 0.6 - up * 0.4 - forward * 0.2)
	_left_guard(torso, right, impact)
	_place_tool(h, swing, hand_pos - h * 0.1)

## Estocada de lança com as duas mãos: lança deitada na altura do peito, mão
## direita atrás e esquerda na frente; recua, avança o corpo e estoca.
func _apply_thrust(chest: int, spine: int, right: Vector3) -> void:
	var t := clampf(_work_time / SWING_CYCLE, 0.0, 1.0)
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var draw := 0.0
	if t < 0.32:
		draw = -_ease_in_out(t / 0.32)
	elif t < 0.5:
		var k := (t - 0.32) / 0.18
		draw = lerpf(-1.0, 1.0, k * k * (3.0 - 2.0 * k))
	else:
		draw = 1.0 - _ease_in_out((t - 0.5) / 0.5)
	var thrust := maxf(draw, 0.0)
	var back := maxf(-draw, 0.0)
	_work_dip = 0.25 * thrust
	_turn_spine(spine, (0.25 * back - 0.15 * thrust) * signf(right.x), 0.28 * thrust - 0.05 * back)
	var torso := skeleton.get_bone_global_pose(chest).origin
	# Mãos perto do corpo para os dois braços alcançarem o cabo; a lança anda
	# para a frente com o tronco e os braços na estocada.
	var axis := (forward - up * 0.03 - right * 0.06).normalized()
	var base := torso + right * 0.14 - up * 0.13 + forward * (-0.5 + 0.32 * thrust - 0.12 * back)
	var right_hand := base + axis * 0.3
	var left_hand := base + axis * 0.6
	_grip_on_staff("Right", right_hand, axis, -up, right * 0.6 - up * 0.5)
	_grip_on_staff("Left", left_hand, axis, -up, -right * 0.6 - up * 0.5)
	_place_tool(axis, up, base)

## Carregando a arma branca ("hold"): as duas mãos no cabo na frente do quadril
## direito e a arma deitada para trás por cima do ombro direito.
func _apply_hold(chest: int, right_arm: int) -> void:
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var right := Vector3(signf(skeleton.get_bone_global_pose(right_arm).origin.x), 0, 0)
	var torso := skeleton.get_bone_global_pose(chest).origin
	var h := (up * 0.85 - forward * 0.35 + right * 0.15).normalized()
	var right_hand := torso + right * 0.17 - up * 0.30 + forward * 0.22
	var left_hand := right_hand + h * 0.17
	for spec in [["Right", right_hand, right], ["Left", left_hand, -right]]:
		var pole: Vector3 = (spec[2] as Vector3) * 0.6 - forward * 0.4 - up * 0.3
		_grip_on_staff(spec[0], spec[1], h, forward, pole)
	if _tool_node != null:
		var y := h
		var z := (forward - h * forward.dot(h)).normalized()
		var x := y.cross(z).normalized()
		_tool_node.transform = Transform3D(Basis(x, y, z), right_hand - h * 0.1)

## Mão fechada no cabo: o meio da palma fica em `grip_point` (no eixo do
## cabo), os dedos dão a volta no cabo partindo de `fingers_dir` (só a parte
## perpendicular ao cabo vale) e o indicador aponta para a ponta da arma.
const STAFF_GRIP_RADIUS := 0.035 # do eixo do cabo até a palma (raio da empunhadura + palma)

func _grip_on_staff(side: String, grip_point: Vector3, axis: Vector3, fingers_dir: Vector3, pole: Vector3) -> void:
	var upper := Grip._bone(skeleton, side + "Arm")
	var lower := Grip._bone(skeleton, side + "ForeArm")
	var hand := Grip._bone(skeleton, side + "Hand")
	var middle := Grip._bone(skeleton, side + "HandMiddle1")
	var index := Grip._bone(skeleton, side + "HandIndex1")
	var pinky := Grip._bone(skeleton, side + "HandPinky1")
	if hand < 0 or middle < 0 or index < 0 or pinky < 0:
		_two_bone_ik(upper, lower, hand, grip_point, pole)
		return
	var rest_fingers := skeleton.get_bone_rest(middle).origin.normalized()
	var rest_across := skeleton.get_bone_rest(index).origin - skeleton.get_bone_rest(pinky).origin
	var rest_x := (rest_across - rest_fingers * rest_across.dot(rest_fingers)).normalized()
	var rest_frame := Basis(rest_x, rest_fingers, rest_x.cross(rest_fingers).normalized())
	var fingers := (fingers_dir - axis * fingers_dir.dot(axis)).normalized()
	var x := (axis - fingers * axis.dot(fingers)).normalized()
	var hand_basis := Basis(x, fingers, x.cross(fingers).normalized()) * rest_frame.inverse()
	# Lado da palma: para onde os dedos dobram ao fechar (Grip._close_fingers gira
	# em volta do eixo indicador–mindinho). O cabo fica desse lado, a um raio da
	# palma, para os dedos fecharem em volta dele (e não na frente dele).
	var hinge := (rest_across - rest_fingers * rest_across.dot(rest_fingers)).normalized()
	var palm_side := (hand_basis * hinge.cross(rest_fingers)).normalized()
	# Pegada de força: o eixo do cabo passa na linha dos nós dos dedos, um raio
	# para o lado da palma; os dedos saem dali e dão a volta no cabo.
	var knuckles := hand_basis * skeleton.get_bone_rest(middle).origin
	var wrist := grip_point - knuckles - palm_side * STAFF_GRIP_RADIUS
	_two_bone_ik(upper, lower, hand, wrist, pole)
	Grip._set_global_rotation(skeleton, hand, hand_basis)
	# Todos os dedos fechados no cabo (o indicador também: não é gatilho).
	for finger in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
		for segment in range(1, 4):
			var bone := Grip._bone(skeleton, side + "Hand" + finger + str(segment))
			if bone < 0:
				continue
			var angle: float = [1.0, 1.15, 0.8][segment - 1]
			var rotation := Quaternion(hinge, angle)
			if finger == "Thumb":
				# Polegar por cima dos dedos, do outro lado do cabo.
				angle = [0.35, 0.6, 0.5][segment - 1]
				rotation = Quaternion(hinge, angle)
				if segment == 1:
					rotation = Quaternion(hinge.cross(rest_fingers).normalized(), -0.75) * rotation
			skeleton.set_bone_pose_rotation(bone, rotation)

## Golpe lateral com as duas mãos: 0–35% arma para trás do ombro direito,
## 35–60% varre rápido da direita para a esquerda na altura do peito,
## 60–100% termina o movimento do outro lado e relaxa.
func _apply_swing(chest: int, spine: int, right_arm: int) -> void:
	var t := clampf(_work_time / SWING_CYCLE, 0.0, 1.0)
	var wind := 1.35 # ângulo da arma para o lado direito (radianos, a partir da frente)
	var follow := -1.25
	var a := 0.0
	var lift := 0.0
	if t < 0.35:
		var k := _ease_in_out(t / 0.35)
		a = lerpf(0.3, wind, k)
		lift = 0.45 * k
	elif t < 0.6:
		var k := (t - 0.35) / 0.25
		a = lerpf(wind, follow, k * k * (3.0 - 2.0 * k))
		lift = lerpf(0.45, 0.05, k)
	else:
		var k := (t - 0.6) / 0.4
		a = lerpf(follow, follow * 0.7, k)
		lift = lerpf(0.05, -0.25, k)
	var up := Vector3.UP
	var forward := Vector3(0, 0, 1)
	var right := Vector3(signf(skeleton.get_bone_global_pose(right_arm).origin.x), 0, 0)
	# O tronco gira junto com o golpe (dá peso ao movimento).
	if spine >= 0:
		Grip._set_global_rotation(skeleton, spine, Basis(up, a * 0.35 * signf(right.x)) * skeleton.get_bone_global_pose(spine).basis)
	var torso := skeleton.get_bone_global_pose(chest).origin
	var pivot := torso + forward * 0.16 + up * 0.02
	var h := (forward * cos(a) + right * sin(a) + up * lift).normalized()
	var right_hand := pivot + h * 0.40
	var left_hand := pivot + h * 0.27
	for spec in [["Right", right_hand, right], ["Left", left_hand, -right]]:
		var pole: Vector3 = (spec[2] as Vector3) * 0.6 - forward * 0.3 - up * 0.5
		if work_tool == "long_bat":
			_grip_on_staff(spec[0], spec[1], h, up, pole)
			continue
		var side: String = spec[0]
		var hand := Grip._bone(skeleton, side + "Hand")
		_two_bone_ik(Grip._bone(skeleton, side + "Arm"), Grip._bone(skeleton, side + "ForeArm"), hand, spec[1], pole)
		if hand >= 0:
			skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_rest(hand).basis.get_rotation_quaternion())
	if _tool_node != null:
		var y := h
		var z := y.cross(up).normalized()
		if z.length_squared() < 0.01:
			z = forward
		var x := y.cross(z).normalized()
		_tool_node.transform = Transform3D(Basis(x, y, z), left_hand - h * 0.12)

# -------------------------------------------------------------- mochila ---
## Mochila nas costas (Sobrevivência): "" tira. Tamanho e cor pelo tipo.
const BACKPACK_LOOK := {
	"school_bag": [Vector3(0.30, 0.38, 0.14), Color("#2f5d8a")],
	"sack_bag": [Vector3(0.32, 0.34, 0.16), Color("#8a7a5a")],
	"backpack": [Vector3(0.36, 0.50, 0.20), Color("#4b5a32")],
}
var backpack_id := ""
var _backpack: Node3D

func set_backpack(item_id: String) -> void:
	if item_id == backpack_id or skeleton == null:
		return
	backpack_id = item_id
	if _backpack != null:
		_backpack.queue_free()
		_backpack = null
	if not BACKPACK_LOOK.has(item_id):
		return
	var look: Array = BACKPACK_LOOK[item_id]
	_backpack = BackpackModel.build(item_id, look[0], look[1])
	skeleton.add_child(_backpack)
	_update_backpack()

func _update_backpack() -> void:
	if _backpack == null:
		return
	var hips := Grip._bone(skeleton, "Hips")
	var left := Grip._bone(skeleton, "LeftArm")
	var right := Grip._bone(skeleton, "RightArm")
	if hips < 0 or left < 0 or right < 0:
		return
	# Plano das costas pelos ombros e quadril: a mochila fica chapada nas costas
	# mesmo com o peito torcido da pose de fuzil ou inclinado ao agachar.
	var l := skeleton.get_bone_global_pose(left).origin
	var r := skeleton.get_bone_global_pose(right).origin
	var shoulders := (l + r) * 0.5
	var up := (shoulders - skeleton.get_bone_global_pose(hips).origin).normalized()
	var side := (l - r)
	side = (side - up * side.dot(up)).normalized()
	var back := side.cross(up).normalized()
	if back.dot(Vector3(0, 0, -1)) < 0.0:
		back = -back # costas = -Z no espaço do esqueleto (o modelo olha para +Z)
	side = up.cross(back).normalized()
	var basis := Basis(-side, up, -back) # base direita (x × y = z)
	_backpack.transform = Transform3D(basis, shoulders - up * 0.24 + back * 0.10)

# ------------------------------------------------------------- agachar ---
# Os clipes do Ch31 são todos em pé. Agachar é feito por cima: o quadril desce,
# as pernas dobram com IK (pés onde o clipe os pôs, joelhos para a frente) e o
# tronco inclina um pouco. As hitboxes seguem os ossos, então o alvo fica menor.
const CROUCH_DROP := 0.36 # fração do comprimento da perna
const CROUCH_LEAN := 0.32 # radianos de inclinação do tronco
var crouch_weight := 0.0
var unarmed_weight := 0.0
var _move_amount := 0.0

func _apply_crouch() -> void:
	if work_action.is_empty():
		_work_dip = 0.0
	var w := maxf(crouch_weight, _work_dip)
	if w <= 0.001:
		return
	var hips := Grip._bone(skeleton, "Hips")
	var spine := Grip._bone(skeleton, "Spine")
	if hips < 0:
		return
	var feet := {}
	for side in ["Left", "Right"]:
		var foot := Grip._bone(skeleton, side + "Foot")
		if foot >= 0:
			feet[side] = skeleton.get_bone_global_pose(foot)
	var leg_length := 0.0
	var up_leg := Grip._bone(skeleton, "LeftUpLeg")
	var leg := Grip._bone(skeleton, "LeftLeg")
	var foot_bone := Grip._bone(skeleton, "LeftFoot")
	if up_leg >= 0 and leg >= 0 and foot_bone >= 0:
		leg_length = skeleton.get_bone_rest(leg).origin.length() + skeleton.get_bone_rest(foot_bone).origin.length()
	# Desce o quadril no espaço do esqueleto (Y para cima), convertido para o espaço do pai.
	var drop := Vector3(0, -leg_length * CROUCH_DROP * w, 0)
	var parent := skeleton.get_bone_parent(hips)
	if parent >= 0:
		drop = skeleton.get_bone_global_pose(parent).basis.inverse() * drop
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + drop)
	if spine >= 0:
		var spine_global := skeleton.get_bone_global_pose(spine).basis
		# Frente do modelo é +Z no espaço do esqueleto: girar em X leva o topo para a frente.
		Grip._set_global_rotation(skeleton, spine, Basis(Vector3.RIGHT, CROUCH_LEAN * crouch_weight) * spine_global)
	for side in feet:
		_leg_ik(side, (feet[side] as Transform3D).origin, Vector3(0, 0, 1))
		Grip._set_global_rotation(skeleton, Grip._bone(skeleton, side + "Foot"), (feet[side] as Transform3D).basis)

# ------------------------------------------------------------- degraus ---
# Pés no degrau. O corpo segue a rampa invisível que passa pelo meio dos
# degraus; cada pé procura o chão embaixo dele por raio, primeiro nos degraus
# (camada LAYER_FOOT_PROBE, parkour_district._stairs) e depois no mundo. O
# quadril desce o necessário para o pé mais baixo alcançar o degrau dele e o
# outro pé sobe por IK. No ar os pés voltam ao clipe.
const FOOT_PROBE := 0.6 # alcance do raio acima/abaixo da origem do personagem (m)
const FOOT_STEP_LAYER := 8 # hitbox.gd LAYER_FOOT_PROBE
var foot_ik_enabled := true
var _foot_offsets := {"Left": 0.0, "Right": 0.0}
var _airborne := false

const FOOT_SWING_HEIGHT := 0.17 # tornozelo acima disto (m, sobre a origem) = pé no ar

## Altura do chão embaixo de `point` em relação à origem: degraus primeiro, depois o mundo.
func _ground_offset(space: PhysicsDirectSpaceState3D, point: Vector3, base_y: float) -> float:
	var from := Vector3(point.x, base_y + FOOT_PROBE, point.z)
	var to := Vector3(point.x, base_y - FOOT_PROBE, point.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, FOOT_STEP_LAYER))
	if hit.is_empty():
		hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	if hit.is_empty():
		return 0.0
	return clampf((hit["position"] as Vector3).y - base_y, -FOOT_PROBE, FOOT_PROBE)

func set_foot_ik(value: bool) -> void:
	foot_ik_enabled = value
	if not value:
		_foot_offsets = {"Left": 0.0, "Right": 0.0}

func _apply_foot_ik() -> void:
	if not foot_ik_enabled or prone_weight > 0.01 or not is_inside_tree():
		return
	if _airborne:
		_foot_offsets = {"Left": 0.0, "Right": 0.0}
		return
	var hips := Grip._bone(skeleton, "Hips")
	if hips < 0:
		return
	var space := get_world_3d().direct_space_state
	var to_world := skeleton.global_transform
	var to_local := to_world.affine_inverse().basis
	var base_y := global_position.y
	var feet := {}
	var lowest := 0.0
	for side in ["Left", "Right"]:
		var foot := Grip._bone(skeleton, side + "Foot")
		if foot < 0:
			return
		var pose := skeleton.get_bone_global_pose(foot)
		var world := to_world * pose.origin
		var target := _ground_offset(space, world, base_y)
		# Pé no ar (o clipe levantou o tornozelo): olha também embaixo da ponta
		# do pé e sobe rápido, para não atravessar a quina do próximo degrau.
		# Pé apoiado: só o tornozelo, suave.
		var rate := 18.0
		if world.y - base_y > FOOT_SWING_HEIGHT:
			var toe := Grip._bone(skeleton, side + "ToeBase")
			if toe >= 0:
				target = maxf(target, _ground_offset(space, to_world * skeleton.get_bone_global_pose(toe).origin, base_y))
			if target > float(_foot_offsets[side]):
				rate = 45.0
		_foot_offsets[side] = lerpf(float(_foot_offsets[side]), target, minf(1.0, _last_delta * rate))
		feet[side] = [foot, pose]
		lowest = minf(lowest, float(_foot_offsets[side]))
	var drop := to_local * Vector3(0, lowest, 0)
	var parent := skeleton.get_bone_parent(hips)
	if parent >= 0:
		drop = skeleton.get_bone_global_pose(parent).basis.inverse() * drop
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + drop)
	for side in feet:
		var foot: int = feet[side][0]
		var pose: Transform3D = feet[side][1]
		_leg_ik(side, pose.origin + to_local * Vector3(0, float(_foot_offsets[side]), 0), Vector3(0, 0, 1))
		Grip._set_global_rotation(skeleton, foot, pose.basis)

## IK de duas juntas (coxa e canela) até `target`, com o joelho apontando para `pole`.
func _leg_ik(side: String, target: Vector3, pole: Vector3) -> void:
	_two_bone_ik(Grip._bone(skeleton, side + "UpLeg"), Grip._bone(skeleton, side + "Leg"), Grip._bone(skeleton, side + "Foot"), target, pole)

func _two_bone_ik(upper: int, lower: int, foot: int, target: Vector3, pole: Vector3) -> void:
	if upper < 0 or lower < 0 or foot < 0:
		return
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var upper_length := skeleton.get_bone_rest(lower).origin.length()
	var lower_length := skeleton.get_bone_rest(foot).origin.length()
	var offset := target - upper_pose.origin
	var distance := clampf(offset.length(), 0.001, upper_length + lower_length - 0.0001)
	var direction := offset.normalized()
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.00001:
		return
	bend = bend.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var outward := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var knee := upper_pose.origin + direction * along + bend * outward
	var upper_dir := (upper_pose.basis * skeleton.get_bone_rest(lower).origin).normalized()
	Grip._set_global_rotation(skeleton, upper, Basis(Quaternion(upper_dir, (knee - upper_pose.origin).normalized())) * upper_pose.basis)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var lower_dir := (lower_pose.basis * skeleton.get_bone_rest(foot).origin).normalized()
	var reach := upper_pose.origin + direction * distance
	Grip._set_global_rotation(skeleton, lower, Basis(Quaternion(lower_dir, (reach - lower_pose.origin).normalized())) * lower_pose.basis)

# ---------------------------------------------------- pose parada em pé ---
# Parado e desarmado, todos os personagens ficam na mesma pose: em pé e
# ereto (coluna e cabeça na vertical), pernas quase esticadas com os pés
# embaixo do quadril e braços retos caindo ao lado do corpo. Corrige o clipe
# de respiração (cotovelos dobrados, mãos à frente) e o retarget do Manequim
# (tronco curvado, joelhos dobrados); a respiração do clipe continua por baixo.
# Entra e sai suave ao começar/parar de andar.
const STAND_ARM_REACH := 0.97 # fração do braço esticado (cotovelo quase reto)
const STAND_LEG_REACH := 0.985 # fração da perna esticada (joelho quase reto)
const STAND_ARM_OUT := 0.05 # m para fora do ombro: a mão passa ao lado da coxa
const STAND_ARM_FORWARD := 0.02 # m à frente do ombro
const STAND_FOOT_OUT := 0.03 # m para fora do quadril (base um pouco aberta)
const STAND_BLEND_RATE := 4.0
var stand_weight := 0.0
var stand_pose_enabled := true

func _apply_stand_pose() -> void:
	var calm := stand_pose_enabled and current_clip in ["idle_unarmed", "idle_with_rifle"] and not _airborne and crouch_weight < 0.01 and prone_weight < 0.01 and work_action.is_empty()
	stand_weight = move_toward(stand_weight, 1.0 if calm else 0.0, _last_delta * STAND_BLEND_RATE)
	var w := _smooth(stand_weight)
	if w <= 0.001:
		return
	# Armado ou não: em pé e ereto. Os braços só caem ao lado do corpo sem
	# arma; com arma as mãos seguem o cabo (_update_weapon_mount, depois).
	_stand_legs(w)
	_stand_upright(w)
	if unarmed_weight > 0.001:
		_stand_arms(w * unarmed_weight)

## Pés embaixo do quadril e o quadril sobe até as pernas ficarem quase retas.
func _stand_legs(w: float) -> void:
	var hips := Grip._bone(skeleton, "Hips")
	var hips_origin := skeleton.get_bone_global_pose(hips).origin
	var plans := []
	var lift := INF
	for side in ["Left", "Right"]:
		var up_leg := Grip._bone(skeleton, side + "UpLeg")
		var leg := Grip._bone(skeleton, side + "Leg")
		var foot := Grip._bone(skeleton, side + "Foot")
		var hip := skeleton.get_bone_global_pose(up_leg).origin
		var foot_pose := skeleton.get_bone_global_pose(foot)
		var outward := hip - hips_origin
		outward.y = 0.0
		outward = outward.normalized() if outward.length_squared() > 0.000001 else Vector3.ZERO
		var under := Vector3(hip.x, foot_pose.origin.y, hip.z) + outward * STAND_FOOT_OUT
		var target := foot_pose.origin.lerp(under, w)
		var length := (skeleton.get_bone_rest(leg).origin.length() + skeleton.get_bone_rest(foot).origin.length()) * STAND_LEG_REACH
		var across := Vector2(target.x - hip.x, target.z - hip.z).length()
		var height := sqrt(maxf(length * length - across * across, 0.0))
		lift = minf(lift, target.y + height - hip.y)
		plans.append([side, target, foot_pose.basis])
	if lift != INF:
		var raise := Vector3(0, lift * w, 0)
		var parent := skeleton.get_bone_parent(hips)
		if parent >= 0:
			raise = skeleton.get_bone_global_pose(parent).basis.inverse() * raise
		skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + raise)
	for plan in plans:
		_leg_ik(plan[0], plan[1], Vector3(0, 0, 1))
		Grip._set_global_rotation(skeleton, Grip._bone(skeleton, plan[0] + "Foot"), plan[2])

## Tronco, pescoço e cabeça na vertical (tira a curvatura para a frente/lado).
func _stand_upright(w: float) -> void:
	# Só a coluna endireita; a cabeça mantém a orientação do clipe (olhando para
	# a frente). Endireitar o pescoço jogaria a cabeça para trás (o pescoço
	# humano é naturalmente inclinado para a frente).
	var head := Grip._bone(skeleton, "Head")
	var head_basis := skeleton.get_bone_global_pose(head).basis if head >= 0 else Basis.IDENTITY
	for link in [["Spine", "Neck", 1.0]]:
		var bone := Grip._bone(skeleton, link[0])
		var tip := Grip._bone(skeleton, link[1])
		if bone < 0 or tip < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var along := skeleton.get_bone_global_pose(tip).origin - pose.origin
		if along.length_squared() < 0.000001:
			continue
		along = along.normalized()
		var wanted := along.lerp(Vector3.UP, w * float(link[2])).normalized()
		if along.dot(wanted) > 0.99999:
			continue
		Grip._set_global_rotation(skeleton, bone, Basis(Quaternion(along, wanted)) * pose.basis)
	if head >= 0:
		Grip._set_global_rotation(skeleton, head, head_basis)

## Braços retos, caindo do ombro ao lado do corpo; cotovelo para trás e punho reto.
func _stand_arms(w: float) -> void:
	var chest := Grip._bone(skeleton, "Spine2")
	var torso := skeleton.get_bone_global_pose(chest).origin
	for side in ["Left", "Right"]:
		var upper := Grip._bone(skeleton, side + "Arm")
		var fore := Grip._bone(skeleton, side + "ForeArm")
		var hand := Grip._bone(skeleton, side + "Hand")
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var lateral := shoulder - torso
		lateral.y = 0.0
		if lateral.length_squared() < 0.0001:
			continue
		lateral = lateral.normalized()
		var length := skeleton.get_bone_rest(fore).origin.length() + skeleton.get_bone_rest(hand).origin.length()
		var target := shoulder + Vector3.DOWN * length * STAND_ARM_REACH + lateral * STAND_ARM_OUT + Vector3(0, 0, STAND_ARM_FORWARD)
		var current := skeleton.get_bone_global_pose(hand).origin
		_two_bone_ik(upper, fore, hand, current.lerp(target, w), lateral * 0.3 + Vector3(0, 0, -1))
		var rest := skeleton.get_bone_rest(hand).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_pose_rotation(hand).slerp(rest, w))

# ------------------------------------------------------ braços desarmado ---
## Sem arma: mãos ao lado do quadril, balançando ao andar (os clipes seguram um fuzil).
var _run_arms := 0.0

func _relax_arms(weight: float) -> void:
	var hips := Grip._bone(skeleton, "Hips")
	var chest := Grip._bone(skeleton, "Spine2")
	if hips < 0 or chest < 0:
		return
	var torso := skeleton.get_bone_global_pose(chest).origin
	var hip := skeleton.get_bone_global_pose(hips).origin
	var length := maxf(animation_player.current_animation_length, 0.01)
	var phase := animation_player.current_animation_position / length * TAU
	for side in ["Left", "Right"]:
		var upper := Grip._bone(skeleton, side + "Arm")
		var hand := Grip._bone(skeleton, side + "Hand")
		if upper < 0 or hand < 0:
			continue
		var shoulder := skeleton.get_bone_global_pose(upper).origin
		var lateral := shoulder - torso
		lateral.y = 0.0
		if lateral.length_squared() < 0.0001:
			continue
		lateral = lateral.normalized()
		var swing := sin(phase + (0.0 if side == "Left" else PI)) * 0.2 * _move_amount
		# Mão à frente sobe um pouco (cotovelo dobra), atrás fica mais baixa.
		var relaxed := Vector3(hip.x, hip.y + 0.03 + maxf(swing, 0.0) * 0.35, hip.z) + lateral * 0.24 + Vector3(0, 0, 0.03 + swing)
		var current := skeleton.get_bone_global_pose(hand).origin
		var target := current.lerp(relaxed, weight)
		# Cotovelo para trás e um pouco para fora; punho reto (pose de descanso da mão).
		_two_bone_ik(upper, Grip._bone(skeleton, side + "ForeArm"), hand, target, lateral * 0.4 + Vector3(0, 0, -1))
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_rest(hand).basis.get_rotation_quaternion())

func play_action(action: String) -> bool:
	if not ready_ok:
		return false
	if action in ["punch", "elbow_punch"]:
		stop_overlay()
		current_clip = action
		animation_player.play(action, 0.12)
		animation_player.speed_scale = 1.0
		return true
	if ACTIONS.has(action):
		var spec: Array = ACTIONS[action]
		return play_overlay(spec[0], spec[1], float(spec[2]), float(spec[3]), float(spec[4]))
	if action.begins_with("ual:"):
		return play_overlay(action.substr(4), "full")
	return false

## Same as play_action, but held for `seconds` (repeating short clips).
func play_action_for(action: String, seconds: float) -> bool:
	if not ready_ok or not ACTIONS.has(action):
		return false
	var spec: Array = ACTIONS[action]
	return play_overlay(spec[0], spec[1], float(spec[2]), float(spec[3]), seconds)

# ------------------------------------------------- camada de ações (UAL2) ---
# Clipes da Universal Animation Library 2 (Quaternius, CC0), retargetizados para
# o rig do Ch31 por tools/characters/build_ual2_clips.gd. Tocam POR CIMA da
# locomoção: cada osso da máscara é amostrado do clipe e misturado com o peso
# da ação (entra e sai suave), então as pernas continuam andando numa ação de
# tronco e o IK/mira por baixo não "estala" quando a ação acaba.
const UAL_DIR := "res://assets/personagens/ual2/clips/"
const UAL_CLIPS := ["chest_open", "climbup_1m", "consume", "farm_harvest", "farm_plantseed", "farm_watering", "hit_knockback", "idle_foldarms", "idle_lantern", "idle_no", "idle_rail", "idle_rail_call", "idle_shield", "idle_shield_break", "idle_talkingphone", "laytoidle", "melee_hook", "melee_hook_rec", "ninjajump_idle", "ninjajump_land", "ninjajump_start", "overhandthrow", "shield_dash", "shield_oneshot", "slide", "slide_exit", "slide_start", "sword_block", "sword_dash", "sword_heavy_combo", "sword_regular_a", "sword_regular_a_rec", "sword_regular_b", "sword_regular_b_rec", "sword_regular_c", "sword_regular_combo", "treechopping", "walk_carry", "yes", "zombie_idle", "zombie_scratch", "zombie_walk_fwd"]
## Gatilhos do jogo -> [clipe, máscara, velocidade, peso máximo, segundos (-1 = clipe todo)].
const ACTIONS := {
	"throw": ["overhandthrow", "upper", 1.25, 1.0, -1.0], # granada
	"consume": ["consume", "arms", 1.0, 1.0, -1.0], # comer, beber, remédio
	"open": ["chest_open", "full", 1.2, 1.0, -1.0], # revistar recipiente / caixa
	"harvest": ["farm_harvest", "full", 1.3, 1.0, -1.0], # colher fruta do arbusto
	"plant": ["farm_plantseed", "full", 1.0, 1.0, -1.0],
	"hit": ["hit_knockback", "upper", 1.0, 0.6, 0.3], # recuo de um golpe forte (sem a queda)
	"get_up": ["laytoidle", "full", 1.3, 1.0, -1.0], # levantar do chão
	"climb": ["climbup_1m", "full", 1.0, 1.0, -1.0],
	"hook": ["melee_hook", "upper", 1.0, 1.0, -1.0],
	"yes": ["yes", "upper", 1.0, 1.0, 2.5],
	"no": ["idle_no", "upper", 1.0, 1.0, 2.5],
	"wave": ["idle_rail_call", "upper", 1.0, 1.0, 2.5],
	"scratch": ["zombie_scratch", "upper", 1.0, 1.0, -1.0],
}
## Parado e desarmado por um tempo: uma destas, uma vez (cancela ao mexer).
const IDLE_FIDGETS := ["idle_foldarms", "idle_talkingphone", "idle_rail", "idle_no"]
const IDLE_FIDGET_DELAY := 9.0
const OVERLAY_FADE_IN := 0.16
const OVERLAY_FADE_OUT := 0.22
static var _ual_cache := {} # modelo -> {clip: [Animation, [[track, bone, type], ...]]}
var ual_clips := {}
var _overlay_name := ""
var _overlay_mask := ""
var _overlay_time := 0.0
var _overlay_speed := 1.0
var _overlay_max := 1.0
var _overlay_weight := 0.0
var _overlay_until := -1.0 # seconds of a looping clip to play (-1 = one cycle)
var _overlay_stopping := false
var _overlay_fidget := false
var overlay_hold_hips := false # a ação não mexe na altura do quadril (escalada)
var _idle_time := 0.0
var _fidget_index := 0
var _masks := {}

func has_action(action: String) -> bool:
	return ACTIONS.has(action) and ual_clips.has(ACTIONS[action][0])

func is_overlay_playing() -> bool:
	return not _overlay_name.is_empty()

func play_overlay(clip_name: String, mask: String = "full", speed: float = 1.0, max_weight: float = 1.0, seconds: float = -1.0) -> bool:
	if not ready_ok or not ual_clips.has(clip_name):
		return false
	if current_clip in ["punch", "elbow_punch"]:
		current_clip = ""
	# Restarting the same one-shot (two hits in a row) keeps the weight: no pop.
	if clip_name != _overlay_name:
		_overlay_weight = 0.0 if _overlay_name.is_empty() else _overlay_weight * 0.5
	_overlay_name = clip_name
	_overlay_mask = mask
	_overlay_time = 0.0
	_overlay_speed = speed
	_overlay_max = max_weight
	_overlay_until = seconds
	_overlay_stopping = false
	_overlay_fidget = false
	overlay_hold_hips = false
	return true

## Escalada: o clipe inteiro em `seconds`, sem a subida do quadril (quem sobe
## é a cápsula do jogador; o clipe só mexe braços, pernas e tronco).
func play_climb(clip_name: String, seconds: float) -> bool:
	if not ual_clips.has(clip_name):
		return false
	var clip: Animation = ual_clips[clip_name][0]
	if not play_overlay(clip_name, "full", clip.length / maxf(seconds, 0.05)):
		return false
	overlay_hold_hips = true
	return true

## Fade the current action out (it keeps playing while it fades).
func stop_overlay() -> void:
	if not _overlay_name.is_empty():
		_overlay_stopping = true

func _load_ual_clips(skeleton_path: String, hip_scale: float, retarget: bool, hip_anchor: Vector3) -> void:
	var key := "%s|%s|%.3f" % [model_path, skeleton_path, hip_scale]
	if not _ual_cache.has(key):
		var built := {}
		for clip_name in UAL_CLIPS:
			var source := load(UAL_DIR + clip_name + ".tres") as Animation
			if source == null:
				continue
			var clip := source.duplicate() as Animation
			if retarget:
				_retarget_clip(clip, skeleton_path, hip_scale)
			_make_in_place(clip, hip_anchor)
			var tracks := []
			for t in clip.get_track_count():
				var bone := skeleton.find_bone(String(clip.track_get_path(t)).get_slice(":", 1))
				var type := clip.track_get_type(t)
				if bone >= 0 and (type == Animation.TYPE_ROTATION_3D or type == Animation.TYPE_POSITION_3D):
					tracks.append([t, bone, type])
			built[clip_name] = [clip, tracks]
		_ual_cache[key] = built
	ual_clips = _ual_cache[key]

## Per-bone weight of a mask: "full" everything; "upper" from the spine up
## (lower spine blends so the hips keep walking); "arms" shoulders down to the
## fingers with a little chest and head.
func _mask_weights(mask: String) -> PackedFloat32Array:
	if _masks.has(mask):
		return _masks[mask]
	var weights := PackedFloat32Array()
	weights.resize(skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():
		var suffix := String(skeleton.get_bone_name(bone)).trim_prefix(bone_prefix)
		var limb := suffix.contains("Shoulder") or suffix.contains("Arm") or suffix.contains("Hand")
		var w := 0.0
		match mask:
			"full":
				w = 1.0
			"upper":
				if limb or suffix in ["Spine2", "Neck", "Head", "HeadTop_End"]:
					w = 1.0
				elif suffix == "Spine1":
					w = 0.7
				elif suffix == "Spine":
					w = 0.4
			"arms":
				if limb:
					w = 1.0
				elif suffix in ["Neck", "Head"]:
					w = 0.5
				elif suffix == "Spine2":
					w = 0.35
		weights[bone] = w
	_masks[mask] = weights
	return weights

func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Advances the action clock and its blend weight; ends finished actions.
func _advance_overlay() -> void:
	if _overlay_name.is_empty():
		return
	var clip: Animation = ual_clips[_overlay_name][0]
	_overlay_time += _last_delta * _overlay_speed
	# One cycle, or only `_overlay_until` seconds of it (a loop, or the first
	# part of a one-shot, e.g. the recoil of a knockback without the fall).
	var looping := clip.loop_mode != Animation.LOOP_NONE
	var span := _overlay_until if _overlay_until >= 0.0 else (INF if looping else clip.length)
	var remaining := (span - _overlay_time) / maxf(_overlay_speed, 0.01)
	if remaining <= OVERLAY_FADE_OUT:
		_overlay_stopping = true
	var target := 0.0 if _overlay_stopping else _overlay_max
	var rate := (1.0 / OVERLAY_FADE_OUT) if _overlay_stopping else (1.0 / OVERLAY_FADE_IN)
	_overlay_weight = move_toward(_overlay_weight, target, _last_delta * rate * maxf(_overlay_max, 0.01))
	if _overlay_stopping and _overlay_weight <= 0.001:
		_overlay_name = ""
		_overlay_weight = 0.0
		_overlay_fidget = false

## Weight the arms currently get from the action (0 when none touches them).
func _overlay_arm_weight() -> float:
	if _overlay_name.is_empty():
		return 0.0
	return _smooth(_overlay_weight / maxf(_overlay_max, 0.01)) * _overlay_max

func _apply_overlay() -> void:
	if _overlay_name.is_empty() or _overlay_weight <= 0.001:
		return
	var entry: Array = ual_clips[_overlay_name]
	var clip: Animation = entry[0]
	# A one-shot asked to last longer than itself repeats (eating for 3 s).
	var repeat := clip.loop_mode != Animation.LOOP_NONE or _overlay_until > clip.length
	var t := fmod(_overlay_time, clip.length) if repeat else minf(_overlay_time, clip.length)
	var mask := _mask_weights(_overlay_mask)
	var weight := _smooth(_overlay_weight / maxf(_overlay_max, 0.01)) * _overlay_max
	for track_info in entry[1]:
		var bone: int = track_info[1]
		var w := mask[bone] * weight
		if w <= 0.001:
			continue
		if track_info[2] == Animation.TYPE_ROTATION_3D:
			var q := clip.rotation_track_interpolate(track_info[0], t)
			skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(q, w))
		elif not overlay_hold_hips:
			var p := clip.position_track_interpolate(track_info[0], t)
			skeleton.set_bone_pose_position(bone, skeleton.get_bone_pose_position(bone).lerp(p, w))

## Idle fidgets: standing still, unarmed and free for a while plays one idle
## variation (arms folded, phone call, leaning, head shake), cancelled by any input.
func _update_idle_fidget(moving: bool) -> void:
	var calm := not moving and not armed and not _airborne and crouch_weight < 0.01 and prone_weight < 0.01 and work_action.is_empty() and not aim_active and current_clip == "idle_unarmed"
	if not calm:
		_idle_time = 0.0
		if _overlay_fidget:
			stop_overlay()
		return
	if not _overlay_name.is_empty():
		return
	_idle_time += _last_delta
	if _idle_time < IDLE_FIDGET_DELAY:
		return
	_idle_time = 0.0
	var clip_name: String = IDLE_FIDGETS[_fidget_index % IDLE_FIDGETS.size()]
	_fidget_index += 1
	if play_overlay(clip_name, "full", 1.0, 1.0, 5.0):
		_overlay_fidget = true

func _play_clip(clip: String, rate: float) -> void:
	if current_clip != clip:
		current_clip = clip
		animation_player.play(clip, 0.18)
	animation_player.speed_scale = rate

func _update_weapon_mount() -> void:
	if skeleton == null or weapon_mount == null:
		return
	var chest_bone := Grip._bone(skeleton, "Spine2")
	if chest_bone < 0:
		return
	var chest := skeleton.get_bone_global_pose(chest_bone)
	if weapon_id == "pistol" and not locomotion_active:
		# Stopped pistol carry stays level with the character, independent of the
		# rifle-idle chest twist; the right hand is posed forward by the grip solver.
		weapon_mount.transform = Transform3D(Basis(Vector3.UP, PI), chest.origin + Vector3(0.0, -0.08, -0.08))
	else:
		weapon_mount.transform = chest * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, -0.08, -0.08))
	if not armed or not is_instance_valid(bound_weapon):
		return
	if aim_weight > 0.001 and current_clip not in ["punch", "elbow_punch"]:
		_aim_mount()
	for side in ["Right", "Left"]:
		var source := bound_weapon.get_node_or_null(side + "Grip") as Marker3D
		if source:
			weapon_mount.get_node(side + "Grip").position = weapon_mount.to_local(source.global_position)
	var is_pistol := weapon_id == "pistol"
	# The chest is only a stable orientation reference. Anchor the weapon itself
	# to the animated trigger hand so it cannot sit at the torso origin; the
	# support hand is solved against rifles after this primary contact is set.
	var right_hand := Grip._bone(skeleton, "RightHand")
	var muzzle := bound_weapon.get_node_or_null("Muzzle") as Marker3D
	var trigger_grip := bound_weapon.get_node_or_null("RightGrip") as Marker3D
	var barrel_direction := Vector3.ZERO
	if muzzle != null and trigger_grip != null:
		barrel_direction = muzzle.global_position - trigger_grip.global_position
	if right_hand >= 0:
		var wrist_target: Vector3
		if is_pistol and barrel_direction.length_squared() > 0.000001:
			var shoulder_world := skeleton.to_global(skeleton.get_bone_global_pose(Grip._bone(skeleton, "RightArm")).origin)
			var chest_world := skeleton.to_global(chest.origin)
			var up_world := skeleton.global_basis.y.normalized()
			var lateral_world := shoulder_world - chest_world
			lateral_world -= up_world * lateral_world.dot(up_world)
			if lateral_world.length_squared() > 0.000001:
				lateral_world = lateral_world.normalized()
				var pistol_wrist_world := shoulder_world + lateral_world * 0.06 - up_world * 0.23 + barrel_direction.normalized() * 0.13
				wrist_target = skeleton.to_local(pistol_wrist_world)
			else:
				wrist_target = skeleton.get_bone_global_pose(right_hand).origin
		else:
			wrist_target = skeleton.get_bone_global_pose(right_hand).origin
		weapon_mount.position += wrist_target - Grip.wrist_target(skeleton, weapon_mount, "Right")
	# Keep the muzzle clear of the torso and hand bones, accounting for avatar scale.
	if barrel_direction.length_squared() > 0.000001:
		weapon_mount.global_position += barrel_direction.normalized() * (0.06 if is_pistol else 0.035)
	var grip_sides: Array[String] = ["Right"]
	if not is_pistol:
		grip_sides.append("Left")
	for iteration in range(8):
		var moved := false
		for side in grip_sides:
			var upper: int = Grip._bone(skeleton, side + "Arm")
			var lower: int = Grip._bone(skeleton, side + "ForeArm")
			var hand: int = Grip._bone(skeleton, side + "Hand")
			var origin: Vector3 = skeleton.get_bone_global_pose(upper).origin
			var target: Vector3 = Grip.wrist_target(skeleton, weapon_mount, side)
			var reach: float = skeleton.get_bone_rest(lower).origin.length() + skeleton.get_bone_rest(hand).origin.length() - 0.002
			if origin.distance_to(target) > reach:
				weapon_mount.position -= (target - origin).normalized() * (origin.distance_to(target) - reach)
				moved = true
		if not moved:
			break
	# The hand anchoring above only translates; re-aim from the final grip spot.
	if aim_weight > 0.001 and current_clip not in ["punch", "elbow_punch"]:
		_aim_mount()
	for side in grip_sides:
		Grip.solve(skeleton, weapon_mount, side, true)
	if is_pistol:
		_relax_left_arm()
	else:
		_clear_stock_from_arm()

# Arma longa: o cotovelo direito vem do clipe e, em alguns corpos/armas, o
# antebraço caía em cima da linha da coronha (a coronha atravessava o braço).
# Testa o cotovelo cada vez mais para fora (e um pouco para baixo) até braço e
# antebraço ficarem a STOCK_CLEARANCE da coronha; a mão continua no cabo.
const STOCK_CLEARANCE := 0.085 # m: meia espessura da coronha + do antebraço
const STOCK_POLE_STEPS := [0.0, 0.25, 0.5, 0.8, 1.2, 1.8, 2.6]

func _clear_stock_from_arm() -> void:
	var muzzle := bound_weapon.get_node_or_null("Muzzle") as Marker3D
	var grip := bound_weapon.get_node_or_null("RightGrip") as Marker3D
	if muzzle == null or grip == null:
		return
	var back := grip.global_position - muzzle.global_position
	if back.length_squared() < 0.0001:
		return
	back = back.normalized()
	# Linha do cano/coronha (o cabo fica abaixo dela) até o fim da coronha.
	var length := float((bound_weapon.get_meta("dimensions_m", Vector3(0, 0, 0.8)) as Vector3).z)
	var stock_start := muzzle.global_position + back * back.dot(grip.global_position - muzzle.global_position)
	var stock_end := muzzle.global_position + back * length
	var upper := Grip._bone(skeleton, "RightArm")
	var fore := Grip._bone(skeleton, "RightForeArm")
	var hand := Grip._bone(skeleton, "RightHand")
	var chest := Grip._bone(skeleton, "Spine2")
	if _arm_clearance(upper, fore, hand, stock_start, stock_end) >= STOCK_CLEARANCE:
		return
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow_now := skeleton.get_bone_global_pose(fore).origin - shoulder
	var lateral := shoulder - skeleton.get_bone_global_pose(chest).origin
	lateral.y = 0.0
	if lateral.length_squared() < 0.000001:
		return
	lateral = lateral.normalized() * elbow_now.length()
	var best_pole := elbow_now
	var best := -INF
	for step in STOCK_POLE_STEPS:
		var pole: Vector3 = elbow_now + (lateral + Vector3.DOWN * elbow_now.length() * 0.3) * float(step)
		Grip.solve(skeleton, weapon_mount, "Right", true, pole)
		var clearance := _arm_clearance(upper, fore, hand, stock_start, stock_end)
		if clearance > best:
			best = clearance
			best_pole = pole
		if clearance >= STOCK_CLEARANCE:
			return
	Grip.solve(skeleton, weapon_mount, "Right", true, best_pole)

## Menor distância (m, mundo) entre a coronha e o braço/antebraço direitos.
func _arm_clearance(upper: int, fore: int, hand: int, a: Vector3, b: Vector3) -> float:
	var shoulder := skeleton.to_global(skeleton.get_bone_global_pose(upper).origin)
	var elbow := skeleton.to_global(skeleton.get_bone_global_pose(fore).origin)
	var wrist := skeleton.to_global(skeleton.get_bone_global_pose(hand).origin)
	# O pulso encosta no cabo de propósito: o antebraço só conta do meio para trás.
	return minf(_segment_distance(shoulder, elbow, a, b), _segment_distance(elbow, elbow.lerp(wrist, 0.6), a, b))

static func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a < 0.0000001 and e < 0.0000001:
		return r.length()
	if a < 0.0000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e < 0.0000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 0.0000001 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()

## Turn the mount so the barrel (-Z of the weapon model) points from the muzzle
## to the aim target, pivoting on the trigger grip so the hand stays put.
func _aim_mount() -> void:
	var muzzle := bound_weapon.get_node_or_null("Muzzle") as Marker3D
	var grip := bound_weapon.get_node_or_null("RightGrip") as Marker3D
	if muzzle == null or grip == null:
		return
	# Two passes: turning the gun moves the muzzle a little.
	for pass_index in 2:
		var axis := -bound_weapon.global_basis.z
		var wanted := aim_target - muzzle.global_position
		if axis.length_squared() < 0.000001 or wanted.length_squared() < 0.25:
			return
		var turn := Quaternion(axis.normalized(), wanted.normalized())
		var angle := turn.get_angle()
		var limit := minf(1.0, MAX_AIM_CORRECTION / maxf(angle, 0.0001)) * aim_weight
		turn = Quaternion.IDENTITY.slerp(turn, limit)
		var pivot := grip.global_position
		var frame := weapon_mount.global_transform
		frame.basis = Basis(turn) * frame.basis
		frame.origin = pivot + Basis(turn) * (frame.origin - pivot)
		weapon_mount.global_transform = frame

func _relax_left_arm() -> void:
	var upper := Grip._bone(skeleton, "LeftArm")
	var hand := Grip._bone(skeleton, "LeftHand")
	var hips := Grip._bone(skeleton, "Hips")
	var chest := Grip._bone(skeleton, "Spine2")
	if upper < 0 or hand < 0 or hips < 0 or chest < 0:
		return
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var torso := skeleton.get_bone_global_pose(chest).origin
	var lateral := shoulder - torso
	lateral.y = 0.0
	if lateral.length_squared() < 0.0001:
		return
	lateral = lateral.normalized()
	var hip := skeleton.get_bone_global_pose(hips).origin
	var relaxed_wrist := hip + lateral * 0.28 + Vector3.UP * 0.18
	var relaxed_hand_basis := skeleton.get_bone_global_pose(hand).basis
	Grip.solve_to_target(skeleton, "Left", relaxed_wrist, relaxed_hand_basis)
