extends "res://scripts/audio/nature_voice.gd"
var _next_call := randf_range(3.0, 12.0)
var _last_hp := -1.0
var _pain_cooldown := 0.0

func _process(delta: float) -> void:
	var animal := get_parent()
	var hp := float(animal.get("hp"))
	var kind := str(animal.get("kind"))
	_pain_cooldown = maxf(0.0, _pain_cooldown - delta)
	if bool(animal.get("dead")):
		stop()
		return
	if kind not in ["boar", "deer", "wolf"]:
		return
	if _last_hp >= 0.0 and hp < _last_hp and _pain_cooldown <= 0.0:
		play_sound(kind, true)
		_pain_cooldown = 0.8
		_next_call = randf_range(8.0, 18.0)
	_last_hp = hp
	_next_call -= delta
	if _next_call <= 0.0:
		_next_call = randf_range(12.0, 26.0)
		if not playing:
			play_sound(kind)
