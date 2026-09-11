"""Author original PRF hard-surface assets using Blender 4.1+. No game files touched.

Run with Blender --background --factory-startup --python this_file.py.
Outputs are beside this script. Dimensions are metres; front is -Y, up is +Z.
"""
from pathlib import Path
from math import pi, sin, cos, radians
import json
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parent
for folder in ('models', 'previews'):
    (OUT / folder).mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)
SCENE = bpy.context.scene
SCENE.unit_settings.system = 'METRIC'
SCENE.unit_settings.scale_length = 1.0
SCENE.render.engine = 'CYCLES'
SCENE.cycles.device = 'CPU'
SCENE.cycles.samples = 40
SCENE.cycles.use_denoising = True
SCENE.render.threads_mode = 'FIXED'
SCENE.render.threads = 8
SCENE.render.resolution_percentage = 100
SCENE.render.image_settings.file_format = 'PNG'
SCENE.view_settings.view_transform = 'AgX'
SCENE.render.film_transparent = False
SCENE.world.color = (0.12, 0.12, 0.12)
SCENE.world.use_nodes = True
SCENE.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.17, 0.23, 0.3, 1)
SCENE.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.35
CURRENT = None


def material(name, color, metal=0, rough=0.4, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m


M = {
    'ivory': material('M_PRF_CeramicIvory', (0.63, 0.69, 0.66), 0.42, 0.32),
    'orange': material('M_PRF_BurntOrange', (0.56, 0.105, 0.025), 0.38, 0.32),
    'dark': material('M_PRF_Graphite', (0.022, 0.044, 0.054), 0.65, 0.3),
    'black': material('M_PRF_Rubber', (0.012, 0.019, 0.022), 0.05, 0.6),
    'steel': material('M_PRF_BrushedSteel', (0.24, 0.33, 0.35), 0.85, 0.32),
    'brass': material('M_PRF_ChampagneMetal', (0.49, 0.30, 0.105), 0.8, 0.3),
    'cyan': material('M_PRF_StatusCyan', (0.015, 0.67, 0.88), 0.25, 0.25, 2.0),
    'amber': material('M_PRF_StatusAmber', (1.0, 0.28, 0.025), 0.2, 0.25, 1.5),
    'white': material('M_PRF_Lettering', (0.82, 0.88, 0.81), 0.1, 0.45),
}


def collection(name):
    global CURRENT
    CURRENT = bpy.data.collections.new(name)
    SCENE.collection.children.link(CURRENT)
    return CURRENT


def own(obj, name, mat=None):
    obj.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    CURRENT.objects.link(obj)
    if mat:
        obj.data.materials.append(M[mat])
    return obj


def bevel(obj, width=0.03, segments=3):
    if width:
        mod = obj.modifiers.new('Machined edge radii', 'BEVEL')
        mod.width = width
        mod.segments = segments
    mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    return obj


def box(name, loc, size, mat, edge=0.03, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = own(bpy.context.object, name, mat)
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if rot:
        o.rotation_euler = rot
    return bevel(o, edge)


def cyl(name, loc, radius, depth, mat, axis='Z', vertices=32, edge=0.015):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    o = own(bpy.context.object, name, mat)
    if axis == 'Y':
        o.rotation_euler.x = pi / 2
    elif axis == 'X':
        o.rotation_euler.y = pi / 2
    for p in o.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return bevel(o, edge, 2)


def ring(name, loc, radius, tube, mat, axis='Z', major_segments=40):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=tube,
                                   major_segments=major_segments, minor_segments=8, location=loc)
    o = own(bpy.context.object, name, mat)
    if axis == 'Y':
        o.rotation_euler.x = pi / 2
    elif axis == 'X':
        o.rotation_euler.y = pi / 2
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def pipe(name, points, radius, mat):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 1
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('POLY')
    spline.points.add(len(points)-1)
    for p, co in zip(spline.points, points):
        p.co = (*co, 1)
    o = bpy.data.objects.new(name, curve)
    CURRENT.objects.link(o)
    o.data.materials.append(M[mat])
    return o


def text(name, label, loc, size, mat='white', rot=(pi/2, 0, 0)):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = label
    curve.size = size
    curve.align_x = 'CENTER'
    curve.align_y = 'CENTER'
    curve.extrude = 0.0005
    curve.resolution_u = 3
    o = bpy.data.objects.new(name, curve)
    o.location = loc
    o.rotation_euler = rot
    CURRENT.objects.link(o)
    o.data.materials.append(M[mat])
    return o


def bolt(name, loc, axis='Y', r=0.028):
    cyl(name, loc, r, 0.018, 'steel', axis, vertices=6, edge=0.003)


def front_panel(name, loc, size, mat='ivory'):
    x,y,z = loc
    w,d,h = size
    box(name+'_gasket', (x,y+0.02,z), (w+0.045,d,h+0.045), 'black', 0.035)
    box(name, loc, size, mat, 0.035)
    for dx in [-w/2+0.08, w/2-0.08]:
        for dz in [-h/2+0.075, h/2-0.075]:
            bolt(name+'_fastener', (x+dx,y-d/2-0.009,z+dz), r=0.021)


def warning_band(name, loc, width, height):
    x,y,z=loc
    box(name+'_plate', loc, (width,0.018,height), 'brass', 0.005)
    # Individual vertical slashes remain inside plate bounds.
    for i in range(int(width/0.11)):
        box(name+'_stripe', (x-width/2+0.07+i*0.11,y-0.014,z),
            (0.041,0.009,height*0.8), 'dark', 0.002, (0,-0.3,0))


def feet(width, depth):
    for x in (-width/2+0.22,width/2-0.22):
        for y in (-depth/2+0.22,depth/2-0.22):
            box('Isolation_foot', (x,y,0.09), (0.42,0.42,0.18), 'black', 0.04)
            box('Foot_mount', (x,y,0.2), (0.32,0.32,0.11), 'steel', 0.025)


def hatch_glyph(x,y,z,scale=1):
    # Original geometric egg insignia, opaque enclosure; not an actual egg.
    points=[]
    for i in range(33):
        a=2*pi*i/32
        points.append((x+scale*0.12*sin(a)*(0.88-0.16*cos(a)),y,z+scale*0.18*cos(a)))
    pipe('Egg_insignia', points, scale*0.008, 'cyan')
    pipe('Egg_insignia_divider', [(x-0.067*scale,y,z),(x+0.067*scale,y,z)], 0.005*scale, 'cyan')



exec(compile((OUT/'converter_geometry.py').read_text(encoding='utf-8'),str(OUT/'converter_geometry.py'),'exec'))
