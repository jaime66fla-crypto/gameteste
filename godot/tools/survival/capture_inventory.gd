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
	ui.call("set_inventory", {"stick": 3, "stone": 5, "fiber": 7, "wood": 2, "rope": 1, "berries": 4, "bandage": 2, "herb": 2, "herbal_cure": 1, "stone_axe": 1, "stone_knife": 1, "raw_meat": 3, "cooked_meat": 1, "hide": 2, "hide_bag": 1}, 14.6, 20, "sack_bag")
	ui.call("set_status", 82, 64, 47, "")
	ui.call("show_container", "b1", "Carcaça de cervo", {"raw_meat": 4, "hide": 2})
	ui.call("open")
	ui.set("_selected", "raw_meat")
	ui.set("_tab", 1)
	ui.call("_refresh")
	root.size = Vector2i(1280, 720)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("inventory_craft_first.png"))
	ui.set("_tab", 0)
	ui.call("_refresh")
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 600)]:
		root.size = size
		for i in 10:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("inventory_%dx%d.png" % [size.x, size.y]))
	ui.set("_tab", 1)
	ui.call("_refresh")
	root.size = Vector2i(1280, 720)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("inventory_craft.png"))
	print("salvo em " + out)
	quit(0)
