"""Blender background authoring. Metres; Blender -Y is Godot +Z (forward).
Run: blender --background --python tools/weapons/build_bow.py
The .blend retains editable separate bow and arrow collections.
"""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets' / 'weapons' / 'bow'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0

def material(name, color, metal=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    node = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if node is None:
        node = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
        mat.node_tree.links.new(node.outputs['BSDF'], output.inputs['Surface'])
    node.inputs['Base Color'].default_value = (*color, 1)
    node.inputs['Metallic'].default_value = metal
    node.inputs['Roughness'].default_value = roughness
    return mat

wood = material('Warm laminated walnut', (.24, .105, .038))
edge = material('Maple laminate', (.62, .40, .18))
leather = material('Dark leather grip', (.065, .043, .025), roughness=.85)
metal = material('Brushed steel', (.32, .38, .42), .8, .3)
feather = material('Ochre fletching', (.62, .21, .045), roughness=.8)
shaft = material('Cedar arrow shaft', (.48, .30, .13))
cord = material('Linen winding', (.65, .58, .40), roughness=.9)
bow_objects = []
arrow_objects = []

def mesh(name, vertices, faces, mat, group):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    group.append(ob)
    return ob

def cube(name, loc, size, mat, group, bevel=.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.data.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new('Soft edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        ob.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    group.append(ob)
    return ob

def rod(name, a, b, radius, mat, group, vertices=10):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=(b-a).length, location=(a+b)/2)
    ob = bpy.context.object
    ob.name = name
    ob.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    ob.data.materials.append(mat)
    group.append(ob)
    return ob

# Recurved limbs: broad at the riser, tapering into reinforced tips.
for side in (-1, 1):
    # Convex limb surface toward the target (-Y); braced string behind grip (+Y).
    points = [(.085, .0), (.16, -.025), (.27, -.062), (.39, -.096), (.49, -.072), (.56, .015), (.61, .12)]
    for layer, thickness, mat, xoffset in [('Walnut', .018, wood, 0), ('Maple', .004, edge, .0)]:
        verts = []
        for i, (z, y) in enumerate(points):
            width = .043 - .025 * i/(len(points)-1)
            centre_y = y + (.013 if layer == 'Maple' else 0)
            for x, dy in [(-width/2,-thickness/2),(width/2,-thickness/2),(width/2,thickness/2),(-width/2,thickness/2)]:
                verts.append((x+xoffset, centre_y+dy, side*z))
        faces = [(0,3,2,1)]
        for i in range(len(points)-1):
            for j in range(4):
                a=i*4+j; b=i*4+(j+1)%4
                faces.append((a,b,b+4,a+4))
        faces.append(tuple(range(len(verts)-4,len(verts))))
        mesh(f'{layer} limb {side}', verts, faces, mat, bow_objects)
    cube(f'Tip reinforcement {side}', (0,.12,side*.61), (.023,.027,.045), leather,bow_objects,.004)

cube('Carved riser', (0,0,0), (.044,.054,.23), wood,bow_objects,.012)
cube('Leather hand grip', (0,.0,-.013), (.047,.058,.13), leather,bow_objects,.009)
for i in range(11):
    z=-.07+i*.011
    cube('Grip stitching', (.025,.0,z), (.003,.052,.003),cord,bow_objects,.001)
cube('Arrow shelf', (.033,-.008,.033), (.035,.027,.012),wood,bow_objects,.003)
for z in (-.104,.104):
    cube('Limb binding', (0,.0,z), (.048,.058,.022),cord,bow_objects,.004)

# 85 cm arrow allows a full cheek anchor without pulling the tip off the rest.
rod('Cedar shaft',(0,-.025,0),(0,-.79,0),.0045,shaft,arrow_objects)
rod('Nock',(0,0,0),(0,-.03,0),.006,cord,arrow_objects)
rod('Ferrule',(0,-.77,0),(0,-.81,0),.007,metal,arrow_objects)
mesh('Broadhead',[(0,-.85,0),(-.017,-.795,0),(0,-.805,.004),(.017,-.795,0),(0,-.805,-.004)],[(0,1,2),(0,2,3),(0,3,4),(0,4,1),(1,4,3,2)],metal,arrow_objects)
for i in range(3):
    angle=i*math.tau/3
    x,z=math.cos(angle),math.sin(angle)
    fin=mesh(f'Feather {i}',[(x*.004,-.035,z*.004),(x*.024,-.055,z*.024),(x*.021,-.14,z*.021),(x*.004,-.16,z*.004)],[(0,1,2,3)],feather,arrow_objects)
    feather.surface_render_method = 'DITHERED'
    feather.use_backface_culling = False

# Separate named collections in the native editable file.
for title, objects in [('Recurve bow 125cm',bow_objects),('Arrow 85cm',arrow_objects)]:
    collection=bpy.data.collections.new(title)
    scene.collection.children.link(collection)
    for ob in objects:
        for previous in list(ob.users_collection): previous.objects.unlink(ob)
        collection.objects.link(ob)

for filename, objects in [('recurve_bow.glb',bow_objects),('arrow.glb',arrow_objects)]:
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects: ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT/filename),export_format='GLB',use_selection=True,export_apply=True)

# Source includes the rest string as an editable display curve (not in GLB).
for a,b in [((0,.12,.61),(0,.12,.035)),((0,.12,.035),(0,.12,-.61))]:
    rod('Rest bowstring',a,b,.0013,cord,[],8)
# The arrow is moved aside in the source file for convenient inspection.
for ob in arrow_objects: ob.location.x += .16
scene['avatar_height_m']=1.8
scene['bow_height_m']=1.25
scene['arrow_length_m']=.85
scene['game_axes']='Godot +Y up, +Z arrow forward; bow grip at origin'
(OUT/'source').mkdir(exist_ok=True)
(OUT/'source'/'.gdignore').touch()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source'/'recurve_bow.blend'))
print('BOW_ASSETS_OK',OUT)
