extends Node3D
## Som do carro: motor em duas camadas (grave/agudo) cruzadas pelo RPM, com
## marchas simuladas (o giro cai na troca), carga do acelerador, ronco de pneu
## pela velocidade, pneu cantando, partida e batida.
const SfxBank = preload("res://scripts/audio/sfx_bank.gd")
const IDLE_RPM := 850.0
const MAX_RPM := 6200.0
const LOW_BASE_RPM := 960.0 # 32 Hz de explosões no loop grave (4 cilindros)
const HIGH_BASE_RPM := 2880.0 # 96 Hz no loop agudo
const GEARS := [0.2, 0.38, 0.58, 0.8, 1.06] # fim de cada marcha (fração da velocidade máxima)

var vehicle: Node # Vehicle (speed, throttle_input, skidding, controlled, max_speed())
var rpm := IDLE_RPM
var running := false
var _engine_gain := 0.0 # 0..1, sobe na partida e desce ao desligar
var _start_delay := 0.0
var _load := 0.0
var _last_speed := 0.0
var _skid_gain := 0.0
var _low: AudioStreamPlayer3D
var _high: AudioStreamPlayer3D
var _road: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _oneshot: AudioStreamPlayer3D

func _ready() -> void:
	position = Vector3(0, 0.8, -1.2) # motor na frente
	_low = _make_player("EngineLow", SfxBank.engine_loop(false), 70.0)
	_high = _make_player("EngineHigh", SfxBank.engine_loop(true), 80.0)
	_road = _make_player("Road", SfxBank.road_loop(), 45.0)
	_skid = _make_player("Skid", SfxBank.skid_loop(), 70.0)
	_oneshot = _make_player("OneShot", null, 90.0)
	_oneshot.max_polyphony = 3

func _make_player(player_name: String, stream: AudioStream, max_distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.stream = stream
	p.unit_size = 7.0
	p.max_distance = max_distance
	p.attenuation_filter_cutoff_hz = 3800.0 # longe fica abafado
	p.attenuation_filter_db = -14.0
	p.volume_db = -80.0
	add_child(p)
	return p

func set_running(on: bool) -> void:
	if on == running:
		return
	running = on
	if on:
		_oneshot.stream = SfxBank.starter()
		_oneshot.volume_db = -4.0
		_oneshot.pitch_scale = randf_range(0.95, 1.05)
		_oneshot.play()
		_start_delay = 0.55 # o motor "pega" no fim da partida
		rpm = IDLE_RPM + 900.0 # aquela acelerada de quando pega

func crash(impact: float) -> void:
	_oneshot.stream = SfxBank.crash()
	_oneshot.volume_db = lerpf(-8.0, 2.0, clampf((impact - 4.5) / 12.0, 0.0, 1.0))
	_oneshot.pitch_scale = randf_range(0.9, 1.08)
	_oneshot.play()

func _process(delta: float) -> void:
	if vehicle == null:
		return
	var speed := absf(float(vehicle.get("speed")))
	var top := maxf(1.0, float(vehicle.call("max_speed")))
	# Carga do motor: do motorista local vem do acelerador; dos outros, da aceleração.
	var load_target := 0.0
	if bool(vehicle.get("controlled")):
		load_target = float(vehicle.get("throttle_input"))
	else:
		var accel := (speed - _last_speed) / maxf(delta, 0.0001)
		load_target = 1.0 if accel > 0.4 else (0.35 if speed > 1.0 else 0.0)
	_last_speed = speed
	_load = lerpf(_load, load_target, 1.0 - exp(-6.0 * delta))
	# RPM pela marcha engatada; parado e acelerando = embreagem patinando.
	var gear := GEARS.size() - 1
	for g in GEARS.size():
		if speed < float(GEARS[g]) * top:
			gear = g
			break
	var frac := speed / (float(GEARS[gear]) * top)
	var target := lerpf(IDLE_RPM + 300.0, MAX_RPM, clampf(frac, 0.0, 1.0))
	if gear == 0:
		target = maxf(target, IDLE_RPM + _load * 1800.0)
	if speed < 0.6 and _load < 0.05:
		target = IDLE_RPM + sin(Time.get_ticks_msec() * 0.004) * 25.0 # marcha lenta "respirando"
	# Sobe com o pé, cai rápido na troca de marcha.
	var rate := 10.0 if target < rpm - 600.0 else 5.0
	rpm = lerpf(rpm, target, 1.0 - exp(-rate * delta))
	# Liga/desliga suave.
	if _start_delay > 0.0:
		_start_delay -= delta
	var want := 1.0 if running and _start_delay <= 0.0 else 0.0
	_engine_gain = move_toward(_engine_gain, want, delta * (3.0 if want > 0.0 else 1.6))
	_update_engine()
	# Pneus: ronco pela velocidade (mesmo desligado, se estiver andando).
	var speed_k := clampf(speed / top, 0.0, 1.0)
	_set_loop(_road, speed_k * 0.75 if speed > 0.5 else 0.0, 0.6 + speed_k * 0.9)
	var skid_target := 1.0 if bool(vehicle.get("skidding")) else 0.0
	_skid_gain = move_toward(_skid_gain, skid_target, delta * (8.0 if skid_target > 0.0 else 4.0))
	_set_loop(_skid, _skid_gain * 0.6, 0.9 + speed_k * 0.25)

func _update_engine() -> void:
	if _engine_gain <= 0.001:
		_set_loop(_low, 0.0, 1.0)
		_set_loop(_high, 0.0, 1.0)
		return
	# Cruzamento de potência constante entre as camadas.
	var x := clampf((rpm - 1800.0) / 1800.0, 0.0, 1.0)
	var low_mix := cos(x * PI * 0.5)
	var high_mix := sin(x * PI * 0.5)
	var loudness := (0.5 + 0.5 * _load) * _engine_gain
	_set_loop(_low, low_mix * loudness, clampf(rpm / LOW_BASE_RPM, 0.5, 3.5))
	_set_loop(_high, high_mix * loudness * (0.8 + 0.4 * _load), clampf(rpm / HIGH_BASE_RPM, 0.4, 2.4))

## Volume linear 0..1 e tom; para o loop quando fica mudo (não gasta mixagem).
func _set_loop(p: AudioStreamPlayer3D, gain: float, pitch: float) -> void:
	if gain <= 0.002:
		if p.playing:
			p.stop()
		return
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(gain) - 3.0
	if not p.playing:
		p.play()
