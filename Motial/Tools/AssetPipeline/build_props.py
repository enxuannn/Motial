"""Game props: river stepping stones and a lotus (original models)."""
import sys; sys.path.insert(0, '/home/claude/build')
from common import *
import random
reset()
random.seed(3)
cols = [(0.52, 0.50, 0.47), (0.45, 0.44, 0.42), (0.58, 0.55, 0.50)]
moss = material('Moss', (0.30, 0.42, 0.22), rough=0.9)
for i, c in enumerate(cols):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=5, radius=1)
    s = bpy.context.active_object; s.name = f'Stone_{"ABC"[i]}'; s.data.name = s.name
    tex = bpy.data.textures.new(f'n{i}', 'VORONOI'); tex.noise_scale = 0.6 + 0.2 * i
    d = s.modifiers.new('d', 'DISPLACE'); d.texture = tex; d.strength = 0.16
    tex2 = bpy.data.textures.new(f'c{i}', 'CLOUDS'); tex2.noise_scale = 0.35
    d2 = s.modifiers.new('d2', 'DISPLACE'); d2.texture = tex2; d2.strength = 0.08
    apply_mods(s)
    # flatten: wide, low stepping stone, flat-ish top
    for v in s.data.vertices:
        v.co.z = max(v.co.z, -0.6) * 0.32
        if v.co.z > 0.22: v.co.z = 0.22 + (v.co.z - 0.22) * 0.25
    sx, sy = 0.24 + 0.02 * i, 0.21 + 0.015 * (2 - i)
    s.data.transform(Matrix.Diagonal((sx, sy, 0.6, 1)))
    mz = min(v.co.z for v in s.data.vertices)
    s.data.transform(Matrix.Translation((0, 0, -mz - 0.045)))  # sits slightly into the water
    dec = s.modifiers.new('dec', 'DECIMATE'); dec.ratio = 0.25; apply_mods(s)
    assign(s, material(f'Rock{i}', c, rough=0.85))
    smooth(s, 40)
    s.location.x = i * 0.7
# lotus: 3 rings of petals + pad
petal_mat = material('Petal', (0.98, 0.72, 0.82), rough=0.45)
core_mat = material('LotusCore', (1.0, 0.85, 0.35), rough=0.4, emission=(1.0, 0.75, 0.3))
pad_mat = material('Pad', (0.22, 0.52, 0.30), rough=0.6)
parts = []
for ring, (n, tilt, size) in enumerate([(8, 25, 1.0), (8, 45, 0.85), (6, 65, 0.7)]):
    for k in range(n):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.05 * size, segments=16, ring_count=8)
        p = bpy.context.active_object
        p.scale = (0.45, 1.0, 0.18)
        ang = 2 * math.pi * (k + 0.5 * ring) / n
        p.rotation_euler = (math.radians(tilt), 0, ang)
        p.location = (math.sin(ang) * -0.035 * size, math.cos(ang) * 0.035 * size, 0.02 + 0.012 * ring)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        assign(p, petal_mat); parts.append(p)
lotus = join(parts, 'LotusPetals'); smooth(lotus)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.022, location=(0, 0, 0.04)); core = bpy.context.active_object
core.name = 'LotusCore'; core.data.name = 'LotusCore'; assign(core, core_mat); smooth(core)
bpy.ops.mesh.primitive_cylinder_add(radius=0.13, depth=0.006, vertices=48, location=(0, 0, 0.003)); pad = bpy.context.active_object
pad.name = 'LilyPad'; pad.data.name = 'LilyPad'; assign(pad, pad_mat)
root = bpy.data.objects.new('Lotus', None); bpy.context.scene.collection.objects.link(root)
for o in (lotus, core, pad): o.parent = root
root.location.x = 2.4
select_only([o for o in bpy.data.objects if o.name.startswith('Stone')])
export = OUT + 'Stones.usdz'
bpy.ops.wm.usd_export(filepath=export, selected_objects_only=True, export_materials=True, generate_preview_surface=True,
                      convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                      triangulate_meshes=True)
root.location.x = 0
select_only([root, lotus, core, pad])
bpy.ops.wm.usd_export(filepath=OUT + 'Lotus.usdz', selected_objects_only=True, export_materials=True, generate_preview_surface=True,
                      convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y',
                      triangulate_meshes=True)
for o in bpy.data.objects:
    if o.name.startswith('Stone'): o.location.x = 0
print('ok')
