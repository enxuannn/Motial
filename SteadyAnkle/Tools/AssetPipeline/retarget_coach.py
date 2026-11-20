"""Retargets the clinical exercise motion library onto any humanoid rig (e.g. a Sketchfab photoreal/scan model)
and exports Coach.usdz + coach_clips.json. Usage: python3 retarget_coach.py <model.glb|fbx> [height_m]"""
import sys; sys.path.insert(0, '/home/claude/build')
from common import *
from mathutils import Quaternion
import math, re

SRC = sys.argv[1]
TARGET_H = float(sys.argv[2]) if len(sys.argv) > 2 else None
reset()
FPS = 30
bpy.context.scene.render.fps = FPS
if SRC.lower().endswith(('.glb', '.gltf')):
    bpy.ops.import_scene.gltf(filepath=SRC)
else:
    bpy.ops.import_scene.fbx(filepath=SRC, automatic_bone_orientation=False)

arm = max((o for o in bpy.data.objects if o.type == 'ARMATURE'), key=lambda a: len(a.data.bones))
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
for o in list(bpy.data.objects):
    if o.type in ('CAMERA', 'LIGHT') or (o.type == 'MESH' and o not in meshes) or (o.type == 'ARMATURE' and o != arm):
        bpy.data.objects.remove(o)
# drop imported animation
if arm.animation_data: arm.animation_data_clear()
for a in list(bpy.data.actions): bpy.data.actions.remove(a)

# ---------- bake the rest-pose deformation into the mesh so bind pose == rest pose ----------
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = Quaternion(); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
for o in meshes:
    ev = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old_me = o.data; o.data = me
    me.materials.clear()
    for m in old_me.materials: me.materials.append(m)
    # the armature now deforms from this (rest) shape
    for m in o.modifiers:
        if m.type == 'ARMATURE': m.object = arm
    me.name = old_me.name

# ---------- normalise transforms: unparent everything, apply, Z-up, feet on floor ----------
for o in meshes + [arm]:
    mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type == 'EMPTY': bpy.data.objects.remove(o)
select_only([arm] + meshes)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in meshes:
    for m in o.modifiers:
        if m.type == 'ARMATURE': m.object = arm

def bbox_dims():
    vs = []
    for o in meshes: vs += [o.matrix_world @ v.co for v in o.data.vertices]
    return [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
dims = bbox_dims()
up = dims.index(max(dims))
if up != 2:
    Rup = Matrix.Rotation(math.pi / 2, 4, 'X') if up == 1 else Matrix.Rotation(-math.pi / 2, 4, 'Y')
    for o in meshes + [arm]: o.matrix_world = Rup @ o.matrix_world
    select_only([arm] + meshes); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    print('rotated up axis', 'XYZ'[up], '-> Z')

def all_verts():
    vs = []
    for o in meshes: vs += [o.matrix_world @ v.co for v in o.data.vertices]
    return vs
V = all_verts()
zmin, zmax = min(v.z for v in V), max(v.z for v in V)
h = zmax - zmin
s = (TARGET_H / h) if TARGET_H else (1.0 if 1.4 < h < 2.0 else 1.68 / h)
M = Matrix.Translation((0, 0, -zmin * s)) @ Matrix.Diagonal((s, s, s, 1))
for o in meshes + [arm]: o.matrix_world = M @ o.matrix_world
select_only([arm] + meshes)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print('height', round(h * s, 3), 'scale', round(s, 4))

# ---------- bone mapping ----------
B = arm.data.bones
def clean(n):
    c = re.sub(r'^(mixamorig\d*[:_]|cc_base_|bip\d*[ _]|def[-_]|j_bip_[clr]_|rig[:_])', '', n.lower())
    return re.sub(r'[_.]\d+$', '', c)
def core(n):
    c = clean(n)
    c = re.sub(r'left|right', '', c)
    c = re.sub(r'(^|[_.\s])[lr]($|[_.\s])', r'\1\2', c)
    return c.strip('_. ')
def side_of(n):
    c = clean(n)
    if re.search(r'(^|[_.\s-])l($|[_.\s-])|left|_l$|\.l$|^l_', c): return 'L'
    if re.search(r'(^|[_.\s-])r($|[_.\s-])|right|_r$|\.r$|^r_', c): return 'R'
    return None
def find(pats, side=None, exclude=()):
    best = None
    for b in B:
        c = core(b.name)
        if any(e in c for e in exclude): continue
        if side and side_of(b.name) != side: continue
        if not side and side_of(b.name): continue
        for i, p in enumerate(pats):
            if re.search(p, c):
                if best is None or i < best[0]: best = (i, b.name)
    return best[1] if best else None

MAP = {}
MAP['Hips'] = find([r'^hips?$', r'pelvis', r'hip$'], exclude=('thigh', 'upleg'))
spines = [b for b in B if not side_of(b.name) and re.search(r'spine|chest|torso|waist', clean(b.name))]
# order spine bones along the chain from hips
def chain_depth(b):
    d = 0; p = b.parent
    while p: d += 1; p = p.parent
    return d
spines.sort(key=chain_depth)
MAP['Spine'] = spines[0].name
MAP['Chest'] = spines[-1].name
MAP['Neck'] = find([r'^neck', r'neck'], exclude=('twist',))
MAP['Head'] = find([r'^head$', r'^head'], exclude=('end', 'top', 'nub'))
for sd in 'RL':
    MAP['Thigh_' + sd] = find([r'upleg', r'thigh', r'upperleg', r'upper_leg'], sd, exclude=('twist', 'share'))
    MAP['Shin_' + sd] = find([r'^.?leg$', r'(^|[_.\s])leg($|[_.\s])', r'calf', r'shin', r'lowerleg', r'lower_leg', r'knee'], sd, exclude=('up', 'thigh', 'twist', 'share'))
    MAP['Foot_' + sd] = find([r'foot', r'ankle'], sd, exclude=('twist', 'end'))
    MAP['Toe_' + sd] = find([r'toebase', r'toe_?base', r'toes?$', r'(^|[_.\s])toe'], sd, exclude=('end', 'nub', 'tip'))
    MAP['UpperArm_' + sd] = find([r'^.?arm$', r'(^|[_.\s])arm($|[_.\s])', r'upperarm', r'upper_arm', r'uparm'], sd, exclude=('fore', 'lower', 'twist', 'share'))
    MAP['ForeArm_' + sd] = find([r'forearm', r'lowerarm', r'lower_arm', r'elbow'], sd, exclude=('twist', 'share'))
    MAP['Hand_' + sd] = find([r'^.?hand$', r'(^|[_.\s])hand($|[_.\s])', r'wrist'], sd, exclude=('twist', 'index', 'thumb', 'middle', 'ring', 'pinky'))
# joint-named rigs (SMPL-style: hip/knee/ankle/foot, shoulder/elbow/wrist)
for sd in 'RL':
    if MAP['Thigh_' + sd] is None: MAP['Thigh_' + sd] = find([r'^hip$'], sd)
    if MAP['Toe_' + sd] is None and MAP['Foot_' + sd] and 'ankle' in core(MAP['Foot_' + sd]): MAP['Toe_' + sd] = find([r'^foot$'], sd)
    if MAP['UpperArm_' + sd] is None and MAP['ForeArm_' + sd] and 'elbow' in core(MAP['ForeArm_' + sd]): MAP['UpperArm_' + sd] = find([r'^shoulder$'], sd)
missing = [k for k, v in MAP.items() if v is None and not k.startswith('Toe_')]
print('MAP', MAP)
assert not missing, f'unmapped bones: {missing}'

def head(k): return B[MAP[k]].head_local.copy()
def mesh_toe_tip_pre(sd):
    a = B[MAP['Foot_' + sd]].head_local
    cand = [v for v in all_verts() if v.z < a.z * 0.6 and abs(v.x - a.x) < 0.07]
    far = max(cand, key=lambda v: abs(v.y - a.y)) if cand else a
    return far
def tail(k): return B[MAP[k]].tail_local.copy()
# facing: toes should be at -Y
if (head('Toe_R') if MAP['Toe_R'] else mesh_toe_tip_pre('R')).y > head('Foot_R').y:
    R180 = Matrix.Rotation(math.pi, 4, 'Z')
    for o in meshes + [arm]: o.matrix_world = R180 @ o.matrix_world
    select_only([arm] + meshes); bpy.ops.object.transform_apply(rotation=True)
    B = arm.data.bones
# the right side must be at -X (subject's right); swap labels if needed
if head('Thigh_R').x > 0:
    for a, b2 in [('Thigh', 'Thigh'), ('Shin', 'Shin'), ('Foot', 'Foot'), ('Toe', 'Toe'), ('UpperArm', 'UpperArm'), ('ForeArm', 'ForeArm'), ('Hand', 'Hand')]:
        MAP[a + '_R'], MAP[a + '_L'] = MAP[a + '_L'], MAP[a + '_R']

def mesh_toe_tip(sd):
    a = head('Foot_' + sd)
    cand = [v for v in all_verts() if v.z < a.z * 0.6 and abs(v.x - a.x) < 0.07]
    return min(cand, key=lambda v: v.y) if cand else a + Vector((0, -0.18, -a.z + 0.01))
if MAP['Toe_R']:
    mtp_R = head('Toe_R'); toe_tip_R = mtp_R + (mtp_R - head('Foot_R')).normalized() * 0.06
    if B[MAP['Toe_R']].children: toe_tip_R = B[MAP['Toe_R']].children[0].head_local.copy()
    elif (tail('Toe_R') - mtp_R).length < 0.15: toe_tip_R = tail('Toe_R')
else:
    toe_tip_R = mesh_toe_tip('R'); a = head('Foot_R')
    mtp_R = a + (toe_tip_R - a) * 0.72; mtp_R.z = max(0.02, toe_tip_R.z + 0.012)
fore_dir_R = head('Hand_R') - head('ForeArm_R')
J = {'hip': head('Thigh_R'), 'knee': head('Shin_R'), 'ankle': head('Foot_R'), 'mtp': mtp_R, 'toe': toe_tip_R,
     'shoulder': head('UpperArm_R'), 'elbow': head('ForeArm_R'), 'wrist': head('Hand_R'), 'fingertip': head('Hand_R') + fore_dir_R.normalized() * 0.18,
     'pelvis': head('Hips'), 'spine': head('Spine'), 'chest': head('Chest'), 'neck': head('Neck'), 'headbase': head('Head'), 'headtop': head('Head') + Vector((0, 0, 0.2))}
# symmetric model assumption: use the right side for both (mirrored)
def side(v, sd): return Vector((v.x if sd == 'R' else -v.x, v.y, v.z))
REST = {k: (B[v].matrix_local.to_3x3().normalized().to_quaternion(), B[v].head_local.copy()) for k, v in MAP.items() if v}

# ---------- rename meshes so the app can style them ("Body*") ----------
meshes.sort(key=lambda o: -len(o.data.vertices))
for i, o in enumerate(meshes):
    o.name = 'Body' if i == 0 else f'Body_{i}'
    o.data.name = o.name
    if o.data.shape_keys:
        bpy.context.view_layer.objects.active = o; bpy.ops.object.shape_key_remove(all=True)
total = sum(len(o.data.polygons) for o in meshes)
ratio = min(1.0, 95000 / max(total, 1))
if ratio < 0.98:
    for o in meshes:
        d = o.modifiers.new('dec', 'DECIMATE'); d.ratio = ratio
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_move_to_index(modifier='dec', index=0)
        bpy.ops.object.modifier_apply(modifier='dec')
print('tris', total, '->', sum(len(o.data.polygons) for o in meshes))

# ---------- CT leg/foot skeleton fitted inside each leg (for "See the ankle" X-ray) ----------
CTJ = {k: Vector(v) for k, v in json.load(open(OUT + 'joints.json')).items()}
bone_mat = material('Bone', (0.93, 0.89, 0.80), rough=0.5)
glow_mat = material('InjuryGlow', (1.0, 0.25, 0.3), rough=0.3, emission=(1.0, 0.2, 0.25))
GROUPS = {'Shin': ['FMA24477', 'FMA24480'],
          'Foot': ['FMA24482', 'FMA24497', 'FMA24500', 'FMA24528', 'FMA24521', 'FMA24523', 'FMA24525',
                   'FMA24507', 'FMA24509', 'FMA24511', 'FMA24513', 'FMA24515'],
          'Toe': ['FMA43253', 'FMA32650', 'FMA32634', 'FMA32642', 'FMA32652', 'FMA32636', 'FMA32644', 'FMA32654',
                  'FMA32638', 'FMA32646', 'FMA32656', 'FMA32640', 'FMA230986', 'FMA32658']}
def frame3(a, b, c):
    y = (b - a).normalized(); f = (c - b); z = (f - y * f.dot(y)).normalized(); x = y.cross(z)
    return Matrix((x, y, z)).transposed()
def fit_matrix(sd):
    k0, a0, m0 = side(CTJ['knee'], sd), side(CTJ['ankle'], sd), side(CTJ['mtp'], sd)
    k1, a1, m1 = side(J['knee'], sd), side(J['ankle'], sd), side(J['mtp'], sd)
    sc = (a1 - k1).length / (a0 - k0).length
    R = frame3(k1, a1, m1) @ frame3(k0, a0, m0).inverted()
    return Matrix.Translation(a1) @ (R.to_4x4() @ Matrix.Diagonal((sc, sc, sc, 1))) @ Matrix.Translation(-a0)
for sd in 'RL':
    Mfit = fit_matrix(sd); parts = []
    for grp, ids in GROUPS.items():
        for f in ids:
            o = import_stl(f, f + sd)
            o.data.transform(Matrix.Translation((0, 0, 0.0134)))
            decimate(o, 0.3 if grp != 'Toe' else 0.5)
            if sd == 'L':
                for v in o.data.vertices: v.co.x = -v.co.x
                o.data.flip_normals()
            o.data.transform(Mfit)
            vg = o.vertex_groups.new(name=MAP[f'{grp}_{sd}'] or MAP[f'Foot_{sd}'])
            vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
            parts.append(o)
    bo = join(parts, 'Bones_' + sd); assign(bo, bone_mat); smooth(bo)
    a = side(J['ankle'], sd)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, segments=24, ring_count=12,
                                         location=(a.x + (-0.03 if sd == 'R' else 0.03), a.y - 0.015, a.z - 0.022))
    g = bpy.context.active_object; g.name = 'InjuryGlow_' + sd; g.data.name = g.name
    g.scale = (0.6, 1.0, 0.75); bpy.ops.object.transform_apply(scale=True)
    vg = g.vertex_groups.new(name=MAP['Foot_' + sd]); vg.add(list(range(len(g.data.vertices))), 1.0, 'REPLACE')
    assign(g, glow_mat)
    for o in (bo, g):
        o.parent = arm; m = o.modifiers.new('Armature', 'ARMATURE'); m.object = arm

# ---------- motion library (shared with build_coach.py) ----------
src = open('/home/claude/build/build_coach.py').read()
lib = src[src.index('def RX(d)'):src.index('rig.animation_data_create()')]
ns = dict(globals())
ns.update({'J': J, 'side': side, 'REST': REST})
exec(lib, ns)
ns['PRON'] = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0   # T/A-pose rigs already have neutral palms after arm correction

# arm base correction: rotate this rig's rest arm segments onto the CT anatomical rest directions
def rotdiff(a, b): return a.normalized().rotation_difference(b.normalized())
BASE = {}
def segdir(k, sd):
    nxt = {'UpperArm': 'ForeArm', 'ForeArm': 'Hand'}
    if k in nxt: return head(nxt[k] + '_' + sd) - head(k + '_' + sd)
    return head('Hand_' + sd) - head('ForeArm_' + sd)       # hand follows the forearm line
for sd in 'RL':
    BASE['UpperArm_' + sd] = rotdiff(segdir('UpperArm', sd), side(CTJ['elbow'], sd) - side(CTJ['shoulder'], sd))
    BASE['ForeArm_' + sd] = rotdiff(segdir('ForeArm', sd), side(CTJ['wrist'], sd) - side(CTJ['elbow'], sd))
    BASE['Hand_' + sd] = rotdiff(segdir('Hand', sd), side(CTJ['fingertip'], sd) - side(CTJ['wrist'], sd))
INV = {v: k for k, v in MAP.items() if v}
I = Quaternion()
def apply_pose(D, T, frame):
    Deff = {}
    for b in sorted(arm.data.bones, key=chain_depth):
        if b.name in INV:
            k = INV[b.name]; d = D[k]
            if k in BASE: d = d @ BASE[k]
            Deff[b.name] = d
        else:
            Deff[b.name] = Deff[b.parent.name] if b.parent else I
    for b in arm.data.bones:
        pb = arm.pose.bones[b.name]
        Rb = b.matrix_local.to_3x3().normalized().to_quaternion()
        Dp = Deff[b.parent.name] if b.parent else I
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Rb.inverted() @ (Dp.inverted() @ Deff[b.name]) @ Rb
        pb.keyframe_insert('rotation_quaternion', frame=frame)
    hb = arm.pose.bones[MAP['Hips']]
    hb.location = REST['Hips'][0].inverted() @ T
    hb.keyframe_insert('location', frame=frame)

arm.animation_data_create()
frame = 0; manifest = []
for inj in 'RL':
    for name, fn, seated_flag, phase in ns['CLIPS']:
        keys = [(t, ns['to_vec'](p)) for t, p in fn(inj)]
        start = frame; dur = keys[-1][0]; nf = int(round(dur * FPS))
        for f in range(nf + 1):
            t = f / FPS
            i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
            if i >= len(keys) - 1: P = keys[-1][1]
            else:
                (t0, A), (t1, Bp) = keys[i], keys[i + 1]
                P = ns['lerp_pose'](A, Bp, ns['smooth01']((t - t0) / (t1 - t0)))
            D, T = ns['pose_to_D'](P)
            apply_pose(D, T, frame + f)
        frame += nf + 1
        manifest.append({'id': f'{name}_{inj}', 'exercise': name, 'side': inj, 'phase': phase, 'seated': seated_flag,
                         'start': round(start / FPS, 4), 'end': round((start + nf) / FPS, 4)})
bpy.context.scene.frame_start = 0; bpy.context.scene.frame_end = frame - 1
stool_y_rk = -(J['hip'].y + ns['T_SEATED'].y + 0.035)
json.dump({'fps': FPS, 'clips': manifest, 'stool': {'seatHeight': ns['SEAT_H'], 'z': round(stool_y_rk, 4), 'radius': 0.19},
           'height': round(max(v.z for v in all_verts()), 3), 'map': MAP,
           'source': 'Coach model: see Credits. Leg bones: BodyParts3D (c) DBCLS CC BY-SA 2.1 JP. Motion: original'},
          open(OUT + os.environ.get('RT_MAN','coach_clips_rt.json'), 'w'), indent=1)
arm.name = 'CoachRig'
for o in meshes:
    o.parent = arm; o.matrix_parent_inverse = Matrix.Identity(4)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=OUT + os.environ.get('RT_BLEND','coach_rt.blend'))
select_only([arm] + meshes + [bpy.data.objects[n] for n in ('Bones_R', 'Bones_L', 'InjuryGlow_R', 'InjuryGlow_L')])
bpy.ops.wm.usd_export(filepath=OUT + os.environ.get('RT_USD','Coach_rt.usdz'), selected_objects_only=True, export_animation=True, export_armatures=True,
                      only_deform_bones=False, export_materials=True, generate_preview_surface=True, export_textures_mode='NEW',
                      usdz_downscale_size='2048', export_normals=True, export_uvmaps=True, convert_orientation=True,
                      export_global_forward_selection='NEGATIVE_Z', export_global_up_selection='Y', triangulate_meshes=True,
                      evaluation_mode='RENDER')
print('frames', frame)
