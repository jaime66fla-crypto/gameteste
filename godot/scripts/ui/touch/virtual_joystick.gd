extends RefCounted
## Joystick virtual do polegar esquerdo (usado por touch_controls.gd).
## - Flutuante: a base nasce onde o polegar encosta e acompanha o dedo quando
##   ele passa do raio (nunca "perde" o joystick).
## - Fixo: a base fica sempre no mesmo lugar (rest); só pega o dedo que
##   encostar perto dela.
## Zona morta reescalada: logo depois da zona morta o valor começa em 0, não
## num pulo. Ao soltar, o pino volta suave ao centro (só o desenho; o valor
## de entrada zera na hora).

## Índice do dedo (InputEventScreenTouch.index) que está no joystick, ou -1.
var finger := -1
## Centro da base, em pixels do Control.
var base := Vector2.ZERO
## Valor de entrada (-1..1), já com zona morta.
var value := Vector2.ZERO
## Onde a base descansa quando ninguém toca (e onde fica no modo fixo).
var rest := Vector2.ZERO
var radius := 72.0
var deadzone := 0.12
var fixed := false

## Posição do pino só para desenho (anda suave de volta ao centro).
var _shown := Vector2.ZERO
var _raw := Vector2.ZERO

func is_active() -> bool:
	return finger >= 0

## Tenta pegar um dedo novo. Devolve true se o joystick ficou com ele.
func press(index: int, pos: Vector2) -> bool:
	if finger >= 0:
		return false
	if fixed:
		if pos.distance_to(rest) > radius * 1.6:
			return false
		base = rest
	else:
		base = pos
	finger = index
	drag(pos)
	return true

## Dedo arrastou: atualiza o valor. Devolve o valor novo.
func drag(pos: Vector2) -> Vector2:
	var offset := pos - base
	if offset.length() > radius:
		if not fixed:
			base = pos - offset.normalized() * radius
		offset = offset.limit_length(radius)
	_raw = offset / radius
	value = apply_deadzone(_raw, deadzone)
	return value

func release() -> void:
	finger = -1
	value = Vector2.ZERO
	_raw = Vector2.ZERO

## Chamar todo frame: anima o pino (segue o dedo, volta suave ao soltar).
func update(delta: float) -> void:
	var k := 1.0 if finger >= 0 else 1.0 - exp(-delta * 14.0)
	_shown = _shown.lerp(_raw, k)

static func apply_deadzone(v: Vector2, dz: float) -> Vector2:
	var length := v.length()
	if length <= dz or dz >= 1.0:
		return Vector2.ZERO
	return v / length * minf((length - dz) / (1.0 - dz), 1.0)

## Desenha no CanvasItem dado. `running` pinta o pino de laranja.
func draw(canvas: CanvasItem, alpha: float, ui_scale: float, running: bool, accent: Color) -> void:
	var center := base if finger >= 0 else rest
	var idle := finger < 0 and _shown.length() < 0.02
	canvas.draw_circle(center, radius, Color(0, 0, 0, (0.18 if idle else 0.28) * alpha))
	canvas.draw_arc(center, radius, 0, TAU, 48, Color(1, 1, 1, (0.35 if idle else 0.55) * alpha), 2.0 * ui_scale)
	if deadzone > 0.0 and not idle:
		canvas.draw_arc(center, radius * deadzone, 0, TAU, 24, Color(1, 1, 1, 0.18 * alpha), 1.0 * ui_scale)
	var knob := center + _shown * radius
	var knob_color := Color(accent, 0.8 * alpha) if running else Color(1, 1, 1, (0.3 if idle else 0.55) * alpha)
	canvas.draw_circle(knob, radius * 0.42, knob_color)
	if idle:
		# Em repouso: setas nas quatro direções mostram onde fica o joystick.
		var arrow := Color(1, 1, 1, 0.55 * alpha)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var tip: Vector2 = center + dir * radius * 0.86
			var side: Vector2 = Vector2(-dir.y, dir.x) * radius * 0.1
			var back: Vector2 = tip - dir * radius * 0.1
			canvas.draw_polyline(PackedVector2Array([back + side, tip, back - side]), arrow, 2.0 * ui_scale)
