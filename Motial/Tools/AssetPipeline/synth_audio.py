"""Original synthesised sound design: ambiences, UI/game SFX and three royalty-free music loops."""
import numpy as np, subprocess, os
from scipy.signal import butter, lfilter
from scipy.io import wavfile
SR = 44100
OUT = '/home/claude/build/out/audio/'; os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1)

def t(d): return np.arange(int(SR * d)) / SR
def env(n, a=0.005, r=0.2, sus=None):
    x = np.ones(n); A = max(1, int(a * SR)); R = max(1, int(r * SR))
    x[:A] = np.linspace(0, 1, A)
    x[-R:] *= np.exp(-np.linspace(0, 6, R))
    return x
def adsr_exp(n, decay): return np.exp(-np.arange(n) / SR / decay)
def bp(x, lo, hi, o=2):
    b, a = butter(o, [lo / (SR / 2), hi / (SR / 2)], 'band'); return lfilter(b, a, x)
def lp(x, f, o=2):
    b, a = butter(o, f / (SR / 2)); return lfilter(b, a, x)
def hp(x, f, o=2):
    b, a = butter(o, f / (SR / 2), 'high'); return lfilter(b, a, x)
def pink(n):
    w = rng.standard_normal(n); f = np.fft.rfft(w); k = np.arange(1, len(f) + 1); f /= np.sqrt(k)
    p = np.fft.irfft(f, n); return p / np.abs(p).max()
def norm(x, peak=0.9): return x / (np.abs(x).max() + 1e-9) * peak
def save(name, x, stereo=False, m4a=False):
    x = np.clip(x, -1, 1)
    path = OUT + name + '.wav'
    wavfile.write(path, SR, (x * 32767).astype(np.int16))
    if m4a:
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path, '-c:a', 'aac', '-b:a', '160k', OUT + name + '.m4a'], check=True)
        os.remove(path)
def loopify(x, xf=2.0):
    n = int(xf * SR); a = x[:n]; b = x[-n:]; w = np.linspace(0, 1, n)
    if x.ndim == 2: w = w[:, None]
    y = x[n:].copy(); y[-n:] = b * (1 - w) + a * w
    return y
def note(f, d, kind='sine', decay=0.4, vib=0):
    tt = t(d)
    ph = 2 * np.pi * f * tt + (vib * np.sin(2 * np.pi * 5 * tt) if vib else 0)
    if kind == 'sine': y = np.sin(ph)
    elif kind == 'bell': y = np.sin(ph) + 0.5 * np.sin(2.76 * ph) * np.exp(-tt * 6) + 0.25 * np.sin(5.4 * ph) * np.exp(-tt * 10)
    elif kind == 'pluck': y = np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.2 * np.sin(3 * ph)
    elif kind == 'saw': y = 2 * ((f * tt) % 1) - 1
    elif kind == 'tri': y = 2 * np.abs(2 * ((f * tt) % 1) - 1) - 1
    return y * adsr_exp(len(tt), decay) * env(len(tt), 0.004, min(0.05, d / 3))
def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o
def mtof(m): return 440 * 2 ** ((m - 69) / 12)
def place(buf, x, at):
    i = int(at * SR); j = min(len(buf), i + len(x)); buf[i:j] += x[:j - i]

# ---------------- SFX ----------------
save('sfx_tap', norm(mix(note(1320, 0.09, 'sine', 0.03), 0.3 * note(2640, 0.06, 'sine', 0.02)), 0.5))
s = np.zeros(int(SR * 1.2))
for i, m in enumerate([72, 76, 79, 84]): place(s, note(mtof(m), 0.9, 'bell', 0.35) * 0.5, i * 0.07)
save('sfx_success', norm(s, 0.8))
s = np.zeros(int(SR * 1.6))
for i, m in enumerate([72, 79, 84, 88, 91]): place(s, note(mtof(m), 1.1, 'bell', 0.45) * 0.45, i * 0.06)
sh = hp(rng.standard_normal(len(s)), 6000) * np.exp(-t(1.6) * 3) * 0.08
save('sfx_perfect', norm(s + sh, 0.85))
thump = lp(rng.standard_normal(int(SR * 0.25)), 300) * np.exp(-t(0.25) * 25) * 2 + note(110, 0.25, 'sine', 0.08)
spark = np.zeros(int(SR * 0.6)); place(spark, note(mtof(88), 0.5, 'bell', 0.2) * 0.4, 0.03); place(spark, note(mtof(95), 0.4, 'bell', 0.15) * 0.3, 0.08)
c = np.zeros(int(SR * 0.7)); place(c, thump, 0); place(c, spark, 0)
save('sfx_catch', norm(c, 0.85))
save('sfx_miss', norm(note(220, 0.45, 'tri', 0.2) * 0.6 + note(207, 0.45, 'sine', 0.25) * 0.4, 0.45))
n = int(SR * 1.0); spl = bp(rng.standard_normal(n), 300, 4000) * np.exp(-t(1.0) * 5) * (1 + 0.5 * np.sin(2 * np.pi * 13 * t(1.0)))
drops = np.zeros(n)
for k in range(9): place(drops, note(rng.uniform(900, 2400), 0.08, 'sine', 0.02) * 0.3, 0.1 + rng.uniform(0, 0.6))
save('sfx_splash', norm(spl + drops, 0.8))
knock = bp(rng.standard_normal(int(SR * 0.2)), 200, 2500) * np.exp(-t(0.2) * 35) + note(180, 0.2, 'sine', 0.05) * 0.8
save('sfx_stone', norm(knock, 0.8))
save('sfx_beat', norm(note(880, 0.08, 'sine', 0.025) + hp(rng.standard_normal(int(SR * 0.08)), 5000) * np.exp(-t(0.08) * 60) * 0.3, 0.6))
save('sfx_tick', norm(note(1000, 0.12, 'sine', 0.04), 0.5))
save('sfx_go', norm(note(1500, 0.35, 'bell', 0.2) + note(750, 0.35, 'sine', 0.2) * 0.5, 0.7))
s = np.zeros(int(SR * 2.4))
for i, m in enumerate([60, 64, 67, 72, 76, 79, 84]): place(s, note(mtof(m), 1.5, 'bell', 0.6) * 0.35, i * 0.09)
for m in [60, 67, 72, 76]: place(s, note(mtof(m), 1.6, 'tri', 0.9) * 0.12, 0.66)
save('sfx_levelup', norm(s, 0.85))
w = np.zeros(int(SR * 0.9))
for i in range(2): place(w, note(660, 0.25, 'tri', 0.15) * 0.6 + note(622, 0.25, 'sine', 0.15) * 0.4, i * 0.32)
save('sfx_warning', norm(w, 0.6))
save('sfx_stop', norm(mix(note(392, 0.6, 'bell', 0.3), note(262, 0.8, 'sine', 0.4) * 0.6), 0.7))
br = np.zeros(int(SR * 4)); tt = t(4)
br += pink(len(tt)) * 0.0
for m in [60, 64, 67]: br += np.sin(2 * np.pi * mtof(m) * tt) * 0.15
br *= np.sin(np.pi * tt / 4) ** 2
save('sfx_breath', norm(br, 0.35))

# ---------------- Ambiences (seamless 40 s loops) ----------------
D = 42
def birds(n, count, lo=2500, hi=5200):
    b = np.zeros(n)
    for _ in range(count):
        at = rng.uniform(0, n / SR - 1.5); f0 = rng.uniform(lo, hi); k = rng.integers(2, 6)
        for j in range(k):
            d = rng.uniform(0.05, 0.14); tt = t(d)
            sweep = f0 * (1 + rng.uniform(-0.25, 0.25) * tt / d)
            ch = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * np.sin(np.pi * tt / d) ** 2
            place(b, ch * rng.uniform(0.08, 0.2), at + j * rng.uniform(0.12, 0.2))
    return b
def stereoize(x, y=None, w=0.3):
    y = x if y is None else y
    return np.stack([x * (1 - w) + y * w, y * (1 - w) + x * w], 1)
n = int(SR * D)
wind = lp(pink(n), 500) * (0.6 + 0.4 * np.sin(2 * np.pi * t(D) / 13) ** 2)
laps = bp(rng.standard_normal(n), 200, 1200) * (0.5 + 0.5 * np.sin(2 * np.pi * t(D) / 4.3) ** 8) * 0.5
L = 0.5 * wind + laps + birds(n, 9); R = 0.5 * lp(pink(n), 500) + laps * 0.8 + birds(n, 9)
save('amb_lake', norm(loopify(stereoize(L, R)), 0.5), m4a=True)
rush = bp(pink(n), 250, 6000) * (0.8 + 0.2 * np.sin(2 * np.pi * t(D) / 7)); rush2 = bp(pink(n), 250, 6000)
save('amb_river', norm(loopify(stereoize(rush + birds(n, 5) * 0.6, rush2 + birds(n, 5) * 0.6)), 0.5), m4a=True)
grass = hp(lp(pink(n), 2500), 300) * (0.4 + 0.6 * np.sin(2 * np.pi * t(D) / 9) ** 2) * 0.7
save('amb_meadow', norm(loopify(stereoize(grass + birds(n, 14, 3000, 6500), hp(lp(pink(n), 2500), 300) * 0.6 + birds(n, 14, 3000, 6500))), 0.5), m4a=True)
pad = sum(np.sin(2 * np.pi * mtof(m) * t(D) + 0.3 * np.sin(2 * np.pi * 0.1 * t(D) * (i + 1))) * 0.18 for i, m in enumerate([45, 52, 57, 64, 69]))
pad *= 0.7 + 0.3 * np.sin(2 * np.pi * t(D) / 10)
cr = np.zeros(n)
for k in range(int(D * 2.5)):
    at = rng.uniform(0, D - 0.3); f = rng.uniform(4200, 5200)
    for j in range(3): place(cr, note(f, 0.03, 'sine', 0.01) * 0.12, at + j * 0.045)
save('amb_night', norm(loopify(stereoize(pad + cr, pad * 0.9 + np.roll(cr, 5000))), 0.45), m4a=True)

# ---------------- Music loops ----------------
def kick(): tt = t(0.35); return np.sin(2 * np.pi * (50 + 90 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 9)
def snare(): tt = t(0.25); return (bp(rng.standard_normal(len(tt)), 1500, 8000) * 0.7 + np.sin(2 * np.pi * 190 * tt) * 0.4) * np.exp(-tt * 18)
def hat(): tt = t(0.06); return hp(rng.standard_normal(len(tt)), 7000) * np.exp(-tt * 70)
def track(name, bpm, bars, prog, mood='bright', drums=True):
    beat = 60 / bpm; dur = bars * 4 * beat + 2.0
    Lb = np.zeros(int(SR * dur)); Rb = np.zeros(int(SR * dur))
    for bar in range(bars):
        root = prog[bar % len(prog)]
        b0 = bar * 4 * beat
        chord = [root, root + (4 if mood == 'bright' else 3), root + 7, root + 11 if mood == 'bright' else root + 10]
        for m in chord:
            pd = note(mtof(m + 12), 4 * beat, 'tri', 2.5) * 0.06
            place(Lb, pd, b0); place(Rb, pd, b0 + 0.01)
        for k in range(8):
            m = chord[(k * 3 + bar) % 4] + 24
            ar = note(mtof(m), beat / 2, 'pluck', 0.18) * 0.09
            place(Lb if k % 2 else Rb, ar, b0 + k * beat / 2)
        for k in range(4):
            bs = note(mtof(root - 12), beat * 0.9, 'saw', 0.25); bs = lp(bs, 600) * 0.25
            place(Lb, bs, b0 + k * beat); place(Rb, bs, b0 + k * beat)
            if drums:
                place(Lb, kick() * 0.55, b0 + k * beat); place(Rb, kick() * 0.55, b0 + k * beat)
                if k % 2 == 1: place(Lb, snare() * 0.3, b0 + k * beat); place(Rb, snare() * 0.3, b0 + k * beat)
                for h in range(2): place(Lb if h else Rb, hat() * 0.12, b0 + k * beat + h * beat / 2)
    x = np.stack([Lb, Rb], 1)
    x = x[:int(SR * bars * 4 * beat)]
    save(name, norm(x, 0.85), m4a=True)
track('music_calm_flow', 84, 16, [57, 53, 60, 55], 'bright', drums=False)
track('music_step_up', 104, 16, [60, 57, 53, 55], 'bright')
track('music_night_pulse', 122, 16, [57, 53, 48, 55], 'minor')
print(sorted(os.listdir(OUT)))
