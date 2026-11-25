"""Berry bush: 5 images, 42x42, top-down, dark pixel-art palette.

A round, domed bush built from overlapping leaf clumps (so the outline is softly scalloped
and the top reads as masses of foliage), lit from the top-left. bush_4.png carries 4 red
berries; each image below has one fewer (picked in the same order), down to bush_0.png with
none, so the game can show a bush being picked clean.

Run:  python tools/tilekit/berry_bush.py
      writes art/resources/bush_0.png .. bush_4.png and tools/tilekit/preview/bush_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 42
C = F / 2.0              # centre (pixel-centre coordinates)
BERRIES = 4

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "resources")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "bush_preview.png")

OUTLINE = (8, 19, 14)
LEAF = [                  # darkest -> lightest: a deep, slightly blue green (apart from hemp/pines)
	(12, 29, 21),
	(17, 40, 28),
	(23, 53, 35),
	(30, 67, 42),
	(39, 82, 49),
	(51, 98, 57),
	(66, 116, 66),
]
BERRY_OUT = (52, 8, 16)
BERRY = [(122, 16, 32), (176, 30, 44), (214, 58, 62)]
BERRY_HI = (246, 168, 158)
_L = (-0.55, -0.62, 0.56)
_n = math.sqrt(sum(c * c for c in _L))
LIGHT = tuple(c / _n for c in _L)

R = 16.5                  # bush radius
# Berry spots (offset from centre), in the order they're picked: the last one left is first.
SPOTS = [(-4, -5), (6, -1), (-6, 5), (3, 8)]


def clumps():
	"""Leaf clumps: (x, y, radius, height). A ring of clumps makes the scalloped rim, an inner
	ring and a crown clump build up the dome."""
	out = []
	n = 11
	for i in range(n):
		a = i / n * 6.283 + h(i, 1) * 0.3
		r = R - 4.2
		out.append((C + math.cos(a) * r, C + math.sin(a) * r, 4.6 + h(i, 2) * 0.9, 0.0))
	n = 6
	for i in range(n):
		a = i / n * 6.283 + 0.5 + h(i, 3) * 0.4
		r = 6.0
		out.append((C + math.cos(a) * r, C + math.sin(a) * r, 5.6 + h(i, 4) * 0.8, 0.45))
	out.append((C - 0.5, C - 0.5, 5.5, 0.85))
	return out


def bush():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	cl = clumps()
	cover = set()
	for y in range(F):
		for x in range(F):
			cx, cy = x + 0.5, y + 0.5
			best = None
			for i, (bx, by, br, bz) in enumerate(cl):
				d = math.hypot(cx - bx, cy - by)
				if d > br:
					continue
				t = d / br
				z = bz + math.sqrt(1.0 - t * t) * 0.55       # top of this clump
				if best is None or z > best[0]:
					best = (z, i, t, (cx - bx) / br, (cy - by) / br)
			if best is None:
				continue
			z, i, t, nx, ny = best
			# clump normal, tilted outward by the overall dome so the bush reads as round
			gx, gy = (cx - C) / R, (cy - C) / R
			nx, ny = nx * 0.75 + gx * 0.6, ny * 0.75 + gy * 0.6
			nz = math.sqrt(max(0.05, 1.0 - min(0.95, nx * nx + ny * ny)))
			l = math.sqrt(nx * nx + ny * ny + nz * nz)
			lit = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / l
			v = 0.4 + lit * 5.2 + z * 1.2
			v -= 1.3 * max(0.0, t - 0.8) / 0.2                # clump edges dip into shade
			v += (h(x, y, 5) - 0.5) * 1.0                       # leafy speckle
			if h(x // 2, y // 2, i, 6) < 0.12:
				v -= 0.9                                         # small gaps between leaves
			px[x, y] = LEAF[max(0, min(len(LEAF) - 1, int(round(v))))]
			cover.add((x, y))
	for y in range(F):
		for x in range(F):
			if (x, y) not in cover and any((x + ox, y + oy) in cover for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
				px[x, y] = OUTLINE
	return img


def add_berry(img, ox, oy):
	"""A round berry ~5 px across, with a highlight and a soft shadow on the leaves."""
	px = img.load()
	bx, by = C + ox, C + oy
	# shadow on the leaves, down-right
	for y in range(int(by) - 2, int(by) + 5):
		for x in range(int(bx) - 2, int(bx) + 5):
			if math.hypot(x + 0.5 - (bx + 1.2), y + 0.5 - (by + 1.4)) < 2.6:
				r, g, b, a = px[x, y]
				if a:
					px[x, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.55), a)
	for y in range(int(by) - 4, int(by) + 4):
		for x in range(int(bx) - 4, int(bx) + 4):
			d = math.hypot(x + 0.5 - bx, y + 0.5 - by)
			if d < 2.6:
				lit = -((x + 0.5 - bx) * 0.7 + (y + 0.5 - by) * 0.7) / 2.6
				px[x, y] = BERRY[max(0, min(2, int(round(1 + lit * 1.4))))]
			elif d < 3.5:
				px[x, y] = BERRY_OUT
	px[int(bx) - 1, int(by) - 1] = BERRY_HI


def stages():
	base = bush()
	out = {}
	for n in range(BERRIES + 1):
		im = base.copy()
		for ox, oy in SPOTS[:n]:
			add_berry(im, ox, oy)
		out[n] = im
	return out


def preview(imgs):
	W, H = 5 * 56, 72
	out = Image.new("RGBA", (W, H))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	for yy in range(0, H, g.height):
		for xx in range(0, W, g.width):
			out.paste(g, (xx, yy))
	for i, n in enumerate((4, 3, 2, 1, 0)):
		im = imgs[n]
		x, y = 7 + i * 56, 15
		shadow = Image.new("RGBA", (F, F), (0, 0, 0, 0))
		shadow.putalpha(im.getchannel("A").point(lambda a: 90 if a else 0))
		out.alpha_composite(shadow, (x + 2, y + 3))
		out.alpha_composite(im, (x, y))
	return out.resize((W * 4, H * 4), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	imgs = stages()
	for n, im in imgs.items():
		im.save(os.path.join(OUT_DIR, "bush_%d.png" % n))
	preview(imgs).save(PREVIEW)
	print("wrote", OUT_DIR, "bush_0..4.png and", PREVIEW)
