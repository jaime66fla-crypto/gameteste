extends Node
## Fishing presentation only; the server validates timing, equipment and rewards.
const Data = preload("res://scripts/survival/survival_data.gd")
var line: MeshInstance3D
var previous_holstered := true
var previous_bow := false
var ctl: Node
var active := false
var pending := false
var elapsed := 0.0
var wait_seconds := 0.0
var window_seconds := 1.8
var origin := Vector3.ZERO
var bobber: MeshInstance3D
var cast_point := Vector3.ZERO

func setup(controller: Node) -> void:
	ctl = controller

func target() -> Dictionary:
	if active or pending or int(ctl.inv.get("fishing_rod", 0)) <= 0 or ctl.ui_open() or ctl.is_building():
		return {}
	var me: Vector3 = ctl.player.global_position
	# Probe the facing shore first, then nearby water around the player.
	var yaw := float(ctl.player.get("yaw"))
	for distance in [3.0, 4.5, 1.5]:
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2, PI]:
			var spot: Vector3 = me + Vector3(-sin(yaw + turn), 0, -cos(yaw + turn)) * distance
			var water: Dictionary = ctl.world.call("water_at", spot)
			if not water.is_empty():
				spot.y = float(water.get("surface", 0.0)) + 0.06
				return {"type": "fish", "id": "water", "pos": spot, "label": "[E] Pescar com vara • [Shift+E] Beber água doce" if bool(ctl.world.call("water_at", me).get("fresh", false)) else "[E] Pescar com vara"}
	return {}

func start(spot: Vector3) -> void:
	if active or pending:
		return
	pending = true
	elapsed = 0.0
	Net.send({"t": "fish_start", "p": [spot.x, spot.y, spot.z]})

func on_message(data: Dictionary) -> bool:
	if str(data.get("t", "")) != "fishing":
		return false
	pending = false
	_clear()
	if bool(data.get("active", false)):
		active = true
		elapsed = 0.0
		wait_seconds = float(data.get("wait_ms", 6000)) / 1000.0
		window_seconds = float(data.get("window_ms", 1800)) / 1000.0
		origin = ctl.player.global_position
		var p: Array = data.get("p", [origin.x, origin.y, origin.z])
		cast_point = Vector3(float(p[0]), float(p[1]) + 0.06, float(p[2]))
		previous_holstered = bool(ctl.player.get("weapon_holstered"))
		var toward := cast_point - origin
		var facing := atan2(-toward.x, -toward.z)
		ctl.player.set("_body_yaw", facing)
		var body: Node3D = ctl.player.get("avatar")
		if is_instance_valid(body):
			body.rotation.y = wrapf(facing - float(ctl.player.get("yaw")), -PI, PI)
		ctl.player.set("fishing_active", true)
		ctl.player.call("cancel_grenade_aim")
		previous_bow = bool(ctl.player.call("has_bow"))
		if previous_bow:
			ctl.player.get("bow_controller").call("unequip")
		ctl.player.set("aiming", false)
		ctl.player.set("weapon_holstered", true)
		ctl.call("_set_action", "fish", "fishing_rod")
		bobber = MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.07
		mesh.height = 0.14
		bobber.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.ORANGE_RED
		bobber.material_override = material
		ctl.main_node.add_child(bobber)
		bobber.global_position = cast_point
		line = MeshInstance3D.new()
		var line_material := StandardMaterial3D.new()
		line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_material.albedo_color = Color(0.8, 0.85, 0.8, 0.8)
		line.material_override = line_material
		ctl.main_node.add_child(line)
	elif not str(data.get("item", "")).is_empty():
		ctl.call("_toast", "PESCOU: " + str(data.get("count", 1)) + " × " + Data.item_name(str(data.item)))
	return true

func hint() -> String:
	return "MORDEU! Botão direito para fisgar • Esc cancela" if elapsed >= wait_seconds else "Pescando… aguarde a mordida • Esc cancela"

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Net.send({"t": "fish_hook"})
			_clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire") or event.is_action_pressed("interact") or event.is_action_pressed("grenade"):
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	elapsed += delta
	if pending and elapsed > 4.0:
		pending = false
	if not active:
		return
	if ctl.local_dead or ctl.is_driving() or ctl.ui_open() or ctl.player.global_position.distance_to(origin) > 0.35 or Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1 or elapsed > wait_seconds + window_seconds:
		cancel()
		return
	if is_instance_valid(bobber):
		var thread := ImmediateMesh.new()
		thread.surface_begin(Mesh.PRIMITIVE_LINES)
		var from: Vector3 = ctl.player.global_position + Vector3(0, 1.7, 0)
		var avatar: Node3D = ctl.player.get("humanoid_avatar")
		if is_instance_valid(avatar):
			var rod: Node3D = avatar.get("_tool_node")
			if is_instance_valid(rod):
				from = rod.to_global(Vector3(0, 2.1, 0))
		thread.surface_add_vertex(from)
		thread.surface_add_vertex(bobber.global_position)
		thread.surface_end()
		line.mesh = thread
		bobber.global_position.y = cast_point.y + sin(elapsed * (18.0 if elapsed >= wait_seconds else 3.0)) * (0.09 if elapsed >= wait_seconds else 0.02)

func cancel() -> void:
	Net.send({"t": "fish_cancel"})
	_clear()

func _clear() -> void:
	if active:
		ctl.player.set("weapon_holstered", previous_holstered)
		if previous_bow:
			ctl.player.get("bow_controller").call("equip")
		Input.action_release("aim")
		Input.action_release("fire")
	active = false
	ctl.player.set("fishing_active", false)
	if str(ctl.get("action")) == "fish":
		ctl.call("_set_action", "", "")
	if is_instance_valid(line):
		line.queue_free()
	if is_instance_valid(bobber):
		bobber.queue_free()

func _exit_tree() -> void:
	if is_instance_valid(bobber):
		bobber.queue_free()

