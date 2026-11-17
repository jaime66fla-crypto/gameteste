extends SceneTree
## Ch31: agachar dobra as pernas (cabeça desce, pés no chão, joelhos à frente) e,
## desarmado, as mãos ficam soltas ao lado do quadril em vez da pose de fuzil.
## godot --headless --path godot --script res://tests/crouch_pose.gd
const Grip = preload("res://scripts/characters/swat_grip.gd")

var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FALHOU: " + what)
	else:
		print("ok: " + what)

func _initialize() -> void:
	_run.call_deferred()

func _pose(avatar: Node3D, frames: int, move: float, crouch: bool) -> void:
	for i in frames:
		avatar.call("animate", 1.0 / 60.0, move, false, crouch, false, false, false, Vector2(0, -1), Vector3(0, 0, -2.0 * move))
		await process_frame

func _y(skel: Skeleton3D, name: String) -> float:
	return skel.get_bone_global_pose(Grip._bone(skel, name)).origin.y

func _p(skel: Skeleton3D, name: String) -> Vector3:
	return skel.get_bone_global_pose(Grip._bone(skel, name)).origin

func _run() -> void:
	var avatar: Node3D = load("res://scenes/characters/avatar.tscn").instantiate()
	root.add_child(avatar)
	await process_frame
	check(bool(avatar.call("is_visual_ready")), "avatar carregado")
	var skel: Skeleton3D = avatar.get("skeleton")
	await _pose(avatar, 40, 0.0, false)
	var stand_head := _y(skel, "Head")
	var stand_foot := _y(skel, "LeftFoot")
	await _pose(avatar, 60, 0.0, true)
	var crouch_head := _y(skel, "Head")
	print("cabeça em pé %.2f, agachado %.2f" % [stand_head, crouch_head])
	check(crouch_head < stand_head - 0.25, "agachado: cabeça desce")
	check(absf(_y(skel, "LeftFoot") - stand_foot) < 0.05, "agachado: pé continua no chão")
	var knee := _p(skel, "LeftLeg")
	var hip := _p(skel, "LeftUpLeg")
	var ankle := _p(skel, "LeftFoot")
	check(knee.z > (hip.z + ankle.z) * 0.5 + 0.08, "agachado: joelho dobra para a frente")
	await _pose(avatar, 40, 1.0, true)
	check(_y(skel, "Head") < stand_head - 0.2, "andando agachado continua baixo")
	await _pose(avatar, 60, 0.0, false)
	check(absf(_y(skel, "Head") - stand_head) < 0.05, "levanta de volta")
	# Armado: mãos juntas na frente (pose de fuzil). Desarmado: soltas ao lado do corpo.
	avatar.call("set_armed", false)
	await _pose(avatar, 60, 1.0, false)
	var hips_y := _y(skel, "Hips")
	var chest_y := _y(skel, "Spine2")
	var left := _p(skel, "LeftHand")
	var right := _p(skel, "RightHand")
	print("mãos: esq %s dir %s  quadril y %.2f  peito y %.2f" % [left, right, hips_y, chest_y])
	check(left.y < chest_y - 0.15 and right.y < chest_y - 0.15, "desarmado: mãos abaixo do peito")
	check(left.distance_to(right) > 0.35, "desarmado: mãos afastadas (não seguram fuzil)")
	# Deitado: corpo na horizontal, cabeça à frente (+Z do modelo) e baixa, pés atrás.
	avatar.call("set_armed", true)
	avatar.call("set_prone", true)
	await _pose(avatar, 90, 0.0, false)
	var head := _p(skel, "Head")
	var foot := _p(skel, "LeftFoot")
	var hips := _p(skel, "Hips")
	print("deitado: cabeça %s  quadril %s  pé %s" % [head, hips, foot])
	check(head.y < 0.75, "deitado: cabeça perto do chão")
	check(hips.y < 0.35, "deitado: quadril no chão")
	check(head.z > hips.z + 0.4 and foot.z < hips.z - 0.4, "deitado: cabeça à frente, pés atrás")
	await _pose(avatar, 40, 1.0, false)
	check(_y(skel, "Head") < 0.8, "rastejando continua deitado")
	avatar.call("set_prone", false)
	await _pose(avatar, 90, 0.0, false)
	check(absf(_y(skel, "Head") - stand_head) < 0.05, "levanta de deitado")
	print("FALHAS: %d" % failures)
	quit(1 if failures else 0)
