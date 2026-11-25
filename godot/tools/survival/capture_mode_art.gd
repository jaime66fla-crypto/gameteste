extends Node
## Imagem da aba Sobrevivência no menu (assets/ui/survival_mode.jpg): rua da
## cidade abandonada no fim da tarde, zumbis e carro largado, sem HUD.
## godot --path godot res://tools/survival/capture_mode_art.tscn -- --out=<pasta>
## Sem --out= grava direto em res://assets/ui/survival_mode.jpg.
const SurvivalData = preload("res://scripts/survival/survival_data.gd")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func _hide_hud(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			child.visible = false
		_hide_hud(child)

func _run() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	get_tree().root.size = Vector2i(1600, 900)
	var world: Dictionary = SurvivalData.world()
	var town: Array = world["towns"][0]["center"]
	var c := Vector3(float(town[0]), 0, float(town[1]))
	var spot := c + Vector3(-2.0, 0.2, 20.0)
	Net.my_id = "me"
	Net.host_id = "ninguem"
	Net.in_match = true
	var vehicles: Array = []
	for v in world["vehicles"]:
		vehicles.append({"id": v["id"], "kind": v["kind"], "color": v["color"], "p": v["p"], "yaw": v["yaw"], "fuel": 12, "driver": null})
	var zombies: Array = []
	var zpos := [[1.5, 4.0], [-3.0, 0.0], [3.5, -4.0], [-1.0, -9.0], [5.0, -13.0]]
	for i in zpos.size():
		zombies.append({"id": "z%d" % i, "kind": "walker", "hp": 60, "p": [spot.x + zpos[i][0], 0.2, spot.z - 6.0 + zpos[i][1]]})
	# 17h40: sol baixo, luz quente e sombras compridas.
	Net.start_info = {"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 700000},
		"you": {"id": "me", "p": [spot.x, spot.y, spot.z], "hp": 90, "hunger": 70, "thirst": 60,
			"inv": {"crowbar": 1}, "back": "", "weight": 3.0, "cap": 10},
		"roster": [], "zombies": zombies, "bags": [], "searched": [], "depleted": {}, "vehicles": vehicles, "builds": []}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	var player: CharacterBody3D = main.get("player")
	player.set("yaw", 0.0)
	player.set("pitch", -0.05)
	await _frames(60)
	_hide_hud(get_tree().root)
	var cam: Camera3D = get_viewport().get_camera_3d()
	cam.global_position = spot + Vector3(-1.6, 1.8, 3.2)
	cam.look_at(spot + Vector3(0.8, 0.3, -10.0))
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	var path := "res://assets/ui/survival_mode.jpg" if out.is_empty() else out.path_join("survival_mode.jpg")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_jpg(path, 0.86)
	print("imagem salva em " + path)
	Net.in_match = false
	get_tree().quit(0)
