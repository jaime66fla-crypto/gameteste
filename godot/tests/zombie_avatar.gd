extends SceneTree
## Zumbi com o modelo Mixamo: braços esticados para a frente em todos os estados
## (menos o bote, que vai mais longe), áreas de acerto presas aos ossos.
## godot --headless --path godot --script res://tests/zombie_avatar.gd
const ZombieScript = preload("res://scripts/survival/zombie.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.6, 6)
	camera.current = true
	var names := ["IDLE", "WALK", "RUN", "ATTACK"]
	for kind in ["walker", "runner", "brute"]:
		for state in 4:
			var z: CharacterBody3D = ZombieScript.new()
			z.call("setup", "t", kind, 60)
			root.add_child(z)
			var avatar: Node3D = z.get("_avatar")
			if avatar == null:
				check(false, "modelo do zumbi carregado")
				quit(1)
				return
			for f in 40:
				z.set("anim", state)
				await physics_frame
			var sk: Skeleton3D = avatar.get("skeleton")
			var shoulder := sk.get_bone_global_pose(int(avatar.call("_bone", "RightArm"))).origin
			var hand := sk.get_bone_global_pose(int(avatar.call("_bone", "RightHand"))).origin
			var ahead := hand.z - shoulder.z # frente do modelo = +Z no esqueleto
			print("%s %s: mão %.2f m à frente do ombro, %.2f m abaixo" % [kind, names[state], ahead, shoulder.y - hand.y])
			check(ahead > (0.42 if state != 3 else 0.5), "%s %s: braços esticados para a frente" % [kind, names[state]])
			if kind == "walker" and state == 0:
				# Casca única na física; a parte do corpo sai da conta nos ossos.
				check((z.get("hitboxes") as Array).size() == 1, "uma casca de acerto por zumbi")
				var p := z.global_position
				var zone_at := func(x: float, y: float) -> String:
					return str((avatar.call("resolve_ray", p + Vector3(x, y, 6), Vector3(0, 0, -1)) as Dictionary).get("zone", ""))
				var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(int(avatar.call("_bone", "Head"))).origin
				var head_y := head.y - p.y + 0.12
				check(zone_at.call(head.x - p.x, head_y) == "head", "tiro na cabeça = cabeça (%s)" % zone_at.call(head.x - p.x, head_y))
				check(zone_at.call(0.0, 1.2) == "chest", "tiro no peito = tronco (%s)" % zone_at.call(0.0, 1.2))
				check(zone_at.call(0.1, 0.45) == "leg", "tiro na canela = perna (%s)" % zone_at.call(0.1, 0.45))
				check(zone_at.call(0.5, 0.3) == "", "tiro entre a perna e a borda da casca passa direto")
				var query := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.2, 6), p + Vector3(0, 1.2, -6), 4)
				var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
				check(not hit.is_empty() and (hit["collider"] as Object).has_method("resolve_ray"), "raio do tiro acerta a casca")
			z.queue_free()
			await process_frame
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
