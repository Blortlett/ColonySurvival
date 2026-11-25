"""Top-down pine trees.

64x64 px, straight down, dark pixel-art palette. Seen from above a pine is a stack of
star-shaped tiers of branches: wide and dark at the bottom, smaller and lighter toward the
apex in the middle. Each tier casts a thin shadow on the one below, light comes from the
top-left, and radial needle streaks give it texture. VARIANTS trees side by side in one strip
(different branch counts, rotations and sizes).

Run:  python tools/tilekit/pine_tree.py
      writes art/trees/pine.png and tools/tilekit/preview/pine_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 64
C = 31.5
VARIANTS = 4

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "trees", "pine.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "pine_preview.png")

OUTLINE = (7, 15, 12)
# darkest -> lightest needle greens
GREEN = [
	(11, 24, 19),
	(15, 33, 25),
	(20, 44, 31),
	(27, 56, 37),
	(35, 69, 43),
	(46, 84, 50),
	(60, 101, 57),
	(78, 120, 66),
]
LIGHT = (-0.7071, -0.7071)          # light from the top-left


def tiers_for(var):
	"""(radius, branches, phase, spike depth) per tier, outermost first."""
	size = 0.9 + 0.1 * h(var, 1)
	out = []
	radii = (30.5, 23.5, 16.5, 9.5, 4.0)
	for k, r in enumerate(radii):
		n = (13, 11, 9, 7, 5)[k] + (1 if h(var, k, 2) < 0.4 else 0) - (1 if h(var, k, 9) < 0.25 and k < 3 else 0)
		out.append((r * size if k == 0 else r * (0.92 + 0.12 * h(var, k, 3)), n, h(var, k, 4) * 6.283, (0.42, 0.42, 0.40, 0.38, 0.25)[k]))
	return out


def edge(theta, r_max, n, phase, depth, var, k):
	"""Silhouette radius of a tier at angle theta: pointed branch tips with gaps between."""
	a = (theta + phase) * n / 6.283
	f = a - math.floor(a)                        # 0..1 across one branch
	tip = 1.0 - abs(f - 0.5) * 2.0               # 1 at the tip, 0 between branches
	tip = tip ** 1.3
	b = int(math.floor(a)) % n
	jag = 1.0 - 0.10 * h(var, k, b, 5)           # branches differ a bit in length
	# ragged needle tufts along the edge
	tuft = h(var, k, int((theta + 3.1416) / 6.283 * 140), 6) - 0.5
	return r_max * jag * ((1.0 - depth) + depth * tip) + tuft * (2.4 if k < 3 else 1.2)


def tree(var):
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	tiers = tiers_for(var)
	cover = {}
	for y in range(F):
		for x in range(F):
			dx, dy = x - C, y - C
			r = math.hypot(dx, dy)
			th = math.atan2(dy, dx)
			top = -1
			for k, (rm, n, ph, dp) in enumerate(tiers):
				if r <= edge(th, rm, n, ph, dp, var, k):
					top = k
			if top < 0:
				continue
			rm, n, ph, dp = tiers[top]
			e = edge(th, rm, n, ph, dp, var, top)
			v = 2.1 + top * 1.0                         # higher tiers are lighter
			# light from the top-left, strongest out at the rim
			if r > 0.01:
				v += 1.6 * (dx / r * LIGHT[0] + dy / r * LIGHT[1]) * min(1.0, r / 10.0)
			v -= 1.2 * max(0.0, (r / max(e, 0.01)) - 0.75)  # tips fade darker
			# each branch has a lit spine down its middle and darker flanks
			a = (th + ph) * n / 6.283
			spine = 1.0 - abs((a - math.floor(a)) - 0.5) * 2.0
			v += 1.1 * (spine - 0.5)
			# shadow from the tier above: just outside its silhouette
			if top + 1 < len(tiers):
				rm2, n2, ph2, dp2 = tiers[top + 1]
				gap = r - edge(th, rm2, n2, ph2, dp2, var, top + 1)
				if gap < 2.5:
					v -= 2.2 if gap < 1.5 else 1.1
			# needle streaks: thin radial strands, hashed per angular slot
			slot = int((th + 3.1416) / 6.283 * 90)
			v += (h(var, slot, int(r / 3), 7) - 0.5) * 0.7
			v += (h(var, x, y, 8) - 0.5) * 0.3
			if top == len(tiers) - 1 and r < 1.6:
				v = len(GREEN) - 1                     # the apex
			cover[(x, y)] = True
			px[x, y] = GREEN[max(0, min(len(GREEN) - 1, int(round(v))))]
	# outline: one px around the silhouette
	for y in range(F):
		for x in range(F):
			if (x, y) in cover:
				continue
			if any((x + ox, y + oy) in cover for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
				px[x, y] = OUTLINE
	return img


def strip():
	img = Image.new("RGBA", (F * VARIANTS, F), (0, 0, 0, 0))
	for v in range(VARIANTS):
		img.alpha_composite(tree(v), (v * F, 0))
	return img


def preview(trees):
	"""A small grove on the darkened grass with a soft offset shadow, 3x."""
	W, H = 9 * 32, 6 * 32
	out = Image.new("RGBA", (W, H))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	for yy in range(0, H, g.height):
		for xx in range(0, W, g.width):
			out.paste(g, (xx, yy))
	spots = [(16, 8, 0), (88, 30, 1), (40, 92, 2), (150, 12, 3), (200, 80, 1), (120, 110, 0), (222, 4, 2)]
	for x, y, v in spots:
		t = trees.crop((v * F, 0, v * F + F, F))
		shadow = Image.new("RGBA", (F, F), (0, 0, 0, 0))
		shadow.putalpha(t.getchannel("A").point(lambda a: 95 if a else 0))
		out.alpha_composite(shadow, (x + 5, y + 6))
	for x, y, v in spots:
		out.alpha_composite(trees.crop((v * F, 0, v * F + F, F)), (x, y))
	sheet = Image.new("RGBA", (W, F + 8), (14, 14, 16, 255))
	sheet.alpha_composite(trees, (0, 4))
	both = Image.new("RGBA", (W, H + F + 8))
	both.paste(out, (0, 0))
	both.paste(sheet, (0, H))
	return both.resize((both.width * 3, both.height * 3), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	s = strip()
	s.save(OUT)
	preview(s).save(PREVIEW)
	print("wrote", OUT, "and", PREVIEW)
