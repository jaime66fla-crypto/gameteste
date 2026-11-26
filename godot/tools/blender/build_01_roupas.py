"""Roupas do personagem 01: camiseta, bermuda, calça e boné, moldadas no corpo.

Usado por build_01.py (não roda sozinho). Cada peça nasce da PRÓPRIA malha do
corpo MPFB em alta resolução, antes da redução:
  1. regiões por osso + juntas do rig (manga até o meio do braço, bainha da
     bermuda acima do joelho, calça até o tornozelo, boné acima da testa/orelhas);
  2. a região é copiada com os pesos de osso e o UV do MakeHuman do corpo, então
     a roupa dobra exatamente com a pele em qualquer animação;
  3. afastamento ao longo da normal (folga por peça: manga/bermuda abrem na
     barra) + suavização laplaciana (tecido não entra no umbigo, na coluna,
     entre os glúteos) + "shrinkwrap" que empurra para fora do corpo: nada fura;
  4. redução igual à do corpo, pesos reprojetados da versão alta, nova checagem
     contra o corpo reduzido (e camiseta por cima de calça/bermuda), barra com
     espessura para dentro e aba do boné;
  5. textura de tecido assada no layout UV do MakeHuman (skins = outra textura);
  6. no corpo, cada face totalmente coberta ganha um material "Pele01-<peças>":
     o jogo remove essas superfícies quando a peça está vestida (sem pele vazando).
"""
import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector as V
from mathutils.bvhtree import BVHTree

PIECES = ["camiseta", "bermuda", "calca", "bone"]
# Cores lineares (paleta urbana escura): camiseta grafite, bermuda oliva,
# calça jeans escuro, boné preto.
COLORS = {"camiseta": (0.05, 0.052, 0.056), "bermuda": (0.075, 0.07, 0.042),
          "calca": (0.028, 0.038, 0.062), "bone": (0.022, 0.022, 0.024)}
TEX_SIZE = 1024
SLEEVE_T = 0.5    # barra da manga ao longo do braço (0 ombro, 1 cotovelo)
SHORTS_T = 0.78   # barra da bermuda ao longo da coxa (1 = joelho)
PANTS_T = 1.9     # barra da calça ao longo da canela (2 = tornozelo)
# Folga mínima depois de reduzir (corpo reduzido pode estufar uns mm).
MIN_GAP = {"camiseta": 0.006, "bermuda": 0.005, "calca": 0.005, "bone": 0.005}
BRIM = 0.075      # aba do boné (m)

def _ctx(ob):
    return bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob])

def _world(ob):
    mw = ob.matrix_world
    return np.array([tuple(mw @ v.co) for v in ob.data.vertices])

def _normals(ob):
    m3 = ob.matrix_world.to_3x3().inverted().transposed()
    return np.array([tuple((m3 @ v.normal).normalized()) for v in ob.data.vertices])

def _bvh(ob):
    mw = ob.matrix_world
    return BVHTree.FromPolygons([mw @ v.co for v in ob.data.vertices], [list(p.vertices) for p in ob.data.polygons])

def joints(rig):
    return {b.name.split(":")[-1]: rig.matrix_world @ b.head_local for b in rig.data.bones}

def _seg_t(P, a, b, c):
    """0 em a, 1 em b, 2 em c ao longo do membro (a->b->c)."""
    a, b, c = (np.array(tuple(x)) for x in (a, b, c))
    ab, bc = b - a, c - b
    t1 = (P - a) @ ab / ab.dot(ab)
    t2 = (P - b) @ bc / bc.dot(bc)
    return np.where(t1 <= 1.0, t1, 1.0 + np.maximum(t2, 0.0))

def _limb_weights(body):
    n = len(body.data.vertices)
    arm = {"Left": np.zeros(n), "Right": np.zeros(n)}
    leg = {"Left": np.zeros(n), "Right": np.zeros(n)}
    head = np.zeros(n)
    total = np.zeros(n)
    names = {g.index: g.name.split(":")[-1] for g in body.vertex_groups}
    for v in body.data.vertices:
        for e in v.groups:
            total[v.index] += e.weight
            nm = names.get(e.group, "")
            side = "Left" if nm.startswith("Left") else ("Right" if nm.startswith("Right") else "")
            part = nm[len(side):]
            if side and part.startswith(("Arm", "ForeArm", "Hand")):
                arm[side][v.index] += e.weight
            elif side and part.startswith(("UpLeg", "Leg", "Foot", "Toe")):
                leg[side][v.index] += e.weight
            elif nm in ("Neck", "Head") or nm.startswith("Head"):
                head[v.index] += e.weight
    # Os pesos do MPFB não somam 1 (o modificador normaliza): usa a fração.
    total[total == 0] = 1
    for d in (arm, leg):
        for k in d:
            d[k] /= total
    return arm, leg, head / total

def regioes(body, rig, eyes):
    """Máscaras (por vértice do corpo alto) e folga de cada peça."""
    P, N = _world(body), _normals(body)
    J = joints(rig)
    arm, leg, head = _limb_weights(body)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    is_arm = (arm["Left"] > 0.5) | (arm["Right"] > 0.5)
    is_leg = (leg["Left"] > 0.5) | (leg["Right"] > 0.5)
    t_arm = np.where(arm["Left"] >= arm["Right"],
                     _seg_t(P, J["LeftArm"], J["LeftForeArm"], J["LeftHand"]),
                     _seg_t(P, J["RightArm"], J["RightForeArm"], J["RightHand"]))
    t_leg = np.where(leg["Left"] >= leg["Right"],
                     _seg_t(P, J["LeftUpLeg"], J["LeftLeg"], J["LeftFoot"]),
                     _seg_t(P, J["RightUpLeg"], J["RightLeg"], J["RightFoot"]))
    hips, neck = J["Hips"], J["Neck"]
    # Gola careca rente ao pescoço: corte geométrico em volta do eixo do
    # pescoço (o peso do osso Neck desce pelo trapézio e abria um decote
    # canoa). Atrás fica na base do pescoço; na frente desce ~2,5 cm.
    front_neck = np.clip((neck.y - y) / 0.06, 0, 1)
    collar = neck.z + 0.004 - 0.028 * front_neck ** 1.5
    r_neck = np.hypot(x - neck.x, (y - neck.y) * 1.15)
    on_neck = (z > collar) & (r_neck < 0.085)
    hem = hips.z - 0.035
    body_ok = ~is_arm & (head < 0.5)
    shirt = ((~is_arm & (z >= hem)) | (is_arm & (t_arm < SLEEVE_T))) & ~on_neck & (z < neck.z + 0.04)
    # Cós um pouco abaixo do umbigo, mais baixo na frente.
    front_hip = np.clip((hips.y - y) / 0.1, 0, 1)
    waist = hips.z + 0.06 - 0.02 * front_hip
    lower = body_ok & (z <= waist)
    shorts = lower & (~is_leg | (t_leg < SHORTS_T))
    pants = lower & (~is_leg | (t_leg < PANTS_T))
    # Boné: acima da testa na frente, desce atrás, passa por cima das orelhas.
    ec = sum((c for c, r in eyes), V()) / max(1, len(eyes))
    cap_cut = ec.z + 0.05 - 0.29 * (y - ec.y)
    cap = (head > 0.6) & (z > cap_cut)
    off = {
        # camiseta: 1 cm no tronco, mais solta perto da barra; manga abre na barra
        "camiseta": np.where(is_arm, 0.009 + 0.009 * np.clip(t_arm / SLEEVE_T, 0, 1) ** 2,
                             0.010 + 0.006 * np.clip((hips.z + 0.15 - z) / 0.18, 0, 1)),
        # bermuda: justa no cós, larga na barra
        "bermuda": np.where(is_leg, 0.008 + 0.014 * np.clip(t_leg / SHORTS_T, 0, 1) ** 1.5, 0.008),
        # calça reta: justa no quadril, mais folga na canela
        "calca": np.where(is_leg, 0.007 + 0.004 * np.clip(t_leg, 0, 1) + 0.008 * np.clip(t_leg - 1, 0, 1), 0.007),
        # boné: copa mais alta que o crânio
        "bone": 0.007 + 0.012 * np.clip((z - cap_cut) / 0.12, 0, 1),
    }
    masks = {"camiseta": shirt, "bermuda": shorts, "calca": pants, "bone": cap}
    for k, m in masks.items():
        print("roupas: %s %d vertices" % (k, int(m.sum())))
    return {"P": P, "N": N, "masks": masks, "off": off, "waist": waist, "hem": hem,
            "head_center": ec}

# ---------------------------------------------------------------- moldagem

def _edges(me):
    E = np.zeros(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", E)
    return E.reshape(-1, 2)

def _boundary_edges(me):
    count = np.zeros(len(me.edges), dtype=np.int64)
    keys = {}
    for i, e in enumerate(me.edges):
        keys[tuple(sorted(e.vertices))] = i
    for p in me.polygons:
        for k in p.edge_keys:
            count[keys[tuple(sorted(k))]] += 1
    E = _edges(me)
    return E[count == 1]

def _smooth(Q, E, EB, lam=0.5):
    """Laplaciano: interior com todos os vizinhos, barra só ao longo da barra."""
    n = len(Q)
    isb = np.zeros(n, bool)
    isb[EB.ravel()] = True
    S, D = np.zeros_like(Q), np.zeros(n)
    for a, b in ((0, 1), (1, 0)):
        src, dst = E[:, a], E[:, b]
        ok = ~isb[dst]
        np.add.at(S, dst[ok], Q[src[ok]])
        np.add.at(D, dst[ok], 1)
        src, dst = EB[:, a], EB[:, b]
        np.add.at(S, dst, Q[src])
        np.add.at(D, dst, 1)
    m = D > 0
    out = Q.copy()
    out[m] = Q[m] + lam * (S[m] / D[m, None] - Q[m])
    return out

def _push(Q, bvh, gap, only=None):
    """Shrinkwrap para fora: cada ponto fica a pelo menos `gap` da superfície."""
    moved = 0
    for i in range(len(Q)):
        if only is not None and not only[i]:
            continue
        p = V(Q[i])
        loc, nrm, fi, d = bvh.find_nearest(p)
        if loc is None:
            continue
        g = gap[i] if hasattr(gap, "__len__") else gap
        s = (p - loc).dot(nrm)
        if s < g:
            Q[i] = tuple(p + nrm * (g - s))
            moved += 1
    return moved

def _set_positions(ob, Q):
    inv = ob.matrix_world.inverted()
    for v, q in zip(ob.data.vertices, Q):
        v.co = inv @ V(q)

def _extract(body, mask, name):
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = ob.data.name = "Roupa_" + name
    bpy.context.scene.collection.objects.link(ob)
    for m in list(ob.modifiers):
        if m.type != 'ARMATURE':
            ob.modifiers.remove(m)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    orig = bm.verts.layers.int.new("orig")
    for v in bm.verts:
        v[orig] = v.index
    drop = [f for f in bm.faces if not all(mask[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context='FACES_ONLY')
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    # Ilhas pequenas (sobras do corte) saem.
    seen, islands = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        stack, isl = [f], []
        seen.add(f)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        islands.append(isl)
    big = max(len(i) for i in islands)
    small = [f for isl in islands if len(isl) < 0.05 * big for f in isl]
    if small:
        bmesh.ops.delete(bm, geom=small, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.verts.ensure_lookup_table()
    idx = np.array([v[orig] for v in bm.verts])
    bm.verts.layers.int.remove(orig)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.materials.clear()
    return ob, idx

def moldar(body, R):
    """Peças em alta resolução, já afastadas e suavizadas sobre o corpo alto."""
    bvh = _bvh(body)
    pieces = {}
    for name in PIECES:
        ob, idx = _extract(body, R["masks"][name], name)
        off = R["off"][name][idx]
        Q = R["P"][idx] + R["N"][idx] * off[:, None]
        E, EB = _edges(ob.data), _boundary_edges(ob.data)
        for _ in range(5):
            Q = _smooth(Q, E, EB, 0.5)
            _push(Q, bvh, off)
        _set_positions(ob, Q)
        pieces[name] = ob
        print("roupas: %s alta %d vertices, %d na barra" % (name, len(Q), len(np.unique(EB))))
    return pieces

# ---------------------------------------------------------------- acabamento

def _decimate(ob, ratio):
    hi = ob.copy()
    hi.data = ob.data.copy()
    hi.modifiers.clear()
    bpy.context.scene.collection.objects.link(hi)
    dec = ob.modifiers.new("Decimate", 'DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = ratio
    dec.use_symmetry = True
    dec.symmetry_axis = 'X'
    with _ctx(ob):
        bpy.ops.object.modifier_move_to_index(modifier=dec.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dec.name)
    dt = ob.modifiers.new("Weights", 'DATA_TRANSFER')
    dt.object = hi
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    with _ctx(ob):
        bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(hi)

def _rigid_head(ob):
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    g = ob.vertex_groups.new(name="mixamorig:Head")
    g.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')

def _boundary_loops(bm):
    edges = [e for e in bm.edges if e.is_boundary]
    nxt = {}
    for e in edges:
        f = e.link_faces[0]
        for l in f.loops:
            if l.edge == e:
                nxt[l.vert] = l.link_loop_next.vert  # sentido da face
    loops, used = [], set()
    for start in list(nxt):
        if start in used:
            continue
        loop, v = [], start
        while v not in used and v in nxt:
            used.add(v)
            loop.append(v)
            v = nxt[v]
        loops.append(loop)
    return loops

def _brim(ob, R):
    """Aba do boné presa no arco da frente da borda da copa."""
    mw, inv = ob.matrix_world, ob.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.active
    loop = max(_boundary_loops(bm), key=len)
    pts = [mw @ v.co for v in loop]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    def uv_of(v):
        return v.link_loops[0][uv].uv.copy() if uv and v.link_loops else None
    outer, lower, lower_in = [], [], []
    for v, p in zip(loop, pts):
        u = V((p.x - cx, p.y - cy, 0)).normalized()
        fwd = -u.y
        t = min(1.0, max(0.0, (fwd - 0.3) / 0.6))
        t = t * t * (3 - 2 * t)
        d = V((u.x * 0.55, u.y, 0)).normalized()
        o = p + d * (BRIM * t) + V((0, 0, -0.16 * BRIM * t - 0.008 * (1 - fwd) * t))
        outer.append((t, o))
    new_faces = []
    n = len(loop)
    ov, lv, li = {}, {}, {}
    for i in range(n):
        t, o = outer[i]
        if t <= 0.0 and outer[(i + 1) % n][0] <= 0.0 and outer[i - 1][0] <= 0.0:
            continue
        ov[i] = bm.verts.new(inv @ o)
        lv[i] = bm.verts.new(inv @ (o + V((0, 0, -0.006))))
        li[i] = bm.verts.new(inv @ (pts[i] + V((0, 0, -0.006))))
    for i in range(n):
        j = (i + 1) % n
        if i not in ov or j not in ov:
            continue
        a, b = loop[i], loop[j]
        quads = [(b, a, ov[i], ov[j]),            # topo (sentido oposto ao da copa)
                 (ov[j], ov[i], lv[i], lv[j]),    # borda da aba
                 (lv[j], lv[i], li[i], li[j])]    # baixo
        for q in quads:
            try:
                f = bm.faces.new(q)
            except ValueError:
                continue
            f.smooth = False
            new_faces.append((f, a))
    if uv:
        for f, a in new_faces:
            c = uv_of(a)
            for l in f.loops:
                l[uv].uv = c
    bm.to_mesh(ob.data)
    bm.free()
    print("roupas: aba do bone com %d faces" % len(new_faces))

def _rim(ob, body_bvh, depth=0.008):
    """Barra com espessura: a borda dobra para dentro, em direção ao corpo."""
    mw, inv = ob.matrix_world, ob.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if e.is_boundary]
    res = bmesh.ops.extrude_edge_only(bm, edges=edges)
    for v in (g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)):
        p = mw @ v.co
        loc, nrm, fi, d = body_bvh.find_nearest(p)
        if loc is None:
            continue
        v.co = inv @ (p + (loc - p).normalized() * min(depth, 0.6 * d))
    for f in (g for g in res["geom"] if isinstance(g, bmesh.types.BMFace)):
        f.smooth = False
    bm.to_mesh(ob.data)
    bm.free()

def _bake_fabric(ob, name):
    """Tecido: cor base com manchas e trama fina, assado no UV do MakeHuman."""
    path = os.path.join(TEX_DIR, name + ".png")
    mat = bpy.data.materials.new("Bake_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    big = nt.nodes.new("ShaderNodeTexNoise")
    big.inputs["Scale"].default_value = 9.0
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 140.0
    fine.inputs["Detail"].default_value = 1.0
    mix = nt.nodes.new("ShaderNodeMath")
    mix.operation = 'MULTIPLY_ADD'
    nt.links.new(coord.outputs["Object"], big.inputs["Vector"])
    nt.links.new(coord.outputs["Object"], fine.inputs["Vector"])
    nt.links.new(fine.outputs["Fac"], mix.inputs[0])
    mix.inputs[1].default_value = 0.35
    nt.links.new(big.outputs["Fac"], mix.inputs[2])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    c = COLORS[name]
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (c[0] * 0.8, c[1] * 0.8, c[2] * 0.8, 1)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = (c[0] * 1.2, c[1] * 1.2, c[2] * 1.2, 1)
    nt.links.new(mix.outputs[0], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    img = bpy.data.images.new("roupa_" + name, TEX_SIZE, TEX_SIZE)
    img.generated_color = (c[0], c[1], c[2], 1)
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = img
    nt.nodes.active = node
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 2
    bake = sc.render.bake
    bake.use_pass_direct = bake.use_pass_indirect = False
    bake.use_pass_color = True
    bake.margin = 8
    for o in sc.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='DIFFUSE')
    os.makedirs(TEX_DIR, exist_ok=True)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    # Material final: textura do tecido (o Godot troca pela PNG pelo nome).
    final = bpy.data.materials.new("Roupa_" + name)
    final.use_nodes = True
    fb = next(n for n in final.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = final.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = img
    final.node_tree.links.new(tex.outputs["Color"], fb.inputs["Base Color"])
    fb.inputs["Roughness"].default_value = 0.9
    ob.data.materials.clear()
    ob.data.materials.append(final)
    print("roupas: textura ->", path)

TEX_DIR = ""

def finalizar(pieces, body, ratio, R, smooth_weights, tex_dir):
    """Reduz, repesa, confere folga contra o corpo reduzido, barra, aba, textura."""
    global TEX_DIR
    TEX_DIR = tex_dir
    body_bvh = _bvh(body)
    for name in PIECES:
        ob = pieces[name]
        _decimate(ob, ratio)
        if name == "bone":
            _rigid_head(ob)
        else:
            smooth_weights(ob)
        for p in ob.data.polygons:
            p.use_smooth = False
        Q = _world(ob)
        for _ in range(2):
            moved = _push(Q, body_bvh, MIN_GAP[name])
        _set_positions(ob, Q)
        print("roupas: %s reduzida %d tris, %d vertices empurrados" % (name, sum(len(p.vertices) - 2 for p in ob.data.polygons), moved))
    # Camiseta por cima do cós da calça e da bermuda.
    shirt = pieces["camiseta"]
    Q = _world(shirt)
    waist_top = max(_world(pieces["calca"])[:, 2].max(), _world(pieces["bermuda"])[:, 2].max())
    low = Q[:, 2] < waist_top + 0.005
    for lower in ("calca", "bermuda"):
        lb = _bvh(pieces[lower])
        for _ in range(2):
            m = _push(Q, lb, 0.004, only=low)
        print("roupas: camiseta sobre %s: %d vertices" % (lower, m))
    _set_positions(shirt, Q)
    for name in PIECES:
        ob = pieces[name]
        if name == "bone":
            _brim(ob, R)
        _rim(ob, body_bvh, 0.006 if name == "bone" else 0.008)
        if name == "bone":
            _rigid_head(ob)  # aba e barra nasceram sem peso: tudo preso na cabeça
        if tex_dir:
            _bake_fabric(ob, name)
        else:
            m = bpy.data.materials.new("Roupa_" + name)
            m.use_nodes = True
            next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = COLORS[name] + (1,)
            ob.data.materials.clear()
            ob.data.materials.append(m)

# ---------------------------------------------------------------- pele coberta

def zonas(body, src, R):
    """Divide a pele do corpo reduzido por quais peças a cobrem por inteiro."""
    me = src.data
    E = _edges(me)
    interior = {}
    for name in PIECES:
        m = R["masks"][name].copy()
        for _ in range(2):  # erosão de 2 anéis: borda da roupa nunca deixa buraco
            bad = ~m[E[:, 0]] | ~m[E[:, 1]]
            m[E[bad].ravel()] = False
        interior[name] = m
    covered = {}
    for name in PIECES:
        m = interior[name]
        covered[name] = np.array([all(m[i] for i in p.vertices) for p in me.polygons])
    hi = _bvh(src)
    mw = body.matrix_world
    skin = body.data.materials[0]
    groups = {}
    for p in body.data.polygons:
        if p.material_index != 0:
            continue
        pts = [mw @ body.data.vertices[i].co for i in p.vertices]
        c = sum(pts, V()) / len(pts)
        samples = [c] + [c + (q - c) * 0.9 for q in pts]
        faces = [hi.find_nearest(s)[2] for s in samples]
        cls = tuple(n for n in PIECES if all(f is not None and covered[n][f] for f in faces))
        if cls:
            groups.setdefault(cls, []).append(p.index)
    for cls, faces in sorted(groups.items()):
        mat = skin.copy()
        mat.name = "Pele01-" + "-".join(cls)
        body.data.materials.append(mat)
        k = len(body.data.materials) - 1
        for i in faces:
            body.data.polygons[i].material_index = k
        print("roupas: pele %s %d faces" % (mat.name, len(faces)))
