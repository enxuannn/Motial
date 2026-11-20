"""Activity covers for Steady's plan tiles and the daily check-in: one distinct, calm artwork per activity,
in the brand moodboard (dawn lake & orbs, sunlit leaves, sky lanterns, river stones, glowing particles).
No people (no coach in menus). The app draws the SF Symbol and text on top."""
import numpy as np, math, sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont
ART = '../../Motial/Assets.xcassets/'
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
W, H = 1200, 520
rng = np.random.default_rng(3)
CREAM = (255, 244, 224); DAWN = (156, 195, 255); LILAC = (201, 182, 255); PEACH = (255, 199, 154); AMBER = (255, 190, 110); FIREFLY = (255, 236, 150)

def bg(name, x0=0.5, y0=0.5, zoom=1.0, warm=0.0, bright=1.0):
    im = Image.open(ART + f'art_{name}.imageset/art_{name}.jpg').convert('RGB')
    iw, ih = im.size
    cw = iw / zoom; ch = cw * H / W
    if ch > ih: ch = ih; cw = ch * W / H
    l = (iw - cw) * x0; t = (ih - ch) * y0
    im = im.crop((int(l), int(t), int(l + cw), int(t + ch))).resize((W, H), Image.LANCZOS)
    if warm:
        a = np.asarray(im).astype(np.float32); a[..., 0] *= 1 + warm; a[..., 2] *= 1 - warm * 0.6
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return ImageEnhance.Brightness(im).enhance(bright).convert('RGBA')

def glow_layer(draw_fn, blur=14, strength=1.0):
    sharp = Image.new('RGBA', (W, H), (0, 0, 0, 0)); draw_fn(ImageDraw.Draw(sharp))
    g = sharp.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(g).astype(np.float32); a[..., 3] = np.clip(a[..., 3] * 1.8 * strength, 0, 255)
    return Image.alpha_composite(Image.fromarray(a.astype(np.uint8)), sharp)

def orb(d, x, y, r, c, a=255): d.ellipse((x - r, y - r, x + r, y + r), fill=c + (a,))

def leaf(d, x, y, s, ang, c, a=230):
    pts = []
    for t in np.linspace(0, math.pi, 18):
        pts.append((math.cos(t) * s, math.sin(t) * s * 0.42))
    for t in np.linspace(math.pi, 2 * math.pi, 18):
        pts.append((math.cos(t) * s, math.sin(t) * s * 0.42))
    ca, sa = math.cos(ang), math.sin(ang)
    d.polygon([(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts], fill=c + (a,))

def lantern(d, x, y, s, a=255):
    d.rounded_rectangle((x - s * 0.5, y - s * 0.7, x + s * 0.5, y + s * 0.7), radius=s * 0.35, fill=AMBER + (a,))
    d.rounded_rectangle((x - s * 0.32, y - s * 0.45, x + s * 0.32, y + s * 0.5), radius=s * 0.25, fill=(255, 226, 170, a))

def stone(d, x, y, w, c=(120, 128, 150), a=255):
    d.ellipse((x - w, y - w * 0.32, x + w, y + w * 0.32), fill=c + (a,))
    d.ellipse((x - w * 0.8, y - w * 0.3, x + w * 0.7, y + w * 0.12), fill=tuple(min(255, v + 40) for v in c) + (a,))

def ring(d, x, y, rx, ry, c, wdt=5, a=255): d.ellipse((x - rx, y - ry, x + rx, y + ry), outline=c + (a,), width=wdt)

def particles(d, n, box, c, rmax=4, seed=1):
    r = np.random.default_rng(seed)
    for _ in range(n):
        x, y = r.uniform(box[0], box[2]), r.uniform(box[1], box[3]); rr = r.uniform(1.2, rmax)
        orb(d, x, y, rr, c, int(r.uniform(120, 255)))

def lotus(d, x, y, s, open_=1.0):
    for k, (ang, c) in enumerate([(-0.9, LILAC), (0.9, LILAC), (-0.45, (230, 214, 255)), (0.45, (230, 214, 255)), (0, CREAM)]):
        a = ang * open_
        pts = []
        for t in np.linspace(0, 1, 20):
            w = math.sin(t * math.pi) * s * 0.28
            pts.append((w, -t * s))
        for t in np.linspace(1, 0, 20):
            w = math.sin(t * math.pi) * s * 0.28
            pts.append((-w, -t * s))
        ca, sa = math.cos(a), math.sin(a)
        d.polygon([(x + px * ca - py * sa, y + px * sa + py * ca) for px, py in pts], fill=c + (235,))
    d.ellipse((x - s * 0.7, y - s * 0.08, x + s * 0.7, y + s * 0.16), fill=(110, 170, 150, 200))

def arc_pts(x0, y0, x1, y1, h, n=40):
    return [(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t - h * 4 * t * (1 - t)) for t in np.linspace(0, 1, n)]

def dotted(d, pts, c, r=4, every=2):
    for i, (x, y) in enumerate(pts):
        if i % every == 0: orb(d, x, y, r, c, 230)

def save(im, name):
    im = im.convert('RGB'); im.save(OUT + f'{name}.jpg', quality=88)

# ---------- covers ----------
def c_ankle_pumps():
    im = bg('dawn_lake', 0.3, 0.6)
    def f(d):
        for i, t in enumerate(np.linspace(0, 1, 9)):
            x = 380 + t * 520; y = 300 - 120 * math.sin(t * math.pi * 2)
            orb(d, x, y, 10 + 4 * (i % 2), CREAM)
        particles(d, 40, (300, 120, 1000, 420), DAWN, 3, 2)
    return Image.alpha_composite(im, glow_layer(f, 16))
def c_ankle_alphabet():
    im = bg('dawn_lake', 0.7, 0.5, 1.2)
    def f(d):
        try: font = ImageFont.truetype('/usr/share/fonts/opentype/inter/Inter-Bold.otf', 170)
        except Exception: font = ImageFont.load_default()
        for i, ch in enumerate('ABC'):
            d.text((380 + i * 170, 170 + (i % 2) * 30), ch, font=font, fill=CREAM + (200 - i * 40,))
        particles(d, 50, (350, 120, 950, 420), FIREFLY, 3, 5)
    return Image.alpha_composite(im, glow_layer(f, 12, 0.9))
def c_seated_eversion():
    im = bg('river_valley', 0.2, 0.5, 1.1)
    def f(d):
        for i in range(7):
            leaf(d, 520 + i * 70, 260 - i * 18 + (i % 2) * 20, 46, -0.2 - i * 0.22, (255, 226, 140) if i % 2 else (190, 230, 150))
        particles(d, 30, (450, 120, 1050, 400), FIREFLY, 3, 7)
    return Image.alpha_composite(im, glow_layer(f, 10))
def c_calf_raise():
    im = bg('golden_meadow', 0.4, 0.5)
    def f(d):
        for i in range(5):
            d.rounded_rectangle((420 + i * 90, 380 - i * 55, 500 + i * 90, 392 - i * 55), 6, fill=CREAM + (230,))
        orb(d, 860, 120, 16, FIREFLY)
        particles(d, 30, (400, 100, 950, 400), FIREFLY, 3, 9)
    return Image.alpha_composite(im, glow_layer(f, 14))
def c_knee_to_wall():
    im = bg('golden_meadow', 0.8, 0.5, 1.15, warm=0.03)
    def f(d):
        d.rounded_rectangle((760, 60, 800, 470), 18, fill=CREAM + (210,))
        for i in range(6):
            orb(d, 520 + i * 40, 330 - i * 6, 8, PEACH)
        particles(d, 25, (500, 100, 900, 450), FIREFLY, 3, 11)
    return Image.alpha_composite(im, glow_layer(f, 14))
def c_supported_sls():
    im = bg('dawn_lake', 0.55, 0.6, 1.3)
    def f(d):
        d.rounded_rectangle((330, 250, 900, 262), 6, fill=CREAM + (200,))
        lotus(d, 640, 420, 110, 0.35)
        particles(d, 30, (300, 100, 1000, 400), DAWN, 3, 13)
    return Image.alpha_composite(im, glow_layer(f, 12))
def c_single_leg_stance():
    im = bg('dawn_lake', 0.5, 0.65, 1.0)
    def f(d):
        for r in (60, 110, 170): ring(d, 600, 430, r * 1.6, r * 0.35, CREAM, 3, 120)
        lotus(d, 600, 430, 170, 1.0)
        particles(d, 60, (250, 80, 950, 380), FIREFLY, 4, 15)
    return Image.alpha_composite(im, glow_layer(f, 16))
def c_sls_head_turns():
    im = bg('dawn_lake', 0.15, 0.4, 1.2)
    def f(d):
        d.arc((300, 120, 900, 520), 200, 340, fill=CREAM + (220,), width=8)
        orb(d, 340, 300, 14, PEACH); orb(d, 860, 300, 14, PEACH); orb(d, 600, 140, 18, CREAM)
        particles(d, 30, (250, 80, 950, 400), DAWN, 3, 17)
    return Image.alpha_composite(im, glow_layer(f, 12))
def c_sls_reach_catch():
    im = bg('golden_meadow', 0.25, 0.45)
    def f(d):
        pts = arc_pts(240, 420, 880, 230, 230)
        dotted(d, pts, CREAM, 4, 2)
        orb(d, 880, 230, 30, (250, 248, 240))
        d.arc((858, 208, 902, 252), 300, 60, fill=(220, 90, 80, 255), width=3)
        d.arc((858, 208, 902, 252), 120, 240, fill=(220, 90, 80, 255), width=3)
        particles(d, 30, (300, 100, 1000, 420), FIREFLY, 3, 19)
    return Image.alpha_composite(im, glow_layer(f, 12))
def c_sl_mini_squat():
    im = bg('golden_meadow', 0.65, 0.6, 1.2)
    def f(d):
        d.arc((420, 120, 780, 480), 20, 160, fill=CREAM + (220,), width=10)
        orb(d, 600, 480, 16, PEACH)
        particles(d, 30, (350, 100, 900, 420), FIREFLY, 3, 21)
    return Image.alpha_composite(im, glow_layer(f, 14))
def c_sl_calf_raise():
    im = bg('aurora_night', 0.6, 0.5, 1.1)
    def f(d):
        for i in range(6): lantern(d, 520 + (i % 2) * 120 + i * 18, 420 - i * 60, 24 + i * 2)
        particles(d, 40, (300, 60, 1000, 450), FIREFLY, 3, 23)
    return Image.alpha_composite(im, glow_layer(f, 16))
def c_stepping_stones():
    im = bg('river_valley', 0.5, 0.75, 1.0)
    def f(d):
        for i, (x, y, w) in enumerate([(380, 440, 70), (560, 380, 58), (700, 330, 48), (820, 290, 40), (920, 258, 32)]):
            stone(d, x, y, w)
            ring(d, x, y + 4, w * 1.35, w * 0.45, CREAM, 3, 140)
        particles(d, 25, (300, 200, 1000, 480), CREAM, 3, 25)
    return Image.alpha_composite(im, glow_layer(f, 8))
def c_rhythm_steps():
    im = bg('aurora_night', 0.4, 0.6)
    def f(d):
        for i, (x, y) in enumerate([(420, 420), (600, 440), (780, 420), (600, 360)]):
            ring(d, x, y, 80, 24, DAWN if i != 1 else FIREFLY, 6)
        for i in range(9): lantern(d, 260 + i * 95, 110 + (i % 3) * 40, 16)
    return Image.alpha_composite(im, glow_layer(f, 14))
def c_hop_forward():
    im = bg('river_valley', 0.8, 0.7, 1.15)
    def f(d):
        stone(d, 380, 440, 60); stone(d, 820, 400, 60)
        dotted(d, arc_pts(390, 410, 820, 370, 200), CREAM, 5, 2)
        for k in range(8): leaf(d, 820 + math.cos(k) * 90, 380 + math.sin(k * 1.7) * 30, 16, k, (255, 226, 140))
    return Image.alpha_composite(im, glow_layer(f, 10))
def c_side_hop():
    im = bg('golden_meadow', 0.1, 0.65, 1.2)
    def f(d):
        ring(d, 420, 420, 90, 26, CREAM, 6); ring(d, 780, 420, 90, 26, CREAM, 6)
        dotted(d, arc_pts(440, 400, 760, 400, 150), PEACH, 5, 2)
        dotted(d, arc_pts(760, 430, 440, 430, -60), (255, 255, 255), 3, 3)
        particles(d, 30, (300, 100, 950, 400), FIREFLY, 3, 27)
    return Image.alpha_composite(im, glow_layer(f, 12))
def c_river_hops():
    im = bg('river_valley', 0.35, 0.8, 1.05)
    def f(d):
        pts = [(330, 450), (520, 390), (690, 345), (840, 305)]
        for x, y in pts: stone(d, x, y, 48)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]): dotted(d, arc_pts(x0, y0 - 20, x1, y1 - 20, 90, 24), CREAM, 4, 2)
        for k in range(10): orb(d, 840 + math.cos(k) * 60, 290 - abs(math.sin(k * 2.1)) * 50, 4, DAWN)
    return Image.alpha_composite(im, glow_layer(f, 8))

def c_checkin():
    im = bg('dawn_lake', 0.5, 0.45, 1.0, bright=1.05)
    def f(d):
        for r, a in ((70, 230), (130, 150), (200, 90), (280, 50)): ring(d, 860, 250, r, r, CREAM, 5, a)
        orb(d, 860, 250, 30, CREAM)
        particles(d, 60, (500, 60, 1150, 460), DAWN, 3, 31)
    return Image.alpha_composite(im, glow_layer(f, 14))

COVERS = {k[2:]: v for k, v in list(globals().items()) if k.startswith('c_')}

def court_covers(court_png):
    """Sport drills: crops of the Sunset Court render with a motif per drill."""
    base = Image.open(court_png).convert('RGB')
    def crop(x0, y0, w):
        h = w * H / W
        y0 = min(y0, base.size[1] - h)
        return base.crop((x0, y0, x0 + w, y0 + h)).resize((W, H), Image.LANCZOS).convert('RGBA')
    out = {}
    im = crop(380, 120, 1150)
    def f(d):
        dotted(d, arc_pts(200, 470, 700, 170, 230), CREAM, 5, 2)
        orb(d, 700, 170, 22, (255, 140, 70))
    out['bb_set_shot'] = Image.alpha_composite(im, glow_layer(f, 10))
    im = crop(200, 430, 1500)
    def f(d):
        ring(d, 450, 400, 110, 32, CREAM, 6); ring(d, 750, 400, 110, 32, CREAM, 6)
        for k in range(14): orb(d, 600 + math.cos(k) * 220, 380 - abs(math.sin(k * 1.3)) * 70, 4, FIREFLY)
    out['bb_jump_stop'] = Image.alpha_composite(im, glow_layer(f, 12))
    im = crop(100, 343, 1700)
    def f(d):
        for i in range(5): ring(d, 260 + i * 170, 420 - (i % 2) * 20, 70, 20, PEACH if i % 2 else DAWN, 5)
        d.line([(260, 440), (940, 440)], fill=CREAM + (140,), width=3)
    out['bb_defensive_slide'] = Image.alpha_composite(im, glow_layer(f, 12))
    im = crop(300, 495, 1350)
    def f(d):
        for i, (x, y) in enumerate([(300, 450), (470, 400), (620, 350)]): ring(d, x, y, 60, 18, [DAWN, LILAC, FIREFLY][i], 6)
        dotted(d, arc_pts(620, 330, 820, 150, 120), CREAM, 5, 2)
    out['bb_layup_footwork'] = Image.alpha_composite(im, glow_layer(f, 12))
    return out

if __name__ == '__main__':
    for k, fn in COVERS.items():
        save(fn(), 'cover_' + k if k != 'checkin' else 'art_checkin')
    if len(sys.argv) > 2:
        for k, im in court_covers(sys.argv[2]).items(): save(im, 'cover_' + k)
    print('ok', len(COVERS))
