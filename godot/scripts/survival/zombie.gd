extends CharacterBody3D
## Zumbi da Sobrevivência. A vida mora no servidor; o movimento é simulado
## pelo jogador anfitrião (`controlled`), que manda as posições para os outros.
## Nos demais clientes o zumbi só segue as posições recebidas.
##
## Tipos: andarilho (lento, como no Project Zomboid), corredor (rápido, frágil)
## e brutamontes (lento, muita vida e dano).
signal damaged(zombie_id: String, zone: String, point: Vector3, normal: Vector3, weapon_id: String)
signal attacked(zombie_id: String, target_id: String)

const HitboxScript = preload("res://scripts/net/hitbox.gd")
const GRAVITY := 22.0
const KINDS := {
	"walker": {"wander": 0.9, "chase": 2.4, "scale": 1.0, "skin": "#7f8f6a", "shirt": "#5a4a3c", "tint": "#ffffff", "width": 1.0},
	"runner": {"wander": 1.2, "chase": 5.0, "scale": 0.95, "skin": "#8c9a74", "shirt": "#3b4d63", "tint": "#d9e0d0", "width": 0.95},
	"brute":  {"wander": 0.8, "chase": 2.1, "scale": 1.18, "skin": "#6f7d5c", "shirt": "#463b33", "tint": "#a89a8a", "width": 1.25},
}
const ZombieAvatar = preload("res://scripts/survival/zombie_avatar.gd")
var _avatar: Node3D
const SIGHT := 24.0 # metros; de noite cai pela metade
const HIDDEN_SIGHT := 4.0 # agachado dentro da grama alta
const HEARING := 48.0 # tiros ouvidos daqui
const ATTACK_RANGE := 1.7
const ATTACK_COOLDOWN := 1.3
const GIVE_UP := 45.0
const SLEEP_RANGE := 95.0 # longe de todos: fica parado (economiza o anfitrião)
enum Anim { IDLE, WALK, RUN, ATTACK }

var zombie_id := ""
var kind := "walker"
var hp := 60.0
var dead := false
var controlled := false
## Devolve [{id, node}] dos jogadores vivos (anfitrião).
var targets: Callable
var night := false

var anim := Anim.IDLE
var _target_id := ""
var _target: Node3D
var _investigate := Vector3.INF
var _wander_goal := Vector3.INF
var _think := 0.0
var _attack_timer := 0.0
var _lost_timer := 0.0
var _avoid_side := 1.0
var _avoid_timer := 0.0
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _has_remote := false
var _phase := randf() * TAU
var _death_timer := 0.0
var _flinch := 0.0

var visual: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _torso: Node3D
var _head: Node3D
var hitboxes: Array[StaticBody3D] = []

func setup(id: String, zombie_kind: String, start_hp: float) -> void:
	zombie_id = id
	kind = zombie_kind if KINDS.has(zombie_kind) else "walker"
	hp = start_hp
	name = "Zombie_" + id

func _ready() -> void:
	collision_layer = HitboxScript.LAYER_CHARACTERS
	collision_mask = HitboxScript.LAYER_WORLD | HitboxScript.LAYER_CHARACTERS
	var spec: Dictionary = KINDS[kind]
	var s := float(spec["scale"])
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32 * s
	capsule.height = 1.75 * s
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.875 * s
	add_child(col)
	if ZombieAvatar.available():
		# Modelo de zumbi animado (assets/personagens/zumbi); sem ele, o corpo de blocos.
		_avatar = ZombieAvatar.new()
		_avatar.set("actor", self)
		_avatar.set("tint", Color(spec.get("tint", "#ffffff")))
		_avatar.scale = Vector3(float(spec.get("width", 1.0)), 1.0, float(spec.get("width", 1.0))) * s
		add_child(_avatar)
		visual = _avatar
		hitboxes.assign(_avatar.get("hitboxes"))
	else:
		_build_body(spec, s)
	_remote_pos = global_position
	_avoid_side = 1.0 if randf() < 0.5 else -1.0

# ---------------------------------------------------------------- corpo ---

func _mat(hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 0.9
	return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = pos
	m.material_override = material
	parent.add_child(m)
	return m

func _hitbox(parent: Node3D, pos: Vector3, size: Vector3, zone: String) -> void:
	var body: StaticBody3D = HitboxScript.new()
	body.set("actor", self)
	body.set("zone", zone)
	body.position = pos
	parent.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var c := CollisionShape3D.new()
	c.shape = shape
	body.add_child(c)
	hitboxes.append(body)

## Corpo simples de blocos (leve para 60+ zumbis): braços esticados para a frente.
func _build_body(spec: Dictionary, s: float) -> void:
	var skin := _mat(str(spec["skin"]))
	var shirt := _mat(str(spec["shirt"]))
	var pants := _mat("#33383a")
	var blood := _mat("#5c1512")
	visual = Node3D.new()
	visual.scale = Vector3.ONE * s
	add_child(visual)
	_torso = Node3D.new()
	_torso.position.y = 0.95
	visual.add_child(_torso)
	_box(_torso, Vector3(0, 0.33, 0), Vector3(0.5, 0.62, 0.28), shirt)
	_box(_torso, Vector3(0.08, 0.38, 0.145), Vector3(0.22, 0.18, 0.01), blood)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.78, 0.04)
	_torso.add_child(_head)
	_box(_head, Vector3(0, 0, 0), Vector3(0.27, 0.3, 0.27), skin)
	for x in [-0.07, 0.07]:
		_box(_head, Vector3(x, 0.03, -0.14), Vector3(0.05, 0.04, 0.01), _mat("#d8d26a"))
	_box(_head, Vector3(0, -0.09, -0.14), Vector3(0.12, 0.03, 0.01), blood)
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.31, 0.58, 0)
		shoulder.rotation.x = 1.35 # braços para a frente (-Z)
		_torso.add_child(shoulder)
		_box(shoulder, Vector3(0, -0.3, 0), Vector3(0.12, 0.6, 0.12), shirt if side < 0 else skin)
		_box(shoulder, Vector3(0, -0.66, 0), Vector3(0.1, 0.14, 0.1), skin)
		_arms.append(shoulder)
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.13, 0.95, 0)
		visual.add_child(hip)
		_box(hip, Vector3(0, -0.46, 0), Vector3(0.16, 0.9, 0.17), pants)
		_box(hip, Vector3(0, -0.92, -0.05), Vector3(0.15, 0.08, 0.26), _mat("#2a2420"))
		_legs.append(hip)
	_hitbox(_head, Vector3.ZERO, Vector3(0.32, 0.34, 0.32), "head")
	_hitbox(_torso, Vector3(0, 0.33, 0), Vector3(0.56, 0.66, 0.34), "chest")
	_hitbox(visual, Vector3(0, 0.5, 0), Vector3(0.42, 0.9, 0.28), "leg")

## As hitboxes chamam isto; o servidor decide o dano.
func receive_hit(zone: String, _amount: float, point: Vector3, normal: Vector3, weapon: String) -> void:
	if dead:
		return
	_flinch = 1.0
	damaged.emit(zombie_id, zone, point, normal, weapon)

func take_damage(amount: float) -> void:
	receive_hit("chest", amount, global_position + Vector3(0, 1.2, 0), Vector3.UP, "")

# ------------------------------------------------------------------ rede ---

## [id, x, y, z, yaw, anim] para o servidor.
func state() -> Array:
	var p := global_position
	return [zombie_id, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rotation.y, 0.01), int(anim)]

func apply_state(entry: Array) -> void:
	if dead or controlled or entry.size() < 6:
		return
	_remote_pos = Vector3(float(entry[1]), float(entry[2]), float(entry[3]))
	_remote_yaw = float(entry[4])
	anim = int(entry[5]) as Anim
	if not _has_remote:
		global_position = _remote_pos
		rotation.y = _remote_yaw
		_has_remote = true

func set_controlled(value: bool) -> void:
	controlled = value and not dead
	velocity = Vector3.ZERO

## Tiro ouvido: vai ver de onde veio (anfitrião).
func hear(at: Vector3) -> void:
	if dead or not controlled or _target != null:
		return
	if global_position.distance_to(at) < HEARING:
		_investigate = at

func die() -> void:
	if dead:
		return
	dead = true
	controlled = false
	collision_layer = 0
	collision_mask = HitboxScript.LAYER_WORLD
	for body in hitboxes:
		body.collision_layer = 0
	_death_timer = 0.0

# ---------------------------------------------------------------- quadro ---

func _physics_process(delta: float) -> void:
	if dead:
		_death_timer += delta
		visual.rotation.x = lerpf(visual.rotation.x, PI * 0.5, minf(1.0, delta * 5.0))
		visual.position.y = lerpf(visual.position.y, 0.15, minf(1.0, delta * 5.0))
		if _death_timer > 8.0:
			queue_free()
		return
	if controlled:
		_run_ai(delta)
	else:
		var blend := minf(1.0, delta * 8.0)
		global_position = global_position.lerp(_remote_pos, blend)
		rotation.y = lerp_angle(rotation.y, _remote_yaw, blend)
	_animate(delta)

func _animate(delta: float) -> void:
	if _avatar != null:
		# Distância da câmera decide o detalhe da animação.
		var camera := get_viewport().get_camera_3d()
		var d := camera.global_position.distance_to(global_position) if camera != null else 0.0
		var lod := 0 if d < 45.0 else (1 if d < 110.0 else 2)
		_flinch = move_toward(_flinch, 0.0, delta * 4.0)
		_avatar.set("flinch", maxf(float(_avatar.get("flinch")), _flinch))
		var rate := clampf(velocity.length() / 2.4, 0.6, 1.6) if anim == Anim.WALK else clampf(velocity.length() / 5.0, 0.7, 1.4)
		_avatar.call("animate", delta, int(anim), rate if controlled else 1.0, lod)
		return
	var speed: float = float({Anim.IDLE: 0.0, Anim.WALK: 5.0, Anim.RUN: 11.0, Anim.ATTACK: 3.0}[anim])
	_phase += delta * speed
	var swing := sin(_phase) * (0.55 if anim == Anim.RUN else 0.35) * (0.0 if anim == Anim.IDLE else 1.0)
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	var arm_base := 1.35
	if anim == Anim.ATTACK:
		arm_base = 1.35 + sin(_phase * 3.0) * 0.6
	_arms[0].rotation.x = arm_base + sin(_phase * 0.7) * 0.12
	_arms[1].rotation.x = arm_base + cos(_phase * 0.8) * 0.12
	# Curvado para a frente (-Z); o tranco do tiro empurra para trás.
	_torso.rotation.x = -0.18 - (0.15 if anim == Anim.RUN else 0.0)
	_head.rotation.z = sin(_phase * 0.5) * 0.15
	_flinch = move_toward(_flinch, 0.0, delta * 4.0)
	_torso.rotation.x += _flinch * 0.4

func _closest_target() -> Dictionary:
	var best := {}
	var best_d := INF
	if not targets.is_valid():
		return best
	for entry in targets.call():
		var node: Node3D = entry["node"]
		var d := global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = {"id": entry["id"], "node": node, "dist": d, "range": _sight_for(entry)}
	return best

## Quanto o zumbi enxerga esse alvo: agachado na grama alta = só bem de perto.
func _sight_for(entry: Dictionary) -> float:
	var sight := SIGHT * (0.55 if night else 1.0)
	var grass := bool(entry.get("grass", false))
	var crouch := bool(entry.get("crouch", false))
	if grass and crouch:
		return HIDDEN_SIGHT
	if grass or crouch:
		sight *= 0.65
	return sight

func _sees(node: Node3D) -> bool:
	var from := global_position + Vector3(0, 1.6, 0)
	var to := node.global_position + Vector3(0, 1.4, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, HitboxScript.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _run_ai(delta: float) -> void:
	var spec: Dictionary = KINDS[kind]
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_think -= delta
	if _think <= 0.0:
		_think = 0.3 + randf() * 0.2
		var near := _closest_target()
		if near.is_empty() or float(near["dist"]) > SLEEP_RANGE:
			_target = null
			anim = Anim.IDLE
			velocity.x = 0.0
			velocity.z = 0.0
			_apply_gravity(delta)
			return
		var sight := float(near["range"])
		if _target == null:
			if float(near["dist"]) < sight and _sees(near["node"]):
				_target = near["node"]
				_target_id = str(near["id"])
				_lost_timer = 0.0
		elif not is_instance_valid(_target) or global_position.distance_to(_target.global_position) > GIVE_UP:
			_target = null
		else:
			# Troca para quem estiver bem mais perto.
			if str(near["id"]) != _target_id and float(near["dist"]) + 4.0 < global_position.distance_to(_target.global_position):
				_target = near["node"]
				_target_id = str(near["id"])
			# Agachou na grama alta longe do zumbi: ele perde a pista em ~3 s e vai até o último ponto.
			var hiding := str(near["id"]) == _target_id and float(near["range"]) <= HIDDEN_SIGHT and float(near["dist"]) > HIDDEN_SIGHT * 2.0
			if _sees(_target) and not hiding:
				_lost_timer = 0.0
			else:
				_lost_timer += 2.7 if hiding else 0.4
				if _lost_timer > 8.0:
					_investigate = _target.global_position
					_target = null
	var goal := Vector3.INF
	var speed := float(spec["wander"])
	anim = Anim.WALK
	if _target != null:
		goal = _target.global_position
		speed = float(spec["chase"])
		anim = Anim.RUN if speed > 3.0 else Anim.WALK
		var dist := global_position.distance_to(goal)
		if dist < ATTACK_RANGE:
			speed = 0.0
			anim = Anim.ATTACK
			if _attack_timer <= 0.0:
				_attack_timer = ATTACK_COOLDOWN
				attacked.emit(zombie_id, _target_id)
	elif _investigate != Vector3.INF:
		goal = _investigate
		speed = float(spec["chase"]) * 0.75
		if global_position.distance_to(goal) < 2.0:
			_investigate = Vector3.INF
	else:
		if _wander_goal == Vector3.INF or global_position.distance_to(_wander_goal) < 1.5 or randf() < delta * 0.05:
			_wander_goal = global_position + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
		goal = _wander_goal
		if randf() < 0.3 and global_position.distance_to(goal) < 3.0:
			anim = Anim.IDLE
			speed = 0.0
	var dir := Vector3.ZERO
	if goal != Vector3.INF and speed > 0.0:
		dir = goal - global_position
		dir.y = 0.0
		dir = dir.normalized()
		dir = _avoid(dir, delta)
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, delta * 6.0))
	elif _target != null:
		var to := _target.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 8.0))
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_apply_gravity(delta)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
	move_and_slide()

## Contorna paredes, carros e árvores: se a frente está bloqueada, desvia para um lado por um tempo.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	_avoid_timer = maxf(0.0, _avoid_timer - delta)
	var from := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 1.4, HitboxScript.LAYER_WORLD)
	var blocked := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	if blocked:
		if _avoid_timer <= 0.0 and randf() < 0.15:
			_avoid_side = -_avoid_side
		_avoid_timer = 0.8
	if _avoid_timer > 0.0:
		return dir.rotated(Vector3.UP, _avoid_side * 1.1).normalized()
	return dir
