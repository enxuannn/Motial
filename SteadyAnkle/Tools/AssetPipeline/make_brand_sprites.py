"""Brand sprites for Steady's companion butterfly and step effects (moodboard: dawn-blue lake,
sunlit leaf shadows, lantern amber, Sky-like glowing particles). Output: RGBA colour + greyscale alpha."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
out = sys.argv[1]
S = 1024

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient_ramp(t):
    stops = [(0.0, (255, 246, 228)), (0.30, (190, 222, 255)), (0.62, (150, 186, 255)), (0.86, (205, 178, 255)), (1.0, (255, 214, 190))]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1: return lerp(c0, c1, (t - t0) / (t1 - t0))
    return stops[-1][1]

# --- wing (right side; hinge at left-centre, forewing in the top half) ---
mask = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(mask)
def bez(p0, p1, p2, p3, n=60):
    return [((1-t)**3*p0[0]+3*(1-t)**2*t*p1[0]+3*(1-t)*t*t*p2[0]+t**3*p3[0],
             (1-t)**3*p0[1]+3*(1-t)**2*t*p1[1]+3*(1-t)*t*t*p2[1]+t**3*p3[1]) for t in [i/n for i in range(n+1)]]
fore = bez((10, 500), (160, 150), (650, 20), (960, 70)) + bez((960, 70), (1010, 260), (900, 420), (700, 470)) + bez((700, 470), (480, 500), (200, 500), (10, 515))
hind = bez((10, 520), (300, 500), (700, 520), (800, 640)) + bez((800, 640), (860, 800), (640, 990), (430, 960)) + bez((430, 960), (250, 930), (90, 700), (10, 540))
d.polygon(fore, fill=255); d.polygon(hind, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(3))

col = Image.new("RGB", (S, S))
px = col.load()
for y in range(S):
    for x in range(S):
        r = math.hypot(x - 10, (y - 512) * 1.1) / 1000
        px[x, y] = gradient_ramp(min(1, r))
# glowing veins
veins = Image.new("L", (S, S), 0); vd = ImageDraw.Draw(veins)
for ang in [-62, -48, -34, -20, -8]:
    a = math.radians(ang); vd.line([(10, 505), (10 + 1000 * math.cos(a), 505 + 1000 * math.sin(a))], fill=255, width=5)
for ang in [10, 26, 44, 62]:
    a = math.radians(ang); vd.line([(10, 520), (10 + 900 * math.cos(a), 520 + 900 * math.sin(a))], fill=255, width=5)
veins = ImageChops.multiply(veins.filter(ImageFilter.GaussianBlur(2.5)), mask)
col = Image.composite(Image.new("RGB", (S, S), (255, 250, 238)), col, veins.point(lambda v: int(v * 0.75)))
# rim glow + spots near the edge
rim = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(31))).filter(ImageFilter.GaussianBlur(6))
col = Image.composite(Image.new("RGB", (S, S), (255, 226, 196)), col, rim)
spots = Image.new("L", (S, S), 0); sd = ImageDraw.Draw(spots)
for (x, y, r) in [(860, 130, 22), (900, 250, 18), (820, 380, 16), (700, 840, 20), (560, 920, 16), (760, 700, 14)]:
    sd.ellipse([x - r, y - r, x + r, y + r], fill=255)
spots = spots.filter(ImageFilter.GaussianBlur(5))
col = Image.composite(Image.new("RGB", (S, S), (255, 248, 230)), col, spots)
# alpha: translucent body, brighter rim and veins, soft outer halo
alpha = mask.point(lambda v: int(v * 0.72))
alpha = ImageChops.lighter(alpha, rim.point(lambda v: int(v * 0.98)))
alpha = ImageChops.lighter(alpha, ImageChops.multiply(veins, mask).point(lambda v: int(v * 0.9)))
halo = mask.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * 0.3))
alpha = ImageChops.lighter(alpha, halo)
wing = col.copy(); wing.putalpha(alpha)
wing.resize((512, 512), Image.LANCZOS).save(f"{out}/butterfly_wing.png")
alpha.resize((512, 512), Image.LANCZOS).save(f"{out}/butterfly_wing_alpha.png")

# --- leaf sprite (sunlit leaf shadow motif) ---
L = 256
lm = Image.new("L", (L, L), 0); ld = ImageDraw.Draw(lm)
leaf = bez((128, 10), (230, 80), (200, 200), (128, 246)) + bez((128, 246), (56, 200), (26, 80), (128, 10))
ld.polygon(leaf, fill=230)
ld.line([(128, 30), (128, 236)], fill=150, width=6)
lm = lm.filter(ImageFilter.GaussianBlur(4))
lm.save(f"{out}/leaf_alpha.png")
li = Image.new("RGB", (L, L), (255, 255, 255)); li.putalpha(lm); li.save(f"{out}/leaf.png")

# --- soft glow disc ---
g = Image.new("L", (L, L), 0); gp = g.load()
for y in range(L):
    for x in range(L):
        r = math.hypot(x - L / 2, y - L / 2) / (L / 2)
        gp[x, y] = int(255 * max(0, math.exp(-r * r * 4.5) - 0.011))
g.save(f"{out}/glow_alpha.png")
gi = Image.new("RGB", (L, L), (255, 255, 255)); gi.putalpha(g); gi.save(f"{out}/glow.png")
print("ok")
