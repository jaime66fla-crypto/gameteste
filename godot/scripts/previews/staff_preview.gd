extends Node3D
## Cena de demonstração: golpe lateral com o bastão longo no boneco de treino,
## com o dano do jogo. O acerto usa a mesma regra da Sobrevivência: um raio na
## altura do peito (1,35 m) até o alcance da arma, nas hitboxes do boneco, e o
## dano da arma em data/survival_items.json (×1,5 na cabeça, como o servidor).
## Abra scenes/previews/staff_preview.tscn e aperte F6.
## Teclas: 1 bastão longo, 2 taco, 3 pé de cabra, 4 machado; ↑/↓ afasta ou
## aproxima o boneco (fora do alcance o golpe erra); espaço pausa; ←/→ câmera.
## Fotos: godot --path godot res://scenes/previews/staff_preview.tscn -- --capture=<pasta>
const Stage = preload("res://scripts/previews/preview_stage.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const DummyScript = preload("res://scripts/training_dummy.gd")
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const SWING_CYCLE := 0.55 # igual ao "swing" do avatar e ao SWING_TIME da Sobrevivência
const IMPACT_AT := 0.48 # fração do golpe em que o bastão passa na frente do corpo
const REPEAT := 1.35 # um golpe a cada REPEAT segundos
const WEAPONS := ["long_bat", "bat", "crowbar", "axe"]

var avatar: Node3D
var camera: Camera3D
var dummy: Node3D
var sound: Node
var hint: Label
var weapon := "long_bat"
var distance := 1.8
var _orbit := 0.75
var _clock := 0.0
var _struck := false
var _paused := false
var last_result := ""
var _camera_locked := false # fotos de perto

func _ready() -> void:
	camera = Stage.build(self)
	avatar = load("res://scenes/characters/avatar.tscn").instantiate()
	add_child(avatar)
	dummy = DummyScript.new()
	dummy.set("title", "BONECO DE TREINO")
	add_child(dummy)
	dummy.rotation.y = PI # de frente para o personagem
	sound = SoundFXScript.new()
	sound.set("spatial_audio", false)
	add_child(sound)
	hint = Stage.hint(self, "")
	await get_tree().process_frame
	avatar.call("set_armed", false)
	_place_dummy()
	_start_swing()
	var folder := Stage.capture_folder()
	if not folder.is_empty():
		_capture(folder)

func _place_dummy() -> void:
	dummy.position = Vector3(0, 0, -distance)
	# O NetActor do boneco segue target_position (posição de rede): sem isto ele volta à origem.
	var actor := dummy.get("actor") as Node3D
	actor.set("target_position", actor.global_position)
	_update_hint()

func _start_swing() -> void:
	_clock = 0.0
	_struck = false
	avatar.call("set_action", "", "")
	avatar.call("set_action", "swing", weapon)
	sound.call("melee_swing")

func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_orbit -= delta * 1.5
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_orbit += delta * 1.5
	if not _camera_locked:
		var focus := Vector3(0, 1.1, -distance * 0.5)
		camera.position = focus + Vector3(sin(_orbit) * 4.4, 0.6, cos(_orbit) * 4.4)
		camera.look_at(focus)
	if avatar == null or not avatar.has_method("animate"):
		return
	var step := 0.0 if _paused else delta
	avatar.call("animate", step, 0.0, false, false, false, false, false)
	if _paused:
		return
	_clock += step
	if not _struck and _clock >= SWING_CYCLE * IMPACT_AT:
		_struck = true
		_strike()
	if _clock >= REPEAT:
		_start_swing()

## Mesmo teste da Sobrevivência (survival_controller._melee): raio do peito
## para a frente até o alcance da arma, só mundo e hitboxes.
func _strike() -> void:
	var entry := SurvivalData.item(weapon)
	var reach := float(entry.get("reach", 2.4))
	var forward := -avatar.global_basis.z
	var from := avatar.global_position + Vector3(0, 1.35, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * reach, HitboxScript.SHOT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var body: Object = hit.get("collider")
	if hit.is_empty() or body == null or body.get("actor") == null:
		last_result = "errou"
		dummy.call("_show", "ERROU: fora do alcance (%.1f m)" % reach)
		return
	var zone := str(body.get("zone"))
	var damage := float(entry.get("melee", 9)) * (1.5 if zone == "head" else 1.0)
	last_result = "%s %d" % [zone, roundi(damage)]
	print("golpe: %s acertou %s, dano %d" % [weapon, zone, roundi(damage)])
	dummy.call("melee_hit", damage, str(entry.get("name", weapon)).to_upper(), zone, hit["position"], hit["normal"])
	sound.call("melee_impact", zone == "head")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			weapon = WEAPONS[event.physical_keycode - KEY_1]
			_start_swing()
		KEY_UP:
			distance = minf(distance + 0.4, 4.2)
			_place_dummy()
		KEY_DOWN:
			distance = maxf(distance - 0.4, 1.0)
			_place_dummy()
		KEY_SPACE:
			_paused = not _paused
	_update_hint()

func _update_hint() -> void:
	var entry := SurvivalData.item(weapon)
	hint.text = "GOLPE COM ARMA BRANCA  •  %s: dano %d (cabeça ×1,5), alcance %.1f m\nboneco a %.1f m   [1] bastão longo [2] taco [3] pé de cabra [4] machado   [↑/↓] distância   [espaço] %s   [←/→] câmera" % [
		str(entry.get("name", weapon)), int(entry.get("melee", 9)), float(entry.get("reach", 2.4)), distance, "continuar" if _paused else "pausar"]

## Fotos do golpe (armando, impacto, terminando) e o número de dano no ar.
func _capture(folder: String) -> void:
	get_window().size = Vector2i(900, 900)
	_orbit = 0.95
	var shots := [[0.12, "bastao_1_armando"], [0.27, "bastao_2_impacto"], [0.45, "bastao_3_dano"], [0.7, "bastao_4_terminando"]]
	for shot in shots:
		while _clock < float(shot[0]):
			await get_tree().process_frame
		Stage.save_shot(get_viewport(), folder, str(shot[1]))
	# Close das mãos: carregando no ombro (frente e lado) e no meio do golpe.
	_paused = true
	_camera_locked = true
	avatar.call("set_action", "", "")
	avatar.call("set_action", "hold", weapon)
	for view in [["maos_carregando_frente", Vector3(0.0, 1.25, -1.1)], ["maos_carregando_lado", Vector3(-1.0, 1.3, -0.5)], ["maos_carregando_tras", Vector3(0.5, 1.4, 0.9)]]:
		avatar.call("animate", 1.0 / 60.0, 0.0, false, false, false, false, false)
		camera.position = view[1]
		camera.look_at(Vector3(0.05, 1.05, -0.1))
		await get_tree().process_frame
		await get_tree().process_frame
		Stage.save_shot(get_viewport(), folder, str(view[0]))
	avatar.call("set_action", "", "")
	avatar.call("set_action", "swing", weapon)
	for k in 3:
		avatar.set("_work_time", SWING_CYCLE * [0.2, 0.45, 0.7][k])
		avatar.call("animate", 0.0, 0.0, false, false, false, false, false)
		camera.position = Vector3(0.9, 1.5, -1.4)
		camera.look_at(Vector3(0, 1.15, -0.2))
		await get_tree().process_frame
		await get_tree().process_frame
		Stage.save_shot(get_viewport(), folder, "maos_golpe_%d" % (k + 1))
	print("resultado: " + last_result)
	print("fotos salvas em " + folder)
	get_tree().quit(0)
