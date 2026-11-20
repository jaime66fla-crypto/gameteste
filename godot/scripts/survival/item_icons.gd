extends RefCounted
## Ícones dos itens da Sobrevivência, desenhados em vetor (sem arquivos de
## imagem): cada item tem um desenho chapado em tons sóbrios, com contorno
## escuro, no mesmo estilo low-poly do jogo. Itens sem desenho próprio usam a
## cor da categoria com uma letra.
##   ItemIcons.draw(canvas_item, "stone_axe", Rect2(...))

const OUTLINE := Color(0.05, 0.05, 0.06, 0.85)
const WOOD := Color("#8a6440")
const WOOD_DARK := Color("#5c4128")
const STONE := Color("#8d8d88")
const STONE_DARK := Color("#5e5e5a")
const FIBER := Color("#8fa65a")
const LEATHER := Color("#7a5236")
const CAT_COLOR := {"weapon": Color("#d0574a"), "ammo": Color("#d6a23e"), "armor": Color("#6f8fb0"), "melee": Color("#b9824f"), "medical": Color("#e05a6a"), "food": Color("#8fbf5a"), "drink": Color("#4aa3d8"), "gear": Color("#7f9a5b"), "fuel": Color("#e08a2e"), "material": Color("#9a9389")}

## Desenha o ícone de `id` dentro de `r` (quadrado de preferência).
static func draw(ci: CanvasItem, id: String, r: Rect2, cat: String = "") -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var poly := func(points: Array, fill: Color) -> void:
		var pts := PackedVector2Array()
		for q in points:
			pts.append(p.call(q[0], q[1]))
		ci.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		ci.draw_polyline(pts, OUTLINE, maxf(1.0, s * 0.025), true)
	var line := func(a: Array, b: Array, width: float, color: Color) -> void:
		ci.draw_line(p.call(a[0], a[1]), p.call(b[0], b[1]), OUTLINE, s * width + maxf(2.0, s * 0.05), true)
		ci.draw_line(p.call(a[0], a[1]), p.call(b[0], b[1]), color, s * width, true)
	var dot := func(x: float, y: float, radius: float, color: Color) -> void:
		ci.draw_circle(p.call(x, y), s * radius + maxf(1.0, s * 0.025), OUTLINE)
		ci.draw_circle(p.call(x, y), s * radius, color)
	match id:
		"stick":
			line.call([0.2, 0.82], [0.8, 0.18], 0.09, WOOD)
			line.call([0.5, 0.5], [0.72, 0.56], 0.05, WOOD)
			line.call([0.36, 0.66], [0.3, 0.44], 0.045, WOOD_DARK)
		"stone":
			poly.call([[0.18, 0.62], [0.28, 0.36], [0.5, 0.24], [0.74, 0.32], [0.84, 0.56], [0.7, 0.78], [0.38, 0.8]], STONE)
			poly.call([[0.32, 0.4], [0.5, 0.31], [0.62, 0.36], [0.46, 0.46]], STONE.lightened(0.25))
		"fiber":
			for i in 5:
				var x := 0.3 + i * 0.1
				line.call([0.5, 0.85], [x, 0.18 + absf(i - 2) * 0.06], 0.035, FIBER.darkened(0.1 * (i % 2)))
			line.call([0.4, 0.62], [0.6, 0.62], 0.05, Color("#c9b27a"))
		"wood":
			poly.call([[0.14, 0.44], [0.68, 0.28], [0.8, 0.62], [0.26, 0.78]], WOOD)
			dot.call(0.74, 0.45, 0.17, Color("#c49a6c"))
			ci.draw_arc(p.call(0.74, 0.45), s * 0.1, 0, TAU, 20, WOOD_DARK, maxf(1.0, s * 0.02), true)
			ci.draw_arc(p.call(0.74, 0.45), s * 0.045, 0, TAU, 12, WOOD_DARK, maxf(1.0, s * 0.02), true)
		"herb":
			poly.call([[0.5, 0.86], [0.3, 0.6], [0.32, 0.34], [0.5, 0.14], [0.68, 0.34], [0.7, 0.6]], Color("#5f8f4e"))
			line.call([0.5, 0.86], [0.5, 0.22], 0.02, Color("#3d6332"))
			poly.call([[0.5, 0.7], [0.22, 0.62], [0.16, 0.48], [0.34, 0.5]], Color("#79a862"))
		"rope":
			for k in 3:
				ci.draw_arc(p.call(0.5, 0.5), s * (0.32 - k * 0.09), 0, TAU, 28, OUTLINE, s * 0.08 + 2.0, true)
				ci.draw_arc(p.call(0.5, 0.5), s * (0.32 - k * 0.09), 0, TAU, 28, Color("#c9a86b").darkened(k * 0.12), s * 0.07, true)
			line.call([0.78, 0.6], [0.88, 0.86], 0.06, Color("#c9a86b"))
		"berries":
			line.call([0.5, 0.18], [0.46, 0.4], 0.025, Color("#4e6b32"))
			poly.call([[0.5, 0.2], [0.68, 0.12], [0.62, 0.28]], Color("#5f8f4e"))
			for b in [[0.36, 0.56], [0.62, 0.54], [0.5, 0.74]]:
				dot.call(b[0], b[1], 0.15, Color("#8e2a3a"))
				ci.draw_circle(p.call(b[0] - 0.05, b[1] - 0.05), s * 0.035, Color(1, 1, 1, 0.55))
		"bandage":
			poly.call([[0.2, 0.58], [0.6, 0.58], [0.84, 0.82], [0.44, 0.82]], Color("#d9d2bf"))
			dot.call(0.4, 0.44, 0.24, Color("#e8e2d0"))
			dot.call(0.4, 0.44, 0.08, Color("#b8b09a"))
			line.call([0.6, 0.24], [0.6, 0.4], 0.05, Color("#c44a4a"))
			line.call([0.52, 0.32], [0.68, 0.32], 0.05, Color("#c44a4a"))
		"herbal_cure":
			poly.call([[0.34, 0.3], [0.66, 0.3], [0.74, 0.5], [0.7, 0.86], [0.3, 0.86], [0.26, 0.5]], Color("#4f6b45"))
			poly.call([[0.4, 0.16], [0.6, 0.16], [0.6, 0.3], [0.4, 0.3]], WOOD)
			poly.call([[0.5, 0.78], [0.38, 0.62], [0.5, 0.46], [0.62, 0.62]], Color("#9cc77a"))
		"stone_knife":
			line.call([0.2, 0.8], [0.42, 0.58], 0.1, WOOD)
			line.call([0.33, 0.67], [0.38, 0.62], 0.12, Color("#c9b27a"))
			poly.call([[0.4, 0.52], [0.84, 0.14], [0.52, 0.64]], STONE)
		"stone_axe":
			line.call([0.24, 0.86], [0.66, 0.2], 0.08, WOOD)
			poly.call([[0.48, 0.18], [0.82, 0.12], [0.86, 0.46], [0.62, 0.4]], STONE)
			line.call([0.52, 0.36], [0.64, 0.3], 0.07, Color("#c9b27a"))
		"stone_pick":
			line.call([0.3, 0.88], [0.56, 0.28], 0.08, WOOD)
			poly.call([[0.14, 0.32], [0.4, 0.2], [0.56, 0.24], [0.72, 0.2], [0.9, 0.36], [0.62, 0.32], [0.5, 0.34], [0.36, 0.3]], STONE)
		"club":
			poly.call([[0.22, 0.86], [0.3, 0.9], [0.84, 0.3], [0.78, 0.12], [0.6, 0.14]], WOOD)
			for k in [[0.66, 0.28], [0.74, 0.22]]:
				dot.call(k[0], k[1], 0.035, WOOD_DARK)
		"sack_bag", "hide_bag":
			var bag := Color("#b8a477") if id == "sack_bag" else LEATHER
			poly.call([[0.24, 0.38], [0.76, 0.38], [0.84, 0.82], [0.16, 0.82]], bag)
			poly.call([[0.34, 0.2], [0.66, 0.2], [0.76, 0.38], [0.24, 0.38]], bag.darkened(0.15))
			if id == "hide_bag":
				poly.call([[0.24, 0.38], [0.76, 0.38], [0.7, 0.58], [0.3, 0.58]], bag.darkened(0.25))
				dot.call(0.5, 0.56, 0.04, Color("#c9b27a"))
			else:
				line.call([0.3, 0.38], [0.7, 0.38], 0.04, Color("#6b5a3a"))
		"raw_meat":
			poly.call([[0.16, 0.5], [0.3, 0.26], [0.62, 0.2], [0.84, 0.38], [0.8, 0.66], [0.52, 0.82], [0.24, 0.74]], Color("#b8464e"))
			poly.call([[0.3, 0.32], [0.6, 0.27], [0.74, 0.38], [0.5, 0.4]], Color("#e3b8a8"))
			dot.call(0.56, 0.56, 0.08, Color("#efe6d6"))
		"cooked_meat":
			line.call([0.62, 0.38], [0.84, 0.16], 0.07, Color("#efe6d6"))
			dot.call(0.86, 0.14, 0.05, Color("#efe6d6"))
			poly.call([[0.14, 0.62], [0.24, 0.36], [0.46, 0.28], [0.66, 0.4], [0.62, 0.66], [0.4, 0.84], [0.2, 0.8]], Color("#8a4a24"))
			poly.call([[0.26, 0.42], [0.44, 0.34], [0.52, 0.42], [0.34, 0.5]], Color("#b8703a"))
		"hide":
			poly.call([[0.2, 0.24], [0.4, 0.3], [0.6, 0.3], [0.8, 0.22], [0.76, 0.46], [0.86, 0.66], [0.66, 0.68], [0.6, 0.86], [0.4, 0.86], [0.34, 0.68], [0.14, 0.66], [0.24, 0.46]], LEATHER)
			poly.call([[0.4, 0.4], [0.6, 0.4], [0.62, 0.64], [0.38, 0.64]], LEATHER.lightened(0.15))
		_:
			var c: Color = CAT_COLOR.get(cat, Color("#9a9389"))
			var box := Rect2(p.call(0.18, 0.18), Vector2(s, s) * 0.64)
			ci.draw_rect(box, c.darkened(0.45))
			ci.draw_rect(box, c, false, maxf(1.0, s * 0.03))
			var font := ThemeDB.fallback_font
			var letter := id.substr(0, 1).to_upper()
			var size_px := int(s * 0.36)
			var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
			ci.draw_string(font, box.get_center() + Vector2(-w * 0.5, size_px * 0.35), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, c.lightened(0.4))
