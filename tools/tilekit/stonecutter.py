"""Stone cutter: three prototype concepts to pick from. 32x32, top-down, dark palette.

  A  mason's bench   - a timber bench: a rough boulder on one end, neat cut blocks on the
                       other, mallet and chisel lying between, stone chips about
  B  stone saw       - a heavy stone-slab table with a block clamped in the middle and a
                       big saw blade (edge-on) through it, a water trough along the back
  C  grinding wheel  - a timber frame holding a big round grindstone (seen from above, a
                       thick shaded drum) on an axle with a crank, cut blocks stacked beside

Run:  python tools/tilekit/stonecutter.py
      writes tools/tilekit/preview/stonecutter_concepts.png (and each concept as
      stonecutter_a/b/c.png in the preview folder; nothing in art/ until one is picked)
"""
import math
import os

from PIL import Image

from wood_walls import h
from furniture import finish, rect, shade, TABLE, STEEL, IRON, OUTLINE
import stone_node

F = 32
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PREVIEW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview")

STONE = [(36, 37, 42), (52, 53, 59), (70, 71, 77), (90, 91, 96), (112, 112, 116), (136, 136, 139)]
SLAB = [(44, 45, 50), (58, 59, 64), (72, 73, 78), (88, 89, 94)]
WATER = [(20, 34, 44), (30, 52, 66), (52, 84, 100)]
WOOD = [(50, 33, 21), (70, 47, 30), (92, 63, 40), (114, 80, 51)]
DUST = [(120, 120, 122), (150, 150, 152)]


def block(px, x0, y0, x1, y1, tone=0.0):
	"""A cut stone block from above: flat lit top with a bevelled edge."""
	for y in range(y0, y1):
		for x in range(x0, x1):
			v = 3.0 + tone
			if x == x0 or y == y0:
				v += 1.2
			if x == x1 - 1 or y == y1 - 1:
				v -= 1.5
			v += (h(x, y, 21) - 0.5) * 0.6
			px[x, y] = shade(STONE, v)


def chips(px, spots):
	for x, y in spots:
		px[x, y] = DUST[(x + y) % 2]


def concept_a():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	solid = rect(2, 6, 30, 26)
	for (x, y) in solid:
		fy = y - 6
		v = 1.8 + (0.6 if fy % 5 == 0 else 0) - (1.2 if fy % 5 == 4 else 0) + (h(x, y, 1) - 0.5) * 0.5
		v += 0.6 if (x == 2 or y == 6) else 0
		v -= 0.9 if (x == 29 or y == 25) else 0
		px[x, y] = shade(WOOD, v)
	# rough boulder on the left end (faceted, like the stone nodes)
	cover = set()
	stone_node.draw_rock(px, cover, 10.0, 14.0, 6.0, 7, 6)
	# a half-dressed edge: one flat cut face on the boulder's right side
	for y in range(9, 19):
		px[16, y] = STONE[4]
	# neat cut blocks on the right end, a 2x2 stack
	for i, (bx, by) in enumerate(((20, 9), (25, 9), (20, 14), (25, 14))):
		block(px, bx, by, bx + 4, by + 4, (h(i, 2) - 0.5) * 0.8)
	# mallet and chisel along the front of the bench, each outlined so they read on the wood
	tools = {}
	for (x, y) in rect(4, 20, 9, 25):                       # mallet head: a pale wooden block
		tools[(x, y)] = WOOD[3] if (x == 4 or y == 20) else (150, 112, 74) if (x, y) != (8, 24) else WOOD[2]
	for x in range(9, 15):                                  # its handle
		tools[(x, 22)] = (150, 112, 74) if x < 12 else WOOD[3]
	for x in range(17, 22):                                 # chisel: wooden grip
		tools[(x, 22)] = WOOD[3]
	for x in range(22, 27):                                 # and a bright steel blade
		tools[(x, 22)] = STEEL[3] if x < 26 else STEEL[2]
	tools[(26, 21)] = STEEL[2]
	for (x, y) in tools:
		for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q = (x + ox, y + oy)
			if q not in tools and q in solid:
				px[q] = OUTLINE
	for q, c in tools.items():
		px[q] = c
	chips(px, ((17, 12), (18, 16), (19, 19), (24, 19), (12, 19), (15, 9)))
	finish(img, solid)
	return img


def concept_b():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	solid = rect(2, 5, 30, 27)
	for (x, y) in solid:
		v = 2.0 + (h(x // 3, y // 3, 3) - 0.5) * 0.7
		v += 0.8 if (x == 2 or y == 5) else 0
		v -= 1.1 if (x == 29 or y == 26) else 0
		if (x - 2) % 14 == 13 or (y - 5) % 11 == 10:
			v -= 1.0                               # joints between the slabs
		px[x, y] = shade(SLAB, v)
	# water trough along the back edge
	for (x, y) in rect(4, 7, 28, 10):
		px[x, y] = WATER[1] if y == 8 else WATER[0]
		if (x + y) % 7 == 0:
			px[x, y] = WATER[2]
	# the block being cut, clamped in the middle
	block(px, 9, 13, 23, 23, 0.3)
	for (x, y) in rect(7, 16, 9, 20) | rect(23, 16, 25, 20):
		px[x, y] = IRON[1] if (x + y) % 2 else IRON[2]     # clamps
	# the saw: a long blade edge-on, cutting down the middle of the block, and its kerf
	for y in range(11, 26):
		px[15, y] = STEEL[3] if y % 3 == 0 else STEEL[2]
		px[16, y] = STEEL[1]
	for y in range(13, 23):
		px[17, y] = STONE[0]
	chips(px, ((14, 24), (18, 24), (13, 25), (19, 11), (13, 11)))
	finish(img, solid)
	return img


def concept_c():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	# timber frame: two side rails and two cross pieces
	solid = rect(3, 6, 29, 9) | rect(3, 23, 29, 26) | rect(3, 6, 6, 26) | rect(26, 6, 29, 26)
	for (x, y) in solid:
		v = 2.0 + (h(x, y, 4) - 0.5) * 0.6 + (0.7 if (x in (3,) or y in (6,)) else 0) - (0.8 if (x == 28 or y == 25) else 0)
		px[x, y] = shade(WOOD, v)
	# the grindstone: a drum seen from above, axle running left-right
	drum = rect(9, 9, 23, 23)
	for (x, y) in drum:
		u = (y + 0.5 - 16) / 7.0                   # across the drum: -1 top .. 1 bottom
		if abs(u) > 1:
			continue
		v = 3.4 - 2.6 * u - 1.2 * u * u            # cylinder lit from the top
		if (x - 9) in (0, 13):
			v -= 1.0                                # the drum's flat sides
		v += (h(x, y, 5) - 0.5) * 0.6
		px[x, y] = shade(STONE, v)
	solid |= drum
	# axle through the frame, crank handle off the right side
	for x in range(6, 31):
		if x < 9 or x > 22:
			px[x, 16] = IRON[2]
			px[x, 17] = IRON[1]
	for y in range(16, 22):
		px[30, y] = IRON[2]
	px[30, 21] = WOOD[3]
	px[30, 22] = WOOD[2]
	solid |= rect(29, 16, 31, 23) | rect(6, 16, 9, 18)
	# cut blocks stacked off the left end of the frame
	for i, by in enumerate((10, 15, 20)):
		block(px, 0, by, 3, by + 4, (h(i, 6) - 0.5) * 0.8)
	solid |= rect(0, 10, 3, 24)
	chips(px, ((12, 24), (19, 24), (16, 24), (21, 7), (10, 7)))
	finish(img, solid)
	return img


if __name__ == "__main__":
	concepts = [concept_a(), concept_b(), concept_c()]
	# A was picked: it's the game's stone cutter
	concepts[0].save(os.path.join(ROOT, "art", "structures", "stonecutter.png"))
	floor = Image.open(os.path.join(ROOT, "art", "structures", "wood_floor.png")).convert("RGBA")
	W = 3 * 48
	out = Image.new("RGBA", (W, 48))
	for xx in range(0, W, 32):
		for yy in (0, 32):
			out.paste(floor.crop(((xx // 32 % 4) * 32, 0, (xx // 32 % 4) * 32 + 32, 32)), (xx, yy))
	for i, im in enumerate(concepts):
		im.save(os.path.join(PREVIEW_DIR, "stonecutter_%s.png" % "abc"[i]))
		out.alpha_composite(im, (8 + i * 48, 8))
	out.resize((W * 7, 48 * 7), Image.NEAREST).save(os.path.join(PREVIEW_DIR, "stonecutter_concepts.png"))
	print("wrote concepts")
