"""Texturas de marca das roupas pagas do 01 (marca própria do jogo: BRASA).

    godot --headless --path godot --script res://tools/characters/export_roupas.gd
    python godot/tools/characters/paint_roupas.py [--preview]

Lê as malhas Roupa_* exportadas (posição de repouso + UV do MakeHuman), pinta
cada triângulo no UV com detalhes decididos pela POSIÇÃO no corpo (costuras,
golas, bolsos, logo), e grava:
  roupas/<skin>.png        cor (2048 px) das skins pagas;
  roupas/<peça>_normal.png relevo do tecido (trama, costuras, gomos, bolsos),
                           usado por todas as skins da peça (avatar_01.gd).
Eixos do modelo: +Z frente, +Y cima, +X lado esquerdo do personagem.
Marca e emblema são originais (chama estilizada + BRASA), nada de marca real.
"""
import json
import math
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

GODOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(GODOT, "assets", "personagens", "01", "roupas")
SIZE = 2048
FONT = "C:/Windows/Fonts/bahnschrift.ttf"

# ------------------------------------------------------------------ util

def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float) / 255.0

def hash3(i):
    i = i.astype(np.int64)
    h = (i[..., 0] * 73856093) ^ (i[..., 1] * 19349663) ^ (i[..., 2] * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0

def vnoise(p):
    i = np.floor(p)
    f = p - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hash3(i + np.array([dx, dy, dz]))
    return out

def fbm(p, octaves=3):
    v, a = 0, 0.5
    for _ in range(octaves):
        v = v + a * vnoise(p)
        p = p * 2.03 + 1.7
        a *= 0.5
    return v

def band(d, w, aa=0.0015):
    """1 dentro da faixa |d| < w (borda suave)."""
    return np.clip((w - np.abs(d)) / aa + 0.5, 0, 1)

def stitch_line(d, along, w=0.0007, pitch=0.0045):
    """Pesponto: tracejado fino ao longo de uma linha (d = distância à linha)."""
    dash = (np.mod(along, pitch) < pitch * 0.62).astype(float)
    return band(d, w, 0.0006) * dash

# ------------------------------------------------------------- malha/UV

def load(piece):
    d = json.load(open(os.path.join(GODOT, ".godot", "roupa_%s.json" % piece)))
    return np.array(d["v"]), np.array(d["n"]), np.array(d["uv"]), np.array(d["i"]).reshape(-1, 3)

def boundary_dist(V, T, groups):
    """Distância (m) de cada vértice à borda de cada grupo (ex.: gola, mangas)."""
    from collections import Counter
    edges = Counter()
    for a, b, c in T:
        for e in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted(e))] += 1
    bverts = np.unique([v for e, k in edges.items() if k == 1 for v in e])
    out = {}
    for name, sel in groups.items():
        B = V[bverts[sel(V[bverts])]]
        if len(B) == 0:
            out[name] = np.full(len(V), 9.0)
            continue
        d = np.full(len(V), 9.0)
        for s in range(0, len(V), 2048):
            d[s:s + 2048] = np.sqrt(((V[s:s + 2048, None, :] - B[None]) ** 2).sum(-1)).min(1)
        out[name] = d
    return out

def raster(V, N, UV, T, attrs):
    """Para cada texel coberto: posição, normal e atributos interpolados."""
    S = SIZE
    px = UV * np.array([S, S]) - 0.5
    cov = np.zeros((S, S), bool)
    P = np.zeros((S, S, 3))
    NN = np.zeros((S, S, 3))
    A = {k: np.zeros((S, S)) for k in attrs}
    for a, b, c in T:
        pa, pb, pc = px[a], px[b], px[c]
        x0 = int(max(0, math.floor(min(pa[0], pb[0], pc[0])) - 1))
        x1 = int(min(S - 1, math.ceil(max(pa[0], pb[0], pc[0])) + 1))
        y0 = int(max(0, math.floor(min(pa[1], pb[1], pc[1])) - 1))
        y1 = int(min(S - 1, math.ceil(max(pa[1], pb[1], pc[1])) + 1))
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        den = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(den) < 1e-9:
            continue
        w0 = ((pb[1] - pc[1]) * (gx - pc[0]) + (pc[0] - pb[0]) * (gy - pc[1])) / den
        w1 = ((pc[1] - pa[1]) * (gx - pc[0]) + (pa[0] - pc[0]) * (gy - pc[1])) / den
        w2 = 1 - w0 - w1
        m = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
        if not m.any():
            continue
        ys, xs = gy[m], gx[m]
        W = np.stack([w0[m], w1[m], w2[m]], -1)
        P[ys, xs] = W @ np.stack([V[a], V[b], V[c]])
        NN[ys, xs] = W @ np.stack([N[a], N[b], N[c]])
        for k, arr in attrs.items():
            A[k][ys, xs] = W @ np.array([arr[a], arr[b], arr[c]])
        cov[ys, xs] = True
    n = np.linalg.norm(NN, axis=-1, keepdims=True)
    NN = NN / np.maximum(n, 1e-6)
    return cov, P, NN, A

def dilate(img, cov, steps=12):
    """Espalha as bordas das ilhas de UV (sem costura escura nas emendas)."""
    img = img.copy()
    cov = cov.copy()
    for _ in range(steps):
        acc = np.zeros_like(img)
        cnt = np.zeros(cov.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(cov, dy, 0), dx, 1)
            acc += np.roll(np.roll(img, dy, 0), dx, 1) * sh[..., None]
            cnt += sh
        new = (~cov) & (cnt > 0)
        img[new] = acc[new] / cnt[new, None]
        cov = cov | new
    return img

def normal_map(H, cov, strength):
    """Relevo em espaço tangente a partir da altura pintada no UV."""
    H = dilate(H[..., None], cov, 6)[..., 0]
    gx = np.roll(H, -1, 1) - np.roll(H, 1, 1)
    gy = np.roll(H, -1, 0) - np.roll(H, 1, 0)
    n = np.stack([-gx * strength, gy * strength, np.ones_like(H)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)

# ---------------------------------------------------------------- emblema

def emblem(size=512, text=True, color=(255, 255, 255)):
    """Chama estilizada original (gota com corte interno) e, embaixo, BRASA."""
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    cx = size / 2
    top = size * (0.06 if text else 0.08)
    base = size * (0.62 if text else 0.92)
    r = (base - top) * 0.36
    pts = []
    for i in range(41):
        t = i / 40
        ang = math.pi * (1 + t)  # meia volta embaixo
        pts.append((cx + r * math.cos(ang) * -1, base - r + r * math.sin(ang) * -1))
    outer = [(cx - r, base - r)] + [(cx + r * math.cos(a), base - r + r * math.sin(a)) for a in np.linspace(math.pi, 0, 30)]
    outer = [(cx - r, base - r)]
    for a in np.linspace(math.pi, 2 * math.pi, 30):
        outer.append((cx + r * math.cos(a), base - r - r * math.sin(a) * -1))
    # Corpo da chama: base redonda e ponta curva para a direita.
    flame = [(cx + r * math.cos(a), base - r + r * math.sin(a)) for a in np.linspace(0, math.pi, 32)]
    flame += [(cx - r * 0.95, base - r * 1.6), (cx - r * 0.55, base - r * 2.3), (cx + r * 0.05, top + r * 0.4),
              (cx + r * 0.25, top), (cx + r * 0.55, base - r * 2.1), (cx + r * 0.95, base - r * 1.4)]
    d.polygon(flame, fill=255)
    inner = [(cx + r * 0.45 * math.cos(a), base - r * 0.75 + r * 0.45 * math.sin(a)) for a in np.linspace(0, math.pi, 20)]
    inner += [(cx - r * 0.35, base - r * 1.3), (cx + r * 0.05, base - r * 1.85), (cx + r * 0.4, base - r * 1.2)]
    d.polygon(inner, fill=0)
    if text:
        font = ImageFont.truetype(FONT, int(size * 0.24))
        try:
            font.set_variation_by_name("Bold")
        except Exception:
            pass
        w = d.textlength("BRASA", font=font)
        d.text((cx - w / 2, size * 0.68), "BRASA", fill=255, font=font)
    return np.asarray(img, float) / 255.0

def decal(P, N, center, right, up, w, h, img, facing, min_facing=0.35):
    """Projeta uma imagem (0..1) num retângulo do corpo; devolve a máscara."""
    rel = P - np.array(center)
    u = (rel @ np.array(right)) / w + 0.5
    v = 0.5 - (rel @ np.array(up)) / h
    ok = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & ((N @ np.array(facing)) > min_facing)
    ok &= np.abs(rel @ np.array(facing)) < 0.08
    H, W = img.shape
    out = np.zeros(P.shape[:2])
    out[ok] = img[(v[ok] * (H - 1)).astype(int), (u[ok] * (W - 1)).astype(int)]
    return out

def paint(base, mask, color, a=1.0):
    m = (mask * a)[..., None]
    return base * (1 - m) + np.array(color) * m

# ------------------------------------------------------------------- peças

def camiseta():
    V, N, UV, T = load("camiseta")
    neck_y = V[:, 1].max()
    D = boundary_dist(V, T, {
        "gola": lambda B: B[:, 1] > neck_y - 0.06,
        "manga": lambda B: np.abs(B[:, 0]) > 0.2,
        "barra": lambda B: B[:, 1] < V[:, 1].min() + 0.05,
    })
    cov, P, NN, A = raster(V, N, UV, T, D)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    fabric = fbm(P * 260.0, 2)
    heather = fbm(P * 160.0, 3)
    col = hexc("#4b5236")[None, None] * np.ones((SIZE, SIZE, 3))
    col *= (0.86 + 0.22 * heather)[..., None] * (0.95 + 0.1 * fabric)[..., None]
    H = fabric * 0.08
    # Gola, punhos e barra canelados, com pesponto duplo.
    for key, w in (("gola", 0.016), ("manga", 0.02), ("barra", 0.022)):
        d = A[key]
        rib = (d < w) & cov
        ribs = 0.5 + 0.5 * np.sin((x * 0.6 + z * 0.8 + y * 0.2) * 2 * math.pi / 0.0035)
        if key == "manga":
            ribs = 0.5 + 0.5 * np.sin((y + z) * 2 * math.pi / 0.0035)
        col[rib] *= (0.82 + 0.1 * ribs[rib])[..., None]
        H = H + rib * (0.15 + 0.12 * ribs)
        for off in (w + 0.002, w + 0.006):
            st = stitch_line(d - off, x + y + z)
            col = paint(col, st * cov, hexc("#2f3424"), 0.8)
            H = H - st * 0.8
    # Costuras laterais e do ombro (sem manga).
    torso = np.abs(x) < 0.19
    side = band(z - 0.015, 0.0012) * torso * (np.abs(NN[..., 0]) > 0.5) * (y < 1.5)
    shoulder = band(z - 0.0, 0.0012) * (y > 1.48) * (NN[..., 1] > 0.3)
    for s in (side, shoulder):
        col = paint(col, s, hexc("#343a26"), 0.9)
        H = H - s * 1.2
    # Logo bordado no peito esquerdo e etiqueta impressa na nuca.
    em = emblem(256, text=True)
    m = decal(P, NN, (0.095, 1.42, 0.15), (1, 0, 0), (0, 1, 0), 0.07, 0.07, em, (0, 0, 1))
    col = paint(col, m, hexc("#d9d2bd"))
    H = H + m * 0.9
    em2 = emblem(256, text=True)
    m2 = decal(P, NN, (0.0, 1.535, -0.09), (-1, 0, 0), (0, 1, 0), 0.06, 0.06, em2, (0, 0, -1), 0.2)
    col = paint(col, m2, hexc("#2b2f20"), 0.85)
    return col, H, cov

def calca():
    V, N, UV, T = load("calca")
    top = V[:, 1].max()
    D = boundary_dist(V, T, {
        "cos": lambda B: B[:, 1] > top - 0.06,
        "barra": lambda B: B[:, 1] < 0.3,
    })
    cov, P, NN, A = raster(V, N, UV, T, D)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    side = np.sign(x)
    col = hexc("#4a4d50")[None, None] * np.ones((SIZE, SIZE, 3))
    # Ripstop: grade de fios mais grossos a cada 6 mm + trama fina.
    weave = fbm(P * 280.0, 2)
    gx = band(np.mod(y, 0.008) - 0.004, 0.0005, 0.0008)
    gz = band(np.mod(x + z, 0.008) - 0.004, 0.0005, 0.0008)
    grid = np.maximum(gx, gz)
    col *= (0.93 + 0.1 * weave)[..., None]
    col *= (1 - 0.035 * grid)[..., None]
    col *= (0.92 + 0.12 * fbm(P * 40.0, 2))[..., None]
    H = weave * 0.08 + grid * 0.06
    stitch = hexc("#7d7f78")
    # Cós com passantes e pesponto.
    cos = (A["cos"] < 0.04) & cov
    col[cos] *= 0.88
    H = H + cos * 0.4
    for off in (0.004, 0.036, 0.043):
        st = stitch_line(A["cos"] - off, x + z) * cov
        col = paint(col, st, stitch, 0.75)
        H = H - st * 0.7
    ang = np.arctan2(x - 0.0, z - 0.015)
    for a0 in np.radians([-150, -100, -45, 45, 100, 150, 180]):
        loop = band(np.angle(np.exp(1j * (ang - a0))), 0.05) * (A["cos"] < 0.05)
        col = paint(col, loop * cov, hexc("#3b3e41"))
        H = H + loop * 1.5
    # Barra com pesponto duplo.
    for off in (0.012, 0.016):
        st = stitch_line(A["barra"] - off, x + z) * cov
        col = paint(col, st, stitch, 0.75)
        H = H - st * 0.7
    hem = (A["barra"] < 0.01) & cov
    H = H + hem * 0.6
    # Costura lateral externa e interna.
    outer = band(z - 0.01, 0.0011) * (np.abs(x) > 0.06) * ((NN[..., 0] * side) > 0.4) * (y < top - 0.05)
    col = paint(col, outer, hexc("#33363a"), 0.9)
    H = H - outer * 1.2
    for o in (0.0035, -0.0035):
        st = stitch_line(z - 0.01 - o, y) * (np.abs(x) > 0.06) * ((NN[..., 0] * side) > 0.4) * (y < top - 0.05)
        col = paint(col, st * cov, stitch, 0.6)
    # Bolsos da frente (curva) e de trás (retângulo com pesponto).
    front = (NN[..., 2] > 0.25)
    curve = (np.abs(x) - 0.085) - (top - 0.045 - y) * 0.75
    pocket_edge = band(curve, 0.0012) * front * (y > top - 0.16) * (y < top - 0.045) * (np.abs(x) < 0.2)
    col = paint(col, pocket_edge, hexc("#2c2f32"))
    H = H - pocket_edge * 1.5
    st = stitch_line(curve - 0.004, y) * front * (y > top - 0.16) * (y < top - 0.045) * (np.abs(x) < 0.2)
    col = paint(col, st * cov, stitch, 0.7)
    back = NN[..., 2] < -0.3
    bx, by = np.abs(x) - 0.095, y - (top - 0.13)
    rect = (np.abs(bx) < 0.05) & (np.abs(by) < 0.055) & back
    edge = rect & ((np.abs(np.abs(bx) - 0.05) < 0.0025) | (np.abs(np.abs(by) - 0.055) < 0.0025))
    col[rect] *= 0.95
    col = paint(col, edge * cov, hexc("#2c2f32"))
    H = H + rect * 0.5 - edge * 0.8
    # Bolsos cargo na lateral da coxa: corpo, lapela, pesponto e etiqueta BRASA.
    outward = (NN[..., 0] * side) > 0.45
    cz, cy = z - 0.01, y - 0.66
    cargo = outward & (np.abs(cz) < 0.065) & (np.abs(cy) < 0.085)
    flap = cargo & (cy > 0.045)
    col[cargo] *= 0.93
    col[flap] *= 0.85
    H = H + cargo * 0.9 + flap * 0.6
    for edge_d in (np.abs(cz) - 0.065, np.abs(cy) - 0.085):
        e = outward & (np.abs(cz) < 0.068) & (np.abs(cy) < 0.088) & (np.abs(edge_d) < 0.0025)
        col = paint(col, e * cov, hexc("#2a2d30"))
        H = H - e * 1.2
    fl = outward & (np.abs(cz) < 0.065) & (np.abs(cy - 0.045) < 0.0018)
    col = paint(col, fl * cov, hexc("#25282b"))
    H = H - fl * 1.6
    for o in (0.006,):
        st = stitch_line(np.minimum(np.abs(np.abs(cz) - (0.065 - o)), np.abs(np.abs(cy) - (0.085 - o))), cz + cy) * cargo
        col = paint(col, st * cov, stitch, 0.65)
    patch = outward & (np.abs(cz) < 0.025) & (np.abs(cy - 0.065) < 0.012)
    col = paint(col, patch * cov, hexc("#1f2022"))
    em = emblem(256, text=False)
    for sgn in (-1, 1):
        m = decal(P, NN, (sgn * 0.2, 0.725, 0.01), (0, 0, -sgn), (0, 1, 0), 0.018, 0.018, em, (sgn, 0, 0), 0.4)
        m *= (np.sign(x) == sgn)
        col = paint(col, m, hexc("#c4521c"))
    H = H + patch * 0.5
    # Reforço do joelho (painel com pesponto duplo).
    knee = front & (np.abs(y - 0.48) < 0.075) & (np.abs(np.abs(x) - 0.15) < 0.075)
    col[knee] *= 0.9
    H = H + knee * 0.4
    for o in (0.0, 0.004):
        st = stitch_line(np.minimum(np.abs(np.abs(y - 0.48) - (0.075 - o)), 1), x) * front * (np.abs(np.abs(x) - 0.15) < 0.075)
        col = paint(col, st * cov, stitch, 0.6)
        H = H - st * 0.6
    # Etiqueta de couro sintético BRASA no cós de trás.
    em2 = emblem(256, text=True)
    lab = decal(P, NN, (0.07, top - 0.02, -0.09), (-1, 0, 0), (0, 1, 0), 0.045, 0.03, np.ones((8, 8)), (0, 0, -1), 0.2)
    col = paint(col, lab, hexc("#5a3a26"))
    m = decal(P, NN, (0.07, top - 0.02, -0.09), (-1, 0, 0), (0, 1, 0), 0.03, 0.03, em2, (0, 0, -1), 0.2)
    col = paint(col, m, hexc("#c9a77c"))
    H = H + lab * 0.6
    return col, H, cov

def bone():
    V, N, UV, T = load("bone")
    D = boundary_dist(V, T, {"borda": lambda B: np.ones(len(B), bool)})
    cov, P, NN, A = raster(V, N, UV, T, D)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    topv = V[np.argmax(V[:, 1])]
    cx, cz = topv[0], topv[2]
    col = hexc("#5b1f24")[None, None] * np.ones((SIZE, SIZE, 3))
    twill = 0.5 + 0.5 * np.sin((x + y * 1.3 + z) * 2 * math.pi / 0.0022)
    col *= (0.9 + 0.12 * fbm(P * 200.0, 2) + 0.02 * twill)[..., None]
    H = twill * 0.05
    # Seis gomos: costuras do botão até a borda, cada uma com pesponto dos dois lados.
    ang = np.arctan2(x - cx, z - cz)
    r = np.hypot(x - cx, z - cz)
    for k in range(6):
        a0 = math.radians(k * 60)
        da = np.angle(np.exp(1j * (ang - a0))) * np.maximum(r, 0.01)
        seam = band(da, 0.0011) * (r > 0.012)
        col = paint(col, seam * cov, hexc("#3e1418"))
        H = H - seam * 1.6
        for o in (0.0035, -0.0035):
            st = stitch_line(da - o, y) * (r > 0.015)
            col = paint(col, st * cov, hexc("#7e3a3f"), 0.7)
        # Ilhós bordado em cada gomo.
        mid = a0 + math.radians(30)
        ex, ez = cx + 0.055 * math.sin(mid), cz + 0.055 * math.cos(mid)
        ey = topv[1] - 0.035
        dd = np.sqrt((x - ex) ** 2 + (y - ey) ** 2 + (z - ez) ** 2)
        ring = band(dd - 0.0035, 0.0012)
        hole = dd < 0.0022
        col = paint(col, ring * cov, hexc("#7e3a3f"))
        col = paint(col, hole * cov, hexc("#1a0a0c"))
        H = H + ring * 0.8 - hole * 1.0
    # Botão no topo.
    dtop = np.sqrt((x - cx) ** 2 + (y - topv[1]) ** 2 + (z - cz) ** 2)
    btn = dtop < 0.011
    col = paint(col, btn * cov, hexc("#4a181c"))
    H = H + btn * 1.2
    # Borda inferior: pesponto.
    st = stitch_line(A["borda"] - 0.006, x + z) * (A["borda"] < 0.02)
    col = paint(col, st * cov, hexc("#7e3a3f"), 0.8)
    H = H - st * 0.6
    # Logo bordado em relevo na frente (chama + BRASA).
    em = emblem(512, text=True)
    crown = V[(V[:, 1] > 1.81) & (np.abs(V[:, 0] - cx) < 0.04)]
    front_z = crown[:, 2].max()
    front_y = crown[np.argmax(crown[:, 2]), 1] - 0.008
    m = decal(P, NN, (cx, front_y, front_z - 0.01), (1, 0, 0), (0, 1, 0), 0.07, 0.07, em, (0, 0.25, 1), 0.3)
    m *= (y > 1.805)
    col = paint(col, m, hexc("#e6dcc4"))
    H = H + m * 1.4
    return col, H, cov

PIECES = {"bone": ("bone_vinho", bone, 2.5), "camiseta": ("camiseta_oliva", camiseta, 2.0), "calca": ("calca_cinza", calca, 2.0)}

if __name__ == "__main__":
    for piece, (skin, fn, strength) in PIECES.items():
        col, H, cov = fn()
        col = dilate(np.clip(col, 0, 1), cov)
        Image.fromarray((col * 255).astype(np.uint8)).save(os.path.join(OUT, skin + ".png"))
        Image.fromarray(normal_map(H, cov, strength)).save(os.path.join(OUT, piece + "_normal.png"))
        print("roupa:", skin, "+", piece + "_normal")
