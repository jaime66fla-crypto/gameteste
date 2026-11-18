extends RefCounted
## Banco de sons do jogo, montados pelo Synth. Cada função devolve um
## AudioStreamWAV em cache (gerado só uma vez por partida).
const Synth = preload("res://scripts/audio/synth.gd")

# ---------------------------------------------------------------- armas ---
# Receita de cada arma: corpo grave (Hz início → fim, queda), ruído do estampido
# (queda, brilho), cauda de eco, e o mecanismo (ferrolho, bomba).
const GUNS := {
	"pistol":  {"f0": 210.0, "f1": 70.0, "body": 0.035, "blast": 0.045, "bright": 4200.0, "low": 700.0, "tail": 0.55, "crack": 0.9, "drive": 1.7, "mech": [[0.035, 0.12]]},
	"smg":     {"f0": 260.0, "f1": 90.0, "body": 0.025, "blast": 0.03, "bright": 5200.0, "low": 800.0, "tail": 0.45, "crack": 0.8, "drive": 1.6, "mech": [[0.03, 0.14]]},
	"rifle":   {"f0": 170.0, "f1": 55.0, "body": 0.05, "blast": 0.06, "bright": 4800.0, "low": 650.0, "tail": 0.9, "crack": 1.0, "drive": 1.9, "mech": [[0.04, 0.1]]},
	"shotgun": {"f0": 120.0, "f1": 40.0, "body": 0.09, "blast": 0.11, "bright": 3000.0, "low": 450.0, "tail": 1.3, "crack": 0.7, "drive": 2.2, "mech": [[0.42, 0.35], [0.56, 0.4]]},
	"sniper":  {"f0": 140.0, "f1": 38.0, "body": 0.1, "blast": 0.12, "bright": 4000.0, "low": 420.0, "tail": 1.6, "crack": 1.2, "drive": 2.3, "mech": [[0.7, 0.3], [0.86, 0.35]]},
}
const GUN_VARIANTS := 2

static var _warm := false

## Carrega o banco todo de uma vez (no início da partida), para nenhum som
## engasgar o jogo na primeira vez que toca. Com os .wav gravados é rápido.
static func warmup() -> void:
	if _warm:
		return
	_warm = true
	_add_master_limiter()
	warm_all()

## Limitador na saída: rajada + explosão + zumbis juntos nunca passam de 0 dB
## (era o que "estourava"). Não muda nada quando o som já está abaixo do teto.
static func _add_master_limiter() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, limiter)

## Todos os sons do banco, pelo nome com que são gravados.
static func warm_all() -> void:
	for id in GUNS:
		for v in GUN_VARIANTS:
			gun(id, v)
	reload_sound()
	for v in 3:
		step(v)
	hit_body()
	hit_head()
	kill()
	notify()
	hurt(false)
	zombie_bite()
	swing()
	melee_impact()
	for v in 3:
		zombie_snarl(v)
	zombie_swipe()
	engine_loop(false)
	engine_loop(true)
	road_loop()
	skid_loop()
	starter()
	crash()
	hurt(true)
	for v in 3:
		zombie_groan(v)
		zombie_pain(v)
		zombie_death(v)

static func gun(weapon_id: String, variant: int) -> AudioStream:
	var id := weapon_id if GUNS.has(weapon_id) else "pistol"
	return Synth.get_stream("gun_%s_%d" % [id, variant], func(): return _build_gun(id, variant))

static func _build_gun(id: String, variant: int) -> AudioStream:
	var g: Dictionary = GUNS[id]
	var seed_value := hash(id) + variant * 977
	var length := float(g["tail"]) + 0.35
	var out := Synth.buffer(length)
	# 1) Estalo supersônico / percussão: ruído agudo curtíssimo.
	var crack := Synth.noise(0.02, seed_value)
	Synth.highpass(crack, 2500.0)
	Synth.envelope(crack, 0.0003, 0.0025)
	Synth.mix(out, crack, float(g["crack"]))
	# 2) Estampido: ruído com brilho que escurece (duas faixas).
	var blast := Synth.noise(0.5, seed_value + 1)
	var blast_low := blast.duplicate()
	Synth.lowpass(blast, float(g["bright"]))
	Synth.envelope(blast, 0.0008, float(g["blast"]))
	Synth.lowpass(blast_low, float(g["low"]))
	Synth.envelope(blast_low, 0.002, float(g["blast"]) * 2.2)
	Synth.mix(out, blast, 0.8)
	Synth.mix(out, blast_low, 1.6)
	# 3) Corpo: o "soco" grave que dá peso.
	var body := Synth.sweep(0.6, float(g["f0"]) * (1.0 + variant * 0.04), float(g["f1"]), 0.07)
	Synth.envelope(body, 0.0015, float(g["body"]))
	Synth.mix(out, body, 1.1)
	Synth.saturate(out, float(g["drive"]))
	# 4) Rua/paredes: reflexões escuras e um ronco longo que some.
	var tail := Synth.noise(float(g["tail"]), seed_value + 2)
	Synth.lowpass(tail, 380.0)
	Synth.envelope(tail, 0.02, float(g["tail"]) * 0.28)
	Synth.mix(out, tail, 0.9, 0.01)
	out = Synth.echo(out, [0.075 + variant * 0.01, 0.16, 0.27, 0.41], [0.32, 0.2, 0.12, 0.06], 1600.0)
	# 5) Mecanismo: ferrolho/bomba (metal contra metal).
	var m := 0
	for click in g["mech"]:
		Synth.mix(out, _metal_click(seed_value + 10 + m, m), float(click[1]), float(click[0]))
		m += 1
	Synth.normalize(out, 0.85)
	Synth.fade_tail(out, 0.05)
	return Synth.to_wav(out)

static func _metal_click(seed_value: int, flavor: int) -> PackedFloat32Array:
	var b := Synth.noise(0.09, seed_value)
	Synth.bandpass(b, 1800.0, 7000.0)
	Synth.envelope(b, 0.0005, 0.006)
	var ring := Synth.sweep(0.09, 3100.0 + flavor * 400.0, 2900.0 + flavor * 400.0, 0.05)
	Synth.envelope(ring, 0.0005, 0.012)
	Synth.mix(b, ring, 0.35)
	var thud := Synth.sweep(0.09, 420.0, 260.0, 0.03)
	Synth.envelope(thud, 0.001, 0.01)
	Synth.mix(b, thud, 0.4)
	return b

## Recarga: tira o pente, encaixa, puxa o ferrolho.
static func reload_sound() -> AudioStream: # "reload" é método do próprio Script
	return Synth.get_stream("reload", func():
		var out := Synth.buffer(1.0)
		Synth.mix(out, _metal_click(71, 0), 0.5, 0.05)
		var slide := Synth.noise(0.12, 72)
		Synth.bandpass(slide, 900.0, 3500.0)
		Synth.envelope(slide, 0.03, 0.04)
		Synth.mix(out, slide, 0.25, 0.12)
		Synth.mix(out, _metal_click(73, 1), 0.8, 0.48)
		Synth.mix(out, _metal_click(74, 2), 0.6, 0.8)
		Synth.mix(out, _metal_click(75, 0), 0.7, 0.87)
		Synth.normalize(out, 0.8)
		return Synth.to_wav(out))

## Passos: três variações de terra/asfalto.
static func step(variant: int) -> AudioStream:
	return Synth.get_stream("step_%d" % variant, func():
		var b := Synth.noise(0.14, 300 + variant)
		Synth.lowpass(b, 900.0 + variant * 250.0)
		Synth.envelope(b, 0.002, 0.025)
		var heel := Synth.sweep(0.14, 95.0, 55.0, 0.05)
		Synth.envelope(heel, 0.001, 0.02)
		Synth.mix(b, heel, 0.7)
		var grit := Synth.noise(0.14, 310 + variant)
		Synth.highpass(grit, 3000.0)
		Synth.envelope(grit, 0.004, 0.018, 0.01)
		Synth.mix(b, grit, 0.12)
		Synth.normalize(b, 0.8)
		Synth.fade_tail(b)
		return Synth.to_wav(b))

# --------------------------------------------------- dano causado (acerto) ---

## Acerto no corpo: estalo seco + baque de carne.
static func hit_body() -> AudioStream:
	return Synth.get_stream("hit_body", func():
		var out := Synth.buffer(0.18)
		var tick := Synth.sweep(0.18, 2700.0, 2300.0, 0.02)
		Synth.envelope(tick, 0.0004, 0.012)
		Synth.mix(out, tick, 0.55)
		Synth.mix(out, _flesh(401, 0.05), 1.0, 0.004)
		Synth.normalize(out, 0.85)
		Synth.fade_tail(out)
		return Synth.to_wav(out))

## Tiro na cabeça: "tink" metálico + estalo de osso + baque.
static func hit_head() -> AudioStream:
	return Synth.get_stream("hit_head", func():
		var out := Synth.buffer(0.45)
		var tink := Synth.sweep(0.45, 2350.0, 2330.0, 0.1)
		Synth.envelope(tink, 0.0004, 0.07)
		var tink2 := Synth.sweep(0.45, 3720.0, 3700.0, 0.1)
		Synth.envelope(tink2, 0.0004, 0.045)
		Synth.mix(out, tink, 0.5)
		Synth.mix(out, tink2, 0.35)
		var crunch := Synth.noise(0.08, 411)
		Synth.bandpass(crunch, 1400.0, 6000.0)
		Synth.envelope(crunch, 0.0005, 0.01)
		Synth.mix(out, crunch, 0.7, 0.003)
		Synth.mix(out, _flesh(412, 0.06), 0.9, 0.005)
		Synth.normalize(out, 0.9)
		Synth.fade_tail(out)
		return Synth.to_wav(out))

## Abate confirmado: baque grave e um sino curto descendo.
static func kill() -> AudioStream:
	return Synth.get_stream("kill", func():
		var out := Synth.buffer(0.6)
		var thunk := Synth.sweep(0.6, 140.0, 48.0, 0.12)
		Synth.envelope(thunk, 0.002, 0.09)
		Synth.mix(out, thunk, 0.9)
		var a := Synth.sweep(0.6, 1318.0, 1318.0, 1.0)
		Synth.envelope(a, 0.002, 0.07)
		var b := Synth.sweep(0.6, 880.0, 880.0, 1.0)
		Synth.envelope(b, 0.002, 0.16)
		Synth.mix(out, a, 0.28)
		Synth.mix(out, b, 0.3, 0.09)
		Synth.saturate(out, 1.4)
		Synth.normalize(out, 0.8)
		Synth.fade_tail(out, 0.05)
		return Synth.to_wav(out))

## Notificação (convite chegou): duas notas suaves subindo.
static func notify() -> AudioStream:
	return Synth.get_stream("notify", func():
		var out := Synth.buffer(0.7)
		for note in [[987.8, 0.0], [1318.5, 0.11]]:
			var tone := Synth.sweep(0.6, note[0], note[0], 1.0)
			var octave := Synth.sweep(0.6, note[0] * 2.0, note[0] * 2.0, 1.0)
			Synth.mix(tone, octave, 0.18)
			Synth.envelope(tone, 0.006, 0.16)
			Synth.mix(out, tone, 0.5, note[1])
		out = Synth.echo(out, [0.09, 0.18], [0.22, 0.1], 3000.0)
		Synth.normalize(out, 0.7)
		Synth.fade_tail(out, 0.06)
		return Synth.to_wav(out))

## Arma branca: zunido do golpe.
static func swing() -> AudioStream:
	return Synth.get_stream("swing", func(): return Synth.to_wav(_whoosh(501, 0.32, 0.55)))

## Arma branca acertando: pancada seca de madeira/metal na carne.
static func melee_impact() -> AudioStream:
	return Synth.get_stream("melee_impact", func():
		var out := Synth.buffer(0.35)
		var knock := Synth.sweep(0.35, 230.0, 120.0, 0.05)
		Synth.envelope(knock, 0.001, 0.04)
		Synth.mix(out, knock, 1.0)
		Synth.mix(out, _flesh(511, 0.08), 1.1, 0.002)
		var crack := Synth.noise(0.05, 512)
		Synth.bandpass(crack, 1200.0, 5000.0)
		Synth.envelope(crack, 0.0004, 0.006)
		Synth.mix(out, crack, 0.5)
		Synth.saturate(out, 2.0)
		Synth.normalize(out, 0.9)
		Synth.fade_tail(out)
		return Synth.to_wav(out))

# ---------------------------------------------------- dano sentido (levar) ---

## Levou dano: impacto abafado no corpo (forte = mais grave e longo).
static func hurt(heavy: bool) -> AudioStream:
	return Synth.get_stream("hurt_%d" % int(heavy), func():
		var length := 1.4 if heavy else 0.4
		var out := Synth.buffer(length)
		var thump := Synth.sweep(length, 120.0 if heavy else 150.0, 42.0, 0.14)
		Synth.envelope(thump, 0.002, 0.14 if heavy else 0.08)
		Synth.mix(out, thump, 1.0)
		Synth.mix(out, _flesh(601 + int(heavy), 0.09 if heavy else 0.06), 0.8, 0.003)
		var air := Synth.noise(length, 603)
		Synth.lowpass(air, 350.0)
		Synth.envelope(air, 0.004, 0.12)
		Synth.mix(out, air, 0.6)
		Synth.saturate(out, 1.8)
		if heavy:
			# Zumbido no ouvido depois do golpe forte.
			var ring := Synth.sweep(length, 3900.0, 3800.0, 1.0)
			Synth.envelope(ring, 0.08, 0.45, 0.05)
			Synth.mix(out, ring, 0.07)
		Synth.normalize(out, 0.9)
		Synth.fade_tail(out, 0.08)
		return Synth.to_wav(out))

## Mordida/arranhão de zumbi em quem leva: rasgo úmido + baque.
static func zombie_bite() -> AudioStream:
	return Synth.get_stream("zombie_bite", func():
		var out := Synth.buffer(0.6)
		var rng := RandomNumberGenerator.new()
		rng.seed = 701
		# Rasgo: grãos de ruído médio em sequência.
		var t := 0.0
		while t < 0.28:
			var grain := Synth.noise(0.05, rng.randi())
			Synth.bandpass(grain, 500.0, 2800.0)
			Synth.envelope(grain, 0.002, 0.008 + rng.randf() * 0.01)
			Synth.mix(out, grain, 0.35 + rng.randf() * 0.35, t)
			t += 0.012 + rng.randf() * 0.02
		Synth.mix(out, _flesh(702, 0.07), 1.0)
		var squelch := Synth.sweep(0.6, 380.0, 110.0, 0.18)
		Synth.envelope(squelch, 0.01, 0.07, 0.04)
		Synth.mix(out, squelch, 0.45)
		Synth.saturate(out, 1.6)
		Synth.normalize(out, 0.9)
		Synth.fade_tail(out, 0.05)
		return Synth.to_wav(out))

# -------------------------------------------------------------- zumbis ---

## Rosnado do bote (posicional, sai do zumbi). Variações com tom diferente.
static func zombie_snarl(variant: int) -> AudioStream:
	return Synth.get_stream("zsnarl_%d" % variant, func(): return Synth.to_wav(_growl(801 + variant, 0.55, 105.0 + variant * 14.0, 1.35, 0.9)))

## Gemido longo de zumbi perseguindo.
static func zombie_groan(variant: int) -> AudioStream:
	return Synth.get_stream("zgroan_%d" % variant, func(): return Synth.to_wav(_growl(851 + variant, 1.3 + variant * 0.2, 72.0 + variant * 9.0, 0.85, 0.55)))

## Grito curto de dor quando o zumbi leva tiro/golpe.
static func zombie_pain(variant: int) -> AudioStream:
	return Synth.get_stream("zpain_%d" % variant, func(): return Synth.to_wav(_growl(871 + variant, 0.32, 150.0 + variant * 22.0, 1.7, 1.0)))

## Morte: gemido longo que cai de tom, com gorgolejo.
static func zombie_death(variant: int) -> AudioStream:
	return Synth.get_stream("zdeath_%d" % variant, func():
		var b := _growl(891 + variant, 1.4, 120.0 + variant * 15.0, 0.55, 0.8)
		for i in b.size():
			var t := float(i) / Synth.RATE
			b[i] *= 0.55 + 0.45 * sin(t * TAU * (13.0 - t * 5.0))
		var thud := Synth.sweep(1.4, 90.0, 45.0, 0.1)
		Synth.envelope(thud, 0.003, 0.08, 1.05) # o corpo bate no chão
		Synth.mix(b, thud, 0.5)
		Synth.normalize(b, 0.85)
		Synth.fade_tail(b, 0.08)
		return Synth.to_wav(b))

## Zunido dos braços no golpe do zumbi.
static func zombie_swipe() -> AudioStream:
	return Synth.get_stream("zswipe", func(): return Synth.to_wav(_whoosh(811, 0.28, 0.4)))

## Voz rouca: dente de serra com tremor, rascado por ruído, filtrado em formantes.
static func _growl(seed_value: int, length: float, f0: float, rise: float, rasp: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := Synth.buffer(length)
	var grit := Synth.noise(length, seed_value + 1)
	Synth.lowpass(grit, 600.0)
	var phase := 0.0
	var jitter := 0.0
	for i in b.size():
		var t := float(i) / Synth.RATE
		var k := t / length
		jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.01)
		var f := f0 * lerpf(1.0, rise, sin(k * PI * 0.7)) * (1.0 + jitter * 0.12 + sin(t * TAU * 6.5) * 0.03)
		phase = fmod(phase + f / Synth.RATE, 1.0)
		var saw := phase * 2.0 - 1.0
		b[i] = saw * (1.0 - rasp * 0.5 + rasp * grit[i] * 3.0)
	var vowel := b.duplicate()
	Synth.bandpass(vowel, 550.0, 1100.0)
	Synth.bandpass(b, 120.0, 2200.0)
	Synth.mix(b, vowel, 1.4)
	# Envelope: entra rápido, sustenta e morre.
	for i in b.size():
		var k := float(i) / b.size()
		b[i] *= minf(1.0, k * 12.0) * pow(1.0 - k, 1.4)
	Synth.saturate(b, 2.2)
	Synth.normalize(b, 0.85)
	return b

## Zunido de ar: ruído com filtro que abre e fecha.
static func _whoosh(seed_value: int, length: float, peak_at: float) -> PackedFloat32Array:
	var b := Synth.noise(length, seed_value)
	var y1 := 0.0
	var y2 := 0.0
	var n := b.size()
	for i in n:
		var k := float(i) / n
		var shape := exp(-pow((k - peak_at) / 0.22, 2.0))
		var cutoff := 300.0 + 2600.0 * shape
		var a := 1.0 - exp(-TAU * cutoff / Synth.RATE)
		y1 += a * (b[i] - y1)
		y2 += a * (y1 - y2)
		b[i] = (y1 - y2 * 0.6) * shape
	Synth.normalize(b, 0.8)
	Synth.fade_tail(b)
	return b

## Baque de carne (base de todos os impactos no corpo).
static func _flesh(seed_value: int, decay: float) -> PackedFloat32Array:
	var b := Synth.noise(decay * 6.0, seed_value)
	Synth.lowpass(b, 1100.0)
	Synth.envelope(b, 0.001, decay * 0.6)
	var thump := Synth.sweep(decay * 6.0, 170.0, 70.0, decay)
	Synth.envelope(thump, 0.001, decay)
	Synth.mix(b, thump, 0.9)
	return b

# --------------------------------------------------------------- carros ---

## Motor em loop. `base` = frequência de explosões (Hz inteiro, loop de 1 s
## sem emenda). Camada grave (rotação baixa) e aguda (alta), cruzadas pelo RPM.
static func engine_loop(high: bool) -> AudioStream:
	return Synth.get_stream("engine_%d" % int(high), func():
		var base := 96.0 if high else 32.0
		var b := Synth.buffer(1.1)
		var exhaust := Synth.noise(1.1, 901 + int(high))
		Synth.lowpass(exhaust, 1400.0 if high else 800.0)
		var phases := [0.0, 1.3, 2.1, 0.7, 2.9, 1.8, 0.4, 2.5, 1.1, 0.2, 2.2, 1.6]
		var cyl := [1.0, 0.84, 0.95, 0.79] # 4 cilindros levemente diferentes
		var amp := 1.0
		for i in b.size():
			var t := float(i) / Synth.RATE
			var cycle := t * base
			var x := fmod(cycle, 1.0)
			amp = lerpf(amp, float(cyl[int(cycle) % 4]), 0.004)
			var tone := 0.0
			for h in range(1, 13):
				tone += sin(TAU * base * h * t + float(phases[h - 1])) / pow(h, 1.05 if high else 1.25)
			var pulse := exp(-x * 5.0)
			b[i] = (tone * 0.5 + exhaust[i] * pulse * (2.2 if high else 1.6)) * amp
		Synth.lowpass(b, 4200.0 if high else 2200.0)
		Synth.highpass(b, 35.0)
		Synth.saturate(b, 1.8 if high else 1.5)
		var loop := Synth.make_loop(b, 0.1)
		Synth.normalize(loop, 0.8)
		return Synth.to_wav(loop, true))

## Ronco de pneu no asfalto (loop).
static func road_loop() -> AudioStream:
	return Synth.get_stream("road", func():
		var b := Synth.noise(1.6, 921)
		Synth.bandpass(b, 60.0, 420.0)
		var loop := Synth.make_loop(b, 0.2)
		Synth.normalize(loop, 0.7)
		return Synth.to_wav(loop, true))

## Pneu cantando (loop).
static func skid_loop() -> AudioStream:
	return Synth.get_stream("skid", func():
		var b := Synth.noise(0.9, 931)
		Synth.bandpass(b, 700.0, 2600.0)
		var phase := 0.0
		for i in b.size():
			var t := float(i) / Synth.RATE
			phase += TAU * (1150.0 + sin(t * TAU * 7.0) * 60.0) / Synth.RATE
			b[i] = b[i] * 0.6 + sin(phase) * 0.35
		var loop := Synth.make_loop(b, 0.15)
		Synth.normalize(loop, 0.7)
		return Synth.to_wav(loop, true))

## Partida: motor de arranque girando e o motor pegando.
static func starter() -> AudioStream:
	return Synth.get_stream("starter", func():
		var out := Synth.buffer(1.0)
		var crank := Synth.buffer(0.6)
		var phase := 0.0
		for i in crank.size():
			var t := float(i) / Synth.RATE
			phase += TAU * 170.0 / Synth.RATE
			var chug := 0.55 + 0.45 * sin(t * TAU * 8.5)
			crank[i] = (sin(phase) + sin(phase * 2.0) * 0.4) * chug
		Synth.lowpass(crank, 1500.0)
		Synth.mix(out, crank, 0.5)
		var catch_ := Synth.noise(0.5, 941)
		Synth.lowpass(catch_, 900.0)
		Synth.envelope(catch_, 0.01, 0.12)
		var rev := Synth.sweep(0.5, 45.0, 90.0, 0.2)
		Synth.envelope(rev, 0.01, 0.16)
		Synth.mix(out, catch_, 0.8, 0.55)
		Synth.mix(out, rev, 0.9, 0.55)
		Synth.saturate(out, 1.6)
		Synth.normalize(out, 0.85)
		Synth.fade_tail(out, 0.08)
		return Synth.to_wav(out))

## Batida: lataria amassando, metal ressoando e vidro.
static func crash() -> AudioStream:
	return Synth.get_stream("crash", func():
		var out := Synth.buffer(1.3)
		var thump := Synth.sweep(1.3, 110.0, 38.0, 0.15)
		Synth.envelope(thump, 0.002, 0.12)
		Synth.mix(out, thump, 1.0)
		var crunch := Synth.noise(1.3, 951)
		Synth.lowpass(crunch, 3200.0)
		Synth.envelope(crunch, 0.002, 0.14)
		Synth.mix(out, crunch, 0.9)
		for partial in [[420.0, 0.35], [1130.0, 0.25], [1870.0, 0.18], [2650.0, 0.12]]:
			var ring := Synth.sweep(1.3, partial[0], partial[0] * 0.985, 1.0)
			Synth.envelope(ring, 0.002, 0.3)
			Synth.mix(out, ring, partial[1])
		var rng := RandomNumberGenerator.new()
		rng.seed = 952
		for k in 14:
			var shard := Synth.noise(0.04, rng.randi())
			Synth.highpass(shard, 4500.0)
			Synth.envelope(shard, 0.0005, 0.006)
			Synth.mix(out, shard, rng.randf_range(0.1, 0.3), 0.03 + rng.randf() * 0.5)
		Synth.saturate(out, 2.0)
		Synth.normalize(out, 0.95)
		Synth.fade_tail(out, 0.1)
		return Synth.to_wav(out))
