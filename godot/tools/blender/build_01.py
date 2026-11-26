"""Builds character "01": a slender, flat-shaded low-poly human (slate blue).

    blender -b -P godot/tools/blender/build_01.py -- [--render=DIR] [--no-export] [--tris=N]

Needs the MPFB extension (MakeHuman for Blender, CC0 assets) enabled in the
user's Blender (installed from extensions.blender.org); do NOT pass
--factory-startup or MPFB won't load.

Steps:
  1. MPFB human with real anatomy (male, slim, a bit tall): correct neck,
     shoulders, face, hands and feet instead of hand-tuned primitives;
  2. MPFB's built-in "mixamo" rig with its authored skin weights (smooth
     shoulders/elbows, fingers), bones renamed mixamorig:X -> mixamorig_X;
  3. targets baked, helper geometry removed, eye sockets closed;
  4. symmetric collapse decimation to ~N tris + flat shading = faceted
     low-poly "base mesh" look of the reference picture.
Output: assets/personagens/01/01.glb (armature + mesh, MakeHuman A-pose rest: arms
turn less to reach idle/aim poses than from a T-pose, so shoulders deform less).
Godot side (Mixamo skeleton + retarget like the Manequim):
  godot --headless --path godot --import
  godot --headless --path godot --script res://tools/characters/build_mannequin_model.gd -- --id=01
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector as V, Matrix
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(GODOT, "assets", "personagens", "01", "01.glb")
SKIN_PNG = os.path.join(GODOT, "assets", "personagens", "01", "pele.png")
SKIN_SIZE = 2048
# Linear colours: sclera, iris (dark brown; at this size it also reads as the pupil).
EYE_COLORS = [("Olho01_Branco", (0.62, 0.6, 0.57, 1.0)), ("Olho01_Iris", (0.035, 0.016, 0.007, 1.0))]

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def _arg(name, default=None):
    for a in ARGS:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default
RENDER = _arg("--render")
EXPORT = "--no-export" not in ARGS
TRIS = int(_arg("--tris", "6000"))

# Slim adult male, slightly tall (MakeHuman macro sliders, 0..1).
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.4, "weight": 0.3, "proportions": 0.5, "height": 0.6,
         "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.33, "caucasian": 0.34, "african": 0.33}}
# Narrow, sloped shoulders like the reference (MakeHuman targets, 0..1),
# applied before the rig is fitted so the joints follow the new shape.
SHAPE = {
    "torso/measure-shoulder-dist-decr": 0.9,
    "torso/torso-vshape-decr": 0.6,
    "torso/torso-muscle-dorsi-decr": 0.6,
    "torso/torso-muscle-pectoral-decr": 0.6,
    "arms/l-upperarm-shoulder-muscle-decr": 0.4,
    "arms/r-upperarm-shoulder-muscle-decr": 0.4,
    # Slightly thicker arms (upper arm and forearm), without widening shoulders.
    "arms/measure-upperarm-circ-incr": 1.0,
    "arms/l-upperarm-scale-horiz-incr": 0.5,
    "arms/r-upperarm-scale-horiz-incr": 0.5,
    "arms/l-upperarm-scale-depth-incr": 0.5,
    "arms/r-upperarm-scale-depth-incr": 0.5,
    "arms/l-lowerarm-scale-horiz-incr": 0.7,
    "arms/r-lowerarm-scale-horiz-incr": 0.7,
    "arms/l-lowerarm-scale-depth-incr": 0.7,
    "arms/r-lowerarm-scale-depth-incr": 0.7,
}

try:
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.targetservice import TargetService
    import bl_ext.blender_org.mpfb as _mpfb
    TARGETS = os.path.join(os.path.dirname(_mpfb.__file__), "data", "targets")
except ImportError:
    sys.exit("MPFB nao esta ativo: instale 'MPFB' em extensions.blender.org e rode sem --factory-startup")

def ctx(ob):
    return bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob])

def smooth_weights(ob, iters=2, keep=4):
    """Laplacian-smooth every vertex group, keep the 4 strongest, normalize."""
    me, groups = ob.data, list(ob.vertex_groups)
    W = np.zeros((len(me.vertices), len(groups)))
    for v in me.vertices:
        for e in v.groups:
            W[v.index, e.group] = e.weight
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
    if W.shape[1] > keep:
        idx = np.argsort(-W, axis=1)[:, keep:]
        np.put_along_axis(W, idx, 0.0, axis=1)
    W[W < 0.01] = 0
    total = W.sum(axis=1, keepdims=True)
    total[total == 0] = 1
    W /= total
    for j, g in enumerate(groups):
        g.remove(list(range(len(me.vertices))))
        for i in np.nonzero(W[:, j])[0]:
            g.add([int(i)], float(W[i, j]), 'REPLACE')

def eye_spheres(body):
    """Centre and radius of each eye from MPFB's eye helper geometry."""
    out = []
    for side in ("l", "r"):
        g = body.vertex_groups.get("helper-%s-eye" % side)
        if g is None:
            continue
        pts = [body.matrix_world @ v.co for v in body.data.vertices if any(e.group == g.index and e.weight > 0.5 for e in v.groups)]
        if not pts:
            continue
        c = sum(pts, V()) / len(pts)
        r = max((p - c).length for p in pts)
        out.append((c, r))
    print("01: olhos", [(tuple(round(x, 3) for x in c), round(r, 4)) for c, r in out])
    return out

def add_eyeballs(body, eyes, rig):
    """Low-poly eyeballs (white, dark brown iris) rigid on the Head."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    head_layer = bm.verts.layers.deform.verify()
    head_index = body.vertex_groups["mixamorig:Head"].index
    inv = body.matrix_world.inverted()
    for c, r in eyes:
        res = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=r * 0.97)
        verts = res["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=V(), matrix=Matrix.Rotation(math.radians(90), 3, 'X'))
        bmesh.ops.translate(bm, verts=verts, vec=inv @ c)
        local_c = inv @ c
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            d = (f.calc_center_median() - local_c).normalized()
            front = -d.y  # eyes look along -Y
            f.material_index = 2 if front > 0.95 else 1
            f.smooth = False
        for v in verts:
            v[head_layer].clear()
            v[head_layer][head_index] = 1.0
    bm.to_mesh(body.data)
    bm.free()

def bake_skin(body):
    """Bakes MPFB's procedural v2 skin (base colour only) to pele.png."""
    from bl_ext.blender_org.mpfb.services.materialservice import MaterialService
    mat = MaterialService.create_v2_skin_material("SkinBake", body)
    img = bpy.data.images.new("01_pele", SKIN_SIZE, SKIN_SIZE)
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    bake = sc.render.bake
    bake.use_pass_direct = bake.use_pass_indirect = False
    bake.use_pass_color = True
    bake.margin = 16
    for o in bpy.context.scene.objects:
        o.select_set(o == body)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.bake(type='DIFFUSE')
    os.makedirs(os.path.dirname(SKIN_PNG), exist_ok=True)
    img.filepath_raw = SKIN_PNG
    img.file_format = 'PNG'
    img.save()
    print("01: pele assada ->", SKIN_PNG)
    return img

NECK_BASE_Z = 1.555  # base of the neck (MPFB puts the Neck joint under the skull)

def lower_neck_joint(rig, body):
    """Moves the Neck joint down to the base of the neck, like Ch31's, and hands
    the neck skin from Spine2 to Neck. With MPFB's high joint the whole neck
    followed the chest and bent only under the skull: in game the head stuck
    forward and the upper back looked hunched."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    neck = eb["mixamorig:Neck"]
    inv = rig.matrix_world.inverted()
    old_z = (rig.matrix_world @ neck.head).z
    neck.head = inv @ V((0.0, (rig.matrix_world @ neck.head).y + 0.004, NECK_BASE_Z))
    # Spine joints on a straight line Hips -> Neck. MPFB's zig-zag (Spine2 5.6 cm
    # behind Spine1) made Ch31's straight-spine clips fold the torso there:
    # chest pushed out, upper back rounded.
    hips = rig.matrix_world @ eb["mixamorig:Hips"].head
    top = rig.matrix_world @ neck.head
    for n in ("Spine", "Spine1", "Spine2"):
        b = eb["mixamorig:" + n]
        p = rig.matrix_world @ b.head
        t = (p.z - hips.z) / (top.z - hips.z)
        b.head = inv @ V((0.0, hips.y + (top.y - hips.y) * t, p.z))
    bpy.ops.object.mode_set(mode='OBJECT')
    sp2 = body.vertex_groups["mixamorig:Spine2"]
    nk = body.vertex_groups["mixamorig:Neck"]
    moved = 0
    for v in body.data.vertices:
        p = body.matrix_world @ v.co
        if p.z < NECK_BASE_Z - 0.03 or math.hypot(p.x, p.y + 0.01) > 0.085:
            continue
        w = next((e.weight for e in v.groups if e.group == sp2.index), 0.0)
        if w <= 0.0:
            continue
        t = min(1.0, max(0.0, (p.z - (NECK_BASE_Z - 0.03)) / (old_z - NECK_BASE_Z + 0.03)))
        t = t * t * (3 - 2 * t)
        sp2.add([v.index], w * (1 - t), 'REPLACE')
        nk.add([v.index], w * t, 'ADD')
        moved += 1
    print("01: pescoco %.3f -> %.3f m, %d vertices repassados ao Neck" % (old_z, NECK_BASE_Z, moved))

def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    body = HumanService.create_human(macro_detail_dict=MACRO)
    for target, weight in SHAPE.items():
        path = os.path.join(TARGETS, target + ".target.gz")
        TargetService.load_target(body, path, weight=weight, name=os.path.basename(target))
    bpy.context.view_layer.update()
    rig = HumanService.add_builtin_rig(body, "mixamo")
    body.name, rig.name = "01", "01_Rig"
    bpy.context.view_layer.objects.active = body
    # Bake targets (shape keys) and drop helper geometry (mask modifier).
    if body.data.shape_keys:
        with ctx(body):
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    eyes = eye_spheres(body)
    for mod in list(body.modifiers):
        if mod.type != 'ARMATURE':
            with ctx(body):
                bpy.ops.object.modifier_apply(modifier=mod.name)
    # Only the deform-bone groups stay.
    bone_names = {b.name for b in rig.data.bones}
    for g in list(body.vertex_groups):
        if g.name not in bone_names:
            body.vertex_groups.remove(g)
    lower_neck_joint(rig, body)
    # Drop loose helper leftovers (eye sockets stay open: eyeballs go in later).
    bm = bmesh.new()
    bm.from_mesh(body.data)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(body.data)
    bm.free()
    # Human skin: MPFB's procedural skin baked on the hi-res body, in the
    # standard MakeHuman UV layout (clothing skins can be painted on it later).
    skin_img = bake_skin(body)
    # Hi-res copy: its MakeHuman weights are re-projected after decimation
    # (collapse decimation averages weights badly at shoulders and armpits).
    src = body.copy()
    src.data = body.data.copy()
    src.modifiers.clear()
    bpy.context.scene.collection.objects.link(src)
    # Faceted low poly: symmetric collapse decimation, then flat shading.
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    dec = body.modifiers.new("Decimate", 'DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = min(1.0, TRIS / tris)
    dec.use_symmetry = True
    dec.symmetry_axis = 'X'
    with ctx(body):
        bpy.ops.object.modifier_move_to_index(modifier=dec.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dec.name)
    for p in body.data.polygons:
        p.use_smooth = False
    dt = body.modifiers.new("Weights", 'DATA_TRANSFER')
    dt.object = src
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    with ctx(body):
        bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dt.name)
    bpy.data.objects.remove(src)
    # Light smoothing, at most 4 bones per vertex, normalized (glTF/Godot skin).
    smooth_weights(body)
    # Materials: 0 skin texture, then sclera / iris / pupil of the eyeballs.
    body.data.materials.clear()
    mat = bpy.data.materials.new("Pele01")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = skin_img
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.62
    body.data.materials.append(mat)
    for name, color in EYE_COLORS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = color
        m.diffuse_color = color
        body.data.materials.append(m)
    add_eyeballs(body, eyes, rig)
    # Bone names as Godot expects them (vertex groups follow the rename).
    for b in rig.data.bones:
        b.name = b.name.replace("mixamorig:", "mixamorig_")
    for g in body.vertex_groups:
        g.name = g.name.replace("mixamorig:", "mixamorig_")
    top = max((body.matrix_world @ v.co).z for v in body.data.vertices)
    print("01: %d verts, %d tris, %d grupos, topo %.3f m" % (len(body.data.vertices), sum(len(p.vertices) - 2 for p in body.data.polygons), len(body.vertex_groups), top))
    return rig, body

def export_glb(rig, ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    rig.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_morph=False,
                              export_apply=False, export_materials='EXPORT',
                              export_image_format='NONE')  # Godot uses pele.png directly
    print("exported", path)

def render(dirpath):
    os.makedirs(dirpath, exist_ok=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = 'BLENDER_EEVEE'
    except TypeError:
        sc.render.engine = 'BLENDER_WORKBENCH'
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sc.collection.objects.link(sun)
    sc.render.resolution_x, sc.render.resolution_y = 600, 900
    world = bpy.data.worlds.new("W")
    sc.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (0.75, 0.75, 0.75, 1)
    bg.inputs[1].default_value = 0.6
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.lens = 70
    views = {"front": (0, -1, 0.08), "three": (0.55, -0.85, 0.12), "face": (0.35, -1, 0.05),
             "profile": (1, -0.05, 0.03), "hand": (0.2, -1, 0.3), "side": (1, 0, 0.05)}
    for name, d in views.items():
        d = V(d).normalized()
        target, dist = V((0, 0, 0.93)), 4.8
        if name in ("face", "profile"):
            target, dist = V((0, -0.02, 1.62)), 1.0
        if name == "hand":
            target, dist = V((0.5, -0.15, 1.15)), 0.8
        cam.location = target + d * dist
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(dirpath, "01_%s.png" % name)
        bpy.ops.render.render(write_still=True)

rig, ob = build()
if EXPORT:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    export_glb(rig, ob, OUT)
if RENDER:
    render(RENDER)
