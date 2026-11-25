"""Anvil: one 32x32 image, straight top-down, dark pixel-art palette.

From above an anvil is its flat working face: a long block with a tapering conical horn at
one end and a square heel at the other, pierced by the square hardy hole and the round
pritchel hole. Its waist and feet spread a little wider underneath, showing as a darker rim.
It sits on a round wooden stump (rings on top, bark at the edge). Light from the top-left,
so the face carries a polished highlight along its top edge and the horn is lit on one side.

Run:  python tools/tilekit/anvil.py
      writes art/structures/anvil.png and tools/tilekit/preview/anvil_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 32

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "structures", "anvil.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "anvil_preview.png")

OUTLINE = (12, 12, 15)
IRON = [(24, 25, 29), (36, 37, 43), (50, 51, 58), (66, 67, 75), (84, 85, 93), (108, 110, 118), (150, 152, 160)]
BARK = [(30, 20, 13), (44, 29, 18)]
RINGS = [(84, 58, 36), (104, 74, 46), (126, 92, 58)]

STUMP_C = (16.0, 16.5)
STUMP_R = 12.5
FACE = (10, 10, 25, 20)        # x0, y0, x1, y1 of the working face (exclusive ends)
HORN_TIP = 2.5                 # x where the horn's point is
CY = 15.0                      # face centre line


def in_face(x, y):
	x0, y0, x1, y1 = FACE
	return x0 <= x < x1 and y0 <= y < y1


def in_horn(x, y):
	"""A cone narrowing from the face's height to a point, slightly curved like a horn."""
	x0 = FACE[0]
	if not (HORN_TIP <= x < x0):
		return False
	t = (x + 0.5 - HORN_TIP) / (x0 - HORN_TIP)          # 0 at the tip, 1 at the face
	half = 0.6 + 4.4 * t ** 0.85
	centre = CY + 0.5 - 0.9 * (1 - t)                    # the tip lifts a touch
	return abs(y + 0.5 - centre) <= half


def in_base(x, y):
	"""Waist and feet, a bit wider than the face, seen around it."""
	return 11 <= x < 26 and 8 <= y < 23 and not (x in (11, 25) and y in (8, 22))


def anvil():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	# stump: rings on top, bark at the edge, outline
	cover = set()
	for y in range(F):
		for x in range(F):
			d = math.hypot(x + 0.5 - STUMP_C[0], y + 0.5 - STUMP_C[1])
			if d <= STUMP_R:
				cover.add((x, y))
				if d > STUMP_R - 1.6:
					px[x, y] = BARK[int(h(x, y, 1) < 0.4)]
				else:
					ring = int(d * 0.9 + h(x, y, 2) * 0.8) % 3
					lit = -((x + 0.5 - STUMP_C[0]) + (y + 0.5 - STUMP_C[1])) / STUMP_R
					px[x, y] = RINGS[max(0, min(2, ring - (1 if lit < -0.5 else 0)))]
	for y in range(F):
		for x in range(F):
			if (x, y) not in cover and any((x + ox, y + oy) in cover for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
				px[x, y] = OUTLINE
	# shadow of the anvil on the stump, down-right
	for y in range(F):
		for x in range(F):
			if (x, y) in cover and (in_base(x - 2, y - 2) or in_horn(x - 2, y - 2)):
				r, g, b, a = px[x, y]
				px[x, y] = (int(r * 0.62), int(g * 0.62), int(b * 0.62), a)
	# base (waist/feet): dark iron, a touch lighter on the lit sides
	metal = set()
	for y in range(F):
		for x in range(F):
			if in_base(x, y):
				px[x, y] = IRON[2] if (x < 13 or y < 10) else IRON[1]
				metal.add((x, y))
	# face and horn
	x0, y0, x1, y1 = FACE
	for y in range(F):
		for x in range(F):
			if in_face(x, y):
				v = 4.0
				if y == y0:
					v = 6                                   # polished front edge catching the light
				elif y == y0 + 1:
					v = 5
				elif y == y1 - 1:
					v = 2                                   # far edge rounds away
				elif x == x1 - 1:
					v = 3
				v += (h(x, y, 3) - 0.5) * 0.8 if 0 < y - y0 < y1 - y0 - 1 else 0
				px[x, y] = IRON[max(0, min(6, int(round(v))))]
				metal.add((x, y))
			elif in_horn(x, y):
				t = (x + 0.5 - HORN_TIP) / (x0 - HORN_TIP)
				half = 0.6 + 4.4 * t ** 0.85
				centre = CY + 0.5 - 0.9 * (1 - t)
				u = (y + 0.5 - centre) / half             # -1 top .. 1 bottom
				v = 4.3 - 2.4 * u                           # a cone: lit on top, dark below
				if -0.75 < u < -0.3:
					v += 1.2                                # the highlight line along the horn
				px[x, y] = IRON[max(0, min(6, int(round(v))))]
				metal.add((x, y))
	# hardy hole (square) and pritchel hole (round) in the heel
	for x, y in ((21, 13), (22, 13), (21, 14), (22, 14)):
		px[x, y] = IRON[0]
	px[23, 17] = IRON[0]
	px[21, 12] = IRON[1]                                    # lip of the hardy hole
	# outline around the iron
	for (x, y) in list(metal):
		for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q = (x + ox, y + oy)
			if q not in metal and 0 <= q[0] < F and 0 <= q[1] < F:
				px[q] = OUTLINE
	return img


def preview(im):
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	floor = Image.open(os.path.join(ROOT, "art", "structures", "wood_floor.png")).convert("RGBA")
	out = Image.new("RGBA", (96, 48))
	out.paste(g.crop((0, 0, 48, 48)), (0, 0))
	for yy in (0, 32):
		for xx in (48, 80):
			out.paste(floor.crop((0, 0, 32, 32)), (xx, yy))
	out.alpha_composite(im, (8, 8))
	out.alpha_composite(im, (56, 8))
	return out.resize((96 * 8, 48 * 8), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	im = anvil()
	im.save(OUT)
	preview(im).save(PREVIEW)
	print("wrote", OUT, "and", PREVIEW)
