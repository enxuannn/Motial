"""Court.usdz for Sport Lab: "Basketball Court" by Klieg3D (Sketchfab, CC BY 4.0), court only, scaled so the rim is
3.05 m high and placed so its near hoop's rim sits exactly on Sport Lab's rim (RealityKit (0, 3.05, -4.225)), facing
the person. The floor art is the 4K redraw (floor_4k.png) because the download only carries a 256 px texture.

Usage: python3 bake_court_only.py <basketball_court.glb> <floor_4k.png> <out.usdz>
"""
import bpy, sys, math
from mathutils import Vector, Matrix

GLB, FLOOR, OUT = sys.argv[-3], sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
D, C = bpy.data, bpy.context
bpy.ops.import_scene.gltf(filepath=GLB)
court = list(D.objects)
holder = D.objects.new('Court', None); C.scene.collection.objects.link(holder)
for o in court:
    if o.parent is None: o.parent = holder
S = 3.05 / (0.999 - 0.217)                        # rim height / model units (same as bake_court3d.py)
rim_model = Vector((-1.89, 0.0, 0.999))           # near (left) rim centre in model units, glTF imported Z-up
R = Matrix.Rotation(math.radians(-90), 4, 'Z')    # model -X (towards that hoop) -> Blender +Y (= RealityKit -Z, ahead)
rim_scaled = (R @ (rim_model * S).to_4d()).to_3d()
target = Vector((0.0, 4.225, 3.05))              # RealityKit (0, 3.05, -4.225) in Blender axes
holder.scale = (S, S, S)
holder.rotation_euler = (0, 0, math.radians(-90))
holder.location = target - rim_scaled
holder.location.z = -0.217 * S                    # floor at 0
crisp = D.images.load(FLOOR); crisp.name = 'court_floor_4k'
for m in D.materials:
    if not m.node_tree: continue
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image and tuple(n.image.size) == (256, 128):
            n.image = crisp
C.view_layer.update()
print('rim now at', tuple(round(v, 3) for v in (holder.matrix_world @ (rim_model.to_4d())).to_3d()), flush=True)

props = {p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties}
kw = dict(filepath=OUT)
for k, v in (('export_materials', True), ('export_textures', True), ('selected_objects_only', False),
             ('visible_objects_only', False), ('convert_orientation', True),
             ('export_global_forward_selection', 'NEGATIVE_Z'), ('export_global_up_selection', 'Y'),
             ('generate_preview_surface', True), ('export_lights', False), ('export_cameras', False),
             ('export_animation', False)):
    if k in props: kw[k] = v
bpy.ops.wm.usd_export(**kw)
print('DONE')
