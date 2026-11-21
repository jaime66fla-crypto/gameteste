extends RefCounted
## Original synthesized fauna and tool foley. Cached mono finite clips, no external assets.
const Synth = preload("res://scripts/audio/synth.gd")
static var _cache: Dictionary = {}

static func sound(kind: String, pain: bool = false) -> AudioStreamWAV:
	var key := kind + ("_pain" if pain else "")
	if _cache.has(key):
		return _cache[key]
	var impact := kind in ["wood", "stone"]
	var seconds := 0.32 if impact else (1.8 if kind == "wolf" and not pain else 0.65)
	var b := Synth.noise(seconds, hash(key))
	Synth.lowpass(b, 3500.0 if impact else 1200.0)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / Synth.RATE
		var u := t / seconds
		if impact:
			var freq := 155.0 if kind == "wood" else 1850.0
			var ring := sin(TAU * freq * t) * exp(-t * (32.0 if kind == "wood" else 18.0))
			b[i] = b[i] * exp(-t * 36.0) * 1.8 + ring * 0.45
		else:
			var freq := 95.0 if kind == "boar" else (240.0 if kind == "deer" else 340.0)
			freq *= (1.4 if pain else 1.0) * (0.85 + 0.3 * sin(PI * u))
			phase += TAU * freq / Synth.RATE
			var throat := sin(phase) + 0.35 * sin(phase * 2.0) + 0.17 * sin(phase * 3.0)
			var pulse := 0.6 + 0.4 * sin(TAU * 12.0 * t) if kind == "boar" else 1.0
			b[i] = (throat * 0.55 + b[i] * (0.8 if kind == "boar" else 0.16)) * pulse * pow(sin(PI * u), 0.8)
		b[i] *= minf(1.0, t / 0.003) * minf(1.0, (seconds - t) / 0.018)
	Synth.normalize(b, 0.75)
	var wav := Synth.to_wav(b)
	_cache[key] = wav
	return wav
