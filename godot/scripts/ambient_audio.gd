extends Node3D
## Procedural outdoor wind/foliage ambience, low-volume and looped.
const SAMPLE_RATE := 16000
var player: AudioStreamPlayer
var active := true

func _ready() -> void:
    player = AudioStreamPlayer.new()
    player.name = "OutdoorAmbience"
    player.volume_db = -27.0
    player.stream = _generate_wind()
    add_child(player)
    player.play()

func _generate_wind() -> AudioStreamWAV:
    var seconds := 4.0
    var length := int(SAMPLE_RATE * seconds)
    var pcm := PackedByteArray()
    pcm.resize(length * 2)
    var rng := RandomNumberGenerator.new()
    rng.seed = 20261114
    var lowpass := 0.0
    for i in range(length):
        var t := float(i) / SAMPLE_RATE
        lowpass = lerpf(lowpass, rng.randf_range(-1.0, 1.0), 0.007)
        var gust := 0.65 + 0.2 * sin(TAU * t / seconds) + 0.1 * sin(TAU * t * 0.73)
        var sample := clampf(lowpass * gust * 1.7, -0.8, 0.8)
        pcm.encode_s16(i * 2, int(sample * 26000.0))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = SAMPLE_RATE
    stream.stereo = false
    stream.data = pcm
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = length
    return stream

func set_ambience_enabled(enabled: bool) -> void:
    active = enabled
    if player != null:
        player.stream_paused = not enabled
