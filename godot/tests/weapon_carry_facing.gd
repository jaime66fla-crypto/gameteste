extends SceneTree
## Arma de fogo baixa no estilo mundo aberto: sem mirar o corpo vira para onde
## anda (de ré ele corre de frente para a câmera); depois de um tiro gira
## rápido (não no mesmo quadro) para a mira e fica pronto ~1,6 s.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print(("ok: " if ok else "FALHOU: ") + message)
	if not ok:
		failures.append(message)

func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame

func _body_offset(player: Node) -> float:
	return absf(wrapf(float(player.get("_body_yaw")) - float(player.get("yaw")), -PI, PI))

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(400, 30, 400)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 80)
	collider.shape = shape
	floor_body.add_child(collider)
	scene.add_child(floor_body)
	player.global_position = Vector3(400, 30.6, 400)
	player.set("yaw", 0.0)
	player.set("weapon_holstered", false)
	await _frames(30)
	_check(str(player.get("current_weapon")) == "pistol", "começa com a pistola")

	var always_ready: bool = player.get_script().get_script_constant_map().get("ALWAYS_READY", false)
	var avatar: Node = player.get("humanoid_avatar")
	if always_ready:
		# Postura de tiro sempre pronta (fps-tatico): de ré o corpo continua de
		# frente para a mira, arma levantada nas duas mãos.
		Input.action_press("move_back")
		await _frames(60)
		_check(_body_offset(player) < 0.15, "sempre pronto: de ré o corpo fica de frente para a mira (%.2f rad)" % _body_offset(player))
		if avatar != null:
			_check(bool(avatar.get("weapon_ready")), "avatar com a arma sempre pronta")
			_check(float(avatar.get("_stance")) > 0.95, "avatar na postura de tiro da UAL (%.2f)" % float(avatar.get("_stance")))
	else:
		# De ré sem mirar: o corpo vira para trás (corre de frente para a câmera).
		Input.action_press("move_back")
		await _frames(60)
		_check(_body_offset(player) > 2.6, "arma baixa de ré: corpo virado para o movimento (%.2f rad)" % _body_offset(player))
		# Tiro (simulado): gira para a mira rápido, mas não no mesmo quadro.
		player.set("_weapon_ready_left", 1.6)
		await _frames(1)
		var first := _body_offset(player)
		_check(first > 0.3, "giro para a mira é suave, não estala (%.2f rad no 1º quadro)" % first)
		await _frames(8)
		_check(_body_offset(player) < 0.15, "em ~0,15 s já está de frente para a mira (%.2f rad)" % _body_offset(player))
		if avatar != null:
			_check(bool(avatar.get("weapon_ready")), "avatar com a arma pronta depois do tiro")
		# Passado o tempo pronto, baixa a arma e volta a virar para o movimento.
		await _frames(130)
		_check(_body_offset(player) > 2.6, "depois de ~1,6 s baixa e corre de frente de novo (%.2f rad)" % _body_offset(player))
		if avatar != null:
			_check(not bool(avatar.get("weapon_ready")), "avatar com a arma baixa de novo")

	# Mirando (botão direito): corpo preso na câmera, andando de ré.
	Input.action_press("aim")
	await _frames(10)
	_check(bool(player.get("aiming")), "botão de mirar liga a mira")
	_check(_body_offset(player) < 0.15, "mirando: corpo de frente para a mira (%.2f rad)" % _body_offset(player))
	await _frames(30)
	var planar := Vector2(player.velocity.x, player.velocity.z).length()
	_check(planar > 2.0 and planar <= 2.75, "mirando anda em passo de mira (%.2f m/s)" % planar)
	Input.action_release("aim")
	await _frames(30)
	planar = Vector2(player.velocity.x, player.velocity.z).length()
	_check(planar > 4.5, "sem mirar volta ao passo normal (%.2f m/s)" % planar)
	Input.action_release("move_back")
	Input.action_release("move_back")

	if failures.is_empty():
		print("WEAPON CARRY FACING: PASS")
	else:
		print("FALHAS: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
