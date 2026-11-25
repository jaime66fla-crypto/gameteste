extends Node
## Intro do naufrágio dentro do jogo (sem servidor): personagem novo, a praia
## de verdade e o começo do jogo no mesmo lugar. Fotos em alguns momentos.
## godot --path godot --fixed-fps 20 res://tools/survival/capture_intro_world.tscn -- <pasta>
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const Intro = preload("res://scripts/survival/shipwreck_intro.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://intro_world"
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Intro.SEEN_PATH))
	var spawn: Array = SurvivalData.world()["spawns"][0]
	Net.my_id = "me"
	Net.host_id = "me"
	Net.in_match = true
	Net.start_info = {
		"t": "start", "survival": true, "host": "me", "clock": {"day_ms": 1440000, "time": 60000},
		"you": {"id": "me", "p": [spawn[0], 0.2, spawn[1]], "hp": 100, "hunger": 85, "thirst": 85, "dead": false, "inv": {}, "weight": 0, "cap": 20},
		"roster": [], "zombies": [], "bags": [], "searched": [], "depleted": {}, "vehicles": [],
	}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var intro: Node = main.find_child("ShipwreckIntro", true, false)
	if intro == null:
		printerr("intro não tocou")
		get_tree().quit(1)
		return
	print("praia real: ", intro.get("real_beach"), " em ", intro.get("beach_point"), " (spawn ", spawn, ")")
	for at in [33.0, 36.5, 41.6, 44.5, 48.8, 53.0]:
		while is_instance_valid(intro) and float(intro.get("t")) < at:
			await get_tree().process_frame
		if not is_instance_valid(intro):
			for i in 30:
				await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/world_%04.1f.png" % [out, at])
	var player: Node3D = main.get("player")
	print("jogador em ", player.global_position, " física ", player.is_physics_processing())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Intro.SEEN_PATH))
	get_tree().quit()
