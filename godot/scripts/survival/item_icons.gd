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
		"charcoal":
			poly.call([[0.16, 0.6], [0.3, 0.38], [0.56, 0.32], [0.7, 0.5], [0.6, 0.74], [0.3, 0.78]], Color("#2a2724"))
			poly.call([[0.5, 0.56], [0.66, 0.36], [0.84, 0.42], [0.86, 0.66], [0.7, 0.8]], Color("#353130"))
			line.call([0.34, 0.46], [0.48, 0.42], 0.02, Color("#5a524b"))
			dot.call(0.74, 0.6, 0.035, Color("#c0582a"))
		"iron_ore", "saltpeter":
			poly.call([[0.16, 0.64], [0.26, 0.34], [0.5, 0.2], [0.76, 0.3], [0.86, 0.58], [0.68, 0.8], [0.36, 0.82]], STONE_DARK)
			var fleck := Color("#9a5a32") if id == "iron_ore" else Color("#ddd6c2")
			for f in [[0.36, 0.44, 0.07], [0.6, 0.38, 0.05], [0.52, 0.62, 0.08], [0.72, 0.58, 0.04], [0.32, 0.66, 0.04]]:
				dot.call(f[0], f[1], f[2], fleck)
		"iron_bar":
			poly.call([[0.12, 0.6], [0.3, 0.42], [0.88, 0.42], [0.7, 0.6]], Color("#8c9094"))
			poly.call([[0.12, 0.6], [0.7, 0.6], [0.7, 0.72], [0.12, 0.72]], Color("#5f6367"))
			poly.call([[0.7, 0.6], [0.88, 0.42], [0.88, 0.54], [0.7, 0.72]], Color("#4a4d50"))
		"nails":
			for n in [[0.28, 0.0], [0.5, 0.08], [0.72, -0.04]]:
				line.call([n[0], 0.24 + n[1]], [n[0] + 0.04, 0.8 + n[1] * 0.3], 0.04, Color("#9a9ea2"))
				line.call([n[0] - 0.07, 0.24 + n[1]], [n[0] + 0.07, 0.24 + n[1]], 0.05, Color("#b5b9bc"))
		"wood_spear":
			line.call([0.14, 0.9], [0.74, 0.3], 0.07, WOOD)
			poly.call([[0.68, 0.3], [0.9, 0.1], [0.74, 0.38]], STONE)
			line.call([0.64, 0.4], [0.72, 0.3], 0.08, Color("#c9b27a"))
		"iron_knife", "machete":
			var blade_end := [0.86, 0.14] if id == "iron_knife" else [0.9, 0.1]
			line.call([0.18, 0.84], [0.4, 0.62], 0.1, Color("#4a3a2c"))
			poly.call([[0.38, 0.58], blade_end, [0.5, 0.7] if id == "iron_knife" else [0.62, 0.72], [0.44, 0.66]], Color("#a3a8ac"))
		"iron_axe":
			line.call([0.24, 0.86], [0.66, 0.2], 0.08, WOOD_DARK)
			poly.call([[0.5, 0.2], [0.84, 0.1], [0.9, 0.5], [0.64, 0.4]], Color("#8f9498"))
		"iron_pick":
			line.call([0.3, 0.88], [0.56, 0.28], 0.08, WOOD_DARK)
			poly.call([[0.1, 0.36], [0.4, 0.2], [0.56, 0.24], [0.72, 0.2], [0.94, 0.38], [0.62, 0.32], [0.5, 0.34], [0.36, 0.3]], Color("#8f9498"))
		"nail_bat":
			poly.call([[0.2, 0.86], [0.28, 0.9], [0.84, 0.32], [0.76, 0.14], [0.62, 0.16]], WOOD)
			for k in [[0.62, 0.22], [0.72, 0.3], [0.68, 0.14], [0.8, 0.22]]:
				line.call(k, [k[0] + 0.07, k[1] - 0.06], 0.02, Color("#b5b9bc"))
		"leather_cap", "iron_helmet":
			var cap_color := LEATHER if id == "leather_cap" else Color("#7d8286")
			poly.call([[0.18, 0.66], [0.22, 0.42], [0.36, 0.24], [0.64, 0.24], [0.78, 0.42], [0.82, 0.66]], cap_color)
			poly.call([[0.14, 0.66], [0.86, 0.66], [0.82, 0.74], [0.18, 0.74]], cap_color.darkened(0.25))
			if id == "iron_helmet":
				line.call([0.5, 0.26], [0.5, 0.64], 0.04, cap_color.lightened(0.2))
		"leather_vest", "iron_vest":
			var vest := LEATHER if id == "leather_vest" else Color("#6c7175")
			poly.call([[0.26, 0.2], [0.42, 0.2], [0.5, 0.34], [0.58, 0.2], [0.74, 0.2], [0.84, 0.36], [0.78, 0.86], [0.22, 0.86], [0.16, 0.36]], vest)
			if id == "iron_vest":
				for y in [0.46, 0.62, 0.78]:
					line.call([0.24, y], [0.76, y], 0.02, vest.darkened(0.35))
			else:
				line.call([0.5, 0.36], [0.5, 0.84], 0.02, vest.darkened(0.35))
		"scrap":
			poly.call([[0.14, 0.62], [0.32, 0.3], [0.58, 0.38], [0.5, 0.62]], Color("#6e6a64"))
			poly.call([[0.46, 0.7], [0.62, 0.36], [0.86, 0.48], [0.76, 0.82]], Color("#7a4a30"))
			line.call([0.22, 0.56], [0.4, 0.4], 0.02, Color("#9a958d"))
		"mech_parts":
			dot.call(0.42, 0.52, 0.22, Color("#6f7377"))
			dot.call(0.42, 0.52, 0.08, Color("#2a2c2e"))
			for k in 8:
				var a := TAU * k / 8.0
				dot.call(0.42 + cos(a) * 0.25, 0.52 + sin(a) * 0.25, 0.045, Color("#6f7377"))
			line.call([0.6, 0.8], [0.86, 0.3], 0.06, Color("#8c9094"))
		"rubber":
			ci.draw_arc(p.call(0.5, 0.5), s * 0.3, 0, TAU, 28, OUTLINE, s * 0.2 + 2.0, true)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.3, 0, TAU, 28, Color("#26272a"), s * 0.18, true)
			dot.call(0.5, 0.5, 0.09, Color("#6f7377"))
		"glass":
			poly.call([[0.22, 0.2], [0.78, 0.2], [0.7, 0.84], [0.3, 0.84]], Color(0.55, 0.68, 0.64, 0.6))
			line.call([0.34, 0.3], [0.42, 0.66], 0.025, Color(1, 1, 1, 0.5))
		"cloth":
			poly.call([[0.14, 0.34], [0.86, 0.26], [0.8, 0.74], [0.2, 0.8]], Color("#6d6552"))
			line.call([0.2, 0.5], [0.82, 0.44], 0.02, Color("#4e483a"))
			line.call([0.22, 0.64], [0.8, 0.6], 0.02, Color("#4e483a"))
		"copper_wire":
			for k in 3:
				ci.draw_arc(p.call(0.5, 0.5), s * (0.3 - k * 0.07), 0.3, TAU - 0.3, 24, OUTLINE, s * 0.05 + 2.0, true)
				ci.draw_arc(p.call(0.5, 0.5), s * (0.3 - k * 0.07), 0.3, TAU - 0.3, 24, Color("#b8733a"), s * 0.04, true)
		"gasoline":
			poly.call([[0.24, 0.3], [0.66, 0.3], [0.78, 0.42], [0.78, 0.86], [0.24, 0.86]], Color("#7a2a22"))
			line.call([0.66, 0.3], [0.8, 0.16], 0.06, Color("#3a3a3a"))
			line.call([0.34, 0.24], [0.56, 0.24], 0.06, Color("#3a3a3a"))
		"manual_page":
			poly.call([[0.24, 0.14], [0.7, 0.14], [0.8, 0.26], [0.78, 0.86], [0.22, 0.86]], Color("#c9bf9f"))
			for y in [0.34, 0.46, 0.58, 0.7]:
				line.call([0.32, y], [0.68, y], 0.015, Color("#6b6250"))
		"gunpowder":
			poly.call([[0.2, 0.8], [0.32, 0.56], [0.5, 0.48], [0.7, 0.56], [0.82, 0.8]], Color("#2f2d2b"))
			dot.call(0.5, 0.3, 0.12, Color("#8a8070"))
		"pipe":
			line.call([0.16, 0.76], [0.84, 0.24], 0.16, Color("#6f7377"))
			dot.call(0.84, 0.24, 0.07, Color("#2a2c2e"))
		"crowbar":
			line.call([0.22, 0.86], [0.7, 0.2], 0.07, Color("#3f4a5e"))
			line.call([0.7, 0.2], [0.84, 0.26], 0.07, Color("#3f4a5e"))
			line.call([0.22, 0.86], [0.14, 0.8], 0.07, Color("#3f4a5e"))
		"repair_kit":
			poly.call([[0.14, 0.4], [0.86, 0.4], [0.86, 0.82], [0.14, 0.82]], Color("#7a2a22"))
			line.call([0.38, 0.4], [0.38, 0.28], 0.05, Color("#3a3a3a"))
			line.call([0.62, 0.4], [0.62, 0.28], 0.05, Color("#3a3a3a"))
			line.call([0.38, 0.28], [0.62, 0.28], 0.05, Color("#3a3a3a"))
		"scrap_vest":
			poly.call([[0.26, 0.2], [0.42, 0.2], [0.5, 0.34], [0.58, 0.2], [0.74, 0.2], [0.84, 0.36], [0.78, 0.86], [0.22, 0.86], [0.16, 0.36]], Color("#5d5a54"))
			poly.call([[0.3, 0.46], [0.5, 0.42], [0.48, 0.62], [0.28, 0.64]], Color("#7a4a30"))
			poly.call([[0.54, 0.56], [0.74, 0.52], [0.72, 0.74], [0.52, 0.76]], Color("#6e6a64"))
		"canned_food":
			poly.call([[0.26, 0.24], [0.74, 0.24], [0.74, 0.82], [0.26, 0.82]], Color("#8c9094"))
			poly.call([[0.26, 0.38], [0.74, 0.38], [0.74, 0.66], [0.26, 0.66]], Color("#8a5a2a"))
		"water_bottle":
			poly.call([[0.36, 0.3], [0.64, 0.3], [0.68, 0.86], [0.32, 0.86]], Color(0.45, 0.62, 0.72, 0.8))
			poly.call([[0.42, 0.14], [0.58, 0.14], [0.6, 0.3], [0.4, 0.3]], Color("#2e5f86"))
		"w_pistol", "w_smg", "w_shotgun", "w_rifle":
			var length := {"w_pistol": 0.5, "w_smg": 0.62, "w_shotgun": 0.78, "w_rifle": 0.8}[id] as float
			var x0 := 0.5 - length * 0.5
			poly.call([[x0, 0.36], [x0 + length, 0.36], [x0 + length, 0.48], [x0, 0.48]], Color("#2d2f31"))
			poly.call([[x0 + 0.04, 0.48], [x0 + 0.16, 0.48], [x0 + 0.12, 0.74], [x0, 0.74]], Color("#3e3226") if id != "w_pistol" else Color("#2d2f31"))
			if id in ["w_smg", "w_rifle"]:
				poly.call([[x0 + length * 0.45, 0.48], [x0 + length * 0.55, 0.48], [x0 + length * 0.55, 0.68], [x0 + length * 0.45, 0.68]], Color("#2d2f31"))
		"a_9mm", "a_12g", "a_556":
			var shell_color := Color("#8a2a22") if id == "a_12g" else Color("#b8923a")
			for k in 3:
				var x := 0.3 + k * 0.2
				poly.call([[x - 0.07, 0.4], [x + 0.07, 0.4], [x + 0.07, 0.82], [x - 0.07, 0.82]], shell_color)
				poly.call([[x - 0.07, 0.4], [x, 0.24], [x + 0.07, 0.4]], Color("#9a7a52") if id != "a_12g" else Color("#c9b27a"))
		"zombie_gland":
			poly.call([[0.2, 0.56], [0.3, 0.32], [0.56, 0.24], [0.78, 0.38], [0.8, 0.64], [0.56, 0.8], [0.3, 0.76]], Color("#5a6a3a"))
			dot.call(0.46, 0.5, 0.08, Color("#7c8a3e"))
			dot.call(0.62, 0.6, 0.05, Color("#3c4a28"))
		"zombie_serum":
			poly.call([[0.4, 0.26], [0.6, 0.26], [0.62, 0.86], [0.38, 0.86]], Color(0.55, 0.68, 0.4, 0.85))
			poly.call([[0.4, 0.14], [0.6, 0.14], [0.6, 0.26], [0.4, 0.26]], Color("#c44a4a"))
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
