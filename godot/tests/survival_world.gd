extends SceneTree
## Sobrevivência: monta o mundo aberto, um zumbi anfitrião e o inventário sem rede.
## godot --headless --path godot --script res://tests/survival_world.gd
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const SurvivalWorld = preload("res://scripts/survival/survival_world.gd")
const ZombieScript = preload("res://scripts/survival/zombie.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")

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
	var data := SurvivalData.world()
	check(data.get("containers", []).size() > 100, "mundo com recipientes")
	check(SurvivalData.ammo_for("pistol") == "a_9mm", "pistola usa 9mm")
	check(SurvivalData.best_melee({"bat": 1, "axe": 1})[0] == "axe", "machado é a melhor arma branca")
	var root3d := Node3D.new()
	root.add_child(root3d)
	var world: Node3D = SurvivalWorld.new()
	root3d.add_child(world)
	await process_frame
	check(world.containers.size() == data["containers"].size(), "todos os recipientes montados")
	check(world.resources.size() == data["resources"].size(), "todos os recursos montados")
	var rid: String = world.resources.keys()[0]
	world.call("set_depleted", rid, true)
	check(bool(world.resources[rid]["depleted"]), "recurso coletado")
	# Cone de visão: alvo 10 m ATRÁS do zumbi (que olha para -Z) passa despercebido.
	var spawn: Array = data["spawns"][0]
	var target := Node3D.new()
	root3d.add_child(target)
	target.global_position = Vector3(float(spawn[0]), 0, float(spawn[1]) + 10.0)
	var z: CharacterBody3D = ZombieScript.new()
	z.call("setup", "z1", "runner", 45)
	root3d.add_child(z)
	z.global_position = Vector3(float(spawn[0]), 0.3, float(spawn[1]))
	z.rotation.y = 0.0
	z.set("targets", func(): return [{"id": "p1", "node": target}])
	z.call("set_controlled", true)
	var bites := [0]
	z.connect("attacked", func(_zid, tid): bites[0] += 1)
	await physics_frame
	z.set("_think", 0.0)
	for i in 3:
		await physics_frame
	check(z.get("_target") == null, "zumbi não vê quem está atrás dele, longe")
	z.global_position = Vector3(float(spawn[0]), 0.3, float(spawn[1]))
	z.rotation.y = 0.0
	z.set("_target", null)
	z.set("_investigate", Vector3.INF)
	# Zumbi anfitrião persegue um alvo a 10 m à frente, em campo aberto
	# (vagueando na direção dele, para não virar de costas antes de vê-lo).
	target.global_position = Vector3(float(spawn[0]), 0, float(spawn[1]) - 10.0)
	z.set("_wander_goal", target.global_position)
	var start: float = z.global_position.distance_to(target.global_position)
	for i in 240:
		await physics_frame
	check(z.global_position.distance_to(target.global_position) < start - 4.0, "zumbi se aproxima do alvo")
	check(bites[0] > 0, "zumbi ataca de perto")
	check(z.call("state").size() == 6, "pacote do zumbi")
	# Parede entre os dois (jogador dentro de casa, zumbi fora): não morde através dela.
	var wall := StaticBody3D.new()
	wall.collision_layer = HitboxScript.LAYER_WORLD
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 3.0, 6.0)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	root3d.add_child(wall)
	var base := Vector3(float(spawn[0]) + 40.0, 0, float(spawn[1]))
	wall.global_position = base + Vector3(0, 1.5, 0)
	target.global_position = base + Vector3(0.45, 0, 0)
	z.global_position = base + Vector3(-0.55, 0.3, 0)
	z.set("_target", target)
	z.set("_target_id", "p1")
	z.set("_attack_timer", 0.0)
	await physics_frame
	bites[0] = 0
	for i in 150:
		z.global_position.x = minf(z.global_position.x, base.x - 0.25) # encostado na parede
		await physics_frame
	check(bites[0] == 0, "zumbi não morde através da parede")
	wall.queue_free()
	var ui: Control = InventoryUI.new()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(ui)
	await process_frame
	ui.call("set_inventory", {"w_pistol": 1, "a_9mm": 20, "cloth": 4}, 1.8, 20)
	ui.call("show_container", "k1", "Armário", {"canned_beans": 2})
	await process_frame
	check(ui.get("inv").size() == 3, "inventário mostra a mochila")
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
