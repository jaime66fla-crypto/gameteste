extends Node
## Nado (pose do avatar), armas brancas nos slots 1, 2, 3... e a mata alta.
## Rodar: godot --headless --path godot --quit-after 3000 res://tests/swim_melee_forest.tscn

const AvatarScript = preload("res://scripts/characters/downloaded_avatar.gd")
const SurvivalWorld = preload("res://scripts/survival/survival_world.gd")
const Grip = preload("res://scripts/characters/swat_grip.gd")

var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	print(("ok: " if condition else "FALHOU: ") + message)
	if not condition:
		failures.append(message)

func _ready() -> void:
	_run.call_deferred()

func _key(player: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	player.call("_unhandled_input", event)

func _run() -> void:
	await _swim()
	await _combo()
	await _slots()
	await _forest()
	for failure in failures:
		printerr(failure)
	print("SWIM MELEE FOREST: ", "PASS" if failures.is_empty() else "FAIL (%d falhas)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _swim() -> void:
	var avatar: Node3D = AvatarScript.new()
	add_child(avatar)
	await get_tree().process_frame
	_check(bool(avatar.call("is_visual_ready")), "avatar pronto")
	var skeleton: Skeleton3D = avatar.get("skeleton")
	var hips := Grip._bone(skeleton, "Hips")
	var hand := Grip._bone(skeleton, "RightHand")
	for i in 60:
		avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
	var standing_up := (skeleton.get_bone_global_pose(hips).basis * Vector3.UP).normalized()
	avatar.call("set_swimming", true)
	var hand_low := INF
	var hand_high := -INF
	for i in 180:
		avatar.call("animate", 1.0 / 60.0, 1.0, false, false, false, true, false)
		var y := skeleton.get_bone_global_pose(hand).origin.y
		hand_low = minf(hand_low, y)
		hand_high = maxf(hand_high, y)
	var swim_up := (skeleton.get_bone_global_pose(hips).basis * Vector3.UP).normalized()
	_check(rad_to_deg(standing_up.angle_to(swim_up)) > 45.0, "crawl deita o corpo (%.0f°)" % rad_to_deg(standing_up.angle_to(swim_up)))
	_check(hand_high - hand_low > 0.3, "braçada: a mão sobe e desce (%.2f m)" % (hand_high - hand_low))
	for i in 120:
		avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, true, false)
	var tread_up := (skeleton.get_bone_global_pose(hips).basis * Vector3.UP).normalized()
	_check(rad_to_deg(standing_up.angle_to(tread_up)) < 25.0, "parado na água fica em pé (boiando)")
	avatar.call("set_swimming", false)
	for i in 90:
		avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
	_check(float(avatar.get("swim_weight")) == 0.0, "saindo da água a pose de nado some")
	avatar.queue_free()

func _combo() -> void:
	var avatar: Node3D = AvatarScript.new()
	add_child(avatar)
	await get_tree().process_frame
	avatar.call("set_armed", false)
	for tool in ["machete", "club", "stone_knife", "wood_spear", "iron_axe"]:
		avatar.call("set_action", "hold", tool)
		for i in 30:
			avatar.call("animate", 1.0 / 60.0, 0.5, false, false, false, false, false)
		var node: Node3D = avatar.get("_tool_node")
		_check(node != null and node.visible, "%s aparece na mão segurando" % tool)
		var ends: Array[Vector3] = []
		avatar.set("_last_swing_ms", -100000) # cada ferramenta começa um combo novo
		for swing in 2:
			avatar.call("set_action", "swing", tool)
			for i in 11: # fim da preparação: arma atrás de um ombro ou do outro
				avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
			ends.append(avatar.get("_tool_node").global_position)
			for i in 23:
				avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
			avatar.call("set_action", "hold", tool)
		_check(int(avatar.get("_swing_count")) == 1, "%s: 2º golpe seguido é o de volta" % tool)
		if tool in ["machete", "club"]:
			_check(ends[0].distance_to(ends[1]) > 0.15, "%s: ida e volta passam por lugares diferentes" % tool)
	avatar.queue_free()

func _slots() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var player: Node = scene.get_node("Jaime")
	player.set_physics_process(false)
	player.call("start_unarmed")
	player.call("give_weapon", "rifle", 0)
	_check(int(player.call("give_melee", "machete", "Facão")) == 2, "facão ganha o slot 2")
	_check(int(player.call("give_melee", "stone_axe", "Machado de pedra")) == 3, "machado ganha o slot 3")
	_key(player, KEY_2)
	_check(str(player.get("melee_weapon")) == "machete" and bool(player.get("weapon_holstered")), "2 pega o facão e guarda o fuzil")
	_key(player, KEY_3)
	_check(str(player.get("melee_weapon")) == "stone_axe", "3 troca para o machado")
	_key(player, KEY_3)
	_check(str(player.get("melee_weapon")).is_empty(), "3 de novo guarda o machado")
	_key(player, KEY_1)
	_check(str(player.get("current_weapon")) == "rifle" and not bool(player.get("weapon_holstered")) and str(player.get("melee_weapon")).is_empty(), "1 saca o fuzil")
	player.call("remove_melee", "machete")
	_check(player.get("slot_order") == ["rifle", "stone_axe"], "facão saiu: o machado sobe para o slot 2")
	_key(player, KEY_2)
	_check(str(player.get("melee_weapon")) == "stone_axe", "2 agora pega o machado")
	player.call("remove_weapon", "rifle")
	_check(bool(player.get("weapon_holstered")), "sem arma de fogo fica guardada (não tenta sacar o machado como arma)")
	scene.queue_free()
	await get_tree().process_frame

func _forest() -> void:
	var world: Node3D = SurvivalWorld.new()
	world.set("staged_loading", true)
	add_child(world)
	await world.call("build_staged")
	var count := int(world.get("deep_forest_trees"))
	_check(count > 300, "mata alta tem muitas árvores (%d)" % count)
	var body := world.get_node_or_null("MataAlta") as StaticBody3D
	_check(body != null and body.get_child_count() == count, "cada árvore da mata tem tronco sólido")
	var forest: Dictionary = SurvivalWorld.DEEP_FOREST
	var center := Vector3(float(forest["x"]), 0, float(forest["z"]))
	_check(bool(world.call("in_deep_forest", center)), "centro está na mata")
	var nearest := INF
	if body != null:
		for col in body.get_children():
			var p: Vector3 = (col as CollisionShape3D).position
			nearest = minf(nearest, Vector2(p.x - center.x, p.z - center.z).length())
	_check(nearest < 4.0, "mata fechada no miolo (árvore a %.1f m do centro)" % nearest)
	world.queue_free()
