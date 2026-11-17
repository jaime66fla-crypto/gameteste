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
				check((avatar.get("hitboxes") as Array).size() >= 12, "áreas de acerto nos ossos")
				var zones := {}
				for hb in avatar.get("hitboxes"):
					zones[str(hb.get("zone"))] = true
				check(zones.has("head") and zones.has("chest") and zones.has("leg"), "zonas cabeça/peito/perna")
			z.queue_free()
			await process_frame
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
