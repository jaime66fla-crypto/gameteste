extends Node3D
## Cena de demonstração: o personagem anda até a escada, sobe, vira no patamar,
## desce e repete. O corpo segue a rampa invisível pelo meio dos degraus (como
## no jogo) e os pés pisam em cada degrau por IK.
## Abra scenes/previews/stairs_preview.tscn e aperte F6.
## Teclas: 1 liga/desliga os pés no degrau, 2 anda/trota, espaço pausa,
## setas giram a câmera.
## Fotos: godot --path godot res://scenes/previews/stairs_preview.tscn -- --capture=<pasta>
const Stage = preload("res://scripts/previews/preview_stage.gd")
const STEPS := 9
const STEP := 0.2 # altura de cada degrau (igual ao bairro de parkour)
const TREAD := 0.32 # profundidade do degrau
const WIDTH := 1.4
const FLAT_BEFORE := 2.6 # chão antes da escada
const LANDING := 1.8 # patamar no alto
const TURN_TIME := 0.9

var avatar: Node3D
var camera: Camera3D
var hint: Label
var _orbit := 1.25
var _d := -FLAT_BEFORE # distância percorrida na direção da subida
var _dir := 1.0 # 1 subindo, -1 descendo
var _turn := 0.0 # tempo restante virando no fim do trajeto
var _yaw := 0.0
var _jog := false
var _paused := false
var _foot_ik := true

func _ready() -> void:
	camera = Stage.build(self)
	_build_stairs()
	avatar = load("res://scenes/characters/atacante.tscn").instantiate()
	add_child(avatar)
	hint = Stage.hint(self, "")
	await get_tree().process_frame
	avatar.call("set_armed", false)
	avatar.call("set_foot_ik", _foot_ik)
	_update_hint()
	var folder := Stage.capture_folder()
	if not folder.is_empty():
		_capture(folder)

func _run_length() -> float:
	return STEPS * TREAD

func _rise() -> float:
	return STEPS * STEP

## Degraus maciços até o chão, subindo para -Z a partir de z = 0, e o patamar.
func _build_stairs() -> void:
	for k in STEPS:
		var top := (k + 1) * STEP
		Stage.box(self, Vector3(0, top * 0.5, -(k + 0.5) * TREAD), Vector3(WIDTH, top, TREAD), "concrete", Color("#b3b4ab") if k % 2 == 0 else Color("#a6a79e"))
	Stage.box(self, Vector3(0, _rise() * 0.5, -_run_length() - LANDING * 0.5), Vector3(WIDTH + 1.0, _rise(), LANDING), "concrete", Color("#9c9d95"))
	# Parede ao lado (dá referência de altura).
	Stage.box(self, Vector3(-WIDTH * 0.5 - 0.1, 1.6, -_run_length() * 0.5 - 0.6), Vector3(0.2, 3.2, _run_length() + LANDING + 1.2), "concrete", Color("#c9c3b4"))

## Altura do corpo: rampa que passa pelo meio da pisada de cada degrau.
func _height(d: float) -> float:
	return clampf(STEP * (d / TREAD + 0.5), 0.0, _rise())

func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_orbit -= delta * 1.5
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_orbit += delta * 1.5
	if avatar == null or not avatar.has_method("animate"):
		return
	var step := 0.0 if _paused else delta
	var speed := 2.6 if _jog else 1.35
	var moving := false
	if _turn > 0.0:
		_turn = maxf(0.0, _turn - step)
		var target_yaw := 0.0 if _dir > 0.0 else PI
		_yaw = lerp_angle(_yaw, target_yaw, minf(1.0, step * 7.0))
	else:
		_d += _dir * speed * step
		moving = step > 0.0
		var end := _run_length() + LANDING - 0.5
		if _dir > 0.0 and _d >= end:
			_d = end
			_dir = -1.0
			_turn = TURN_TIME
		elif _dir < 0.0 and _d <= -FLAT_BEFORE:
			_d = -FLAT_BEFORE
			_dir = 1.0
			_turn = TURN_TIME
	avatar.rotation.y = _yaw
	avatar.position = Vector3(0, _height(_d), -_d)
	# Velocidade no espaço do personagem (frente = -Z).
	var local_velocity := Vector3(0, 0, -speed) if moving else Vector3.ZERO
	avatar.call("animate", step, 1.0 if moving else 0.0, false, false, false, false, false, Vector2(0, -1), local_velocity)
	var focus := avatar.position + Vector3(0, 1.0, 0)
	camera.position = focus + Vector3(sin(_orbit) * 4.6, 0.9, cos(_orbit) * 4.6)
	camera.look_at(focus)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				_foot_ik = not _foot_ik
				avatar.call("set_foot_ik", _foot_ik)
			KEY_2:
				_jog = not _jog
			KEY_SPACE:
				_paused = not _paused
		_update_hint()

func _update_hint() -> void:
	hint.text = "SUBIR ESCADA  •  %d degraus de %d cm\n[1] pés no degrau: %s   [2] %s   [espaço] %s   [←/→] câmera" % [
		STEPS, roundi(STEP * 100), "LIGADO" if _foot_ik else "desligado", "trotando" if _jog else "andando", "continuar" if _paused else "pausar"]

## Fotos subindo (meio da escada) e descendo, de lado.
func _capture(folder: String) -> void:
	get_window().size = Vector2i(900, 900)
	_orbit = PI * 0.5
	var shots := [[1.4, "escada_1_comeco"], [3.0, "escada_2_meio"], [4.6, "escada_3_patamar"], [8.6, "escada_4_descendo"]]
	var elapsed := 0.0
	for shot in shots:
		while elapsed < float(shot[0]):
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		Stage.save_shot(get_viewport(), folder, str(shot[1]))
	print("fotos salvas em " + folder)
	get_tree().quit(0)
