"""Builds Coach.usdz: CT-derived human (BodyParts3D skin), clothed, skinned and animated with
clinically-based ankle-rehab exercises for a right- and left-injured ankle. Writes coach_clips.json."""
import sys; sys.path.insert(0, '/home/claude/build')
from common import *
from mathutils import Quaternion
import math

bpy.ops.wm.open_mainfile(filepath=OUT + 'body.blend')
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)
body = bpy.data.objects['Body']
FPS = 30
bpy.context.scene.render.fps = FPS

# ---------- keep the main skin island only ----------
bm = bmesh.new(); bm.from_mesh(body.data); bm.verts.ensure_lookup_table()
seen = {}; comp_id = 0; sizes = []
for v in bm.verts:
    if v.index in seen: continue
    stack = [v]; n = 0
    while stack:
        x = stack.pop()
        if x.index in seen: continue
        seen[x.index] = comp_id; n += 1
        stack.extend(e.other_vert(x) for e in x.link_edges if e.other_vert(x).index not in seen)
    sizes.append(n); comp_id += 1
main = max(range(len(sizes)), key=lambda i: sizes[i])
bmesh.ops.delete(bm, geom=[v for v in bm.verts if seen[v.index] != main], context='VERTS')
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
bm.to_mesh(body.data); bm.free()

J = {k: Vector(v) for k, v in json.load(open(OUT + 'joints.json')).items()}

def side(v, s):  # joints.json stores the right side (x < 0)
    return Vector((v.x if s == 'R' else -v.x, v.y, v.z))

# ---------- armature ----------
arm_data = bpy.data.armatures.new('CoachRig'); rig = bpy.data.objects.new('CoachRig', arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones
def bone(name, h, t, parent=None):
    b = eb.new(name); b.head = h; b.tail = t
    if parent: b.parent = eb[parent]
    b.use_connect = False
    return b
bone('Hips', J['pelvis'], J['spine'])
bone('Spine', J['spine'], J['chest'], 'Hips')
bone('Chest', J['chest'], J['neck'], 'Spine')
bone('Neck', J['neck'], J['headbase'], 'Chest')
bone('Head', J['headbase'], J['headtop'], 'Neck')
for s in 'RL':
    bone('Thigh_' + s, side(J['hip'], s), side(J['knee'], s), 'Hips')
    bone('Shin_' + s, side(J['knee'], s), side(J['ankle'], s), 'Thigh_' + s)
    bone('Foot_' + s, side(J['ankle'], s), side(J['mtp'], s), 'Shin_' + s)
    bone('Toe_' + s, side(J['mtp'], s), side(J['toe'], s), 'Foot_' + s)
    bone('UpperArm_' + s, side(J['shoulder'], s), side(J['elbow'], s), 'Chest')
    bone('ForeArm_' + s, side(J['elbow'], s), side(J['wrist'], s), 'UpperArm_' + s)
    bone('Hand_' + s, side(J['wrist'], s), side(J['fingertip'], s), 'ForeArm_' + s)
bpy.ops.object.mode_set(mode='OBJECT')
REST = {b.name: (b.matrix_local.to_3x3().normalized().to_quaternion(), b.head_local.copy()) for b in arm_data.bones}
PARENT = {b.name: (b.parent.name if b.parent else None) for b in arm_data.bones}

# ---------- skin weights (bone heat) ----------
# bone-heat fails on metre-scale meshes; solve at 10x scale, then restore
for o in (body, rig): o.scale = (10, 10, 10)
bpy.context.view_layer.update()
select_only([body, rig]); bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
select_only([body]); bpy.ops.object.parent_clear(type='CLEAR')
body.modifiers.clear()
for o in (body, rig): o.scale = (1, 1, 1)
body.parent = rig
mod = body.modifiers.new('Armature', 'ARMATURE'); mod.object = rig
bpy.context.view_layer.update()
# ---------- modesty: flatten groin region into a smooth "shorts" surface ----------
bm = bmesh.new(); bm.from_mesh(body.data); bm.verts.ensure_lookup_table()
def fall(v):
    c = v.co
    if c.y > -0.02: return 0.0
    dx = abs(c.x) / 0.085; dz = abs(c.z - 0.775) / 0.105
    d = max(dx, dz)
    return max(0.0, min(1.0, (1.15 - d) / 0.35))
W = [fall(v) for v in bm.verts]
for it in range(140):
    new_co = {}
    for v in bm.verts:
        w = W[v.index]
        if w <= 0: continue
        nb = [e.other_vert(v).co for e in v.link_edges]
        avg = sum(nb, Vector()) / len(nb)
        new_co[v.index] = v.co.lerp(avg, 0.6 * w)
    for i, co in new_co.items(): bm.verts[i].co = co
bm.to_mesh(body.data); bm.free()
empty_groups = [g.name for g in body.vertex_groups]
print('vertex groups', empty_groups)

# ---------- clothing from dominant-bone classification ----------
def dominant(v):
    best = max(v.groups, key=lambda g: g.weight, default=None)
    return body.vertex_groups[best.group].name if best else None
dom = [dominant(v) for v in body.data.vertices]
me = body.data
def face_dom(p):
    names = [dom[i] for i in p.vertices]
    return max(set(names), key=names.count)
def along(p, bname):
    h = REST[bname][1]; t = arm_data.bones[bname].tail_local
    ax = (t - h).normalized()
    return (p.center - h).dot(ax)
WAIST = 0.955; NECK = J['neck'].z - 0.02
def region(p):
    d = face_dom(p); c = p.center; z = c.z
    if d is None: return 'Skin'
    if d.startswith(('ForeArm', 'Hand', 'Shin', 'Foot', 'Toe', 'Head')): return 'Skin'
    if d.startswith('UpperArm'):
        return 'Shirt' if (along(p, d) < 0.125 or (abs(c.x) < 0.16 and WAIST < z < NECK)) else 'Skin'
    if d.startswith('Thigh'):
        return 'Shorts' if (along(p, d) < 0.25 and z > 0.5) else 'Skin'
    if WAIST < z < NECK and d != 'Neck': return 'Shirt'
    if z <= WAIST and d in ('Hips', 'Spine'): return 'Shorts'
    return 'Skin'
skin_mat = material('Skin', (0.78, 0.58, 0.47), rough=0.55)
shirt_mat = material('Shirt', (0.12, 0.52, 0.58), rough=0.8)
shorts_mat = material('Shorts', (0.11, 0.12, 0.15), rough=0.85)
me.materials.clear()
for m in (skin_mat, shirt_mat, shorts_mat): me.materials.append(m)
IDX = {'Skin': 0, 'Shirt': 1, 'Shorts': 2}
regs = [region(p) for p in me.polygons]
# majority filter twice to clean jagged hems
adj = {}
for e in me.edges:
    pass
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
for _ in range(6):
    newr = list(regs)
    for f in bm.faces:
        nb = [regs[g.index] for e in f.edges for g in e.link_faces if g.index != f.index]
        if nb:
            best = max(set(nb), key=nb.count)
            if nb.count(best) >= 2 and best != regs[f.index]: newr[f.index] = best
    regs = newr
bm.free()
for p, r in zip(me.polygons, regs): p.material_index = IDX[r]
shirt = shorts = None

# ---------- internal skeleton of both lower legs (rigid weights) ----------
bone_mat = material('Bone', (0.93, 0.89, 0.80), rough=0.5)
glow_mat = material('InjuryGlow', (1.0, 0.25, 0.3), rough=0.3, emission=(1.0, 0.2, 0.25))
GROUPS = {'Shin': ['FMA24477', 'FMA24480'],
          'Foot': ['FMA24482', 'FMA24497', 'FMA24500', 'FMA24528', 'FMA24521', 'FMA24523', 'FMA24525',
                   'FMA24507', 'FMA24509', 'FMA24511', 'FMA24513', 'FMA24515'],
          'Toe': ['FMA43253', 'FMA32650', 'FMA32634', 'FMA32642', 'FMA32652', 'FMA32636', 'FMA32644', 'FMA32654',
                  'FMA32638', 'FMA32646', 'FMA32656', 'FMA32640', 'FMA230986', 'FMA32658']}
lig = json.load(open(OUT + 'anatomy_landmarks.json'))
for s in 'RL':
    parts = []
    for grp, ids in GROUPS.items():
        for f in ids:
            o = import_stl(f, f + s)
            o.data.transform(Matrix.Translation((0, 0, 0.0134)))
            decimate(o, 0.3 if grp != 'Toe' else 0.5)
            if s == 'L':
                for v in o.data.vertices: v.co.x = -v.co.x
                o.data.flip_normals()
            vg = o.vertex_groups.new(name=f'{grp}_{s}')
            vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
            parts.append(o)
    bones_ob = join(parts, 'Bones_' + s); assign(bones_ob, bone_mat); smooth(bones_ob)
    # glowing marker over the lateral ligament complex (ATFL / CFL)
    a = Vector(J['ankle']); a.x = side(J['ankle'], s).x
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, segments=24, ring_count=12,
                                         location=(a.x + (-0.03 if s == 'R' else 0.03), a.y - 0.015, a.z - 0.022))
    g = bpy.context.active_object; g.name = 'InjuryGlow_' + s; g.data.name = g.name
    g.scale = (0.6, 1.0, 0.75); bpy.ops.object.transform_apply(scale=True)
    vg = g.vertex_groups.new(name='Foot_' + s); vg.add(list(range(len(g.data.vertices))), 1.0, 'REPLACE')
    assign(g, glow_mat)
    for o in (bones_ob, g):
        o.parent = rig
        m = o.modifiers.new('Armature', 'ARMATURE'); m.object = rig

for o in (body,):
    select_only([o])
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    smooth(o, 60)

# =====================================================================
#                       ANIMATION (analytic FK / 2-bone IK)
# =====================================================================
def RX(d): return Quaternion((1, 0, 0), math.radians(d))
def RY(d): return Quaternion((0, 1, 0), math.radians(d))
def RZ(d): return Quaternion((0, 0, 1), math.radians(d))
I = Quaternion()
SG = {'R': 1, 'L': -1}
L1 = (J['knee'] - J['hip']).length; L2 = (J['ankle'] - J['knee']).length

def frame_from(dirv, fwd):
    y = dirv.normalized(); z = (fwd - y * fwd.dot(y)).normalized(); x = y.cross(z)
    return Matrix((x, y, z)).transposed()

def solve_leg(hip, ankle, pole):
    d = ankle - hip; dl = min(d.length, L1 + L2 - 1e-4); dh = d.normalized()
    a = (L1 * L1 - L2 * L2 + dl * dl) / (2 * dl); h = math.sqrt(max(L1 * L1 - a * a, 0))
    n = (pole - dh * pole.dot(dh)).normalized()
    knee = hip + dh * a + n * h
    return knee, (knee - hip).normalized(), (hip + dh * dl - knee).normalized(), n

def leg_quats(s, hip, ankle_target, pole):
    knee, u1, u2, n = solve_leg(hip, ankle_target, pole)
    r_hip, r_knee, r_ank = side(J['hip'], s), side(J['knee'], s), side(J['ankle'], s)
    fwd_rest = Vector((0, -1, 0))
    Dt = (frame_from(u1, n) @ frame_from(r_knee - r_hip, fwd_rest).inverted()).to_quaternion()
    Ds = (frame_from(u2, n) @ frame_from(r_ank - r_knee, fwd_rest).inverted()).to_quaternion()
    return Dt, Ds

def pose_to_D(P):
    """P = pose dict -> absolute armature-space delta rotation per bone + hips translation."""
    D = {}
    T = Vector(P.get('T', (0, 0, 0)))
    D['Hips'] = P.get('hips', I)
    D['Spine'] = D['Hips'] @ P.get('spine', I)
    D['Chest'] = D['Spine'] @ P.get('chest', I)
    D['Neck'] = D['Chest'] @ P.get('neck', I)
    D['Head'] = D['Neck'] @ P.get('head', I)
    hips_head = REST['Hips'][1]
    for s in 'RL':
        hip = hips_head + T + D['Hips'] @ (side(J['hip'], s) - hips_head)
        legs = P['legs'][s]
        ank = Vector(legs['ankle'])
        pole = Vector(legs.get('pole', (0, -1, 0.15)))
        D['Thigh_' + s], D['Shin_' + s] = leg_quats(s, hip, ank, pole)
        D['Foot_' + s] = legs.get('foot', I)
        D['Toe_' + s] = legs.get('toe', D['Foot_' + s] if 'toe' not in legs else legs['toe'])
        a = P['arms'][s]
        D['UpperArm_' + s] = D['Chest'] @ a.get('upper', I)
        D['ForeArm_' + s] = D['UpperArm_' + s] @ a.get('fore', I)
        D['Hand_' + s] = D['ForeArm_' + s] @ a.get('hand', I)
    return D, T

def apply_pose(D, T, frame):
    for name, pb in rig.pose.bones.items():
        Rb = REST[name][0]; p = PARENT[name]
        Dp = D[p] if p else I
        local = Rb.inverted() @ (Dp.inverted() @ D[name]) @ Rb
        pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = local
        pb.keyframe_insert('rotation_quaternion', frame=frame)
    hb = rig.pose.bones['Hips']
    hb.location = REST['Hips'][0].inverted() @ T
    hb.keyframe_insert('location', frame=frame)

# ---------- pose vocabulary ----------
def ankle_rest(s): return side(J['ankle'], s)
def mtp_rest(s): return side(J['mtp'], s)
def heel_raise(s, deg, offset=(0, 0, 0)):
    """Foot plantarflexed about the MTP joint (toes stay on the floor)."""
    m = mtp_rest(s) + Vector(offset)
    ank = m + RX(deg) @ (ankle_rest(s) - mtp_rest(s))
    return {'ankle': ank, 'foot': RX(deg), 'toe': I}
def planted(s, offset=(0, 0, 0), foot=I):
    return {'ankle': ankle_rest(s) + Vector(offset), 'foot': foot, 'toe': foot}
PRON = 70  # forearm pronation so palms face the body / downwards (natural pose)
def arms_relaxed(abd=6, elbow=12):
    return {s: {'upper': RY(abd * SG[s]) @ RZ(25 * SG[s]), 'fore': RX(-elbow) @ RZ(PRON * 0.6 * SG[s])} for s in 'RL'}
def arms(fR, aR, eR, fL=None, aL=None, eL=None):
    fL = fR if fL is None else fL; aL = aR if aL is None else aL; eL = eR if eL is None else eL
    return {'R': {'upper': RX(-fR) @ RY(aR), 'fore': RX(-eR) @ RZ(PRON)},
            'L': {'upper': RX(-fL) @ RY(-aL), 'fore': RX(-eL) @ RZ(-PRON)}}

SEAT_H = 0.46
HIP_SEATED_Z = SEAT_H + 0.085
T_SEATED = Vector((0, 0.06, HIP_SEATED_Z - J['hip'].z))
def seated_feet(s, fwd=0.40):
    hipy = J['hip'].y + T_SEATED.y
    return Vector((side(J['ankle'], s).x * 1.15, hipy - fwd, J['ankle'].z))
ARMS_SEATED = arms(22, 10, 68)
def seated(inj, inj_leg=None, trunk=4):
    o = 'L' if inj == 'R' else 'R'
    legs = {o: {'ankle': seated_feet(o), 'foot': I, 'toe': I}}
    legs[inj] = inj_leg or {'ankle': seated_feet(inj), 'foot': I, 'toe': I}
    return {'T': T_SEATED, 'spine': RX(trunk), 'legs': legs, 'arms': ARMS_SEATED}

def stance_shift(s, amt=0.85):
    return ankle_rest(s).x * amt

# Each clip: list of (time_s, pose_fn(inj)) keys; looped clips repeat their first key at the end.
def standing(inj, T=(0, 0, 0), **kw):
    P = {'T': Vector(T), 'legs': {'R': planted('R'), 'L': planted('L')}, 'arms': arms_relaxed()}
    P.update(kw); return P

def C_idle(inj):
    return [(0, standing(inj)), (2, standing(inj, T=(0, 0, -0.004), chest=RX(-2))), (4, standing(inj))]

def C_seated_idle(inj):
    return [(0, seated(inj)), (2, dict(seated(inj), chest=RX(-2))), (4, seated(inj))]

def lifted_seated(inj, foot):
    hipy = J['hip'].y + T_SEATED.y
    ank = Vector((side(J['ankle'], inj).x * 1.1, hipy - 0.56, 0.19))
    return {'ankle': ank, 'foot': foot, 'toe': foot}

def C_ankle_pumps(inj):
    k = []
    for i, (t, a) in enumerate([(0, 0), (1.0, -18), (2.0, 0), (3.0, 32), (4.0, 0)]):
        k.append((t, seated(inj, lifted_seated(inj, RX(a)))))
    return k

def C_ankle_alphabet(inj):
    k = []
    for i in range(9):
        t = i * 0.75; th = 2 * math.pi * i / 8
        f = RX(12 + 16 * math.sin(th)) @ RY(-16 * math.cos(th) * SG[inj])
        k.append((t, seated(inj, lifted_seated(inj, f))))
    return k

def C_seated_eversion(inj):
    ev = lambda d: seated(inj, {'ankle': seated_feet(inj) + Vector((0, 0, 0.012)), 'foot': RY(d * SG[inj]), 'toe': RY(d * SG[inj])})
    return [(0, ev(0)), (1.2, ev(18)), (2.2, ev(18)), (3.5, ev(0)), (4.5, ev(0))]

def C_calf_raise(inj):
    up = lambda d: {'R': heel_raise('R', d), 'L': heel_raise('L', d)}
    def P(d):
        rise = (heel_raise('R', d)['ankle'] - ankle_rest('R')).z
        return {'T': Vector((0, -0.01, rise * 0.97)), 'legs': up(d), 'arms': arms(48, 6, 35)}
    return [(0, P(0)), (1.4, P(26)), (2.0, P(26)), (3.6, P(0)), (4.2, P(0))]

def sls(inj, T=None, lift_back=0.12, lift_up=0.26, **kw):
    """Single-leg stance on the injured leg, other leg lifted behind."""
    o = 'L' if inj == 'R' else 'R'
    Tv = Vector((stance_shift(inj), -0.012, -0.004)) if T is None else Vector(T)
    legs = {inj: planted(inj), o: {'ankle': ankle_rest(o) + Vector((0, lift_back, lift_up)) + Vector((Tv.x * 0.6, Tv.y, Tv.z)),
                                     'foot': RX(18), 'toe': RX(18)}}
    P = {'T': Tv, 'legs': legs, 'arms': kw.pop('arms', arms(10, 22, 18)), 'hips': RY(-3 * SG[inj])}
    P.update(kw); return P

def C_single_leg_stance(inj):
    sx = stance_shift(inj)
    return [(0, sls(inj)), (1.5, sls(inj, T=(sx + 0.004, -0.018, -0.004))), (3, sls(inj, T=(sx - 0.003, -0.008, -0.004))),
            (4.5, sls(inj, T=(sx + 0.002, -0.014, -0.004))), (6, sls(inj))]

def C_sls_reach_catch(inj):
    """Single-leg stance + reaching to catch a ball (perturbation / dual-task)."""
    sx = stance_shift(inj)
    reachR = arms(85, 32, 8, 15, 20, 15); reachL = arms(15, 20, 15, 85, 32, 8); both = arms(70, 8, 25)
    return [(0, sls(inj)),
            (1.0, sls(inj, arms=reachR, chest=RZ(-12), T=(sx - 0.01, -0.02, -0.006))),
            (2.0, sls(inj)),
            (3.0, sls(inj, arms=reachL, chest=RZ(12), T=(sx + 0.008, -0.02, -0.006))),
            (4.0, sls(inj)),
            (5.0, sls(inj, arms=both, chest=RX(6), T=(sx, -0.03, -0.01))),
            (6.0, sls(inj))]

def C_sls_head_turns(inj):
    return [(0, sls(inj)), (1.2, sls(inj, head=RZ(40), neck=RZ(15))), (2.4, sls(inj)),
            (3.6, sls(inj, head=RZ(-40), neck=RZ(-15))), (4.8, sls(inj))]

def C_sl_mini_squat(inj):
    sx = stance_shift(inj)
    down = lambda: sls(inj, T=(sx, 0.03, -0.075), spine=RX(16), arms=arms(55, 10, 10), lift_back=0.2, lift_up=0.2)
    return [(0, sls(inj)), (1.6, down()), (2.3, down()), (4.0, sls(inj)), (4.6, sls(inj))]

def C_sl_calf_raise(inj):
    o = 'L' if inj == 'R' else 'R'; sx = stance_shift(inj)
    def P(d):
        hr = heel_raise(inj, d); rise = (hr['ankle'] - ankle_rest(inj)).z
        Pp = sls(inj, T=(sx, -0.02, rise * 0.96 - 0.004), arms=arms(45, 12, 35))
        Pp['legs'][inj] = hr
        Pp['legs'][o]['ankle'] = Pp['legs'][o]['ankle'] + Vector((0, 0, rise))
        return Pp
    return [(0, P(0)), (1.4, P(24)), (2.0, P(24)), (3.6, P(0)), (4.2, P(0))]

def C_knee_to_wall(inj):
    o = 'L' if inj == 'R' else 'R'
    def P(f):
        legs = {inj: planted(inj, (0, -0.24, 0)), o: heel_raise(o, 18, (0, 0.30, 0))}
        T = Vector((0, -0.05 - 0.07 * f, -0.03 - 0.06 * f))
        return {'T': T, 'legs': legs, 'arms': arms(72, 6, 32), 'spine': RX(4 + 4 * f)}
    return [(0, P(0)), (1.5, P(1)), (2.5, P(1)), (4.0, P(0)), (4.5, P(0))]

def C_hop_forward(inj):
    o = 'L' if inj == 'R' else 'R'; sx = stance_shift(inj)
    def H(dy, up=0.0, crouch=0.0, air=False, pf=0):
        Tv = (sx, -0.012 + dy, -0.004 - crouch + up)
        P = sls(inj, T=Tv, spine=RX(10 * (crouch > 0) + 6 * air), arms=arms(30 if air else 15, 20, 30 if air else 18))
        P['legs'][inj] = planted(inj, (0, dy, up), foot=RX(pf), ) if air else planted(inj, (0, dy, 0))
        if not air and crouch:
            pass
        return P
    return [(0, H(0)), (0.5, H(0, crouch=0.06)), (0.8, H(-0.18, up=0.09, air=True, pf=20)),
            (1.05, H(-0.35, crouch=0.07)), (2.2, H(-0.35)), (2.7, H(-0.35, crouch=0.06)),
            (3.0, H(-0.17, up=0.09, air=True, pf=20)), (3.25, H(0, crouch=0.07)), (4.4, H(0))]

def C_side_hop(inj):
    sx = stance_shift(inj); g = -SG[inj]  # hop toward the injured side's lateral direction
    def H(dx, up=0.0, crouch=0.0, air=False):
        P = sls(inj, T=(sx + dx, -0.012, -0.004 - crouch + up), arms=arms(20, 30, 25), spine=RX(8 * (crouch > 0)))
        P['legs'][inj] = planted(inj, (dx, 0, up), foot=RX(15) if air else I)
        o = 'L' if inj == 'R' else 'R'
        P['legs'][o]['ankle'] = P['legs'][o]['ankle'] + Vector((dx, 0, up))
        return P
    return [(0, H(0)), (0.5, H(0, crouch=0.06)), (0.75, H(0.15 * g, up=0.07, air=True)), (1.0, H(0.30 * g, crouch=0.07)),
            (2.0, H(0.30 * g)), (2.5, H(0.30 * g, crouch=0.06)), (2.75, H(0.15 * g, up=0.07, air=True)),
            (3.0, H(0, crouch=0.07)), (4.0, H(0))]

def C_step_beat(inj):
    """Rhythm-step pattern (both feet, low impact): front, side, back, centre."""
    o = 'L' if inj == 'R' else 'R'; beat = 0.6
    def S(s, off):
        P = standing(inj, T=(Vector(off).x * 0.5 if s else 0, Vector(off).y * 0.5 if s else 0, -0.01), arms=arms(25, 15, 45))
        if s: P['legs'][s] = planted(s, off)
        return P
    k = [(0, S(None, (0, 0, 0)))]
    seq = [(inj, (0, -0.28, 0)), (None, (0, 0, 0)), (o, (0, -0.28, 0)), (None, (0, 0, 0)),
           (inj, (-0.26 * SG[inj], 0, 0)), (None, (0, 0, 0)), (o, (-0.26 * SG[o], 0, 0)), (None, (0, 0, 0))]
    for i, (s, off) in enumerate(seq):
        k.append(((i + 1) * beat, S(s, off)))
    return k

CLIPS = [
    ('idle', C_idle, False, 'all'),
    ('seated_idle', C_seated_idle, True, 'all'),
    ('ankle_pumps', C_ankle_pumps, True, 'protect'),
    ('ankle_alphabet', C_ankle_alphabet, True, 'protect'),
    ('seated_eversion', C_seated_eversion, True, 'load'),
    ('calf_raise', C_calf_raise, False, 'load'),
    ('knee_to_wall', C_knee_to_wall, False, 'load'),
    ('single_leg_stance', C_single_leg_stance, False, 'balance'),
    ('sls_reach_catch', C_sls_reach_catch, False, 'balance'),
    ('sls_head_turns', C_sls_head_turns, False, 'balance'),
    ('sl_mini_squat', C_sl_mini_squat, False, 'balance'),
    ('sl_calf_raise', C_sl_calf_raise, False, 'return'),
    ('hop_forward', C_hop_forward, False, 'return'),
    ('side_hop', C_side_hop, False, 'return'),
    ('step_beat', C_step_beat, False, 'return'),
]

def smooth01(x): return x * x * (3 - 2 * x)
def lerp_pose(A, B, u):
    out = {}
    for k in set(A) | set(B):
        a, b = A.get(k), B.get(k)
        if a is None: a = I if isinstance(b, Quaternion) else b
        if b is None: b = I if isinstance(a, Quaternion) else a
        if isinstance(a, Quaternion): out[k] = a.slerp(b, u)
        elif isinstance(a, Vector): out[k] = a.lerp(b, u)
        elif isinstance(a, dict): out[k] = lerp_pose(a, b, u)
        else: out[k] = a
    return out
def to_vec(P):
    for k, v in list(P.items()):
        if isinstance(v, dict): to_vec(v)
        elif isinstance(v, (tuple, list)) and len(v) == 3: P[k] = Vector(v)
    return P

rig.animation_data_create()
frame = 0; manifest = []
for inj in 'RL':
    for name, fn, seated_flag, phase in CLIPS:
        keys = [(t, to_vec(p)) for t, p in fn(inj)]
        start = frame; dur = keys[-1][0]
        nf = int(round(dur * FPS))
        for f in range(nf + 1):
            t = f / FPS
            i = max(j for j in range(len(keys)) if keys[j][0] <= t + 1e-9)
            if i >= len(keys) - 1: P = keys[-1][1]
            else:
                (t0, A), (t1, B) = keys[i], keys[i + 1]
                P = lerp_pose(A, B, smooth01((t - t0) / (t1 - t0)))
            D, T = pose_to_D(P)
            apply_pose(D, T, frame + f)
        frame += nf + 1
        manifest.append({'id': f'{name}_{inj}', 'exercise': name, 'side': inj, 'phase': phase, 'seated': seated_flag,
                         'start': round(start / FPS, 4), 'end': round((start + nf) / FPS, 4)})
bpy.context.scene.frame_start = 0; bpy.context.scene.frame_end = frame - 1
for fc in rig.animation_data.action.fcurves if hasattr(rig.animation_data.action, 'fcurves') else []:
    for kp in fc.keyframe_points: kp.interpolation = 'LINEAR'

stool_y_rk = -(J['hip'].y + T_SEATED.y + 0.035)
json.dump({'fps': FPS, 'clips': manifest, 'stool': {'seatHeight': SEAT_H, 'z': round(stool_y_rk, 4), 'radius': 0.19},
           'height': round(J['headtop'].z, 3), 'source': 'Body: BodyParts3D (c) DBCLS CC BY-SA 2.1 JP; rig & motion: original'},
          open(OUT + 'coach_clips.json', 'w'), indent=1)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=OUT + 'coach.blend')
select_only([rig, body] + [bpy.data.objects[n] for n in ('Bones_R', 'Bones_L', 'InjuryGlow_R', 'InjuryGlow_L')])
export_usdz(OUT + 'Coach.usdz', animation=True, armatures=True)
print('frames', frame, 'faces body', len(body.data.polygons), 'regions', {k: regs.count(k) for k in IDX})
