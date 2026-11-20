extends SceneTree
## Recorta o atlas de texturas urbanas (assets/textures/maps_source/urban_atlas.png,
## pasta ignorada pelo Godot) em texturas PBR de 512 px em assets/textures/maps:
## <tipo>_albedo.png, _normal.png e _rough.png, usadas por scripts/map_materials.gd
## (mapas online e Sobrevivência).
## - Superfícies que repetem (chão, parede) ganham emenda invisível: cada eixo é
##   misturado com a própria imagem deslocada meia volta perto das bordas.
## - Caixotes ficam inteiros (vão uma vez em cada face da caixa).
## - O brilho médio é ajustado por tipo: o atlas é muito escuro para o sol do jogo.
## - Relevo e rugosidade saem da luminância (escuro = fundo e mais áspero).
##   godot --headless --path godot --script res://tools/import_map_atlas.gd
##   godot --headless --path godot --import
const SRC := "res://assets/textures/maps_source/urban_atlas.png"
const OUT := "res://assets/textures/maps/"
const S := 512
## tipo: [x0, y0, x1, y1 no atlas, repete?, brilho médio alvo, força do relevo,
## rugosidade base, saturação, contraste (opcional, 1 = original)]
const TILES := {
	"asphalt": [196, 8, 366, 340, true, 0.20, 4.0, 0.92, 1.0],
	"pavers": [455, 6, 820, 340, true, 0.33, 5.0, 0.88, 1.0],
	"concrete": [839, 6, 1068, 340, true, 0.36, 4.0, 0.90, 1.0],
	"brick": [1086, 6, 1386, 340, true, 0.28, 6.0, 0.90, 1.0],
	"roof": [1404, 6, 1666, 236, true, 0.32, 6.0, 0.70, 1.0],
	"dirt": [6, 358, 296, 612, true, 0.27, 5.0, 0.95, 1.0],
	"gravel": [314, 358, 578, 612, true, 0.25, 7.0, 0.95, 1.0],
	"grass": [597, 358, 847, 612, true, 0.20, 3.0, 0.95, 1.0, 0.7],
	"leaves": [866, 358, 1126, 612, true, 0.25, 5.0, 0.95, 1.0],
	"hazard": [292, 636, 504, 896, false, 0.32, 3.0, 0.85, 1.0],
	"crate_metal": [741, 630, 941, 936, false, 0.30, 5.0, 0.65, 1.0],
	"crate_wood": [1184, 630, 1420, 936, false, 0.33, 5.0, 0.85, 1.0],
	# Reboco para pintar: o concreto clareado e sem cor (a tinta vem do material).
	"plaster": [839, 6, 1068, 340, true, 0.78, 2.0, 0.88, 0.0, 0.18],
}

func _initialize() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if atlas == null or atlas.is_empty():
		push_error("Atlas não encontrado: " + SRC)
		quit(1)
		return
	atlas.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for kind in TILES:
		_build(atlas, kind, TILES[kind])
		print("ok ", kind)
	quit(0)

func _build(atlas: Image, kind: String, spec: Array) -> void:
	var rect := Rect2i(spec[0], spec[1], spec[2] - spec[0], spec[3] - spec[1])
	var tiles: bool = spec[4]
	if tiles:
		# Quadrado central: a textura cobre a mesma medida nos dois eixos.
		var side := mini(rect.size.x, rect.size.y)
		rect = Rect2i(rect.position + (rect.size - Vector2i(side, side)) / 2, Vector2i(side, side))
	var img := atlas.get_region(rect)
	img.resize(S, S, Image.INTERPOLATE_LANCZOS)
	if tiles:
		img = _seamless(img, true)
		img = _seamless(img, false)
	_levels(img, spec[5], spec[8], float(spec[9]) if spec.size() > 9 else 1.0)
	var heights := PackedFloat32Array()
	heights.resize(S * S)
	var rough := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var lum := img.get_pixel(x, y).get_luminance()
			heights[y * S + x] = lum
	heights = _blur(heights, tiles)
	var mean := 0.0
	for value in heights:
		mean += value
	mean /= heights.size()
	for y in S:
		for x in S:
			var r := clampf(float(spec[7]) - (heights[y * S + x] - mean) * 0.6, 0.3, 1.0)
			rough.set_pixel(x, y, Color(r, r, r))
	var normal := Image.create(S, S, false, Image.FORMAT_RGB8)
	var k: float = spec[6] * 4.0
	for y in S:
		for x in S:
			var l := heights[y * S + _wrap(x - 1, tiles)]
			var r := heights[y * S + _wrap(x + 1, tiles)]
			var up := heights[_wrap(y - 1, tiles) * S + x]
			var dn := heights[_wrap(y + 1, tiles) * S + x]
			var n := Vector3((l - r) * k, (dn - up) * k, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.save_png(OUT + kind + "_albedo.png")
	normal.save_png(OUT + kind + "_normal.png")
	rough.save_png(OUT + kind + "_rough.png")

static func _wrap(i: int, tiles: bool) -> int:
	return posmod(i, S) if tiles else clampi(i, 0, S - 1)

## Emenda invisível num eixo: perto das bordas entra a imagem deslocada meia
## volta (cuja costura fica no meio, onde ela não aparece).
static func _seamless(img: Image, horizontal: bool) -> Image:
	var out := Image.create(S, S, false, Image.FORMAT_RGB8)
	var half := S / 2
	for y in S:
		for x in S:
			var t := float(x if horizontal else y) / (S - 1)
			var edge := minf(t, 1.0 - t) # 0 na borda, 0,5 no meio
			var w := 1.0 - smoothstep(0.0, 0.32, edge)
			var a := img.get_pixel(x, y)
			var b := img.get_pixel((x + half) % S, y) if horizontal else img.get_pixel(x, (y + half) % S)
			out.set_pixel(x, y, a.lerp(b, w))
	return out

## Brilho médio no alvo (ganho em sRGB), saturação e contraste ajustados.
static func _levels(img: Image, target: float, saturation: float, contrast: float) -> void:
	var total := 0.0
	for y in S:
		for x in S:
			total += img.get_pixel(x, y).get_luminance()
	var mean := maxf(total / (S * S), 0.01)
	var gain := target / mean
	var flat := Color(mean, mean, mean)
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y)
			var lum := c.get_luminance()
			c = Color(lum, lum, lum).lerp(c, saturation)
			c = flat.lerp(c, contrast)
			# Clareia comprimindo o topo, para o claro não estourar em branco.
			c = Color(_lift(c.r, gain), _lift(c.g, gain), _lift(c.b, gain))
			img.set_pixel(x, y, c)

static func _lift(value: float, gain: float) -> float:
	var v := value * gain
	return v / (1.0 + maxf(v - 0.8, 0.0)) if v > 0.8 else v

static func _blur(h: PackedFloat32Array, tiles: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(h.size())
	for y in S:
		for x in S:
			var sum := 0.0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					sum += h[_wrap(y + dy, tiles) * S + _wrap(x + dx, tiles)]
			out[y * S + x] = sum / 9.0
	return out
