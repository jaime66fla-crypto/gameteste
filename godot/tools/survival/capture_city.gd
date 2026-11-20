extends Node
## Fotos de conferência das cidades abandonadas da Sobrevivência (sem servidor):
## rua no chão, de cima, e a oficina/química montadas.
## godot --path godot res://tools/survival/capture_city.tscn -- --out=<pasta>
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _shot(out: String, file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(file))

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	get_tree().root.size = Vector2i(1600, 900)
	var world: Dictionary = SurvivalData.world()
	var town: Array = world["towns"][0]["center"]
	var c := Vector3(float(town[0]), 0, float(town[1]))
	# Na avenida, entre a 2ª e a 3ª rua, olhando para o norte (casas de frente).
	var spot := c + Vector3(-2.0, 0.2, 20.0)
	Net.my_id = "me"
	Net.host_id = "ninguem"
	Net.in_match = true
	var vehicles: Array = []
	for v in world["vehicles"]:
		vehicles.append({"id": v["id"], "kind": v["kind"], "color": v["color"], "p": v["p"], "yaw": v["yaw"], "fuel": 12, "driver": null})
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 300000},
		"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 90, "hunger": 70, "thirst": 60,
			"inv": {"crowbar": 1, "w_pistol": 1, "a_9mm": 12}, "back": "", "weight": 3.0, "cap": 10},
		"roster": [], "zombies": [
			{"id": "z1", "kind": "walker", "hp": 60, "p": [c.x + 6.0, 0.2, c.z + 2.0]},
			{"id": "z2", "kind": "walker", "hp": 60, "p": [c.x - 10.0, 0.2, c.z + 6.0]}],
		"bags": [], "searched": [], "depleted": {}, "vehicles": vehicles,
		"builds": [
			{"id": "P1", "kind": "workshop", "p": [spot.x + 3.0, 0.0, spot.z - 1.5], "y": 0.0, "hp": 500, "ow": "me"},
			{"id": "P2", "kind": "chem_table", "p": [spot.x + 6.0, 0.0, spot.z - 1.5], "y": 0.0, "hp": 250, "ow": "me"}]}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	var player: CharacterBody3D = main.get("player")
	player.set("yaw", 0.0) # olha para -Z (norte)
	player.set("pitch", -0.05)
	await _frames(60)
	await _shot(out, "city_street.png")
	var cam: Camera3D = get_viewport().get_camera_3d()
	cam.global_position = spot + Vector3(4.5, 1.8, 2.5)
	cam.look_at(spot + Vector3(4.5, 0.8, -1.5))
	await _frames(3)
	await _shot(out, "city_stations.png")
	cam.global_position = c + Vector3(0, 70, 75)
	cam.look_at(c)
	await _frames(3)
	await _shot(out, "city_aerial.png")
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
