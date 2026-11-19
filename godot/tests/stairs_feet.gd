extends Node
## Pés nos degraus da escada do campo de treino (treino offline, a mesma técnica
## das escadas do parkour: degraus na camada dos pés sobre rampa invisível): o jogador
## sobe andando e, a cada quadro, mede a altura de cada tornozelo acima do
## degrau embaixo dele. Com o IK dos pés o pé de apoio fica na altura de quem
## pisa no chão plano e nenhum pé afunda no degrau; sem o IK (controle) os pés
## seguem a rampa invisível e afundam/flutuam.
## godot --headless --path godot res://tests/stairs_feet.tscn
const Grip = preload("res://scripts/characters/swat_grip.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Net.in_match = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(10)
	var player: CharacterBody3D = main.get("player")
	var avatar: Node3D = player.get("humanoid_avatar")
	var stairs := main.find_children("StairSteps", "", true, false)
	check(not stairs.is_empty(), "as escadas têm degraus para os pés (%d escadas)" % stairs.size())
	if stairs.is_empty():
		get_tree().quit(1)
		return
	# Uma escada longa: do primeiro ao último degrau.
	var best: Node3D = null
	var best_len := 0.0
	for s in stairs:
		var shapes := (s as Node3D).get_children()
		var length := (shapes[0] as Node3D).global_position.distance_to((shapes[-1] as Node3D).global_position)
		if length > best_len:
			best_len = length
			best = s
	var shapes := best.get_children()
	var first: Vector3 = (shapes[0] as Node3D).global_position
	var last: Vector3 = (shapes[-1] as Node3D).global_position
	var dir := last - first
	dir.y = 0.0
	dir = dir.normalized()
	print("escada de %d degraus, %.1f m" % [shapes.size(), best_len])
	var flat := await _ankle_on_flat(player, avatar)
	print("tornozelo no chão plano: %.3f m" % flat)
	var with_ik: Dictionary = await _climb(player, avatar, first, dir, true)
	var without: Dictionary = await _climb(player, avatar, first, dir, false)
	print("com IK: apoio %.3f m (chão plano %.3f), mais fundo %.3f m, %d quadros na escada" % [with_ik["stance"], flat, with_ik["deepest"], with_ik["frames"]])
	print("sem IK: apoio %.3f m, mais fundo %.3f m" % [without["stance"], without["deepest"]])
	check(int(with_ik["frames"]) > 30, "o jogador subiu a escada andando (%d quadros nos degraus)" % with_ik["frames"])
	check(absf(float(with_ik["stance"]) - flat) < 0.05, "com IK o pé de apoio pisa no degrau como no chão (%.3f x %.3f)" % [with_ik["stance"], flat])
	# Pé afundado mais de 6 cm no degrau (tornozelo abaixo do normal).
	var sunk_ik := _share_below(with_ik["lows"], flat - 0.06)
	var sunk_off := _share_below(without["lows"], flat - 0.06)
	print("pé afundado > 6 cm: com IK %.0f%% dos quadros, sem IK %.0f%%" % [sunk_ik * 100.0, sunk_off * 100.0])
	# O pé no ar ainda raspa a quina por alguns quadros ao passar de degrau (sem IK: ~73%).
	check(sunk_ik < 0.15, "com IK o pé raramente afunda no degrau (%.0f%% dos quadros)" % (sunk_ik * 100.0))
	check(absf(float(without["stance"]) - flat) > absf(float(with_ik["stance"]) - flat) or float(without["deepest"]) < float(with_ik["deepest"]), "sem IK é pior (o teste mede algo real)")
	print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures else 0)

func _feet(avatar: Node3D) -> Array:
	var sk: Skeleton3D = avatar.get("skeleton")
	var out := []
	for side in ["Left", "Right"]:
		var b := Grip._bone(sk, side + "Foot")
		out.append(sk.global_transform * sk.get_bone_global_pose(b).origin)
	return out

func _ground_under(p: Vector3) -> float:
	var space := get_viewport().world_3d.direct_space_state
	for mask in [8, 1]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.8, 0), p - Vector3(0, 1.5, 0), mask))
		if not hit.is_empty():
			return (hit["position"] as Vector3).y
	return -INF

func _ankle_on_flat(player: CharacterBody3D, avatar: Node3D) -> float:
	player.global_position = Vector3(12, 0.1, -10)
	await _frames(30)
	var lows := []
	for i in 30:
		await _frames(1)
		var feet := _feet(avatar)
		lows.append(minf(feet[0].y - _ground_under(feet[0]), feet[1].y - _ground_under(feet[1])))
	return _mean(lows)

## Sobe a escada andando (W) e mede: pé mais baixo acima do seu degrau (apoio)
## e o tornozelo mais fundo em relação ao degrau embaixo dele.
func _climb(player: CharacterBody3D, avatar: Node3D, first: Vector3, dir: Vector3, ik: bool) -> Dictionary:
	avatar.call("set_foot_ik", ik)
	player.global_position = first - dir * 2.0 + Vector3(0, 0.2, 0)
	player.set("yaw", atan2(-dir.x, -dir.z))
	player.set("pitch", 0.0)
	await _frames(30)
	Input.action_press("move_forward")
	var stance := []
	var deepest := INF
	var frames := 0
	var lows := []
	for i in 360:
		await _frames(1)
		var feet := _feet(avatar)
		var on_steps := true
		var heights := []
		for f in feet:
			var g := _ground_under(f)
			heights.append(f.y - g)
		# Só conta enquanto os dois pés estão sobre degraus (não no chão nem no patamar).
		var space := get_viewport().world_3d.direct_space_state
		for f in feet:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(f + Vector3(0, 0.8, 0), f - Vector3(0, 1.5, 0), 8))
			if hit.is_empty():
				on_steps = false
		if not on_steps or not player.is_on_floor():
			continue
		frames += 1
		stance.append(minf(heights[0], heights[1]))
		deepest = minf(deepest, minf(heights[0], heights[1]))
		lows.append(minf(heights[0], heights[1]))
	Input.action_release("move_forward")
	avatar.call("set_foot_ik", true)
	await _frames(10)
	return {"stance": _median(stance), "deepest": deepest, "frames": frames, "lows": lows}

func _share_below(values: Array, limit: float) -> float:
	var n := 0
	for v in values:
		if float(v) < limit:
			n += 1
	return float(n) / maxf(1.0, values.size())

func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total / maxf(1.0, values.size())

func _median(values: Array) -> float:
	if values.is_empty():
		return INF
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])
