extends AudioStreamPlayer3D
## Shared cap includes fauna and work impacts across all nearby actors.
const Bank = preload("res://scripts/audio/nature_sfx.gd")
const VOICE_LIMIT := 8

func _ready() -> void:
	add_to_group("nature_audio_voices")
	max_polyphony = 1
	unit_size = 5.0
	max_distance = 45.0
	max_db = -4.0
	volume_db = -14.0
	attenuation_filter_cutoff_hz = 3800.0
	attenuation_filter_db = -16.0
	if AudioServer.get_bus_index("SFX") >= 0:
		bus = "SFX"

func play_sound(kind: String, pain: bool = false) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera != null and global_position.distance_to(camera.global_position) > max_distance:
		return false
	var active := 0
	for voice in get_tree().get_nodes_in_group("nature_audio_voices"):
		if voice != self and voice.playing:
			active += 1
	if active >= VOICE_LIMIT:
		return false
	stream = Bank.sound(kind, pain)
	pitch_scale = randf_range(0.94, 1.06)
	play()
	return true
