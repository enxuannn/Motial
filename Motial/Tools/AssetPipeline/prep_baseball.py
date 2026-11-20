import bpy, sys, math
from mathutils import Vector, Matrix
sys.path.insert(0,'build')
from common import OUT, select_only
def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes=[o for o in bpy.data.objects if o.type=='MESH']
    for o in meshes:
        o.data.transform(o.matrix_world); o.parent=None; o.matrix_world=Matrix.Identity(4)
    for o in list(bpy.data.objects):
        if o.type!='MESH': bpy.data.objects.remove(o)
    select_only(meshes); bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes)>1: bpy.ops.object.join()
    ob=bpy.context.active_object
    # centre + bbox
    vs=[v.co for v in ob.data.vertices]
    mn=Vector(map(min,*zip(*vs))) if False else Vector((min(v.x for v in vs),min(v.y for v in vs),min(v.z for v in vs)))
    mx=Vector((max(v.x for v in vs),max(v.y for v in vs),max(v.z for v in vs)))
    c=(mn+mx)/2; ob.data.transform(Matrix.Translation(-c))
    return ob,(mx-mn)
which=sys.argv[-1]
if which=='ball':
    ob,size=load('/mnt/user-data/uploads/Downloads/steady_baseball.glb')
    s=0.074/max(size); ob.data.transform(Matrix.Scale(s,4))
    for im in bpy.data.images:
        im.scale(512,512)
    ob.name='BaseballMesh'; ob.data.name='BaseballMesh'
    root=bpy.data.objects.new('Baseball',None); bpy.context.scene.collection.objects.link(root); ob.parent=root
    for im in bpy.data.images: im.pack()
    select_only([root,ob])
    bpy.ops.wm.usd_export(filepath=OUT+'Baseball.usdz', selected_objects_only=True, export_materials=True, generate_preview_surface=True,
        convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', triangulate_meshes=True)
    print('BALL ok', [round(x*s,3) for x in size])
else:
    ob,size=load('/mnt/user-data/uploads/Downloads/steady_glove.glb')
    print('GLOVE size',[round(x,3) for x in size], 'attrs',[a.name for a in ob.data.color_attributes])
    s=0.30/max(size); ob.data.transform(Matrix.Scale(s,4))
    m=ob.modifiers.new('d','DECIMATE'); m.ratio=16000/len(ob.data.polygons)
    bpy.ops.object.modifier_apply(modifier='d')
    print('tris',len(ob.data.polygons))
    bpy.ops.wm.save_as_mainfile(filepath='build/models/baseball/glove_dec.blend')

if which in ('glove2','glove3'):
    ob,size=load('/mnt/user-data/uploads/Downloads/steady_'+which+'.glb')
    s=0.29/max(size); ob.data.transform(Matrix.Scale(s,4))
    for im in bpy.data.images: im.scale(1024,1024); im.pack()
    ob.name='GloveMesh'; ob.data.name='GloveMesh'
    bpy.ops.wm.save_as_mainfile(filepath='build/models/baseball/'+which+'.blend')
    # previews from 6 axes
    sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=16; sc.render.resolution_x=sc.render.resolution_y=360
    w=bpy.data.worlds.new('w'); sc.world=w; w.color=(0.8,0.8,0.8)
    cam=bpy.data.objects.new('cam',bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera=cam
    cam.data.type='ORTHO'; cam.data.ortho_scale=0.36
    sun=bpy.data.objects.new('sun',bpy.data.lights.new('sun','SUN')); sc.collection.objects.link(sun); sun.data.energy=3
    for name,d in {'px':(1,0,0),'nx':(-1,0,0),'py':(0,1,0),'ny':(0,-1,0),'pz':(0,0,1),'nz':(0,0,-1)}.items():
        v=Vector(d); cam.location=v*1.0
        cam.rotation_euler=(-v).to_track_quat('-Z','Y' if abs(v.z)<0.9 else 'X').to_euler()
        sun.rotation_euler=cam.rotation_euler
        sc.render.filepath=f'build/models/baseball/{which}_view_{name}.png'; bpy.ops.render.render(write_still=True)
    print('GLOVE2 ok',[round(x*s,3) for x in size])
