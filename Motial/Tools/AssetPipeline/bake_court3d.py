"""Court Smarts live 3D: bakes the 'sprain' and 'safe' rebound scenes from vr180.py into ONE animated USDZ for RealityKit,
so the app can play them life-size on Sunset Court with real stereo depth and walk-around parallax (no video).

Timeline (24 fps):  sprain = frames 0 .. 158   ·   safe = frames 170 .. 290   (see COURT3D_* in CourtGuideView.swift)
X-ray fade, bone glow and ligament glow are NOT baked: the app drives them from the same timing as vr180.plan().

Usage (inputs in build/tmp/vr, same as vr180.py):  python3 bake_court3d.py -- sprain bake
Output: build/tmp/vr/Court3D.usdz
"""
import bpy, sys, math
from mathutils import Vector, Matrix

VR = 'build/tmp/vr'
src = open(f'{VR}/vr180.py').read().split("if mode=='preview'")[0]
sys.argv = ['x', '--', 'sprain', 'bake']
g = {'__name__': 'bake'}
exec(src, g)
D, C = bpy.data, bpy.context
maya, dfd, ball = g['maya'], g['dfd'], g['ball']
maya_root, dfd_root = g['maya_root'], g['dfd_root']
FPS = g['FPS']
SAFE_START = 170

def record(variant):
    g['variant'] = variant
    # the catch point depends on the variant (Maya drifts only in 'sprain')
    g['CATCH'] = (0, 0, 0)
    g['apply'](g['CATCH_T']); C.view_layer.update(); mw = maya.matrix_world
    g['CATCH'] = tuple((mw @ maya.pose.bones['RightHand_019'].head + mw @ maya.pose.bones['LeftHand_015'].head) / 2 + Vector((0, -0.05, 0.10)))
    dur = 6.6 if variant == 'sprain' else 5.0
    frames = []
    for f in range(int(dur * FPS) + 1):
        g['apply'](f / FPS)
        C.view_layer.update()
        frames.append({
            'maya': {b.name: (b.location.copy(), b.rotation_quaternion.copy()) for b in maya.pose.bones},
            'dfd': {b.name: (b.location.copy(), b.rotation_quaternion.copy()) for b in dfd.pose.bones},
            'mroot': maya_root.location.copy(), 'droot': dfd_root.location.copy(), 'ball': ball.location.copy(),
        })
    return frames

rec = {'sprain': record('sprain'), 'safe': record('safe')}
print('recorded', {k: len(v) for k, v in rec.items()}, flush=True)

# drop helpers the app does not need (defender x-ray parts, halos, render floor, light)
for o in list(D.objects):
    if (o.name.endswith('.001') and o.name.startswith(('Bones', 'InjuryGlow'))) or o.name in ('HaloR', 'HaloL') \
       or o.type in ('LIGHT', 'CAMERA') or (o.type == 'MESH' and getattr(o, 'is_shadow_catcher', False)):
        D.objects.remove(o, do_unlink=True)
for o in D.objects:
    o.hide_render = False; o.hide_viewport = False; o.hide_set(False)

# write clean keyframes
for arm in (maya, dfd):
    arm.animation_data_create(); arm.animation_data.action = D.actions.new(arm.name + '_court3d')
for o in (maya_root, dfd_root, ball):
    o.animation_data_create(); o.animation_data.action = D.actions.new(o.name + '_court3d')

def key(frame, fr):
    for arm, k in ((maya, 'maya'), (dfd, 'dfd')):
        for b in arm.pose.bones:
            loc, rot = fr[k][b.name]
            b.location = loc; b.rotation_quaternion = rot
            b.keyframe_insert('location', frame=frame); b.keyframe_insert('rotation_quaternion', frame=frame)
    for o, k in ((maya_root, 'mroot'), (dfd_root, 'droot'), (ball, 'ball')):
        o.location = fr[k]; o.keyframe_insert('location', frame=frame)

for i, fr in enumerate(rec['sprain']): key(i, fr)
for i, fr in enumerate(rec['safe']): key(SAFE_START + i, fr)
sc = C.scene
sc.render.fps = FPS
sc.frame_start = 0; sc.frame_end = SAFE_START + len(rec['safe']) - 1
print('keyed frames', sc.frame_start, sc.frame_end, flush=True)

# ---- the court itself: "Basketball Court" by Klieg3D (Sketchfab, CC BY 4.0), scaled so its rim is 3.05 m high and
# its left rim sits exactly on the rebound scene's rim; the floor art is redrawn at 4K (floor_4k.png) because the
# download only carries a 256 px texture. The procedural hoop is then removed.
import os
COURT = f'{VR}/basketball_court.glb'
if os.path.exists(COURT):
    before = set(D.objects)
    bpy.ops.import_scene.gltf(filepath=COURT)
    court = [o for o in D.objects if o not in before]
    holder = D.objects.new('KliegCourt', None); C.scene.collection.objects.link(holder)
    for o in court:
        if o.parent is None: o.parent = holder
    S = 3.05 / (0.999 - 0.217)                      # rim height / model units
    rim = Vector((-1.89, 0.0, 0.999)) * S            # left rim centre in the scaled model
    holder.scale = (S, S, S)
    holder.location = Vector(g['RIM']) - rim + Vector((0, 0, 0.0))
    holder.location.z = -0.217 * S                   # floor at 0
    if os.path.exists(f'{VR}/floor_4k.png'):
        crisp = D.images.load(f'{VR}/floor_4k.png'); crisp.name = 'court_floor_4k'
        for m in D.materials:
            if not m.node_tree: continue
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE' and n.image and tuple(n.image.size) == (256, 128):
                    n.image = crisp
    for o in list(D.objects):
        if o.name in ('Pole', 'Arm', 'Board', 'Torus', 'Cone') or o.name.startswith('Frame'):
            D.objects.remove(o, do_unlink=True)
    print('court placed, scale', round(S, 3), 'at', tuple(round(x, 3) for x in holder.location), flush=True)

# ---- the ball: the owner's basketball model (credited in Settings) replaces the procedural sphere
BALL = f'{VR}/ball.usdz'
if os.path.exists(BALL):
    before = set(D.objects)
    bpy.ops.wm.usd_import(filepath=BALL)
    new = [o for o in D.objects if o not in before]
    mesh_obj = next(o for o in new if o.type == 'MESH')
    me = mesh_obj.data.copy()
    me.transform(mesh_obj.matrix_world)
    vs = [v.co for v in me.vertices]
    ctr = sum(vs, Vector()) / len(vs)
    rad = max((v - ctr).length for v in vs)
    me.transform(Matrix.Translation(-ctr)); me.transform(Matrix.Scale(0.12 / rad, 4))
    old = ball.data
    ball.data = me
    for o in new: D.objects.remove(o, do_unlink=True)
    for im in D.images:
        if im.name.lower().startswith('basketball_clean') and im.size[0] > 1024: im.scale(1024, 1024)
    print('ball replaced, radius was', round(rad, 3), flush=True)

# The glTF and USD imports above reset the scene's frame range (and fps) to their own files, which made the
# export a single still frame. Restore the full timeline right before exporting.
sc.render.fps = FPS
sc.frame_start = 0; sc.frame_end = SAFE_START + len(rec['safe']) - 1
print('export frames', sc.frame_start, sc.frame_end, 'fps', sc.render.fps, flush=True)
props = {p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties}
kw = dict(filepath=f'{VR}/Court3D.usdz', export_animation=True)
for k, v in (('export_armatures', True), ('export_materials', True), ('export_textures', True),
             ('selected_objects_only', False), ('visible_objects_only', False),
             ('convert_orientation', True), ('export_global_forward_selection', 'NEGATIVE_Z'),
             ('export_global_up_selection', 'Y'), ('generate_preview_surface', True),
             ('export_lights', False), ('export_cameras', False), ('only_deform_bones', False)):
    if k in props: kw[k] = v
print('export options', sorted(kw), flush=True)
bpy.ops.wm.usd_export(**kw)
print('DONE')
