extends Node
## Escada interna dos sobrados de parkour (os da Sobrevivência, montados por
## tests/parkour_fixture.gd): o jogador entra pela frente, sobe andando (W) e
## chega ao piso do 1º andar (3,4 m), saindo para o lado no alto da escada.
## Mede onde trava, se travar.
## godot --headless --path godot res://tests/house_stairs.tscn
const Parkour = preload("res://scripts/parkour_district.gd")
const Fixture = preload("res://tests/parkour_fixture.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Net.in_match = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	Fixture.build(main)
	await _frames(10)
	var player: CharacterBody3D = main.get("player")
	var houses := get_tree().get_nodes_in_group("parkour_house").filter(func(n): return str(n.name).begins_with("Sobrado"))
	check(not houses.is_empty(), "há sobrados nos lotes de teste (%d)" % houses.size())
	if houses.is_empty():
		get_tree().quit(1)
		return
	for house in houses.slice(0, 3):
		var body := house as Node3D
		var xf := body.global_transform
		var hx := 5.0
		var foot_local := Vector3(-hx + Parkour.WALL + 0.6, 0, 1.5) # pé da escada interna
		var dir := (xf.basis * Vector3(0, 0, -1)).normalized()
		var start := xf * (foot_local + Vector3(0, 0, 1.2))
		player.global_position = start + Vector3(0, 0.15, 0)
		player.velocity = Vector3.ZERO
		player.set("yaw", atan2(-dir.x, -dir.z))
		player.set("pitch", 0.0)
		await _frames(20)
		Input.action_press("move_forward")
		var top := 0.0
		var stuck_at := Vector3.ZERO
		var last := player.global_position
		var still := 0
		for i in 300:
			await _frames(1)
			top = maxf(top, player.global_position.y)
			if player.global_position.distance_to(last) < 0.003:
				still += 1
				if still == 20:
					stuck_at = player.global_position
			else:
				still = 0
			last = player.global_position
		Input.action_release("move_forward")
		var local_stuck := xf.affine_inverse() * stuck_at if stuck_at != Vector3.ZERO else Vector3.ZERO
		print("%s: subiu até %.2f m; travou em %s (local %s)" % [body.name, top, stuck_at, local_stuck])
		# No alto (encostado no fundo) vira para o lado e sai no piso do 1º andar.
		var side := (xf.basis * Vector3(1, 0, 0)).normalized()
		player.set("yaw", atan2(-side.x, -side.z))
		Input.action_press("move_forward")
		await _frames(60)
		Input.action_release("move_forward")
		await _frames(20)
		print("   depois de sair para o lado: altura %.2f m" % player.global_position.y)
		check(top > Parkour.FLOOR_H - 0.08, "%s: a escada interna chega à altura do 1º andar (%.2f m)" % [body.name, top])
		var off := xf.affine_inverse() * player.global_position
		check(player.global_position.y > Parkour.FLOOR_H - 0.08 and off.x > -2.9, "%s: sai da escada para o piso do 1º andar (altura %.2f m, x local %.2f)" % [body.name, player.global_position.y, off.x])
	print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures else 0)
