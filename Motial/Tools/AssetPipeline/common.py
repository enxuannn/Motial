"""Shared Blender helpers for the StrideXR asset pipeline."""
import bpy, bmesh, os, json, math
from mathutils import Vector, Matrix

STL = 'data/BodyParts3D_data/stl/'
OUT = 'build/out/'
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30


def import_stl(fma, name, scale=0.001):
    bpy.ops.wm.stl_import(filepath=STL + fma + '.stl', global_scale=scale)
    ob = bpy.context.selected_objects[0]
    ob.name = name
    ob.data.name = name
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    return ob


def decimate(ob, ratio):
    if ratio >= 1:
        return
    m = ob.modifiers.new('dec', 'DECIMATE')
    m.ratio = ratio
    apply_mods(ob)


def apply_mods(ob):
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def smooth(ob, angle=50):
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        pass


def clip_above(ob, z):
    """Remove geometry above world height z and cap the hole."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_outer=True)
    edges = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
    try:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    except Exception:
        pass
    bm.to_mesh(ob.data)
    bm.free()


def material(name, rgb, rough=0.5, metal=0.0, alpha=1.0, emission=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*rgb, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Alpha'].default_value = alpha
    if emission:
        b.inputs['Emission Color'].default_value = (*emission, 1)
        b.inputs['Emission Strength'].default_value = 1.0
    mat.diffuse_color = (*rgb, alpha)
    return mat


def assign(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def verts_world(ob):
    mw = ob.matrix_world
    return [mw @ v.co for v in ob.data.vertices]


def mirror_copy(ob, name):
    """Geometry-mirrored (not negative-scaled) copy across the sagittal plane."""
    me = ob.data.copy()
    me.name = name
    for v in me.vertices:
        v.co.x = -v.co.x
    me.flip_normals()
    new = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(new)
    new.matrix_world = ob.matrix_world.copy()
    return new


def select_only(obs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]


def join(obs, name):
    select_only(obs)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def export_usdz(path, animation=False, armatures=False):
    bpy.ops.wm.usd_export(
        filepath=path,
        export_animation=animation,
        export_armatures=armatures,
        only_deform_bones=True,
        export_materials=True,
        generate_preview_surface=True,
        generate_materialx_network=False,
        export_normals=True,
        export_uvmaps=True,
        convert_orientation=True,
        export_global_forward_selection='NEGATIVE_Z',
        export_global_up_selection='Y',
        triangulate_meshes=True,
        export_lights=False,
        export_cameras=False,
        evaluation_mode='RENDER',
    )


def to_rk(v):
    """Blender (Z-up, front = -Y) -> RealityKit (Y-up, front = +Z)."""
    return [round(v.x, 5), round(v.z, 5), round(-v.y, 5)]
