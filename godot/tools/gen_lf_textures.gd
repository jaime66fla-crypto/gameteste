extends SceneTree
## Texturas do Linha de Fogo (fps-tatico/tools/gen_textures.gd) para o Campo de Fogo, mais as superfícies
## que só o Campo de Fogo tem (grama, asfalto, terra, cascalho, folhas, faixa de perigo), no mesmo estilo.
## Albedo + normal repetíveis em assets/textures/lf/ (usadas por scripts/map_materials.gd).
## Uso: godot --headless --path godot --script res://tools/gen_lf_textures.gd

const S := 512
const OUT := "res://assets/textures/lf/"
var rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	rng.seed = 2026
	_floor_tiles()
	_plaster()
	_stone_blocks("stone", Color(0.74, 0.62, 0.45), 4, 8)
	_stone_blocks("stone_dark", Color(0.52, 0.45, 0.37), 3, 6)
	_concrete()
	_crate()
	_metal()
	_trim()
	_grass()
	_asphalt()
	_dirt()
	_gravel()
	_leaves()
	_hazard()
	print("texturas geradas")
	quit()


# ------------------------------------------------------------------ utilidades

func _noise(seed: int, freq: float, octaves := 4) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img := n.get_seamless_image(S, S, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	var bytes := img.get_data()
	var out := PackedFloat32Array()
	out.resize(S * S)
	for i in S * S:
		out[i] = bytes[i] / 255.0
	return out


func _save(name: String, col: PackedColorArray, height: PackedFloat32Array, strength: float) -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	var nrm := Image.create(S, S, false, Image.FORMAT_RGB8)
	for y in S:
		for x in S:
			var i := y * S + x
			img.set_pixel(x, y, col[i])
			var hl := height[y * S + (x - 1 + S) % S]
			var hr := height[y * S + (x + 1) % S]
			var hu := height[((y - 1 + S) % S) * S + x]
			var hd := height[((y + 1) % S) * S + x]
			var n := Vector3((hl - hr) * strength, (hd - hu) * strength, 1.0).normalized()
			nrm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	nrm.save_png(ProjectSettings.globalize_path(OUT + name + "_n.png"))
	print("  ", name)


func _buffers() -> Array:
	var col := PackedColorArray()
	col.resize(S * S)
	var h := PackedFloat32Array()
	h.resize(S * S)
	return [col, h]


# ------------------------------------------------------------------ texturas

## Piso: lajotas de arenito 1 m (textura = 4 m), rejunte, variação por peça, poeira.
func _floor_tiles() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var big := _noise(11, 0.004, 3)
	var grain := _noise(12, 0.08, 2)
	var chips := _noise(13, 0.025, 4)
	var tile := S / 4
	var tints := []
	for i in 16:
		tints.append(rng.randf_range(-0.07, 0.07))
	for y in S:
		for x in S:
			var i := y * S + x
			var tx := x % tile
			var ty := y % tile
			var edge := mini(mini(tx, tile - 1 - tx), mini(ty, tile - 1 - ty))
			var t: float = tints[(y / tile) * 4 + x / tile]
			var base := Color(0.76, 0.64, 0.47).lightened(t) if t > 0 else Color(0.76, 0.64, 0.47).darkened(-t)
			var v := 0.82 + big[i] * 0.25 + grain[i] * 0.12
			var c := base * v
			var hh := 0.6 + grain[i] * 0.15
			if chips[i] > 0.72:
				c = c.darkened(0.12)
				hh -= 0.2
			if edge < 3:
				c = Color(0.4, 0.34, 0.27) * (0.85 + grain[i] * 0.3)
				hh = 0.1
			elif edge < 6:
				c = c.darkened(0.08 * (6 - edge) / 3.0)
				hh -= 0.05 * (6 - edge)
			# poeira de areia por cima
			var dust := clampf((big[i] - 0.55) * 2.5, 0.0, 0.6)
			c = c.lerp(Color(0.82, 0.72, 0.55), dust)
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save("floor", col, h, 6.0)


## Reboco: manchas, sujeira e partes descascadas mostrando tijolo (textura = 4 m).
func _plaster() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var blot := _noise(21, 0.006, 4)
	var fine := _noise(22, 0.06, 3)
	var peel := _noise(23, 0.012, 5)
	var bw := 64
	var bh := 24
	for y in S:
		for x in S:
			var i := y * S + x
			var c := Color(0.86, 0.78, 0.62) * (0.84 + blot[i] * 0.2 + fine[i] * 0.08)
			var hh := 0.7 + fine[i] * 0.1
			var p := peel[i]
			if p > 0.84:
				# tijolo à mostra
				var row := y / bh
				var bx := (x + (bw / 2 if row % 2 == 1 else 0)) % bw
				var by := y % bh
				if bx < 3 or by < 3:
					c = Color(0.55, 0.5, 0.42) * (0.9 + fine[i] * 0.2)
					hh = 0.2
				else:
					var tint := float(hash(Vector2i((x + (bw / 2 if row % 2 == 1 else 0)) / bw, row)) % 100) / 100.0
					c = Color(0.62, 0.36, 0.24).lerp(Color(0.7, 0.45, 0.3), tint) * (0.85 + fine[i] * 0.25)
					hh = 0.35
			elif p > 0.815:
				c = c.darkened(0.12)
				hh = 0.55
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save("plaster", col, h, 5.0)


## Blocos de pedra assentados com argamassa.
func _stone_blocks(name: String, base: Color, cols: int, rows: int) -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var fine := _noise(31 + cols, 0.07, 3)
	var mid := _noise(32 + cols, 0.02, 4)
	var bw := S / cols
	var bh := S / rows
	for y in S:
		for x in S:
			var i := y * S + x
			var row := y / bh
			var off := bw / 2 if row % 2 == 1 else 0
			var bx := (x + off) % bw
			var by := y % bh
			var id := Vector2i(((x + off) % S) / bw, row)
			var tint := float(hash(id) % 1000) / 1000.0 - 0.5
			var edge := mini(mini(bx, bw - 1 - bx), mini(by, bh - 1 - by))
			var c := base.lightened(tint * 0.25) if tint > 0 else base.darkened(-tint * 0.3)
			c = c * (0.82 + mid[i] * 0.22 + fine[i] * 0.1)
			var hh := 0.65 + mid[i] * 0.2 + fine[i] * 0.1
			if edge < 3:
				c = base.darkened(0.45) * (0.9 + fine[i] * 0.2)
				hh = 0.05
			elif edge < 7:
				hh -= 0.06 * (7 - edge)
				c = c.darkened(0.04 * (7 - edge))
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save(name, col, h, 6.0)


## Concreto: pintas, manchas e furos de forma (textura = 2 m).
func _concrete() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var blot := _noise(41, 0.01, 4)
	var fine := _noise(42, 0.15, 2)
	for y in S:
		for x in S:
			var i := y * S + x
			var c := Color(0.6, 0.6, 0.58) * (0.82 + blot[i] * 0.22 + fine[i] * 0.1)
			var hh := 0.6 + fine[i] * 0.15
			if fine[i] > 0.8:
				c = c.darkened(0.3)
				hh -= 0.2
			if x < 3 or y < 3:
				c = c.darkened(0.35)
				hh = 0.2
			for hp in [Vector2(128, 128), Vector2(384, 128), Vector2(128, 384), Vector2(384, 384)]:
				var d := Vector2(x, y).distance_to(hp)
				if d < 7:
					c = c.darkened(0.5)
					hh = 0.2 + d * 0.05
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save("concrete", col, h, 5.0)


## Caixote de madeira: moldura + tábuas (textura = 1 m).
func _crate() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var grain_n := _noise(51, 0.004, 2)
	var fine := _noise(52, 0.12, 2)
	var frame := 48
	var plank := (S - frame * 2) / 4
	for y in S:
		for x in S:
			var i := y * S + x
			var in_frame := x < frame or x >= S - frame or y < frame or y >= S - frame
			var wood := Color(0.6, 0.42, 0.24)
			var hh := 0.7
			var g: float
			if in_frame:
				g = sin(float(x if (y < frame or y >= S - frame) else y) * 0.15 + grain_n[i] * 3.0) * 0.5 + 0.5
				wood = wood.darkened(0.12)
				var e := mini(mini(x, S - 1 - x), mini(y, S - 1 - y))
				var inner := mini(mini(absi(x - frame), absi(x - (S - frame))), mini(absi(y - frame), absi(y - (S - frame))))
				if e < 3 or inner < 3:
					hh = 0.3
					wood = wood.darkened(0.3)
				else:
					hh = 0.85
			else:
				var py := (y - frame) % plank
				g = sin(float(y) * 0.9 + grain_n[i] * 5.0 + float((y - frame) / plank) * 3.0) * 0.5 + 0.5
				if py < 4:
					hh = 0.1
					wood = Color(0.2, 0.13, 0.08)
				else:
					var tint := float(((y - frame) / plank) * 37 % 10) / 10.0 - 0.5
					wood = wood.lightened(tint * 0.12) if tint > 0 else wood.darkened(-tint * 0.15)
			var c := wood * (0.82 + g * 0.18 + fine[i] * 0.08)
			# pregos
			for np in [Vector2(24, 24), Vector2(S - 24, 24), Vector2(24, S - 24), Vector2(S - 24, S - 24)]:
				if Vector2(x, y).distance_to(np) < 6:
					c = Color(0.25, 0.25, 0.26)
					hh = 0.95
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save("crate", col, h, 5.0)


## Metal ondulado pintado com ferrugem (textura = 2 m).
func _metal() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var rust := _noise(61, 0.012, 5)
	var fine := _noise(62, 0.1, 2)
	var streak := _noise(63, 0.03, 3)
	for y in S:
		for x in S:
			var i := y * S + x
			var wave := sin(float(x) / S * TAU * 16.0)
			var hh := 0.5 + wave * 0.35
			var paint := Color(0.26, 0.38, 0.34) * (0.85 + fine[i] * 0.12 + wave * 0.06)
			var r := clampf((rust[i] - 0.62) * 4.0 + (streak[i] - 0.5) * 0.6, 0.0, 1.0)
			var c := paint.lerp(Color(0.42, 0.22, 0.1) * (0.8 + fine[i] * 0.4), r)
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh + fine[i] * 0.05
	_save("metal", col, h, 4.0)


## Friso/rodapé de pedra lisa.
func _trim() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var blot := _noise(71, 0.015, 4)
	var fine := _noise(72, 0.1, 2)
	for y in S:
		for x in S:
			var i := y * S + x
			var c := Color(0.58, 0.52, 0.44) * (0.8 + blot[i] * 0.25 + fine[i] * 0.08)
			var hh := 0.6 + fine[i] * 0.1
			if x % 256 < 3:
				c = c.darkened(0.4)
				hh = 0.2
			col[i] = Color(c.r, c.g, c.b)
			h[i] = hh
	_save("trim", col, h, 4.0)


# ------------------------------------------------------- superfícies do Campo de Fogo

## Grama: verde-oliva com tufos, manchas secas e falhas de terra (textura = 3,5 m).
func _grass() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var patch := _noise(81, 0.008, 4)
	var blades := _noise(82, 0.22, 2)
	var dry := _noise(83, 0.02, 3)
	for i in S * S:
		var c := Color(0.36, 0.44, 0.22).lerp(Color(0.5, 0.5, 0.28), clampf((dry[i] - 0.45) * 2.5, 0.0, 1.0))
		c = c * (0.72 + blades[i] * 0.4 + patch[i] * 0.15)
		var hh := 0.5 + blades[i] * 0.4
		if patch[i] < 0.22:
			c = c.lerp(Color(0.45, 0.36, 0.25), 0.7)
			hh = 0.3
		col[i] = Color(c.r, c.g, c.b)
		h[i] = hh
	_save("grass", col, h, 4.0)


## Asfalto: cinza escuro com agregado claro, remendos e rachaduras (textura = 3 m).
func _asphalt() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var blot := _noise(91, 0.008, 4)
	var grit := _noise(92, 0.35, 1)
	var crack := _noise(93, 0.03, 5)
	for i in S * S:
		var c := Color(0.27, 0.27, 0.27) * (0.82 + blot[i] * 0.25)
		var hh := 0.5 + grit[i] * 0.2
		if grit[i] > 0.78:
			c = c.lightened(0.25)
			hh += 0.1
		if absf(crack[i] - 0.5) < 0.012:
			c = c.darkened(0.45)
			hh = 0.1
		col[i] = Color(c.r, c.g, c.b)
		h[i] = hh
	_save("asphalt", col, h, 5.0)


## Terra batida: marrom com torrões e pedrinhas (textura = 3 m).
func _dirt() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var blot := _noise(101, 0.01, 4)
	var fine := _noise(102, 0.12, 2)
	var stones := _noise(103, 0.09, 1)
	for i in S * S:
		var c := Color(0.5, 0.38, 0.26) * (0.75 + blot[i] * 0.3 + fine[i] * 0.12)
		var hh := 0.4 + blot[i] * 0.3 + fine[i] * 0.1
		if stones[i] > 0.82:
			c = Color(0.62, 0.58, 0.52) * (0.85 + fine[i] * 0.3)
			hh = 0.9
		col[i] = Color(c.r, c.g, c.b)
		h[i] = hh
	_save("dirt", col, h, 5.0)


## Cascalho: pedras arredondadas cinza-areia (células), juntas escuras (textura = 1,5 m).
func _gravel() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var cell := FastNoiseLite.new()
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.seed = 111
	cell.frequency = 0.05
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var dist := cell.get_seamless_image(S, S, false, false, 0.1, true)
	dist.convert(Image.FORMAT_L8)
	cell.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var ids := cell.get_seamless_image(S, S, false, false, 0.1, true)
	ids.convert(Image.FORMAT_L8)
	var dd := dist.get_data()
	var idd := ids.get_data()
	var fine := _noise(112, 0.2, 2)
	for i in S * S:
		var d := dd[i] / 255.0
		var tint := idd[i] / 255.0
		var c := Color(0.62, 0.58, 0.5).lerp(Color(0.45, 0.43, 0.4), tint) * (0.85 + fine[i] * 0.2)
		var hh := 1.0 - d
		if d > 0.75:
			c = c.darkened(0.5)
		col[i] = Color(c.r, c.g, c.b)
		h[i] = hh
	_save("gravel", col, h, 6.0)


## Folhas no chão: marrom, ocre e verde-escuro em manchas (textura = 2 m).
func _leaves() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var a := _noise(121, 0.05, 3)
	var bb := _noise(122, 0.07, 2)
	var fine := _noise(123, 0.25, 1)
	for i in S * S:
		var c := Color(0.42, 0.3, 0.16).lerp(Color(0.6, 0.45, 0.2), clampf((a[i] - 0.4) * 2.0, 0.0, 1.0))
		c = c.lerp(Color(0.25, 0.32, 0.16), clampf((bb[i] - 0.6) * 3.0, 0.0, 1.0))
		c = c * (0.75 + fine[i] * 0.35)
		col[i] = Color(c.r, c.g, c.b)
		h[i] = 0.4 + a[i] * 0.3 + fine[i] * 0.2
	_save("leaves", col, h, 5.0)


## Faixa de perigo: listras diagonais amarelas e pretas, gastas (textura = 1 m).
func _hazard() -> void:
	var b := _buffers()
	var col: PackedColorArray = b[0]
	var h: PackedFloat32Array = b[1]
	var wear := _noise(131, 0.03, 4)
	var fine := _noise(132, 0.15, 2)
	for y in S:
		for x in S:
			var i := y * S + x
			var stripe := int(floor(float(x + y) / (S / 4.0))) % 2 == 0
			var c := Color(0.86, 0.68, 0.12) if stripe else Color(0.1, 0.1, 0.1)
			c = c * (0.82 + fine[i] * 0.2)
			if wear[i] > 0.7:
				c = c.lerp(Color(0.45, 0.45, 0.43), 0.6)
			col[i] = Color(c.r, c.g, c.b)
			h[i] = 0.6 + fine[i] * 0.1 - (0.15 if wear[i] > 0.7 else 0.0)
	_save("hazard", col, h, 3.0)