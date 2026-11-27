extends SceneTree
## Clipes do addon real-controller no 01: sem arma, Shift a 8 m/s toca o
## sprint_unarmed (não a corrida acelerada); com fuzil continua run_in_place.
## No ar sem arma pernas/tronco do pulo HumanM (braços do clipe só 15%); com fuzil
## só as pernas, como antes.
const Registry = preload("res://scripts/characters/character_registry.gd")
const DT := 1.0 / 60.0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print(("ok: " if ok else "FALHOU: ") + message)
	if not ok:
		failures.append(message)

func _step(avatar: Node, frames: int, running: bool, velocity: Vector3, airborne: bool) -> void:
	for i in frames:
		avatar.call("animate", DT, 1.0 if Vector2(velocity.x, velocity.z).length() > 0.1 else 0.0, running, false, false, airborne, false, Vector2(0, -1), velocity)

## Quanto as mãos ficam abaixo dos ombros (m, a pior das duas; correndo, o braço
## da frente fica na altura do peito, ~0,2 m). O pulo puro do
## HumanM levanta as mãos na altura do ombro ou acima (Y/cruz, visto de frente).
func _hands_below_shoulders(avatar: Node) -> float:
	var sk: Skeleton3D = avatar.get("skeleton")
	var p: String = avatar.get("bone_prefix")
	var worst := INF
	for side in ["Left", "Right"]:
		var hand := sk.get_bone_global_pose(sk.find_bone(p + side + "Hand")).origin
		var shoulder := sk.get_bone_global_pose(sk.find_bone(p + side + "Arm")).origin
		worst = minf(worst, shoulder.y - hand.y)
	return worst

func _run() -> void:
	var avatar := Registry.create_visual("atacante")
	root.add_child(avatar)
	await process_frame
	_check(bool(avatar.call("is_visual_ready")), "avatar pronto")
	var player: AnimationPlayer = avatar.get("animation_player")
	_check(player.has_animation("sprint_unarmed"), "sprint_unarmed carregado")
	var ual: Dictionary = avatar.get("ual_clips")
	_check(ual.has("jump_unarmed_start") and ual.has("fall_unarmed") and ual.has("land_unarmed"), "pulo/queda/pouso HumanM carregados")

	avatar.call("set_armed", false)
	_step(avatar, 40, true, Vector3(0, 0, -8.0), false)
	_check(str(avatar.get("current_clip")) == "sprint_unarmed", "sem arma, Shift 8 m/s: sprint_unarmed (%s)" % avatar.get("current_clip"))
	_step(avatar, 40, false, Vector3(0, 0, -5.0), false)
	_check(str(avatar.get("current_clip")) == "run_in_place", "sem arma, 5 m/s sem Shift: run_in_place (%s)" % avatar.get("current_clip"))
	_step(avatar, 40, true, Vector3(0, 0, -8.0), false)
	_step(avatar, 2, true, Vector3.ZERO, false)
	_check(str(avatar.get("current_clip")) == "run_to_stop", "parar do sprint freia (%s)" % avatar.get("current_clip"))

	# Pulo no sprint: no ar o passo continua por baixo (não troca para o freio).
	_step(avatar, 40, true, Vector3(0, 0, -8.0), false)
	_step(avatar, 1, true, Vector3(0, 8.5, -8.0), true)
	_step(avatar, 20, true, Vector3(0, 0.0, -8.0), true)
	_check(str(avatar.get("current_clip")) == "sprint_unarmed", "no ar do sprint segue o passo, sem freio (%s)" % avatar.get("current_clip"))
	_check(float(player.speed_scale) < 0.3, "no ar o passo quase para (ritmo %.2f)" % player.speed_scale)
	_step(avatar, 30, true, Vector3(0, 0, -8.0), false)
	_check(str(avatar.get("current_clip")) == "sprint_unarmed" and player.speed_scale > 1.0, "pousa de volta no sprint (ritmo %.2f)" % player.speed_scale)

	# Pulo sem arma: pula a 8,5 m/s; no meio do voo, na queda.
	_step(avatar, 30, false, Vector3(0, 0, -5.0), false)
	_step(avatar, 1, false, Vector3(0, 8.5, -5.0), true)
	_step(avatar, 30, false, Vector3(0, 0.0, -5.0), true)
	for i in 3:
		_check(_hands_below_shoulders(avatar) > 0.1, "no ar sem arma (%.2f s) mãos bem abaixo dos ombros, sem Y/T (%.2f m)" % [0.5 + i * 0.1, _hands_below_shoulders(avatar)])
		_step(avatar, 6, false, Vector3(0, 0.0, -5.0), true)
	if bool(avatar.get("clean_locomotion")):
		# Soldados (controlador do Linha de Fogo): pulo pelo clipe "jump" da UAL.
		_check(float(avatar.get("_clean_air")) > 0.9, "pulo do Linha de Fogo ativo (%.2f)" % float(avatar.get("_clean_air")))
		_step(avatar, 60, false, Vector3(0, 0, -5.0), false)
		_check(float(avatar.get("_clean_air")) < 0.01, "pulo termina ao pousar (%.2f)" % float(avatar.get("_clean_air")))
	else:
		_check(float(avatar.get("_air_weight")) > 0.9, "camada do ar ativa (%.2f)" % float(avatar.get("_air_weight")))
		_step(avatar, 1, false, Vector3(0, 0, -5.0), false)
		_check(bool(avatar.get("_land_full")) and float(avatar.get("_land_time")) >= 0.0, "pouso HumanM sem arma")
		_step(avatar, 60, false, Vector3(0, 0, -5.0), false)
		_check(float(avatar.get("_land_time")) < 0.0, "pouso termina")

	# Com fuzil: Shift continua na corrida armada e o pulo segue só nas pernas.
	avatar.call("set_armed", true)
	avatar.call("configure_weapon", "rifle", 1.0)
	_step(avatar, 40, true, Vector3(0, 0, -8.0), false)
	_check(str(avatar.get("current_clip")) == "run_in_place", "fuzil, Shift: run_in_place (%s)" % avatar.get("current_clip"))
	_check(not bool(avatar.call("_air_full_body")), "fuzil: pulo só nas pernas")

	print("AVATAR SPRINT JUMP: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
