extends CharacterBody3D
## Carro que funciona (Sobrevivência). Física arcade simples: acelera, freia,
## dá ré, esterça pela velocidade e bate nas paredes. Quem dirige é o jogo do
## motorista (`controlled`); os outros só seguem a posição que o servidor repassa.
## Sem gasolina o motor não liga. Atropelar zumbis: `rammed` avisa o controlador.
signal rammed(zombie_id: String, speed: float)
## Batida forte (só o motorista): `impact` = velocidade perdida no choque, em m/s.
signal crashed(impact: float)

const CarModel = preload("res://scripts/survival/car_model.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const VehicleAudio = preload("res://scripts/audio/vehicle_audio.gd")
const GRAVITY := 22.0
const MAX_STEER := 0.55
const REVERSE_SPEED := 6.0
const BRAKE := 14.0
const HANDBRAKE := 20.0
const DRAG := 2.2

var vehicle_id := ""
var kind := "sedan"
var color_hex := "#8c1d18"
var fuel := 0.0
var driver := ""
var controlled := false
var hp := 100.0 # lataria (servidor)
var broken := false # explodiu: carcaça queimada até alguém usar um kit de reparos
var _smoke: CPUParticles3D
var _burnt_mat: StandardMaterial3D
## Devolve os zumbis (id -> nó) para checar atropelamento.
var zombies: Callable

var speed := 0.0 # m/s, positivo para a frente (-Z)
var steer := 0.0
var engine_on := false
var _spec: Dictionary = {}
var _model: Node3D
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _spin := 0.0
var _remote_pos := Vector3.ZERO
var _remote_yaw := 0.0
var _remote_speed := 0.0
var _rammed: Dictionary = {}
var _audio: Node3D # VehicleAudio: motor, pneus, partida
var throttle_input := 0.0 # quanto o motorista pisa (0..1), para o ronco
var skidding := false
# Interpolação visual: o corpo anda no passo da física (60 Hz) e o modelo é
# desenhado entre os dois últimos passos, para não trepidar em telas de 75/144 Hz.
var _prev_xf := Transform3D.IDENTITY
var _curr_xf := Transform3D.IDENTITY
var _model_local := Transform3D.IDENTITY

func setup(data: Dictionary) -> void:
	vehicle_id = str(data.get("id", ""))
	kind = str(data.get("kind", "sedan"))
	color_hex = str(data.get("color", "#8c1d18"))
	fuel = float(data.get("fuel", 0.0))
	driver = str(data.get("driver", "")) if data.get("driver") != null else ""
	hp = float(data.get("hp", 100.0))
	broken = bool(data.get("broken", false))
	name = "Vehicle_" + vehicle_id

## Lataria do servidor: fumaça quando muito batido; quebrado = carcaça preta, sem motor.
func set_condition(new_hp: float, new_broken: bool) -> void:
	hp = new_hp
	var was_broken := broken
	broken = new_broken
	if _model == null:
		return
	if broken != was_broken or broken:
		_apply_burnt(broken)
	if _smoke != null:
		_smoke.emitting = broken or hp < 35.0
		_smoke.color = Color(0.08, 0.08, 0.08, 0.7) if broken else Color(0.45, 0.45, 0.45, 0.5)
	if broken and engine_on:
		set_engine(false)

func _apply_burnt(on: bool) -> void:
	if _burnt_mat == null:
		_burnt_mat = StandardMaterial3D.new()
		_burnt_mat.albedo_color = Color("#1b1714")
		_burnt_mat.roughness = 1.0
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = _burnt_mat if on else null

func display_name() -> String:
	return str(SurvivalData.catalog().get("vehicles", {}).get(kind, {}).get("name", "Carro"))

func _ready() -> void:
	_spec = SurvivalData.catalog().get("vehicles", {}).get(kind, {"max_speed": 24, "accel": 7})
	collision_layer = HitboxScript.LAYER_WORLD # dá cobertura e bloqueia quem anda
	collision_mask = HitboxScript.LAYER_WORLD
	floor_snap_length = 0.6
	_model = CarModel.build(kind, color_hex, false, int(vehicle_id.substr(1)))
	add_child(_model)
	for child in _model.get_children():
		if str(child.name).begins_with("Wheel_"):
			_wheels.append(child)
			if str(child.name).begins_with("Wheel_F"):
				_front_wheels.append(child)
	var size := CarModel.size_of(kind)
	# Corpo (acima das rodas) + duas esferas embaixo que deslizam sobre meio-fios.
	var body := BoxShape3D.new()
	body.size = Vector3(size.x, size.y - 0.45, size.z)
	var body_col := CollisionShape3D.new()
	body_col.shape = body
	body_col.position.y = 0.45 + body.size.y * 0.5
	add_child(body_col)
	for z in [-size.z * 0.3, size.z * 0.3]:
		var ball := SphereShape3D.new()
		ball.radius = 0.42
		var col := CollisionShape3D.new()
		col.shape = ball
		col.position = Vector3(0, 0.42, z)
		add_child(col)
	_audio = VehicleAudio.new()
	_audio.set("vehicle", self)
	add_child(_audio)
	_model_local = _model.transform
	_model.top_level = true # desenhado pela interpolação em _process
	reset_visual()
	_remote_pos = global_position
	_remote_yaw = rotation.y
	# Fumaça do capô (carro muito batido ou queimado).
	_smoke = CPUParticles3D.new()
	_smoke.amount = 18
	_smoke.lifetime = 2.2
	_smoke.emitting = false
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.4
	_smoke.scale_amount_min = 0.5
	_smoke.scale_amount_max = 1.1
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.vertex_color_use_as_albedo = true
	puff.material = puff_mat
	_smoke.mesh = puff
	_smoke.position = Vector3(0, CarModel.size_of(kind).y, -CarModel.size_of(kind).z * 0.32)
	add_child(_smoke)
	set_condition(hp, broken)

## Começa a interpolação do zero (nasceu, teleportou, correção do servidor).
func reset_visual() -> void:
	_curr_xf = global_transform
	_prev_xf = _curr_xf
	if _model != null:
		_model.global_transform = _curr_xf * _model_local

## Onde o carro aparece na tela neste quadro (entre dois passos de física).
## A câmera de perseguição segue isto, não a posição crua do corpo.
func visual_transform() -> Transform3D:
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return _prev_xf.interpolate_with(_curr_xf, f)

func _process(_delta: float) -> void:
	if _model != null:
		_model.global_transform = visual_transform() * _model_local

func set_engine(on: bool) -> void:
	var was_on := engine_on
	engine_on = on
	var body := _model.get_node_or_null("Body") as MeshInstance3D
	if body != null:
		for i in body.mesh.get_surface_count():
			var surface: String = body.mesh.surface_get_name(i)
			if surface == "headlight":
				body.set_surface_override_material(i, CarModel.headlight_material(on))
			elif surface == "taillight":
				body.set_surface_override_material(i, CarModel.taillight_material(on))
	if _audio != null and on != was_on:
		_audio.call("set_running", on)

## Posição vinda do servidor (outros motoristas, ou correção do nosso).
func apply_remote(p: Vector3, yaw: float, remote_speed: float, snap: bool = false) -> void:
	_remote_pos = p
	_remote_yaw = yaw
	_remote_speed = remote_speed
	if snap or controlled:
		global_position = p
		rotation.y = yaw
		reset_visual()
		if controlled:
			speed = 0.0

func set_controlled(value: bool) -> void:
	controlled = value
	speed = 0.0
	set_engine(value and fuel > 0.0 and not broken)

func _physics_process(delta: float) -> void:
	if controlled:
		_drive(delta)
	else:
		var blend := minf(1.0, delta * 8.0)
		global_position = global_position.lerp(_remote_pos, blend)
		rotation.y = lerp_angle(rotation.y, _remote_yaw, blend)
		speed = lerpf(speed, _remote_speed, blend)
		var running := not driver.is_empty() and fuel > 0.0 and not broken
		if engine_on != running:
			set_engine(running)
	_spin += speed * delta / 0.34
	for wheel in _wheels:
		wheel.rotation.x = -_spin
	for wheel in _front_wheels:
		wheel.rotation.y = steer
	# Guarda os dois últimos passos para o desenho interpolado; salto grande = teleporte.
	_prev_xf = _curr_xf
	_curr_xf = global_transform
	if _prev_xf.origin.distance_squared_to(_curr_xf.origin) > 36.0:
		_prev_xf = _curr_xf

func max_speed() -> float:
	return float(_spec.get("max_speed", 24))

func _drive(delta: float) -> void:
	var max_speed := float(_spec.get("max_speed", 24))
	var accel := float(_spec.get("accel", 7))
	var throttle := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var turn := Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var handbrake := Input.is_action_pressed("jump")
	if fuel <= 0.0 or broken:
		throttle = 0.0
		if engine_on:
			set_engine(false)
	if throttle > 0.0:
		speed = move_toward(speed, max_speed, (accel if speed >= 0.0 else BRAKE) * throttle * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, -REVERSE_SPEED, (BRAKE if speed > 0.0 else accel * 0.6) * -throttle * delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, HANDBRAKE * delta)
	throttle_input = absf(throttle)
	# Pneu cantando: freio de mão ou curva fechada rápida.
	skidding = absf(speed) > 6.0 and (handbrake or (absf(turn) > 0.5 and absf(speed) > max_speed * 0.7))
	# Menos esterço em alta velocidade.
	var steer_limit := MAX_STEER * (1.0 - clampf(absf(speed) / max_speed, 0.0, 1.0) * 0.55)
	steer = move_toward(steer, turn * steer_limit, delta * 2.5)
	# Curva pelas rodas da frente (modelo de bicicleta): as dianteiras apontam
	# para onde o carro vai e o eixo traseiro segue sem escorregar de lado; o
	# carro gira em torno do eixo traseiro, não do centro. Assim o centro (meio
	# entre-eixos à frente do eixo traseiro) também desliza para dentro da curva.
	var wheelbase := float(CarModel.KINDS.get(kind, CarModel.KINDS["sedan"])["wb"])
	var yaw_rate := speed / wheelbase * tan(steer)
	rotation.y += yaw_rate * delta
	var forward := -global_basis.z
	var left := -global_basis.x
	var center_velocity := forward * speed + left * (wheelbase * 0.5) * yaw_rate
	velocity.x = center_velocity.x
	velocity.z = center_velocity.z
	velocity.y = velocity.y - GRAVITY * delta if not is_on_floor() else -0.5
	move_and_slide()
	# Bateu: a velocidade cai para o que de fato andou.
	var real := get_real_velocity()
	var along := real.dot(forward)
	if absf(along) < absf(speed) - 0.5:
		# Só conta batida em parede/obstáculo (não o chão), e o servidor ignora encostões.
		var lost := absf(speed) - absf(along)
		if lost > 4.5 and _hit_wall():
			crashed.emit(lost)
			if _audio != null:
				_audio.call("crash", lost)
		speed = along
	_check_ram()

func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		if absf(get_slide_collision(i).get_normal().y) < 0.6:
			return true
	return false

func _check_ram() -> void:
	if absf(speed) < 6.0 or not zombies.is_valid():
		return
	var now := Time.get_ticks_msec()
	var forward := -global_basis.z * signf(speed)
	var size := CarModel.size_of(kind)
	var list: Dictionary = zombies.call()
	for id in list:
		var z: Node3D = list[id]
		if not is_instance_valid(z) or bool(z.get("dead")):
			continue
		var offset := z.global_position - global_position
		offset.y = 0.0
		var ahead := offset.dot(forward)
		var side := absf(offset.dot(global_basis.x))
		if ahead > 0.0 and ahead < size.z * 0.5 + 0.9 and side < size.x * 0.5 + 0.3:
			if now - int(_rammed.get(id, 0)) > 600:
				_rammed[id] = now
				rammed.emit(str(id), absf(speed))
