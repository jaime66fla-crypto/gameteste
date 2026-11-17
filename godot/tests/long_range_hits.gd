extends Node
## Tiro de longe: um alvo parado a 25-150 m, mirando no peito, conta acertos.
## godot --headless --path godot res://tests/long_range_hits.tscn
const NetActorScript = preload("res://scripts/net/net_actor.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Mundo aberto da Sobrevivência (sem rede): espaço livre para tiros de 150 m.
	var origin := Vector3(-120, 0.1, 120)
	Net.my_id = "me"
	Net.host_id = "nobody"
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "nobody", "clock": {"day_ms": 1440000, "time": 0},
		"you": {"id": "me", "p": [origin.x, origin.y, origin.z], "hp": 100, "hunger": 90, "thirst": 90, "inv": {}, "weight": 0, "cap": 20},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(10)
	var player: CharacterBody3D = main.get("player")
	# Acha uma direção sem nada no caminho por 160 m.
	var space := player.get_world_3d().direct_space_state
	var forward := Vector3.ZERO
	for angle_deg in range(0, 360, 10):
		var dir := Vector3(-sin(deg_to_rad(angle_deg)), 0, -cos(deg_to_rad(angle_deg)))
		var q := PhysicsRayQueryParameters3D.create(origin + Vector3(0, 1.4, 0), origin + Vector3(0, 1.4, 0) + dir * 165.0, 1)
		if space.intersect_ray(q).is_empty():
			forward = dir
			break
	print("direção livre: %s" % forward)
	var actor: CharacterBody3D = NetActorScript.new()
	actor.call("setup", "t1", "Alvo", false)
	main.add_child(actor)
	var hits := {"n": 0, "zones": {}}
	actor.connect("damaged", func(_id, zone, _p, _n, _w):
		hits["n"] += 1
		hits["zones"][zone] = int(hits["zones"].get(zone, 0)) + 1)
	for weapon in ["rifle", "sniper", "pistol"]:
		for distance in [25.0, 50.0, 80.0, 120.0, 150.0]:
			# Alvo à frente (-Z), sem nada no meio.
			actor.global_position = origin + forward * distance
			actor.set("target_position", actor.global_position) # NetActor segue a última posição recebida
			player.global_position = origin
			await _frames(3)
			hits["n"] = 0
			hits["zones"] = {}
			var shots := 20
			for i in shots:
				# Mira no peito do alvo (1.35 m) a partir da câmera atual.
				var camera: Camera3D = player.get("camera")
				var chest := actor.global_position + Vector3(0, 1.3, 0)
				for k in 4: # a câmera fica no ombro: ajusta yaw/pitch até o centro da tela cair no peito
					var to := chest - camera.global_position
					player.set("yaw", atan2(-to.x, -to.z))
					player.set("pitch", atan2(to.y, Vector2(to.x, to.z).length()))
					await _frames(2)
				player.set("current_weapon", weapon)
				player.set("ammo", 30)
				player.set("reloading", false)
				player.set("fire_delay", 0.0)
				player.set("aiming", true)
				player.call("_shoot")
			print("  (alvo em %s)" % actor.global_position)
			print("%s a %3d m: %2d/%d acertos %s" % [weapon, int(distance), hits["n"], shots, hits["zones"]])
	get_tree().quit(0)
