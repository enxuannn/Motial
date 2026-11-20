"""Adds speaking and shooting to the two life-size coaches (Maya = CoachFitness, Alex = CoachScan).

1. A new "Jaw" bone (child of the head) with the lower face (chin, lower lip, jaw line) weighted to it, so the mouth can
   open and close. The scanned meshes have no face rig or blend shapes; a small jaw rotation (max ~9°) reads as talking
   without tearing the closed-mouth scan.
2. New clips appended after the existing timeline (30 fps, same JSON manifest as the motion library):
     talk_R/L          standing, explaining gestures, gentle head nods, jaw "syllables"     (6 s loop)
     seated_talk_R/L   the same, seated on the stool                                       (6 s loop)
     set_shot_R/L      basketball set shot: ball at chest, rise onto the toes, release, hold the finish (2.6 s)
   Hands are posed with IK (empties along a path), then visually baked so the result is plain bone keys.
3. Exports <Coach>.usdz and updates <coach>_clips.json (adds the clips and the "shot" ball points used in Sport Lab).

Usage:  python3 coach_talk_shot.py <in_dir> <out_dir>
"""
import bpy, sys, json, math, os
import numpy as np
from mathutils import Vector, Matrix, Quaternion

IN, OUT = sys.argv[-2], sys.argv[-1]
os.makedirs(OUT, exist_ok=True)
FPS = 30

CFG = {
    'CoachFitness': dict(json='coach_fitness_clips.json', mouth=1.478, chin=1.440, front=-0.112, meshes=['Body'],
                         jaw_max=10.0),
    'CoachScan': dict(json='coach_scan_clips.json', mouth=1.548, chin=1.500, front=-0.112, meshes=['Body'],
                      jaw_max=12.0),
}


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def run(name):
    cfg = CFG[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=f'{IN}/{name}.usdz')
    sc = bpy.context.scene
    sc.render.fps = FPS
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    man = json.load(open(f'{IN}/{cfg["json"]}'))
    bmap = man['map']
    act = arm.animation_data.action
    clips = {c['id']: c for c in man['clips']}
    last_end = max(c['end'] for c in man['clips'])
    print(name, 'action', act.name, 'last clip end', last_end, flush=True)

    # ---------- 1. jaw bone ----------
    head_b = arm.data.bones[bmap['Head']]
    Mw = arm.matrix_world
    pivot = Vector((0.0, cfg['front'] + 0.085, cfg['mouth'] + 0.035))      # ~TMJ: in front of the ear, above the mouth line
    chin_tip = Vector((0.0, cfg['front'] + 0.02, cfg['chin'] + 0.005))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    jaw = eb.new('Jaw')
    inv = Mw.inverted()
    jaw.head = inv @ pivot
    jaw.tail = inv @ chin_tip
    jaw.parent = eb[bmap['Head']]
    jaw.use_deform = True
    jaw.roll = 0
    bpy.ops.object.mode_set(mode='OBJECT')

    for mname in cfg['meshes']:
        o = bpy.data.objects[mname]
        M = o.matrix_world
        V = np.array([tuple(M @ v.co) for v in o.data.vertices])
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        m = cfg['mouth']; c = cfg['chin']
        w = (1 - smooth(m - 0.006, m + 0.004, z))                 # stops at the lip line
        w *= smooth(c - 0.040, c - 0.008, z)                       # fades out into the neck
        w *= 1 - smooth(0.040, 0.072, np.abs(x))                   # fades towards the ears
        w *= 1 - smooth(pivot.y - 0.035, pivot.y + 0.005, y)       # only in front of the jaw joint
        idx = np.nonzero(w > 0.01)[0]
        g = o.vertex_groups.get('Jaw') or o.vertex_groups.new(name='Jaw')
        for i in idx:
            wi = float(w[i])
            v = o.data.vertices[int(i)]
            for ge in v.groups:
                ge.weight *= (1 - wi)
            g.add([int(i)], wi, 'REPLACE')
        print(' jaw weights on', mname, len(idx), 'verts', flush=True)

    # ---------- helpers ----------
    pb = arm.pose.bones
    for b in pb:
        b.rotation_mode = 'QUATERNION'
    names = [b.name for b in pb]

    def sample(frame):
        sc.frame_set(int(frame), subframe=frame - int(frame))
        return {n: (pb[n].location.copy(), pb[n].rotation_quaternion.copy()) for n in names}

    def put(frame, pose):
        for n, (l, r) in pose.items():
            pb[n].location = l; pb[n].rotation_quaternion = r
            pb[n].keyframe_insert('location', frame=frame); pb[n].keyframe_insert('rotation_quaternion', frame=frame)

    def world_head(bname, frame):
        sc.frame_set(int(frame)); return Mw @ pb[bname].head

    def world_axis_in_bone(bname, axis_world):
        """A world axis expressed in the bone's local (rest) frame, for delta rotations."""
        rest = (Mw.to_3x3() @ arm.data.bones[bname].matrix_local.to_3x3())
        return (rest.inverted() @ Vector(axis_world)).normalized()

    start_f = math.ceil(last_end * FPS) + 30
    new_clips = []
    shot_points = {}

    def make_clip(cid, base_id, dur, seated, hands_fn, retime=None, head_fn=None, jaw_fn=None, exercise=None):
        nonlocal start_f
        base = clips[base_id + '_R']
        b0, b1 = base['start'] * FPS, base['end'] * FPS
        n = int(round(dur * FPS))
        f0 = start_f
        # (a) copy the base motion (optionally re-timed) into the new range
        for k in range(n + 1):
            t = k / FPS
            src = retime(t, b0, b1) if retime else b0 + ((k) % max(1, int(b1 - b0)))
            put(f0 + k, sample(src))
        # (b) IK hands along their paths, then bake visually
        chest0 = world_head(bmap['Chest'], b0)
        tgt = {}
        for side in ('R', 'L'):
            e = bpy.data.objects.new(f'IK_{side}', None); sc.collection.objects.link(e); tgt[side] = e
            con = pb[bmap['ForeArm_' + side]].constraints.new('IK')
            con.target = e; con.chain_count = 2; con.use_tail = True
        for k in range(n + 1):
            t = k / FPS
            hr, hl = hands_fn(t, chest0)
            for side, p in (('R', hr), ('L', hl)):
                tgt[side].location = p; tgt[side].keyframe_insert('location', frame=f0 + k)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode='POSE')
        bpy.ops.pose.select_all(action='SELECT')
        bpy.ops.nla.bake(frame_start=f0, frame_end=f0 + n, only_selected=True, visual_keying=True,
                         clear_constraints=True, use_current_action=True, bake_types={'POSE'})
        bpy.ops.object.mode_set(mode='OBJECT')
        for e in tgt.values(): bpy.data.objects.remove(e, do_unlink=True)
        # (c) head nods and jaw syllables as delta rotations on top of the baked pose
        nod_ax = world_axis_in_bone(bmap['Head'], (1, 0, 0))
        tilt_ax = world_axis_in_bone(bmap['Head'], (0, 1, 0))
        jaw_ax = world_axis_in_bone('Jaw', (1, 0, 0))
        for k in range(n + 1):
            t = k / FPS; f = f0 + k
            sc.frame_set(f)
            if head_fn:
                nod, tilt = head_fn(t)
                hb = pb[bmap['Head']]
                hb.rotation_quaternion = hb.rotation_quaternion @ Quaternion(nod_ax, math.radians(nod)) @ Quaternion(tilt_ax, math.radians(tilt))
                hb.keyframe_insert('rotation_quaternion', frame=f)
            jb = pb['Jaw']
            jb.rotation_quaternion = Quaternion(jaw_ax, math.radians(jaw_fn(t) if jaw_fn else 0.0))
            jb.keyframe_insert('rotation_quaternion', frame=f)
        for side in ('R', 'L'):
            new_clips.append(dict(id=f'{cid}_{side}', exercise=exercise or cid, side=side, phase='all', seated=seated,
                                  start=round(f0 / FPS, 4), end=round((f0 + n) / FPS, 4)))
        start_f = f0 + n + 30
        return f0, chest0

    # jaw on every existing frame stays closed (explicit key so the bone is part of every clip)
    jaw_ax0 = world_axis_in_bone('Jaw', (1, 0, 0))
    pb['Jaw'].rotation_quaternion = Quaternion((1, 0, 0, 0))
    pb['Jaw'].keyframe_insert('rotation_quaternion', frame=0)

    TWO_PI = 2 * math.pi
    jmax = cfg['jaw_max']

    def jaw_talk(t):
        # syllables at ~4.4 Hz, words grouped with short pauses (loops every 6 s)
        syl = max(0.0, math.sin(TWO_PI * 4.4 * t + 0.6 * math.sin(TWO_PI * t / 3))) ** 0.8
        gate = 1.0 if (t % 1.5) < 1.22 else 0.15
        accent = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(TWO_PI * t / 2))
        return jmax * syl * gate * accent

    def head_talk(t):
        return (3.5 * math.sin(TWO_PI * t / 1.5) * (0.5 + 0.5 * math.sin(TWO_PI * t / 6)),   # nods
                2.5 * math.sin(TWO_PI * t / 3 + 1.0))                                         # small tilts

    def hands_talk(t, chest):
        # explaining gestures in front of the body; right hand leads, left answers (loops every 6 s)
        a = TWO_PI * t
        r = chest + Vector((-0.17 - 0.05 * math.sin(a / 1.5), -0.27 - 0.04 * max(0, math.sin(a / 3)), -0.20 + 0.06 * max(0, math.sin(a / 1.5 + 0.4))))
        l = chest + Vector((0.17 + 0.04 * math.sin(a / 2 + 2.0), -0.24, -0.24 + 0.05 * max(0, math.sin(a / 3 + 3.1))))
        return r, l

    make_clip('talk', 'idle', 6.0, False, hands_talk, head_fn=head_talk, jaw_fn=jaw_talk)
    make_clip('seated_talk', 'seated_idle', 6.0, True, hands_talk, head_fn=head_talk, jaw_fn=jaw_talk)

    # ---- set shot: re-time the calf raise so the rise peaks at the release ----
    cr = clips['calf_raise_R']
    c0, c1 = cr['start'] * FPS, cr['end'] * FPS
    hips = bmap['Hips']
    zs = [(world_head(hips, f).z, f) for f in range(int(c0), int(c1))]
    top = max(zs)[1]
    RELEASE = 0.45

    def retime(t, b0, b1):
        if t < RELEASE: return c0 + (top - c0) * (t / RELEASE)               # rise
        if t < 1.5: return top                                              # hold the finish on the toes
        if t < 2.3: return top + (c1 - top) * ((t - 1.5) / 0.8)             # come down softly
        return c1

    sc.frame_set(int(c0))
    head_top = world_head(bmap['Head'], c0) + Vector((0, 0, 0.17))
    shoulder_r = world_head(bmap['UpperArm_R'], c0)

    def lerp(a, b, u): return a + (b - a) * max(0.0, min(1.0, u))

    def ease(u): u = max(0.0, min(1.0, u)); return u * u * (3 - 2 * u)

    def hands_shot(t, chest):
        lift = world_head(hips, retime(t, c0, c1)).z - world_head(hips, c0).z
        hold_r = chest + Vector((-0.10, -0.28, -0.07 + lift)); hold_l = chest + Vector((0.10, -0.26, -0.07 + lift))
        set_r = Vector((-0.06, head_top.y - 0.16, head_top.z - 0.02 + lift)); set_l = set_r + Vector((0.13, 0.03, -0.03))
        fin_r = shoulder_r + Vector((0.02, -0.42, 0.50 + lift)); fin_l = set_l + Vector((0.04, 0.02, -0.06))
        if t < 0.12: return hold_r, hold_l
        if t < 0.38: u = ease((t - 0.12) / 0.26); return lerp(hold_r, set_r, u), lerp(hold_l, set_l, u)
        if t < 0.55: u = ease((t - 0.38) / 0.17); return lerp(set_r, fin_r, u), lerp(set_l, fin_l, u)
        if t < 1.5: return fin_r, fin_l                                     # hold the follow-through
        if t < 2.3: u = ease((t - 1.5) / 0.8); return lerp(fin_r, hold_r, u), lerp(fin_l, hold_l, u)
        return hold_r, hold_l

    def head_shot(t): return (-6.0 * ease((t - 0.1) / 0.3) * (1 - ease((t - 1.6) / 0.6)), 0.0)  # eyes up to the rim

    f0, chest0 = make_clip('set_shot', 'idle', 2.6, False, hands_shot, retime=retime, head_fn=head_shot, exercise='set_shot')
    # ball points for the app (coach-local, RealityKit/USD axes: x right, y up, z towards the viewer)
    def to_usd(v): return [round(v.x, 3), round(v.z, 3), round(-v.y, 3)]
    hr, hl = hands_shot(0.05, chest0); hold = (hr + hl) / 2 + Vector((0, -0.07, 0))
    rr, rl = hands_shot(0.40, chest0); release = (rr + rl) / 2 + Vector((0, -0.04, 0.10))
    shot_points = dict(hold=to_usd(hold), release=to_usd(release), releaseTime=RELEASE, length=2.6)

    sc.frame_start = 0; sc.frame_end = start_f
    print(' new clips', [c['id'] for c in new_clips], 'frames to', start_f, flush=True)

    # ---------- export ----------
    props = {p.identifier for p in bpy.ops.wm.usd_export.get_rna_type().properties}
    kw = dict(filepath=f'{OUT}/{name}.usdz', export_animation=True)
    for k, v in (('export_armatures', True), ('export_materials', True), ('export_textures', True),
                 ('selected_objects_only', False), ('visible_objects_only', False),
                 ('convert_orientation', True), ('export_global_forward_selection', 'NEGATIVE_Z'),
                 ('export_global_up_selection', 'Y'), ('generate_preview_surface', True),
                 ('export_lights', False), ('export_cameras', False), ('only_deform_bones', False)):
        if k in props: kw[k] = v
    bpy.ops.wm.usd_export(**kw)
    man['clips'] = [c for c in man['clips'] if not c['id'].startswith(('talk_', 'seated_talk_', 'set_shot_'))] + new_clips
    man['shot'] = shot_points
    json.dump(man, open(f'{OUT}/{cfg["json"]}', 'w'), indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=f'{OUT}/{name}_talk.blend')
    print(' exported', name, shot_points, flush=True)


for n in CFG:
    run(n)
print('DONE')
