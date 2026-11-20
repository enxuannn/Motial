"""Procedurally paints equirectangular 360-degree environments (original artwork, no licences needed).
u = azimuth (0..1, 0.5 = straight ahead), v = elevation (top = +90deg)."""
import numpy as np
from PIL import Image, ImageFilter
OUT = '/home/claude/build/out/'
W, H = 4096, 2048
rng = np.random.default_rng(7)
az = (np.arange(W) + 0.5) / W * 2 * np.pi                 # 0..2pi
el = (0.5 - (np.arange(H) + 0.5) / H) * np.pi             # +pi/2..-pi/2
ELd = np.degrees(el)[:, None]

def fbm1(n, octaves=6, seed=0, base=3):
    """Periodic 1-D fractal noise over azimuth."""
    r = np.random.default_rng(seed); out = np.zeros(n); amp = 1; tot = 0
    for o in range(octaves):
        k = base * 2 ** o
        ph = r.uniform(0, 2 * np.pi, k)
        a = r.uniform(0.4, 1, k)
        x = np.linspace(0, 2 * np.pi, n, endpoint=False)
        out += amp * sum(a[i] * np.sin((i + 1) * x * (k / max(k, 1)) + ph[i]) / (i + 1) ** 0.9 for i in range(k)) / np.sqrt(k)
        tot += amp; amp *= 0.5
    return out / tot

def noise2(h, w, scale, seed, octaves=5):
    r = np.random.default_rng(seed); out = np.zeros((h, w)); amp = 1; tot = 0
    for o in range(octaves):
        gh, gw = max(2, int(h / scale * 2 ** o)), max(2, int(w / scale * 2 ** o))
        g = r.random((gh, gw)).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += amp * (np.asarray(im, np.float32) / 255); tot += amp; amp *= 0.5
    return out / tot

def lerp(a, b, t): return a + (b - a) * t
def C(*hexes): return [np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255 for h in hexes]
def smooth(x): x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)

def sky(top, mid, hor, sun_az=0.5, sun_el=8, sun_col='#fff2d0', glow=0.6, sun_size=1.2):
    t, m, h = C(top, mid, hor)
    e = np.clip(ELd / 90, 0, 1)[..., None]
    col = np.where(e < 0.18, lerp(h, m, smooth(e / 0.18)), lerp(m, t, smooth((e - 0.18) / 0.82)))
    col = np.broadcast_to(col, (H, W, 3)).copy()
    daz = np.angle(np.exp(1j * (az[None, :] - sun_az * 2 * np.pi)))
    d = np.sqrt(np.degrees(daz) ** 2 + (ELd - sun_el) ** 2)
    sc = C(sun_col)[0]
    col += sc * (glow * np.exp(-d / 22) + 0.35 * np.exp(-d / 6))[..., None]
    col = np.where((d < sun_size)[..., None], sc * 1.3, col)
    return col

def clouds(col, color, amount=0.5, seed=3, band=(4, 40)):
    n = noise2(H, W, 260, seed)
    e = ELd
    mask = smooth((n - (1 - amount)) / 0.25) * smooth((e - band[0]) / 6) * smooth((band[1] - e) / 10)
    c = C(color)[0]
    return lerp(col, c, (mask * 0.75)[..., None])

def ridges(col, layers, fog_col, water_line=None):
    """layers: list of (base_el, amp, color, seed, fog)"""
    fc = C(fog_col)[0]
    hmap = np.full(W, -90.0)
    for base, amp, c, seed, fog in layers:
        f = fbm1(W, seed=seed); f = (f - f.min()) / (np.ptp(f) + 1e-9)
        prof = base + amp * (f ** 1.6) * 2.2
        cc = lerp(C(c)[0], fc, fog)
        mask = ELd[:, 0][:, None] < prof[None, :]
        if water_line is not None:
            mask &= ELd[:, 0][:, None] > water_line
        shade = 1 - 0.18 * smooth((prof[None, :] - ELd) / max(amp, 1))  # darker lower down
        col = np.where(mask[..., None], cc * shade[..., None] if True else cc, col)
        hmap = np.maximum(hmap, prof)
    return col

def treeline(col, base_el, color, seed=40, density=0.6, h=2.2):
    r = np.random.default_rng(seed); prof = np.full(W, -90.0)
    x = np.arange(W)
    for c in r.choice(W, int(W * density / 8), replace=False):
        hh = h * r.uniform(0.5, 1.3); wd = r.uniform(5, 14)
        prof = np.maximum(prof, base_el + hh * (1 - np.abs(((x - c + W / 2) % W) - W / 2) / wd))
    prof = np.maximum(prof, base_el + 0.4 * fbm1(W, seed=seed + 1))
    m = (ELd[:, 0][:, None] < prof[None, :]) & (ELd[:, 0][:, None] > base_el - 0.6)
    return np.where(m[..., None], C(color)[0], col)

def stars(col, density=0.0009, seed=5):
    r = np.random.default_rng(seed)
    m = (r.random((H, W)) < density) & (ELd > 5)
    b = r.random((H, W)) ** 3
    col = col + (m * b * 1.2)[..., None]
    return col

def aurora(col, seed=9):
    x = az[None, :]
    curtain = 18 + 10 * fbm1(W, seed=seed, base=2)[None, :]
    e = ELd
    n = noise2(H, W, 90, seed + 1)
    rays = 0.5 + 0.5 * np.sin(x * 140 + 6 * fbm1(W, seed=seed + 2)[None, :])
    band = np.exp(-((e - curtain) / 9) ** 2) * (e > curtain - 6)
    tail = np.exp(-np.clip(e - curtain, 0, None) / 14) * (e > curtain)
    g, p = C('#5dffb2', '#9b6bff')
    a = (band * 0.9 + tail * 0.6) * (0.55 + 0.45 * rays) * (0.6 + 0.6 * n)
    a *= 0.55 + 0.45 * np.cos(x - np.pi)  # strongest in front
    colr = lerp(g, p, smooth((e - curtain) / 25)[..., None])
    return col + colr * a[..., None] * 0.9

def water(col, horizon_el=0.0, tint='#2b4a66', ripple=0.012, strength=0.6, seed=11):
    out = col.copy()
    rows = np.where(ELd[:, 0] < horizon_el)[0]
    n = noise2(H, W, 40, seed, 4)
    tc = C(tint)[0]
    for r in rows:
        depth = horizon_el - ELd[r, 0]
        src = int(np.clip(np.argmin(np.abs(ELd[:, 0] - (horizon_el + depth))), 0, H - 1))
        off = ((n[r] - 0.5) * ripple * W * min(1, depth / 10)).astype(int)
        ref = col[src, (np.arange(W) + off) % W]
        fres = np.clip(0.25 + 0.75 * np.exp(-depth / 12), 0, 1)
        out[r] = lerp(tc, ref, fres * strength)[None] if False else lerp(tc[None, :], ref, fres * strength)
    return out

def meadow(col, horizon_el, c1, c2, seed=21):
    a, b = C(c1, c2)
    e = ELd
    depth = np.clip(horizon_el - e, 0.05, 90)
    n1 = noise2(H, W, 18, seed, 3); n2 = noise2(H, W, 120, seed + 1, 3)
    t = smooth((horizon_el - e) / 45)
    stripes = 0.5 + 0.5 * np.sin(az[None, :] * 900 * np.clip(depth / 30, 0.2, 1) + n2 * 9)
    g = lerp(a, b, t[..., None]) * (0.8 + 0.25 * n1[..., None] + 0.12 * (stripes * smooth(depth / 15))[..., None])
    haze = np.exp(-depth / 2.5)[..., None]
    g = lerp(g, col[np.argmin(np.abs(ELd[:, 0] - horizon_el - 1)), :][None], haze * 0.6)
    return np.where((e < horizon_el)[..., None], g, col)

def path_river(col, horizon_el, colr='#6fa8c9', seed=31):
    """A river running from the horizon straight toward the viewer (front, u=0.5)."""
    e = ELd; x = np.degrees(np.angle(np.exp(1j * (az[None, :] - np.pi))))
    width = 3 + (horizon_el - e) * 1.6
    wig = 6 * np.sin(np.radians(e) * 9) * smooth((horizon_el - e) / 20)
    mask = (np.abs(x - wig) < width) & (e < horizon_el)
    n = noise2(H, W, 25, seed, 3)
    rc = C(colr)[0] * (0.85 + 0.35 * n[..., None])
    sh = C('#ffffff')[0]
    rc = lerp(rc, sh, (np.clip(n - 0.72, 0, 1) * 2.5)[..., None])
    return np.where(mask[..., None], rc, col)

def finish(col, name, vignette=0.0):
    col = np.clip(col, 0, 1) ** (1 / 1.0)
    im = Image.fromarray((col * 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    im.save(OUT + name + '.jpg', quality=90)
    im.resize((1024, 512)).save(OUT + 'thumb_' + name + '.jpg', quality=85)

# 1) Dawn Lake — calm default
c = sky('#3c4f8f', '#d892a7', '#ffd2a1', sun_az=0.5, sun_el=6, glow=0.7)
c = clouds(c, '#ffd8c8', 0.42, seed=3)
c = ridges(c, [(9, 7, '#6d5f8f', 1, 0.55), (6, 6, '#4b4775', 2, 0.35), (3.5, 4, '#2f3256', 3, 0.15)], '#e7a9a8')
c = water(c, 0.0, '#2c3c63', strength=0.75)
finish(c, 'env_dawn_lake')
# 2) River Valley — stone-hopping game
c = sky('#3d7fd1', '#9cc9ef', '#e7f3ff', sun_az=0.38, sun_el=40, glow=0.25)
c = clouds(c, '#ffffff', 0.5, seed=5, band=(6, 55))
c = ridges(c, [(11, 8, '#7b97b8', 4, 0.5), (7, 6, '#4f7f5f', 5, 0.25), (4, 4, '#3f6b45', 6, 0.1)], '#cfe3f5')
c = treeline(c, 3.0, '#2f5a33', seed=41)
c = meadow(c, 3.0, '#5f9a4b', '#3c6e2f')
c = path_river(c, 3.0)
finish(c, 'env_river_valley')
# 3) Golden Meadow — ball-catch game
c = sky('#4a74b8', '#f0b779', '#ffe3a8', sun_az=0.62, sun_el=10, glow=0.6)
c = clouds(c, '#fff0dc', 0.38, seed=8)
c = ridges(c, [(7, 5, '#a2847a', 7, 0.5), (4, 3, '#6a6b45', 8, 0.25)], '#f4cfa0')
c = treeline(c, 2.0, '#4b4a2a', seed=44, density=0.35, h=3.0)
c = meadow(c, 2.0, '#d2a956', '#6d7a30', seed=23)
finish(c, 'env_golden_meadow')
# 4) Aurora Night — rhythm game
c = sky('#03040d', '#0b1636', '#1b2f5c', sun_az=0.0, sun_el=-30, glow=0.0, sun_size=0)
c = stars(c)
c = aurora(c)
c = ridges(c, [(6, 6, '#0a1020', 12, 0.2), (3, 3, '#05070f', 13, 0.0)], '#1b2f5c')
c = water(c, 0.0, '#050a16', strength=0.7, seed=14)
finish(c, 'env_aurora_night')
print('done')
