extends CharacterBody3D
## Another combatant in an online match: a remote human, or a bot.
## Remote actors interpolate the states received from the server.
## When this client is the bot host, bots run their AI here with real map
## collision and report hits to the server, which owns every health value.
signal damaged(actor_id: String, zone: String, point: Vector3, normal: Vector3, weapon_id: String)
signal bot_fired(actor_id: String, weapon_id: String, from: Vector3, to: Vector3)
signal bot_hit(actor_id: String, target_id: String, damage: float)

const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
# Body-part volumes: [from bone, to bone, zone, radius in metres].
# Mixamo bone names; prefixes (mixamorig9_, mixamorig:) are matched by suffix.
const HITBOXES := [
	["Head", "HeadTop_End", "head", 0.115],
	["Neck", "Head", "chest", 0.075],
	["Spine2", "Neck", "chest", 0.16],
	["Spine", "Spine2", "chest", 0.15],
	["Hips", "Spine", "pelvis", 0.155],
	["LeftArm", "LeftForeArm", "arm", 0.058],
	["LeftForeArm", "LeftHand", "arm", 0.048],
	["RightArm", "RightForeArm", "arm", 0.058],
	["RightForeArm", "RightHand", "arm", 0.048],
	["LeftUpLeg", "LeftLeg", "leg", 0.085],
	["LeftLeg", "LeftFoot", "leg", 0.062],
	["RightUpLeg", "RightLeg", "leg", 0.085],
	["RightLeg", "RightFoot", "leg", 0.062],
]
const GRAVITY := 22.0
const BOT_SPEED := 4.2
const BOT_RUN_SPEED := 6.0
const BOT_DAMAGE := 11.0
const BOT_FIRE_INTERVAL := 0.45
const BOT_VIEW_RANGE := 40.0
# Main roads are always clear (tests/map_layout.gd), so bots patrol on them.
const ROAD_LINES := [-48.0, 0.0, 48.0]

var actor_id := ""
var display_name := ""
var is_bot := false
var controlled := false # true when this client simulates the bot
var hp := 100.0
var dead := false
var weapon_id := "rifle"
var visual: Node3D
var weapon_model: Node3D
var sound_fx: Node3D
var name_tag: Label3D
# Remote interpolation state.
var target_position := Vector3.ZERO
var target_yaw := 0.0
var remote_state: Dictionary = {}
var _has_state := false
# Bot AI state, read by the match controller to pick targets.
var combatants: Callable # returns Array of {id, node} still alive
var _ai_target_id := ""
var _ai_target: Node3D
var _think_timer := 0.0
var _fire_timer := 0.0
var _waypoint := Vector3.ZERO
var _has_waypoint := false
var _stuck_timer := 0.0
var _strafe_phase := randf() * TAU
var _sees_target := false
var _move_amount := 0.0
var _death_timer := 0.0
var hitboxes: Array[StaticBody3D] = []
var _flinch := 0.0
var _flinch_side := 0.0

func setup(id: String, label: String, bot: bool) -> void:
	actor_id = id
	display_name = label
	is_bot = bot
	name = "Actor_" + id

func _ready() -> void:
	# Movement capsule: blocks walking, but bullets only see the hitboxes.
	collision_layer = HitboxScript.LAYER_CHARACTERS
	collision_mask = HitboxScript.LAYER_WORLD | HitboxScript.LAYER_CHARACTERS
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.name = "Body"
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)
	visual = CharacterRegistry.create_visual(CharacterRegistry.DEFAULT_ID)
	if visual != null:
		add_child(visual)
		_build_hitboxes()
	sound_fx = SoundFXScript.new()
	sound_fx.name = "SoundFX"
	sound_fx.position.y = 1.4
	add_child(sound_fx)
	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font_size = 44
	name_tag.outline_size = 10
	name_tag.pixel_size = 0.004
	name_tag.modulate = Color("#ff8f7a")
	name_tag.position.y = 2.15
	add_child(name_tag)
	target_position = global_position
	_set_weapon(weapon_id)

func _set_weapon(id: String) -> void:
	weapon_id = id
	if visual == null:
		return
	var mount := visual.get("weapon_mount") as Node3D
	if mount == null:
		return
	if weapon_model != null:
		weapon_model.get_parent().queue_free()
	var gun := Node3D.new()
	gun.name = "Gun"
	mount.add_child(gun)
	weapon_model = Node3D.new()
	gun.add_child(weapon_model)
	var imported := WeaponProportions.create_model(id)
	if imported != null:
		weapon_model.add_child(imported)
	WeaponProportions.apply(weapon_model, id, imported)
	if visual.has_method("configure_weapon"):
		visual.call("configure_weapon", id, weapon_model.scale.x)
	if visual.has_method("bind_weapon"):
		visual.call("bind_weapon", weapon_model)

func muzzle_position() -> Vector3:
	var muzzle := weapon_model.get_node_or_null("Muzzle") as Marker3D if weapon_model != null else null
	return muzzle.global_position if muzzle != null else global_position + Vector3(0, 1.4, 0)

func _find_bone(skeleton: Skeleton3D, suffix: String) -> int:
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if bone == suffix or bone.ends_with("_" + suffix) or bone.ends_with(":" + suffix):
			return i
	return -1

## Capsules from each bone to its child, following the animated skeleton.
func _build_hitboxes() -> void:
	var skeleton := visual.get("skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var scale_factor := maxf(skeleton.global_basis.get_scale().x, 0.0001)
	for spec in HITBOXES:
		var from := _find_bone(skeleton, spec[0])
		var to := _find_bone(skeleton, spec[1])
		if from < 0 or to < 0:
			continue
		var from_rest := skeleton.get_bone_global_rest(from)
		var local_to: Vector3 = from_rest.affine_inverse() * skeleton.get_bone_global_rest(to).origin
		var length := local_to.length()
		if length < 0.001:
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Hit_" + spec[0]
		attachment.bone_name = skeleton.get_bone_name(from)
		skeleton.add_child(attachment)
		var body: StaticBody3D = HitboxScript.new()
		body.name = "Hitbox"
		body.set("actor", self)
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

## Hitboxes call this; the server decides the real damage.
func receive_hit(zone: String, _amount: float, point: Vector3, normal: Vector3, weapon: String) -> void:
	if dead:
		return
	# Flinch away from the shot: stronger on the head.
	_flinch = 1.0 if zone == "head" else 0.6
	var away := -normal
	_flinch_side = signf(global_basis.x.dot(away)) * 0.5
	damaged.emit(actor_id, zone, point, normal, weapon)

## Legacy entry point (no zone information).
func take_damage(amount: float) -> void:
	receive_hit("chest", amount, global_position + Vector3(0, 1.3, 0), Vector3.UP, "")

func apply_state(state: Dictionary) -> void:
	if dead or controlled:
		return
	var p: Array = state.get("p", [])
	if p.size() != 3:
		return
	target_position = Vector3(p[0], p[1], p[2])
	target_yaw = float(state.get("y", 0.0))
	remote_state = state
	if not _has_state:
		global_position = target_position
		rotation.y = target_yaw
		_has_state = true
	var w := str(state.get("w", weapon_id))
	if w != weapon_id:
		_set_weapon(w)

func set_controlled(value: bool) -> void:
	controlled = value and is_bot and not dead
	velocity = Vector3.ZERO
	_has_waypoint = false

func set_hp(value: float, killed: bool) -> void:
	hp = value
	if killed and not dead:
		die()

func die() -> void:
	dead = true
	controlled = false
	collision_layer = 0
	collision_mask = HitboxScript.LAYER_WORLD # keep standing on the ground while falling over
	for body in hitboxes:
		body.collision_layer = 0
	name_tag.visible = false
	_death_timer = 0.0

func play_remote_shot(weapon: String) -> void:
	sound_fx.call("shot", weapon)

func _physics_process(delta: float) -> void:
	if dead:
		# Simple fall-over, then disappear.
		_death_timer += delta
		if visual != null:
			visual.rotation.x = lerpf(visual.rotation.x, -PI * 0.5, minf(1.0, delta * 6.0))
		if _death_timer > 2.5:
			visible = false
			set_physics_process(false)
		return
	if controlled:
		_run_bot(delta)
	else:
		_follow_remote(delta)
	# Hit reaction: a quick lean away from the shot that settles back.
	_flinch = move_toward(_flinch, 0.0, delta * 5.0)
	if visual != null:
		var kick := sin(_flinch * PI * 0.5)
		visual.rotation.x = -0.16 * kick
		visual.rotation.z = _flinch_side * 0.18 * kick

func _follow_remote(delta: float) -> void:
	var blend := minf(1.0, delta * 12.0)
	global_position = global_position.lerp(target_position, blend)
	rotation.y = lerp_angle(rotation.y, target_yaw, blend)
	var v: Array = remote_state.get("v", [0, 0])
	var planar := Vector3(float(v[0]), 0, float(v[1]))
	_animate(delta, float(remote_state.get("m", 0.0)), bool(remote_state.get("r", false)), bool(remote_state.get("c", false)), bool(remote_state.get("a", false)), bool(remote_state.get("f", false)), bool(remote_state.get("rl", false)), planar)

func _animate(delta: float, move: float, running: bool, crouch: bool, aim: bool, air: bool, reload: bool, planar_world: Vector3) -> void:
	if visual == null or not visual.has_method("animate"):
		return
	var local_velocity := visual.global_basis.inverse() * planar_world
	visual.call("animate", delta, move, running, crouch, aim, air, reload, Vector2(0, -1), local_velocity)

## Compact state for the server, same shape as the local player's packet.
func bot_state() -> Dictionary:
	var p := global_position
	return {"id": actor_id, "p": [p.x, p.y, p.z], "y": rotation.y, "w": weapon_id, "m": _move_amount, "r": _move_amount > 0.8, "c": false, "a": _sees_target, "f": not is_on_floor(), "rl": false, "v": [velocity.x, velocity.z]}

# ---------------------------------------------------------------- bot AI ---

func _run_bot(delta: float) -> void:
	_think_timer -= delta
	_fire_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.35
		_pick_target()
	var desired := Vector3.ZERO
	var speed := BOT_SPEED
	if _ai_target != null and _sees_target:
		var to_target := _ai_target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		var forward := to_target.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-forward.x, -forward.z), minf(1.0, delta * 8.0))
		_strafe_phase += delta * 1.3
		var side := forward.cross(Vector3.UP) * sin(_strafe_phase)
		if distance > 16.0:
			desired = forward + side * 0.3
		elif distance < 7.0:
			desired = -forward + side * 0.5
		else:
			desired = side * 0.8
		if _fire_timer <= 0.0:
			_fire_timer = BOT_FIRE_INTERVAL * randf_range(0.8, 1.4)
			_bot_shoot(distance)
	else:
		desired = _patrol_direction()
		speed = BOT_RUN_SPEED
		if desired.length_squared() > 0.01:
			rotation.y = lerp_angle(rotation.y, atan2(-desired.x, -desired.z), minf(1.0, delta * 6.0))
	desired.y = 0.0
	if desired.length() > 1.0:
		desired = desired.normalized()
	velocity.x = move_toward(velocity.x, desired.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z * speed, 30.0 * delta)
	velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.1
	move_and_slide()
	var real := get_real_velocity()
	var planar := Vector2(real.x, real.z).length()
	_move_amount = clampf(planar / BOT_RUN_SPEED, 0.0, 1.0)
	# Unstick: if the bot wants to move but cannot, pick another waypoint.
	if desired.length_squared() > 0.1 and planar < 0.4:
		_stuck_timer += delta
		if _stuck_timer > 0.8:
			_stuck_timer = 0.0
			_waypoint = _nearest_road_point(global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)))
			_has_waypoint = true
	else:
		_stuck_timer = 0.0
	_animate(delta, _move_amount, _move_amount > 0.8 and not _sees_target, false, _sees_target, not is_on_floor(), false, Vector3(real.x, 0, real.z))

func _pick_target() -> void:
	_ai_target = null
	_ai_target_id = ""
	_sees_target = false
	if not combatants.is_valid():
		return
	var previous_target := _ai_target_id
	var best_distance := INF
	var fallback: Dictionary = {}
	var fallback_distance := INF
	for entry in combatants.call():
		if entry["id"] == actor_id:
			continue
		var node: Node3D = entry["node"]
		var distance := global_position.distance_to(node.global_position)
		if distance < fallback_distance:
			fallback_distance = distance
			fallback = entry
		if distance < BOT_VIEW_RANGE and distance < best_distance and _line_of_sight(node):
			best_distance = distance
			_ai_target = node
			_ai_target_id = entry["id"]
	if _ai_target != null:
		_sees_target = true
		if _ai_target_id != previous_target:
			# Reaction time before the first shot at a newly spotted enemy.
			_fire_timer = maxf(_fire_timer, randf_range(0.6, 1.0))
	elif not fallback.is_empty():
		# Nobody visible: head toward the closest opponent along the roads.
		_ai_target_id = fallback["id"]
		_waypoint = _next_road_point((fallback["node"] as Node3D).global_position)
		_has_waypoint = true

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.55, 0)

func _line_of_sight(node: Node3D) -> bool:
	# Walls only: characters live on other physics layers.
	var query := PhysicsRayQueryParameters3D.create(_eye(), node.global_position + Vector3(0, 1.3, 0), HitboxScript.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _bot_shoot(distance: float) -> void:
	if _ai_target == null:
		return
	var aim_point := _ai_target.global_position + Vector3(0, 1.3, 0)
	# Accuracy falls with distance and when the target is moving.
	var chance := clampf(0.62 - distance * 0.011, 0.14, 0.55)
	if _ai_target is CharacterBody3D and Vector2((_ai_target as CharacterBody3D).velocity.x, (_ai_target as CharacterBody3D).velocity.z).length() > 3.0:
		chance *= 0.7
	var hit := randf() < chance
	if not hit:
		aim_point += Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.9), randf_range(-1.2, 1.2))
	var from := muzzle_position()
	sound_fx.call("shot", weapon_id)
	bot_fired.emit(actor_id, weapon_id, from, aim_point)
	if hit:
		bot_hit.emit(actor_id, _ai_target_id, BOT_DAMAGE)

func _patrol_direction() -> Vector3:
	if not _has_waypoint or global_position.distance_to(_waypoint) < 2.0:
		var goal := global_position + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40))
		_waypoint = _next_road_point(goal)
		_has_waypoint = true
	var direction := _waypoint - global_position
	direction.y = 0.0
	return direction.normalized()

func _nearest_road_point(point: Vector3) -> Vector3:
	# Snap onto the closest road line, clamped to the map.
	var best := Vector3.ZERO
	var best_distance := INF
	for line in ROAD_LINES:
		for candidate in [Vector3(line, 0, clampf(point.z, -48, 48)), Vector3(clampf(point.x, -48, 48), 0, line)]:
			var distance: float = candidate.distance_to(Vector3(point.x, 0, point.z))
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best

func _next_road_point(goal: Vector3) -> Vector3:
	# Stay on the road we are on, moving along it toward the goal; when the goal
	# lies on a crossing road, go to the intersection first.
	var here := _nearest_road_point(global_position)
	var there := _nearest_road_point(goal)
	if absf(here.x - there.x) < 0.5 or absf(here.z - there.z) < 0.5:
		return there
	var on_vertical := false
	for line in ROAD_LINES:
		if absf(here.x - line) < 0.5:
			on_vertical = true
	var corner_line := 0.0
	var best := INF
	for line in ROAD_LINES:
		var value: float = (there.z if on_vertical else there.x)
		if absf(line - value) < best:
			best = absf(line - value)
			corner_line = line
	return Vector3(here.x, 0, corner_line) if on_vertical else Vector3(corner_line, 0, here.z)
