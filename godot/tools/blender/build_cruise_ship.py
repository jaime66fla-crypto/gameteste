# Navio de cruzeiro "Aurora do Sul" para a intro da Sobrevivência.
# Gera o modelo todo por script e exporta em duas metades (Proa e Popa),
# cortadas em BREAK_X, para o navio partir ao meio enquanto afunda.
#
#   "C:\Program Files\Blender Foundation\Blender 5.3\blender.exe" -b --factory-startup \
#       --python godot/tools/blender/build_cruise_ship.py -- godot/assets/survival/intro/cruise_ship.glb
#
# Eixos (Blender): X = comprimento (proa em +X), Y = boca, Z = altura. Linha d'água em Z = 0.
# Materiais com nome fixo (o Godot procura por eles):
#   Janelas_D0..Janelas_D5, Vigias  -> emissivos (apagam convés por convés)
import bpy, bmesh, math, random, sys
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "//cruise_ship.glb"
BREAK_X = -6.0
random.seed(3120)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ------------------------------------------------------------------ materiais
def principled(name, color, rough=0.6, metal=0.0, emit=None, emit_tex=None, strength=3.0):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	nodes = m.node_tree.nodes
	bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Base Color"].default_value = (*color, 1.0)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	if emit_tex is not None:
		tex = nodes.new("ShaderNodeTexImage")
		tex.image = emit_tex
		m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
		m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
		bsdf.inputs["Emission Strength"].default_value = strength
	elif emit is not None:
		bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
		bsdf.inputs["Emission Strength"].default_value = strength
	return m

def srgb(hexstr):
	h = hexstr.lstrip("#")
	c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
	return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)

def window_image(name, count, lit_ratio, w_px=32, h_px=32, frame=0.22, porthole=False):
	"""Faixa com `count` janelas; algumas cabines com a luz apagada."""
	img = bpy.data.images.new(name, count * w_px, h_px, alpha=False)
	px = [0.0] * (count * w_px * h_px * 4)
	glass = (0.012, 0.016, 0.02)
	for i in range(count):
		lit = random.random() < lit_ratio
		warm = random.choice([(1.0, 0.72, 0.36), (1.0, 0.8, 0.5), (0.95, 0.66, 0.3), (0.8, 0.82, 0.85)])
		col = warm if lit else (0.03, 0.035, 0.04)
		for y in range(h_px):
			for x in range(w_px):
				u = x / w_px; v = y / h_px
				if porthole:
					inside = (u - 0.5) ** 2 + (v - 0.5) ** 2 < 0.09
				else:
					inside = frame * 0.5 < u < 1 - frame * 0.5 and 0.2 < v < 0.85
				c = col if inside else glass
				k = ((y * count * w_px) + i * w_px + x) * 4
				px[k:k + 4] = [c[0], c[1], c[2], 1.0]
	img.pixels = px
	img.pack()
	return img

HULL = principled("Casco", srgb("#1b242b"), 0.55, 0.2)
BOOT = principled("CascoFundo", srgb("#4a211c"), 0.7)
STRIPE = principled("FaixaCasco", srgb("#7d7f7a"), 0.5)
WHITE = principled("Superestrutura", srgb("#a3a8a4"), 0.5)
DECK = principled("Piso", srgb("#4b4136"), 0.85)
RAIL = principled("Varanda", srgb("#8c918d"), 0.4, 0.3)
FUNNEL = principled("Chamine", srgb("#6e2a22"), 0.6)
SOOT = principled("Fuligem", srgb("#111315"), 0.9)
BOAT = principled("Bote", srgb("#9a5428"), 0.6)
POOL = principled("Piscina", srgb("#1b4a55"), 0.15)
INNER = principled("Interior", srgb("#0b0d0f"), 1.0)
NAV = principled("Farol", srgb("#ffffff"), 0.3, emit=srgb("#ffe2b0"), strength=8.0)
WINDOWS = [principled("Janelas_D%d" % d, (1, 1, 1), 0.2, emit_tex=window_image("jan_d%d" % d, 16, 0.78 - d * 0.04), strength=3.0) for d in range(6)]
PORTS = principled("Vigias", (1, 1, 1), 0.2, emit_tex=window_image("vigias", 16, 0.55, porthole=True), strength=2.5)

def obj_from_bm(name, bm, mats):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for m in mats:
		me.materials.append(m)
	ob = bpy.data.objects.new(name, me)
	scene.collection.objects.link(ob)
	return ob

# ------------------------------------------------------------------- casco
STERN, BOW = -70.0, 74.0
def half_width(x):
	if x <= 38:
		return 11.0 - max(0.0, (-55 - x) / 15.0) ** 2 * 1.2
	k = (x - 38) / (BOW - 38)
	return max(0.15, 11.0 * math.sqrt(max(0.0, 1 - k ** 1.7)))

def keel(x):
	return -7.0 + max(0.0, (x - 46) / (BOW - 46)) ** 2 * 6.0 + max(0.0, (-60 - x) / 10) * 2.0

def top(x):
	return 6.0 + max(0.0, (x - 20) / (BOW - 20)) ** 2 * 3.2

def build_hull():
	bm = bmesh.new()
	xs = [STERN + i * 2.0 for i in range(int((38 - STERN) / 2.0) + 1)] + [38 + (BOW - 38) * (i / 16) ** 0.8 for i in range(1, 17)]
	rings = []
	for x in xs:
		w = half_width(x); kz = keel(x); tz = top(x)
		flare = 1.0 if x < 40 else 0.82 + 0.18 * (1 - (x - 40) / (BOW - 40))
		prof = [(0.0, kz), (0.78 * w * flare, kz), (0.97 * w * flare, kz + 2.2), (w * flare, kz + 4.5), (w, -0.5), (w, tz)]
		ring = [bm.verts.new((x, y, z)) for y, z in prof] + [bm.verts.new((x, -y, z)) for y, z in reversed(prof[1:])]
		rings.append(ring)
	for a, b in zip(rings, rings[1:]):
		n = len(a)
		for i in range(n - 1):
			bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
		bm.faces.new((a[-1], a[0], b[0], b[-1])) # fundo (o convés é o par 5–6 do anel)
	# espelho de popa e ponta da proa
	bm.faces.new(list(reversed(rings[0])))
	bm.faces.new(rings[-1])
	bm.normal_update()
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	for f in bm.faces:
		c = f.calc_center_median()
		if abs(f.normal.z) > 0.95 and c.z > 3:
			f.material_index = 3
		elif c.z < -0.6:
			f.material_index = 1
		else:
			f.material_index = 0
	ob = obj_from_bm("Casco", bm, [HULL, BOOT, STRIPE, DECK])
	return ob

def side_strip(name, xs_from, xs_to, z0, z1, offset, mat, per_window=2.4, count=16):
	"""Faixa nos dois costados do casco, acompanhando a curva da proa."""
	bm = bmesh.new()
	uv = bm.loops.layers.uv.new()
	steps = max(2, int((xs_to - xs_from) / 2.0))
	for side in (1, -1):
		prev = None; dist = 0.0
		for i in range(steps + 1):
			x = xs_from + (xs_to - xs_from) * i / steps
			y = (half_width(x) + offset) * side
			a = bm.verts.new((x, y, z0)); b = bm.verts.new((x, y, z1))
			if prev is not None:
				pa, pb, px_, py_ = prev
				seg = math.hypot(x - px_, y - py_)
				f = bm.faces.new((pa, a, b, pb) if side > 0 else (pa, pb, b, a))
				u0 = dist / (per_window * count); u1 = (dist + seg) / (per_window * count)
				for loop in f.loops:
					co = loop.vert.co
					loop[uv].uv = (u1 if co.x == x else u0, 1.0 if co.z == z1 else 0.0)
				dist += seg
			prev = (a, b, x, y)
	return obj_from_bm(name, bm, [mat])

# ---------------------------------------------------------- superestrutura
DECK_H = 3.0
DECKS = [  # (popa, frente, meia boca)
	(-60, 50, 10.6), (-58, 46, 10.4), (-55, 41, 10.0), (-50, 35, 9.4), (-44, 28, 8.6), (-36, 20, 7.6),
]

def outline(x0, x1, hw, seg=10):
	"""Planta do convés: popa reta, frente arredondada."""
	r = min(hw, (x1 - x0) * 0.3)
	pts = [(x0, -hw), (x1 - r, -hw)]
	for i in range(1, seg):
		a = -math.pi / 2 + math.pi * i / seg
		pts.append((x1 - r + math.cos(a) * r, math.sin(a) * hw))
	pts += [(x1 - r, hw), (x0, hw)]
	return pts

def prism(name, pts, z0, z1, mats, side_mat=0, top_mat=0, uv_window=None):
	bm = bmesh.new()
	uv = bm.loops.layers.uv.new()
	lo = [bm.verts.new((x, y, z0)) for x, y in pts]
	hi = [bm.verts.new((x, y, z1)) for x, y in pts]
	n = len(pts)
	dist = 0.0
	for i in range(n):
		j = (i + 1) % n
		f = bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
		f.material_index = side_mat
		seg = (Vector(pts[j]) - Vector(pts[i])).length
		if uv_window:
			u0 = dist / uv_window; u1 = (dist + seg) / uv_window
			for loop, uvv in zip(f.loops, [(u0, 0), (u1, 0), (u1, 1), (u0, 1)]):
				loop[uv].uv = uvv
		dist += seg
	t = bm.faces.new(list(reversed(lo))); t.material_index = top_mat
	t = bm.faces.new(hi); t.material_index = top_mat
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return obj_from_bm(name, bm, mats)

def build_superstructure():
	parts = []
	base = top(0)
	for d, (x0, x1, hw) in enumerate(DECKS):
		z = base + d * DECK_H
		pts = outline(x0, x1, hw)
		parts.append(prism("Deck%d" % d, pts, z, z + DECK_H, [WHITE, DECK], 0, 1))
		# janelas: faixa um pouco para fora, no meio da altura do convés
		inset = [(x + (0.06 if x > x1 - hw else 0), y * (1 + 0.06 / hw)) for x, y in pts]
		parts.append(prism("Jan%d" % d, inset, z + 0.9, z + 2.3, [WINDOWS[d]], 0, 0, uv_window=2.4 * 16))
		# varandas nos costados (decks 0–3)
		if d <= 3:
			for side in (1, -1):
				slab = [(x0 + 3, side * hw), (x1 - hw * 1.1, side * hw), (x1 - hw * 1.1, side * (hw + 0.9)), (x0 + 3, side * (hw + 0.9))]
				parts.append(prism("Varanda%d" % d, slab, z + 0.05, z + 0.25, [RAIL]))
				rail = [(x0 + 3, side * (hw + 0.85)), (x1 - hw * 1.1, side * (hw + 0.85)), (x1 - hw * 1.1, side * (hw + 0.9)), (x0 + 3, side * (hw + 0.9))]
				parts.append(prism("Grade%d" % d, rail, z + 0.25, z + 1.2, [RAIL]))
	top_z = base + len(DECKS) * DECK_H
	# ponte de comando com asas
	parts.append(prism("Ponte", [(15, -12.2), (24, -12.2), (24, 12.2), (15, 12.2)], top_z - DECK_H, top_z - 0.6, [WHITE]))
	parts.append(prism("PonteJanelas", [(23.9, -12.25), (24.15, -12.25), (24.15, 12.25), (23.9, 12.25)], top_z - 2.4, top_z - 1.3, [WINDOWS[5]], uv_window=2.4 * 16))
	# piscina no último convés (popa)
	parts.append(prism("Piscina", [(-30, -4), (-18, -4), (-18, 4), (-30, 4)], top_z - 0.02, top_z + 0.04, [POOL]))
	# mastro com radar
	bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.25, depth=8, location=(16, 0, top_z + 4))
	mast = bpy.context.object; mast.name = "Mastro"; mast.data.materials.append(RAIL); parts.append(mast)
	bpy.ops.mesh.primitive_cube_add(size=1, location=(16, 0, top_z + 6.5), scale=(0.4, 4, 0.25))
	radar = bpy.context.object; radar.name = "Radar"; radar.data.materials.append(RAIL); parts.append(radar)
	bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.35, location=(16, 0, top_z + 8.2))
	lamp = bpy.context.object; lamp.name = "Farol"; lamp.data.materials.append(NAV); parts.append(lamp)
	# chaminé oval inclinada, com topo de fuligem
	bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=1, depth=10, location=(-30, 0, top_z + 5))
	f = bpy.context.object; f.name = "Chamine"; f.scale = (4.2, 2.6, 1)
	bpy.ops.object.transform_apply(scale=True)
	bm = bmesh.new(); bm.from_mesh(f.data)
	for v in bm.verts:
		k = (v.co.z + 5) / 10
		v.co.x -= k * 2.2
		v.co.x *= 1 - k * 0.15
	for face in bm.faces:
		face.material_index = 1 if face.calc_center_median().z > 3.6 else 0
	bm.to_mesh(f.data); bm.free()
	f.data.materials.append(FUNNEL); f.data.materials.append(SOOT)
	parts.append(f)
	# botes salva-vidas pendurados sob o convés 1
	for i in range(8):
		for side in (1, -1):
			x = -46 + i * 10.5
			bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=6, radius=1, location=(x, side * 11.6, base + 2.6))
			b = bpy.context.object; b.name = "Bote"; b.scale = (3.6, 1.25, 0.95)
			b.data.materials.append(BOAT); parts.append(b)
	return parts

# ------------------------------------------------------------- montagem
hull = build_hull()
strips = [
	side_strip("Vigias1", STERN + 4, 58, 1.2, 2.1, 0.04, PORTS),
	side_strip("Vigias2", STERN + 4, 50, 3.4, 4.3, 0.04, PORTS),
	side_strip("Faixa", STERN + 0.5, BOW - 3, -0.75, -0.35, 0.05, STRIPE),
]
parts = [hull] + strips + build_superstructure()
for p in parts:
	p.select_set(False)
bpy.context.view_layer.update()
for p in parts:
	bpy.context.view_layer.objects.active = p
	p.select_set(True)
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	p.select_set(False)

def join(objs, name):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	ob = bpy.context.object
	ob.name = name
	ob.data.name = name
	return ob

ship = join(parts, "Navio")
if INNER.name not in ship.data.materials:
	ship.data.materials.append(INNER)
inner_index = list(ship.data.materials).index(INNER)

def half(src, name, keep_bow):
	ob = src.copy(); ob.data = src.data.copy(); ob.name = name
	scene.collection.objects.link(ob)
	bm = bmesh.new(); bm.from_mesh(ob.data)
	geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
	res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(BREAK_X, 0, 0), plane_no=(1, 0, 0), clear_inner=keep_bow, clear_outer=not keep_bow)
	cut = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
	filled = bmesh.ops.holes_fill(bm, edges=cut, sides=0)
	for f in filled["faces"]:
		f.material_index = inner_index
	# rasgo irregular na borda do corte
	for v in bm.verts:
		if abs(v.co.x - BREAK_X) < 0.01:
			v.co.x += random.uniform(-0.9, 0.9) * (1 if keep_bow else -1) * 0.5
	# pivô no ponto de quebra, na linha d'água
	for v in bm.verts:
		v.co.x -= BREAK_X
	bm.to_mesh(ob.data); bm.free()
	ob.location = (BREAK_X, 0, 0)
	return ob

bow = half(ship, "Proa", True)
stern = half(ship, "Popa", False)
bpy.data.objects.remove(ship)
for ob in (bow, stern):
	for poly in ob.data.polygons:
		poly.use_smooth = False
print("faces: proa %d, popa %d" % (len(bow.data.polygons), len(stern.data.polygons)))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
print("exportado:", OUT)
