extends Node3D
## Cena de demonstração: sequência de socos (soco direto e cotovelada) no
## boneco de treino, com o dano do jogo. O impacto acontece quando o punho (ou
## o cotovelo) chega mais à frente no clipe; aí vale a regra do jogo: raio na
## altura do peito (1,35 m) até o alcance do soco, nas hitboxes do boneco.
## Dano do soco: Combate 15, Sobrevivência 12 (×1,5 na cabeça), como o servidor.
## Abra scenes/previews/punch_preview.tscn e aperte F6.
## Teclas: 1 Combate, 2 Sobrevivência, 3 só soco / alterna com cotovelada,
## ↑/↓ distância do boneco, espaço pausa, ←/→ câmera.
## Fotos: godot --path godot res://scenes/previews/punch_preview.tscn -- --capture=<pasta>
const Stage = preload("res://scripts/previews/preview_stage.gd")
const HitboxScript = preload("res://scripts/net/hitbox.gd")
const DummyScript = preload("res://scripts/training_dummy.gd")
const SoundFXScript = preload("res://scripts/sound_fx.gd")
const PUNCH_REACH := 2.2 # match_controller.PUNCH_REACH
# Dano do soco no servidor: FIST_DAMAGE em src/godot-match.js e src/godot-survival.js.
const MODES := {"combate": {"name": "Combate", "damage": 15.0}, "sobrevivencia": {"name": "Sobrevivência", "damage": 12.0}}
const STRIKE_BONES := ["RightHand", "LeftHand", "RightForeArm", "LeftForeArm"]
const PAUSE_BETWEEN := 0.35

var avatar: Node3D
var camera: Camera3D
var dummy: Node3D
var sound: Node
var hint: Label
var mode := "combate"
var combo := true
var distance := 0.95
var _orbit := 0.85
var _paused := false
var _clip := ""
var _count := 0
var _wait := 0.0
var _baseline := 0.0
var _peak := 0.0
var _struck := false
var last_result := ""
var hits := 0

func _ready() -> void:
	camera = Stage.build(self)
	avatar = load("res://scenes/characters/01.tscn").instantiate()
	add_child(avatar)
	dummy = DummyScript.new()
	add_child(dummy)
	dummy.rotation.y = PI
	sound = SoundFXScript.new()
	sound.set("spatial_audio", false)
	add_child(sound)
	hint = Stage.hint(self, "")
	await get_tree().process_frame
	avatar.call("set_armed", false)
	_place_dummy()
	_wait = 0.4
	var folder := Stage.capture_folder()
	if not folder.is_empty():
		_capture(folder)

func _place_dummy() -> void:
	dummy.position = Vector3(0, 0, -distance)
	# O NetActor do boneco segue target_position (posição de rede): sem isto ele volta à origem.
	var actor := dummy.get("actor") as Node3D
	actor.set("target_position", actor.global_position)
	_update_hint()

func _throw() -> void:
	_clip = "elbow_punch" if combo and _count % 2 == 1 else "punch"
	_count += 1
	if not bool(avatar.call("play_action", _clip)):
		_clip = ""
		return
	_struck = false
	_baseline = _reach()
	_peak = _baseline
	sound.call("melee_swing")

## Quanto o punho/cotovelo mais adiantado está à frente do corpo (m).
func _reach() -> float:
	var skeleton := avatar.get("skeleton") as Skeleton3D
	if skeleton == null:
		return 0.0
	var forward := -avatar.global_basis.z
	var best := -INF
	for bone_name in STRIKE_BONES:
		var b := Stage.bone(skeleton, bone_name)
		if b >= 0:
			var p := skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
			best = maxf(best, (p - avatar.global_position).dot(forward))
	return best

func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_LEFT):
		_orbit -= delta * 1.5
	if Input.is_physical_key_pressed(KEY_RIGHT):
		_orbit += delta * 1.5
	var focus := Vector3(0, 1.2, -distance * 0.5)
	camera.position = focus + Vector3(sin(_orbit) * 3.6, 0.4, cos(_orbit) * 3.6)
	camera.look_at(focus)
	if avatar == null or not avatar.has_method("animate"):
		return
	var step := 0.0 if _paused else delta
	avatar.call("animate", step, 0.0, false, false, false, false, false)
	if _paused:
		return
	var player := avatar.get("animation_player") as AnimationPlayer
	var playing := not _clip.is_empty() and player != null and player.is_playing() and str(avatar.get("current_clip")) == _clip
	if playing:
		var now := _reach()
		_peak = maxf(_peak, now)
		# Impacto: o golpe avançou bem e começou a voltar.
		if not _struck and _peak > _baseline + 0.18 and now < _peak - 0.03:
			_struck = true
			_strike()
		return
	if not _clip.is_empty():
		_clip = ""
		_wait = PAUSE_BETWEEN
	_wait -= step
	if _wait <= 0.0:
		_throw()

## Mesma regra do Combate (match_controller._punch).
func _strike() -> void:
	var forward := -avatar.global_basis.z
	var from := avatar.global_position + Vector3(0, 1.35, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + forward * PUNCH_REACH, HitboxScript.SHOT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var body: Object = hit.get("collider")
	if hit.is_empty() or body == null or body.get("actor") == null:
		last_result = "errou"
		dummy.call("_show", "ERROU: fora do alcance (%.1f m)" % PUNCH_REACH)
		return
	var zone := str(body.get("zone")) if body.get("zone") != null else "chest"
	var damage := float(MODES[mode]["damage"]) * (1.5 if zone == "head" else 1.0)
	hits += 1
	last_result = "%s %s %d" % [_clip, zone, roundi(damage)]
	print("golpe: %s acertou %s, dano %d" % [_clip, zone, roundi(damage)])
	var what := "COTOVELADA" if _clip == "elbow_punch" else "SOCO"
	dummy.call("melee_hit", damage, what, zone, hit["position"], hit["normal"])
	sound.call("melee_impact", zone == "head")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_1:
			mode = "combate"
		KEY_2:
			mode = "sobrevivencia"
		KEY_3:
			combo = not combo
		KEY_UP:
			distance = minf(distance + 0.3, 3.0)
			_place_dummy()
		KEY_DOWN:
			distance = maxf(distance - 0.3, 0.65)
			_place_dummy()
		KEY_SPACE:
			_paused = not _paused
	_update_hint()

func _update_hint() -> void:
	hint.text = "SOCOS  •  %s: dano %d (cabeça ×1,5), alcance %.1f m\nboneco a %.2f m   [1] Combate [2] Sobrevivência   [3] %s   [↑/↓] distância   [espaço] %s   [←/→] câmera" % [
		MODES[mode]["name"], int(MODES[mode]["damage"]), PUNCH_REACH, distance, "soco + cotovelada" if combo else "só soco", "continuar" if _paused else "pausar"]

## Fotos: o primeiro soco no impacto, o número de dano e a cotovelada.
func _capture(folder: String) -> void:
	get_window().size = Vector2i(900, 900)
	_orbit = 1.05
	var taken := {}
	var elapsed := 0.0
	while elapsed < 8.0 and taken.size() < 3:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if _struck and _clip == "punch" and not taken.has("soco"):
			taken["soco"] = true
			Stage.save_shot(get_viewport(), folder, "socos_1_impacto_soco")
		elif _struck and _clip == "elbow_punch" and not taken.has("cotovelo"):
			taken["cotovelo"] = true
			Stage.save_shot(get_viewport(), folder, "socos_3_impacto_cotovelada")
		elif taken.has("soco") and not taken.has("dano") and _clip.is_empty():
			taken["dano"] = true
			Stage.save_shot(get_viewport(), folder, "socos_2_dano")
	print("acertos: %d  último: %s" % [hits, last_result])
	print("fotos salvas em " + folder)
	get_tree().quit(0)
