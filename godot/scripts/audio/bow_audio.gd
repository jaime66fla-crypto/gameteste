extends Node
## Original offline-rendered foley; local-player mix, like sound_fx.gd.
const DRAW := [preload("res://assets/audio/bow/bow_draw_0.wav"), preload("res://assets/audio/bow/bow_draw_1.wav"), preload("res://assets/audio/bow/bow_draw_2.wav")]
const RELEASE := [preload("res://assets/audio/bow/bow_release_0.wav"), preload("res://assets/audio/bow/bow_release_1.wav"), preload("res://assets/audio/bow/bow_release_2.wav")]
var _draw: AudioStreamPlayer
var _release: AudioStreamPlayer
var _drawing := false
var _fade: Tween
var _variant := 0

func _ready() -> void:
	name = "BowAudio"
	_draw = AudioStreamPlayer.new()
	_draw.name = "BowDraw"
	_draw.stream = DRAW[0]
	_draw.volume_db = -16.0
	add_child(_draw)
	_release = AudioStreamPlayer.new()
	_release.name = "BowRelease"
	_release.stream = RELEASE[0]
	_release.volume_db = -8.0
	_release.max_polyphony = 3
	add_child(_release)

func begin_draw() -> void:
	if _drawing:
		return
	if is_instance_valid(_fade):
		_fade.kill()
	_drawing = true
	_variant = (_variant + 1 + randi() % 2) % DRAW.size()
	_draw.stop()
	_draw.stream = DRAW[_variant]
	_draw.pitch_scale = randf_range(0.985, 1.015)
	_draw.volume_db = -16.0
	_draw.play()

func update_tension(charge: float) -> void:
	if _drawing:
		_draw.volume_db = lerpf(-16.0, -10.0, clampf(charge, 0.0, 1.0))

func cancel_draw() -> void:
	if not _drawing:
		return
	_drawing = false
	if is_instance_valid(_fade):
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_draw, "volume_db", -60.0, 0.025)
	_fade.tween_callback(_draw.stop)

func release_arrow(power: float) -> void:
	cancel_draw()
	_release.stream = RELEASE[(_variant + randi() % RELEASE.size()) % RELEASE.size()]
	_release.pitch_scale = randf_range(0.97, 1.03)
	_release.volume_db = lerpf(-15.0, -7.5, clampf(power, 0.0, 1.0))
	_release.play()

func _exit_tree() -> void:
	if is_instance_valid(_fade):
		_fade.kill()
	if is_instance_valid(_draw):
		_draw.stop()
	if is_instance_valid(_release):
		_release.stop()
