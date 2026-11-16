extends Control
## Screen-space combat feedback: hit marker at the crosshair and arcs that
## point toward whoever is damaging the local player.

var _hit_alpha := 0.0
var _hit_head := false
var _hit_kill := false
var _hit_scale := 1.0
# Each entry: {angle (radians, 0 = straight ahead, clockwise), alpha}
var _damage_arcs: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_hit(headshot: bool, kill: bool = false) -> void:
	_hit_alpha = 1.0
	_hit_head = headshot or (_hit_head and _hit_alpha > 0.5)
	_hit_kill = kill or (_hit_kill and _hit_alpha > 0.5)
	_hit_scale = 1.6 if kill else (1.3 if headshot else 1.0)

func show_damage_from(angle: float) -> void:
	for arc in _damage_arcs:
		if absf(angle_difference(arc["angle"], angle)) < 0.4:
			arc["alpha"] = 1.0
			return
	_damage_arcs.append({"angle": angle, "alpha": 1.0})

func _process(delta: float) -> void:
	_hit_alpha = move_toward(_hit_alpha, 0.0, delta * (1.8 if _hit_kill else 3.2))
	_hit_scale = move_toward(_hit_scale, 1.0, delta * 3.0)
	if _hit_alpha <= 0.0:
		_hit_head = false
		_hit_kill = false
	for arc in _damage_arcs:
		arc["alpha"] = move_toward(arc["alpha"], 0.0, delta * 0.7)
	_damage_arcs = _damage_arcs.filter(func(arc): return arc["alpha"] > 0.0)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	if _hit_alpha > 0.0:
		var color := Color("#ff3b30") if (_hit_head or _hit_kill) else Color(1, 1, 1)
		color.a = _hit_alpha
		var inner := 7.0 * _hit_scale
		var outer := (15.0 if not _hit_kill else 19.0) * _hit_scale
		var width := 3.0 if (_hit_head or _hit_kill) else 2.0
		for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var unit: Vector2 = direction.normalized()
			draw_line(center + unit * inner, center + unit * outer, Color(0, 0, 0, color.a * 0.5), width + 2.0, true)
			draw_line(center + unit * inner, center + unit * outer, color, width, true)
	var radius := minf(size.x, size.y) * 0.22
	for arc in _damage_arcs:
		# 0 = top of the screen (in front), positive = clockwise (to the right).
		var mid: float = arc["angle"] - PI * 0.5
		var color := Color(0.9, 0.08, 0.05, 0.85 * arc["alpha"])
		draw_arc(center, radius, mid - 0.32, mid + 0.32, 24, color, 9.0, true)
