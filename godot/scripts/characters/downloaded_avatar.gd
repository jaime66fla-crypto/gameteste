extends Node3D
## Adapter for the user supplied 65-bone Ch31 avatar.
const AVATAR_SCENE := preload("res://assets/personagens/downloaded/avatar.fbx")
const WALK_WITH_RIFLE := preload("res://assets/personagens/downloaded/movements/walk_with_rifle.tres")
const RUN_TO_STOP := preload("res://assets/personagens/downloaded/movements/run_to_stop.tres")
const PUNCH := preload("res://assets/personagens/downloaded/movements/punch.tres")
const ELBOW_PUNCH := preload("res://assets/personagens/downloaded/movements/elbow_punch.tres")
const IDLE_WITH_RIFLE := preload("res://assets/personagens/downloaded/movements/idle_with_rifle.tres")
const Grip = preload("res://scripts/characters/swat_grip.gd")
const SOURCE_HEIGHT := 1.782
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
	var model := AVATAR_SCENE.instantiate() as Node3D
	model.name = "Avatar"
	# The imported Mixamo model faces +Z; the game character faces -Z.
	model.rotation.y = PI
	# Ch31 source mesh is 1.782 m tall; scale it to the 1.8 m player height.
	# (2.09 is the procedural Jaime's height and shrank this avatar to ~1.54 m,
	# making real-size weapons look oversized.)
	model.scale = Vector3.ONE * (1.8 / SOURCE_HEIGHT)
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or skeleton.get_bone_count() != 65 or animation_player == null:
		return
	if not animation_player.has_animation("Take 001") or not animation_player.has_animation("mixamo_com"):
		return
	# The source run cycle travels about 2.8 m per 0.7 s cycle (4 m/s).
	# Keep the idle Hips horizontal anchor and retain the running vertical bob;
	# CharacterBody3D remains the only owner of horizontal movement.
	var library := animation_player.get_animation_library("").duplicate() as AnimationLibrary
	var hip_bone := skeleton.find_bone("mixamorig9_Hips")
	# Anchor every clip's Hips horizontally at the skeleton rest position, so the
	# visible body stays centred on the character origin (collision, camera,
	# network position). The recorded clips drift up to ~0.76 m forward;
	# vertical bob is kept. CharacterBody3D owns horizontal movement.
	var hip_anchor: Vector3 = skeleton.get_bone_rest(hip_bone).origin
	var run := library.get_animation("mixamo_com").duplicate() as Animation
	run.loop_mode = Animation.LOOP_LINEAR
	_make_in_place(run, hip_anchor)
	library.remove_animation("mixamo_com")
	library.add_animation("run_in_place", run)
	var clips := {"idle_with_rifle": IDLE_WITH_RIFLE, "walk_with_rifle": WALK_WITH_RIFLE, "run_to_stop": RUN_TO_STOP, "punch": PUNCH, "elbow_punch": ELBOW_PUNCH}
	for clip_name in clips:
		# Duplicate: the preloaded resources are shared between avatars.
		var clip := (clips[clip_name] as Animation).duplicate() as Animation
		_make_in_place(clip, hip_anchor)
		library.add_animation(clip_name, clip)
	animation_player.remove_animation_library("")
	animation_player.add_animation_library("", library)
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

func _make_in_place(clip: Animation, hip_anchor: Vector3) -> void:
	for track in range(clip.get_track_count() - 1, -1, -1):
		if clip.track_get_type(track) != Animation.TYPE_POSITION_3D or not String(clip.track_get_path(track)).contains("mixamorig9_Hips"):
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

func animate(delta: float, move_amount: float, running: bool, _crouched: bool, _aiming: bool, airborne: bool, _reloading: bool, _movement_direction: Vector2 = Vector2(0, -1), planar_velocity: Vector3 = Vector3.ZERO) -> void:
	if not ready_ok:
		return
	aim_weight = move_toward(aim_weight, 1.0 if aim_active else 0.0, delta * 7.0)
	animation_player.advance(delta)
	var moving := move_amount > 0.08 and not airborne
	locomotion_active = moving
	if current_clip in ["punch", "elbow_punch"] and animation_player.is_playing():
		_update_weapon_mount()
		return
	if current_clip in ["punch", "elbow_punch"] and not animation_player.is_playing():
		current_clip = ""
	if current_clip == "run_to_stop" and animation_player.is_playing() and not moving:
		_update_weapon_mount()
		return
	var clip := "idle_with_rifle"
	if moving:
		clip = "run_in_place" if running else "walk_with_rifle"
	elif current_clip == "run_in_place":
		clip = "run_to_stop"
	var speed := Vector2(planar_velocity.x, planar_velocity.z).length()
	var gait_rate := clampf(speed / (4.0 if running else 2.8), 0.75, 2.2) if moving else 1.0
	_play_clip(clip, gait_rate)
	_update_weapon_mount()

func play_action(action: String) -> bool:
	if not ready_ok or action not in ["punch", "elbow_punch"]:
		return false
	current_clip = action
	animation_player.play(action, 0.12)
	animation_player.speed_scale = 1.0
	return true

func _play_clip(clip: String, rate: float) -> void:
	if current_clip != clip:
		current_clip = clip
		animation_player.play(clip, 0.18)
	animation_player.speed_scale = rate

func _update_weapon_mount() -> void:
	if skeleton == null or weapon_mount == null:
		return
	var chest_bone := skeleton.find_bone("mixamorig9_Spine2")
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
	var chest := skeleton.find_bone("mixamorig9_Spine2")
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
