extends Node
## Fotos das telas da Sobrevivência no tema do menu principal: HUD, modo de
## construção, "Liberar a base", tela de morte e "Sair da partida?".
## godot --path godot res://tools/survival/capture_ui.tscn -- --out=<pasta>
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
	get_tree().root.size = Vector2i(1280, 720)
	var spawn: Array = SurvivalData.world()["spawns"][2]
	Net.my_id = "me"
	Net.host_id = "ninguem"
	Net.in_match = true
	Net.start_info = {"t": "start", "survival": true, "host": "ninguem", "clock": {"day_ms": 1440000, "time": 300000},
		"you": {"id": "me", "p": [float(spawn[0]), 0.2, float(spawn[1])], "hp": 74, "hunger": 58, "thirst": 81,
			"inv": {"wood": 9, "stone": 6, "fiber": 12, "rope": 2}, "weight": 13, "cap": 20},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": [],
		"tag": "me", "auth": [{"tag": "x1", "name": "Amigo"}], "allowed": [], "builds": [], "animals": []}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	var controller := main.get_node("SurvivalController")
	var b: Node = controller.building_ctl
	b.call("set_building", true)
	await _frames(15)
	await _shot(out, "ui_build.png")
	b.call("set_building", false)
	b.call("open_auth")
	await _frames(8)
	await _shot(out, "ui_auth.png")
	b.call("close_auth")
	Net.message.emit({"t": "hp", "id": "me", "hp": 0, "by": "a9", "w": "a_wolf", "killed": true})
	await _frames(12)
	await _shot(out, "ui_death.png")
	controller.death_panel.visible = false
	main.call("_ask_quit", false)
	await _frames(8)
	await _shot(out, "ui_quit.png")
	print("fotos salvas em " + out)
	Net.in_match = false
	get_tree().quit(0)
