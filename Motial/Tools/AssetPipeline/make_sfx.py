"""Procedural, licence-free drive sounds for Remer (calm style)."""
import sys, os, wave
import numpy as np
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
SR = 44100
rng = np.random.default_rng(1)
def save(name, x, peak=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    d = (x * 32767).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d)
def lp(x, a):
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s); y[i] = s
    return y
def env(n, a=0.005, r=0.2):
    e = np.ones(n); ai = max(1, int(a * SR)); ri = max(1, int(r * SR))
    e[:ai] = np.linspace(0, 1, ai); e[-ri:] *= np.linspace(1, 0, ri) ** 2
    return e
def tone(f, dur, harm=(1, 0.3, 0.1)):
    t = np.arange(int(SR * dur)) / SR
    return sum(h * np.sin(2 * np.pi * f * (k + 1) * t) for k, h in enumerate(harm)) * np.exp(-t * 4)
t2 = np.arange(int(SR * 2.0)) / SR; f0 = 90
eng = (np.sin(2*np.pi*f0*t2) + 0.55*np.sin(2*np.pi*2*f0*t2+0.3) + 0.3*np.sin(2*np.pi*3*f0*t2+1.1) + 0.12*np.sin(2*np.pi*5*f0*t2))
eng *= 1 + 0.12 * np.sin(2 * np.pi * 6 * t2)
n = lp(rng.standard_normal(len(t2)), 0.05); n = n - np.linspace(n[0], n[-1], len(n))
eng += 0.25 * n / np.max(np.abs(n))
save('sfx_engine_loop.wav', eng, 0.6)
t4 = np.arange(int(SR * 4.0)) / SR
w = lp(lp(rng.standard_normal(len(t4) + SR), 0.02), 0.05)
fade = np.linspace(0, 1, SR)
w = np.concatenate([w[:len(t4)-SR], w[len(t4)-SR:len(t4)]*(1-fade) + w[len(t4):len(t4)+SR]*fade])[:len(t4)]
w *= 1 + 0.25 * np.sin(2 * np.pi * 0.5 * t4)
save('amb_wind_loop.wav', w, 0.5)
save('sfx_count_beep.wav', tone(660, 0.25) * env(int(SR * 0.25)), 0.5)
go = tone(880, 0.7) + 0.6 * tone(1320, 0.7)
save('sfx_count_go.wav', go * env(len(go), r=0.4), 0.6)
tw = np.arange(int(SR * 0.8)) / SR
nz = rng.standard_normal(len(tw)); out = np.zeros_like(nz); s1 = s2 = 0.0
for i, v in enumerate(nz):
    a = 0.02 + 0.18 * np.sin(np.pi * tw[i] / 0.8)
    s1 += a * (v - s1); s2 += a * (s1 - s2); out[i] = s1 - s2
save('sfx_gate_whoosh.wav', out * np.sin(np.pi * tw / 0.8) ** 2, 0.55)
ts = np.arange(int(SR * 0.6)) / SR
sq = np.sin(2*np.pi*(1150 + 60*np.sin(2*np.pi*9*ts))*ts) + 0.4*lp(rng.standard_normal(len(ts)), 0.3)
save('sfx_tyre_slide.wav', sq * env(len(ts), a=0.04, r=0.35), 0.35)
parts = []
for f, d in [(523.25, 0.18), (659.25, 0.18), (783.99, 0.6)]:
    parts.append(tone(f, d, (1, 0.5, 0.2, 0.1)) * env(int(SR * d), r=min(0.15, d * 0.6)))
save('sfx_lap_fanfare.wav', np.concatenate(parts), 0.6)
print('ok')
