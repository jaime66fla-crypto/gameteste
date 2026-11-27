"""Builds character "02": a realistic MakeHuman human with hair and clothes.

    blender -b -P godot/tools/blender/build_02.py -- [--render=DIR] [--no-export] [--save=FILE.blend]

Needs the MPFB extension (MakeHuman for Blender) enabled in the user's Blender
and the MakeHuman system asset pack (makehuman_system_assets_cc0.zip, CC0)
unpacked in MPFB's user data folder (%APPDATA%/Blender Foundation/Blender/<v>/mpfb/data).
Do NOT pass --factory-startup or MPFB won't load.

Unlike 01 (faceted low poly, baked procedural skin, own clothes), 02 keeps
MakeHuman's smooth base mesh and its CC0 assets as they come: skin texture,
eyes, eyebrows, eyelashes, short dark hair, dark jacket + jeans, black boots.
Steps:
  1. MPFB human + built-in "mixamo" rig (authored weights);
  2. assets fitted and rigged by MPFB ("GAMEENGINE" PBR materials, which
     glTF exports as plain textures); body faces under the clothes deleted;
  3. same neck/spine joint fix as 01 (Ch31 clips need a straight spine and a
     neck joint at the neck base);
  4. everything joined into one skinned mesh (one draw call per material),
     at most 4 normalized weights per vertex, bones mixamorig:X -> mixamorig_X.
Output: assets/personagens/02/02.glb (textures embedded).
Godot side (Mixamo skeleton + retarget, like 01):
  godot --headless --path godot --import
  godot --headless --path godot --script res://tools/characters/build_mannequin_model.gd -- --id=02
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector as V
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(GODOT, "assets", "personagens", "02", "02.glb")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def _arg(name, default=None):
    for a in ARGS:
        if a.startswith(name + "="):
            return a.split("=", 1)[1]
    return default
RENDER = _arg("--render")
EXPORT = "--no-export" not in ARGS
SAVE = _arg("--save")

# Adult male, average build, a bit tall (MakeHuman macro sliders, 0..1).
MACRO = {"gender": 1.0, "age": 0.5, "muscle": 0.55, "weight": 0.45, "proportions": 0.5, "height": 0.6,
         "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.2, "caucasian": 0.5, "african": 0.3}}
SKIN = "skins/young_caucasian_male/young_caucasian_male.mhmat"
# (asset type, mhclo relative to the asset data folder)
ASSETS = [
    ("Eyes", "eyes/low-poly/low-poly.mhclo"),
    ("Eyebrows", "eyebrows/eyebrow001/eyebrow001.mhclo"),
    ("Eyelashes", "eyelashes/eyelashes01/eyelashes01.mhclo"),
    ("Hair", "hair/short04/short04.mhclo"),
    ("Clothes", "clothes/male_casualsuit05/male_casualsuit05.mhclo"),
    ("Clothes", "clothes/shoes03/shoes03.mhclo"),
]

try:
    from bl_ext.blender_org.mpfb.services.humanservice import HumanService
    from bl_ext.blender_org.mpfb.services.locationservice import LocationService
except ImportError:
    sys.exit("MPFB nao esta ativo: instale 'MPFB' em extensions.blender.org e rode sem --factory-startup")

def asset_path(rel):
    for root in (LocationService.get_user_data(), LocationService.get_mpfb_data()):
        p = os.path.join(root, rel)
        if os.path.exists(p):
            return p
    sys.exit("02: asset do MakeHuman nao encontrado: %s (instale makehuman_system_assets_cc0.zip na pasta de dados do MPFB)" % rel)

def ctx(ob):
    return bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob])

def bake_mesh(ob):
    """Shape keys and every modifier but the armature become real geometry
    (MPFB's helper mask, the clothes' delete-under masks, subdivision)."""
    if ob.data.shape_keys:
        with ctx(ob):
            bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for mod in list(ob.modifiers):
        if mod.type != 'ARMATURE':
            with ctx(ob):
                bpy.ops.object.modifier_apply(modifier=mod.name)

def limit_weights(ob, keep=4):
    """At most `keep` bones per vertex, normalized (glTF/Godot skin).
    MPFB weights are not normalized."""
    me, groups = ob.data, list(ob.vertex_groups)
    W = np.zeros((len(me.vertices), len(groups)))
    for v in me.vertices:
        for e in v.groups:
            W[v.index, e.group] = e.weight
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

def neck_base_z(body):
    """Base of the neck: just above the top of the shoulders' collarbone line,
    measured on the body (MPFB puts the Neck joint under the skull)."""
    g = body.vertex_groups.get("mixamorig:Neck")
    sp2 = body.vertex_groups.get("mixamorig:Spine2")
    # Lowest vertex near the spine axis that the Neck bone owns more than
    # Spine2: where the neck meets the chest (MPFB weights are not normalized).
    best = None
    for v in body.data.vertices:
        p = body.matrix_world @ v.co
        if math.hypot(p.x, p.y + 0.01) > 0.08:
            continue
        wn = next((e.weight for e in v.groups if e.group == g.index), 0.0)
        ws = next((e.weight for e in v.groups if e.group == sp2.index), 0.0)
        if wn > 0.0 and wn >= ws:
            best = p.z if best is None else min(best, p.z)
    print("02: base do pescoco medida %s" % best)
    return best if best is not None else 1.555

def fix_spine_and_neck(rig, meshes, base_z):
    """As in 01 (build_01.py lower_neck_joint): Neck joint moved down to the
    base of the neck and Spine..Spine2 put on a straight line Hips -> Neck,
    then the neck skin handed from Spine2 to Neck on every mesh (collar too)."""
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    neck = eb["mixamorig:Neck"]
    inv = rig.matrix_world.inverted()
    old_z = (rig.matrix_world @ neck.head).z
    neck.head = inv @ V((0.0, (rig.matrix_world @ neck.head).y + 0.004, base_z))
    hips = rig.matrix_world @ eb["mixamorig:Hips"].head
    top = rig.matrix_world @ neck.head
    for n in ("Spine", "Spine1", "Spine2"):
        b = eb["mixamorig:" + n]
        p = rig.matrix_world @ b.head
        t = (p.z - hips.z) / (top.z - hips.z)
        b.head = inv @ V((0.0, hips.y + (top.y - hips.y) * t, p.z))
    bpy.ops.object.mode_set(mode='OBJECT')
    moved = 0
    for ob in meshes:
        sp2 = ob.vertex_groups.get("mixamorig:Spine2")
        nk = ob.vertex_groups.get("mixamorig:Neck")
        if sp2 is None:
            continue
        if nk is None:
            nk = ob.vertex_groups.new(name="mixamorig:Neck")
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            if p.z < base_z - 0.03 or math.hypot(p.x, p.y + 0.01) > 0.11:
                continue
            w = next((e.weight for e in v.groups if e.group == sp2.index), 0.0)
            if w <= 0.0:
                continue
            t = min(1.0, max(0.0, (p.z - (base_z - 0.03)) / (old_z - base_z + 0.03)))
            t = t * t * (3 - 2 * t)
            sp2.add([v.index], w * (1 - t), 'REPLACE')
            nk.add([v.index], w * t, 'ADD')
            moved += 1
    print("02: pescoco %.3f -> %.3f m, %d vertices repassados ao Neck" % (old_z, base_z, moved))

def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    body = HumanService.create_human(macro_detail_dict=MACRO)
    bpy.context.view_layer.update()
    rig = HumanService.add_builtin_rig(body, "mixamo")
    HumanService.set_character_skin(asset_path(SKIN), body, skin_type="GAMEENGINE")
    parts = []
    for kind, rel in ASSETS:
        ob = HumanService.add_mhclo_asset(asset_path(rel), body, asset_type=kind, subdiv_levels=0, material_type="GAMEENGINE")
        name = os.path.splitext(os.path.basename(rel))[0]
        ob.name = "02_" + name
        # Material names say what the surface is; Godot (build_mannequin_model.gd
        # --id=02) keeps alpha only on 02_Hair / 02_Eyebrows / 02_Eyelashes.
        for slot in ob.material_slots:
            if slot.material:
                slot.material.name = "02_%s" % kind + ("_" + name if kind == "Clothes" else "")
        parts.append(ob)
    for slot in body.material_slots:
        if slot.material:
            slot.material.name = "02_Body"
    body.name, rig.name = "02", "02_Rig"
    bpy.context.view_layer.update()
    for ob in [body] + parts:
        bake_mesh(ob)
    # Drop loose helper leftovers on the body.
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(body.data)
    bm.free()
    base_z = neck_base_z(body)
    fix_spine_and_neck(rig, [body] + parts, base_z)
    # One skinned mesh: body + eyes + brows + lashes + hair + clothes.
    for o in bpy.context.scene.objects:
        o.select_set(o in parts or o == body)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    for p in body.data.polygons:
        p.use_smooth = True
    bone_names = {b.name for b in rig.data.bones}
    for g in list(body.vertex_groups):
        if g.name not in bone_names:
            body.vertex_groups.remove(g)
    limit_weights(body)
    for b in rig.data.bones:
        b.name = b.name.replace("mixamorig:", "mixamorig_")
    for g in body.vertex_groups:
        g.name = g.name.replace("mixamorig:", "mixamorig_")
    top = max((body.matrix_world @ v.co).z for v in body.data.vertices)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print("02: %d verts, %d tris, %d materiais %s, topo %.3f m" % (len(body.data.vertices), tris, len(body.data.materials), [m.name for m in body.data.materials], top))
    return rig, body

def export_glb(rig, ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(o in (rig, ob))
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
                              export_skins=True, export_animations=False, export_morph=False,
                              export_apply=False, export_materials='EXPORT', export_image_format='AUTO')
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
             "profile": (1, -0.05, 0.03), "back": (-0.4, 1, 0.1)}
    for name, d in views.items():
        d = V(d).normalized()
        target, dist = V((0, 0, 0.93)), 4.8
        if name in ("face", "profile"):
            target, dist = V((0, -0.02, 1.62)), 1.0
        cam.location = target + d * dist
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(dirpath, "02_%s.png" % name)
        bpy.ops.render.render(write_still=True)

rig, ob = build()
if EXPORT:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    export_glb(rig, ob, OUT)
if SAVE:
    bpy.ops.wm.save_as_mainfile(filepath=SAVE)
if RENDER:
    render(RENDER)
