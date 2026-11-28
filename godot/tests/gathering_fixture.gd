extends "res://scripts/survival/survival_controller.gd"
## Deterministic nearby resource; skips world/network setup for the movement test.
var target_fixture: Dictionary
func _ready() -> void:
	set_physics_process(false)
	set_process(false)
func _find_target() -> Dictionary:
	return target_fixture
