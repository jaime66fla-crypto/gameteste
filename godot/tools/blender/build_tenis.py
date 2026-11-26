"""Tênis do personagem 01, modelado no Blender (pé direito).

    blender --background --factory-startup --python godot/tools/blender/build_tenis.py -- [<png_previa>]

Saída: godot/assets/personagens/01/roupas/tenis.glb. O Godot calça um em cada
pé do 01 (tools/characters/build_01_tenis.gd: ajusta ao tamanho do pé, espelha
para o esquerdo e copia os pesos de osso do pé).

Peças: sola (entressola com faixa, borracha de baixo, bico levantado), cabedal
suavizado com a boca aberta, biqueira, contraforte do calcanhar, uma faixa curva em
cada lado, cano acolchoado, língua, ilhoses e cadarço cruzado com laço.

Convenção: +Y = frente (ponta), +X = lado de fora do pé direito, Z = cima, sola
no chão (z = 0). Cada peça tem uma cor da paleta: o UV de cada material cai no
centro de uma célula 4 x 4 da textura (tools/characters/paint_tenis.py), então
cada modelo da loja é só outra paleta.
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = ARGS[0] if ARGS else ""
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "personagens", "01", "roupas", "tenis.glb")

# Ordem = célula da paleta (linha a linha, 4 por linha).
PARTS = ["cabedal", "biqueira", "calcanhar", "faixa", "entressola", "faixa_sola",
         "borracha", "cadarco", "ilhos", "lingua", "forro", "cano"]

L = 0.27            # comprimento (m)
OPEN_T = 0.33       # boca aberta do calcanhar até aqui
RING = 14           # pontos em volta do cabedal
STATIONS = 20       # seções do calcanhar à ponta

def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def lerp(a, b, t):
    return a + (b - a) * t

def table(points, t):
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1:
            return lerp(v0, v1, smooth(t0, t1, t))
    return points[-1][1]

# ------------------------------------------------------------- medidas ---

def round_ends(t):
    heel = math.sqrt(max(0.0, 1 - ((0.13 - t) / 0.13) ** 2)) if t < 0.13 else 1.0
    toe = math.sqrt(max(0.0, 1 - ((t - 0.76) / 0.24) ** 2)) if t > 0.76 else 1.0
    return heel * toe

def half_width(t):
    """Meia largura do cabedal (calcanhar estreito, antepé largo)."""
    return (0.033 + 0.012 * smooth(0.12, 0.66, t)) * round_ends(t)

def center_x(t):
    return -0.005 * smooth(0.45, 1.0, t)  # antepé puxa para o lado de dentro

def lift(t):
    return 0.016 * smooth(0.8, 1.0, t) ** 1.6 + 0.004 * smooth(0.06, 0.0, t)

def sole_top(t):
    return lift(t) + lerp(0.03, 0.022, smooth(0.2, 0.75, t))

def upper_height(t):
    """Altura do cabedal acima da sola."""
    return table([(0.0, 0.064), (0.25, 0.068), (0.42, 0.064), (0.64, 0.047), (0.86, 0.029), (1.0, 0.012)], t)

def upper_point(t, u, out=0.0):
    """Superfície do cabedal: u = 0 rente à sola por dentro, 0,5 no topo, 1 por fora."""
    th = math.pi * (1 - u)
    c, s = math.cos(th), math.sin(th)
    p = 0.7
    w = half_width(t) + out
    h = upper_height(t) + out
    x = center_x(t) + w * math.copysign(abs(c) ** p, c)
    z = sole_top(t) - 0.004 + h * abs(s) ** p
    return Vector((x, t * L, z))

def upper_normal(t, u):
    e = 1e-3
    a = upper_point(min(1, t + e), u) - upper_point(max(0, t - e), u)
    b = upper_point(t, min(1, u + e)) - upper_point(t, max(0, u - e))
    n = b.cross(a)
    return n.normalized() if n.length > 1e-9 else Vector((0, 0, 1))

def surf(t, u, out):
    return upper_point(t, u) + upper_normal(t, u) * out

# ------------------------------------------------------------- malhas ---

class Builder:
    def __init__(self):
        self.verts, self.faces, self.mats = [], [], []

    def v(self, p):
        self.verts.append(tuple(p))
        return len(self.verts) - 1

    def f(self, idx, mat):
        self.faces.append(idx)
        self.mats.append(PARTS.index(mat))

    def tube(self, pts, radius, mat, sides=5, closed=False):
        """Tubo ao longo de uma polilinha (cadarço, cano acolchoado)."""
        rings = []
        n = len(pts)
        for i, p in enumerate(pts):
            a = pts[(i - 1) % n] if (closed or i > 0) else p
            b = pts[(i + 1) % n] if (closed or i < n - 1) else p
            d = (b - a).normalized()
            up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            x = d.cross(up).normalized()
            y = x.cross(d).normalized()
            rings.append([self.v(p + (x * math.cos(k * math.tau / sides) + y * math.sin(k * math.tau / sides)) * radius)
                          for k in range(sides)])
        for i in range(n if closed else n - 1):
            r0, r1 = rings[i], rings[(i + 1) % n]
            for k in range(sides):
                k2 = (k + 1) % sides
                self.f([r0[k], r0[k2], r1[k2], r1[k]], mat)
        if not closed:
            for r, rev in ((rings[0], True), (rings[-1], False)):
                self.f(list(reversed(r)) if rev else r, mat)

    def ribbon(self, path, width, out, mat):
        """Faixa chata colada no cabedal (path = lista de (t, u))."""
        left, right = [], []
        for i, (t, u) in enumerate(path):
            a = path[max(0, i - 1)]
            b = path[min(len(path) - 1, i + 1)]
            d = (upper_point(*b) - upper_point(*a)).normalized()
            n = upper_normal(t, u)
            side = d.cross(n).normalized() * (width / 2)
            p = surf(t, u, out)
            left.append(self.v(p + side))
            right.append(self.v(p - side))
        for i in range(len(path) - 1):
            self.f([left[i], right[i], right[i + 1], left[i + 1]], mat)

    def obj(self, name, subdiv=0):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for m in PARTS:
            ob.data.materials.append(MATS[m])
        for poly, m in zip(me.polygons, self.mats):
            poly.material_index = m
        if subdiv:
            mod = ob.modifiers.new("Sub", 'SUBSURF')
            mod.levels = mod.render_levels = subdiv
        return ob

def build_sole():
    b = Builder()
    rings = []
    for s in range(STATIONS + 1):
        t = s / STATIONS
        w = half_width(t) + 0.007 * (0.6 + 0.4 * round_ends(t))
        w = max(w, 0.006)
        # Sola passa um pouco da ponta e do calcanhar.
        y = lerp(-0.008, L + 0.008, t)
        z0, z1 = lift(t), sole_top(t)
        ring = []
        for k in range(RING):
            th = math.tau * k / RING
            c, sn = math.cos(th), math.sin(th)
            x = center_x(t) + w * math.copysign(abs(c) ** 0.3, c)
            z = (z0 + z1) / 2 + (z1 - z0) / 2 * math.copysign(abs(sn) ** 0.3, sn)
            ring.append(b.v((x, y, z)))
        rings.append(ring)
    for s in range(STATIONS):
        for k in range(RING):
            k2 = (k + 1) % RING
            zc = math.sin(math.tau * (k + 0.5) / RING)
            mat = "borracha" if zc < -0.55 else ("faixa_sola" if abs(zc) < 0.2 else "entressola")
            b.f([rings[s][k], rings[s][k2], rings[s + 1][k2], rings[s + 1][k]], mat)
    for r, rev in ((rings[0], False), (rings[-1], True)):
        b.f(list(reversed(r)) if rev else r, "entressola")
    return b.obj("Sola", subdiv=1)

def region(t, u):
    """Cor de cada pedaço do cabedal."""
    if t > 0.8 and (u < 0.2 or u > 0.8 or t > 0.86):
        return "biqueira"
    if t < 0.2 and not (0.35 < u < 0.65):
        return "calcanhar"
    return "cabedal"

def build_upper():
    b = Builder()
    grid = [[b.v(upper_point(s / STATIONS, k / RING)) for k in range(RING + 1)] for s in range(STATIONS + 1)]
    for s in range(STATIONS):
        t = (s + 0.5) / STATIONS
        for k in range(RING):
            u = (k + 0.5) / RING
            if t < OPEN_T and 0.3 < u < 0.7:
                continue  # boca do tênis
            b.f([grid[s][k], grid[s + 1][k], grid[s + 1][k + 1], grid[s][k + 1]], region(t, u))
    return b.obj("Cabedal", subdiv=1)

def collar_path():
    pts = []
    for i in range(16, -1, -1):  # lado de dentro, de frente para trás
        pts.append(surf(OPEN_T * i / 16, 0.3, 0.0))
    for i in range(1, 17):       # lado de fora, de trás para frente
        pts.append(surf(OPEN_T * i / 16, 0.7, 0.0))
    return pts

def build_details():
    b = Builder()
    # Cano acolchoado em volta da boca.
    b.tube(collar_path(), 0.0045, "cano", sides=6)
    # Língua: sai do peito do pé e sobe na frente do tornozelo.
    rows = 8
    tongue = []
    for i in range(rows + 1):
        f = i / rows
        t = lerp(0.56, OPEN_T - 0.06, f)
        row = []
        for j in range(5):
            u = lerp(0.33, 0.67, j / 4)
            p = surf(max(t, OPEN_T), u, 0.0045)
            if t < OPEN_T:
                rise = (OPEN_T - t) / 0.06
                p = p + Vector((0, -0.006 * rise, 0.02 * rise))
            row.append(b.v(p))
        tongue.append(row)
    for i in range(rows):
        for j in range(4):
            b.f([tongue[i][j], tongue[i][j + 1], tongue[i + 1][j + 1], tongue[i + 1][j]], "lingua")
    # Faixas laterais: duas diagonais em cada lado.
    for side in (0.12, 0.88):
        # Uma faixa larga em curva, da sola até perto dos ilhoses.
        path = []
        for i in range(9):
            f = i / 8
            u = lerp(0.1 if side < 0.5 else 0.9, 0.31 if side < 0.5 else 0.69, f)
            path.append((0.62 - 0.2 * f + 0.05 * math.sin(f * math.pi), u))
        b.ribbon(path, 0.016, 0.0045, "faixa")
    # Ilhoses e cadarço cruzado.
    eyelet_rows = [lerp(0.37, 0.62, i / 5) for i in range(6)]
    holes = []
    for t in eyelet_rows:
        pair = []
        for u in (0.345, 0.655):
            p = surf(t, u, 0.0035)
            n = upper_normal(t, u)
            ring = []
            for k in range(10):
                a = math.tau * k / 10
                x = n.cross(Vector((0, 1, 0))).normalized()
                y = n.cross(x).normalized()
                ring.append(p + (x * math.cos(a) + y * math.sin(a)) * 0.0042)
            b.tube(ring, 0.0013, "ilhos", sides=4, closed=True)
            pair.append(surf(t, u, 0.005))
        holes.append(pair)
    def arch(a, c, h=0.004, n=7):
        mid = (a + c) / 2
        return [a.lerp(c, i / (n - 1)) + Vector((0, 0, h * math.sin(math.pi * i / (n - 1)))) for i in range(n)]
    for i in range(len(holes) - 1):
        b.tube(arch(holes[i][0], holes[i + 1][1]), 0.0021, "cadarco")
        b.tube(arch(holes[i][1], holes[i + 1][0], h=0.006), 0.0021, "cadarco")
    b.tube(arch(holes[-1][0], holes[-1][1], h=0.005), 0.0021, "cadarco")
    # Laço no primeiro par (perto da boca): duas alças e duas pontas.
    top = (holes[0][0] + holes[0][1]) / 2 + Vector((0, 0, 0.006))
    n0 = upper_normal(eyelet_rows[0], 0.5)
    for sgn in (-1, 1):
        loop = []
        for k in range(12):
            a = math.tau * k / 12
            loop.append(top + Vector((sgn * (0.011 + 0.009 * math.cos(a)), -0.002 + 0.006 * math.sin(a), 0.002)))
        b.tube(loop, 0.0019, "cadarco", sides=5, closed=True)
        tail = [top + Vector((sgn * 0.003, 0, 0)),
                top + Vector((sgn * 0.01, 0.012, -0.004)),
                top + Vector((sgn * 0.016, 0.024, -0.012)) + n0 * 0.002]
        b.tube(tail, 0.0019, "cadarco")
    b.tube([holes[0][0], top], 0.0021, "cadarco")
    b.tube([holes[0][1], top], 0.0021, "cadarco")
    # Forro dentro da boca (fundo escuro).
    forro = []
    for i in range(13):
        t = OPEN_T * i / 12
        forro.append([b.v(surf(t, u, -0.003)) for u in (0.3, 0.5, 0.7)])
    for i in range(12):
        for j in range(2):
            b.f([forro[i][j + 1], forro[i][j], forro[i + 1][j], forro[i + 1][j + 1]], "forro")
    return b.obj("Detalhes")

# --------------------------------------------------------------- cena ---

bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {}
for i, name in enumerate(PARTS):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    MATS[name] = m

parts = [build_sole(), build_upper(), build_details()]
for ob in parts:
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        for mod in list(ob.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
for ob in bpy.context.scene.objects:
    ob.select_set(ob in parts)
bpy.context.view_layer.objects.active = parts[1]
bpy.ops.object.join()
shoe = bpy.context.view_layer.objects.active
shoe.name = shoe.data.name = "Tenis"
for poly in shoe.data.polygons:
    poly.use_smooth = True
# UV: cada material no centro da sua célula da paleta 4 x 4.
uv = shoe.data.uv_layers.new(name="UVMap")
for poly in shoe.data.polygons:
    m = poly.material_index
    cu, cv = (m % 4 + 0.5) / 4, 1 - (m // 4 + 0.5) / 4
    for li in poly.loop_indices:
        uv.data[li].uv = (cu, cv)
# Um material só no GLB (a paleta escolhe a cor).
shoe.data.materials.clear()
final = bpy.data.materials.new("Roupa_tenis")
shoe.data.materials.append(final)
tris = sum(len(p.vertices) - 2 for p in shoe.data.polygons)
print("TENIS BLENDER: %d triângulos" % tris)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_materials='PLACEHOLDER', export_yup=True, export_apply=True)
print("TENIS BLENDER: ->", OUT)

if PREVIEW:
    # Prévia rápida colorida pelas partes (só para conferir a forma).
    cols = [(0.06, 0.065, 0.07), (0.04, 0.042, 0.045), (0.04, 0.042, 0.045), (0.5, 0.5, 0.48), (0.6, 0.58, 0.54),
            (0.3, 0.3, 0.3), (0.03, 0.03, 0.03), (0.7, 0.7, 0.68), (0.3, 0.3, 0.3), (0.05, 0.055, 0.06),
            (0.02, 0.02, 0.02), (0.05, 0.05, 0.055)]
    shoe.data.materials.clear()
    for c in cols:
        m = bpy.data.materials.new("p")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = c + (1,)
        shoe.data.materials.append(m)
    for poly in shoe.data.polygons:
        u = shoe.data.uv_layers.active.data[poly.loop_indices[0]].uv
        poly.material_index = int(u[0] * 4) + 4 * int((1 - u[1]) * 4)
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w")
    world.color = (0.35, 0.4, 0.45)
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (0.8, 0.3, 0.6)
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (0.33, 0.02, 0.2)
    direction = Vector((0, 0.13, 0.04)) - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = 40
    sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x, sc.render.resolution_y = 900, 600
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("TENIS BLENDER: prévia ->", PREVIEW)
