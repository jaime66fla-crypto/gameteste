extends RefCounted
## Presentation only. The server owns totals; these slots arrange and split them.
var slots: Array = []

func sync(items: Dictionary) -> void:
	var remaining := items.duplicate()
	for i in slots.size():
		var item := str(slots[i].get("item", ""))
		var n := mini(int(slots[i].get("n", 0)), int(remaining.get(item, 0)))
		slots[i] = {"item": item, "n": n} if n > 0 else {}
		remaining[item] = int(remaining.get(item, 0)) - n
	for item in remaining:
		var n := int(remaining[item])
		if n <= 0:
			continue
		var target := -1
		for i in slots.size():
			if slots[i].get("item", "") == item:
				target = i
				break
		if target >= 0:
			slots[target]["n"] += n
		else:
			var empty := slots.find({})
			if empty >= 0:
				slots[empty] = {"item": item, "n": n}
			else:
				slots.append({"item": item, "n": n})
	while slots.size() < 24 or slots.back() != {}:
		slots.append({})

func move_stack(source: int, target: int, n: int) -> bool:
	if source == target or source < 0 or target < 0 or source >= slots.size() or target >= slots.size() or slots[source].is_empty():
		return false
	var from: Dictionary = slots[source]
	if n < 1 or n > int(from["n"]):
		return false
	var to: Dictionary = slots[target]
	if not to.is_empty() and to["item"] != from["item"]:
		if n != int(from["n"]):
			return false
		slots[source] = to
		slots[target] = from
		return true
	slots[target] = {"item": from["item"], "n": int(to.get("n", 0)) + n}
	from["n"] -= n
	if from["n"] == 0:
		slots[source] = {}
	return true
