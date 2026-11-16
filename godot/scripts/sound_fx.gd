extends Node3D
## Lightweight synthetic SFX, generated once in memory: no external asset licensing.
const RATE := 22050
const SHOT_LENGTH := 0.19
# Remote actors keep positional audio. The local player opts out before _ready.
@export var spatial_audio := true
var shot_sound: AudioStreamWAV
var reload_sound: AudioStreamWAV
var step_sound: AudioStreamWAV
var shot_player: Node
var reload_player: AudioStreamPlayer
var step_player: Node
var step_timer := 0.0

func _ready() -> void:
    shot_sound = _make_wave(0.22, 1)
    reload_sound = _make_wave(0.31, 2)
    step_sound = _make_wave(0.12, 3)
    shot_player = AudioStreamPlayer3D.new() if spatial_audio else AudioStreamPlayer.new()
    shot_player.name = "ShotAudio"
    shot_player.stream = shot_sound
    if shot_player is AudioStreamPlayer3D:
        shot_player.unit_size = 8.0
        shot_player.max_distance = 90.0
    add_child(shot_player)
    reload_player = AudioStreamPlayer.new()
    reload_player.name = "ReloadAudio"
    reload_player.stream = reload_sound
    reload_player.volume_db = -10.0
    add_child(reload_player)
    step_player = AudioStreamPlayer3D.new() if spatial_audio else AudioStreamPlayer.new()
    step_player.name = "FootstepAudio"
    step_player.stream = step_sound
    step_player.volume_db = -15.0
    if step_player is AudioStreamPlayer3D:
        step_player.max_distance = 24.0
    add_child(step_player)

## Feedback sounds (always 2D, created on first use): hit / headshot / kill / hurt.
var _feedback: Dictionary = {}

func _feedback_player(kind: int, duration: float, volume: float) -> AudioStreamPlayer:
    if not _feedback.has(kind):
        var player := AudioStreamPlayer.new()
        player.stream = _make_wave(duration, kind)
        player.volume_db = volume
        player.max_polyphony = 4
        add_child(player)
        _feedback[kind] = player
    return _feedback[kind]

func hit_confirm(headshot: bool) -> void:
    var player := _feedback_player(5, 0.2, -6.0) if headshot else _feedback_player(4, 0.07, -9.0)
    player.pitch_scale = randf_range(0.97, 1.03)
    player.play()

func kill_confirm() -> void:
    _feedback_player(7, 0.38, -7.0).play()

func hurt() -> void:
    var player := _feedback_player(6, 0.26, -4.0)
    player.pitch_scale = randf_range(0.9, 1.08)
    player.play()

func shot(weapon_id: String = "pistol") -> void:
    # Synthetic placeholders: vary timbre without requiring external assets.
    var pitch_ranges := {
        "pistol": Vector2(0.94, 1.06),
        "smg": Vector2(1.25, 1.42),
        "rifle": Vector2(0.76, 0.89),
        "shotgun": Vector2(0.48, 0.61),
        "sniper": Vector2(0.58, 0.70)
    }
    var range_value: Vector2 = pitch_ranges.get(weapon_id, Vector2(0.94, 1.06))
    shot_player.pitch_scale = randf_range(range_value.x, range_value.y)
    shot_player.volume_db = 0.0 if weapon_id == "shotgun" or weapon_id == "sniper" else -4.0
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
        elif kind == 4:
            # Hit marker: short bright click.
            sample = (sin(TAU * 1900.0 * t) * 0.7 + noise * 0.3) * pow(1.0 - phase, 3.0) * 0.9
        elif kind == 5:
            # Headshot: metallic "tink" with two inharmonic partials.
            sample = (sin(TAU * 2350.0 * t) * 0.55 + sin(TAU * 3720.0 * t) * 0.35 + noise * 0.1) * exp(-t * 22.0)
        elif kind == 6:
            # Taking damage: dull low thud.
            sample = (sin(TAU * (95.0 - 40.0 * phase) * t) * 0.75 + previous_noise * 0.4) * pow(1.0 - phase, 2.0)
        elif kind == 7:
            # Kill confirmed: quick descending two-note chime.
            var note := 1320.0 if phase < 0.4 else 880.0
            sample = sin(TAU * note * t) * 0.6 * exp(-fmod(t, 0.152) * 14.0) * (1.0 - phase)
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
