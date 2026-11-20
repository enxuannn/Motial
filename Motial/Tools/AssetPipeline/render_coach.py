import sys; sys.path.insert(0, 'build')
from common import *
bpy.ops.wm.open_mainfile(filepath=OUT + 'coach.blend')
M = json.load(open(OUT + 'coach_clips.json'))
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'MATERIAL'
sc.render.resolution_x, sc.render.resolution_y = 420, 600
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 2.0
# floor + stool for context
bpy.ops.mesh.primitive_plane_add(size=4); fl = bpy.context.active_object; assign(fl, material('floor', (0.6, 0.6, 0.62)))
st = M['stool']
bpy.ops.mesh.primitive_cylinder_add(radius=st['radius'], depth=st['seatHeight'], location=(0, -st['z'], st['seatHeight'] / 2))
stool = bpy.context.active_object; assign(stool, material('stool', (0.35, 0.25, 0.2)))
view = sys.argv[-1]
pos = {'front': (-1.6, -3.2, 1.0), 'side': (-3.5, 0, 0.9)}[view]
cam.location = pos; cam.rotation_mode = 'QUATERNION'
cam.rotation_quaternion = (Vector((0, -0.1, 0.85)) - Vector(pos)).to_track_quat('-Z', 'Y')
want = sys.argv[-2].split(',')
for c in M['clips']:
    if c['id'] not in want: continue
    for frac in (0.3,):
        t = c['start'] + (c['end'] - c['start']) * frac
        f = int(round(t * M['fps']))
        sc.frame_set(f)
        stool.hide_render = not c['seated']
        sc.render.filepath = OUT + f"pose_{c['id']}_{int(frac*100)}_{view}.png"
        bpy.ops.render.render(write_still=True)
