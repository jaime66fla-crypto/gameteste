extends Control
## Resolution-independent closed optic. Drawn locally, never consumes input.
var magnification := 4.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    focus_mode = Control.FOCUS_NONE
    resized.connect(queue_redraw)

func set_magnification(value: float) -> void:
    if not is_equal_approx(value, magnification):
        magnification = value
        queue_redraw()

func _draw() -> void:
    var center := size * 0.5
    var radius := minf(size.x, size.y) * 0.44
    if radius < 10:
        return
    var outer := size.length()
    # Ring polygons form a circular hole without textures or stretched masks.
    for segment in range(96):
        var a := TAU * segment / 96.0
        var b := TAU * (segment + 1) / 96.0
        var near_a := Vector2(cos(a), sin(a))
        var near_b := Vector2(cos(b), sin(b))
        draw_colored_polygon(PackedVector2Array([center + near_a * radius, center + near_b * radius, center + near_b * outer, center + near_a * outer]), Color.BLACK)
    draw_arc(center, radius, 0, TAU, 128, Color("#353b38"), 5.0, true)
    var ink := Color("#101713")
    var end := radius - 8.0
    for axis in [Vector2.RIGHT, Vector2.DOWN]:
        draw_line(center - axis * end, center - axis * 3, ink, 1.2, true)
        draw_line(center + axis * 3, center + axis * end, ink, 1.2, true)
    for tick in range(1, 5):
        var distance := radius * tick * 0.14
        var half_width := 5.0 if tick % 2 == 0 else 3.0
        for side in [-1.0, 1.0]:
            draw_line(center + Vector2(side * distance, -half_width), center + Vector2(side * distance, half_width), ink, 1.0, true)
        draw_line(center + Vector2(-half_width, distance), center + Vector2(half_width, distance), ink, 1.0, true)
    draw_circle(center, 1.5, Color("#b44437"))
    draw_string(get_theme_default_font(), center + Vector2(-35, radius * 0.76), "%.0f×" % magnification, HORIZONTAL_ALIGNMENT_CENTER, 70, 20, Color("#cbd3c1"))
