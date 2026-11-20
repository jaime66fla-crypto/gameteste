extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
	else:
		print("ok: " + message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://scripts/audio/bow_audio.gd"):
		check(false, "bow draw and release audio exists")
		quit(1)
		return
	var sound: Node = load("res://scripts/audio/bow_audio.gd").new()
	root.add_child(sound)
	var draw: AudioStreamPlayer = sound.get_node("BowDraw")
	var release: AudioStreamPlayer = sound.get_node("BowRelease")
	check(not draw.playing and not release.playing, "equipped idle bow stays silent")
	sound.call("begin_draw")
	check(draw.playing and not release.playing, "press plays cord tension without a shot")
	for i in 8:
		await physics_frame
	var position := draw.get_playback_position()
	sound.call("begin_draw")
	check(draw.get_playback_position() >= position - 0.02, "holding does not restart the drawing sound")
	check(draw.stream.get_length() > 0.75 and draw.stream.get_length() < 1.15, "draw foley fits the existing 0.9 second animation")
	sound.call("cancel_draw")
	await (sound.get("_fade") as Tween).finished
	await process_frame
	check(not draw.playing and not release.playing, "cancel fades cord sound without a release twang")
	sound.call("begin_draw")
	sound.call("release_arrow", 1.0)
	check(release.playing, "actual shot starts the bowstring snap immediately")
	await (sound.get("_fade") as Tween).finished
	await process_frame
	check(not draw.playing, "shot ends the pull sound")
	check(release.stream.get_length() > 0.3 and release.stream.get_length() < 1.2, "release has a short natural tail")
	for sample in sound.get("DRAW") + sound.get("RELEASE"):
		check(sample is AudioStreamWAV and sample.loop_mode == AudioStreamWAV.LOOP_DISABLED, "foley is a finite WAV rather than an endless tension loop")
	sound.queue_free()
	for i in 5:
		await physics_frame
	print("BOW AUDIO: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
