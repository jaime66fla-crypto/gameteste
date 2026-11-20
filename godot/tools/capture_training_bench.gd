extends SceneTree
## Foto da janela da bancada no treino offline (construção com material grátis):
## godot --path godot --script res://tools/capture_training_bench.gd -- --out=C:/pasta
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var out := "user://training_bench"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("Net").set("in_match", false)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in 20:
		await process_frame
	var ctl: Node = scene.get_node("TrainingBuild").get("building_ctl")
	ctl.call("open_bench")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("bancada.png"))
	ctl.call("pick_bench", "workshop")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("barra_bancada.png"))
	ctl.call("set_building", false)
	# Casinha: duas fundações, paredes, janela e a porta com a rampa de acesso.
	var pieces := [
		{"kind": "foundation", "i": 20, "j": 20, "k": 0}, {"kind": "foundation", "i": 21, "j": 20, "k": 0},
		{"kind": "wall", "i": 20, "j": 20, "k": 0, "o": "h"}, {"kind": "doorway", "i": 21, "j": 20, "k": 0, "o": "h"},
		{"kind": "window", "i": 20, "j": 20, "k": 0, "o": "v"}, {"kind": "door", "i": 21, "j": 20, "k": 0, "o": "h", "r": 0, "open": true}]
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		p.merge({"id": "C%d" % i, "hp": 100.0, "ow": "treino"})
		ctl.call("_place", p)
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.global_position = Vector3(61.5, 2.4, 55.5)
	cam.look_at(Vector3(64.5, 0.6, 60.5))
	cam.current = true
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("rampa_porta.png"))
	quit()
