extends SceneTree
## Fotos da intro do naufrágio em alguns momentos (precisa de janela, sem --headless).
## godot --path godot --script res://tools/survival/capture_intro.gd -- <pasta>
const Intro = preload("res://scripts/survival/shipwreck_intro.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://intro_shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var intro: CanvasLayer = Intro.new()
	root.add_child(intro)
	await process_frame
	await process_frame
	for at in [12.0, 14.0]:
		while float(intro.get("t")) < at:
			await process_frame # rode com --fixed-fps 20: partículas no ritmo certo
		root.get_texture().get_image().save_png("%s/intro_%04.1f.png" % [out, at])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Intro.SEEN_PATH))
	quit()
