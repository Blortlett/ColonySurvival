"""Iron ore resource node: 4 depletion stages, matching stone_node.py.

Same outcrop layouts and faceted top-down rocks as stone (so the two read as the same family),
but the rock is a darker, warmer near-black, rust-orange ore veins run across every boulder,
cracks are stained rust, and a few lit facets catch small metallic glints.

Run:  python tools/tilekit/iron_node.py
      writes art/resources/iron_1.png .. iron_4.png and tools/tilekit/preview/iron_preview.png
"""
import math
import os

import stone_node
from wood_walls import h

OUT_DIR = stone_node.OUT_DIR
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "iron_preview.png")

# darkest -> lightest: dark ironstone, a touch warm
ROCK = [
	(22, 19, 20),
	(32, 28, 29),
	(43, 38, 38),
	(55, 49, 48),
	(68, 61, 59),
	(83, 75, 71),
	(99, 90, 85),
	(116, 106, 99),
]
RUST = [(74, 32, 16), (116, 52, 22), (160, 78, 30), (200, 112, 44)]   # dark -> bright
GLINT = (176, 164, 150)
VEINS = 2           # vein bands per boulder


def ore(seed, facet, x, y, dx, dy, R, v, crack):
	shade = max(0.0, min(1.0, v / 7.0))                # how lit this pixel is
	if crack:
		return RUST[0] if shade < 0.55 else RUST[1]
	# veins: wavy bands across the boulder, a different angle per rock
	for k in range(VEINS if R > 3 else 1):
		a = h(seed, k, 61) * 3.1416
		u = dx * math.cos(a) + dy * math.sin(a)          # across the band
		w = -dx * math.sin(a) + dy * math.cos(a)         # along it
		centre = (h(seed, k, 62) - 0.5) * R * 0.9 + math.sin(w * 0.45 + h(seed, k, 63) * 6.283) * 1.6
		width = 0.55 + 0.35 * math.sin(w * 0.3 + k) + (0.25 if R > 10 else 0.0)
		if abs(u - centre) < width:
			# blotchy: let the rock break through now and then
			if h(seed, x, y, 64) < 0.12:
				return None
			i = int(shade * 3.6 + (h(seed, x, y, 65) - 0.5) * 0.8)
			return RUST[max(0, min(3, i))]
	# small rust flecks scattered over the rock
	if h(seed, x, y, 66) < 0.018:
		return RUST[1] if shade < 0.5 else RUST[2]
	# metallic glints on well-lit facets
	if shade > 0.78 and h(seed, x, y, 67) < 0.03:
		return GLINT
	return None


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	imgs = {}
	for n in (1, 2, 3, 4):
		imgs[n] = stone_node.stage(n, palette=ROCK, ore=ore, seed_shift=100)
		imgs[n].save(os.path.join(OUT_DIR, "iron_%d.png" % n))
	stone_node.preview(imgs).save(PREVIEW)
	print("wrote", OUT_DIR, "iron_1..4.png and", PREVIEW)
