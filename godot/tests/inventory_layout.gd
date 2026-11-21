extends SceneTree
func _initialize() -> void:
	var layout = load("res://scripts/survival/inventory_layout.gd").new()
	layout.sync({"wood": 20, "stone": 10})
	assert(layout.move_stack(0, 5, 7))
	assert(layout.slots[0].n == 13 and layout.slots[5].n == 7)
	layout.sync({"wood": 20, "stone": 10})
	assert(layout.slots[5].n == 7, "refresh preserves split stacks")
	assert(layout.move_stack(5, 1, 7))
	assert(layout.slots[5].item == "stone" and layout.slots[1].item == "wood")
	assert(not layout.move_stack(0, 5, 2))
	layout.sync({"wood": 3, "stone": 10})
	var totals := {}
	for slot in layout.slots:
		if not slot.is_empty():
			totals[slot.item] = int(totals.get(slot.item, 0)) + slot.n
	assert(totals == {"wood": 3, "stone": 10}, "server changes cannot duplicate items")
	print("INVENTORY LAYOUT: PASS")
	quit()
