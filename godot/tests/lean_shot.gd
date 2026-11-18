extends SceneTree
## Luneta aberta + inclinação (Q/E): a bala sai de onde a mira está, inclinada
## para fora da cobertura — não do cano parado atrás da parede.
var failures: Array[String] = []

class Target extends StaticBody3D:
	var damage := 0.0
	func take_damage(amount: float) -> void:
		damage += amount

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _box(parent: Node, at: Vector3, size: Vector3) -> Target:
	var body := Target.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = at
	return body

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.position = Vector3(0, 0.1, 10)
	player.set("yaw", 0.0)
	player.set("pitch", 0.0)
	player.call("_equip_weapon", "sniper")
	Input.action_press("aim")
	Input.action_press("lean_right")
	await _frames(45)
	_check(bool(player.call("is_scope_active")) and float(player.get("lean")) > 0.9, "Scoped and leaning right")
	var aim: Dictionary = player.call("_aim_setup")
	var barrel: Vector3 = aim["barrel"]
	var muzzle: Marker3D = (player.get("weapon_model") as Node3D).get_node("Muzzle")
	_check(barrel.x - muzzle.global_position.x > 0.25, "The barrel moves with the lean (%.2f m)" % (barrel.x - muzzle.global_position.x))
	# Cobertura: parede baixa que tapa a linha do cano SEM inclinar, mas não a da
	# mira inclinada. Alvo lá na frente, no centro da mira.
	var cam: Camera3D = player.get("camera")
	var center := cam.global_position + (-cam.global_basis.z) * 30.0
	var target := _box(scene, center, Vector3(2, 2, 0.5))
	var unleaned := muzzle.global_position
	var cover := _box(scene, Vector3(unleaned.x - 0.35, unleaned.y, unleaned.z - 2.0), Vector3(1.1, 0.5, 0.15))
	await _frames(3)
	player.call("_shoot")
	_check(target.damage > 0.0, "Leaning past cover, the scoped shot reaches the crosshair target")
	_check(cover.damage == 0.0, "The shot does not stop on the cover beside the un-leaned barrel")
	# Sem inclinar, a mesma parede barra (o cano está atrás dela).
	Input.action_release("lean_right")
	await _frames(45)
	var before := target.damage
	var cam_now := cam.global_position + (-cam.global_basis.z) * 30.0
	target.global_position = cam_now
	var muzzle_now := muzzle.global_position
	cover.global_position = Vector3(muzzle_now.x, muzzle_now.y, muzzle_now.z - 2.0)
	(cover.get_child(0).shape as BoxShape3D).size = Vector3(3.0, 0.5, 0.15)
	player.set("ammo", 5)
	player.set("fire_delay", 0.0)
	await _frames(3)
	player.call("_shoot")
	_check(cover.damage > 0.0 and target.damage == before, "Not leaning, a wall on the barrel line still blocks")
	Input.action_release("aim")
	for failure in failures:
		printerr(failure)
	print("LEAN SHOT: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
