"""Environment-themed hit sounds + baseball sounds (original, synthesised)."""
src = open('build/synth_audio.py').read().split('# ---------------- SFX')[0]
exec(src)
import numpy as np
# Dawn Lake: glassy water chime (two bell partials + tiny drop)
x = mix(note(mtof(84), 1.1, 'bell', 0.45) * 0.6, note(mtof(91), 0.9, 'bell', 0.35) * 0.35)
tt = t(0.12); drop = np.sin(2*np.pi*(900 + 1600*np.exp(-tt*40))*tt) * np.exp(-tt*30) * 0.5
save('sfx_chime', norm(mix(drop, x), 0.75))
# River Valley: water "bloop" droplet + small splash
tt = t(0.25); bloop = np.sin(2*np.pi*(380 + 900*(1-np.exp(-tt*25)))*tt) * np.exp(-tt*14)
spl = bp(rng.standard_normal(int(SR*0.3)), 1200, 6000) * np.exp(-t(0.3)*16) * 0.35
save('sfx_drop', norm(mix(bloop, spl), 0.75))
# Golden Meadow: short bird chirp pair
def chirp(f0, f1, d):
    tt = t(d); f = f0 + (f1 - f0) * (tt / d) ** 0.7
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.sin(np.pi*tt/d) ** 1.5
b = np.zeros(int(SR*0.45)); place(b, chirp(3200, 4600, 0.07), 0); place(b, chirp(3600, 5200, 0.06), 0.11); place(b, chirp(4200, 3000, 0.09), 0.22)
save('sfx_bird', norm(b, 0.6))
# Aurora Night: rising shimmer
s = np.zeros(int(SR*1.0))
for i, m in enumerate([79, 83, 86, 91, 95]): place(s, note(mtof(m), 0.6, 'bell', 0.25) * (0.5 - i*0.06), i*0.05)
s += hp(rng.standard_normal(len(s)), 6000) * np.exp(-t(1.0)*5) * 0.08
save('sfx_shimmer', norm(s, 0.7))
# Baseball: leather mitt pop and pitch whoosh
tt = t(0.18); pop = (np.sin(2*np.pi*(140 + 260*np.exp(-tt*60))*tt) * np.exp(-tt*28) + bp(rng.standard_normal(len(tt)), 500, 3500) * np.exp(-tt*55) * 0.8)
save('sfx_mitt', norm(pop, 0.9))
tt = t(0.5); wh = bp(rng.standard_normal(len(tt)), 600, 4000) * np.sin(np.pi * tt / 0.5) ** 2
save('sfx_pitch', norm(wh, 0.45))
print('ok')
