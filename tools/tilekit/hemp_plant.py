"""Hemp plant: one 42x42 image, top-down, dark pixel-art palette.

Seen from above, hemp is a rosette of fan leaves: each fan is a spray of long, thin, serrated
leaflets (the middle one longest) from one point. A lower tier of big fans points outward,
a smaller upper tier sits rotated between them, and a pale bud cluster crowns the middle.
Upper leaves cast a 1 px shadow down-right onto the lower ones; light from the top-left.
Yellower and lighter than the pines so the two never read alike.

Run:  python tools/tilekit/hemp_plant.py
      writes art/resources/hemp.png and tools/tilekit/preview/hemp_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 42
C = F / 2 - 0.5
S = F / 32.0            # the shapes were tuned at 32 px; everything scales with this

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "resources", "hemp.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "hemp_preview.png")

OUTLINE = (10, 20, 9)
LEAF = [                       # darkest -> lightest, yellow-green
	(18, 32, 13),
	(27, 47, 17),
	(38, 64, 22),
	(51, 82, 27),
	(66, 101, 33),
	(84, 120, 40),
	(104, 138, 50),
]
BUD = [(92, 112, 44), (124, 142, 60), (156, 168, 82)]
LIGHT = (-0.7071, -0.7071)

# Two looks, both a full rosette of 5 big fans with 5 smaller ones rotated between them:
#   "full"  - broad leaves, a dense star-shaped bush
#   "spiky" - fans start nearer the middle with longer, thinner fingers, so the edge is ragged
# Each: fans per tier as (distance of the fan's base from the centre, leaflet length,
# leaflet count), plus the fan's spread, leaflet half-widths (big, small fans), how fast the
# side leaflets shorten, and the depth of the edge serration.
PRESETS = {
	"full": dict(tiers=[(4.5, 9.5, 7), (2.0, 6.5, 5)], spread=130, widths=(1.25, 1.0), taper=(0.75, 1.3), teeth=0.18),
	"spiky": dict(tiers=[(2.5, 12.5, 7), (1.0, 7.5, 5)], spread=110, widths=(0.95, 0.8), taper=(0.9, 1.2), teeth=0.14),
}
STYLE = "spiky"
ANGLES = [(-90, -18, 54, 126, 198), (-54, 18, 90, 162, 234)]


def tiers(style):
	"""Fans per tier: (angle in degrees, base distance, leaflet length, leaflet count), scaled."""
	t = PRESETS[style]["tiers"]
	return [[(a, br * S, L * S, n) for a in ANGLES[k]] for k, (br, L, n) in enumerate(t)]


def leaflets(fan_angle, base_r, length, count, seed, style, big):
	"""(base point, direction, length, half-width) for each leaflet of one fan."""
	a = math.radians(fan_angle)
	bx, by = C + 0.5 + math.cos(a) * base_r, C + 0.5 + math.sin(a) * base_r
	out = []
	p = PRESETS[style]
	spread = math.radians(p["spread"])
	w = p["widths"][0 if big else 1] * S
	for i in range(count):
		t = i / (count - 1) - 0.5                  # -0.5 .. 0.5 across the fan
		d = a + t * spread
		L = length * (1.0 - p["taper"][0] * abs(t) ** p["taper"][1]) * (0.92 + 0.16 * h(seed, i, 1))
		out.append((bx, by, math.cos(d), math.sin(d), L, w, p["teeth"]))
	return out


def in_leaflet(x, y, lf):
	"""(inside?, position along 0..1, signed distance across) for a pixel centre."""
	bx, by, dx, dy, L, w, teeth = lf
	px, py = x + 0.5 - bx, y + 0.5 - by
	along = px * dx + py * dy
	across = -px * dy + py * dx
	if along < 0.6 or along > L:
		return False, 0, 0
	u = along / L
	width = w * math.sin(math.pi * min(1.0, u * 1.15)) ** 0.8   # thin lens, widest a bit past the middle
	# serrated edge: small teeth along the blade
	width *= 1.0 - teeth + teeth * abs(math.sin(along * 2.2 / S))
	return abs(across) <= width, u, across


def plant(style=STYLE):
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	tier_of = {}
	for k, fans in enumerate(tiers(style)):
		for f, (ang, br, L, n) in enumerate(fans):
			for lf in leaflets(ang + (h(k, f, 9) - 0.5) * 14, br, L, n, k * 10 + f, style, k == 0):
				for y in range(F):
					for x in range(F):
						inside, u, across = in_leaflet(x, y, lf)
						if not inside:
							continue
						v = 2.4 + k * 1.4
						v += 1.0 * -(lf[2] * LIGHT[0] + lf[3] * LIGHT[1]) * -1.0   # blades pointing at the light are lit
						v += 0.9 if abs(across) < 0.5 else 0.0                       # pale midrib
						v -= 0.8 * max(0.0, u - 0.7) / 0.3                           # tips a bit darker
						v += (h(x, y, k, 3) - 0.5) * 0.5
						px[x, y] = LEAF[max(0, min(len(LEAF) - 1, int(round(v))))]
						tier_of[(x, y)] = k
	# shadow of the upper tier on the lower one, 1 px down-right
	for (x, y), k in list(tier_of.items()):
		if tier_of.get((x - 1, y - 1), -1) > k:
			r, g, b, a = px[x, y]
			px[x, y] = (int(r * 0.62), int(g * 0.62), int(b * 0.62), a)
	# bud cluster in the middle
	for y in range(F):
		for x in range(F):
			d = math.hypot(x + 0.5 - (C + 0.5), y + 0.5 - (C + 0.5))
			if d < (2.3 + 0.5 * h(x, y, 7)) * S:
				lit = ((x - C) * LIGHT[0] + (y - C) * LIGHT[1]) / S
				i = 1 + (1 if lit > 0.3 else 0) - (1 if lit < -0.8 else 0)
				if h(x, y, 8) < 0.2:
					i = max(0, i - 1)
				px[x, y] = BUD[i]
				tier_of[(x, y)] = 9
	# outline
	for y in range(F):
		for x in range(F):
			if (x, y) in tier_of:
				continue
			if any((x + ox, y + oy) in tier_of for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
				px[x, y] = OUTLINE
	return img


def preview(im):
	W, H = 5 * 42, 3 * 42
	out = Image.new("RGBA", (W, H))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	for yy in range(0, H, g.height):
		for xx in range(0, W, g.width):
			out.paste(g, (xx, yy))
	shadow = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	shadow.putalpha(im.getchannel("A").point(lambda a: 90 if a else 0))
	for x, y in ((18, 18), (86, 52), (150, 14), (50, 76)):
		out.alpha_composite(shadow, (x + 2, y + 2))
		out.alpha_composite(im, (x, y))
	big = out.resize((W * 4, H * 4), Image.NEAREST)
	close = Image.new("RGBA", (F, F), (30, 52, 28, 255))
	close.alpha_composite(im)
	close = close.resize((F * 8, F * 8), Image.NEAREST)
	both = Image.new("RGBA", (big.width + close.width + 16, max(big.height, close.height)), (14, 14, 16, 255))
	both.paste(big, (0, 0))
	both.paste(close, (big.width + 16, 0))
	return both


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	im = plant()
	im.save(OUT)
	preview(im).save(PREVIEW)
	# side-by-side of both presets, for picking a look
	sheet = Image.new("RGBA", (F * 2 + 4, F), (30, 52, 28, 255))
	for i, style in enumerate(PRESETS):
		sheet.alpha_composite(plant(style), (i * (F + 4), 0))
	sheet.resize((sheet.width * 8, F * 8), Image.NEAREST).save(PREVIEW.replace(".png", "_styles.png"))
	print("wrote", OUT, "and", PREVIEW)
