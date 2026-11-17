extends SceneTree
## Foto de conferência do inventário em várias resoluções de janela
## (o jogo usa stretch canvas_items com base 1280x720).
## godot --path godot --script res://tools/survival/capture_inventory.gd -- --out=<pasta>
const InventoryUI = preload("res://scripts/survival/inventory_ui.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out := "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	var bg := ColorRect.new()
	bg.color = Color("#5d7a4e")
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui: Control = InventoryUI.new()
	layer.add_child(ui)
	await process_frame
	ui.call("set_inventory", {"w_rifle": 1, "a_556": 60, "canned_beans": 2, "water_bottle": 1, "bandage": 3, "wood": 2, "cloth": 4, "improvised_axe": 1, "gasoline": 1, "school_bag": 1}, 14.6, 34, "backpack")
	ui.call("set_status", 82, 64, 47, "Fuzil")
	ui.call("show_container", "k0", "Geladeira", {"soda": 2, "water_bottle": 1, "apple": 3})
	ui.call("open")
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 600)]:
		root.size = size
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("inventory_%dx%d.png" % [size.x, size.y]))
	ui.set("_tab", 1)
	ui.call("_refresh")
	root.size = Vector2i(1280, 720)
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("inventory_craft.png"))
	print("salvo em " + out)
	quit(0)
