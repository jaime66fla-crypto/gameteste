extends SceneTree
var failures := 0
class Fauna extends Node3D:
	var hp := 80.0
	var kind := "boar"
	var dead := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var bank = load("res://scripts/audio/nature_sfx.gd")
	for kind in ["boar", "deer", "wolf", "wood", "stone"]:
		var stream: AudioStreamWAV = bank.sound(kind)
		check(stream.get_length() > 0.2 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, kind + " finite original mono sound")
		check(not stream.stereo, kind + " positional mono")
	var gathering: AudioStreamPlayer3D = load("res://scripts/audio/gathering_audio.gd").new()
	root.add_child(gathering)
	gathering.call("set_action", "chop")
	gathering.call("tick_work", 0.5, 0.95)
	check(not gathering.playing, "preparing swing remains silent")
	gathering.call("tick_work", 0.62, 0.95)
	check(gathering.playing, "tree impact occurs at visible strike phase")
	gathering.stop()
	gathering.call("tick_work", 0.7, 0.95)
	check(not gathering.playing, "one impact per stroke")
	gathering.call("tick_work", 1.6, 0.95)
	check(gathering.playing, "continuous gathering repeats next strike")
	gathering.call("set_action", "")
	gathering.call("tick_work", 3.0, 0.95)
	check(not gathering.playing, "cancel immediately stops and suppresses impacts")
	gathering.call("set_action", "pry")
	gathering.call("tick_work", 0.62, 0.95)
	check(gathering.stream == bank.sound("stone"), "mining selects stone foley")
	gathering.stop()
	var animal := Fauna.new()
	root.add_child(animal)
	var audio: AudioStreamPlayer3D = load("res://scripts/audio/animal_audio.gd").new()
	animal.add_child(audio)
	audio.call("_process", 0.01)
	animal.hp = 60.0
	audio.call("_process", 0.01)
	check(audio.playing and audio.stream == bank.sound("boar", true), "replicated damage produces positional pain")
	animal.dead = true
	audio.call("_process", 0.01)
	check(not audio.playing, "dead fauna stops calling")
	check(audio.max_distance == 45.0 and audio.unit_size == 5.0, "spatial attenuation has bounded audible range")
	var voices: Array = []
	for i in 12:
		var voice = load("res://scripts/audio/nature_voice.gd").new()
		root.add_child(voice)
		voice.play_sound("wolf")
		voices.append(voice)
	var active := 0
	for voice in voices:
		if voice.playing:
			active += 1
	check(active == 8, "crowded fauna is limited to eight concurrent voices")
	for voice in voices:
		voice.free()
	animal.free()
	gathering.free()
	print("NATURE AUDIO: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
