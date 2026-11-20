extends RefCounted
## A release consumes the draw exactly once; losing focus cancels it.
const DRAW_TIME := 0.9
const MIN_DRAW := 0.12
var drawing := false
var charge := 0.0
var _held := 0.0

func press() -> void:
	if not drawing:
		drawing = true
		_held = 0.0
		charge = 0.0

func advance(delta: float) -> void:
	if drawing:
		_held += maxf(delta, 0.0)
		charge = clampf(_held / DRAW_TIME, 0.0, 1.0)

func release() -> float:
	var power := charge if drawing and _held >= MIN_DRAW else 0.0
	cancel()
	return power

func cancel() -> void:
	drawing = false
	charge = 0.0
	_held = 0.0
