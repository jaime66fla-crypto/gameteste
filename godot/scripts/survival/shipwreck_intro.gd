extends CanvasLayer
## Intro da Sobrevivência: o cruzeiro Aurora do Sul afunda numa tempestade,
## o jogador flutua agarrado aos destroços e acorda na beira da ilha.
## O navio vem do Blender (tools/blender/build_cruise_ship.py) em duas metades
## que se partem; o resto (mar, praia, chuva, sons) é procedural. Tudo num
## SubViewport com mundo 3D próprio: enquanto passa, o 3D do jogo fica
## desligado (não pesa no celular). Pular: botão, Esc, Enter ou Espaço.
## Toca uma vez por personagem novo.
signal finished

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const RainWeather = preload("res://scripts/survival/rain_weather.gd")
const NatureModel = preload("res://scripts/survival/nature_model.gd")
const Hydrology = preload("res://scripts/survival/hydrology.gd")
const SurvivalData = preload("res://scripts/survival/survival_data.gd")
const CharacterRegistry = preload("res://scripts/characters/character_registry.gd")
const SHIP_PATH := "res://assets/survival/intro/cruise_ship.glb"
const SEEN_PATH := "user://survival_intro.cfg"
const REPLAY_AFTER := 1800 # s: sair e voltar logo não repete a intro

## Linha do tempo (s): tempestade até BLACK_AT; preto com legenda; praia em BEACH_AT.
const BLACK_AT := 28.4
const BEACH_AT := 33.6
const POV_AT := 39.0
const GETUP_AT := 43.2
const END := 51.5
const EXPLODE_AT := 11.4
const BEACH := Vector3(4000, 0, 0) # a praia fica no mesmo mundo, longe do naufrágio
## [início, fim, texto] em segundos da intro.
const CAPTIONS := [
	[1.2, 7.2, "Atlântico Sul. A bordo do cruzeiro Aurora do Sul, duas mil pessoas dormem."],
	[7.9, 11.2, "Às 3h12, uma onda gigante atinge o navio de lado."],
	[11.8, 14.3, "Na casa de máquinas, algo explode. O fogo toma conta do convés."],
	[14.6, 21.6, "O navio enche de água e se parte ao meio. Botes caem no mar."],
	[22.6, 28.2, "Você se agarra a um pedaço do convés e flutua a noite inteira."],
	[29.8, 33.2, "A tempestade passa. Você apaga de cansaço."],
	[34.4, 38.7, "Horas depois, as ondas te deixam na beira de uma ilha que não está em nenhum mapa."],
	[39.8, 42.9, "Você está vivo."],
	[44.2, 49.0, "Sem nada além da roupa do corpo. Agora é sobreviver."],
]
const STAMPS := [[0.0, "ATLÂNTICO SUL  ·  03:07"], [7.6, "ATLÂNTICO SUL  ·  03:12"], [14.4, "ATLÂNTICO SUL  ·  03:31"], [22.2, "ATLÂNTICO SUL  ·  04:50"], [BEACH_AT, "ILHA DESCONHECIDA"]]
## Ondas: [direção, comprimento (m), altura (m)]. O shader usa as mesmas.
const WAVES := [[Vector2(0.958, 0.287), 38.0, 1.1], [Vector2(0.514, 0.857), 21.0, 0.55], [Vector2(-0.371, 0.928), 11.0, 0.25]]
const SEA_SHADER := """
shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
uniform float sea_time;
uniform float amp = 1.0;
uniform float shore_on = 0.0;
uniform float shore_line = 0.0;
varying float crest;
varying vec3 wpos;
float wave(vec2 p, vec2 d, float len, float a, inout vec2 g) {
	float k = 6.2831853 / len;
	float ph = dot(d, p) * k + sea_time * sqrt(9.8 * k);
	g += a * k * cos(ph) * d;
	return a * sin(ph);
}
void vertex() {
	vec2 g = vec2(0.0);
	float h = wave(VERTEX.xz, vec2(0.958, 0.287), 38.0, 1.1 * amp, g)
		+ wave(VERTEX.xz, vec2(0.514, 0.857), 21.0, 0.55 * amp, g)
		+ wave(VERTEX.xz, vec2(-0.371, 0.928), 11.0, 0.25 * amp, g);
	VERTEX.y += h;
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
	crest = h;
	wpos = VERTEX;
}
void fragment() {
	float foam = smoothstep(1.0, 1.75, crest);
	float to_shore = shore_line - wpos.z;
	float edge = shore_on * (1.0 - smoothstep(0.0, 2.6, max(to_shore, 0.0)));
	edge *= 0.55 + 0.45 * sin(wpos.x * 0.9 + sea_time * 1.3) * sin(wpos.x * 0.37 - sea_time);
	foam = max(foam, edge);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 water = mix(vec3(0.018, 0.045, 0.058), vec3(0.07, 0.13, 0.15), fres * 0.8);
	water = mix(water, vec3(0.13, 0.25, 0.25), shore_on * (1.0 - smoothstep(0.0, 14.0, to_shore)));
	ALBEDO = mix(water, vec3(0.55, 0.58, 0.56), foam * 0.75);
	ROUGHNESS = mix(0.16, 0.85, foam);
	SPECULAR = 0.55;
}
"""

var controller: Node # SurvivalController (opcional: nos testes não existe)
## Praia de verdade (no jogo): sem isso, a cena da praia usa um cenário próprio.
var real_beach := false
var game_world: Node3D # nó principal do jogo (o mundo da ilha)
var player_body: Node3D
var beach_point := Vector3.ZERO
var beach_basis := Basis.IDENTITY # +Z local = para dentro da ilha
var _container: SubViewportContainer
var _prev_camera: Camera3D
var _real_cam: Camera3D
var _props: Node3D
var t := 0.0
var started := false
var done := false
var _mobile := OS.has_feature("mobile")
var _rng := RandomNumberGenerator.new()
var _root: Control
var _viewport: SubViewport
var _camera: Camera3D
var _haze: ColorRect # vista turva ao acordar
var _sea: ShaderMaterial
var _beach_sea: ShaderMaterial
var _beach_water: MeshInstance3D
var _env: Environment
var _dawn: Environment
var _we: WorldEnvironment
var _moon: DirectionalLight3D
var _ship: Node3D
var _bow: Node3D
var _stern: Node3D
var _bow_base: Transform3D
var _stern_base: Transform3D
var _deck_mats: Array[StandardMaterial3D] = [] # Vigias, Janelas_D0..D5 (de baixo para cima)
var _deck_energy: Array[float] = []
var _ship_lights: Array[OmniLight3D] = []
var _lifeboats: Array[Node3D] = []
var _debris: Array[Dictionary] = [] # {node, base: Vector3, spin: float, lift: float}
var _my_plank: Node3D
var _spray: CPUParticles3D
## Explosão na casa de máquinas (perto da chaminé, na metade da popa).
var _exploded := false
var _fireball: CPUParticles3D
var _blast_debris: CPUParticles3D
var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _blast_light: OmniLight3D
var _boom: AudioStreamPlayer
var _break_spray: CPUParticles3D
var _rain: CPUParticles3D
var _castaway: Node3D # avatar escolhido pelo jogador (deitado na areia)
var _castaway_at := Vector3.ZERO
var _got_up := false
var _flash := 0.0
var _next_bolt := 3.2
var _bolts := [7.95, 16.2, 19.1, 23.4]
var _thunder_at := -1.0
var _horns := [9.0, 15.8]
var _creaked := false
var _at_beach := false
var _storm: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _creak: AudioStreamPlayer
var _surf: AudioStreamPlayer
var _caption: Label
var _stamp: Label
var _fade: ColorRect
var _lids: Array[ColorRect] = []
var _skip: Button

## Personagem recém-criado pelo servidor (fome e sede 85, vivo) e a intro
## não passou nos últimos 30 min neste aparelho.
static func should_play(you: Dictionary) -> bool:
	if bool(you.get("dead", false)):
		return false
	if not is_equal_approx(float(you.get("hunger", 0)), 85.0) or not is_equal_approx(float(you.get("thirst", 0)), 85.0):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(SEEN_PATH) == OK:
		var seen := int(cfg.get_value("intro", "seen_at", 0))
		if Time.get_unix_time_from_system() - seen < REPLAY_AFTER:
			return false
	return true

static func mark_seen() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SEEN_PATH)
	cfg.set_value("intro", "seen_at", int(Time.get_unix_time_from_system()))
	cfg.save(SEEN_PATH)

static func wave_height(x: float, z: float, time: float, amp: float = 1.0) -> float:
	var h := 0.0
	for w in WAVES:
		var k := TAU / float(w[1])
		h += float(w[2]) * amp * sin((w[0] as Vector2).dot(Vector2(x, z)) * k + time * sqrt(9.8 * k))
	return h

static func wave_normal(x: float, z: float, time: float, amp: float = 1.0) -> Vector3:
	var g := Vector2.ZERO
	for w in WAVES:
		var k := TAU / float(w[1])
		var d := w[0] as Vector2
		g += float(w[2]) * amp * k * cos(d.dot(Vector2(x, z)) * k + time * sqrt(9.8 * k)) * d
	return Vector3(-g.x, 1.0, -g.y).normalized()

## Areia da praia (coordenadas locais da praia; o mar fica em z < 0).
static func sand_height(x: float, z: float) -> float:
	var h := z * 0.09 if z < 20.0 else 1.8 + (z - 20.0) * 0.22
	return h + 0.18 * sin(x * 0.21 + z * 0.13) * clampf(z / 8.0, 0.0, 1.0) + 0.08 * sin(x * 0.67 - z * 0.4)

## Liga a praia de verdade: o náufrago acorda na costa mais perto do spawn.
func use_real_beach(main: Node3D, body: Node3D, from: Vector3) -> void:
	var found := find_beach(from)
	if found.is_empty():
		return
	real_beach = true
	game_world = main
	player_body = body
	beach_point = found.p
	var inland: Vector3 = found.inland
	beach_basis = Basis(Vector3.UP, atan2(inland.x, inland.z))

## Costa mais perto: anda em 32 direções até o chão cair no mar (fora das
## cidades; lago ou rio no caminho não conta) e volta 3 m para a areia seca.
static func find_beach(from: Vector3) -> Dictionary:
	var towns: Array = SurvivalData.world().get("towns", [])
	var best := {}
	var start := Vector2(from.x, from.z)
	for i in 32:
		var a := TAU * i / 32.0
		var dir := Vector2(cos(a), sin(a))
		for step in range(1, 450):
			var q := start + dir * (step * 2.0)
			if Hydrology.ground_height(q.x, q.y) > -0.75:
				continue
			if Hydrology.coast_height(q.x, q.y) > -0.3:
				break # lago ou rio no caminho, não é o mar
			var land := q - dir * 3.0
			var in_town := false
			for town in towns:
				var c: Array = town.get("center", [0, 0])
				if land.distance_to(Vector2(float(c[0]), float(c[1]))) < 90.0:
					in_town = true
			var dist := step * 2.0
			if not in_town and (best.is_empty() or dist < float(best.dist)):
				var ground := Hydrology.ground_height(land.x, land.y)
				best = {"p": Vector3(land.x, ground, land.y), "inland": Vector3(-dir.x, 0, -dir.y), "dist": dist}
			break
	return best

func _ready() -> void:
	name = "ShipwreckIntro"
	layer = 90
	_rng.seed = 3120
	_build_ui()
	_build_world()
	if not real_beach:
		_build_beach()
	_build_audio()
	_update(0.0)

func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.disable_3d = false

## Começa quando a tela de carregamento some.
func _begin() -> void:
	started = true
	get_viewport().disable_3d = true
	_storm.play()
	mark_seen()

func _process(delta: float) -> void:
	if done:
		return
	if not started:
		if get_tree().root.has_node("MatchLoading"):
			return
		_begin()
	t += delta
	_update(delta)
	if t >= END:
		_finish()

func _input(event: InputEvent) -> void:
	if not started or done or t < 1.0:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
		get_viewport().set_input_as_handled()
		skip()

## Pular: corta direto para o fim (fade do preto para o jogo).
func skip() -> void:
	if done:
		return
	if t < END - 1.5:
		t = END - 1.5
		for p in [_storm, _thunder, _horn, _creak, _boom]:
			p.stop()
		_surf.volume_db = -30
		_caption.modulate.a = 0.0

func _finish() -> void:
	done = true
	get_viewport().disable_3d = false
	if real_beach:
		_hand_over()
	finished.emit()
	queue_free()

# ------------------------------------------------------------- timeline ---

func _update(delta: float) -> void:
	_sea.set_shader_parameter("sea_time", t)
	if t >= BEACH_AT and not _at_beach:
		_enter_beach()
	if _at_beach:
		_update_beach(delta)
	else:
		_update_ship()
		_update_boats_and_debris()
		_update_camera()
		_update_lightning(delta)
	_update_text()
	_update_sound()

func _ease(a: float, b: float) -> float:
	return smoothstep(a, b, t)

func _update_ship() -> void:
	var flood := _ease(13.5, 19.0)
	var impact := 0.0
	if t > 8.0:
		impact = exp(-(t - 8.0) * 0.9) * sin((t - 8.0) * 2.4)
	# Arfagem segue a inclinação da onda entre proa e popa.
	var slope := (wave_height(50, 0, t) - wave_height(-50, 0, t)) / 100.0
	var roll := deg_to_rad(4.0) * sin(t * 0.6) + deg_to_rad(20.0) * impact + deg_to_rad(9.0) * flood
	var pitch := atan(slope) * 0.6 - deg_to_rad(10.0) * flood
	var heave := wave_height(0, 0, t) * 0.35 - 5.0 * flood
	_ship.transform = Transform3D(Basis(Vector3.RIGHT, roll) * Basis(Vector3.BACK, pitch), Vector3(0, heave, 0))
	# Quebra às 19 s: a proa mergulha; a popa cai de volta, depois empina e desce.
	var brk := _ease(19.0, 20.8)
	var bow_pitch := -deg_to_rad(32.0) * brk - deg_to_rad(25.0) * _ease(21.0, 26.0)
	var bow_drop := 20.0 * _ease(19.4, 25.0)
	_bow.transform = Transform3D(Basis(Vector3.BACK, bow_pitch), Vector3(1.5 * brk, -bow_drop, 0)) * _bow_base
	var stern_pitch := deg_to_rad(9.0) * brk - deg_to_rad(62.0) * _ease(21.5, 28.0)
	var stern_drop := 30.0 * pow(_ease(22.5, 30.0), 1.4)
	_stern.transform = Transform3D(Basis(Vector3.BACK, stern_pitch), Vector3(-1.0 * brk, -stern_drop, 0)) * _stern_base
	# Luzes: piscam depois da onda; a água apaga convés por convés, de baixo para cima.
	var flicker := 1.0
	if t > 8.1 and t < 14.0:
		flicker = 0.3 if sin(t * 23.0) * sin(t * 7.3) > 0.55 else 1.0
	for i in _deck_mats.size():
		var dark := _ease(14.2 + i * 0.75, 14.6 + i * 0.75)
		var mat := _deck_mats[i]
		mat.emission_energy_multiplier = _deck_energy[i] * flicker * (1.0 - dark)
	var lit := flicker * (1.0 - _ease(14.5, 19.2))
	for light in _ship_lights:
		light.light_energy = 2.4 * lit
	if t > 8.0 and t < 8.15 and not _spray.emitting:
		_spray.restart()
		_spray.emitting = true
	if t > 19.0 and t < 19.15 and not _break_spray.emitting:
		_break_spray.restart()
		_break_spray.emitting = true
	_update_blast()

func _update_blast() -> void:
	var since := t - EXPLODE_AT
	if since >= 0.0 and not _exploded and t < BLACK_AT:
		_exploded = true
		for p in [_fireball, _blast_debris]:
			p.restart()
			p.emitting = true
		_smoke.emitting = true
		_fire.emitting = true
		_boom.play()
	var burning := 1.0 - _ease(22.5, 26.0) # a popa afunda e apaga o fogo
	if since >= 0.0:
		_blast_light.light_energy = 9.0 * exp(-since * 3.0) + 3.0 * burning * (0.75 + 0.25 * sin(t * 17.0) * sin(t * 5.3))
	else:
		_blast_light.light_energy = 0.0
	if burning <= 0.01:
		_smoke.emitting = false
		_fire.emitting = false

## Clarão da explosão (0–1), usado no céu e na câmera.
func _blast() -> float:
	var since := t - EXPLODE_AT
	return exp(-since * 2.5) if since >= 0.0 else 0.0

func _update_boats_and_debris() -> void:
	for i in _lifeboats.size():
		var boat := _lifeboats[i]
		boat.visible = t > 15.0
		var drift := maxf(0.0, t - 15.0) * (1.2 + i * 0.25)
		_float(boat, Vector3(-25.0 + i * 16.0, 0, 28.0 + i * 3.0 + drift), 0.3, 0.0)
	for d in _debris:
		var node: Node3D = d.node
		node.visible = t > 14.0
		_float(node, d.base + Vector3(0, 0, maxf(0.0, t - 14.0) * 0.6), float(d.lift), float(d.spin) * t)

## Boia na onda: altura e inclinação da superfície.
func _float(node: Node3D, at: Vector3, lift: float, yaw: float, amp: float = 1.0) -> void:
	var n := wave_normal(at.x, at.z, t, amp)
	var tilt := Quaternion(Vector3.UP, n)
	node.transform = Transform3D(Basis(tilt) * Basis(Vector3.UP, yaw), Vector3(at.x, wave_height(at.x, at.z, t, amp) + lift, at.z))

func _update_camera() -> void:
	var ship_at := _ship.position
	var shake := Vector3.ZERO
	if _flash > 0.2 or (t > 8.0 and t < 9.5) or (t > 19.0 and t < 20.5):
		shake = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 0.08
	shake += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 0.45 * _blast()
	if t < 7.6:
		var k := t / 7.6
		var from := Vector3(-130, 11, 130).lerp(Vector3(-100, 9, 112), k)
		from.y += wave_height(from.x, from.z, t) * 0.2
		_camera.look_at_from_position(from, ship_at + Vector3(0, 10, 0))
	elif t >= EXPLODE_AT - 0.2 and t < 14.4:
		# Explosão: perto da popa, olhando o fogo subir pela chaminé.
		var k := (t - EXPLODE_AT + 0.2) / (14.6 - EXPLODE_AT)
		var from := Vector3(-8, 7, 62).lerp(Vector3(-16, 6, 52), k)
		from.y += wave_height(from.x, from.z, t) * 0.3
		_camera.look_at_from_position(from + shake, ship_at + Vector3(-28, 14, 0))
	elif t < 14.4:
		var k := (t - 7.6) / 6.8
		var from := Vector3(62, 5, 62).lerp(Vector3(44, 4.5, 54), k)
		from.y += wave_height(from.x, from.z, t) * 0.3
		_camera.look_at_from_position(from + shake, ship_at + Vector3(10, 12, 0))
	elif t < 22.2:
		var k := (t - 14.4) / 7.8
		var from := Vector3(-60, 5, 120).lerp(Vector3(-40, 4, 104), k)
		from.y += wave_height(from.x, from.z, t) * 0.3
		_camera.look_at_from_position(from + shake, Vector3(-6, 6.0 - 6.0 * _ease(18.0, 22.0), 0))
	else:
		# Ponto de vista: na água, agarrado ao pedaço de convés.
		var at := Vector3(14, 0, 72)
		var n := wave_normal(at.x, at.z, t)
		var eye := Vector3(at.x, wave_height(at.x, at.z, t) + 0.85, at.z)
		var target := Vector3(-30, 4.0 + sin(t * 0.7) * 0.6, -4)
		_camera.look_at_from_position(eye + shake, target, Vector3.UP.lerp(n, 0.6).normalized())
		_my_plank.visible = true
		var plank_at := eye + (target - eye).normalized() * 1.7
		_float(_my_plank, Vector3(plank_at.x, 0, plank_at.z), 0.05, 0.4)

func _update_lightning(delta: float) -> void:
	var strike := false
	if not _bolts.is_empty() and t >= float(_bolts[0]):
		_bolts.pop_front()
		strike = true
	elif t >= _next_bolt and t < BLACK_AT:
		_next_bolt = t + _rng.randf_range(3.5, 7.0)
		strike = true
	if strike:
		_flash = 1.0
		_thunder_at = t + _rng.randf_range(0.25, 0.9)
	_flash = maxf(0.0, _flash - delta * 2.6)
	var pulse := _flash * (0.6 + 0.4 * sin(_flash * 40.0)) # duas piscadas rápidas
	_moon.light_energy = 0.28 + pulse * 4.0
	_env.background_color = Color("#0a1115").lerp(Color("#5d6b75"), pulse * 0.8)
	_env.ambient_light_energy = 0.55 + pulse * 2.0
	_env.background_color = _env.background_color.lerp(Color("#6b3418"), _blast() * 0.55)
	if _thunder_at > 0.0 and t >= _thunder_at:
		_thunder_at = -1.0
		_thunder.pitch_scale = _rng.randf_range(0.8, 1.1)
		_thunder.play()

# ---------------------------------------------------------------- praia ---

func _enter_beach() -> void:
	_at_beach = true
	_storm.stop()
	_surf.play()
	_rain.emitting = false
	_rain.visible = false
	if real_beach:
		_enter_real_beach()
		return
	_we.environment = _dawn
	_moon.light_color = Color("#ffb98a")
	_moon.light_energy = 1.2
	_moon.rotation_degrees = Vector3(-24, 200, 0)
	_moon.shadow_enabled = not _mobile

## Praia de verdade: a cena passa no mundo do jogo, no lugar onde o jogador
## vai começar. O SubViewport some, o 3D do jogo volta e uma câmera nossa
## filma o náufrago (um avatar igual ao do jogador) deitado na areia.
func _enter_real_beach() -> void:
	_container.visible = false
	get_viewport().disable_3d = false
	_prev_camera = get_viewport().get_camera_3d()
	_real_cam = Camera3D.new()
	_real_cam.name = "IntroCamera"
	_real_cam.fov = 62
	game_world.add_child(_real_cam)
	_real_cam.make_current()
	_camera = _real_cam
	if player_body != null:
		player_body.visible = false
		player_body.global_position = beach_point + Vector3.UP * 0.1
	_props = Node3D.new()
	_props.name = "ShipwreckBeach" # destroços ficam na praia depois da intro
	game_world.add_child(_props)
	_props.global_transform = Transform3D(beach_basis, beach_point)
	_add_wreckage(_props, func(x: float, z: float) -> float:
		var g := beach_basis * Vector3(x, 0, z) + beach_point
		return Hydrology.ground_height(g.x, g.z) - beach_point.y)
	_add_castaway(game_world, beach_point, atan2(beach_basis.z.x, beach_basis.z.z) + PI)

## Ponto relativo ao náufrago: +Z local aponta para dentro da ilha.
func _at(local: Vector3) -> Vector3:
	var body := beach_point if real_beach else BEACH + _castaway_at
	var p := body + beach_basis * local
	if real_beach:
		p.y = maxf(p.y, Hydrology.ground_height(p.x, p.z) + 0.35)
	return p

func _update_beach(delta: float) -> void:
	if not real_beach:
		_beach_sea.set_shader_parameter("sea_time", t)
		# Espraiado: a água sobe e desce na areia.
		var swash := sin(t * 0.55) * 0.11 + sin(t * 1.3) * 0.03
		_beach_water.position.y = 0.06 + swash
		_beach_sea.set_shader_parameter("shore_line", BEACH.z + (0.06 + swash) / 0.09)
	if _castaway != null:
		_castaway.visible = t < POV_AT or t >= GETUP_AT
		if t >= GETUP_AT + 0.4 and not _got_up:
			_got_up = true
			_castaway.set("_overlay_speed", 0.95)
		if _castaway.has_method("animate"):
			_castaway.call("animate", delta, 0.0, false, false, false, false, false)
	if t < POV_AT:
		var k := (t - BEACH_AT) / (POV_AT - BEACH_AT)
		_camera.look_at_from_position(_at(Vector3(7.5, 2.1, -7.0).lerp(Vector3(3.6, 1.2, -4.6), k)), _at(Vector3(0, 0.25, 0.6)))
		_set_eyes(1.0)
	elif t < GETUP_AT:
		# Olhos abrindo: vista turva, duas piscadas; olha o mar e vira para a mata.
		var k := (t - POV_AT) / (GETUP_AT - POV_AT)
		var eye := _at(Vector3(0, 0.28, 0.25))
		var turn := smoothstep(0.35, 1.0, k)
		var yaw := lerpf(PI, 0.2, turn) # vira pelo lado (ao longo da praia), não por cima
		var dir := beach_basis * Vector3(sin(yaw), lerpf(0.25, 0.18, turn), cos(yaw)).normalized()
		_camera.look_at_from_position(eye, eye + dir)
		_set_eyes(_eyes_open(t - POV_AT))
		_haze.color.a = lerpf(0.55, 0.0, clampf(k * 1.5, 0.0, 1.0))
	else:
		_set_eyes(1.0)
		_haze.color.a = 0.0
		var k := clampf((t - GETUP_AT) / 6.0, 0.0, 1.0)
		var s := k * k * (3.0 - 2.0 * k)
		var target := _at(Vector3(0, 0.5, 0.3)).lerp(_at(Vector3(0, 1.4, 30.0)), _ease(GETUP_AT + 3.0, GETUP_AT + 6.5))
		_camera.look_at_from_position(_at(Vector3(-3.6, 0.9, -0.8).lerp(Vector3(1.4, 2.0, -2.6), s)), target)

## Fim: o jogador fica de pé onde o náufrago levantou, olhando para a mata.
func _hand_over() -> void:
	if not _at_beach:
		_enter_beach()
	if player_body != null:
		var inland := beach_basis.z
		player_body.global_position = beach_point + Vector3.UP * 0.15
		player_body.set("yaw", atan2(-inland.x, -inland.z))
		player_body.visible = true
	if _prev_camera != null and is_instance_valid(_prev_camera):
		_prev_camera.make_current()
	if _real_cam != null:
		_real_cam.queue_free()
	if _castaway != null:
		_castaway.queue_free()
		_castaway = null

## 0 = fechado, 1 = aberto. Abre devagar, pisca duas vezes.
func _eyes_open(s: float) -> float:
	var keys := [[0.0, 0.0], [0.5, 0.0], [1.0, 0.35], [1.25, 0.05], [1.8, 0.6], [2.05, 0.1], [2.8, 1.0]]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if s <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), smoothstep(float(a[0]), float(b[0]), s))
	return 1.0

func _set_eyes(open: float) -> void:
	var cover := (1.0 - open) * 0.5
	_lids[0].anchor_bottom = cover
	_lids[1].anchor_top = 1.0 - cover
	for lid in _lids:
		lid.visible = open < 0.999

func _update_text() -> void:
	var text := ""
	var alpha := 0.0
	for c in CAPTIONS:
		if t >= float(c[0]) and t <= float(c[1]):
			text = str(c[2])
			alpha = minf(1.0, minf(t - float(c[0]), float(c[1]) - t) / 0.6)
	if text != "":
		_caption.text = text
	_caption.modulate.a = alpha
	for s in STAMPS:
		if t >= float(s[0]):
			_stamp.text = str(s[1])
	var stamp_on := clampf(t / 1.0, 0.0, 1.0) * clampf((BLACK_AT + 0.6 - t) / 1.0, 0.0, 1.0)
	if t >= BEACH_AT:
		stamp_on = clampf((t - BEACH_AT - 0.6) / 1.0, 0.0, 1.0) * clampf((POV_AT - t) / 0.6, 0.0, 1.0)
	_stamp.modulate.a = stamp_on
	_skip.visible = started and t < END - 1.5
	# Preto: entra do carregamento, cai no fim da noite, abre na praia e fecha no fim.
	var black := 0.0
	if t < 1.2:
		black = 1.0 - t / 1.2
	elif t > BLACK_AT and t < BEACH_AT:
		black = clampf((t - BLACK_AT) / 1.4, 0.0, 1.0)
	elif t >= BEACH_AT and t < END - 2.5:
		black = 1.0 - clampf((t - BEACH_AT) / 1.6, 0.0, 1.0)
	elif t >= END - 2.5:
		black = clampf((t - (END - 2.5)) / 1.0, 0.0, 1.0)
	_fade.color = Color(0, 0, 0, black)
	# Últimos 1,5 s: a intro inteira some e o jogo aparece por baixo.
	var reveal := clampf((t - (END - 1.5)) / 1.5, 0.0, 1.0)
	if reveal > 0.0:
		get_viewport().disable_3d = false
		_root.modulate.a = 1.0 - reveal

func _update_sound() -> void:
	if not _horns.is_empty() and t >= float(_horns[0]):
		_horns.pop_front()
		_horn.play()
	if t >= 19.0 and not _creaked and t < BLACK_AT:
		_creaked = true
		_creak.play()
	if t > BLACK_AT - 0.4 and t < BEACH_AT:
		_storm.volume_db = lerpf(-8.0, -40.0, clampf((t - BLACK_AT + 0.4) / 2.0, 0.0, 1.0))
	if _at_beach:
		_surf.volume_db = lerpf(_surf.volume_db, -10.0 if t < END - 2.5 else -40.0, 0.05)

# ---------------------------------------------------------------- build ---

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "IntroRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var container := SubViewportContainer.new()
	_container = container
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2 if _mobile else 1
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if _mobile else Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)
	# Pálpebras (cena dos olhos abrindo).
	for top in [true, false]:
		var lid := ColorRect.new()
		lid.name = "LidTop" if top else "LidBottom"
		lid.color = Color(0.01, 0.005, 0.0)
		lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lid.anchor_right = 1.0
		lid.anchor_top = 0.0 if top else 1.0
		lid.anchor_bottom = 0.0 if top else 1.0
		lid.visible = false
		_root.add_child(lid)
		_lids.append(lid)
	_haze = ColorRect.new()
	_haze.name = "Haze"
	_haze.color = Color(0.85, 0.8, 0.72, 0.0)
	_haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_haze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_haze)
	_root.move_child(_haze, 1)
	# Faixas de cinema em cima e embaixo.
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 0.88
		bar.anchor_bottom = 0.12 if top else 1.0
		_root.add_child(bar)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade) # embaixo das legendas: as do preto aparecem
	_caption = UiTheme.label("", 18 if _mobile else 21, UiTheme.TEXT)
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.anchor_left = 0.08
	_caption.anchor_right = 0.92
	_caption.anchor_top = 0.88
	_caption.anchor_bottom = 1.0
	_caption.modulate.a = 0.0
	_root.add_child(_caption)
	_stamp = UiTheme.caps("", 12, Color(UiTheme.ACCENT, 0.85))
	_stamp.name = "Stamp"
	_stamp.anchor_left = 0.04
	_stamp.anchor_top = 0.0
	_stamp.anchor_bottom = 0.12
	_stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_stamp)
	_skip = Button.new()
	_skip.name = "SkipButton"
	_skip.text = "Pular  ›"
	UiTheme.secondary(_skip, 14)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -130 if not _mobile else -150
	_skip.offset_right = -20
	_skip.offset_top = 14
	_skip.offset_bottom = 54 if not _mobile else 62
	_skip.visible = false
	_skip.pressed.connect(skip)
	_root.add_child(_skip)

func _sea_material(amp: float, shore: bool) -> ShaderMaterial:
	var shader := Shader.new()
	# Na praia a água é transparente na beira (a areia aparece por baixo).
	shader.code = SEA_SHADER if not shore else SEA_SHADER.replace("SPECULAR = 0.55;", "SPECULAR = 0.55;
	ALPHA = mix(0.3, 0.97, smoothstep(0.0, 10.0, to_shore));")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("amp", amp)
	mat.set_shader_parameter("shore_on", 1.0 if shore else 0.0)
	return mat

func _build_world() -> void:
	var world := Node3D.new()
	world.name = "Storm"
	_viewport.add_child(world)
	_we = WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("#0a1115")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#2a3a46")
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color("#0d161b")
	_env.fog_density = 0.0055
	_env.glow_enabled = not _mobile
	_env.glow_intensity = 0.9
	_env.glow_bloom = 0.05
	_we.environment = _env
	world.add_child(_we)
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color("#9fb4c6")
	_moon.light_energy = 0.28
	_moon.rotation_degrees = Vector3(-38, 35, 0)
	_moon.directional_shadow_max_distance = 40.0
	world.add_child(_moon)
	_camera = Camera3D.new()
	_camera.fov = 62
	_camera.far = 900
	_camera.current = true
	world.add_child(_camera)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(560, 560)
	plane.subdivide_width = 120 if _mobile else 220
	plane.subdivide_depth = 120 if _mobile else 220
	sea.mesh = plane
	sea.position = Vector3(-20, 0, 40)
	sea.extra_cull_margin = 4.0
	_sea = _sea_material(1.0, false)
	sea.material_override = _sea
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(sea)
	_build_ship(world)
	_build_boats_and_debris(world)
	# Chuva presa à câmera, inclinada pelo vento.
	_rain = CPUParticles3D.new()
	_rain.amount = 350 if _mobile else 800
	_rain.lifetime = 0.7
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(16, 1, 16)
	_rain.direction = Vector3(0.35, -1, 0.15)
	_rain.spread = 4.0
	_rain.initial_velocity_min = 26
	_rain.initial_velocity_max = 32
	_rain.visibility_aabb = AABB(Vector3(-24, -26, -24), Vector3(48, 32, 48))
	var streak := BoxMesh.new()
	streak.size = Vector3(0.02, 0.6, 0.02)
	streak.material = _unlit(Color(0.62, 0.72, 0.8, 0.45), true)
	_rain.mesh = streak
	_rain.position = Vector3(0, 12, 0)
	_camera.add_child(_rain)

func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = at
	m.rotation_degrees = rot
	m.material_override = _lit_mat(color)
	parent.add_child(m)
	return m

func _lit_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat

func _unlit(color: Color, alpha := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if alpha:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _spray_burst(amount: int, extents: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.8
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.direction = Vector3(0, 1, 0.5)
	p.spread = 30
	p.initial_velocity_min = 10
	p.initial_velocity_max = 22
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	var fade_out := Gradient.new()
	fade_out.set_color(0, Color(1, 1, 1, 0.55))
	fade_out.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = fade_out
	var drop := SphereMesh.new()
	drop.radius = 0.3
	drop.height = 0.6
	drop.radial_segments = 5
	drop.rings = 2
	var foam := _unlit(Color(0.66, 0.72, 0.74), true)
	foam.vertex_color_use_as_albedo = true
	drop.material = foam
	p.mesh = drop
	return p

## Navio do Blender: duas metades (Proa e Popa) com pivô no ponto de quebra.
## As janelas de cada convés são um material próprio (apagam de baixo para cima).
func _build_ship(world: Node3D) -> void:
	_ship = Node3D.new()
	_ship.name = "AuroraDoSul"
	world.add_child(_ship)
	var model := (load(SHIP_PATH) as PackedScene).instantiate() as Node3D
	_ship.add_child(model)
	_bow = model.find_child("Proa", true, false) as Node3D
	_stern = model.find_child("Popa", true, false) as Node3D
	_bow_base = _bow.transform
	_stern_base = _stern.transform
	var order := ["Vigias", "Janelas_D0", "Janelas_D1", "Janelas_D2", "Janelas_D3", "Janelas_D4", "Janelas_D5"]
	var shared := {}
	for half in [_bow, _stern]:
		var mi := half as MeshInstance3D
		if mi == null:
			mi = half.find_children("*", "MeshInstance3D", true, false)[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or not order.has(mat.resource_name):
				continue
			if not shared.has(mat.resource_name):
				var copy := mat.duplicate() as StandardMaterial3D
				copy.emission_enabled = true
				shared[mat.resource_name] = copy
			mi.set_surface_override_material(s, shared[mat.resource_name])
	for key in order:
		if shared.has(key):
			_deck_mats.append(shared[key])
			_deck_energy.append(maxf(1.5, (shared[key] as StandardMaterial3D).emission_energy_multiplier))
	for i in 4:
		var light := OmniLight3D.new()
		light.light_color = Color("#ffc77a")
		light.light_energy = 2.4
		light.omni_range = 30
		light.position = Vector3(-40 + i * 26, 12, 16 if i % 2 == 0 else -16)
		_ship.add_child(light)
		_ship_lights.append(light)
	_spray = _spray_burst(420, Vector3(45, 1, 1))
	_spray.position = Vector3(0, 0, 12)
	_ship.add_child(_spray)
	_break_spray = _spray_burst(300, Vector3(4, 1, 10))
	_break_spray.position = Vector3(-6, 2, 0)
	_break_spray.initial_velocity_max = 16
	_ship.add_child(_break_spray)
	_build_blast()

## Fogo e fumaça: quadrados virados para a câmera com uma mancha redonda.
func _puff_material(glow: bool) -> StandardMaterial3D:
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # fogo soma luz; fumaça cobre
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	return mat

func _ramp(stops: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return float(s[0])))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	return g

func _grow(from: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, from))
	c.add_point(Vector2(1, 1))
	return c

func _puffs(amount: int, lifetime: float, ramp: Array, size_min: float, size_max: float, quad_size: float = 4.0, glow: bool = true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount if not _mobile else maxi(8, amount / 2)
	p.lifetime = lifetime
	p.local_coords = false
	p.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * quad_size
	quad.material = _puff_material(glow)
	p.mesh = quad
	p.color_ramp = _ramp(ramp)
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.scale_amount_curve = _grow(0.35)
	return p

func _build_blast() -> void:
	# Casa de máquinas: embaixo da chaminé, no costado virado para a câmera.
	var at := Node3D.new()
	at.name = "EngineRoomBlast"
	at.position = Vector3(-24, 15, 9.5) # espaço da popa (pivô no ponto de quebra)
	_stern.add_child(at)
	_fireball = _puffs(110, 2.0, [[0.0, Color(1, 0.62, 0.26, 0.75)], [0.3, Color(0.95, 0.34, 0.07, 0.6)], [0.7, Color(0.4, 0.1, 0.02, 0.35)], [1.0, Color(0.1, 0.03, 0.01, 0)]], 2.5, 6.0)
	_fireball.one_shot = true
	_fireball.explosiveness = 0.95
	_fireball.direction = Vector3(0, 0.6, 1)
	_fireball.spread = 70
	_fireball.initial_velocity_min = 5
	_fireball.initial_velocity_max = 13
	_fireball.damping_min = 6
	_fireball.damping_max = 10
	_fireball.gravity = Vector3(0, 2.5, 0)
	_fireball.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_fireball.emission_sphere_radius = 2.5
	at.add_child(_fireball)
	_smoke = _puffs(70, 7.0, [[0.0, Color(0.16, 0.13, 0.12, 0.0)], [0.08, Color(0.14, 0.12, 0.11, 0.75)], [1.0, Color(0.09, 0.09, 0.1, 0.0)]], 4.0, 9.0, 5.0, false)
	_smoke.direction = Vector3(0, 1, 0)
	_smoke.spread = 18
	_smoke.initial_velocity_min = 3
	_smoke.initial_velocity_max = 6
	_smoke.gravity = Vector3(2.5, 1.0, 0) # o vento leva a fumaça
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_smoke.emission_box_extents = Vector3(5, 1, 3)
	at.add_child(_smoke)
	_fire = _puffs(70, 0.9, [[0.0, Color(1, 0.85, 0.45, 0.0)], [0.15, Color(1, 0.62, 0.2, 0.95)], [0.6, Color(0.85, 0.28, 0.08, 0.6)], [1.0, Color(0.2, 0.06, 0.03, 0.0)]], 1.4, 3.2, 3.2)
	_fire.direction = Vector3(0, 1, 0)
	_fire.spread = 12
	_fire.initial_velocity_min = 2
	_fire.initial_velocity_max = 5
	_fire.gravity = Vector3(0, 3, 0)
	_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_fire.emission_box_extents = Vector3(6, 0.5, 2.5)
	at.add_child(_fire)
	_blast_debris = CPUParticles3D.new()
	_blast_debris.amount = 40 if not _mobile else 20
	_blast_debris.lifetime = 3.5
	_blast_debris.one_shot = true
	_blast_debris.explosiveness = 1.0
	_blast_debris.emitting = false
	_blast_debris.local_coords = false
	_blast_debris.direction = Vector3(0, 0.7, 1)
	_blast_debris.spread = 75
	_blast_debris.initial_velocity_min = 12
	_blast_debris.initial_velocity_max = 30
	_blast_debris.angular_velocity_min = -400
	_blast_debris.angular_velocity_max = 400
	_blast_debris.scale_amount_min = 0.4
	_blast_debris.scale_amount_max = 1.6
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.6, 0.15, 0.4)
	chunk.material = _lit_mat(Color("#2a2622"))
	_blast_debris.mesh = chunk
	at.add_child(_blast_debris)
	_blast_light = OmniLight3D.new()
	_blast_light.light_color = Color("#ff8a3c")
	_blast_light.light_energy = 0.0
	_blast_light.omni_range = 70
	_blast_light.position = Vector3(0, 2, 2)
	at.add_child(_blast_light)

func _lifeboat(parent: Node3D, color: Color) -> Node3D:
	var boat := Node3D.new()
	parent.add_child(boat)
	var hull := MeshInstance3D.new()
	var capsule := SphereMesh.new()
	capsule.radius = 1.0
	capsule.height = 2.0
	hull.mesh = capsule
	hull.scale = Vector3(3.4, 0.75, 1.2)
	hull.material_override = _lit_mat(color)
	boat.add_child(hull)
	_box(boat, Vector3(4.6, 0.7, 1.9), Vector3(0, 0.55, 0), Color("#8c8f8a"))
	return boat

func _build_boats_and_debris(world: Node3D) -> void:
	for i in 4:
		var boat := _lifeboat(world, Color("#9a5428"))
		boat.visible = false
		var flare := OmniLight3D.new()
		flare.light_color = Color("#ff8a4a")
		flare.light_energy = 1.4
		flare.omni_range = 9
		flare.position = Vector3(1.5, 1.8, 0)
		boat.add_child(flare)
		_lifeboats.append(boat)
	var wood := Color("#4a3726")
	for i in 22:
		var node := Node3D.new()
		node.visible = false
		world.add_child(node)
		var lift := 0.05
		match i % 5:
			0, 1: _box(node, Vector3(_rng.randf_range(2.0, 3.8), 0.16, 0.45), Vector3.ZERO, wood)
			2: _box(node, Vector3(1.1, 1.1, 1.1), Vector3.ZERO, Color("#3d3328")); lift = 0.1
			3: node.add_child(_buoy())
			4:
				_box(node, Vector3(1.8, 0.12, 0.7), Vector3.ZERO, Color("#6d6a63")) # espreguiçadeira
				_box(node, Vector3(0.12, 0.6, 0.7), Vector3(0.9, 0.3, 0), Color("#6d6a63"))
		var base := Vector3(_rng.randf_range(-30, 30), 0, _rng.randf_range(20, 70))
		if i < 9: # perto da câmera final
			base = Vector3(14, 0, 72) + Vector3(_rng.randf_range(-12, 8), 0, _rng.randf_range(-14, 4))
		_debris.append({"node": node, "base": base, "spin": _rng.randf_range(-0.2, 0.2), "lift": lift})
	_my_plank = Node3D.new()
	_my_plank.visible = false
	world.add_child(_my_plank)
	_box(_my_plank, Vector3(0.6, 0.18, 2.6), Vector3.ZERO, Color("#56402b"))
	_box(_my_plank, Vector3(0.9, 0.12, 0.4), Vector3(0.1, 0.05, -0.5), Color("#56402b"), Vector3(0, 25, 0))

func _buoy() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.7
	ring.mesh = torus
	ring.material_override = _lit_mat(Color("#9c3b2a"))
	return ring

## Praia ao amanhecer: areia, mar calmo com espraiado, mata, pedras,
## destroços do navio e o náufrago (o avatar do jogador) deitado.
func _build_beach() -> void:
	var beach := Node3D.new()
	beach.name = "Beach"
	beach.position = BEACH
	_viewport.add_child(beach)
	_dawn = Environment.new()
	_dawn.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3c4b5e")
	sky_mat.sky_horizon_color = Color("#b48a6c")
	sky_mat.ground_horizon_color = Color("#6f5d4c")
	sky_mat.ground_bottom_color = Color("#2b2a27")
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_dawn.sky = sky
	_dawn.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_dawn.ambient_light_energy = 0.8
	_dawn.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_dawn.fog_enabled = true
	_dawn.fog_light_color = Color("#7e7469")
	_dawn.fog_density = 0.0022
	_dawn.fog_sky_affect = 0.3
	_dawn.glow_enabled = not _mobile
	_dawn.glow_intensity = 0.5
	# Areia (malha com a mesma altura de sand_height).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 1.5
	var nx := 80
	var nz := 60
	for iz in nz:
		for ix in nx:
			var quad := []
			for c in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var x: float = -60.0 + (ix + int(c[0])) * cell
				var z: float = -20.0 + (iz + int(c[1])) * cell
				quad.append(Vector3(x, sand_height(x, z), z))
			for tri in [[0, 1, 2], [0, 2, 3]]: # sentido horário visto de cima = normal para cima
				for k in tri:
					var p: Vector3 = quad[k]
					st.set_uv(Vector2(p.x, p.z) * 0.25)
					st.add_vertex(p)
	st.generate_normals()
	var sand := MeshInstance3D.new()
	sand.name = "Sand"
	sand.mesh = st.commit()
	sand.material_override = _sand_material()
	beach.add_child(sand)
	_beach_water = MeshInstance3D.new()
	_beach_water.name = "ShoreSea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 300)
	plane.subdivide_width = 90
	plane.subdivide_depth = 60
	plane.center_offset = Vector3(0, 0, -146)
	_beach_water.mesh = plane
	_beach_sea = _sea_material(0.07, true)
	_beach_water.material_override = _beach_sea
	_beach_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beach.add_child(_beach_water)
	# Mata atrás da praia e pedras na beira.
	var rng := RandomNumberGenerator.new()
	rng.seed = 610
	var variants := ["oak_a", "oak_b", "pine_a", "birch", "pine_b", "oak_a"]
	for i in 70:
		var x := rng.randf_range(-70, 70)
		var z := rng.randf_range(24, 60) + absf(x) * 0.05
		_nature(beach, variants[i % variants.size()], Vector3(x, sand_height(x, z) - 0.2, z), rng.randf_range(0.9, 1.4), rng.randf() * TAU)
	for i in 30:
		var x := rng.randf_range(-60, 60)
		var z := rng.randf_range(18, 30)
		_nature(beach, "bush_empty", Vector3(x, sand_height(x, z) - 0.1, z), rng.randf_range(1.0, 1.8), rng.randf() * TAU)
	for i in 14:
		var x := rng.randf_range(-45, 45)
		if absf(x) < 6.0:
			continue
		var z := rng.randf_range(-6, 16)
		_nature(beach, "rock", Vector3(x, sand_height(x, z) - 0.3, z), rng.randf_range(1.2, 3.2), rng.randf() * TAU)
	var landing := Node3D.new()
	landing.position = Vector3(0, 0, 4)
	beach.add_child(landing)
	_add_wreckage(landing, func(x: float, z: float) -> float: return sand_height(x, z + 4.0))
	_castaway_at = Vector3(0, sand_height(0, 4.0), 4.0)
	_add_castaway(beach, _castaway_at, PI) # levanta olhando para a mata (+Z)

## Destroços na areia: bote encalhado, chapa do casco, tábuas, boia, mala.
## `ground(x, z)` = altura do chão no espaço local de `parent`.
func _add_wreckage(parent: Node3D, ground: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 611
	var boat := _lifeboat(parent, Color("#8a4c26"))
	boat.position = Vector3(9, float(ground.call(9.0, 5.0)) + 0.15, 5)
	boat.rotation_degrees = Vector3(8, -35, 18)
	var plate := _box(parent, Vector3(7, 0.25, 3.2), Vector3(-11, float(ground.call(-11.0, 1.0)) + 0.2, 1), Color("#1b242b"), Vector3(4, 20, -12))
	plate.name = "HullPlate"
	for i in 7:
		var x := rng.randf_range(-8, 8)
		var z := rng.randf_range(-1, 8)
		if Vector2(x, z).distance_to(Vector2(0, 0)) < 2.2:
			continue
		_box(parent, Vector3(rng.randf_range(1.6, 3.0), 0.14, 0.4), Vector3(x, float(ground.call(x, z)) + 0.05, z), Color("#4f3b28"), Vector3(0, rng.randf_range(0, 180), rng.randf_range(-6, 6)))
	var buoy := _buoy()
	buoy.position = Vector3(2.2, float(ground.call(2.2, -0.8)) + 0.08, -0.8)
	parent.add_child(buoy)
	_box(parent, Vector3(0.75, 0.5, 0.28), Vector3(-2.6, float(ground.call(-2.6, 1.5)) + 0.12, 1.5), Color("#3a2a20"), Vector3(70, 30, 0)) # mala

## Areia: grão de ruído em tons de areia, projetado no mundo.
func _sand_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var img := noise.get_seamless_image(128, 128)
	img.convert(Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var v := img.get_pixel(x, y).r
			img.set_pixel(x, y, Color("#87734f").lerp(Color("#b5a07a"), v))
	img.generate_mipmaps()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.18
	return mat

## O náufrago: avatar escolhido pelo jogador, deitado.
func _add_castaway(parent: Node3D, at: Vector3, yaw: float) -> void:
	_castaway = CharacterRegistry.create_visual(CharacterRegistry.load_selection())
	if _castaway == null:
		_castaway = CharacterRegistry.create_visual(CharacterRegistry.DEFAULT_ID)
	if _castaway == null:
		return
	_castaway.name = "Castaway"
	parent.add_child(_castaway)
	_castaway.position = at # coordenadas de `parent`
	_castaway.rotation.y = yaw
	_lie_down.call_deferred()

## Primeiro quadro de "levantar do chão" parado = deitado na areia.
func _lie_down() -> void:
	if _castaway == null or not _castaway.has_method("play_overlay"):
		return
	if not bool(_castaway.call("play_overlay", "laytoidle", "full", 0.0, 1.0, -1.0)):
		# O modelo ainda carrega: tenta de novo no próximo quadro.
		if is_inside_tree():
			await get_tree().process_frame
			_lie_down()

func _nature(parent: Node3D, variant: String, at: Vector3, scale: float, yaw: float) -> void:
	var m := MeshInstance3D.new()
	m.mesh = NatureModel.mesh(variant, 0)
	m.position = at
	m.scale = Vector3.ONE * scale
	m.rotation.y = yaw
	parent.add_child(m)

func _build_audio() -> void:
	_storm = _player(RainWeather._rain_sound(), -8)
	_thunder = _player(_thunder_sound(), -2)
	_horn = _player(_horn_sound(), -6)
	_creak = _player(_creak_sound(), -3)
	_boom = _player(_boom_sound(), 0)
	_surf = _player(_surf_sound(), -40)

func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	add_child(p)
	return p

static func _pcm(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream

## Trovão: estalo curto e ronco grave que vai sumindo.
static func _thunder_sound() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := int(22050 * 3.2)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	for i in n:
		var s := float(i) / 22050.0
		var white := rng.randf_range(-1, 1)
		brown = clampf(brown + white * 0.06, -1.0, 1.0) * 0.995
		var crack := white * exp(-s * 18.0) * 0.8
		var rumble := brown * 2.2 * exp(-s * 1.1) * (0.6 + 0.4 * sin(s * 9.0 + sin(s * 3.0) * 2.0)) * minf(1.0, s * 12.0)
		out[i] = crack + rumble
	return _pcm(out)

## Apito grave de navio, com harmônicos.
static func _horn_sound() -> AudioStreamWAV:
	var n := int(22050 * 3.0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var s := float(i) / 22050.0
		var env := minf(1.0, s / 0.25) * minf(1.0, (3.0 - s) / 0.6)
		var ph := TAU * 74.0 * s + sin(s * 5.0) * 0.15
		out[i] = env * 0.42 * (sin(ph) + 0.55 * sin(ph * 2.0) + 0.35 * sin(ph * 3.0) + 0.2 * sin(ph * 4.0))
	return _pcm(out)

## Explosão: estalo seco, baque grave e ronco que some.
static func _boom_sound() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var n := int(22050 * 3.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var brown := 0.0
	for i in n:
		var s := float(i) / 22050.0
		var white := rng.randf_range(-1, 1)
		brown = clampf(brown + white * 0.08, -1.0, 1.0) * 0.993
		var crack := white * exp(-s * 25.0)
		var thump := sin(TAU * (48.0 - 20.0 * minf(s, 1.0)) * s) * exp(-s * 3.2) * 0.9
		var rumble := brown * 2.4 * exp(-s * 0.9) * minf(1.0, s * 30.0)
		out[i] = crack + thump + rumble
	return _pcm(out)

## Casco rasgando: gemido metálico grave que desce, com estalos.
static func _creak_sound() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var n := int(22050 * 3.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var brown := 0.0
	for i in n:
		var s := float(i) / 22050.0
		var f := lerpf(62.0, 31.0, s / 3.5) * (1.0 + 0.04 * sin(s * 37.0))
		ph += TAU * f / 22050.0
		brown = clampf(brown + rng.randf_range(-1, 1) * 0.05, -1.0, 1.0) * 0.996
		var saw := fmod(ph / TAU, 1.0) * 2.0 - 1.0
		var pops := rng.randf_range(-1, 1) * (1.0 if rng.randf() < 0.002 else 0.0)
		var env := minf(1.0, s / 0.2) * minf(1.0, (3.5 - s) / 1.2)
		out[i] = env * (saw * 0.35 + brown * 1.2 + pops * 0.9)
	return _pcm(out)

## Ondas quebrando na areia (6 s em loop: chega, espalha, recua).
static func _surf_sound() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var n := 22050 * 6
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var lower := 0.0
	for i in n:
		var s := float(i) / 22050.0
		var white := rng.randf_range(-1, 1)
		low = lerpf(low, white, 0.25)
		lower = lerpf(lower, white, 0.03)
		var cycle := fmod(s, 6.0) / 6.0
		var swell := pow(sin(PI * cycle), 3.0)
		out[i] = (low * 0.5 * swell + lower * 2.5 * (0.35 + 0.65 * swell)) * 0.8
	return _pcm(out, true)
