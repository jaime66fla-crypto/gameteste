extends SceneTree
## Treino offline: construção da Sobrevivência sem servidor e com material
## infinito (scripts/training_build.gd). Monta fundação, parede e piso pelas
## regras de verdade, abre a porta e desmonta a fundação (cai o que ela segurava).
## godot --headless --path godot --script res://tests/training_build.gd
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _put(ctl: Node, piece: Dictionary) -> void:
	var rules = ctl.get("rules")
	var err: String = rules.check(piece, Callable(ctl, "owns"))
	_check(err.is_empty(), "%s pode ser construído (%s)" % [piece["kind"], err])
	_check(str(ctl.call("_missing", str(piece["kind"]))).is_empty(), "%s não pede material no treino" % piece["kind"])
	ctl.set("_candidate", piece)
	ctl.set("_candidate_error", "")
	ctl.call("_place_selected")

func _run() -> void:
	root.get_node("Net").set("in_match", false)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player: CharacterBody3D = scene.get_node("Jaime")
	player.set_physics_process(false)
	await physics_frame
	await process_frame
	var training: Node = scene.get_node_or_null("TrainingBuild")
	_check(training != null, "o treino tem o modo de construção")
	if training == null:
		_finish()
		return
	var ctl: Node = training.get("building_ctl")
	_check(bool(ctl.get("offline")), "construção do treino é offline")
	ctl.call("set_building", true)
	await process_frame
	_check(bool(player.get("weapon_holstered")), "a arma é guardada no modo de construção")
	_put(ctl, {"kind": "foundation", "i": 20, "j": 20, "k": 0})
	_put(ctl, {"kind": "foundation", "i": 21, "j": 20, "k": 0})
	_put(ctl, {"kind": "wall", "i": 20, "j": 20, "k": 0, "o": "h"})
	_put(ctl, {"kind": "doorway", "i": 21, "j": 20, "k": 0, "o": "h"})
	_put(ctl, {"kind": "door", "i": 21, "j": 20, "k": 0, "o": "h", "r": 0})
	_put(ctl, {"kind": "floor", "i": 20, "j": 20, "k": 1, "r": 0})
	var rules = ctl.get("rules")
	await physics_frame
	await physics_frame
	# Rampa de acesso da porta do térreo: fora do vão (z < 60) o chão sobe de 0 até a fundação.
	var space := player.get_world_3d().direct_space_state
	var door_x: float = (21 + 0.5) * float(rules.S)
	var edge_z: float = 20 * float(rules.S)
	var heights: Array[float] = []
	for dz in [1.2, 0.8, 0.4, 0.1]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(door_x, 3, edge_z - dz), Vector3(door_x, -1, edge_z - dz))
		var hit := space.intersect_ray(q)
		heights.append(float(hit["position"].y) if not hit.is_empty() else -9.0)
	_check(heights[0] > 0.0 and heights[0] < 0.12, "a rampa começa rente ao chão (%.2f)" % heights[0])
	_check(heights[1] < heights[2] and heights[2] < heights[3], "a rampa sobe até a porta (%s)" % str(heights))
	_check(absf(heights[3] - float(rules.base)) < 0.08, "a rampa chega na altura da fundação (%.2f)" % heights[3])
	_check(rules.pieces.size() == 6, "6 peças montadas (%d)" % rules.pieces.size())
	_check((ctl.get("nodes") as Dictionary).size() == 6, "6 peças desenhadas")
	var door_id := ""
	for id in rules.pieces:
		if str(rules.pieces[id]["kind"]) == "door":
			door_id = id
	ctl.call("interact", door_id)
	_check(bool(rules.pieces[door_id].get("open", false)), "E abre a porta no treino")
	var found_id := ""
	for id in rules.pieces:
		var p: Dictionary = rules.pieces[id]
		if str(p["kind"]) == "foundation" and int(p["i"]) == 20:
			found_id = id
	ctl.call("_offline_remove", found_id)
	await process_frame
	# Sem a fundação 20: some a parede dela e o piso (apoiado só na parede).
	_check(rules.pieces.size() == 3, "desmontar a fundação derruba o que ela segurava (sobraram %d)" % rules.pieces.size())
	# Barra do B só com estrutura; estações e móveis saem da bancada.
	var order: Array = ctl.get("ORDER")
	for kind in ["campfire", "chest", "bed", "forge", "workshop", "chem_table"]:
		_check(not order.has(kind), "%s não aparece na barra do B" % kind)
	_check(order.has("foundation") and order.has("workbench"), "a barra tem estrutura e a bancada")
	var bench_spot := player.global_position + Vector3(2, 0, 0)
	_put(ctl, {"kind": "workbench", "p": [bench_spot.x, 0.0, bench_spot.z], "y": 0.0})
	var bench_id := ""
	for id in rules.pieces:
		if str(rules.pieces[id]["kind"]) == "workbench":
			bench_id = id
	_check(not bench_id.is_empty(), "a bancada foi montada")
	ctl.call("set_building", false)
	ctl.call("interact", bench_id)
	_check(bool(ctl.call("ui_open")), "E na bancada abre a janela da bancada")
	_check((ctl.get("_bench_grid") as Node).get_child_count() == 6, "a bancada lista 6 peças")
	ctl.call("pick_bench", "campfire")
	_check(bool(ctl.get("building")) and str(ctl.call("selected_kind")) == "campfire", "escolher na bancada entra no modo com a fogueira")
	_check(not bool(ctl.call("ui_open")), "a janela fecha ao escolher")
	_put(ctl, {"kind": "campfire", "p": [bench_spot.x + 3.0, 0.0, bench_spot.z], "y": 0.0})
	var fires := 0
	for id in rules.pieces:
		if str(rules.pieces[id]["kind"]) == "campfire":
			fires += 1
	_check(fires == 1, "a fogueira da bancada foi montada")
	# Baú no treino: E abre o inventário com o baú; guardar e pegar movem a pilha.
	var chest_spot := player.global_position + Vector3(-2, 0, 0)
	ctl.set("bench_pick", "chest")
	_put(ctl, {"kind": "chest", "p": [chest_spot.x, 0.0, chest_spot.z], "y": 0.0})
	var chest_id := ""
	for id in rules.pieces:
		if str(rules.pieces[id]["kind"]) == "chest":
			chest_id = id
	_check(not chest_id.is_empty(), "o baú foi montado no treino")
	var inv_ui: Control = training.get("inventory")
	ctl.call("interact", chest_id)
	_check(inv_ui.visible and str(inv_ui.get("container_id")) == chest_id, "E no baú abre o inventário com o baú")
	var inv: Dictionary = training.get("inv")
	var wood := int(inv.get("wood", 0))
	inv_ui.emit_signal("store_requested", chest_id, "wood")
	_check(not inv.has("wood") and int(rules.pieces[chest_id]["items"].get("wood", 0)) == wood, "guardar leva a madeira para o baú")
	inv_ui.emit_signal("take_requested", chest_id, "wood", true)
	_check(int(inv.get("wood", 0)) == wood and not rules.pieces[chest_id]["items"].has("wood"), "pegar traz a madeira de volta")
	inv_ui.call("close")
	training.call("open_manual", "chem_table")
	_check((training.get("manual") as Control).visible, "o manual abre no treino")
	(training.get("manual") as Control).call("close")
	# Tocha: acesa na mão, fincada no chão e presa numa parede (sai da mochila).
	training.call("set_torch", true)
	_check(player.get_node_or_null("HandTorch") != null, "a tocha acende na mão")
	await process_frame
	var hand := player.get_node_or_null("HandTorch") as Node3D
	_check(hand != null and hand.global_position.distance_to(player.global_position) < 2.5, "a tocha da mão fica junto do corpo")
	_check(hand != null and hand.find_child("TorchLight", true, false) != null, "a tocha da mão ilumina")
	var torches := int(inv.get("torch", 0))
	ctl.set("bench_pick", "torch")
	_put(ctl, {"kind": "torch", "p": [chest_spot.x + 2.0, 0.0, chest_spot.z], "y": 0.0})
	_put(ctl, {"kind": "foundation", "i": 30, "j": 30, "k": 0})
	_put(ctl, {"kind": "wall", "i": 30, "j": 30, "k": 0, "o": "h"})
	var wall_z: float = 30 * float(rules.S) - 0.12
	_put(ctl, {"kind": "torch", "wall": true, "p": [30.5 * float(rules.S), float(rules.base) + 1.6, wall_z], "y": PI})
	var lit := 0
	for id in rules.pieces:
		if str(rules.pieces[id]["kind"]) == "torch":
			lit += 1
			_check((ctl.get("nodes")[id] as Node).get_node_or_null("FireLight") != null, "a tocha colocada tem luz")
	_check(lit == 2, "duas tochas colocadas, chão e parede (%d)" % lit)
	_check(int(inv.get("torch", 0)) == torches - 2, "cada tocha colocada sai da mochila")
	training.call("set_torch", false)
	await process_frame
	_check(player.get_node_or_null("HandTorch") == null or player.get_node("HandTorch").is_queued_for_deletion(), "a tocha da mão apaga")
	ctl.call("cycle", 1)
	_check(str(ctl.call("selected_kind")) in order, "trocar de peça volta para a barra de estrutura")
	ctl.call("set_building", false)
	await process_frame
	_check(not bool(player.get("weapon_holstered")), "a arma volta ao sair do modo de construção")
	_finish()

func _finish() -> void:
	for f in failures:
		printerr("FAIL: ", f)
	print("TRAINING BUILD: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
