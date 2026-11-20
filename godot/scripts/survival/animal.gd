extends CharacterBody3D
## Animal da Sobrevivência: coelho e cervo fogem, javali revida quem bate nele,
## lobo caça quem chega perto. Como os zumbis, a vida mora no servidor e o
## movimento é simulado pelo jogador anfitrião (`controlled`), que manda as
## posições para os outros; nos demais clientes o animal só segue as posições.
##
## Modelos (assets/animais, ver CREDITOS.txt): cervo e lobo da Quaternius com
## animações completas; javali = porco da Quaternius escurecido e com presas,
## pernas animadas por código; coelho (Sherkiz) só tem parado/andar.
signal damaged(animal_id: String, zone: String, point: Vector3, normal: Vector3, weapon_id: String)
signal attacked(animal_id: String, target_id: String)

const HitboxScript = preload("res://scripts/net/hitbox.gd")
const HullScript = preload("res://scripts/survival/zombie_hull.gd")
const GRAVITY := 22.0
## model: arquivo; length: comprimento no jogo (m); face: giro do modelo para olhar -Z;
## walk/run: m/s; anims: nome da animação de cada estado ("" = sem).
const KINDS := {
	"rabbit": {"model": "rabbit", "length": 0.7, "face": PI, "walk": 1.0, "run": 6.5, "radius": 0.16, "height": 0.35,
		"anims": {"idle": "Bunny|Bunny_idle", "walk": "Bunny|Bunny_walk", "run": "Bunny|Bunny_walk", "eat": "Bunny|Bunny_idle"}, "run_rate": 2.4},
	"deer": {"model": "stag", "length": 2.0, "face": PI, "walk": 1.4, "run": 7.5, "radius": 0.4, "height": 1.5,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack_Headbutt", "death": "Death", "eat": "Eating"}},
	"boar": {"model": "pig", "length": 1.45, "face": PI, "walk": 1.2, "run": 5.4, "radius": 0.4, "height": 0.85,
		"anims": {"idle": "Armature|Idle"}, "procedural": true, "tint": Color("#3d342c")},
	"wolf": {"model": "wolf", "length": 1.6, "face": PI, "walk": 1.6, "run": 6.2, "radius": 0.32, "height": 0.9,
		"anims": {"idle": "Idle", "walk": "Walk", "run": "Gallop", "attack": "Attack", "death": "Death", "eat": "Eating"}},
}
const RULES_PATH := "animals"
enum Anim { IDLE, WALK, RUN, ATTACK, EAT }
const ATTACK_RANGE := 1.6
const ATTACK_COOLDOWN := 1.3
const ATTACK_IMPACT := 0.35
const SLEEP_RANGE := 110.0
const GIVE_UP := 38.0

var animal_id := ""
var kind := "deer"
var hp := 80.0
var max_hp := 80.0
var dead := false
var controlled := false
var targets: Callable
var night := false
var anim := Anim.IDLE
var visual: Node3D

var _spec: Dictionary
var _rule: Dictionary
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _current := ""
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _has_remote := false
var _think := 0.0
var _asleep := false
var _goal := Vector3.INF
var _threat: Node3D # de quem foge
var _scared := 0.0
var _target: Node3D # quem persegue (lobo; javali bravo)
var _target_id := ""
var _angry_id := ""
var _angry := 0.0
var _attack_timer := 0.0
var _strike := -1.0
var _rest := 0.0
var _phase := randf() * TAU
var _death_t := 0.0
var _avoid_side := 1.0 if randf() < 0.5 else -1.0
var _avoid_t := 0.0
var _avoid_check := 0.0
var _blocked := false
var _legs: Array = [] # [osso, rotação de repouso, fase] (javali)

func setup(id: String, animal_kind: String, start_hp: float) -> void:
	animal_id = id
	kind = animal_kind if KINDS.has(animal_kind) else "deer"
	hp = start_hp
	name = "Animal_" + id

func _ready() -> void:
	_spec = KINDS[kind]
	_rule = load("res://scripts/survival/survival_data.gd").catalog().get(RULES_PATH, {}).get(kind, {})
	max_hp = float(_rule.get("hp", hp))
	collision_layer = HitboxScript.LAYER_CHARACTERS
	collision_mask = HitboxScript.LAYER_WORLD
	var capsule := CapsuleShape3D.new()
	capsule.radius = float(_spec["radius"])
	capsule.height = maxf(float(_spec["height"]), capsule.radius * 2.0 + 0.01)
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = capsule.height * 0.5
	add_child(col)
	_build_model()
	# Casca de acerto (golpe e tiro): um pouco maior que o corpo, no comprimento do bicho.
	var hull: StaticBody3D = HullScript.new()
	hull.set("actor", self)
	var box := BoxShape3D.new()
	box.size = Vector3(float(_spec["radius"]) * 2.4, float(_spec["height"]), float(_spec["length"]))
	var hull_col := CollisionShape3D.new()
	hull_col.shape = box
	hull.position.y = float(_spec["height"]) * 0.5
	hull.add_child(hull_col)
	add_child(hull)
	_remote_pos = global_position
	_play("idle")

# ---------------------------------------------------------------- modelo ---

func _build_model() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var scene: PackedScene = load("res://assets/animais/%s.glb" % str(_spec["model"]))
	var model: Node3D = scene.instantiate()
	visual.add_child(model)
	# Tamanho e chão: mede a malha e põe as patas em y = 0, centrado.
	var box := _bounds(model)
	var longest := maxf(box.size.x, box.size.z)
	var s := float(_spec["length"]) / maxf(longest, 0.001)
	model.scale = Vector3.ONE * s
	model.position = -Vector3(box.position.x + box.size.x * 0.5, box.position.y, box.position.z + box.size.z * 0.5) * s
	visual.rotation.y = float(_spec["face"])
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_player = players[0]
		for anim_name in _player.get_animation_list():
			var a := _player.get_animation(anim_name)
			if not (anim_name.contains("Death") or anim_name.contains("Attack") or anim_name.contains("Jump")):
				a.loop_mode = Animation.LOOP_LINEAR
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		_skeleton = skels[0]
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.visibility_range_end = 160.0
		if _spec.has("tint"):
			_tint(mi, _spec["tint"])
	if bool(_spec.get("procedural", false)):
		_setup_boar(model)

static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Javali: o porco rosado vira pelagem marrom-acinzentada escura (sem a textura rosa).
static func _tint(mi: MeshInstance3D, tint: Color) -> void:
	for i in mi.get_surface_override_material_count():
		var base := mi.get_active_material(i)
		if base is StandardMaterial3D:
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.albedo_texture = null
			m.albedo_color = tint
			m.roughness = 0.95
			mi.set_surface_override_material(i, m)

## Presas brancas na cabeça e as quatro pernas que o código balança.
func _setup_boar(model: Node3D) -> void:
	# Presas no focinho (no eixo do bicho: frente = -Z, focinho na ponta).
	var tusk := CylinderMesh.new()
	tusk.top_radius = 0.0
	tusk.bottom_radius = 0.025
	tusk.height = 0.16
	tusk.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#d8cfb8")
	tusk.material = mat
	var length := float(_spec["length"])
	# Presas presas ao corpo (tombam junto); o giro desfaz o "face" do modelo.
	var holder := Node3D.new()
	holder.rotation.y = -float(_spec["face"])
	visual.add_child(holder)
	for side in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		m.name = "Tusk"
		m.mesh = tusk
		m.position = Vector3(side * 0.07, float(_spec["height"]) * 0.42, -length * 0.5 + 0.06)
		m.rotation = Vector3(deg_to_rad(-35), 0, side * deg_to_rad(-25))
		holder.add_child(m)
	if _skeleton == null:
		return
	var offsets := {"FrontUpLeg.L": 0.0, "BackUpLeg.R": 0.0, "FrontUpLeg.R": PI, "BackUpLeg.L": PI}
	for bone in offsets:
		var idx := _skeleton.find_bone(bone)
		if idx >= 0:
			_legs.append([idx, _skeleton.get_bone_rest(idx).basis.get_rotation_quaternion(), float(offsets[bone])])

func _play(state: String, rate: float = 1.0) -> void:
	if _player == null:
		return
	var anims: Dictionary = _spec["anims"]
	var anim_name := str(anims.get(state, anims.get("idle", "")))
	if anim_name.is_empty() or not _player.has_animation(anim_name):
		return
	_player.speed_scale = rate
	if anim_name != _current or not _player.is_playing():
		_current = anim_name
		_player.play(anim_name, 0.25)

# ------------------------------------------------------------------ rede ---

func state() -> Array:
	var p := global_position
	return [animal_id, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rotation.y, 0.01), int(anim)]

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

## Hitbox chama isto; o servidor decide o dano.
func receive_hit(zone: String, _amount: float, point: Vector3, normal: Vector3, weapon: String) -> void:
	if not dead:
		damaged.emit(animal_id, zone, point, normal, weapon)

func take_damage(amount: float) -> void:
	receive_hit("chest", amount, global_position + Vector3(0, 0.5, 0), Vector3.UP, "")

## Levou golpe (anfitrião): coelho e cervo disparam; javali e lobo vão para cima de quem bateu.
func hurt(by_id: String, by_node: Node3D) -> void:
	if dead or not controlled:
		return
	match str(_rule.get("behavior", "flee")):
		"flee":
			_threat = by_node
			_scared = 8.0
		_:
			_angry_id = by_id
			_angry = 25.0
			_target = by_node
			_target_id = by_id

## Golpe visto por todos quando o servidor confirma a mordida.
func strike() -> void:
	_strike = 0.0
	_play("attack")

func die() -> void:
	if dead:
		return
	dead = true
	controlled = false
	collision_layer = 0
	for child in get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 0
	_death_t = 0.0
	if str(_spec["anims"].get("death", "")).is_empty():
		if _player != null:
			_player.stop()
	else:
		_play("death")

# ---------------------------------------------------------------- quadro ---

func _physics_process(delta: float) -> void:
	if dead:
		_death_t += delta
		if str(_spec["anims"].get("death", "")).is_empty():
			visual.rotation.z = lerpf(visual.rotation.z, PI * 0.5, minf(1.0, delta * 6.0))
		if _death_t > 6.0:
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
	if _strike >= 0.0:
		_strike += delta
		if _strike > 0.8:
			_strike = -1.0
		return
	match anim:
		Anim.RUN: _play("run", float(_spec.get("run_rate", 1.0)))
		Anim.WALK: _play("walk")
		Anim.ATTACK: _play("attack")
		Anim.EAT: _play("eat")
		_: _play("idle")
	if _legs.is_empty():
		return
	# Javali: pernas balançam no passo (o porco só veio com "parado" e "pulo").
	var moving := anim == Anim.WALK or anim == Anim.RUN or anim == Anim.ATTACK
	if moving:
		if _player != null and _player.is_playing():
			_player.stop()
		_phase += delta * (14.0 if anim != Anim.WALK else 7.0)
	var amp := 0.0 if not moving else (0.65 if anim != Anim.WALK else 0.4)
	for leg in _legs:
		var q: Quaternion = leg[1] * Quaternion(Vector3.RIGHT, sin(_phase + float(leg[2])) * amp)
		_skeleton.set_bone_pose_rotation(int(leg[0]), q)
	if not moving and _player != null and not _player.is_playing():
		_current = ""
		_play("idle")

func _closest() -> Dictionary:
	var best := {}
	var best_d := INF
	if not targets.is_valid():
		return best
	for entry in targets.call():
		var node: Node3D = entry["node"]
		var d := global_position.distance_to(node.global_position)
		if d < best_d:
			best_d = d
			best = {"id": entry["id"], "node": node, "dist": d, "crouch": bool(entry.get("crouch", false)), "grass": bool(entry.get("grass", false))}
	return best

func _node_of(id: String) -> Node3D:
	if not targets.is_valid():
		return null
	for entry in targets.call():
		if str(entry["id"]) == id:
			return entry["node"]
	return null

func _run_ai(delta: float) -> void:
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_scared = maxf(0.0, _scared - delta)
	_angry = maxf(0.0, _angry - delta)
	_rest = maxf(0.0, _rest - delta)
	_think -= delta
	if _asleep and _think > 0.0:
		return
	var behavior := str(_rule.get("behavior", "flee"))
	if _think <= 0.0:
		_think = 0.3 + randf() * 0.2
		var near := _closest()
		_asleep = near.is_empty() or float(near["dist"]) > SLEEP_RANGE
		if _asleep:
			anim = Anim.IDLE
			velocity = Vector3(0, -4, 0)
			move_and_slide()
			_think = 1.0 + randf()
			return
		var notice := float(_rule.get("notice", 10.0))
		if bool(near["crouch"]):
			notice *= 0.5
		if bool(near["grass"]) and bool(near["crouch"]):
			notice *= 0.5
		match behavior:
			"flee":
				if float(near["dist"]) < notice:
					_threat = near["node"]
					_scared = maxf(_scared, 4.0)
			"defend":
				if _angry > 0.0:
					var node := _node_of(_angry_id)
					_target = node if node != null and global_position.distance_to(node.global_position) < GIVE_UP else null
					if _target == null:
						_angry = 0.0
				else:
					_target = null
			"hunt":
				if hp < max_hp * 0.25:
					# Ferido: desiste e foge.
					_target = null
					_threat = near["node"]
					_scared = 6.0
				elif _target == null and float(near["dist"]) < notice * (1.25 if night else 1.0):
					_target = near["node"]
					_target_id = str(near["id"])
				elif _target != null and (not is_instance_valid(_target) or global_position.distance_to(_target.global_position) > GIVE_UP):
					_target = null
	var speed := 0.0
	var dir := Vector3.ZERO
	anim = Anim.IDLE
	if _scared > 0.0 and is_instance_valid(_threat):
		var away := global_position - _threat.global_position
		away.y = 0.0
		dir = away.normalized() if away.length() > 0.01 else -global_basis.z
		speed = float(_spec["run"])
		anim = Anim.RUN
	elif _target != null and is_instance_valid(_target):
		var to := _target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist < ATTACK_RANGE:
			rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 8.0))
			anim = Anim.ATTACK
			if _attack_timer <= 0.0:
				_attack_timer = ATTACK_COOLDOWN
				_bite.call_deferred(_target_id if behavior == "hunt" else _angry_id)
		else:
			dir = to.normalized()
			speed = float(_spec["run"])
			anim = Anim.RUN
	else:
		# Passeia e come de vez em quando.
		if _goal == Vector3.INF or global_position.distance_to(_goal) < 1.2 or randf() < delta * 0.04:
			_goal = global_position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
			if randf() < 0.45:
				_rest = randf_range(3.0, 8.0)
		if _rest > 0.0:
			anim = Anim.EAT if _rest > 2.0 else Anim.IDLE
		else:
			dir = _goal - global_position
			dir.y = 0.0
			dir = dir.normalized()
			speed = float(_spec["walk"])
			anim = Anim.WALK
	if speed > 0.0 and dir.length_squared() > 0.0:
		dir = _avoid(dir, delta)
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, delta * 7.0))
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = -0.1 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

## Mordida/chifrada: sai no impacto, se o alvo ainda estiver no alcance.
func _bite(target_id: String) -> void:
	strike()
	await get_tree().create_timer(ATTACK_IMPACT).timeout
	if dead or not controlled or not is_instance_valid(_target):
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	if to.length() < ATTACK_RANGE + 0.4:
		attacked.emit(animal_id, target_id)

## Contorna árvore/parede: com a frente bloqueada, desvia para um lado por um tempo.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	_avoid_t = maxf(0.0, _avoid_t - delta)
	_avoid_check -= delta
	if _avoid_check <= 0.0:
		_avoid_check = 0.15
		var from := global_position + Vector3(0, float(_spec["height"]) * 0.5, 0)
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * (float(_spec["length"]) * 0.6 + 0.6), HitboxScript.LAYER_WORLD)
		_blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	if _blocked:
		if _avoid_t <= 0.0 and randf() < 0.2:
			_avoid_side = -_avoid_side
		_avoid_t = 0.8
	if _avoid_t > 0.0:
		return dir.rotated(Vector3.UP, _avoid_side * 1.1).normalized()
	return dir
