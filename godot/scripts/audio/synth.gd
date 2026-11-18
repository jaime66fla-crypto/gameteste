extends RefCounted
## Síntese de efeitos sonoros em memória (sem arquivos de áudio de terceiros).
## Cada som é montado em camadas, como num estúdio: estalo de ataque, corpo
## grave, ruído filtrado e cauda de eco. Tudo é gerado uma vez e guardado em
## cache estático, compartilhado por todos os jogadores/zumbis/carros.
const RATE := 32000

## Sons já gravados pelo tools/bake_sfx.gd (importados pelo Godot): carregar
## é instantâneo. Sem o arquivo, o som é sintetizado na hora (mais lento).
const BAKED_DIR := "res://assets/audio/sfx/"
const LOOP_KEYS := ["engine_0", "engine_1", "road", "skid"] # tocam em loop
static var use_baked := true # o bake desliga para regravar a partir da síntese
static var _cache: Dictionary = {}

## Som pronto pelo nome (carrega o gravado ou gera na primeira vez).
static func get_stream(key: String, builder: Callable) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var stream: AudioStream = null
	var path := BAKED_DIR + key + ".wav"
	if use_baked and ResourceLoader.exists(path):
		stream = load(path)
		if LOOP_KEYS.has(key) and stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	if stream == null:
		stream = builder.call()
	_cache[key] = stream
	return stream

static func buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

# ------------------------------------------------------------- filtros ---

## Passa-baixa de um polo (cutoff em Hz). Escreve no próprio buffer.
static func lowpass(b: PackedFloat32Array, cutoff: float) -> void:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y

## Passa-alta de um polo.
static func highpass(b: PackedFloat32Array, cutoff: float) -> void:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var low := 0.0
	for i in b.size():
		low += a * (b[i] - low)
		b[i] = b[i] - low

## Passa-faixa simples (alta + baixa).
static func bandpass(b: PackedFloat32Array, low_hz: float, high_hz: float) -> void:
	highpass(b, low_hz)
	lowpass(b, high_hz)

## Ressonador passa-faixa (biquad) em `freq` com qualidade `q`: devolve uma cópia
## filtrada. Vários em paralelo = formantes de voz (as ressonâncias da garganta).
static func resonator(b: PackedFloat32Array, freq: float, q: float) -> PackedFloat32Array:
	var w := TAU * freq / RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var out := PackedFloat32Array()
	out.resize(b.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in b.size():
		var x := b[i]
		var y := b0 * x - b0 * x2 - a1 * y1 - a2 * y2
		out[i] = y
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
	return out

## Ruído branco determinístico.
static func noise(seconds: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := buffer(seconds)
	for i in b.size():
		b[i] = rng.randf_range(-1.0, 1.0)
	return b

## Envelope: ataque linear (s) e queda exponencial (constante de tempo em s).
static func envelope(b: PackedFloat32Array, attack: float, decay: float, start: float = 0.0) -> void:
	var s0 := int(start * RATE)
	var att := maxf(attack * RATE, 1.0)
	var k := 1.0 / maxf(decay * RATE, 1.0)
	for i in b.size():
		var n := i - s0
		var e := 0.0
		if n >= 0:
			e = (float(n) / att) if n < att else exp(-(n - att) * k)
		b[i] *= e

## Mistura `src` em `dst` com ganho, a partir de `offset` segundos.
static func mix(dst: PackedFloat32Array, src: PackedFloat32Array, gain: float, offset: float = 0.0) -> void:
	var o := int(offset * RATE)
	var n := mini(src.size(), dst.size() - o)
	for i in n:
		if o + i >= 0:
			dst[o + i] += src[i] * gain

## Seno com glissando exponencial de f0 para f1 ao longo de `glide` segundos.
static func sweep(seconds: float, f0: float, f1: float, glide: float) -> PackedFloat32Array:
	var b := buffer(seconds)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var k := clampf(t / maxf(glide, 0.0001), 0.0, 1.0)
		var f := f0 * pow(f1 / f0, k)
		phase += TAU * f / RATE
		b[i] = sin(phase)
	return b

## Eco curto (sala/rua): repetições atenuadas e escurecidas.
static func echo(b: PackedFloat32Array, delays: Array, gains: Array, darken: float = 2500.0) -> PackedFloat32Array:
	var wet := b.duplicate()
	lowpass(wet, darken)
	var out := b.duplicate()
	for j in delays.size():
		mix(out, wet, float(gains[j]), float(delays[j]))
	return out

## Saturação suave (dá "peso" sem estourar).
static func saturate(b: PackedFloat32Array, drive: float) -> void:
	var norm := tanh(drive)
	for i in b.size():
		b[i] = tanh(b[i] * drive) / norm

## Normaliza o pico para `peak` (0..1).
static func normalize(b: PackedFloat32Array, peak: float = 0.9) -> void:
	var m := 0.0
	for v in b:
		m = maxf(m, absf(v))
	if m < 0.00001:
		return
	var g := peak / m
	for i in b.size():
		b[i] *= g

## Fade-out final para não estalar no corte.
static func fade_tail(b: PackedFloat32Array, seconds: float = 0.02) -> void:
	var n := mini(int(seconds * RATE), b.size())
	for i in n:
		b[b.size() - 1 - i] *= float(i) / float(n)

## Loop sem emenda: cruza o fim com o começo (o buffer deve ter `xfade` s a mais).
static func make_loop(b: PackedFloat32Array, xfade: float) -> PackedFloat32Array:
	var f := int(xfade * RATE)
	var n := b.size() - f
	var out := b.slice(0, n)
	for i in f:
		var k := float(i) / float(f)
		out[i] = b[i] * k + b[n + i] * (1.0 - k)
	return out

## Converte para AudioStreamWAV 16 bits mono.
static func to_wav(b: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(b.size() * 2)
	for i in b.size():
		pcm.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = pcm
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = b.size()
	return wav
