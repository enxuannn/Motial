import bpy, sys
from mathutils import Matrix
sys.path.insert(0,'build')
from common import OUT, select_only
bpy.ops.wm.open_mainfile(filepath='build/models/baseball/glove2.blend')
ob=bpy.data.objects['GloveMesh']
img=bpy.data.images.load('build/models/baseball/glove_base_clean.png'); img.pack()
mat=bpy.data.materials.new('GloveLeather'); mat.use_nodes=True
nt=mat.node_tree; bsdf=nt.nodes['Principled BSDF']
tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=img
nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value=0.62; bsdf.inputs['Metallic'].default_value=0.0
ob.data.materials.clear(); ob.data.materials.append(mat)
for o in list(bpy.data.objects):
    if o is not ob: bpy.data.objects.remove(o)
root=bpy.data.objects.new('Glove',None); bpy.context.scene.collection.objects.link(root); ob.parent=root
select_only([root,ob])
bpy.ops.wm.usd_export(filepath=OUT+'Glove.usdz', selected_objects_only=True, export_materials=True, generate_preview_surface=True,
    convert_orientation=True, export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', triangulate_meshes=True)
print('glove ok', len(ob.data.polygons))
