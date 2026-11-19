extends Node3D
## Treino offline: arena pequena (6,6 x 6,6 m, cercada) no canto sudeste do campo de
## treino (training_ground.gd) com um zumbi preso
## dentro e um suporte com o bastão longo na entrada.
## E perto do suporte pega/larga o bastão. Com o bastão na mão a arma de fogo
## fica guardada e o clique esquerdo (ou Q) faz o golpe lateral (dano 34,
## alcance 3,2 m); sem ele, Q é soco (dano 12, alcance 2,4 m). Sacar uma arma
## (1-5 ou H) larga o bastão, que volta para o suporte.
## Mesmas regras da Sobrevivência: golpe pela mira (scripts/melee.gd),
## ×1,5 na cabeça, o zumbi recua ao levar golpe de perto e fica parado um
## instante depois de cada bote (a brecha). O zumbi só caça quem está na arena
## e volta 4 s depois de morrer. Mordidas não tiram vida no treino: são contadas.
const ZombieScript = preload("res://scripts/survival/zombie.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const Melee = preload("res://scripts/melee.gd")
const StaffModel = preload("res://scripts/weapons/staff_model.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const TrainingGround = preload("res://scripts/training_ground.gd")
# Canto sudeste do campo de treino, ao sul da área de cobertura.
# tests/training_arena.gd confere que o espaço está livre.
const CENTER := Vector3(30, 0, 32)
const HALF := 3.3 # arena de 6,6 x 6,6 m
const DOOR := 1.1 # meia largura da entrada (lado norte)
const WALL_H := 1.1
const RACK := CENTER + Vector3(2.1, 0, -2.1) # suporte do bastão, logo depois da entrada
const PICK_REACH := 2.0
const STAFF := "long_bat"
const FIST_DAMAGE := 12.0 # src/godot-survival.js FIST_DAMAGE
const FIST_REACH := 2.4 # survival_controller: soco sem arma branca
const MELEE_COOLDOWN := 0.6
const SWING_TIME := 0.55
const ZOMBIE_HP := 60.0
const RESPAWN := 4.0

var player: CharacterBody3D
var zombie: CharacterBody3D
var holding := false
var hits := 0
var bites := 0
var kills := 0
var _cooldown := 0.0
var _swing_left := 0.0
var _respawn_left := 0.0
var _rack_staff: Node3D
var board: Label3D
var _serial := 0

func setup(p: CharacterBody3D) -> void:
	player = p

func _ready() -> void:
	name = "TrainingArena"
	_build_walls()
	_build_rack()
	board = Label3D.new()
	board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	board.font_size = 34
	board.outline_size = 9
	board.pixel_size = 0.004
	board.modulate = Color("#ffe08a")
	board.position = CENTER + Vector3(0, 3.2, -HALF)
	add_child(board)
	_spawn_zombie()
	if player != null:
		player.set("melee_handler", _melee)
		player.set("interact_handler", _interact)

func _block(center: Vector3, size: Vector3, texture: String) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = TrainingGround.material(texture)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	add_child(body)

## Muro baixo nos quatro lados; o lado norte (-Z, para a praça) tem a entrada.
func _build_walls() -> void:
	var t := 0.25
	var y := WALL_H * 0.5
	var wall := "red_grid"
	_block(CENTER + Vector3(0, y, HALF), Vector3(HALF * 2 + t, WALL_H, t), wall)
	_block(CENTER + Vector3(-HALF, y, 0), Vector3(t, WALL_H, HALF * 2 + t), wall)
	_block(CENTER + Vector3(HALF, y, 0), Vector3(t, WALL_H, HALF * 2 + t), wall)
	var side := HALF - DOOR
	for sign in [-1.0, 1.0]:
		_block(CENTER + Vector3(sign * (DOOR + side * 0.5), y, -HALF), Vector3(side + t * 0.5, WALL_H, t), wall)
	# A entrada fica aberta para o jogador; o zumbi é mantido dentro em _process.
	# Piso marcado (só visual) para destacar a arena.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF * 2, HALF * 2)
	floor_mesh.mesh = plane
	floor_mesh.position = CENTER + Vector3(0, 0.02, 0)
	floor_mesh.material_override = TrainingGround.material("light_marks")
	add_child(floor_mesh)

## Suporte com o bastão em pé.
func _build_rack() -> void:
	_block(RACK + Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.3), "orange_grid")
	# Em pé no suporte, ponta com pregos para cima.
	_rack_staff = StaffModel.build()
	_rack_staff.position = RACK + Vector3(0, 0.62, 0)
	_rack_staff.rotation.z = 0.12
	add_child(_rack_staff)
	var tag := Label3D.new()
	tag.text = "BASTÃO LONGO\n[E] pegar / largar"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 28
	tag.outline_size = 8
	tag.pixel_size = 0.004
	tag.position = RACK + Vector3(0, 2.0, 0)
	add_child(tag)

func _spawn_zombie() -> void:
	_serial += 1
	zombie = ZombieScript.new()
	zombie.call("setup", "arena_%d" % _serial, "walker", ZOMBIE_HP)
	zombie.position = CENTER + Vector3(0, 0.05, HALF - 1.2)
	zombie.rotation.y = 0.0 # olha para a entrada (-Z)
	zombie.set("targets", _targets)
	zombie.connect("attacked", _on_bite)
	add_child(zombie)
	zombie.call("set_controlled", true)
	_update_board()

## O zumbi só enxerga quem está dentro da arena (não sai caçando pela cidade).
func _targets() -> Array:
	if player == null or not inside(player.global_position):
		return []
	return [{"id": "player", "node": player}]

func inside(p: Vector3) -> bool:
	return absf(p.x - CENTER.x) < HALF and absf(p.z - CENTER.z) < HALF

func _on_bite(_zid: String, _tid: String) -> void:
	bites += 1
	var fx = player.get("sound_fx")
	if fx != null:
		fx.call("zombie_bite", 10.0)
	_update_board()

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_sync_holding()
	# O zumbi não sai pela entrada: fica preso dentro do muro.
	if is_instance_valid(zombie) and not bool(zombie.get("dead")):
		var limit := HALF - 0.45
		var p := zombie.global_position
		var clamped := Vector3(clampf(p.x, CENTER.x - limit, CENTER.x + limit), p.y, clampf(p.z, CENTER.z - limit, CENTER.z + limit))
		if not clamped.is_equal_approx(p):
			zombie.global_position = clamped
	if _swing_left > 0.0:
		_swing_left -= delta
		if _swing_left <= 0.0:
			# Depois do golpe volta a carregar o bastão no ombro (ou mãos livres).
			_set_action("hold" if holding else "", STAFF if holding else "")
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			if is_instance_valid(zombie):
				zombie.queue_free()
			_spawn_zombie()

## O bastão está na mão do jogador? (player.melee_weapon; sacar arma larga.)
func _sync_holding() -> void:
	var now := player != null and str(player.get("melee_weapon")) == STAFF
	if now == holding:
		return
	holding = now
	_rack_staff.visible = not holding
	if _swing_left <= 0.0:
		_set_action("hold" if holding else "", STAFF if holding else "")
	_update_board()

## E: pega ou larga o bastão perto do suporte. Devolve true se tratou a tecla.
func _interact() -> bool:
	if player == null or _flat(player.global_position, RACK) > PICK_REACH:
		return false
	if player.get("melee_weapon") == STAFF:
		player.set("melee_weapon", "")
	else:
		# Guarda a arma de fogo antes: o clique esquerdo passa a golpear com o bastão.
		if not bool(player.get("weapon_holstered")):
			player.call("_toggle_weapon_holster")
		player.set("melee_weapon", STAFF)
	_sync_holding()
	_update_board()
	return true

## Q: golpe com o bastão (se pegou) ou soco, como na Sobrevivência.
func _melee() -> void:
	if _cooldown > 0.0 or player == null:
		return
	_cooldown = MELEE_COOLDOWN
	var weapon := STAFF if holding else ""
	var entry := SurvivalData.item(weapon)
	var reach := float(entry.get("reach", 2.4)) if holding else FIST_REACH
	var damage := float(entry.get("melee", FIST_DAMAGE)) if holding else FIST_DAMAGE
	if holding:
		# O Q já começou o clipe de soco (player.gd); com o bastão vale o golpe lateral.
		var avatar = player.get("humanoid_avatar")
		if avatar != null and avatar.get("current_clip") in ["punch", "elbow_punch"]:
			avatar.set("current_clip", "")
		_set_action("", "")
		_set_action("swing", STAFF)
		# O corpo vira para a mira durante o golpe (andando, ele olha para onde vai).
		if player.has_method("face_aim"):
			player.call("face_aim", SWING_TIME + 0.15)
		_swing_left = SWING_TIME
	var fx = player.get("sound_fx")
	if fx != null:
		fx.call("melee_swing")
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_basis.z
	var hit := Melee.ray(player, camera, reach)
	if hit.is_empty():
		return
	var from := camera.global_position
	var body: Object = hit["collider"]
	var target = body.get("actor") if body != null else null
	if target == null:
		return
	var zone := str(body.get("zone")) if body.get("zone") != null else "chest"
	if body.has_method("resolve_ray"):
		zone = str((body.call("resolve_ray", from, forward) as Dictionary).get("zone", "chest"))
	var amount := damage * (1.5 if zone == "head" else 1.0)
	var what := "BASTÃO LONGO" if holding else "SOCO"
	if target == zombie:
		_hit_zombie(amount, zone, hit["position"], hit["normal"])
	elif target.get_parent() != null and target.get_parent().has_method("melee_hit"):
		target.get_parent().call("melee_hit", amount, what, zone, hit["position"], hit["normal"])
	else:
		return
	if fx != null:
		fx.call("melee_impact", zone == "head")

func _hit_zombie(amount: float, zone: String, point: Vector3, normal: Vector3) -> void:
	if bool(zombie.get("dead")):
		return
	hits += 1
	zombie.call("receive_hit", zone, amount, point, normal, STAFF if holding else "fist")
	zombie.set("hp", maxf(0.0, float(zombie.get("hp")) - amount))
	_damage_number(point + normal * 0.05, amount, zone == "head")
	if float(zombie.get("hp")) <= 0.0:
		kills += 1
		zombie.call("die")
		_respawn_left = RESPAWN
	else:
		zombie.call("stagger", player.global_position)
	_update_board()

func _set_action(act: String, tool: String) -> void:
	var avatar = player.get("humanoid_avatar")
	if avatar != null and avatar.has_method("set_action"):
		avatar.call("set_action", act, tool)

func _damage_number(point: Vector3, damage: float, headshot: bool) -> void:
	var label := Label3D.new()
	label.text = ("%d" % roundi(damage)) + ("!" if headshot else "")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 64 if headshot else 46
	label.outline_size = 12
	label.modulate = Color("#ff4d3d") if headshot else Color("#ffe08a")
	add_child(label)
	label.global_position = point + Vector3(0, 0.2, 0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.7, 0), 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tween.chain().tween_callback(label.queue_free)

func _update_board() -> void:
	if board == null:
		return
	var hp := 0.0 if zombie == null or bool(zombie.get("dead")) else float(zombie.get("hp"))
	board.text = "ARENA DO ZUMBI\n%s  •  [Q] golpear\nzumbi: %d/%d de vida   acertos: %d   mordidas: %d   abates: %d" % [
		"COM BASTÃO: clique esquerdo golpeia (dano 34, alcance 3,2 m)" if holding else "SOCO (dano 12)  •  pegue o bastão no suporte [E]",
		roundi(hp), roundi(ZOMBIE_HP), hits, bites, kills]

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
