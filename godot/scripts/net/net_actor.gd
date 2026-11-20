extends CharacterBody3D
## Another combatant in an online match: a remote human, or a bot.
## Remote actors interpolate the states received from the server.
## When this client is the bot host, bots run their AI here with real map
## collision and report hits to the server, which owns every health value.
signal damaged(actor_id: String, zone: String, point: Vector3, normal: Vector3, weapon_id: String)
signal bot_fired(actor_id: String, weapon_id: String, from: Vector3, to: Vector3)
signal bot_hit(actor_id: String, target_id: String, zone: String)
signal bot_loot(actor_id: String, crate_id: String)
signal bot_heal(actor_id: String) # use a carried medkit

const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const WeaponProportions = preload("res://scripts/weapons/WeaponProportions.gd")
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const MatchLayout = preload("res://scripts/net/match_layout.gd")
const BotNav = preload("res://scripts/net/bot_nav.gd")
const WeaponData = preload("res://scripts/weapon_data.gd")
# Bots prefer the strongest weapon they have picked up.
const WEAPON_PREFERENCE := ["rifle", "smg", "shotgun", "sniper", "pistol"]
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
const BOT_FIRE_INTERVAL := 0.45 # minimum gap between bot shots (fast guns are slowed to this)
const BOT_VIEW_RANGE := 40.0
# Main roads are always clear (tests/map_layout.gd), so bots patrol on them.
const ROAD_LINES := [-48.0, 0.0, 48.0]

var actor_id := ""
var display_name := ""
var tag_subtitle := "" # rank for players, "BOT" for bots
var is_bot := false
var team := -1 # team matches: 0/1; -1 in free-for-all
var ally := false # same team as the local player: blue tag, seen through walls
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
# Bot magazine: each weapon has its own cadence, mag size and reload time.
var _bot_mag := 0
var _bot_mag_weapon := ""
var _bot_reloading := false
var _waypoint := Vector3.ZERO
var _has_waypoint := false
var _stuck_timer := 0.0
var _strafe_phase := randf() * TAU
var _sees_target := false
var _move_amount := 0.0
var _death_timer := 0.0
var hitboxes: Array[StaticBody3D] = []
# Loot: everyone starts unarmed in online matches.
var armed := false
var owned_weapons: Dictionary = {}
var medkits := 0 # carried (server count)
var _heal_cooldown := 0.0
var crate_targets: Callable # returns Array of {id, pos} for unopened crates
var _goal_crate := ""
var _loot_cooldown := 0.0
var _wander_goal := Vector3.ZERO
var _detour_until := 0
var _flinch := 0.0
var _flinch_side := 0.0
var _lean := 0.0
var _approach_point := Vector3.INF # nav waypoint toward a visible target behind an obstacle
const HEARING_RANGE := 30.0 # enemies closer than this are "heard" and checked out
## Modo caçada (só bots vivos na partida): vão direto ao inimigo mais próximo,
## correndo mais, enxergando mais longe e errando menos, para a partida acabar logo.
var hunt_mode := false
const HUNT_SPEED_SCALE := 1.35
const HUNT_VIEW_SCALE := 1.6
const HUNT_ACCURACY_BONUS := 0.18
const WANDER_PATIENCE := 25.0 # seconds before giving up on a roaming spot
var _wander_timer := 0.0

func setup(id: String, label: String, bot: bool) -> void:
	actor_id = id
	display_name = label
	is_bot = bot
	name = "Actor_" + id
	if bot:
		character_id = bot_character(id)

## Personagem visível deste combatente: jogadores mandam o seu no estado ("ch");
## bots ganham um fixo pelo id (o mesmo em todos os jogos, sem tráfego de rede).
var character_id := CharacterRegistry.DEFAULT_ID

static func bot_character(id: String) -> String:
	var choices: Array[String] = []
	for definition in CharacterRegistry.all_characters():
		if CharacterRegistry.is_available(definition.id):
			choices.append(definition.id)
	if choices.is_empty():
		return CharacterRegistry.DEFAULT_ID
	return choices[posmod(id.hash(), choices.size())]

## Troca o corpo visível (hitboxes e arma vêm junto). Personagem desconhecido
## ou que não carrega mantém o atual.
func set_character(id: String) -> void:
	if id == character_id or id.is_empty() or not is_inside_tree():
		return
	var next := CharacterRegistry.create_visual(id)
	if next == null:
		return
	add_child(next)
	if next.has_method("is_visual_ready") and not bool(next.call("is_visual_ready")):
		next.queue_free()
		return
	character_id = id
	if visual != null:
		# Hitboxes live under the old skeleton and the gun under its mount: both go with it.
		remove_child(visual)
		visual.queue_free()
	hitboxes.clear()
	weapon_model = null
	visual = next
	_build_hitboxes()
	if dead or sleeping:
		for body in hitboxes:
			body.collision_layer = 0
	_set_weapon(weapon_id)
	_apply_armed()

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
	visual = CharacterRegistry.create_visual(character_id)
	if visual == null and character_id != CharacterRegistry.DEFAULT_ID:
		character_id = CharacterRegistry.DEFAULT_ID
		visual = CharacterRegistry.create_visual(character_id)
	if visual != null:
		add_child(visual)
		_build_hitboxes()
	sound_fx = SoundFXScript.new()
	sound_fx.name = "SoundFX"
	sound_fx.position.y = 1.4
	add_child(sound_fx)
	name_tag = Label3D.new()
	name_tag.text = display_name if tag_subtitle.is_empty() else "%s\n[%s]" % [display_name, tag_subtitle]
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font_size = 44
	name_tag.outline_size = 10
	name_tag.pixel_size = 0.004
	name_tag.modulate = Color("#7cc8ff") if ally else Color("#ff8f7a")
	name_tag.no_depth_test = ally
	name_tag.position.y = 2.15
	add_child(name_tag)
	target_position = global_position
	_set_weapon(weapon_id)
	_apply_armed()

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

## Weapon in hand only when this combatant has one.
func _apply_armed() -> void:
	if weapon_model != null:
		weapon_model.visible = armed
	if visual != null and visual.has_method("set_armed"):
		visual.call("set_armed", armed)

## Server confirmed a loot pickup for this combatant.
func give_weapon(id: String) -> void:
	owned_weapons[id] = true
	for preferred in WEAPON_PREFERENCE:
		if owned_weapons.has(preferred):
			if preferred != weapon_id or not armed:
				_set_weapon(preferred)
			break
	armed = true
	_apply_armed()

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
	# Heavy hits also play the knockback recoil on the upper body.
	if (_amount >= 20.0 or weapon in ["sniper", "shotgun"]) and visual != null and visual.has_method("play_action"):
		visual.call("play_action", "hit")
	damaged.emit(actor_id, zone, point, normal, weapon)

## Legacy entry point (no zone information).
func take_damage(amount: float) -> void:
	receive_hit("chest", amount, global_position + Vector3(0, 1.3, 0), Vector3.UP, "")

func apply_state(state: Dictionary) -> void:
	if dead or controlled or sleeping:
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
	var ch := str(state.get("ch", ""))
	if not ch.is_empty() and ch != character_id:
		set_character(ch)
	var w := str(state.get("w", weapon_id))
	if w != weapon_id:
		_set_weapon(w)
	var now_armed := not bool(state.get("h", false))
	if now_armed != armed:
		armed = now_armed
		_apply_armed()

## Sobrevivência: golpe de trabalho (machado/pé de cabra) visto pelos outros.
func set_action(act: String, tool: String) -> void:
	if visual != null and visual.has_method("set_action"):
		visual.call("set_action", act, tool)

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

## Mata-mata: volta à partida noutro lugar, com vida cheia e só a pistola.
func revive(at: Vector3, weapon: String) -> void:
	dead = false
	hp = 100.0
	visible = true
	set_physics_process(true)
	collision_layer = HitboxScript.LAYER_CHARACTERS
	collision_mask = HitboxScript.LAYER_WORLD | HitboxScript.LAYER_CHARACTERS
	for body in hitboxes:
		body.collision_layer = HitboxScript.LAYER_HITBOXES
	if visual != null:
		visual.rotation = Vector3.ZERO
	name_tag.visible = true
	global_position = at
	target_position = at
	velocity = Vector3.ZERO
	_has_state = false
	remote_state = {}
	_death_timer = 0.0
	medkits = 0
	_ai_target_id = ""
	_ai_target = null
	_has_waypoint = false
	_goal_crate = ""
	_approach_point = Vector3.INF
	owned_weapons.clear()
	if weapon.is_empty():
		# Novo round de equipes, jogador remoto: a arma volta com o próximo estado ("w").
		armed = false
		_apply_armed()
	else:
		give_weapon(weapon)

## Sobrevivência: jogador que saiu do jogo. Fica deitado de costas, dormindo,
## no lugar onde saiu — os outros veem, mas ninguém acerta nem esbarra nele.
var sleeping := false
func sleep(yaw: float) -> void:
	sleeping = true
	controlled = false
	armed = false
	_apply_armed()
	collision_layer = 0
	collision_mask = 0
	for body in hitboxes:
		body.collision_layer = 0
	rotation.y = yaw
	target_position = global_position
	if visual != null:
		visual.rotation = Vector3(PI * 0.5, 0, 0) # de barriga para cima
		visual.position.y = 0.16
		if visual.has_method("set_aim_target"):
			visual.call("set_aim_target", global_position + Vector3(0, 30, 0), false)
	if name_tag != null:
		name_tag.text = "%s\nZzz… (dormindo)" % display_name
		name_tag.modulate = Color("#b8c4cc")
		name_tag.position.y = 0.9

func play_remote_shot(weapon: String) -> void:
	sound_fx.call("shot", weapon)

func _physics_process(delta: float) -> void:
	if sleeping:
		# Parado, respirando devagar (pose de descanso, sem andar nem mirar).
		if visual != null and visual.has_method("animate"):
			visual.call("animate", delta, 0.0, false, false, false, false, false, Vector2(0, -1), Vector3.ZERO)
		return
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
	_update_aim()
	# Hit reaction: a quick lean away from the shot that settles back.
	_flinch = move_toward(_flinch, 0.0, delta * 5.0)
	# Peeking (Q/E while aiming): the whole body tilts, hitboxes included.
	var target_lean := 0.0 if controlled else clampf(float(remote_state.get("l", 0.0)), -1.0, 1.0)
	_lean = move_toward(_lean, target_lean, delta * 6.0)
	if visual != null:
		var kick := sin(_flinch * PI * 0.5)
		visual.rotation.x = -0.16 * kick
		visual.rotation.z = _flinch_side * 0.18 * kick - _lean * 0.24

## Point the held weapon where this combatant looks: its target for a bot this
## client runs, otherwise the yaw/pitch it reported (rifle clips alone hold the
## barrel ~20° off to the side).
func _update_aim() -> void:
	if visual == null or not visual.has_method("set_aim_target"):
		return
	var eye := global_position + Vector3(0, 1.45, 0)
	var point: Vector3
	if controlled and _ai_target != null and _sees_target:
		point = _ai_target.global_position + Vector3(0, 1.3, 0)
	else:
		var look_pitch := float(remote_state.get("pi", 0.0)) if not controlled else 0.0
		var yaw := rotation.y
		point = eye + Vector3(-sin(yaw) * cos(look_pitch), sin(look_pitch), -cos(yaw) * cos(look_pitch)) * 30.0
	var running := _move_amount > 0.8 if controlled else bool(remote_state.get("r", false))
	var reloading := false if controlled else bool(remote_state.get("rl", false))
	visual.call("set_aim_target", point, armed and not running and not reloading)

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
	if visual.has_method("set_prone"):
		visual.call("set_prone", bool(remote_state.get("pr", false)))
	visual.call("animate", delta, move, running, crouch, aim, air, reload, Vector2(0, -1), local_velocity)

## Compact state for the server, same shape as the local player's packet.
func bot_state() -> Dictionary:
	var p := global_position
	return {"id": actor_id, "p": [p.x, p.y, p.z], "y": rotation.y, "w": weapon_id, "m": _move_amount, "r": _move_amount > 0.8, "c": false, "a": _sees_target, "f": not is_on_floor(), "rl": _bot_reloading, "h": not armed, "v": [velocity.x, velocity.z]}

# ---------------------------------------------------------------- bot AI ---

func _run_bot(delta: float) -> void:
	_think_timer -= delta
	_fire_timer -= delta
	_loot_cooldown -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.35
		_think()
	var desired := Vector3.ZERO
	var speed := BOT_SPEED
	if armed and _ai_target != null and _sees_target:
		var to_target := _ai_target.global_position - global_position
		to_target.y = 0.0
		var distance := to_target.length()
		var forward := to_target.normalized()
		rotation.y = lerp_angle(rotation.y, atan2(-forward.x, -forward.z), minf(1.0, delta * 8.0))
		_strafe_phase += delta * 1.3
		var side := forward.cross(Vector3.UP) * sin(_strafe_phase)
		if Time.get_ticks_msec() < _detour_until:
			# Stuck while fighting (e.g. against a low wall it can see over): side-step.
			var away := _waypoint - global_position
			away.y = 0.0
			desired = away.normalized() if away.length() > 0.2 else Vector3.ZERO
		elif distance > 16.0:
			# Approach: straight when walkable, otherwise along the nav route.
			var approach := forward
			if _approach_point != Vector3.INF:
				var to_point := _approach_point - global_position
				to_point.y = 0.0
				if to_point.length() > 0.4:
					approach = to_point.normalized()
			desired = approach + side * 0.3
		elif distance < 7.0:
			desired = -forward + side * 0.5
		else:
			desired = side * 0.8
		if _fire_timer <= 0.0:
			_bot_fire_cycle(distance)
	else:
		var to := _waypoint - global_position
		to.y = 0.0
		if to.length() < 0.6:
			_think_timer = 0.0 # reached: choose the next waypoint right away
		elif to.length() > 0.2:
			desired = to.normalized()
		speed = BOT_RUN_SPEED * (HUNT_SPEED_SCALE if hunt_mode else 1.0)
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
	# Unstick: if the bot wants to move but cannot, side-step for a moment.
	if desired.length_squared() > 0.1 and planar < 0.4:
		_stuck_timer += delta
		if _stuck_timer > 0.8:
			_stuck_timer = 0.0
			var side := desired.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
			_waypoint = global_position + side * 2.5 - desired * 1.0
			_detour_until = Time.get_ticks_msec() + 900
	else:
		_stuck_timer = 0.0
	var fighting := armed and _sees_target
	_animate(delta, _move_amount, _move_amount > 0.8 and not fighting, false, fighting, not is_on_floor(), false, Vector3(real.x, 0, real.z))

## Decide what to do: fight a visible enemy, grab loot, or move toward people.
func _think() -> void:
	_heal_cooldown -= 0.35
	if medkits > 0 and hp < 45.0 and _heal_cooldown <= 0.0:
		_heal_cooldown = 2.0
		bot_heal.emit(actor_id)
	var fallback := _pick_target()
	if armed and _sees_target:
		# Seeing a target does not mean the way is clear (low walls, rails).
		var target_ground := Vector3(_ai_target.global_position.x, global_position.y, _ai_target.global_position.z)
		_approach_point = Vector3.INF if _clear_path(target_ground) else _route_to(target_ground)
		return
	_approach_point = Vector3.INF
	if Time.get_ticks_msec() < _detour_until:
		return
	var goal := Vector3.ZERO
	var has_goal := false
	_goal_crate = ""
	var crate := _nearest_crate()
	if hunt_mode and armed and not fallback.is_empty():
		# Caçada: o inimigo mais próximo, esteja onde estiver (sem passear nem saquear).
		goal = (fallback["node"] as Node3D).global_position
		has_goal = true
	elif not crate.is_empty() and (not armed or _flat_distance(crate["pos"], global_position) < 22.0):
		goal = crate["pos"]
		has_goal = true
		_goal_crate = crate["id"]
		if _flat_distance(goal, global_position) < 1.7 and _loot_cooldown <= 0.0:
			_loot_cooldown = 1.0
			bot_loot.emit(actor_id, _goal_crate)
	elif armed and not fallback.is_empty() and _flat_distance((fallback["node"] as Node3D).global_position, global_position) < HEARING_RANGE:
		# Heard someone close by (not in sight): go check.
		goal = (fallback["node"] as Node3D).global_position
		has_goal = true
	if not has_goal:
		# Nobody seen or heard: roam to random walkable spots across the whole map
		# (streets, yards and building interiors), picking a new one on arrival.
		_wander_timer -= 0.35
		if _wander_goal == Vector3.ZERO or _flat_distance(_wander_goal, global_position) < 2.0 or _wander_timer <= 0.0:
			_wander_goal = BotNav.random_point(get_world_3d())
			_wander_timer = WANDER_PATIENCE
		goal = _wander_goal
	_waypoint = _waypoint_for(goal)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _nearest_crate() -> Dictionary:
	if not crate_targets.is_valid():
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for entry in crate_targets.call():
		# Medkits once armed (weapons first), keeping a couple in reserve.
		if bool(entry.get("med", false)) and (not armed or medkits >= 2):
			continue
		var distance := _flat_distance(entry["pos"], global_position)
		if distance < best_distance:
			best_distance = distance
			best = entry
	return best

## Next point to walk to: straight when the way is clear, otherwise along an
## A* path over the map's real collision (doors, crates and building corners
## included), taking the farthest path point that is in plain sight.
## Buildings have a fixed exit line through the door: door_in (inside, facing
## the door) -> door_out (outside). Bots leaving line up on door_in and walk
## straight out; bots entering line up on door_out and walk straight in.
func _waypoint_for(goal: Vector3) -> Vector3:
	var here := MatchLayout.building_at(global_position)
	var there := MatchLayout.building_at(goal)
	var here_name: String = here.get("name", "")
	var there_name: String = there.get("name", "")
	if not here_name.is_empty() and here_name != there_name:
		var door_in: Vector3 = here["door_in"]
		# (0.7 m: waypoints count as reached at 0.6 m, so this never loops in place)
		var lined_up := _flat_distance(global_position, door_in) < 0.7 or (absf(global_position.x - door_in.x) < 0.45 and global_position.z > door_in.z - 0.5)
		return here["door_out"] if lined_up else _route_to(door_in)
	if not there_name.is_empty() and there_name != here_name:
		var door_out: Vector3 = there["door_out"]
		var at_door := _flat_distance(global_position, door_out) < 1.0
		return there["door_in"] if at_door else _route_to(door_out)
	return _route_to(goal)

func _route_to(goal: Vector3) -> Vector3:
	if _clear_path(goal):
		return goal
	var route := BotNav.path(get_world_3d(), global_position, goal)
	if route.is_empty():
		return _nearest_road_point(goal)
	for index in [16, 10, 6, 3, 1]:
		if index < route.size() and _clear_path(route[index]):
			return route[index]
	return route[mini(1, route.size() - 1)]

func _clear_path(target: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.32
	query.shape = sphere
	query.collision_mask = HitboxScript.LAYER_WORLD
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, 0.9, 0))
	query.motion = Vector3(target.x, global_position.y, target.z) - global_position
	return get_world_3d().direct_space_state.cast_motion(query)[0] >= 0.999

## Closest visible enemy (fights only when armed); returns the closest enemy overall.
## In team matches, teammates are never targets.
func _pick_target() -> Dictionary:
	var previous_target := _ai_target_id
	_ai_target = null
	_ai_target_id = ""
	_sees_target = false
	if not combatants.is_valid():
		return {}
	var best_distance := INF
	var fallback: Dictionary = {}
	var fallback_distance := INF
	for entry in combatants.call():
		if entry["id"] == actor_id:
			continue
		if team >= 0 and int(entry.get("team", -1)) == team:
			continue # teammate
		var node: Node3D = entry["node"]
		var distance := global_position.distance_to(node.global_position)
		if distance < fallback_distance:
			fallback_distance = distance
			fallback = entry
		var view_range := BOT_VIEW_RANGE * (HUNT_VIEW_SCALE if hunt_mode else 1.0)
		if armed and distance < view_range and distance < best_distance and _line_of_sight(node):
			best_distance = distance
			_ai_target = node
			_ai_target_id = entry["id"]
	if _ai_target != null:
		_sees_target = true
		if _ai_target_id != previous_target:
			# Reaction time before the first shot at a newly spotted enemy.
			_fire_timer = maxf(_fire_timer, randf_range(0.6, 1.0))
	return fallback

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.55, 0)

func _line_of_sight(node: Node3D) -> bool:
	# Walls only: characters live on other physics layers.
	var query := PhysicsRayQueryParameters3D.create(_eye(), node.global_position + Vector3(0, 1.3, 0), HitboxScript.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

## One trigger pull: respects the weapon's interval, magazine and reload.
func _bot_fire_cycle(distance: float) -> void:
	var stats: Dictionary = WeaponData.stats(weapon_id)
	if _bot_mag_weapon != weapon_id:
		_bot_mag_weapon = weapon_id
		_bot_mag = int(stats["mag"])
		_bot_reloading = false
	if _bot_reloading:
		_bot_reloading = false
		_bot_mag = int(stats["mag"])
	_bot_shoot(distance)
	_bot_mag -= 1
	if _bot_mag <= 0:
		_bot_reloading = true
		_fire_timer = float(stats["reload"]) * randf_range(1.0, 1.2)
	else:
		_fire_timer = maxf(BOT_FIRE_INTERVAL, float(stats["interval"])) * randf_range(0.8, 1.4)

func _bot_shoot(distance: float) -> void:
	if _ai_target == null:
		return
	var aim_point := _ai_target.global_position + Vector3(0, 1.3, 0)
	# Accuracy falls with distance and when the target is moving.
	var chance := clampf(0.62 - distance * 0.011, 0.14, 0.55) + (HUNT_ACCURACY_BONUS if hunt_mode else 0.0)
	if _ai_target is CharacterBody3D and Vector2((_ai_target as CharacterBody3D).velocity.x, (_ai_target as CharacterBody3D).velocity.z).length() > 3.0:
		chance *= 0.7
	var hit := randf() < chance
	if not hit:
		aim_point += Vector3(randf_range(-1.2, 1.2), randf_range(-0.6, 0.9), randf_range(-1.2, 1.2))
	var from := muzzle_position()
	sound_fx.call("shot", weapon_id)
	bot_fired.emit(actor_id, weapon_id, from, aim_point)
	if not hit:
		return
	# Same damage as the player's weapons (the server applies weapon × body zone).
	if weapon_id == "shotgun":
		# Pellets spread out: close range lands most of the 8, far range only a few.
		var pellets := int(WeaponData.stats("shotgun")["pellets"])
		var landed := clampi(roundi(pellets * (1.0 - distance / 22.0)), 1, pellets)
		for i in landed:
			bot_hit.emit(actor_id, _ai_target_id, "chest")
	else:
		bot_hit.emit(actor_id, _ai_target_id, _bot_hit_zone())

## Where a bot bullet lands: mostly the torso, sometimes head or limbs.
func _bot_hit_zone() -> String:
	var roll := randf()
	if roll < 0.12:
		return "head"
	if roll < 0.67:
		return "chest"
	if roll < 0.80:
		return "pelvis"
	return "arm" if roll < 0.90 else "leg"

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
