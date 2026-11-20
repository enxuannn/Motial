import sys; sys.path.insert(0, 'build')
from common import *
bpy.ops.wm.open_mainfile(filepath=OUT + 'anatomy.blend')
J = json.load(open(OUT + 'anatomy_landmarks.json'))
def B(p): return Vector((p[0], -p[2], p[1]))
red = material('Lig', (0.95, 0.15, 0.2))
for n, l in J['ligaments'].items():
    a, b = B(l['a']), B(l['b'])
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=l['r'], depth=d.length, location=(a + b) / 2)
    c = bpy.context.active_object
    c.rotation_mode = 'QUATERNION'
    c.rotation_quaternion = d.to_track_quat('Z', 'Y')
    assign(c, red)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'
sc.render.resolution_x, sc.render.resolution_y = 900, 700
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 0.26
target = Vector((0, 0, 0.08))
for name, pos in [('lateral', (-0.5, 0, 0.08)), ('medial', (0.5, 0, 0.08)), ('front', (-0.25, -0.45, 0.25))]:
    cam.location = pos
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (target - Vector(pos)).to_track_quat('-Z', 'Y')
    sc.render.filepath = OUT + f'prev_anat_{name}.png'
    bpy.ops.render.render(write_still=True)
