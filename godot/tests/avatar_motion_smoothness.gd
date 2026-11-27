extends SceneTree
## Transições do 01 sem "tranco" a 60 fps: corrida -> sprint -> pulo no
## sprint -> pouso -> freio -> pulo parado -> pouso, sem arma e com fuzil.
## Mede o maior salto de cabeça, mãos e pés entre dois quadros (no espaço do
## personagem, que fica no lugar) e compara com o próprio ciclo de sprint:
## nenhuma transição pode pular mais que o passo mais rápido do sprint.
const Registry = preload("res://scripts/characters/character_registry.gd")
const DT := 1.0 / 60.0
const GRAVITY := 22.0
const JUMP := 8.5
const JOINTS := ["Head", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]
var failures: Array[String] = []
var avatar: Node3D
var skeleton: Skeleton3D
var prefix := ""
var previous := {}
var worst := {} # fase -> [salto (m), osso, quadro]
var frame := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	print(("ok: " if ok else "FALHOU: ") + message)
	if not ok:
		failures.append(message)

func _sample(phase: String) -> void:
	for joint in JOINTS:
		var p := skeleton.get_bone_global_pose(skeleton.find_bone(prefix + joint)).origin * skeleton.global_basis.get_scale()
		if previous.has(joint):
			var jump: float = (p - previous[joint]).length()
			if not worst.has(phase) or jump > worst[phase][0]:
				worst[phase] = [jump, joint, frame]
		previous[joint] = p

func _play(phase: String, frames: int, running: bool, planar: Vector3, air_from: int = -1) -> void:
	for i in frames:
		var velocity := planar
		var airborne := false
		if air_from >= 0 and i >= air_from:
			var t := (i - air_from) * DT
			velocity.y = JUMP - GRAVITY * t
			airborne = JUMP * t - 0.5 * GRAVITY * t * t > 0.0
		var move := 1.0 if Vector2(planar.x, planar.z).length() > 0.1 else 0.0
		avatar.call("animate", DT, move, running, false, false, airborne, false, Vector2(0, -1), velocity)
		frame += 1
		_sample(phase)

func _sequence(label: String) -> Dictionary:
	worst.clear()
	previous.clear()
	_play(label + " corrida", 60, false, Vector3(0, 0, -5))
	_play(label + " sprint (ciclo)", 90, true, Vector3(0, 0, -8))
	_play(label + " pulo no sprint", 70, true, Vector3(0, 0, -8), 0)
	_play(label + " volta ao sprint", 40, true, Vector3(0, 0, -8))
	_play(label + " freio", 60, false, Vector3.ZERO)
	_play(label + " pulo parado", 70, false, Vector3.ZERO, 0)
	_play(label + " parado", 40, false, Vector3.ZERO)
	return worst.duplicate(true)

func _run() -> void:
	avatar = Registry.create_visual("atacante")
	root.add_child(avatar)
	await process_frame
	skeleton = avatar.get("skeleton")
	prefix = avatar.get("bone_prefix")
	for armed in [false, true]:
		var label := "fuzil" if armed else "sem arma"
		avatar.call("set_armed", armed)
		if armed:
			avatar.call("configure_weapon", "rifle", 1.0)
		var result := _sequence(label)
		# Referência: o passo mais rápido do próprio ciclo de corrida/sprint.
		var reference: float = maxf(result[label + " sprint (ciclo)"][0], result[label + " corrida"][0])
		for phase in result:
			var w: Array = result[phase]
			print("%-26s maior salto %.3f m (%s, quadro %d)" % [phase, w[0], w[1], w[2]])
			if phase.ends_with("(ciclo)") or phase.ends_with("corrida"):
				continue
			_check(w[0] <= reference * 1.15, "%s: sem tranco (%.3f m <= %.3f m do ciclo)" % [phase, w[0], reference * 1.15])
	print("AVATAR MOTION SMOOTHNESS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
