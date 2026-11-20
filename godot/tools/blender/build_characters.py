"""Builds the four playable characters in Blender, from scratch, on the Ch31 Mixamo rig.

    blender -b --factory-startup -P godot/tools/blender/build_characters.py -- [--only remy,pato] [--render DIR] [--no-export]

Every character is modelled here, in code, so it can be rebuilt and tweaked:
  - the rig comes from ch31_rig.json (tools/characters/export_rig_joints.gd), the
    skeleton all animation clips are authored on; bone names keep the mixamorig9_
    prefix so Godot can rebind the meshes onto that exact skeleton;
  - organic bodies are metaball sculpts (one family per body, a finer one for
    fingers), converted to mesh and decimated;
  - clothes are painted per face into the "Col" colour attribute (sRGB), hard gear
    is separate low-poly meshes merged into the same object;
  - skin weights are computed here (distance to bone segments, smoothed), with
    rigid zones for the head and for gear.
Outputs: assets/personagens/blender/<id>.glb (one armature + one mesh each) and
tools/blender/personagens.blend (all four side by side, for hand editing).
Godot side: tools/characters/build_blender_characters.gd turns each GLB into
<id>_modelo.scn bound to the Ch31 Skeleton3D.
"""
import bpy, bmesh, json, math, os, sys
import numpy as np
from mathutils import Vector, Matrix, noise

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(os.path.dirname(HERE))
OUT_DIR = os.path.join(GODOT, "assets", "personagens", "blender")
BLEND = os.path.join(HERE, "personagens.blend")
PREFIX = "mixamorig9_"
K = 1.0 / 0.575  # metaball radius for a given surface radius (threshold 0.6, stiffness 2)
V = Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def _arg(name, default=None):
    for a in ARGS:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default
ONLY = [s for s in (_arg("--only") or "").split(",") if s]
RENDER = _arg("--render")
EXPORT = "--no-export" not in ARGS

# ---------------------------------------------------------------- rig
RIG = json.load(open(os.path.join(HERE, "ch31_rig.json"), encoding="utf-8"))
J, PARENT, ORDER = {}, {}, []
for b in RIG["bones"]:
    s = b["name"][len(PREFIX):]
    g = b["pos"]
    J[s] = V((g[0], -g[2], g[1]))  # Godot (Y up, faces +Z) -> Blender (Z up, faces -Y)
    PARENT[s] = b["parent"][len(PREFIX):] if b["parent"] else None
    ORDER.append(s)
CHILDREN = {s: [c for c in ORDER if PARENT[c] == s] for s in ORDER}
MAIN_CHILD = {"Hips": "Spine", "Spine2": "Neck", "LeftHand": "LeftHandMiddle1", "RightHand": "RightHandMiddle1"}

def tail(s):
    c = MAIN_CHILD.get(s) or (CHILDREN[s][0] if CHILDREN[s] else None)
    if c:
        return J[c].copy()
    d = J[s] - J[PARENT[s]]
    return J[s] + d.normalized() * max(d.length * 0.6, 0.02)

FINGERS = ["Thumb", "Index", "Middle", "Ring", "Pinky"]
SIDES = (("Left", 1.0), ("Right", -1.0))
BODY_BONES = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"] + [
    side + n for side, _ in SIDES for n in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase")]
def hand_bones(side):
    return [side + "Hand"] + [side + "Hand" + f + str(i) for f in FINGERS for i in (1, 2, 3)]

def mix(a, b, t):
    return a.lerp(b, t)

def srgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, 1.0)

def frame(d, front=V((0, -1, 0))):
    """Rotation whose X follows d and whose Y is as close to `front` as possible."""
    x = d.normalized()
    y = (front - x * front.dot(x))
    if y.length < 1e-4:
        y = V((0, 0, 1)) - x * x.z
    y.normalize()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()

# ---------------------------------------------------------------- scene utils
def scratch():
    col = bpy.data.collections.get("_scratch")
    if col is None:
        col = bpy.data.collections.new("_scratch")
        bpy.context.scene.collection.children.link(col)
    return col

def bake_object(ob, decimate=None):
    """Evaluated mesh copy of `ob` (with an optional decimate to ~decimate faces)."""
    dg = bpy.context.evaluated_depsgraph_get()
    if decimate:
        me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        tmp = bpy.data.objects.new("_dec", me)
        scratch().objects.link(tmp)
        nf = sum(len(p.vertices) - 2 for p in me.polygons)
        if nf > decimate:
            mod = tmp.modifiers.new("dec", 'DECIMATE')
            mod.ratio = decimate / nf
            mod.use_collapse_triangulate = True
        dg = bpy.context.evaluated_depsgraph_get()
        dg.update()
        out = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
        bpy.data.objects.remove(tmp)
        bpy.data.meshes.remove(me)
        return out
    return bpy.data.meshes.new_from_object(ob.evaluated_get(dg))

class Meta:
    """A metaball family. Sizes are surface radii / half extents in metres."""
    count = 0
    def __init__(self, res):
        Meta.count += 1
        name = "MB%03d" % Meta.count
        self.mb = bpy.data.metaballs.new(name)
        self.mb.resolution = self.mb.render_resolution = res
        self.mb.threshold = 0.6
        self.ob = bpy.data.objects.new(name, self.mb)
        scratch().objects.link(self.ob)

    def _el(self, kind, co, R, neg=False, stiff=2.0):
        e = self.mb.elements.new()
        e.type = kind
        e.co = co
        e.radius = R * K
        e.stiffness = stiff
        e.use_negative = neg
        return e

    def ball(self, co, R, **kw):
        return self._el('BALL', co, R, **kw)

    def ellip(self, co, ext, rot=None, **kw):
        m = max(ext)
        e = self._el('ELLIPSOID', co, m, **kw)
        e.size_x, e.size_y, e.size_z = ext[0] / m, ext[1] / m, ext[2] / m
        if rot is not None:
            e.rotation = rot.to_quaternion()
        return e

    def seg(self, a, b, ext, at=0.5, front=V((0, -1, 0)), **kw):
        """Ellipsoid on segment a-b at fraction `at`: ext = (along, front, other)."""
        return self.ellip(mix(a, b, at), ext, frame(b - a, front), **kw)

    def capsule(self, a, b, R, **kw):
        d = b - a
        e = self._el('CAPSULE', (a + b) / 2, R, **kw)
        e.size_x = d.length / 2
        e.rotation = frame(d).to_quaternion()
        return e

    def mesh(self, decimate=None):
        me = bake_object(self.ob, decimate)
        bpy.data.objects.remove(self.ob)
        bpy.data.metaballs.remove(self.mb)
        return me

# ---------------------------------------------------------------- hard-surface primitives (bmesh)
def bm_to_mesh(bm, name="part"):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me

def uv_sphere(center, ext, rot=None, seg=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    m = Matrix.Diagonal((ext[0], ext[1], ext[2], 1.0))
    if rot is not None:
        m = rot.to_4x4() @ m
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ m, verts=bm.verts)
    return bm_to_mesh(bm)

def box(center, ext, rot=None, bevel=0.0, cuts=0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    if cuts:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((ext[0], ext[1], ext[2], 1.0)), verts=bm.verts)
    if bevel > 0:
        edges = [e for e in bm.edges if e.calc_face_angle(0) > 1.0]
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect='EDGES', profile=0.6)
    m = Matrix.Translation(center)
    if rot is not None:
        m = m @ rot.to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm_to_mesh(bm)

def capsule_mesh(a, b, r1, r2=None, seg=14, cap=4):
    """Tapered capsule from a (radius r1) to b (radius r2), quads + pole fans."""
    r2 = r1 if r2 is None else r2
    L = (b - a).length
    prof = []  # (radius, z)
    for i in range(cap, 0, -1):
        t = (i / cap) * math.pi / 2
        prof.append((r1 * math.cos(t), -r1 * math.sin(t)))
    prof.append((r1, 0.0))
    prof.append((r2, L))
    for i in range(1, cap + 1):
        t = (i / cap) * math.pi / 2
        prof.append((r2 * math.cos(t), L + r2 * math.sin(t)))
    bm = bmesh.new()
    rings = []
    for (r, z) in prof:
        if r < 1e-5:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
    for r0, r1_ in zip(rings, rings[1:]):
        if len(r0) == 1:
            for k in range(seg):
                bm.faces.new((r0[0], r1_[(k + 1) % seg], r1_[k]))
        elif len(r1_) == 1:
            for k in range(seg):
                bm.faces.new((r0[k], r0[(k + 1) % seg], r1_[0]))
        else:
            for k in range(seg):
                bm.faces.new((r0[k], r0[(k + 1) % seg], r1_[(k + 1) % seg], r1_[k]))
    rot = V((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm_to_mesh(bm)

def cylinder(a, b, r1, r2=None, seg=16, caps=True):
    r2 = r1 if r2 is None else r2
    bm = bmesh.new()
    L = (b - a).length
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r1, radius2=r2, depth=L)
    bmesh.ops.translate(bm, vec=V((0, 0, L / 2)), verts=bm.verts)
    rot = V((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    return bm_to_mesh(bm)

def ring(center, axis, r_in, r_out, height, seg=24, rot=None):
    """Thick tube (open band) around `axis`, e.g. belts, collars, cuffs."""
    bm = bmesh.new()
    loops = []
    for (r, z) in ((r_out, -height / 2), (r_out, height / 2), (r_in, height / 2), (r_in, -height / 2)):
        loops.append([bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z)) for k in range(seg)])
    for i in range(4):
        l0, l1 = loops[i], loops[(i + 1) % 4]
        for k in range(seg):
            bm.faces.new((l0[k], l0[(k + 1) % seg], l1[(k + 1) % seg], l1[k]))
    m = V((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
    if rot is not None:
        m = rot.to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(center) @ m, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm_to_mesh(bm)

# ---------------------------------------------------------------- weights
SEGS = {s: (np.array(J[s]), np.array(tail(s))) for s in ORDER}

def auto_weights(P, bones, gate=True, power=5.0):
    W = np.zeros((len(P), len(bones)))
    for i, s in enumerate(bones):
        a, b = SEGS[s]
        ab = b - a
        t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
        d = np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
        W[:, i] = 1.0 / np.maximum(d, 0.004) ** power
        if gate and s.startswith("Left"):
            W[P[:, 0] < -0.03, i] = 0
        if gate and s.startswith("Right"):
            W[P[:, 0] > 0.03, i] = 0
    return W

def prune(W, k=4):
    if W.shape[1] > k:
        idx = np.argsort(-W, axis=1)[:, k:]
        np.put_along_axis(W, idx, 0.0, axis=1)
    W[W < 0.01 * W.max(axis=1, keepdims=True)] = 0
    s = W.sum(axis=1, keepdims=True)
    s[s == 0] = 1
    return W / s

def smooth_weights(W, me, iters=2):
    E = np.zeros(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", E)
    E = E.reshape(-1, 2)
    deg = np.bincount(E.ravel(), minlength=len(W)).astype(float)[:, None]
    deg[deg == 0] = 1
    for _ in range(iters):
        S = np.zeros_like(W)
        np.add.at(S, E[:, 0], W[E[:, 1]])
        np.add.at(S, E[:, 1], W[E[:, 0]])
        W = 0.5 * W + 0.5 * S / deg
    return W

# ---------------------------------------------------------------- character assembly
class Char:
    def __init__(self, cid, title):
        self.id, self.title = cid, title
        self.parts = []  # dicts: me, paint, bones, W (filled later), mat, hard

    def add(self, me, paint, weights, mat=0, hard=False, smooth=0, rigid_zones=None, flatten=None):
        """weights: a bone name (rigid), or a list of bones for automatic weights."""
        self.parts.append(dict(me=me, paint=paint, weights=weights, mat=mat, hard=hard, smooth=smooth, zones=rigid_zones, flatten=flatten))

    def build(self):
        V_all, F_all, C_all, M_all, H_all, W_rows = [], [], [], [], [], []
        off = 0
        bone_index = {s: i for i, s in enumerate(ORDER)}
        for part in self.parts:
            me = part["me"]
            n = len(me.vertices)
            P = np.zeros(n * 3)
            me.vertices.foreach_get("co", P)
            P = P.reshape(-1, 3)
            if part["flatten"] is not None:  # flat soles: clamp everything below the ground
                P[:, 2] = np.maximum(P[:, 2], part["flatten"])
            Wfull = np.zeros((n, len(ORDER)))
            if isinstance(part["weights"], str):
                Wfull[:, bone_index[part["weights"]]] = 1.0
            else:
                bones = part["weights"]
                W = auto_weights(P, bones)
                W = prune(W)
                if part["smooth"]:
                    W = smooth_weights(W, me, part["smooth"])
                    W = prune(W)
                for i, s in enumerate(bones):
                    Wfull[:, bone_index[s]] = W[:, i]
                if part["zones"]:
                    for bone, test in part["zones"]:
                        mask = np.array([test(V(p)) for p in P])
                        Wfull[mask] = 0
                        Wfull[mask, bone_index[bone]] = 1.0
            dom = Wfull.argmax(axis=1)
            for poly in me.polygons:
                vs = list(poly.vertices)
                F_all.append([v + off for v in vs])
                c = V((0, 0, 0))
                for v in vs:
                    c += V(P[v])
                c /= len(vs)
                bone = ORDER[np.bincount(dom[vs]).argmax()]
                paint = part["paint"]
                col = paint(c, poly.normal.copy(), bone) if callable(paint) else paint
                C_all.append(col)
                M_all.append(part["mat"])
                H_all.append(part["hard"])
            V_all.append(P)
            W_rows.append(Wfull)
            off += n
            bpy.data.meshes.remove(me)
        P = np.vstack(V_all)
        W = np.vstack(W_rows)
        me = bpy.data.meshes.new(self.title)
        me.from_pydata([tuple(p) for p in P], [], F_all)
        me.validate(clean_customdata=False)
        me.polygons.foreach_set("material_index", M_all)
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        # Sharp edges on hard gear only, so the glTF normals split there.
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        for e in bm.edges:
            if len(e.link_faces) == 2 and any(H_all[f.index] for f in e.link_faces) and e.calc_face_angle(0) > 0.75:
                e.smooth = False
        bm.to_mesh(me)
        bm.free()
        attr = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
        flat = []
        for poly, col in zip(me.polygons, C_all):
            flat.extend(list(col) * poly.loop_total)
        attr.data.foreach_set("color_srgb", flat)
        me.color_attributes.active_color = attr
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
        for mat in materials():
            me.materials.append(mat)
        ob = bpy.data.objects.new(self.title, me)
        return ob, W

_MATS = []
def materials():
    if _MATS:
        return _MATS
    for name, rough, spec in (("Matte", 0.85, 0.3), ("Gloss", 0.25, 0.6)):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs[0], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = rough
        _MATS.append(mat)
    return _MATS

def make_armature(name):
    arm = bpy.data.armatures.new(name + "_Rig")
    ob = bpy.data.objects.new(name + "_Rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for s in ORDER:
        b = arm.edit_bones.new(PREFIX + s)
        b.head = J[s]
        t = tail(s)
        if (t - J[s]).length < 0.01:
            t = J[s] + V((0, 0, 0.02))
        b.tail = t
        eb[s] = b
    for s in ORDER:
        if PARENT[s]:
            eb[s].parent = eb[PARENT[s]]
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.display_type = 'STICK'
    return ob

def assemble(char):
    col = bpy.data.collections.new(char.title)
    bpy.context.scene.collection.children.link(col)
    rig = make_armature(char.title)
    for c in rig.users_collection:
        c.objects.unlink(rig)
    col.objects.link(rig)
    ob, W = char.build()
    col.objects.link(ob)
    ob.parent = rig
    mod = ob.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    groups = [ob.vertex_groups.new(name=PREFIX + s) for s in ORDER]
    for j, s in enumerate(ORDER):
        idx = np.nonzero(W[:, j])[0]
        for v in idx:
            groups[j].add([int(v)], float(W[v, j]), 'REPLACE')
    # Drop empty groups (glTF only needs the deforming joints; rebind uses names).
    for j, g in enumerate(groups):
        if not np.any(W[:, j]):
            ob.vertex_groups.remove(g)
    print("%s: %d verts, %d tris" % (char.title, len(ob.data.vertices), sum(len(p.vertices) - 2 for p in ob.data.polygons)))
    return rig, ob

def export_glb(rig, ob, path):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    rig.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_yup=True, export_skins=True,
              export_animations=False, export_morph=False, export_apply=False, export_materials='EXPORT')
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(export_colors=True, **kw)
    print("exported", path)

# ---------------------------------------------------------------- shared anatomy
HEAD_C = J["Head"] + V((0, -0.012, 0.105))  # cranium centre

def head_zone(p):
    """Body vertices that must follow the head rigidly (skull, face, jaw)."""
    hz = J["Head"].z
    return p.z > hz + 0.005 or (p.z > hz - 0.055 and p.y < J["Head"].y - 0.04 and abs(p.x) < 0.07)

def human_body(m, o):
    """Sculpts a human torso, limbs and (optionally) head into metaball family m.
    o: build multipliers (chest, belly, hip, arm, leg, neck) and flags."""
    g = lambda k, d=1.0: o.get(k, d)
    hips, sp, sp1, sp2, nk, hd = (J[s] for s in ("Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"))
    cw, bw, hw = g("chest"), g("belly"), g("hip")
    # pelvis, buttocks, belly, ribcage, chest, trapezius
    m.ellip(hips + V((0, 0.01, -0.035)), (0.140 * hw, 0.100, 0.100))
    for sx in (1, -1):
        m.ellip(V((0.068 * sx * hw, hips.y + 0.045, hips.z - 0.055)), (0.075, 0.068, 0.085))
    m.ellip(sp + V((0, -0.005, 0.0)), (0.132 * bw, 0.098 * bw, 0.10))
    m.ellip(sp1 + V((0, 0.0, 0.03)), (0.142 * cw, 0.100, 0.10))
    m.ellip(sp2 + V((0, 0.005, 0.03)), (0.160 * cw, 0.105 * g("chest_d"), 0.105))
    for sx in (1, -1):
        m.ellip(V((0.062 * sx, sp2.y - 0.055, sp2.z + 0.025)), (0.065 * cw, 0.045, 0.06))  # pecs
        m.ellip(V((0.07 * sx, sp2.y + 0.05, sp2.z + 0.03)), (0.07, 0.04, 0.09))          # lats/shoulder blades
    m.ellip(V((0, nk.y + 0.02, nk.z - 0.02)), (0.12 * cw, 0.055, 0.05))                  # trapezius
    m.capsule(nk + V((0, 0.005, -0.03)), hd + V((0, 0.0, 0.035)), 0.054 * g("neck"))
    # arms
    for side, sx in SIDES:
        A, F, H, Sh = J[side + "Arm"], J[side + "ForeArm"], J[side + "Hand"], J[side + "Shoulder"]
        aw = g("arm")
        m.ball(A + V((-0.012 * sx, 0.0, 0.006)), 0.058 * aw)                # deltoid
        m.capsule(A, F, 0.041 * aw)
        m.seg(A, F, (0.10, 0.044 * aw, 0.046 * aw), at=0.42)              # biceps/triceps
        m.capsule(F, H, 0.031 * aw)
        m.seg(F, H, (0.085, 0.040 * aw, 0.036 * aw), at=0.28)             # forearm mass
        hand_dir = J[side + "HandMiddle1"] - H
        m.seg(H, H + hand_dir, (0.050, 0.040, 0.016), at=0.52)             # palm (width along Y)
        m.seg(H, J[side + "HandThumb2"], (0.03, 0.02, 0.016), at=0.45)     # thenar
    # legs
    for side, sx in SIDES:
        U, Lg, Ft = J[side + "UpLeg"], J[side + "Leg"], J[side + "Foot"]
        lw = g("leg")
        m.capsule(U + V((0.0, 0.0, 0.02)), Lg, 0.066 * lw)
        m.seg(U, Lg, (0.16, 0.078 * lw, 0.080 * lw), at=0.3)                # thigh mass
        m.ball(Lg + V((0, -0.005, 0.0)), 0.050 * lw)                       # knee
        m.capsule(Lg, Ft, 0.043 * lw)
        m.seg(Lg, Ft, (0.11, 0.050 * lw, 0.046 * lw), at=0.3, front=V((0, -1, 0)))  # calf
        m.ball(Ft + V((0, 0.0, 0.0)), 0.040 * lw)                          # ankle
    if o.get("head", True):
        human_head(m, o)

def human_head(m, o):
    c = HEAD_C
    m.ellip(c, (0.077, 0.094, 0.104))                                     # cranium
    m.ellip(c + V((0, -0.028, -0.062)), (0.060, 0.070, 0.058))           # jaw
    m.ball(c + V((0, -0.080, -0.098)), 0.022)                            # chin
    m.ellip(c + V((0, -0.097, -0.012)), (0.011, 0.016, 0.024))           # nose
    m.ball(c + V((0, -0.106, -0.032)), 0.011)                            # nose tip
    for sx in (1, -1):
        m.ball(c + V((0.044 * sx, -0.068, -0.030)), 0.026)               # cheeks
        m.ellip(c + V((0.077 * sx, 0.004, -0.004)), (0.011, 0.020, 0.030))  # ears
        m.ball(c + V((0.032 * sx, -0.100, 0.010)), 0.015, neg=True)      # eye sockets
    m.ellip(c + V((0, -0.083, 0.030)), (0.058, 0.020, 0.014))            # brow ridge
    for hair in o.get("hair_mass", []):
        m.ellip(c + hair[0], hair[1])

def human_eyes(ch, iris="#3b2a1e", brow="#20180f"):
    c = HEAD_C
    for sx in (1, -1):
        e = c + V((0.032 * sx, -0.086, 0.010))
        ch.add(uv_sphere(e, (0.0125, 0.0125, 0.0125), seg=12, rings=8), srgb("#d9d4c8"), "Head", mat=1)
        ch.add(uv_sphere(e + V((0, -0.0105, 0)), (0.0062, 0.0035, 0.0062), seg=10, rings=6), srgb(iris), "Head", mat=1)
        ch.add(box(c + V((0.033 * sx, -0.096, 0.031)), (0.017, 0.004, 0.0035), rot=Matrix.Rotation(-0.12 * sx, 3, 'Y'), bevel=0.0015), srgb(brow), "Head")

def is_hair(p, front=0.055, back=-0.075, side=0.02):
    d = p - HEAD_C
    if d.z < back:
        return False
    f = max(0.0, min(1.0, -d.y / 0.09))
    thr = back + (front - back) * f
    if abs(d.x) > 0.062 and d.z < side and d.y < 0.03:  # around the ears
        return False
    return d.z > thr

def fingers(res, ch, paint, glove=1.0):
    """Finger family: one capsule per phalanx, per side; weights limited to the hand."""
    for side, sx in SIDES:
        m = Meta(res)
        for f in FINGERS:
            r = (0.0105 if f == "Thumb" else 0.0086 if f in ("Index", "Middle") else 0.0080 if f == "Ring" else 0.0072) * glove
            for i in (1, 2, 3):
                a, b = J[side + "Hand" + f + str(i)], J[side + "Hand" + f + str(i + 1)]
                rr = r * (1.0 - 0.08 * (i - 1))
                m.capsule(a, b + (b - a).normalized() * (-0.004 if i == 3 else 0.0), rr)
            if f == "Thumb":
                m.capsule(J[side + "Hand"] + V((0.012 * sx, -0.012, -0.004)), J[side + "HandThumb2"], r * 1.25)
        ch.add(m.mesh(decimate=2600), paint, hand_bones(side), smooth=1)

def shoe(m, side, length=1.0, width=1.0, height=1.0, boot=0.0):
    Ft, Tb, Te = J[side + "Foot"], J[side + "ToeBase"], J[side + "Toe_End"]
    heel = V((Ft.x, Ft.y + 0.035, 0.045 * height))
    toe = V((Te.x - 0.004 * (1 if side == "Left" else -1), Te.y - 0.012 * length, 0.036 * height))
    m.capsule(heel, mix(heel, toe, 0.55) + V((0, 0, 0.012 * height)), 0.050 * width * height)
    m.seg(heel, toe, (0.145 * length, 0.050 * width, 0.042 * height), at=0.55, front=V((0, 0, 1)))
    m.ball(toe + V((0, 0.02, 0.0)), 0.038 * width)
    if boot > 0:
        m.capsule(V((Ft.x, Ft.y + 0.01, 0.08)), V((Ft.x, Ft.y + 0.012, 0.08 + boot)), 0.056 * width)

def foot_zone(side):
    Ft = J[side + "Foot"]
    return lambda p, Ft=Ft: p.z < 0.135 and abs(p.x - Ft.x) < 0.11

def shoe_zones():
    """Shoes: everything below the ankle follows Foot (heel) / ToeBase (front)."""
    zones = []
    for side, _ in SIDES:
        Tb = J[side + "ToeBase"]
        Ft = J[side + "Foot"]
        zones.append((side + "Foot", lambda p, Ft=Ft, Tb=Tb: p.z < 0.10 and abs(p.x - Ft.x) < 0.11 and p.y > Tb.y + 0.015))
        zones.append((side + "ToeBase", lambda p, Ft=Ft, Tb=Tb: p.z < 0.10 and abs(p.x - Ft.x) < 0.11 and p.y <= Tb.y + 0.015))
    return zones

def region(p):
    """Coarse T-pose region of a body point."""
    ax = abs(p.x)
    if ax > 0.68 and p.z > 1.25:
        return "hand"
    if ax > 0.17 and p.z > 1.28:
        return "arm"
    if p.z > J["Neck"].z + 0.035 and ax < 0.13:
        return "head"
    if p.z > J["Neck"].z - 0.025 and ax < 0.09:
        return "neck"
    if p.z > 0.93:
        return "torso"
    if p.z < 0.135:
        return "foot"
    return "leg"

def arm_t(p):
    """0 at the shoulder joint, 1 at the wrist (along |x|)."""
    a, h = J["LeftArm"].x, J["LeftHand"].x
    return (abs(p.x) - a) / (h - a)

def camo(p, cols, scale=9.0):
    v = noise.noise(p * scale) + 0.5 * noise.noise(p * scale * 2.3 + V((3.1, 1.7, 0.4)))
    if v > 0.32:
        return cols[0]
    if v > -0.05:
        return cols[1]
    if v > -0.42:
        return cols[2]
    return cols[3]

# ---------------------------------------------------------------- characters
SKIN_FAIR = srgb("#dcb197")
SKIN_TAN = srgb("#c8946f")
BODY_RES = 0.0085

def build_avatar():
    """Avatar CH31: crew-neck charcoal sweater over a pale shirt, black slim
    trousers, dark leather shoes, short black hair."""
    ch = Char("avatar_ch31", "AvatarCH31")
    SWEATER, RIB, SHIRT = srgb("#2d323b"), srgb("#363b44"), srgb("#a3b2c2")
    PANTS, SHOE, SOLE, HAIR = srgb("#26282d"), srgb("#2e2823"), srgb("#5e5853"), srgb("#1c1915")
    m = Meta(BODY_RES)
    human_body(m, dict(chest=1.04, belly=1.0, arm=1.08, leg=1.06, hair_mass=[(V((0, 0.006, 0.020)), (0.081, 0.098, 0.094)), (V((0, -0.05, 0.075)), (0.06, 0.05, 0.04))]))
    for side, sx in SIDES:
        shoe(m, side, length=1.0, width=1.0)
    def paint(p, n, bone):
        r = region(p)
        if r == "head":
            return HAIR if is_hair(p, front=0.062, back=-0.06) else SKIN_TAN
        if r == "neck":
            if p.z < J["Neck"].z + 0.012:
                return SHIRT if p.y < J["Neck"].y - 0.025 else RIB
            return SKIN_TAN
        if r == "hand":
            return SKIN_TAN
        if r == "arm":
            t = arm_t(p)
            return SKIN_TAN if t > 0.985 else (RIB if t > 0.92 else SWEATER)
        if r == "torso":
            if p.z < 0.995:
                return RIB if p.z > 0.955 else PANTS
            return SWEATER
        if r == "foot" or (p.z < 0.12):
            return SOLE if p.z < 0.022 else SHOE
        return PANTS
    ch.add(m.mesh(decimate=17000), paint, BODY_BONES, smooth=2, rigid_zones=[("Head", head_zone)] + shoe_zones(), flatten=0.0)
    fingers(0.0042, ch, SKIN_TAN)
    human_eyes(ch, iris="#2a1d14", brow="#151210")
    # shirt collar peeking out of the crew neck
    nk = J["Neck"]
    for sx in (1, -1):
        ch.add(box(V((0.035 * sx, nk.y - 0.045, nk.z + 0.012)), (0.03, 0.004, 0.016), rot=Matrix.Rotation(0.5 * sx, 3, 'Z') @ Matrix.Rotation(-0.35, 3, 'X'), bevel=0.002), SHIRT, ["Neck", "Spine2"], hard=True)
    ch.add(ring(V((0, nk.y + 0.005, nk.z - 0.008)), V((0, -0.35, 1)), 0.056, 0.064, 0.022, seg=28), RIB, ["Neck", "Spine2"])
    return ch

def build_remy():
    """Remy: civilian survivor. Washed grey V-neck tee, olive cargo shorts with
    side pockets, worn grey sneakers with white soles, messy dirty-blond hair."""
    ch = Char("remy", "Remy")
    TEE, TEE_D, SHORTS, POCKET = srgb("#727578"), srgb("#5b5e61"), srgb("#6e6b51"), srgb("#615e45")
    SNEAK, SOLE, SOCK, HAIR, BELT = srgb("#8c8e90"), srgb("#cfcbc0"), srgb("#bdb9ae"), srgb("#a8895a"), srgb("#3a3530")
    m = Meta(BODY_RES)
    hair = [(V((0, 0.010, 0.022)), (0.082, 0.099, 0.096))]
    for i, (x, y, z, r) in enumerate([(0.03, -0.06, 0.088, 0.03), (-0.035, -0.045, 0.094, 0.032), (0.0, -0.01, 0.106, 0.034),
                                       (0.05, 0.02, 0.085, 0.03), (-0.05, 0.03, 0.08, 0.03), (0.0, 0.06, 0.07, 0.035),
                                       (0.06, -0.035, 0.06, 0.022), (-0.062, -0.03, 0.058, 0.022)]):
        hair.append((V((x, y, z)), (r, r * 1.1, r * 0.8)))
    human_body(m, dict(chest=1.0, belly=1.02, arm=1.0, leg=1.0, hair_mass=hair))
    # baggy shorts and tee volume
    for side, sx in SIDES:
        U, Lg = J[side + "UpLeg"], J[side + "Leg"]
        m.seg(U, Lg, (0.17, 0.088, 0.092), at=0.48)
        m.seg(U, Lg, (0.10, 0.084, 0.088), at=0.80)
        shoe(m, side, length=1.02, width=1.08, height=1.08)
    for side, sx in SIDES:
        A, F = J[side + "Arm"], J[side + "ForeArm"]
        m.seg(A, F, (0.07, 0.052, 0.052), at=0.35)  # loose sleeve
    def paint(p, n, bone):
        r = region(p)
        if r == "head":
            return HAIR if is_hair(p, front=0.045, back=-0.07) else SKIN_FAIR
        if r == "neck":
            vneck = p.y < J["Neck"].y - 0.02 and p.z < J["Neck"].z + 0.01 and p.z < J["Neck"].z - 0.075 + abs(p.x) * 1.6
            return SKIN_FAIR if not vneck and p.z > J["Neck"].z - 0.03 else (TEE_D if abs(p.z - (J["Neck"].z - 0.075 + abs(p.x) * 1.6)) < 0.008 else (TEE if vneck else SKIN_FAIR))
        if r == "hand":
            return SKIN_FAIR
        if r == "arm":
            t = arm_t(p)
            return TEE if t < 0.36 else (TEE_D if t < 0.39 else SKIN_FAIR)
        if r == "torso":
            if p.z < 0.99:
                return BELT if p.z > 0.965 else SHORTS
            # V-neck opening on the chest
            if p.y < -0.02 and p.z > J["Spine2"].z + 0.09 - 0.0 and p.z > J["Neck"].z - 0.075 + abs(p.x) * 1.6:
                return SKIN_FAIR
            return TEE
        if p.z < 0.12 or r == "foot":
            if p.z < 0.026:
                return SOLE
            return SNEAK if p.z < 0.105 else SOCK
        if p.z > 0.505:
            return SHORTS
        return SOCK if p.z < 0.14 else SKIN_FAIR
    ch.add(m.mesh(decimate=17000), paint, BODY_BONES, smooth=2, rigid_zones=[("Head", head_zone)] + shoe_zones(), flatten=0.0)
    fingers(0.0042, ch, SKIN_FAIR)
    human_eyes(ch, iris="#3d4a52", brow="#6b5333")
    # cargo pockets on the outer thighs (follow the thigh)
    for side, sx in SIDES:
        U, Lg = J[side + "UpLeg"], J[side + "Leg"]
        c = mix(U, Lg, 0.58) + V((0.085 * sx, -0.004, 0.0))
        ch.add(box(c, (0.016, 0.055, 0.06), rot=Matrix.Rotation(-0.06 * sx, 3, 'Y'), bevel=0.006), POCKET, side + "UpLeg", hard=True)
        ch.add(box(c + V((0.004 * sx, 0, 0.058)), (0.016, 0.058, 0.012), rot=Matrix.Rotation(-0.06 * sx, 3, 'Y'), bevel=0.004), SHORTS, side + "UpLeg", hard=True)
    return ch

def build_manequim():
    """Manequim: segmented test dummy - mustard shells, dusky purple ball joints,
    blank egg head. Every shell is rigid to its bone; joints blend two bones."""
    ch = Char("manequim", "Manequim")
    SHELL, SHELL_D, JOINT = srgb("#c9a136"), srgb("#ad8a2c"), srgb("#6a4d94")
    def shade(base, dark):
        return lambda p, n, b: dark if n.z < -0.55 else base
    sp = lambda s: J[s]
    # torso: pelvis, abdomen, chest shells
    ch.add(uv_sphere(J["Hips"] + V((0, 0.01, -0.03)), (0.145, 0.105, 0.085), seg=20, rings=12), shade(SHELL, SHELL_D), "Hips")
    ch.add(uv_sphere(J["Spine1"] + V((0, 0.0, -0.02)), (0.120, 0.090, 0.075), seg=20, rings=12), shade(SHELL, SHELL_D), "Spine1")
    ch.add(uv_sphere(J["Spine2"] + V((0, 0.005, 0.03)), (0.170, 0.110, 0.115), seg=22, rings=14), shade(SHELL, SHELL_D), "Spine2")
    ch.add(uv_sphere(J["Spine"] + V((0, 0, 0.0)), (0.085, 0.07, 0.06), seg=16, rings=10), JOINT, ["Spine", "Spine1", "Hips"])
    # neck + egg head
    ch.add(capsule_mesh(J["Neck"] + V((0, 0, -0.02)), J["Head"] + V((0, 0, 0.02)), 0.038), JOINT, ["Neck", "Head", "Spine2"])
    ch.add(uv_sphere(HEAD_C + V((0, -0.005, 0.005)), (0.082, 0.098, 0.118), seg=24, rings=16), shade(SHELL, SHELL), "Head")
    for side, sx in SIDES:
        A, F, H = J[side + "Arm"], J[side + "ForeArm"], J[side + "Hand"]
        ch.add(uv_sphere(A, (0.055, 0.055, 0.055), seg=16, rings=10), JOINT, [side + "Shoulder", side + "Arm", "Spine2"])
        ch.add(capsule_mesh(A + (F - A).normalized() * 0.05, F - (F - A).normalized() * 0.035, 0.043, 0.036), shade(SHELL, SHELL_D), side + "Arm")
        ch.add(uv_sphere(F, (0.036, 0.036, 0.036), seg=14, rings=8), JOINT, [side + "Arm", side + "ForeArm"])
        ch.add(capsule_mesh(F + (H - F).normalized() * 0.035, H - (H - F).normalized() * 0.03, 0.034, 0.027), shade(SHELL, SHELL_D), side + "ForeArm")
        ch.add(uv_sphere(H, (0.026, 0.026, 0.026), seg=12, rings=8), JOINT, [side + "ForeArm", side + "Hand"])
        d = J[side + "HandMiddle1"] - H
        ch.add(box(H + d * 0.55, (d.length * 0.48, 0.040, 0.015), rot=frame(d), bevel=0.008), shade(SHELL, SHELL_D), side + "Hand", hard=False)
        for f in FINGERS:
            r = 0.0105 if f == "Thumb" else 0.0082
            for i in (1, 2, 3):
                a, b = J[side + "Hand" + f + str(i)], J[side + "Hand" + f + str(i + 1)]
                ch.add(capsule_mesh(a, b - (b - a).normalized() * 0.004, r * (1 - 0.07 * i), seg=8, cap=2), SHELL if i > 1 else SHELL_D, side + "Hand" + f + str(i))
        U, Lg, Ft, Tb = J[side + "UpLeg"], J[side + "Leg"], J[side + "Foot"], J[side + "ToeBase"]
        ch.add(uv_sphere(U, (0.064, 0.064, 0.064), seg=16, rings=10), JOINT, [side + "UpLeg", "Hips"])
        ch.add(capsule_mesh(U + (Lg - U).normalized() * 0.06, Lg - (Lg - U).normalized() * 0.05, 0.066, 0.048), shade(SHELL, SHELL_D), side + "UpLeg")
        ch.add(uv_sphere(Lg, (0.046, 0.046, 0.046), seg=14, rings=10), JOINT, [side + "UpLeg", side + "Leg"])
        ch.add(capsule_mesh(Lg + (Ft - Lg).normalized() * 0.05, Ft - (Ft - Lg).normalized() * 0.045, 0.046, 0.034), shade(SHELL, SHELL_D), side + "Leg")
        ch.add(uv_sphere(Ft, (0.035, 0.035, 0.035), seg=12, rings=8), JOINT, [side + "Leg", side + "Foot"])
        heel = V((Ft.x, Ft.y + 0.03, 0.04))
        # rounded heel shell and toe cap, flat soles (clamped at the ground)
        ch.add(uv_sphere(V((Ft.x, (heel.y + Tb.y) / 2 + 0.01, 0.03)), (0.047, (heel.y - Tb.y) / 2 + 0.035, 0.055), seg=18, rings=10), shade(SHELL, SHELL_D), side + "Foot", flatten=0.0)
        Te = J[side + "Toe_End"]
        ch.add(uv_sphere(V((Tb.x, (Tb.y + Te.y) / 2, 0.018)), (0.045, (Tb.y - Te.y) / 2 + 0.02, 0.036), seg=16, rings=8), shade(SHELL, SHELL_D), side + "ToeBase", flatten=0.0)
    return ch

def build_pato():
    """Pato Tatico: elite duck operator. Woodland camo fatigues with rolled
    sleeves, orange forearms, black gloves, plate carrier with pouches and
    patch, belt, knee pads, tan boots; duck head with cap, headset and a scowl."""
    ch = Char("pato", "PatoTatico")
    CAMO = [srgb("#4f523b"), srgb("#6d6c49"), srgb("#877c5b"), srgb("#36362d")]
    FEATHER, FEATHER_D, BILL, BILL_D = srgb("#ece8dc"), srgb("#d3cdbf"), srgb("#e3a03a"), srgb("#c98a2c")
    ARM, GLOVE, CUFF = srgb("#da8a3a"), srgb("#232324"), srgb("#55554a")
    VEST, VEST_D, STRAP = srgb("#4c4c41"), srgb("#3b3b33"), srgb("#30302a")
    BOOT, SOLE, LACE, PAD = srgb("#a68a62"), srgb("#4e4031"), srgb("#705b3e"), srgb("#2e2e30")
    CAP, HEADSET, EYE, BROW, PATCH = srgb("#1e1e20"), srgb("#28292c"), srgb("#0c0c0d"), srgb("#1a1714"), srgb("#c49a2a")
    m = Meta(BODY_RES)
    human_body(m, dict(chest=1.10, chest_d=1.05, belly=1.06, arm=1.12, leg=1.10, neck=1.15, head=False))
    c = HEAD_C + V((0, -0.005, 0.012))
    m.ellip(c, (0.112, 0.118, 0.118))                       # big round duck head
    m.ellip(c + V((0, 0.025, -0.07)), (0.085, 0.09, 0.07))   # cheeks into the neck
    for side, sx in SIDES:
        U, Lg = J[side + "UpLeg"], J[side + "Leg"]
        m.seg(U, Lg, (0.17, 0.088, 0.09), at=0.5)            # loose fatigues
        shoe(m, side, length=1.08, width=1.18, height=1.15, boot=0.11)
        A, F = J[side + "Arm"], J[side + "ForeArm"]
        m.seg(A, F, (0.06, 0.055, 0.055), at=0.25)
        m.seg(A, F, (0.03, 0.058, 0.058), at=0.48)           # rolled sleeve cuff
    def paint(p, n, bone):
        r = region(p)
        d = p - c
        if p.z > J["Neck"].z + 0.03 and abs(p.x) < 0.14 and r in ("head", "neck", "torso"):
            return FEATHER_D if d.z < -0.08 else FEATHER
        if r == "neck":
            return CAMO[3] if p.z < J["Neck"].z + 0.03 else FEATHER
        if r == "hand":
            return GLOVE
        if r == "arm":
            t = arm_t(p)
            if t > 0.93:
                return GLOVE
            if 0.22 < t < 0.33:
                return CUFF
            return camo(p, CAMO) if t <= 0.22 else ARM
        if r == "torso":
            return camo(p, CAMO)
        if p.z < 0.205 or r == "foot":
            if p.z < 0.03:
                return SOLE
            return LACE if (p.y < J["LeftFoot"].y - 0.04 and abs(abs(p.x) - abs(J["LeftFoot"].x)) < 0.02 and p.z > 0.06 and int(p.z * 120) % 2 == 0) else BOOT
        return camo(p, CAMO)
    ch.add(m.mesh(decimate=17000), paint, BODY_BONES, smooth=2, rigid_zones=[("Head", head_zone)] + shoe_zones(), flatten=0.0)
    fingers(0.0042, ch, GLOVE, glove=1.15)
    # bill: upper and lower mandible, slightly open, scowling
    bill_c = c + V((0, -0.118, -0.03))
    ch.add(uv_sphere(bill_c + V((0, -0.025, 0.004)), (0.060, 0.062, 0.018), seg=20, rings=10), lambda p, n, b: BILL if n.z > -0.3 else BILL_D, "Head", mat=1)
    ch.add(uv_sphere(bill_c + V((0, -0.012, -0.020)), (0.050, 0.050, 0.013), seg=18, rings=8), BILL_D, "Head", mat=1)
    for sx in (1, -1):
        e = c + V((0.050 * sx, -0.100, 0.028))
        ch.add(uv_sphere(e, (0.016, 0.009, 0.019), seg=12, rings=8), EYE, "Head", mat=1)
        brow = box(e + V((0.002 * sx, -0.007, 0.024)), (0.026, 0.006, 0.0065), rot=Matrix.Rotation(0.38 * sx, 3, 'Y'), bevel=0.002)
        ch.add(brow, BROW, "Head", hard=True)
    # cap: crown + brim, rotated a touch back
    cap_c = c + V((0, 0.006, 0.05))
    ch.add(uv_sphere(cap_c, (0.118, 0.124, 0.085), seg=24, rings=14), lambda p, n, b: CAP if p.z > cap_c.z - 0.002 else CAP, "Head",
           hard=False)
    ch.add(box(cap_c + V((0, -0.135, -0.004)), (0.085, 0.06, 0.006), rot=Matrix.Rotation(0.12, 3, 'X'), bevel=0.004, cuts=2), CAP, "Head", hard=True)
    ch.add(box(cap_c + V((0, -0.115, 0.06)), (0.022, 0.003, 0.014), rot=Matrix.Rotation(-0.55, 3, 'X'), bevel=0.0015), PATCH, "Head", hard=True)
    # headset: ear cups, band over the cap, boom mic
    for sx in (1, -1):
        cup = c + V((0.118 * sx, 0.004, -0.004))
        ch.add(cylinder(cup - V((0.012 * sx, 0, 0)), cup + V((0.022 * sx, 0, 0)), 0.042, 0.036, seg=18), HEADSET, "Head", hard=True)
    ch.add(ring(c + V((0, 0.004, 0.055)), V((0, 1, 0)), 0.122, 0.132, 0.022, seg=32), HEADSET, "Head", hard=True)
    ch.add(capsule_mesh(c + V((0.13, -0.01, -0.02)), c + V((0.07, -0.12, -0.06)), 0.005, seg=8, cap=2), HEADSET, "Head")
    # plate carrier: front and back plates, cummerbund, shoulder straps, pouches
    s1, s2 = J["Spine1"], J["Spine2"]
    vb = ["Spine", "Spine1", "Spine2"]
    ch.add(box(V((0, s2.y - 0.128, s2.z - 0.04)), (0.145, 0.022, 0.15), rot=Matrix.Rotation(0.05, 3, 'X'), bevel=0.012, cuts=2), VEST, vb, hard=True, smooth=2)
    ch.add(box(V((0, s2.y + 0.128, s2.z - 0.02)), (0.145, 0.022, 0.16), rot=Matrix.Rotation(-0.05, 3, 'X'), bevel=0.012, cuts=2), VEST, vb, hard=True, smooth=2)
    ch.add(ring(V((0, s1.y + 0.004, s1.z - 0.05)), V((0, 0, 1)), 0.150, 0.172, 0.11, seg=28,
                rot=Matrix.Diagonal((1.0, 0.82, 1.0))), VEST_D, vb, smooth=2)
    for sx in (1, -1):
        ch.add(box(V((0.105 * sx, s2.y, s2.z + 0.11)), (0.03, 0.135, 0.012), bevel=0.004, cuts=2), STRAP, ["Spine2", ("Left" if sx > 0 else "Right") + "Shoulder"], hard=True, smooth=1)
    for i, x in enumerate((-0.085, 0.0, 0.085)):
        ch.add(box(V((x, s2.y - 0.165, s2.z - 0.105)), (0.036, 0.022, 0.06), bevel=0.007), VEST_D, vb, hard=True, smooth=1)
        ch.add(box(V((x, s2.y - 0.17, s2.z - 0.043)), (0.038, 0.024, 0.008), bevel=0.003), STRAP, vb, hard=True, smooth=1)
    ch.add(box(V((0.075, s2.y - 0.152, s2.z + 0.05)), (0.032, 0.004, 0.02), bevel=0.002), PATCH, vb, hard=True, smooth=1)
    ch.add(box(V((-0.07, s2.y - 0.152, s2.z + 0.055)), (0.035, 0.012, 0.03), bevel=0.004), VEST_D, vb, hard=True, smooth=1)  # radio pouch
    # belt with buckle, thigh holster, knee pads
    hp = J["Hips"]
    ch.add(ring(V((0, hp.y + 0.004, hp.z + 0.02)), V((0, 0, 1)), 0.145, 0.158, 0.045, seg=28, rot=Matrix.Diagonal((1.0, 0.80, 1.0))), STRAP, ["Hips", "Spine"], smooth=1)
    ch.add(box(V((0, hp.y - 0.13, hp.z + 0.02)), (0.026, 0.008, 0.02), bevel=0.003), srgb("#5e5446"), ["Hips", "Spine"], hard=True)
    U, Lg = J["RightUpLeg"], J["RightLeg"]
    ch.add(box(mix(U, Lg, 0.32) + V((-0.098, -0.01, 0)), (0.02, 0.045, 0.075), rot=Matrix.Rotation(0.06, 3, 'Y'), bevel=0.008), VEST_D, "RightUpLeg", hard=True)
    for side, sx in SIDES:
        Lg = J[side + "Leg"]
        ch.add(box(Lg + V((0.0, -0.06, 0.0)), (0.048, 0.018, 0.058), bevel=0.012, cuts=1), PAD, side + "Leg", hard=True)
    return ch

BUILDERS = [("avatar_ch31", build_avatar), ("remy", build_remy), ("manequim", build_manequim), ("pato", build_pato)]

# ---------------------------------------------------------------- previews
def render(rigs, path, posed=False):
    sc = bpy.context.scene
    for o in [o for o in sc.objects if o.type in ('CAMERA', 'LIGHT')]:
        bpy.data.objects.remove(o)
    n = len(rigs)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(2.2, 1.9 * n)
    cam.location = (0, -10, 0.95)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    for ct in ('VERTEX', 'ATTRIBUTE'):
        try:
            sc.display.shading.color_type = ct
            break
        except TypeError:
            pass
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = False
    sc.render.resolution_x = 520 * n
    sc.render.resolution_y = 1000
    sc.render.film_transparent = False
    views = [("front", 0.0), ("three", math.radians(35)), ("back", math.pi)]
    for vname, ang in views:
        for i, rig in enumerate(rigs):
            rig.location = ((i - (n - 1) / 2) * 1.9, 0, 0)
            rig.rotation_euler = (0, 0, ang)
            if posed:
                pose(rig)
        sc.render.filepath = path.replace(".png", "_%s%s.png" % (vname, "_posed" if posed else ""))
        bpy.ops.render.render(write_still=True)
    for rig in rigs:
        rig.rotation_euler = (0, 0, 0)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix()

def pose(rig):
    def rot(s, axis, deg):
        pb = rig.pose.bones[PREFIX + s]
        local = rig.data.bones[PREFIX + s].matrix_local.to_3x3().inverted() @ V(axis)
        pb.matrix_basis = Matrix.Rotation(math.radians(deg), 4, local)
    rot("LeftArm", (0, 1, 0), 65)
    rot("RightArm", (0, 1, 0), -50)
    rot("RightForeArm", (0, 0, 1), 70)
    rot("LeftUpLeg", (1, 0, 0), 40)
    rot("LeftLeg", (1, 0, 0), -70)
    rot("Head", (0, 0, 1), 30)
    rot("Spine1", (0, 1, 0), 12)
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            rot("RightHand" + f + str(i), (0, 1, 0), 60)

# ---------------------------------------------------------------- main
def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    os.makedirs(OUT_DIR, exist_ok=True)
    built = []
    for cid, fn in BUILDERS:
        if ONLY and cid not in ONLY:
            continue
        ch = fn()
        rig, ob = assemble(ch)
        if EXPORT:
            export_glb(rig, ob, os.path.join(OUT_DIR, cid + ".glb"))
        built.append(rig)
    sc_col = bpy.data.collections.get("_scratch")
    if sc_col:
        bpy.data.collections.remove(sc_col)
    if RENDER:
        os.makedirs(RENDER, exist_ok=True)
        render(built, os.path.join(RENDER, "chars.png"))
        render(built, os.path.join(RENDER, "chars.png"), posed=True)
    for i, rig in enumerate(built):
        rig.location = ((i - (len(built) - 1) / 2) * 1.2, 0, 0)
    if EXPORT and not ONLY:
        bpy.ops.wm.save_as_mainfile(filepath=BLEND)
        print("saved", BLEND)

main()
