"""Sunset Court: an original, procedurally painted outdoor basketball court in Steady's brand palette.
One ray shader, sampled two ways:
  * equirectangular 360 panorama (env_sunset_court.jpg) for the app: lower half = court floor seen from 1.6 m,
    so EnvironmentBuilder.groundFromPanorama re-projects it onto the real floor exactly;
  * perspective concept render for the deck (with the hoop and a coach cut-out composited).
World: person stands on the free-throw line at the origin, facing -Z toward the hoop. Metres. FIBA dimensions."""
import numpy as np
from PIL import Image, ImageFilter
import sys
OUT = sys.argv[1] if len(sys.argv) > 1 else 'build/out/'
import os; os.makedirs(OUT, exist_ok=True)
EYE = 1.6
CAM = [0.0, 0.0]   # eye x, z (panorama: origin)

def C(h): return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255
def smooth(x): x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)
def lerp(a, b, t): return a + (b - a) * t

def fbm_az(az, seed, base=3, octaves=6):
    r = np.random.default_rng(seed); out = np.zeros_like(az); amp = 1; tot = 0
    for o in range(octaves):
        k = base * 2 ** o
        for i in range(k):
            out += amp * r.uniform(0.4, 1) * np.sin((i + 1) * az + r.uniform(0, 6.283)) / (i + 1) ** 0.9 / np.sqrt(k)
        tot += amp; amp *= 0.5
    return out / tot

# ---- court geometry (z: hoop at -Z) ----
BASE_Z = -5.8                 # baseline
RIM_Z = BASE_Z + 1.575        # rim centre
BOARD_Z = BASE_Z + 1.2
HALF_Z = BASE_Z + 14.0        # half-court line (behind the person)
SIDE_X = 7.5

def court_color(x, z, dist, pix):
    """Paint of the court surface at floor point (x, z). pix = metres per pixel for anti-aliasing."""
    surface = C('#4f7ea3'); key = C('#8b7fc0'); runoff = C('#344766'); line = C('#f6ecd9')
    inside = (np.abs(x) <= SIDE_X) & (z >= BASE_Z) & (z <= HALF_Z + 14)
    col = np.where(inside[..., None], surface, runoff)
    # soft sheen / wear
    col = col * (0.94 + 0.06 * np.sin(x * 0.7 + z * 0.4))[..., None]
    inkey = (np.abs(x) <= 2.45) & (z >= BASE_Z) & (z <= 0)
    col = np.where(inkey[..., None], key, col)
    ftc = np.hypot(x, z) <= 1.8
    col = np.where((ftc & (z > 0))[..., None], key * 0.92 + surface * 0.08, col)
    w = np.maximum(0.05, pix * 1.2)               # line half-width (5 cm lines, widened far away)
    def band(d): return smooth(1 - np.abs(d) / w)
    m = np.zeros_like(x)
    m = np.maximum(m, band(z - BASE_Z) * (np.abs(x) <= SIDE_X))                    # baseline
    m = np.maximum(m, band(np.abs(x) - SIDE_X) * (z >= BASE_Z))                     # sidelines
    m = np.maximum(m, band(z - HALF_Z) * (np.abs(x) <= SIDE_X))                     # half-court
    m = np.maximum(m, band(np.abs(x) - 2.45) * (z >= BASE_Z) * (z <= 0))           # key sides
    m = np.maximum(m, band(z) * (np.abs(x) <= 2.45))                                # free-throw line
    m = np.maximum(m, band(np.hypot(x, z) - 1.8))                                   # FT circle
    m = np.maximum(m, band(np.hypot(x, z - HALF_Z) - 1.8))                          # centre circle
    r3 = np.hypot(x, z - RIM_Z)
    arc = band(r3 - 6.75) * (np.abs(x) <= 6.6) * (z > BASE_Z + 2.99)
    corner = band(np.abs(x) - 6.6) * (z >= BASE_Z) * (z <= BASE_Z + 2.99)
    m = np.maximum(m, np.maximum(arc, corner))
    m = np.maximum(m, band(np.hypot(x, z - RIM_Z) - 1.25) * (z > RIM_Z))           # no-charge arc
    col = lerp(col, line, (m * 0.95)[..., None])
    # brand signature: a soft glow pool where the person stands (the Steady step bloom)
    g = np.exp(-(x ** 2 + z ** 2) / 0.35) * 0.35
    col = col + C('#ffe7b8') * g[..., None]
    # haze with distance (toward the sunset sky colour)
    haze = 1 - np.exp(-dist / 38)
    return lerp(col, C('#e9b3a6'), (haze * 0.75)[..., None])

def sky_color(d, az, el_deg):
    top, mid, hor = C('#38507f'), C('#c98fb0'), C('#ffcfa0')
    e = np.clip(el_deg / 90, 0, 1)[..., None]
    col = np.where(e < 0.2, lerp(hor, mid, smooth(e / 0.2)), lerp(mid, top, smooth((e - 0.2) / 0.8)))
    sun_az = np.radians(35)      # low sun ahead-right
    daz = np.degrees(np.angle(np.exp(1j * (az - sun_az))))
    dd = np.sqrt(daz ** 2 + (el_deg - 5) ** 2)
    col = col + C('#fff0cf') * (0.4 * np.exp(-dd / 18) + 0.3 * np.exp(-dd / 4))[..., None]
    col = np.where((dd < 1.3)[..., None], C('#fff6e2') * 1.25, col)
    # soft clouds
    n = 0.5 + 0.5 * np.sin(az * 5 + 2 * np.sin(az * 3)) * np.sin(el_deg * 0.25 + az * 2)
    cm = smooth((n - 0.55) / 0.3) * smooth((el_deg - 6) / 6) * smooth((35 - el_deg) / 10)
    col = lerp(col, C('#ffd9c9'), (cm * 0.5)[..., None])
    # distant tree line and low city silhouettes just above the horizon
    ridge = 2.0 + 5.0 * (0.5 + 0.5 * fbm_az(az, 3)) ** 1.5 + 0.6 * np.abs(np.sin(az * 37)) * (0.5 + 0.5 * fbm_az(az, 5, base=12))
    city = 0.8 + 3.0 * (np.floor((fbm_az(az, 9, base=20) + 1) * 3) / 6) * (np.abs(np.sin(az * 1.5)) > 0.4)
    col = np.where((el_deg < ridge)[..., None] & (el_deg >= 0)[..., None], lerp(C('#5e5a8a'), C('#e3a7a4'), 0.3), col)
    # string lights / lanterns: warm dots along a gentle catenary at ~6-9 degrees
    lamp_el = 7 + 2.2 * np.cos(az * 6)  # (sky lights sit above the fence)
    k = np.round(az / np.radians(4.5)); lamp_az = k * np.radians(4.5)
    ld = np.sqrt(np.degrees(az - lamp_az) ** 2 + (el_deg - (7 + 2.2 * np.cos(lamp_az * 6))) ** 2)
    col = col + C('#ffd38a') * (np.exp(-ld / 0.35) * 1.1 + np.exp(-ld / 1.5) * 0.25)[..., None]
    col = np.where((np.abs(el_deg - lamp_el) < 0.06)[..., None], lerp(col, C('#3e3a5c'), 0.6), col)
    # a few distant sky lanterns (moodboard)
    r = np.random.default_rng(4)
    for _ in range(14):
        a0, e0 = r.uniform(0, 2 * np.pi), r.uniform(14, 40)
        dd2 = np.sqrt(np.degrees(np.angle(np.exp(1j * (az - a0)))) ** 2 + ((el_deg - e0) * 0.8) ** 2)
        col = col + C('#ffb36b') * (np.exp(-dd2 / 0.35) * 0.9 + np.exp(-dd2 / 2) * 0.15)[..., None]
    return col

def shade(d, pix_angle, hoop=False):
    """d: (...,3) unit ray directions from the eye at (0, EYE, 0). Returns colours (...,3)."""
    x, y, z = d[..., 0], d[..., 1], d[..., 2]
    az = np.arctan2(x, -z)                     # 0 = straight ahead (-Z)
    el = np.degrees(np.arcsin(np.clip(y, -1, 1)))
    col = sky_color(d, az, el)
    down = y < -1e-4
    t = np.where(down, EYE / np.maximum(-y, 1e-4), np.inf)
    px, pz = CAM[0] + x * t, CAM[1] + z * t
    dist = np.where(down, np.hypot(px, pz), 1e9)
    pix = np.where(down, t * pix_angle / np.maximum(-y, 0.05), 1)
    fc = court_color(np.where(down, px, 0), np.where(down, pz, 0), np.minimum(dist, 200), np.minimum(pix, 5))
    col = np.where(down[..., None], fc, col)
    tbest = np.where(down, t, np.inf)
    # chain-link fence around the court (box walls, 3.4 m high) with a dark top rail
    FX, FZ0, FZ1, FH = 11.5, BASE_Z - 4.5, HALF_Z + 4.0, 3.0
    cand = []
    for nrm, val in ((0, FX), (0, -FX), (2, FZ0), (2, FZ1)):
        comp = d[..., nrm]; org = CAM[0] if nrm == 0 else CAM[1]
        tt = np.where(np.abs(comp) > 1e-5, (val - org) / np.where(np.abs(comp) > 1e-5, comp, 1), np.inf)
        cand.append(np.where(tt > 0, tt, np.inf))
    tw = np.minimum.reduce(cand)
    wy = EYE + y * tw
    wx, wz = CAM[0] + x * tw, CAM[1] + z * tw
    wall = (wy < FH) & (tw < tbest)
    u = np.where(np.abs(np.abs(wx) - FX) < 1e-3, wz, wx)
    mesh = (np.abs(np.sin((u + wy) * 16)) < 0.10 + tw * pix_angle * 8) | (np.abs(np.sin((u - wy) * 16)) < 0.10 + tw * pix_angle * 8)
    fence_col = lerp(col, C('#3a3f63'), 0.18)
    fence_col = np.where(mesh[..., None], lerp(col, C('#2e3254'), 0.32), fence_col)
    posts = np.abs(((u + 1.5) % 3.0) - 1.5) < 0.04
    rail = np.abs(wy - FH + 0.04) < 0.05
    fence_col = np.where((posts | rail)[..., None], C('#272a45'), fence_col)
    col = np.where(wall[..., None], fence_col, col)
    if hoop:
        def hit_plane_z(z0):
            tt = np.where(z < -1e-4, (z0 - CAM[1]) / np.minimum(z, -1e-4), np.inf)
            return tt, CAM[0] + x * tt, EYE + y * tt
        # pole and arm (behind the board)
        tt, hx, hy = hit_plane_z(BASE_Z - 1.0)
        m = (np.abs(hx) < 0.09) & (hy > 0) & (hy < 3.55) & (tt < tbest)
        col = np.where(m[..., None], C('#2b2f45'), col); tbest = np.where(m, tt, tbest)
        # backboard: translucent glass with a white frame and target square
        tt, hx, hy = hit_plane_z(BOARD_Z)
        inb = (np.abs(hx) < 0.9) & (hy > 2.9) & (hy < 3.95) & (tt < tbest)
        frame = inb & ((np.abs(hx) > 0.86) | (hy < 2.94) | (hy > 3.91))
        sq = inb & (((np.abs(np.abs(hx) - 0.295) < 0.025) & (hy > 3.05) & (hy < 3.5)) | ((np.abs(hy - 3.475) < 0.025) & (np.abs(hx) < 0.32)))
        col = np.where(inb[..., None], lerp(col, C('#eef3ff'), 0.35), col)
        col = np.where((frame | sq)[..., None], C('#fbf7ef'), col)
        tbest = np.where(inb, tt, tbest)
        # net (plane through the rim centre, tapered, diamond mesh)
        tt, hx, hy = hit_plane_z(RIM_Z)
        rr = 0.225 - (3.05 - hy) * 0.2
        innet = (hy < 3.05) & (hy > 2.62) & (np.abs(hx) < rr) & (tt < tbest)
        mesh = (np.abs(np.sin((hx + hy) * 70)) < 0.18) | (np.abs(np.sin((hx - hy) * 70)) < 0.18)
        col = np.where((innet & mesh)[..., None], lerp(col, C('#ffffff'), 0.85), col)
        # rim: annulus in the plane y = 3.05
        ty = np.where(np.abs(y) > 1e-4, (3.05 - EYE) / np.where(np.abs(y) > 1e-4, y, 1), np.inf)
        ty = np.where(ty > 0, ty, np.inf)
        rx, rz = CAM[0] + x * ty, CAM[1] + z * ty
        rd = np.hypot(rx, rz - RIM_Z)
        rim = (np.abs(rd - 0.235) < 0.012 + ty * pix_angle * 0.8) & (ty < tbest)
        col = np.where(rim[..., None], C('#ff7a45'), col)
    return np.clip(col, 0, 1)

def equirect(W=4096, H=2048):
    u = (np.arange(W) + 0.5) / W; v = (np.arange(H) + 0.5) / H
    az = (u - 0.5) * 2 * np.pi                  # u 0.5 = straight ahead (matches EnvironmentBuilder.patch)
    el = (0.5 - v) * np.pi
    AZ, EL = np.meshgrid(az, el)
    d = np.stack([np.sin(AZ) * np.cos(EL), np.sin(EL), -np.cos(AZ) * np.cos(EL)], -1)
    out = np.zeros((H, W, 3), np.float32)
    step = 256
    for r0 in range(0, H, step):
        out[r0:r0 + step] = shade(d[r0:r0 + step], 2 * np.pi / W)
    return out

def perspective(W, H, fov_deg, yaw=0.0, pitch=-6.0, ss=2, hoop=True):
    f = 0.5 * W / np.tan(np.radians(fov_deg) / 2)
    xs = (np.arange(W * ss) + 0.5) / ss - W / 2
    ys = H / 2 - (np.arange(H * ss) + 0.5) / ss
    X, Y = np.meshgrid(xs, ys)
    d = np.stack([X, Y, -np.full_like(X, f)], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    p, yw = np.radians(pitch), np.radians(yaw)
    Rx = np.array([[1, 0, 0], [0, np.cos(p), -np.sin(p)], [0, np.sin(p), np.cos(p)]])
    Ry = np.array([[np.cos(yw), 0, np.sin(yw)], [0, 1, 0], [-np.sin(yw), 0, np.cos(yw)]])
    d = d @ (Ry @ Rx).T
    out = np.zeros(d.shape, np.float32)
    for r0 in range(0, d.shape[0], 200):
        out[r0:r0 + 200] = shade(d[r0:r0 + 200], 1 / f, hoop=hoop)
    im = Image.fromarray((out * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    return im, f

if __name__ == '__main__':
    what = sys.argv[2] if len(sys.argv) > 2 else 'all'
    if what in ('all', 'pano'):
        eq = equirect()
        im = Image.fromarray((eq * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.5))
        im.save(OUT + 'env_sunset_court.jpg', quality=90)
        im.save(OUT + 'env_sunset_court_ground.jpg', quality=90)
        im.resize((1200, 600)).save(OUT + 'pano_preview.jpg', quality=85)
    if what in ('all', 'persp'):
        CAM[0], CAM[1] = 0.5, 4.2
        im, f = perspective(1920, 1080, 64, pitch=0.5)
        im.save(OUT + 'court_persp.png')
    print('ok')
