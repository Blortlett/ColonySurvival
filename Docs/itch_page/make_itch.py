"""Build itch.io banner + tiled background from the game's own sprites."""
import random, sys, os
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

ROOT = sys.argv[1]
OUT = sys.argv[2]
TITLE = sys.argv[3] if len(sys.argv) > 3 else "Anarchy Colony Sim"
A = lambda p: Image.open(os.path.join(ROOT, "art", p)).convert("RGBA")
rng = random.Random(7)
T = 32

def frame(sheet, i=0, size=None):
    s = size or sheet.height
    return sheet.crop((i * s, 0, i * s + s, s))

# ---------- ground ----------
grass = A("ground/grass_atlas.png")
gvars = [frame(grass, i, 80) for i in range(5)]
gweights = [5, 3, 3, 1, 2]

def ground(w, h, seed=1):
    r = random.Random(seed)
    img = Image.new("RGBA", (w, h))
    for y in range(0, h, 80):
        for x in range(0, w, 80):
            img.paste(r.choices(gvars, gweights)[0], (x, y))
    return img

# ---------- banner (native px, upscaled 2x) ----------
W, H = 480, 150
img = ground(W, H)

def shadow(sprite, off=(2, 3), a=90):
    m = sprite.split()[3].point(lambda v: a if v > 0 else 0)
    sh = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    sh.putalpha(m)
    return sh, off

def place(sprite, x, y, sh=True, off=(2, 3)):
    if sh:
        s, o = shadow(sprite, off)
        img.alpha_composite(s, (x + o[0], y + o[1]))
    img.alpha_composite(sprite, (x, y))

# roads
road = A("structures/road_stone.png")
def road_cell(cx, cy):
    img.alpha_composite(frame(road, rng.randrange(4), 32), (cx * T, cy * T))

# walls via neighbour mask
def build(sheet, cells, floor=True, ox=0, oy=0):
    cs = set(cells)
    if floor:
        fl = A("structures/wood_floor.png")
        xs = [c[0] for c in cells]; ys = [c[1] for c in cells]
        for cy in range(min(ys) + 1, max(ys)):
            for cx in range(min(xs) + 1, max(xs)):
                if (cx, cy) not in cs:
                    img.alpha_composite(frame(fl, rng.randrange(4), 32), (ox + cx * T, oy + cy * T))
    for (cx, cy) in cells:
        m = ((cx, cy - 1) in cs) | ((cx + 1, cy) in cs) << 1 | ((cx, cy + 1) in cs) << 2 | ((cx - 1, cy) in cs) << 3
        tile = sheet.crop(((m & 3) * T, (m >> 2) * T, (m & 3) * T + T, (m >> 2) * T + T))
        img.alpha_composite(tile, (ox + cx * T, oy + cy * T))

def ring(x0, y0, x1, y1, door=None):
    out = []
    for x in range(x0, x1 + 1):
        out += [(x, y0), (x, y1)]
    for y in range(y0 + 1, y1):
        out += [(x0, y), (x1, y)]
    return [c for c in dict.fromkeys(out) if c != door]

# road running between the two holds
for cx in range(3, 13):
    road_cell(cx, 3)

# stone keep, left, partly off-canvas
build(A("structures/stone_walls.png"), ring(-2, -1, 2, 3, door=(2, 2)), oy=6)
# wooden hall, right
build(A("structures/wood_walls.png"), ring(12, 0, 16, 3, door=(12, 2)), oy=6)

camp = A("structures/campfire.png")
img.alpha_composite(frame(camp, 3, 32), (0 * T, 1 * T + 6))
img.alpha_composite(A("structures/chest_iron.png"), (1 * T, 0 * T + 6 + 4))
img.alpha_composite(A("structures/anvil.png"), (-1 * T + 26, 2 * T + 6))
img.alpha_composite(frame(camp, 5, 32), (14 * T, 1 * T + 6))
img.alpha_composite(A("structures/crate.png"), (13 * T, 1 * T + 6))
img.alpha_composite(A("structures/task_board.png"), (11 * T - 4, 4 + 6))

# nature
pines = A("trees/pine.png")
for (x, y) in [(96, -24), (150, 96), (300, -30), (350, 100), (220, 112), (395, 110), (60, 112)]:
    place(frame(pines, rng.randrange(4), 64), x, y, off=(4, 6))
for (x, y, f) in [(118, 70, "resources/stone_2.png"), (330, 60, "resources/iron_1.png"), (190, -8, "resources/bush_1.png"), (262, 120, "resources/bush_3.png")]:
    place(A(f), x, y)

# ---------- agents ----------
def agent(gear, weapon, act, f, ang, tone="light"):
    def L(p):
        try: return A("characters/human/" + p)
        except FileNotFoundError: return None
    stance = f"{weapon}_{act}" if weapon else act
    layers = [
        L(f"human_legs_{'walk' if act=='walk' else 'idle'}_{tone}_Sheet.png"),
        L(f"human_outfit_legs_{gear}_{'walk' if act=='walk' else 'idle'}_{tone}_Sheet.png"),
        L(f"human_body_{stance}_{tone}_Sheet.png"),
        L(f"human_outfit_torso_{gear}_{stance}_{tone}_Sheet.png"),
        L(f"human_outfit_head_{gear}_{stance}_{tone}_Sheet.png"),
        L(f"item_{stance}_Sheet.png") if weapon else None,
    ]
    out = Image.new("RGBA", (48, 48))
    for l in layers:
        if l is not None:
            n = l.width // 48
            out.alpha_composite(frame(l, min(f, n - 1), 48))
    return out.rotate(ang, resample=Image.NEAREST)

# defenders out the keep door (facing right = 0 deg), raiders coming from the right (180)
crew = [
    ("iron", "sword", "swing", 2, 0, 92, 82), ("iron", "spear", "thrust", 3, -15, 78, 104),
    ("iron", "bow", "fire", 3, 10, 52, 66),
    ("peasant", "club", "swing", 2, 180, 300, 86), ("peasant", "axe", "walk", 1, 195, 330, 66),
    ("peasant", "spear", "walk", 4, 170, 352, 100), ("peasant", "sword", "walk", 2, 185, 382, 80),
    ("peasant", None, "gather", 3, 70, 214, 6),
]
for gear, wpn, act, f, ang, x, y in crew:
    place(agent(gear, wpn, act, f, ang), x, y, off=(1, 2))

# ---------- grade: darken + warm + vignette + title band ----------
img = ImageEnhance.Color(img).enhance(0.75)
img = ImageEnhance.Brightness(img).enhance(0.62)
shade = Image.new("L", (W, H))
sd = shade.load()
for y in range(H):
    for x in range(W):
        dx = (x - W / 2) / (W / 2); dy = (y - H / 2) / (H / 2)
        band = max(0.0, 1 - abs(dy) * 1.6) * max(0.0, 1 - abs(dx) * 1.25)
        vig = min(1.0, (dx * dx * 0.5 + dy * dy * 0.6))
        sd[x, y] = int(255 * min(0.82, band * 0.7 + vig * 0.55))
dark = Image.new("RGBA", (W, H), (26, 22, 20, 255))
img = Image.composite(dark, img, shade)

big = img.resize((W * 2, H * 2), Image.NEAREST)

# ---------- title (rendered non-AA at native scale, then 2x for crisp pixels) ----------
font_path = "C:/Windows/Fonts/georgiab.ttf"
size = 30
font = ImageFont.truetype(font_path, size)
txt = TITLE
tmp = Image.new("L", (W, 60))
d = ImageDraw.Draw(tmp); d.fontmode = "1"
bbox = d.textbbox((0, 0), txt, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
mask = Image.new("L", (tw + 8, th + 8))
md = ImageDraw.Draw(mask); md.fontmode = "1"
md.text((4 - bbox[0], 4 - bbox[1]), txt, font=font, fill=255)
# gold gradient fill
fill = Image.new("RGBA", mask.size)
fp = fill.load()
for y in range(mask.height):
    t = y / mask.height
    c = (int(250 - 60 * t), int(214 - 80 * t), int(90 - 50 * t), 255) if t < 0.55 else (int(214 - 40 * t), int(150 - 40 * t), int(40 - 20 * t), 255)
    for x in range(mask.width):
        fp[x, y] = c
outline = mask.filter(ImageFilter.MaxFilter(3))
title = Image.new("RGBA", mask.size)
title.paste((20, 12, 8, 255), (0, 0), outline)
title.paste(fill, (0, 0), mask)
crown = A("icon/crown_icon.png").resize((28, 28), Image.NEAREST)
tx = (W - title.width) // 2; ty = (H - title.height) // 2 + 8
lay = Image.new("RGBA", (W, H))
sh = Image.new("RGBA", title.size, (0, 0, 0, 0)); sh.putalpha(outline.point(lambda v: 160 if v else 0))
lay.alpha_composite(sh, (tx + 2, ty + 2))
lay.alpha_composite(title, (tx, ty))
lay.alpha_composite(crown, ((W - 28) // 2, ty - 27))
# tagline
small = ImageFont.truetype("C:/Windows/Fonts/georgiab.ttf", 11)
tag = "ONE LIFE.  NO RULERS.  YET."
tb = ImageDraw.Draw(lay).textbbox((0, 0), tag, font=small)
tagm = Image.new("L", (tb[2] - tb[0] + 10, tb[3] - tb[1] + 4))
tdd = ImageDraw.Draw(tagm); tdd.fontmode = "1"
tdd.text((2 - tb[0], 2 - tb[1]), tag, font=small, fill=255)
tagimg = Image.new("RGBA", tagm.size)
tagimg.paste((20, 12, 8, 255), (0, 0), tagm.filter(ImageFilter.MaxFilter(3)))
tagimg.paste((232, 220, 196, 255), (0, 0), tagm)
lay.alpha_composite(tagimg, ((W - tagimg.width) // 2, ty + title.height + 2))

big.alpha_composite(lay.resize((W * 2, H * 2), Image.NEAREST))
os.makedirs(OUT, exist_ok=True)
big.convert("RGB").save(os.path.join(OUT, "banner.png"))

# ---------- tiled background (seamless: whole 80px tiles, wraps) ----------
bg = ground(320, 320, seed=3)
bg = ImageEnhance.Color(bg).enhance(0.55)
bg = ImageEnhance.Brightness(bg).enhance(0.30)
tint = Image.new("RGBA", bg.size, (26, 22, 20, 255))
bg = Image.blend(bg, tint, 0.35)
bg.resize((640, 640), Image.NEAREST).convert("RGB").save(os.path.join(OUT, "background_tile.png"))
print("ok", tw, th)
