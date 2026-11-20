"""Builds AnkleAnatomy.usdz (right foot & ankle, BodyParts3D) + anatomy_landmarks.json."""
import sys; sys.path.insert(0, 'build')
from common import *

reset()
CLIP = 0.165  # keep distal 16.5 cm of the leg

BONES = {
    'tibia': 'FMA24477', 'fibula': 'FMA24480', 'talus': 'FMA24482', 'calcaneus': 'FMA24497',
    'navicular': 'FMA24500', 'cuboid': 'FMA24528', 'cuneiform_medial': 'FMA24521',
    'cuneiform_intermediate': 'FMA24523', 'cuneiform_lateral': 'FMA24525',
    'metatarsal_1': 'FMA24507', 'metatarsal_2': 'FMA24509', 'metatarsal_3': 'FMA24511',
    'metatarsal_4': 'FMA24513', 'metatarsal_5': 'FMA24515',
}
PHAL = ['FMA43253', 'FMA32650', 'FMA32634', 'FMA32642', 'FMA32652', 'FMA32636', 'FMA32644', 'FMA32654',
        'FMA32638', 'FMA32646', 'FMA32656', 'FMA32640', 'FMA230986', 'FMA32658']
SOFT = {
    'fibularis_longus': 'FMA22552', 'fibularis_brevis': 'FMA22554', 'tibialis_anterior': 'FMA22544',
    'achilles_tendon': 'FMA258847', 'long_plantar_ligament': 'FMA44249',
}

bone_mat = material('Bone', (0.93, 0.89, 0.80), rough=0.55)
tendon_mat = material('Tendon', (0.86, 0.88, 0.92), rough=0.35)
muscle_mat = material('Muscle', (0.72, 0.22, 0.24), rough=0.6)

obs = {}
for n, f in BONES.items():
    o = import_stl(f, n)
    if n in ('tibia', 'fibula'):
        clip_above(o, CLIP)
    decimate(o, 0.55)
    assign(o, bone_mat); obs[n] = o
ph = [import_stl(f, 'p' + f) for f in PHAL]
for o in ph:
    decimate(o, 0.7)
toes = join(ph, 'phalanges'); assign(toes, bone_mat); obs['phalanges'] = toes
for n, f in SOFT.items():
    o = import_stl(f, n)
    clip_above(o, CLIP)
    decimate(o, 0.18 if n != 'achilles_tendon' else 0.2)
    assign(o, tendon_mat if n in ('achilles_tendon', 'long_plantar_ligament') else muscle_mat)
    obs[n] = o

# ---------- landmarks (world, before recentring) ----------
V = {n: verts_world(o) for n, o in obs.items()}
def argmin(vs, key): return min(vs, key=key)
def argmax(vs, key): return max(vs, key=key)

fib = V['fibula']; tib = V['tibia']; tal = V['talus']; cal = V['calcaneus']; nav = V['navicular']
fib_tip = argmin(fib, lambda v: v.z)
lat_mall = [v for v in fib if v.z < fib_tip.z + 0.018]
atfl_a = argmin(lat_mall, lambda v: v.y)                       # anterior border of lateral malleolus
tal_ant = [v for v in tal if v.y < min(w.y for w in tal) + 0.022]
atfl_b = argmin(tal_ant, lambda v: v.x)                         # lateral talar neck
cfl_a = argmin(lat_mall, lambda v: v.z)                         # malleolar tip
cal_lat = [v for v in cal if abs(v.y - (fib_tip.y + 0.012)) < 0.008 and v.z < 0.035]
cfl_b = argmin(cal_lat, lambda v: v.x)                          # lateral calcaneal wall
ptfl_a = argmax(lat_mall, lambda v: v.y)                        # posterior malleolus
tal_post = [v for v in tal if v.y > max(w.y for w in tal) - 0.012]
ptfl_b = argmin(tal_post, lambda v: v.x)                        # posterolateral talar tubercle
med_mall = argmin(tib, lambda v: v.z - 0.6 * v.x)               # medial malleolus tip (medial = +x)
del_nav = argmax(nav, lambda v: v.x)
del_tal = argmax([v for v in tal if v.z < 0.05], lambda v: v.x)
del_cal = argmax([v for v in cal if v.z > 0.02], lambda v: v.x)  # sustentaculum tali
dist_tib = [v for v in tib if v.z < 0.085 and v.z > 0.065]
aitfl_a = argmin(dist_tib, lambda v: v.y + 0.4 * v.x)
dist_fib = [v for v in fib if v.z < 0.085 and v.z > 0.065]
aitfl_b = argmin(dist_fib, lambda v: v.y)
tal_top = argmax(tal, lambda v: v.z)
ankle_c = Vector(((min(v.x for v in tal) + max(v.x for v in tal)) / 2, tal_top.y, tal_top.z - 0.012))

# ---------- recentre: origin at (bbox centre x/y, min z) ----------
allv = [v for vs in V.values() for v in vs]
O = Vector(((min(v.x for v in allv) + max(v.x for v in allv)) / 2,
            (min(v.y for v in allv) + max(v.y for v in allv)) / 2,
            min(v.z for v in allv)))
for o in obs.values():
    o.data.transform(Matrix.Translation(-O))
    smooth(o)

root = bpy.data.objects.new('AnkleModel', None); bpy.context.scene.collection.objects.link(root)
leg = bpy.data.objects.new('Leg', None); bpy.context.scene.collection.objects.link(leg); leg.parent = root
foot = bpy.data.objects.new('Foot', None); bpy.context.scene.collection.objects.link(foot); foot.parent = root
foot.location = ankle_c - O
bpy.context.view_layer.update()
for n, o in obs.items():
    if n in ('tibia', 'fibula', 'fibularis_longus', 'fibularis_brevis', 'tibialis_anterior', 'achilles_tendon'):
        o.parent = leg
    else:
        o.parent = foot
        o.matrix_parent_inverse = foot.matrix_world.inverted()
bpy.context.view_layer.update()

def P(v): return to_rk(v - O)
ligs = {
    'ATFL': {'a': P(atfl_a), 'b': P(atfl_b), 'r': 0.0035, 'bAttach': 'Foot'},
    'CFL': {'a': P(cfl_a), 'b': P(cfl_b), 'r': 0.0030, 'bAttach': 'Foot'},
    'PTFL': {'a': P(ptfl_a), 'b': P(ptfl_b), 'r': 0.0032, 'bAttach': 'Foot'},
    'AITFL': {'a': P(aitfl_a), 'b': P(aitfl_b), 'r': 0.0030, 'bAttach': 'Leg'},
    'Deltoid_TN': {'a': P(med_mall), 'b': P(del_nav), 'r': 0.0030, 'bAttach': 'Foot'},
    'Deltoid_TC': {'a': P(med_mall), 'b': P(del_cal), 'r': 0.0035, 'bAttach': 'Foot'},
    'Deltoid_TT': {'a': P(med_mall), 'b': P(del_tal), 'r': 0.0035, 'bAttach': 'Foot'},
}
size = [round(max(v.x for v in allv) - min(v.x for v in allv), 4),
        round(max(v.z for v in allv) - min(v.z for v in allv), 4),
        round(max(v.y for v in allv) - min(v.y for v in allv), 4)]
json.dump({'anklePivot': P(ankle_c), 'ligaments': ligs, 'sizeMeters': size,
           'source': 'BodyParts3D (c) DBCLS, CC BY-SA 2.1 JP'},
          open(OUT + 'anatomy_landmarks.json', 'w'), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=OUT + 'anatomy.blend')
export_usdz(OUT + 'AnkleAnatomy.usdz')
print('faces', sum(len(o.data.polygons) for o in obs.values()), 'size', size)
