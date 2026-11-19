extends SceneTree
## Escalada de bordas altas (player.gd find_climb_ledge / start_climb):
## espaço de frente para um muro de 2,2 m sobe nele com o clipe ClimbUp_1m;
## segurar a direção no ar contra o muro também sobe; muro de 1 m é pulo normal
## (sem escalada) e muro de 3,2 m está fora do alcance.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body

## Põe o jogador em `spot` olhando para -Z e espera assentar.
func _place(player: CharacterBody3D, spot: Vector3) -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")
	player.velocity = Vector3.ZERO
	player.global_position = spot
	player.set("yaw", 0.0)
	player.set("_body_yaw", 0.0)
	await _frames(20)

func _tap_jump() -> void:
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")

## Espera a escalada acabar; devolve se ela começou.
func _wait_climb(player: CharacterBody3D, frames: int) -> bool:
	var started := false
	for frame in range(frames):
		await _frames(1)
		if bool(player.get("climbing")):
			started = true
		elif started:
			break
	return started

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	var o := Vector3(600, 40, 600)
	var nodes: Array[Node] = []
	nodes.append(_solid(scene, o + Vector3(0, -0.5, 0), Vector3(40, 1, 40))) # chão em y = o.y
	nodes.append(_solid(scene, o + Vector3(0, 1.1, -3.0), Vector3(4, 2.2, 2))) # muro 2,2 m, face em z = -2
	nodes.append(_solid(scene, o + Vector3(8, 0.5, -3.0), Vector3(4, 1.0, 2))) # mureta 1 m
	nodes.append(_solid(scene, o + Vector3(-8, 1.6, -3.0), Vector3(4, 3.2, 2))) # muro 3,2 m
	nodes.append(_solid(scene, o + Vector3(16, 1.1, -3.0), Vector3(4, 2.2, 2))) # muro 2,2 m (no ar)
	await _frames(10)

	# 1) No chão, encostado, de frente: espaço sobe no muro de 2,2 m.
	await _place(player, o + Vector3(0, 0.05, -1.4))
	_check(player.is_on_floor(), "Player did not settle in front of the wall")
	var ledge: Dictionary = player.call("find_climb_ledge", Vector3.FORWARD, 1.25, 2.5)
	_check(not ledge.is_empty(), "2.2 m wall: no ledge found")
	if not ledge.is_empty():
		_check(absf(float(ledge["rise"]) - 2.2) < 0.05, "2.2 m wall: wrong height %.2f" % float(ledge["rise"]))
	await _tap_jump()
	var avatar = player.get("humanoid_avatar")
	await _frames(3)
	if avatar != null and avatar.has_method("is_overlay_playing"):
		_check(bool(avatar.call("is_overlay_playing")), "Climb clip not playing on the avatar")
		_check(String(avatar.get("_overlay_name")) == "climbup_1m", "Wrong clip during climb: %s" % String(avatar.get("_overlay_name")))
	var climbed := await _wait_climb(player, 120)
	_check(climbed, "Jump in front of a 2.2 m wall did not start a climb")
	await _frames(10)
	_check(player.global_position.y > o.y + 2.1, "Did not end on top of the 2.2 m wall (y=%.2f)" % (player.global_position.y - o.y))
	_check(player.global_position.z - o.z < -2.05,"Did not move over the edge (z=%.2f)" % (player.global_position.z - o.z))
	_check(player.is_on_floor(), "Not standing on the wall top after climbing")

	# 2) Mureta de 1 m: o pulo normal resolve, sem escalada.
	await _place(player, o + Vector3(8, 0.05, -1.4))
	await _tap_jump()
	var low_climb := false
	for frame in range(10):
		await _frames(1)
		low_climb = low_climb or bool(player.get("climbing"))
	_check(not low_climb, "1 m wall started a climb (jump should be enough)")
	_check(player.velocity.y > 0.0 or not player.is_on_floor(), "1 m wall: jump did not happen")
	await _frames(60)

	# 3) Muro de 3,2 m: fora do alcance.
	await _place(player, o + Vector3(-8, 0.05, -1.4))
	await _tap_jump()
	Input.action_press("move_forward")
	var high_climb := false
	for frame in range(60):
		await _frames(1)
		high_climb = high_climb or bool(player.get("climbing"))
	Input.action_release("move_forward")
	_check(not high_climb, "3.2 m wall should be out of reach")
	_check(player.global_position.y < o.y + 1.0 or player.is_on_floor() and player.global_position.y < o.y + 0.2, "Ended up on the 3.2 m wall")

	# 4) No ar: pula longe do muro e segura para frente; agarra a borda.
	await _place(player, o + Vector3(16, 0.05, -0.2))
	Input.action_press("move_forward")
	await _frames(2)
	await _tap_jump()
	var air := await _wait_climb(player, 120)
	Input.action_release("move_forward")
	_check(air, "Holding forward in the air against a 2.2 m wall did not climb")
	await _frames(10)
	_check(player.global_position.y > o.y + 2.1, "Air climb did not end on top (y=%.2f)" % (player.global_position.y - o.y))

	for node in nodes:
		node.queue_free()
	scene.queue_free()
	await _frames(2)
	for failure in failures:
		printerr(failure)
	print("LEDGE CLIMB: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
