extends SceneTree
## Soco contra o ataque do zumbi: o jogador fica parado e soca (Q) assim que o
## zumbi entra no alcance do soco. Cada soco que acerta faz o zumbi recuar e
## perder o bote (zombie.stagger, aplicado pelo anfitrião quando o servidor
## confirma o dano, aqui com 0,15 s de atraso de rede). Resultado esperado:
## nenhum zumbi morde. Controle: sem o recuo, o mesmo zumbi morde.
## godot --headless --path godot --script res://tests/zombie_punch.gd
const ZombieScript = preload("res://scripts/survival/zombie.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const PUNCH_REACH := 2.4 # survival_controller._melee: alcance do soco (sem arma branca)
const MELEE_COOLDOWN := 0.6 # survival_controller.MELEE_COOLDOWN
const NET_DELAY := 0.15 # ida e volta até o servidor confirmar o acerto
const DURATION := 8.0

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.6, 5)
	camera.current = true
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	for kind in ["walker", "runner", "brute"]:
		var result: Dictionary = await _duel(kind, true)
		print("%s com recuo: %d socos acertaram, %d mordidas, mais perto %.2f m" % [kind, result["hits"], result["bites"], result["closest"]])
		check(int(result["hits"]) >= 3, "%s: o soco acerta o zumbi de longe (%d acertos)" % [kind, result["hits"]])
		check(int(result["bites"]) == 0, "%s: socando, o zumbi não consegue morder (%d mordidas)" % [kind, result["bites"]])
		check(float(result["closest"]) > float(ZombieScript.ATTACK_RANGE), "%s: o zumbi nunca chega ao alcance do bote (%.2f m > %.2f m)" % [kind, result["closest"], ZombieScript.ATTACK_RANGE])
	var control: Dictionary = await _duel("walker", false)
	print("walker sem recuo (antes): %d socos, %d mordidas" % [control["hits"], control["bites"]])
	check(int(control["bites"]) > 0, "controle: sem o recuo o zumbi morde (o teste mede algo real)")
	for kind in ["walker", "runner", "brute"]:
		var gap: Dictionary = await _opening(kind)
		print("%s brecha: parado %.2f s depois do bote (andou %.2f m), soco na brecha: %s, mordidas depois: %d" % [kind, gap["still"], gap["moved"], gap["landed"], gap["later_bites"]])
		check(float(gap["still"]) >= float(ZombieScript.RECOVER_TIME) * 0.5 - 0.05 and float(gap["moved"]) < 0.05, "%s: depois do bote fica parado (brecha de %.2f s)" % [kind, gap["still"]])
		check(bool(gap["landed"]), "%s: o soco na brecha acerta" % kind)
		check(int(gap["later_bites"]) == 0, "%s: socando na brecha, não morde de novo" % kind)
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)

## Jogador colado (1 m), sem socar: o zumbi dá o bote. Na recuperação depois do
## bote ele fica parado; o jogador soca nessa brecha e continua socando.
func _opening(kind: String) -> Dictionary:
	var player := Node3D.new()
	root.add_child(player)
	var z: CharacterBody3D = ZombieScript.new()
	z.call("setup", "o_" + kind, kind, 999)
	root.add_child(z)
	z.global_position = Vector3(0, 0, -1.0)
	z.call("set_controlled", true)
	z.set("targets", func(): return [{"id": "p", "node": player}])
	z.rotation.y = PI
	z.set("_target", player)
	z.set("_target_id", "p")
	var state := {"bites": 0}
	z.connect("attacked", func(_zid, _tid): state["bites"] += 1)
	var result := {"still": 0.0, "moved": 0.0, "landed": false, "later_bites": 0}
	var dt := 1.0 / Engine.physics_ticks_per_second
	var elapsed := 0.0
	# 1) espera o bote terminar e a recuperação começar.
	while float(z.get("recover_left")) <= 0.0 and elapsed < 4.0:
		await physics_frame
		elapsed += dt
	var start := z.global_position
	var bites_before := int(state["bites"])
	# 2) mede quanto tempo fica parado; soca na metade da brecha.
	var punched := false
	var pending := -1.0
	var cooldown := 0.0
	while elapsed < 9.0:
		await physics_frame
		elapsed += dt
		cooldown = maxf(0.0, cooldown - dt)
		if float(z.get("recover_left")) > 0.0 and not punched:
			result["still"] = float(result["still"]) + dt
			result["moved"] = maxf(float(result["moved"]), Vector2(z.global_position.x - start.x, z.global_position.z - start.z).length())
		if pending >= 0.0:
			pending -= dt
			if pending < 0.0:
				z.call("stagger", player.global_position)
		var flat := Vector2(z.global_position.x, z.global_position.z).length()
		var in_gap := float(z.get("recover_left")) > 0.0 and float(z.get("recover_left")) < float(ZombieScript.RECOVER_TIME) * 0.5
		if cooldown <= 0.0 and flat <= PUNCH_REACH and (punched or in_gap):
			cooldown = MELEE_COOLDOWN
			var from := player.global_position + Vector3(0, 1.35, 0)
			var dir := z.global_position - player.global_position
			dir.y = 0.0
			var query := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * PUNCH_REACH, HitboxScript.SHOT_MASK)
			query.hit_from_inside = true # igual a survival_controller._melee
			var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and (hit["collider"] as Object).get("actor") == z:
				if not punched:
					result["landed"] = true
				punched = true
				pending = NET_DELAY
	result["later_bites"] = int(state["bites"]) - bites_before
	z.queue_free()
	player.queue_free()
	await process_frame
	return result

## Um zumbi a 7 m vem atrás do jogador parado na origem.
func _duel(kind: String, with_stagger: bool) -> Dictionary:
	var player := Node3D.new()
	root.add_child(player)
	var z: CharacterBody3D = ZombieScript.new()
	z.call("setup", "t_" + kind, kind, 999)
	root.add_child(z)
	z.global_position = Vector3(0, 0, -7)
	z.call("set_controlled", true)
	z.set("targets", func(): return [{"id": "p", "node": player}])
	# Já viu o jogador e vem atrás dele.
	z.rotation.y = PI
	z.set("_target", player)
	z.set("_target_id", "p")
	var state := {"bites": 0, "hits": 0, "closest": INF}
	z.connect("attacked", func(_zid, _tid): state["bites"] += 1)
	var cooldown := 0.0
	var pending: Array = [] # atrasos dos recuos ainda a caminho
	var elapsed := 0.0
	await physics_frame
	while elapsed < DURATION:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		elapsed += dt
		cooldown = maxf(0.0, cooldown - dt)
		var flat := Vector2(z.global_position.x, z.global_position.z).length()
		state["closest"] = minf(state["closest"], flat)
		if OS.has_environment("ZP_TRACE") and int(elapsed * 60) % 6 == 0:
			print("t=%.2f d=%.2f stagger=%.2f strike=%.2f atk=%.2f vel=%s" % [elapsed, flat, float(z.get("stagger_left")), float(z.get("strike_t")), float(z.get("_attack_timer")), str(z.velocity)])
		for i in range(pending.size() - 1, -1, -1):
			pending[i] -= dt
			if pending[i] <= 0.0:
				pending.remove_at(i)
				if with_stagger:
					z.call("stagger", player.global_position)
		if cooldown <= 0.0 and flat <= PUNCH_REACH:
			cooldown = MELEE_COOLDOWN
			# Mesmo raio do jogo: peito do jogador para a frente, alcance do soco.
			var from := player.global_position + Vector3(0, 1.35, 0)
			var to_zombie := z.global_position - player.global_position
			to_zombie.y = 0.0
			var query := PhysicsRayQueryParameters3D.create(from, from + to_zombie.normalized() * PUNCH_REACH, HitboxScript.SHOT_MASK)
			query.hit_from_inside = true # igual a survival_controller._melee
			var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and (hit["collider"] as Object).get("actor") == z:
				state["hits"] += 1
				pending.append(NET_DELAY)
	z.queue_free()
	player.queue_free()
	await process_frame
	return state
