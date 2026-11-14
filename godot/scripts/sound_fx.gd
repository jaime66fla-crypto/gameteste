extends Node
## Lightweight synthetic SFX, generated once in memory: no external asset licensing.
const RATE := 22050
const SHOT_LENGTH := 0.19
var shot_sound: AudioStreamWAV
var reload_sound: AudioStreamWAV
var step_sound: AudioStreamWAV
var shot_player: AudioStreamPlayer3D
var reload_player: AudioStreamPlayer
var step_player: AudioStreamPlayer3D
var step_timer := 0.0

func _ready() -> void:
    shot_sound = _make_wave(0.22, 1)
    reload_sound = _make_wave(0.31, 2)
    step_sound = _make_wave(0.12, 3)
    shot_player = AudioStreamPlayer3D.new()
    shot_player.name = "ShotAudio"
    shot_player.stream = shot_sound
    shot_player.unit_size = 8.0
    shot_player.max_distance = 90.0
    add_child(shot_player)
    reload_player = AudioStreamPlayer.new()
    reload_player.name = "ReloadAudio"
    reload_player.stream = reload_sound
    reload_player.volume_db = -10.0
    add_child(reload_player)
    step_player = AudioStreamPlayer3D.new()
    step_player.name = "FootstepAudio"
    step_player.stream = step_sound
    step_player.volume_db = -15.0
    step_player.max_distance = 24.0
    add_child(step_player)

func shot() -> void:
    shot_player.pitch_scale = randf_range(0.94, 1.06)
    shot_player.play()

func reload() -> void:
    reload_player.play()

func update_steps(delta: float, grounded: bool, moving: bool, sprinting: bool, crouching: bool) -> void:
    if not grounded or not moving:
        step_timer = 0.0
        return
    step_timer -= delta
    if step_timer > 0.0:
        return
    step_timer = 0.28 if sprinting else (0.65 if crouching else 0.43)
    step_player.pitch_scale = randf_range(0.88, 1.1)
    step_player.volume_db = -22.0 if crouching else -16.0
    step_player.play()

func _make_wave(duration: float, kind: int) -> AudioStreamWAV:
    var count := int(RATE * duration)
    var pcm := PackedByteArray()
    pcm.resize(count * 2)
    var rng := RandomNumberGenerator.new()
    rng.seed = 9031 + kind * 31
    var previous_noise := 0.0
    for i in range(count):
        var t := float(i) / float(RATE)
        var phase := t / duration
        var noise := rng.randf_range(-1.0, 1.0)
        previous_noise = lerpf(previous_noise, noise, 0.45)
        var sample := 0.0
        if kind == 1:
            var click := (1.0 - phase) * (1.0 - phase)
            sample = (noise * 0.65 + sin(TAU * (100.0 * t + 130.0 * t * t)) * 0.35) * click
        elif kind == 2:
            var first := exp(-absf(t - 0.055) * 65.0)
            var second := exp(-absf(t - 0.20) * 58.0)
            sample = (previous_noise * 0.7 + sin(TAU * t * 640.0) * 0.3) * (first + second) * 0.55
        else:
            sample = (previous_noise * 0.75 + sin(TAU * t * 85.0) * 0.25) * pow(1.0 - phase, 2.0) * 0.4
        var signed_sample := int(clampf(sample, -1.0, 1.0) * 25000.0)
        pcm.encode_s16(i * 2, signed_sample)
    var wav := AudioStreamWAV.new()
    wav.format = AudioStreamWAV.FORMAT_16_BITS
    wav.mix_rate = RATE
    wav.stereo = false
    wav.data = pcm
    return wav
