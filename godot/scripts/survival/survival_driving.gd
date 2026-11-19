extends Node
const PointerMode = preload("res://scripts/pointer_mode.gd")
## Carros da Sobrevivência no jogo: cria os carros do servidor, entra/sai
## (E), abastece (T, com galão), câmera de perseguição, velocímetro e
## gasolina na tela, e manda a posição do carro enquanto você dirige.
const VehicleScript = preload("res://scripts/survival/vehicle.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const GrenadeScript = preload("res://scripts/weapons/grenade.gd")
const DRIVE_RATE := 1.0 / 10.0
const REACH := 3.6

var controller: Node # SurvivalController
var main_node: Node
var player: CharacterBody3D
var vehicles: Dictionary = {} # id -> Vehicle
var driving: CharacterBody3D # carro que você está dirigindo
var _pending_enter := ""
var _drive_timer := 0.0
var _camera: Camera3D
var _orbit := 0.0
var _hud: Label
var _player_layers := 0
var _player_mask := 0

func setup(owner_controller: Node, main: Node, local_player: CharacterBody3D) -> void:
	controller = owner_controller
	main_node = main
	player = local_player

func _ready() -> void:
	name = "Driving"
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.fov = 70.0
	main_node.add_child.call_deferred(_camera)
	_hud = Label.new()
	_hud.visible = false
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_font_size_override("font_size", 20)
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.add_theme_constant_override("shadow_offset_y", 2)
	controller.get("ui").add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.offset_left = -420
	_hud.offset_right = -24
	_hud.offset_top = -130
	_hud.offset_bottom = -20

func spawn_all(list: Array) -> void:
	for data in list:
		_upsert(data)

func _upsert(data: Dictionary) -> CharacterBody3D:
	var id := str(data.get("id", ""))
	if id.is_empty():
		return null
	var v: CharacterBody3D = vehicles.get(id)
	var p = controller.call("_vec", data.get("p"))
	if v == null:
		v = VehicleScript.new()
		v.call("setup", data)
		v.set("zombies", func(): return controller.get("zombies"))
		v.connect("rammed", _on_rammed)
		v.connect("crashed", _on_crashed)
		main_node.add_child(v)
		if p != null:
			v.global_position = p
		v.rotation.y = float(data.get("yaw", 0.0))
		vehicles[id] = v
	v.set("fuel", float(data.get("fuel", v.get("fuel"))))
	v.set("driver", str(data.get("driver", "")) if data.get("driver") != null else "")
	v.call("set_condition", float(data.get("hp", v.get("hp"))), bool(data.get("broken", v.get("broken"))))
	if p != null and v != driving:
		v.call("apply_remote", p, float(data.get("yaw", v.rotation.y)), 0.0, bool(data.get("snap", false)))
	return v

func is_driving() -> bool:
	return driving != null

## Carro ao alcance do E (fora do carro).
func target_near(point: Vector3) -> Dictionary:
	if driving != null:
		return {}
	var best := {}
	var best_d := REACH
	for id in vehicles:
		var v: Node3D = vehicles[id]
		var d := Vector2(v.global_position.x - point.x, v.global_position.z - point.z).length()
		if d < best_d:
			best_d = d
			var fuel := float(v.get("fuel"))
			var has_kit := (controller.get("inv") as Dictionary).has("repair_kit")
			if bool(v.get("broken")):
				# Carcaça queimada: E conserta (com kit), não dirige.
				var label_broken := "[E] Consertar %s com kit de reparos" % v.call("display_name") if has_kit else "%s destruído — precisa de um kit de reparos" % v.call("display_name")
				best = {"type": "repair", "id": id, "label": label_broken}
				continue
			var label := "[E] Dirigir %s  •  gasolina %d%%  •  lataria %d%%" % [v.call("display_name"), int(fuel), int(float(v.get("hp")))]
			if (controller.get("inv") as Dictionary).has("gasoline") and fuel < 99.0:
				label += "   [T] Abastecer"
			elif fuel <= 0.0:
				label += "  (precisa de galão de gasolina)"
			if has_kit and float(v.get("hp")) < 100.0:
				label += "\nUse o kit de reparos no inventário para consertar"
			best = {"type": "vehicle", "id": id, "label": label}
	return best

## Carro mais perto que precisa de conserto (para o kit de reparos), ou "".
func repairable_near(point: Vector3) -> String:
	var best := ""
	var best_d := REACH
	for id in vehicles:
		var v: Node3D = vehicles[id]
		var d := Vector2(v.global_position.x - point.x, v.global_position.z - point.z).length()
		if d < best_d and (bool(v.get("broken")) or float(v.get("hp")) < 100.0):
			best_d = d
			best = str(id)
	return best

## Segura 5 s com o kit de reparos perto do carro; o servidor confere e conserta.
func request_repair(id: String) -> bool:
	if driving != null or id.is_empty():
		return false
	if not (controller.get("inv") as Dictionary).has("repair_kit"):
		controller.call("_toast", "SEM KIT DE REPAROS")
		return true
	var seconds := float(SurvivalData.item("repair_kit").get("use_time", 5))
	if player.call("start_channel", "CONSERTANDO", seconds, func(): Net.send({"t": "repair", "v": id})):
		Net.send({"t": "repair_start", "v": id})
		controller.call("_set_action", "pry", "crowbar")
	return true

func request_enter(id: String) -> void:
	_pending_enter = id
	Net.send({"t": "enter", "v": id})

func request_refuel() -> bool:
	if driving != null:
		return false
	var target := target_near(player.global_position)
	if target.is_empty():
		return false
	if not (controller.get("inv") as Dictionary).has("gasoline"):
		controller.call("_toast", "SEM GALÃO DE GASOLINA")
		return true
	var id := str(target["id"])
	player.call("start_channel", "ABASTECENDO", 2.0, func(): Net.send({"t": "refuel", "v": id}))
	return true

func on_message(data: Dictionary) -> bool:
	match str(data.get("t", "")):
		"veh":
			var v := _upsert(data)
			var me := str(controller.get("my_id"))
			if v == null:
				return true
			if str(data.get("driver", "")) == me and driving == null and str(data.get("id")) == _pending_enter:
				_start_driving(v)
			elif driving == v and str(data.get("driver", "")) != me:
				_stop_driving(false)
			elif driving == v and bool(data.get("snap", false)):
				v.call("apply_remote", controller.call("_vec", data.get("p")), float(data.get("yaw", 0.0)), 0.0, true)
			return true
		"vs":
			var v: CharacterBody3D = vehicles.get(str(data.get("id", "")))
			var p = controller.call("_vec", data.get("p"))
			if v != null and v != driving and p != null:
				v.call("apply_remote", p, float(data.get("y", 0.0)), float(data.get("s", 0.0)))
			return true
		"fuel":
			var v: CharacterBody3D = vehicles.get(str(data.get("v", "")))
			if v != null:
				v.set("fuel", float(data.get("fuel", 0.0)))
			return true
		"boom":
			# Carro explodiu: fogo, fumaça e estrondo (o dano vem do servidor).
			var at = controller.call("_vec", data.get("p"))
			var v: CharacterBody3D = vehicles.get(str(data.get("id", "")))
			if v != null:
				at = v.global_position
			if at != null:
				GrenadeScript.spawn_explosion(main_node, at + Vector3(0, 0.8, 0))
				if player.global_position.distance_to(at) < 30.0:
					player.call("add_hit_shake", 1.0)
			if v != null and v == driving:
				_stop_driving(false)
			return true
	return false

## Batida forte: avisa o servidor (ele decide o dano; encostão não conta).
func _on_crashed(impact: float) -> void:
	if driving == null:
		return
	Net.send({"t": "crash", "v": driving.get("vehicle_id"), "i": impact})
	player.call("add_hit_shake", clampf(impact / 15.0, 0.3, 1.0))
	player.get("sound_fx").call("hurt", impact * 2.0)

func _start_driving(v: CharacterBody3D) -> void:
	_pending_enter = ""
	driving = v
	v.call("set_controlled", true)
	_player_layers = player.collision_layer
	_player_mask = player.collision_mask
	player.collision_layer = 0
	player.collision_mask = 0
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	_orbit = 0.0
	_camera.global_position = v.global_position + v.global_basis.z * 7.0 + Vector3(0, 3, 0)
	_camera.current = true
	PointerMode.capture()
	if float(v.get("fuel")) <= 0.0:
		controller.call("_toast", "TANQUE VAZIO — abasteça com um galão (T fora do carro)")

## Sai do carro e põe o jogador ao lado da porta do motorista (ou do outro lado).
func _stop_driving(tell_server: bool = true) -> void:
	if driving == null:
		return
	var v := driving
	driving = null
	# Sem motorista já aqui: senão, até a resposta do servidor chegar, o carro
	# via "ainda tem motorista" e religava o motor (que ficava roncando).
	v.set("driver", "")
	v.call("set_controlled", false)
	if tell_server:
		Net.send({"t": "exit"})
	var side := v.global_basis.x
	var spot := v.global_position - side * 1.6
	if _blocked(spot):
		spot = v.global_position + side * 1.6
	player.global_position = spot + Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	player.set("yaw", v.rotation.y)
	player.collision_layer = _player_layers
	player.collision_mask = _player_mask
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = not bool(controller.get("local_dead"))
	(player.get("camera") as Camera3D).current = true
	_hud.visible = false

func _blocked(point: Vector3) -> bool:
	var space := player.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = HitboxScript.LAYER_WORLD
	q.transform = Transform3D(Basis.IDENTITY, point + Vector3(0, 1.0, 0))
	return not space.intersect_shape(q, 1).is_empty()

## Morreu ou caiu a conexão dentro do carro.
func force_exit() -> void:
	_stop_driving(false)

func _on_rammed(zombie_id: String, speed: float) -> void:
	Net.send({"t": "ram", "z": zombie_id})
	var z = (controller.get("zombies") as Dictionary).get(zombie_id)
	if z != null:
		z.set("_flinch", 1.0)
	player.get("sound_fx").call("melee_impact", false)

func handle_input(event: InputEvent) -> bool:
	if driving == null:
		return false
	if (event is InputEventKey or event is InputEventMouseButton or event is InputEventAction) and event.is_pressed() and not event.is_echo() and InputMap.has_action("interact") and event.is_action("interact"):
		if absf(float(driving.get("speed"))) > 4.0:
			controller.call("_toast", "DIMINUA A VELOCIDADE PARA SAIR")
		else:
			_stop_driving(true)
		return true
	if event is InputEventMouseMotion and PointerMode.is_captured():
		orbit_camera(event.relative.x)
		return true
	return false

## Gira a câmera em volta do carro (mouse ou dedo arrastando na tela).
func orbit_camera(dx: float) -> void:
	_orbit = clampf(_orbit - dx * 0.004, -PI, PI)

func _physics_process(delta: float) -> void:
	if driving == null:
		return
	# O jogador "viaja" no banco do motorista (zumbis miram nele, servidor sabe onde está).
	player.global_position = driving.global_position + Vector3(0, 0.2, 0)
	_drive_timer -= delta
	if _drive_timer <= 0.0:
		_drive_timer = DRIVE_RATE
		var p := driving.global_position
		Net.send({"t": "drive", "v": driving.get("vehicle_id"), "p": [p.x, p.y, p.z], "y": driving.rotation.y, "s": driving.get("speed")})

func _process(delta: float) -> void:
	if driving == null:
		return
	# Câmera atrás do carro; o mouse gira em volta e ela volta sozinha para trás.
	# Segue o carro *desenhado* (interpolado entre passos de física), não o corpo
	# físico: senão a câmera anda liso e o carro aos saltos = trepidação.
	var speed := absf(float(driving.get("speed")))
	_orbit = move_toward(_orbit, 0.0, delta * 0.6) if speed > 3.0 else _orbit
	var xf: Transform3D = driving.call("visual_transform")
	var flat_back := xf.basis.z
	flat_back.y = 0.0
	flat_back = flat_back.normalized() if flat_back.length_squared() > 0.0001 else Vector3.BACK
	var back := flat_back.rotated(Vector3.UP, _orbit)
	var speed_k := clampf(speed / float(driving.call("max_speed")), 0.0, 1.0)
	var wanted := xf.origin + back * (7.2 + speed_k * 0.8) + Vector3(0, 2.8 - speed_k * 0.3, 0)
	# Suavização independente do FPS (mesma sensação a 60 ou 144 Hz).
	_camera.global_position = _camera.global_position.lerp(wanted, 1.0 - exp(-8.0 * delta))
	_camera.look_at(xf.origin + Vector3(0, 1.1, 0))
	# Sensação de velocidade: o campo de visão abre um pouco em alta.
	_camera.fov = lerpf(_camera.fov, 70.0 + speed_k * 8.0, 1.0 - exp(-3.0 * delta))
	var kmh := speed * 3.6
	var fuel := float(driving.get("fuel"))
	_hud.visible = true
	var body := float(driving.get("hp"))
	_hud.text = "%s\n%d km/h\nGasolina %d%%%s\nLataria %d%%%s\n[E] sair   [Espaço] freio de mão" % [driving.call("display_name"), int(kmh), int(fuel), "  — VAZIO" if fuel <= 0.0 else "", int(body), "  — VAI EXPLODIR!" if body < 25.0 else ""]
	_hud.add_theme_color_override("font_color", Color("#ff8a7a") if fuel < 10.0 or body < 25.0 else Color.WHITE)
