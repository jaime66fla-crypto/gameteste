extends SceneTree
## Foto de conferência do Manual de sobrevivência (L) em algumas páginas e resoluções.
## godot --path godot --script res://tools/survival/capture_manual.gd -- --out=<pasta>
const ManualUI = preload("res://scripts/survival/survival_manual.gd")

func _initialize() -> void:
	_run.call_deferred()

func _shot(out: String, file: String) -> void:
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join(file))

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var bg := ColorRect.new()
	bg.color = Color("#3b4a35")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui: Control = ManualUI.new()
	layer.add_child(ui)
	await process_frame
	ui.call("set_inventory", {"hide": 7, "rope": 3, "iron_ore": 3, "charcoal": 1, "wood": 2, "stone": 4})
	root.size = Vector2i(1280, 720)
	ui.call("open", "")
	ui.set("_section", "era:3")
	ui.set("_selected", "r:iron_bar")
	ui.call("_refresh")
	await _shot(out, "manual_era3.png")
	ui.set("_section", "era:4")
	ui.set("_selected", "r:pipe_shotgun")
	ui.call("_refresh")
	await _shot(out, "manual_era4.png")
	ui.call("open", "workbench")
	ui.set("_selected", "r:leather_vest")
	ui.call("_refresh")
	await _shot(out, "manual_workbench.png")
	ui.set("_section", "materials")
	ui.set("_selected", "i:iron_ore")
	ui.call("_refresh")
	root.size = Vector2i(1920, 1080)
	await _shot(out, "manual_materials_1080.png")
	root.size = Vector2i(1024, 600)
	await _shot(out, "manual_materials_small.png")
	print("salvo em " + out)
	quit(0)
