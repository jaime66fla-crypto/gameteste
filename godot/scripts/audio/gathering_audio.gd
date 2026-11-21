extends "res://scripts/audio/nature_voice.gd"
## Driven by the same work clock and impact phase as the visible tool.
var _action := ""
var _last_impact := -1

func set_action(action: String) -> void:
	_action = action if action in ["chop", "pry"] else ""
	_last_impact = -1
	stop()

func tick_work(time: float, cycle: float) -> void:
	if _action.is_empty():
		return
	var impact := int(floor(time / cycle - 0.64))
	if impact >= 0 and impact > _last_impact:
		_last_impact = impact
		play_sound("wood" if _action == "chop" else "stone")
