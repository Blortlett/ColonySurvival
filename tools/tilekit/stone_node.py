"""Stone resource node: 4 depletion stages, top-down, dark pixel-art palette.

Each stage is its own 64x64 image (drawn centred on the node's cell, like the pines, so a
full rock spills a little past its cell). Stage 4 is a full outcrop: a big boulder with two
smaller stones beside it. Each stage below is the same outcrop mined down: the main boulder
shrinks, the side stones go, and broken rubble chips take their place, until stage 1 is one
small stone in a scatter of chips.

Rocks are faceted: each boulder is an irregular dome split into flat facets (Voronoi cells),
each facet lit as a flat plane from the top-left, so they read as chiselled stone.

Run:  python tools/tilekit/stone_node.py
      writes art/resources/stone_1.png .. stone_4.png and tools/tilekit/preview/stone_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 64
C = 31.5

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "resources")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "stone_preview.png")

OUTLINE = (13, 14, 17)
# darkest -> lightest, slightly cool so it sits apart from the warm wood and green grass
GREY = [
	(28, 29, 34),
	(40, 41, 47),
	(54, 55, 61),
	(69, 70, 76),
	(86, 87, 92),
	(104, 105, 109),
	(124, 124, 127),
	(146, 145, 146),
]
_L = (-0.55, -0.62, 0.56)
_n = math.sqrt(sum(c * c for c in _L))
LIGHT = tuple(c / _n for c in _L)


def blob_radius(theta, R, seed):
	"""Irregular, lumpy outline: a few low harmonics with per-rock phases."""
	r = 1.0
	for k, amp in ((2, 0.10), (3, 0.08), (5, 0.05)):
		r += amp * math.sin(k * theta + h(seed, k) * 6.283)
	return R * r


def dome_normal(dx, dy, R, seed):
	"""Normal of a squashed dome over the blob at offset (dx, dy)."""
	r = math.hypot(dx, dy)
	th = math.atan2(dy, dx)
	e = blob_radius(th, R, seed)
	t = min(0.97, r / e)
	z = math.sqrt(1.0 - t * t) * 0.8                 # flatter than a hemisphere
	if r < 1e-6:
		return (0.0, 0.0, 1.0)
	slope = t / max(z, 0.05) * 0.8
	nx, ny = dx / r * slope, dy / r * slope
	l = math.sqrt(nx * nx + ny * ny + 1.0)
	return (nx / l, ny / l, 1.0 / l)


def draw_rock(px, cover, cx, cy, R, seed, facets=7, palette=None, ore=None):
	"""Draw one faceted boulder centred at (cx, cy) with base radius R, over what's there.
	`palette` replaces GREY; `ore(seed, facet, x, y, dx, dy, R, v, crack)` may return a colour
	to paint over a pixel (ore veins, glints), or None to keep the rock shade."""
	palette = palette or GREY
	seeds = []
	for i in range(facets):
		a = h(seed, i, 1) * 6.283
		d = math.sqrt(h(seed, i, 2)) * R * 0.85
		seeds.append((math.cos(a) * d, math.sin(a) * d))
	seeds.append((-R * 0.15, -R * 0.15))           # a top facet catching the light
	normals = [dome_normal(sx, sy, R, seed) for sx, sy in seeds]
	mine = set()
	for y in range(int(cy - R * 1.3) - 1, int(cy + R * 1.3) + 2):
		for x in range(int(cx - R * 1.3) - 1, int(cx + R * 1.3) + 2):
			if not (0 <= x < F and 0 <= y < F):
				continue
			dx, dy = x + 0.5 - cx, y + 0.5 - cy
			r = math.hypot(dx, dy)
			e = blob_radius(math.atan2(dy, dx), R, seed)
			if r > e:
				continue
			# nearest + second-nearest facet seed (for crack lines on facet edges)
			ds = sorted((math.hypot(dx - sx, dy - sy), i) for i, (sx, sy) in enumerate(seeds))
			i = ds[0][1]
			n = normals[i]
			lit = n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]
			v = 0.6 + lit * 6.4
			v -= 1.4 * max(0.0, r / e - 0.78) / 0.22        # rim falls into shadow
			j = ds[1][1]
			apart = math.hypot(seeds[i][0] - seeds[j][0], seeds[i][1] - seeds[j][1])
			# seeds almost on top of each other would turn the "edge" into a whole patch
			crack = apart > 3.0 and ds[1][0] - ds[0][0] < 0.9 and h(seed, min(i, j), max(i, j), 4) < 0.6
			if crack:
				v -= 1.6                                   # crack along this facet edge
			v += (h(seed, x, y, 5) - 0.5) * 0.9           # grain speckle
			col = ore(seed, i, x, y, dx, dy, R, v, crack) if ore else None
			px[x, y] = col or palette[max(0, min(len(palette) - 1, int(round(v))))]
			mine.add((x, y))
	# outline just this rock, over anything under it
	for (x, y) in list(mine):
		for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q = (x + ox, y + oy)
			if q not in mine and 0 <= q[0] < F and 0 <= q[1] < F:
				px[q] = OUTLINE
				cover.add(q)
	cover |= mine


# Each stage: list of (x offset, y offset, radius, seed, facets), drawn back to front.
# The main boulder keeps seed 1 throughout so it's recognisably the same rock, shrinking.
STAGES = {
	4: [(-18, 11, 8.0, 21, 5), (19, 9, 6.5, 22, 4), (9, -19, 5.0, 23, 4), (0, 0, 17.0, 1, 9)],
	3: [(-17, 12, 6.5, 21, 4), (11, 12, 2.2, 31, 2), (15, 7, 1.8, 32, 2), (6, -13, 2.5, 33, 2), (1, 0, 14.0, 1, 8)],
	2: [(-12, 10, 2.6, 41, 2), (-9, 13, 1.8, 42, 2), (12, 10, 2.2, 31, 2), (14, -4, 1.8, 43, 2), (5, -11, 2.0, 33, 2), (1, 1, 10.5, 1, 6)],
	1: [(-9, 9, 2.0, 41, 2), (-12, 3, 1.6, 51, 2), (9, 10, 2.2, 31, 2), (11, -3, 1.6, 43, 2), (-3, -10, 1.8, 52, 2), (5, -8, 1.4, 53, 2), (1, 2, 6.5, 1, 4)],
}


def stage(n, palette=None, ore=None, seed_shift=0):
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	cover = set()
	for ox, oy, R, seed, facets in STAGES[n]:
		draw_rock(px, cover, C + 0.5 + ox, C + 0.5 + oy, R, seed + seed_shift, facets, palette, ore)
	return img


def preview(imgs):
	"""All four stages on the darkened grass with a soft offset shadow, 3x; plus a 6x row."""
	W, H = 4 * 80, 96
	out = Image.new("RGBA", (W, H))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	for yy in range(0, H, g.height):
		for xx in range(0, W, g.width):
			out.paste(g, (xx, yy))
	for i, n in enumerate((4, 3, 2, 1)):
		im = imgs[n]
		x, y = 8 + i * 80, 16
		shadow = Image.new("RGBA", (F, F), (0, 0, 0, 0))
		shadow.putalpha(im.getchannel("A").point(lambda a: 95 if a else 0))
		out.alpha_composite(shadow, (x + 2, y + 3))
		out.alpha_composite(im, (x, y))
	return out.resize((W * 3, H * 3), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	imgs = {}
	for n in (1, 2, 3, 4):
		imgs[n] = stage(n)
		imgs[n].save(os.path.join(OUT_DIR, "stone_%d.png" % n))
	preview(imgs).save(PREVIEW)
	print("wrote", OUT_DIR, "stone_1..4.png and", PREVIEW)
