extends Node
var failures := 0
func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", what)
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	var ui = load("res://scripts/survival/inventory_ui.gd").new()
	add_child(ui)
	ui._layout.slots = []
	ui.set_inventory({"wood": 20, "stone": 10}, 26.0, 60.0)
	ui.show_container("trunk:v0", "Porta-malas (0 / 180 kg)", {}, true)
	ui.open()
	var received := []
	ui.store_requested.connect(func(k, item, n): received.append([k, item, n]))
	ui._request_amount("store", "wood", 20)
	ui._quantity.value = 7
	ui._quantity_dialog.confirmed.emit()
	check(received == [["trunk:v0", "wood", 7]], "selected quantity reaches store request")
	check(ui.can_drop_item({"ui": ui, "item": "wood", "source": "inventory", "index": 0}, "container", -1), "inventory accepts drag to trunk")
	ui._quantity_dialog.hide()
	for i in 3: await get_tree().process_frame
	var source: Control = ui._grid.get_child(0)
	var target: Control = ui._grid.get_child(5)
	var from := source.get_global_rect().get_center()
	var to := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = from
	motion.global_position = from
	get_viewport().push_input(motion)
	await get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from
	press.global_position = from
	press.pressed = true
	get_viewport().push_input(press)
	await get_tree().process_frame
	motion = InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(motion)
	await get_tree().process_frame
	check(get_viewport().gui_is_dragging(), "mouse gesture starts a drag without recreating the source tile")
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = to
	press.global_position = to
	get_viewport().push_input(press)
	for i in 2: await get_tree().process_frame
	check(ui._quantity_dialog.visible, "dropping into an empty slot opens quantity picker")
	ui._quantity.value = 4
	ui._quantity_dialog.confirmed.emit()
	check(ui._layout.slots[5].get("n") == 4, "mouse drag moves the chosen amount")
	ui._quantity_dialog.hide()
	ui._request_amount("drop", "wood", 4, 5)
	ui._quantity.value = 2
	ui._quantity_dialog.confirmed.emit()
	ui.confirm_operation(ui.operation_token(), {"wood": 18, "stone": 10})
	ui.set_inventory({"wood": 18, "stone": 10}, 24.0, 60.0)
	check(ui._layout.slots[5].get("n") == 2 and ui._layout.slots[0].get("n") == 16, "confirmed discard debits the dragged split stack")
	ui._quantity_dialog.hide()
	ui._request_amount("take", "wood", 10, -1, 8)
	ui._quantity.value = 3
	ui._quantity_dialog.confirmed.emit()
	ui.confirm_operation(ui.operation_token(), {"wood": 21, "stone": 10})
	ui.set_inventory({"wood": 21, "stone": 10}, 27.0, 60.0)
	check(ui._layout.slots[8].get("n") == 3, "confirmed transfer arrives in the chosen slot")
	ui._quantity_dialog.hide()
	ui.set("_selected", "wood")
	ui.call("_refresh")
	for i in 5: await get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			get_viewport().get_texture().get_image().save_png(arg.substr(6))
	ui.free()
	print("INVENTORY INTERACTIONS failures: ", failures)
	get_tree().quit(1 if failures else 0)
