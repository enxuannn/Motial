"""Decimate the BodyParts3D skin once and cache it as body.blend."""
import sys; sys.path.insert(0, '/home/claude/build')
from common import *
reset()
b = import_stl('FMA7163', 'Body')
print('faces in', len(b.data.polygons))
# merge near-duplicate verts so the surface is welded, then decimate
bpy.context.view_layer.objects.active = b
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0004)
bpy.ops.object.mode_set(mode='OBJECT')
decimate(b, 0.035)
# floor at z = 0
mz = min(v.co.z for v in b.data.vertices)
b.data.transform(Matrix.Translation((0, 0, -mz)))
smooth(b, 60)
print('faces out', len(b.data.polygons), 'floor shift', mz)
bm = bmesh.new(); bm.from_mesh(b.data)
import collections
# island count
seen = set(); islands = []
for v in bm.verts:
    if v.index in seen: continue
    stack = [v]; comp = 0
    while stack:
        x = stack.pop()
        if x.index in seen: continue
        seen.add(x.index); comp += 1
        for e in x.link_edges:
            o = e.other_vert(x)
            if o.index not in seen: stack.append(o)
    islands.append(comp)
print('islands', sorted(islands, reverse=True)[:10])
bm.free()
bpy.ops.wm.save_as_mainfile(filepath=OUT + 'body.blend')
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x, sc.render.resolution_y = 600, 900
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.9
for name, pos in [('front', (0, -3, 0.85)), ('side', (-3, 0, 0.85))]:
    cam.location = pos; cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (Vector((0, 0, 0.85)) - Vector(pos)).to_track_quat('-Z', 'Y')
    sc.render.filepath = OUT + f'prev_body_{name}.png'; bpy.ops.render.render(write_still=True)
