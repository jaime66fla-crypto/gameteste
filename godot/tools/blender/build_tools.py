# Modela as ferramentas / armas brancas da Sobrevivência no Blender e exporta
# um GLB por ferramenta (res://assets/tools/<id>.glb, lido por
# scripts/weapons/tool_model.gd).
#
# Uso (Blender em modo de fundo):
#   blender --background --factory-startup --python godot/tools/blender/build_tools.py -- <pasta_glb> [<png_previa>]
#
# Convenção (igual ao modelo simples do jogo): cabo ao longo de +Z do Blender
# (= +Y no Godot) com a base do cabo na origem, lâmina / gume para +Y do
# Blender (= -Z no Godot). Medidas em metros, iguais a ToolModel.LOOK.
# Texturas geradas aqui (ruído periódico com numpy), mapeadas em caixa; tons
# escuros e gastos (estilo urbano escuro do jogo).
import bpy
import bmesh
import math
import os
import sys
import numpy as np
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = ARGS[0] if ARGS else os.path.join(os.path.dirname(__file__), "out")
PREVIEW = ARGS[1] if len(ARGS) > 1 else ""
TEX = 256
UV_SCALE = 0.22  # metros cobertos por uma textura
rng = np.random.default_rng(7)

# ------------------------------------------------------------------ cena ---
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
coll = scene.collection

# --------------------------------------------------------------- texturas ---
def noise(scale, seed):
    """Ruído periódico (emenda sem costura) 0..1: ruído branco filtrado na FFT."""
    r = np.random.default_rng(seed)
    white = r.standard_normal((TEX, TEX))
    fy = np.fft.fftfreq(TEX)[:, None]
    fx = np.fft.fftfreq(TEX)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    filt = np.exp(-(f * TEX / scale) ** 2)
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * filt))
    out -= out.min()
    return out / max(out.max(), 1e-6)

def fbm(seed, scales=(4, 12, 40), weights=(0.55, 0.3, 0.15)):
    acc = np.zeros((TEX, TEX))
    for i, (s, w) in enumerate(zip(scales, weights)):
        acc += noise(s, seed + i * 31) * w
    return acc / sum(weights)

def mix(a, b, t):
    t = t[..., None]
    return np.array(a)[None, None, :] * (1 - t) + np.array(b)[None, None, :] * t

U = np.tile(np.arange(TEX) / TEX, (TEX, 1))  # varia nas colunas (u)
V = U.T

def tex_wood(light, dark, seed):
    # Veios ao longo de v (o comprimento do cabo): listras que variam em u.
    warp = fbm(seed, (3, 8), (0.7, 0.3))
    rings = 0.5 + 0.5 * np.sin(2 * math.pi * (U * 20 + warp * 0.6))
    rings = rings ** 2.2
    fine = noise(60, seed + 5)
    t = np.clip(rings * 0.75 + fine * 0.35, 0, 1)
    return mix(light, dark, t)

def tex_bark(seed):
    streak = fbm(seed, (2, 30), (0.4, 0.6))
    streak = np.abs(np.sin(2 * math.pi * (U * 14 + streak * 2.0)))
    t = np.clip(streak * 0.6 + noise(50, seed + 3) * 0.4, 0, 1)
    return mix((0.40, 0.31, 0.22), (0.17, 0.13, 0.09), t)

def tex_stone(seed, base=(0.36, 0.35, 0.33), dark=(0.17, 0.17, 0.16)):
    t = fbm(seed, (5, 16, 60), (0.5, 0.3, 0.2))
    spots = (noise(30, seed + 9) > 0.62).astype(float) * 0.25
    return mix(base, dark, np.clip(t * 0.9 + spots, 0, 1))

def tex_flint(seed):
    t = fbm(seed, (3, 9, 30), (0.5, 0.35, 0.15))
    shells = 0.5 + 0.5 * np.sin(2 * math.pi * (t * 5.0))
    return mix((0.10, 0.10, 0.11), (0.30, 0.29, 0.28), np.clip(shells * 0.55 + t * 0.3, 0, 1))

def tex_iron(seed, rust=0.35):
    t = fbm(seed, (6, 24, 80), (0.45, 0.35, 0.2))
    col = mix((0.30, 0.30, 0.31), (0.13, 0.13, 0.14), t)
    r = noise(10, seed + 4) * 0.7 + noise(40, seed + 6) * 0.3
    rust_mask = np.clip((r - (1.0 - rust)) * 5.0, 0, 1)[..., None]
    rust_col = mix((0.30, 0.15, 0.07), (0.16, 0.08, 0.04), noise(50, seed + 8))
    return col * (1 - rust_mask) + rust_col * rust_mask

def tex_rope(seed):
    twist = 0.5 + 0.5 * np.sin(2 * math.pi * ((U + V) * 22 + noise(8, seed) * 0.8))
    t = np.clip(twist * 0.7 + noise(70, seed + 2) * 0.3, 0, 1)
    return mix((0.52, 0.45, 0.31), (0.25, 0.20, 0.13), t)

def tex_leather(seed):
    t = fbm(seed, (8, 40, 100), (0.4, 0.4, 0.2))
    return mix((0.16, 0.11, 0.08), (0.06, 0.045, 0.035), t)

def tex_grip(seed):
    bands = (np.sin(2 * math.pi * (V * 18 + U * 2)) > 0.86).astype(float)
    t = np.clip(noise(60, seed) * 0.5 + bands * 0.5, 0, 1)
    return mix((0.08, 0.08, 0.085), (0.02, 0.02, 0.022), t)

def image(name, rgb):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False)
    rgba = np.ones((TEX, TEX, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb, 0, 1) ** 2.2  # cores pensadas em sRGB -> linear
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = "PNG"
    img.pack()
    return img

def material(name, rgb, metallic=0.0, roughness=0.8):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image(name + "_tex", rgb)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

MAT = {
    "bark": material("bark", tex_bark(11), 0.0, 0.92),
    "wood_light": material("wood_light", tex_wood((0.58, 0.43, 0.28), (0.32, 0.22, 0.13), 21), 0.0, 0.7),
    "wood_dark": material("wood_dark", tex_wood((0.38, 0.27, 0.18), (0.17, 0.11, 0.07), 23), 0.0, 0.65),
    "stone": material("stone", tex_stone(31, (0.52, 0.50, 0.46), (0.26, 0.25, 0.23)), 0.0, 0.92),
    "flint": material("flint", tex_flint(33) * 1.5, 0.0, 0.4),
    "iron": material("iron", tex_iron(41, 0.25) * 1.7, 0.45, 0.45),
    "iron_rusty": material("iron_rusty", tex_iron(43, 0.55) * 1.5, 0.3, 0.65),
    "rope": material("rope", tex_rope(51), 0.0, 0.95),
    "leather": material("leather", tex_leather(61), 0.0, 0.75),
    "grip": material("grip", tex_grip(71), 0.0, 0.85),
}

# ---------------------------------------------------------------- malhas ---
class Part:
    """Uma peça (malha) com um material; as peças de uma ferramenta são juntadas."""
    def __init__(self, mat):
        self.bm = bmesh.new()
        self.mat = mat

def frame(tangent):
    t = tangent.normalized()
    ref = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
    n = t.cross(ref).normalized()
    b = t.cross(n).normalized()
    return n, b

def tube(part, pts, radii, sides=12, jitter=0.0, sx=1.0, sy=1.0, cap=(True, True), closed=False, seed=0):
    """Tubo afinando pelos pontos (cabo, haste, anel de corda...)."""
    r = np.random.default_rng(seed)
    bm = part.bm
    pts = [Vector(p) for p in pts]
    rings = []
    count = len(pts)
    prev_n = None
    for i, p in enumerate(pts):
        if closed:
            tangent = pts[(i + 1) % count] - pts[i - 1]
        else:
            tangent = pts[min(i + 1, count - 1)] - pts[max(i - 1, 0)]
        n, b = frame(tangent)
        if prev_n is not None:
            # transporte paralelo: evita o tubo torcer
            n = (prev_n - tangent.normalized() * prev_n.dot(tangent.normalized())).normalized()
            b = tangent.normalized().cross(n).normalized()
        prev_n = n
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            rad = radii[i] * (1.0 + (r.uniform(-jitter, jitter) if jitter else 0.0))
            off = n * (math.cos(a) * rad * sx) + b * (math.sin(a) * rad * sy)
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    segs = count if closed else count - 1
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % count]
        for k in range(sides):
            bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
    if not closed:
        if cap[0]:
            bm.faces.new(list(reversed(rings[0])))
        if cap[1]:
            bm.faces.new(rings[-1])
    return rings

def ring(part, z, radius, thick, y=0.0, sides=10, seg=20, rx=1.0, rz=None, axis="z"):
    """Anel de corda / amarração: tubo fechado num círculo (ou elipse)."""
    pts = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        if axis == "z":  # em volta do cabo (plano XY)
            pts.append((math.cos(a) * radius * rx, y + math.sin(a) * radius, z))
        else:  # em volta da cabeça (plano XZ)
            pts.append((math.cos(a) * radius * rx, y, z + math.sin(a) * (rz if rz else radius)))
    tube(part, pts, [thick] * seg, sides=sides, closed=True)

def blob(part, center, size, jitter, seed, sharpen=None):
    """Pedra lascada: icosfera amassada com ruído; `sharpen(v)` afina o gume."""
    r = np.random.default_rng(seed)
    bm = part.bm
    res = bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    for v in res["verts"]:
        d = v.co.normalized()
        bump = 1.0 + r.uniform(-jitter, jitter) + 0.12 * math.sin(d.x * 7 + d.y * 5 + seed)
        v.co = Vector((d.x * size[0], d.y * size[1], d.z * size[2])) * bump
        if sharpen:
            sharpen(v)
        v.co += Vector(center)
    return res["verts"]

def slab(part, outline, half_thick):
    """Lâmina chapada: contorno no plano YZ, espessura (meia) por ponto; o gume afina."""
    bm = part.bm
    pos = [bm.verts.new((half_thick(y, z), y, z)) for (y, z) in outline]
    neg = [bm.verts.new((-half_thick(y, z), y, z)) for (y, z) in outline]
    n = len(outline)
    bm.faces.new(pos)
    bm.faces.new(list(reversed(neg)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((pos[j], pos[i], neg[i], neg[j]))

def box(part, center, size):
    bmesh.ops.create_cube(part.bm, size=1.0, matrix=Matrix.Translation(center) @ Matrix.Diagonal((*size, 1.0)))

def cylinder_x(part, center, radius, length, sides=10):
    """Cilindro deitado no eixo X (rebite, prego)."""
    mat = Matrix.Translation(center) @ Matrix.Rotation(math.pi / 2, 4, "Y")
    bmesh.ops.create_cone(part.bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=length, matrix=mat)

def cone_dir(part, base, direction, r0, r1, length, sides=8):
    d = Vector(direction).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    mat = Matrix.Translation(Vector(base) + d * (length / 2)) @ rot
    bmesh.ops.create_cone(part.bm, cap_ends=True, segments=sides, radius1=r0, radius2=r1, depth=length, matrix=mat)

def box_uv(bm):
    """UV em caixa (projeção pelo eixo da normal), em metros / UV_SCALE."""
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            c = loop.vert.co
            if ax == 0:
                loop[uv].uv = (c.y / UV_SCALE, c.z / UV_SCALE)
            elif ax == 1:
                loop[uv].uv = (c.x / UV_SCALE, c.z / UV_SCALE)
            else:
                loop[uv].uv = (c.x / UV_SCALE, c.y / UV_SCALE)

def finish(name, parts, offset, sharp_deg=40.0, bevel=0.0):
    """Junta as peças num objeto (um material por peça), com UV e sombreamento."""
    bm = bmesh.new()
    mats = []
    for p in parts:
        if p.mat not in mats:
            mats.append(p.mat)
        idx = mats.index(p.mat)
        bmesh.ops.recalc_face_normals(p.bm, faces=p.bm.faces)
        tmp = bpy.data.meshes.new("tmp")
        p.bm.to_mesh(tmp)
        for poly in tmp.polygons:
            poly.material_index = idx
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        p.bm.free()
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.normal_update()
    box_uv(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(MAT[m])
    mesh.shade_smooth()
    mesh.set_sharp_from_angle(angle=math.radians(sharp_deg))
    obj = bpy.data.objects.new(name, mesh)
    coll.objects.link(obj)
    obj.location = offset
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(50)
        mod.harden_normals = True
    return obj

# ------------------------------------------------------------- ferramentas ---
def branch_handle(part, length, r0, r1, seed, wobble=0.004):
    """Cabo de galho: torto, com nós e casca."""
    r = np.random.default_rng(seed)
    n = 14
    pts, radii = [], []
    for i in range(n):
        z = length * i / (n - 1)
        bend = math.sin(z * 4.0 + seed) * wobble
        pts.append((bend + r.uniform(-0.0012, 0.0012), r.uniform(-0.0012, 0.0012) + math.cos(z * 3.0) * wobble * 0.5, z))
        knot = 0.0035 if r.random() < 0.18 else 0.0
        radii.append(r0 + (r1 - r0) * i / (n - 1) + knot)
    tube(part, pts, radii, sides=10, jitter=0.07, seed=seed)

def turned_handle(part, length, seed, top_r=0.019):
    """Cabo torneado: pomo na base, cintura fina, engrossa perto da cabeça."""
    prof = [(0.0, 0.016), (0.006, 0.024), (0.022, 0.025), (0.04, 0.019), (0.25, 0.017), (0.5, 0.0175), (0.8, 0.019), (1.0, top_r)]
    pts = [(0, 0, f * length) for f, _ in prof]
    radii = [rad for _, rad in prof]
    tube(part, pts, radii, sides=14, seed=seed, sx=1.0, sy=1.25)  # oval: mais largo no sentido do gume

def stone_axe(offset):
    handle = Part("bark")
    branch_handle(handle, 0.70, 0.021, 0.017, 3)
    head = Part("stone")
    zc = 0.60
    def sharpen(v):
        if v.co.y > 0.02:  # frente: afina até o gume
            k = min(1.0, (v.co.y - 0.02) / 0.07)
            v.co.x *= 1.0 - 0.8 * k
            v.co.z *= 1.0 + 0.25 * k
    blob(head, (0, 0.055, zc), (0.032, 0.085, 0.05), 0.13, 5, sharpen)
    lash = Part("rope")
    for z in (zc - 0.055, zc - 0.045, zc + 0.045, zc + 0.055):
        ring(lash, z, 0.021, 0.0035)
    ring(lash, zc, 0.03, 0.0035, y=0.012, axis="x", rz=0.05)
    ring(lash, zc, 0.03, 0.0035, y=-0.004, axis="x", rz=0.05)
    return finish("stone_axe", [handle, head, lash], offset, sharp_deg=55)

def iron_axe(offset):
    handle = Part("wood_light")
    turned_handle(handle, 0.76, 9)
    head = Part("iron")
    outline = [(-0.035, 0.668), (0.02, 0.662), (0.065, 0.672), (0.105, 0.645), (0.148, 0.606),
               (0.160, 0.650), (0.163, 0.700), (0.156, 0.775), (0.110, 0.742), (0.068, 0.722),
               (0.02, 0.728), (-0.035, 0.724)]
    def th(y, z):
        if y < 0.03:
            return 0.021
        if y < 0.135:
            return 0.021 - (y - 0.03) / 0.105 * 0.016
        return max(0.0007, 0.005 - (y - 0.135) / 0.028 * 0.0043)
    slab(head, outline, th)
    return finish("iron_axe", [handle, head], offset, sharp_deg=35, bevel=0.0015)

def stone_pick(offset):
    handle = Part("bark")
    branch_handle(handle, 0.75, 0.021, 0.018, 13)
    head = Part("stone")
    zc = 0.68
    pts = [(0, -0.11, zc - 0.012), (0, -0.07, zc), (0, -0.02, zc + 0.004), (0, 0.04, zc + 0.002), (0, 0.10, zc - 0.01), (0, 0.15, zc - 0.03)]
    tube(head, pts, [0.004, 0.017, 0.026, 0.024, 0.014, 0.003], sides=9, jitter=0.12, sx=0.85, seed=15)
    lash = Part("rope")
    for z in (zc - 0.05, zc - 0.04, zc + 0.04):
        ring(lash, z, 0.021, 0.0035)
    ring(lash, zc, 0.03, 0.0035, y=-0.012, axis="x", rz=0.045)
    ring(lash, zc, 0.03, 0.0035, y=0.012, axis="x", rz=0.045)
    return finish("stone_pick", [handle, head, lash], offset, sharp_deg=60)

def iron_pick(offset):
    handle = Part("wood_light")
    turned_handle(handle, 0.78, 17)
    head = Part("iron")
    zc = 0.735
    pts, radii = [], []
    for i in range(13):
        t = -1.0 + 2.0 * i / 12
        y = t * 0.2
        z = zc - (t * t) * 0.045
        pts.append((0, y, z))
        radii.append(0.0035 + 0.019 * (1 - abs(t)) ** 0.8 + (0.006 if abs(t) < 0.1 else 0.0))
    tube(head, pts, radii, sides=8, sx=0.8, seed=19)
    # cinta do olho em volta do cabo
    tube(head, [(0, 0, zc - 0.035), (0, 0, zc + 0.02)], [0.026, 0.026], sides=12, sy=1.25)
    return finish("iron_pick", [handle, head], offset, sharp_deg=40, bevel=0.001)

def leaf_outline(z0, z1, half_w, jag=0.0, seed=0, points=14):
    r = np.random.default_rng(seed)
    out = []
    for i in range(points + 1):  # lado do gume (+Y), de baixo para cima
        t = i / points
        w = half_w * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.8 if t < 0.99 else 0.0
        out.append((w + r.uniform(-jag, jag) * w, z0 + (z1 - z0) * t))
    for i in range(points - 1, 0, -1):  # volta pelo outro lado
        y, z = out[i]
        out.append((-y + r.uniform(-jag, jag) * abs(y), z))
    return out

def stone_knife(offset):
    handle = Part("wood_dark")
    tube(handle, [(0, 0, 0), (0, 0, 0.165)], [0.013, 0.014], sides=10, sy=1.2)
    wrap = Part("rope")
    z = 0.035
    while z < 0.16:
        ring(wrap, z, 0.0145, 0.0028, rx=1.0, sides=6, seg=14)
        z += 0.0085
    blade = Part("flint")
    outline = leaf_outline(0.15, 0.31, 0.021, jag=0.12, seed=3)
    slab(blade, outline, lambda y, z: max(0.0008, 0.0055 * (1 - (abs(y) / 0.022) ** 1.5)))
    return finish("stone_knife", [handle, wrap, blade], offset, sharp_deg=50)

def iron_knife(offset):
    handle = Part("wood_dark")
    tube(handle, [(0, 0, 0), (0, 0, 0.012), (0, 0, 0.15), (0, 0, 0.158)], [0.011, 0.0135, 0.013, 0.011], sides=12, sx=0.8, sy=1.35)
    rivets = Part("iron")
    for zr in (0.045, 0.115):
        cylinder_x(rivets, (0, 0.0, zr), 0.003, 0.024)
    box(rivets, (0, 0.002, 0.161), (0.016, 0.036, 0.008))  # guarda
    blade = Part("iron")
    outline = [(-0.010, 0.165), (0.016, 0.165), (0.017, 0.22), (0.014, 0.265), (0.006, 0.296), (-0.006, 0.312),
               (-0.009, 0.29), (-0.010, 0.24)]
    slab(blade, outline, lambda y, z: max(0.0006, 0.0021 - (y + 0.01) / 0.027 * 0.0016))
    return finish("iron_knife", [handle, rivets, blade], offset, sharp_deg=35)

def machete(offset):
    handle = Part("leather")
    tube(handle, [(0, 0, 0), (0, 0, 0.01), (0, 0, 0.13), (0, 0, 0.142)], [0.012, 0.0145, 0.0135, 0.012], sides=12, sx=0.8, sy=1.35)
    metal = Part("iron_rusty")
    box(metal, (0, 0.004, 0.146), (0.018, 0.05, 0.008))  # guarda
    blade = Part("iron_rusty")
    outline = [(-0.012, 0.15), (0.020, 0.15), (0.024, 0.25), (0.030, 0.38), (0.036, 0.49), (0.034, 0.545),
               (0.020, 0.575), (0.0, 0.585), (-0.010, 0.57), (-0.011, 0.45), (-0.012, 0.30)]
    slab(blade, outline, lambda y, z: max(0.0006, 0.0028 - (y + 0.012) / 0.045 * 0.0022))
    return finish("machete", [handle, metal, blade], offset, sharp_deg=35)

def wood_spear(offset):
    shaft = Part("bark")
    branch_handle(shaft, 1.1, 0.017, 0.015, 29, wobble=0.003)
    point = Part("flint")
    outline = leaf_outline(1.075, 1.27, 0.022, jag=0.1, seed=7)
    slab(point, outline, lambda y, z: max(0.0008, 0.0065 * (1 - (abs(y) / 0.023) ** 1.5)))
    lash = Part("rope")
    z = 1.04
    while z < 1.105:
        ring(lash, z, 0.0165, 0.003, sides=6, seg=14)
        z += 0.008
    return finish("wood_spear", [shaft, point, lash], offset, sharp_deg=55)

def club(offset):
    wood = Part("bark")
    prof = [(0.0, 0.019), (0.02, 0.021), (0.3, 0.022), (0.5, 0.03), (0.62, 0.042), (0.72, 0.05), (0.77, 0.046), (0.79, 0.028), (0.80, 0.01)]
    tube(wood, [(0, 0, z) for z, _ in prof], [r for _, r in prof], sides=12, jitter=0.1, seed=37)
    knots = Part("bark")
    r = np.random.default_rng(39)
    for i in range(7):
        a = r.uniform(0, 2 * math.pi)
        z = r.uniform(0.58, 0.76)
        rad = 0.032 + (z - 0.5) * 0.07
        blob(knots, (math.cos(a) * rad, math.sin(a) * rad, z), (0.012, 0.012, 0.012), 0.2, 40 + i)
    return finish("club", [wood, knots], offset, sharp_deg=60)

def nail_bat(offset):
    wood = Part("wood_light")
    prof = [(0.0, 0.018), (0.006, 0.026), (0.02, 0.026), (0.03, 0.016), (0.28, 0.0155), (0.5, 0.026), (0.65, 0.034), (0.79, 0.036), (0.815, 0.028), (0.825, 0.01)]
    tube(wood, [(0, 0, z) for z, _ in prof], [r for _, r in prof], sides=16, seed=45)
    grip = Part("grip")
    tube(grip, [(0, 0, 0.032), (0, 0, 0.25)], [0.0175, 0.0175], sides=16, cap=(False, False))
    nails = Part("iron_rusty")
    r = np.random.default_rng(47)
    for i in range(16):
        a = 2 * math.pi * i / 8 + (0.4 if i >= 8 else 0) + r.uniform(-0.15, 0.15)
        z = 0.6 + (i % 8) * 0.024 + (0.012 if i >= 8 else 0)
        rad = 0.026 + (z - 0.5) * 0.06
        d = Vector((math.cos(a), math.sin(a), r.uniform(-0.25, 0.25))).normalized()
        base = Vector((math.cos(a) * (rad - 0.012), math.sin(a) * (rad - 0.012), z))
        cone_dir(nails, base, d, 0.0019, 0.0009, 0.052, sides=6)
    return finish("nail_bat", [wood, grip, nails], offset, sharp_deg=50)

BUILDERS = [
    ("stone_axe", stone_axe), ("iron_axe", iron_axe), ("stone_pick", stone_pick), ("iron_pick", iron_pick),
    ("stone_knife", stone_knife), ("iron_knife", iron_knife), ("machete", machete), ("wood_spear", wood_spear),
    ("club", club), ("nail_bat", nail_bat),
]

SPACING = 0.42
objects = {}
for i, (name, fn) in enumerate(BUILDERS):
    objects[name] = fn(Vector((0, i * SPACING, 0)))

# --------------------------------------------------------------- exporta ---
os.makedirs(OUT_DIR, exist_ok=True)
for name, obj in objects.items():
    keep = obj.location.copy()
    obj.location = (0, 0, 0)
    for o in bpy.data.objects:
        o.select_set(o == obj)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT", export_image_format="AUTO")
    obj.location = keep
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("exportado %s (%d triângulos)" % (path, tris))

# ---------------------------------------------------------------- prévia ---
if PREVIEW:
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.32, 0.34, 0.37, 1)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world
    # chão escuro
    bpy.ops.mesh.primitive_plane_add(size=20, location=(-0.3, 2.0, 0))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fb = next(n for n in fm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    fb.inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
    floor.data.materials.append(fm)
    floor.rotation_euler = (0, math.radians(90), 0)  # parede atrás (plano YZ)
    floor.location = (-0.15, 2.0, 0.5)
    for direction, energy in (((-1.0, 0.5, -0.8), 4.0), ((-0.6, -1.0, 0.2), 1.5)):
        sun = bpy.data.lights.new("sun", "SUN")
        sun.energy = energy
        so = bpy.data.objects.new("sun", sun)
        so.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
        coll.objects.link(so)
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = SPACING * len(BUILDERS) + 0.2
    co = bpy.data.objects.new("cam", cam)
    co.location = (2.0, SPACING * (len(BUILDERS) - 1) / 2 + 0.07, 0.64)
    co.rotation_euler = (math.radians(90), 0, math.radians(90))
    coll.objects.link(co)
    scene.camera = co
    engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
    for e in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "BLENDER_WORKBENCH"):
        if e in engines:
            try:
                scene.render.engine = e
                break
            except TypeError:
                pass
    scene.render.resolution_x = 1800
    scene.render.resolution_y = int(1800 * 1.45 / cam.ortho_scale)
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("prévia em " + PREVIEW + " (" + scene.render.engine + ")")
    # Closes em 3/4 da parte de cima (cabeça / lâmina) de cada ferramenta.
    floor.hide_render = True
    cam.type = "PERSP"
    cam.lens = 70
    scene.render.resolution_x = 520
    scene.render.resolution_y = 520
    for name, obj in objects.items():
        for other in objects.values():
            other.hide_render = other != obj
        corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        lo = min(c.z for c in corners)
        hi = max(c.z for c in corners)
        focus_z = hi - min(0.18, (hi - lo) * 0.5)
        target = Vector((0, obj.location.y + 0.04, focus_z))
        size = min(0.42, hi - lo)
        co.location = target + Vector((0.75, -0.45, 0.25)).normalized() * (size * 2.4 + 0.15)
        co.rotation_euler = (target - co.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = PREVIEW.replace(".png", "_" + name + ".png")
        bpy.ops.render.render(write_still=True)
