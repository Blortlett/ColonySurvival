"""Road tiles: stone road (cobbles) and paved road (slabs).

32x32 px, straight top-down, dark pixel-art palette. Each road is a strip of VARIANTS tiles.
Every joint line that touches a tile edge sits exactly on that edge (rows at 0/8/16/24 for
cobbles, 16 px slabs for paving), so any variant can sit next to any other without a seam.
The game picks a variant from a hash of the cell.

  road_stone.png  - rounded cobbles in rows, packed in dark dirt; warm grey-brown, domed
  road_paved.png  - big flat cut slabs, lighter cool grey, thin joints, a crack here and there

Run:  python tools/tilekit/roads.py
      writes art/structures/road_stone.png, road_paved.png and tools/tilekit/preview/roads_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

T = 32
VARIANTS = 4

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "structures")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "roads_preview.png")

COBBLE = [(42, 38, 33), (55, 50, 44), (69, 63, 56), (84, 77, 68), (100, 92, 81), (117, 108, 95)]
DIRT = [(26, 22, 18), (34, 29, 23)]
SLAB = [(58, 59, 63), (69, 70, 74), (80, 81, 85), (92, 93, 96), (105, 105, 108), (120, 120, 122)]
SLAB_JOINT = (36, 37, 41)
ROW = 8


def cobbles(var):
	"""Rows of rounded cobbles; each row is cut into stones of 6-11 px, joints at 0 and T."""
	img = Image.new("RGBA", (T, T))
	px = img.load()
	for row in range(T // ROW):
		# split this row into stones
		cuts, x = [0], 0
		while True:
			x += 6 + int(h(var, row, len(cuts), 1) * 6)
			if x >= T - 5:
				break
			cuts.append(x)
		cuts.append(T)
		for si in range(len(cuts) - 1):
			x0, x1 = cuts[si], cuts[si + 1]
			y0, y1 = row * ROW, row * ROW + ROW
			tone = (h(var, row, si, 2) - 0.5) * 1.2
			w, hgt = x1 - x0, y1 - y0
			for y in range(y0, y1):
				for x in range(x0, x1):
					# local position inside the stone, -1..1
					u = (x + 0.5 - x0) / w * 2 - 1
					v_ = (y + 0.5 - y0) / hgt * 2 - 1
					# a rounded-rectangle stone with a 1 px dirt gap around it
					inset = abs(u) ** 4 + abs(v_) ** 4
					edge = x == x0 or y == y0
					if edge or inset > 0.72:
						px[x, y] = DIRT[int(h(var, x, y, 3) < 0.3)]
						continue
					# domed: lit toward the top-left, darker toward the bottom-right
					sh = 2.6 + tone - 1.4 * (u * 0.55 + v_ * 0.7) - 1.0 * inset
					sh += (h(var, x, y, 4) - 0.5) * 0.7
					px[x, y] = COBBLE[max(0, min(len(COBBLE) - 1, int(round(sh))))]
	return img


def paved(var):
	"""2x2 slabs of 16 px; some split in two; thin joints on the tile edge; occasional crack."""
	img = Image.new("RGBA", (T, T))
	px = img.load()
	slabs = []
	for sy in (0, 16):
		for sx in (0, 16):
			r = h(var, sx, sy, 5)
			if r < 0.25:
				slabs += [(sx, sy, 16, 8), (sx, sy + 8, 16, 8)]
			elif r < 0.45:
				slabs += [(sx, sy, 8, 16), (sx + 8, sy, 8, 16)]
			else:
				slabs.append((sx, sy, 16, 16))
	for i, (x0, y0, w, hh) in enumerate(slabs):
		tone = (h(var, i, 6) - 0.5) * 0.9
		for y in range(y0, y0 + hh):
			for x in range(x0, x0 + w):
				if x == x0 or y == y0:
					px[x, y] = SLAB_JOINT
					continue
				v = 2.8 + tone
				if x == x0 + 1 or y == y0 + 1:
					v += 0.8                       # lit top-left bevel
				if x == x0 + w - 1 or y == y0 + hh - 1:
					v -= 0.9                       # shaded bottom-right bevel
				v += (h(var, x, y, 7) - 0.5) * 0.6
				if h(var, x // 3, y // 3, i, 8) < 0.06:
					v -= 0.7                       # weathered patches
				px[x, y] = SLAB[max(0, min(len(SLAB) - 1, int(round(v))))]
		# a crack across some slabs: a short random walk
		if w * hh >= 256 and h(var, i, 9) < 0.3:
			x = x0 + 3 + int(h(var, i, 10) * (w - 6))
			y = y0 + 2 + int(h(var, i, 12) * 5)
			for step in range(6 + int(h(var, i, 13) * 4)):
				px[x, y] = SLAB[0]
				y += 1
				x += (-1 if h(var, i, step, 11) < 0.3 else 1 if h(var, i, step, 11) > 0.7 else 0)
				x = max(x0 + 2, min(x0 + w - 2, x))
	return img


def strip(fn):
	img = Image.new("RGBA", (T * VARIANTS, T))
	for v in range(VARIANTS):
		img.paste(fn(v), (v * T, 0))
	return img


def preview(stone, paved_img):
	"""A crossroads of each road on the darkened grass, with the in-game edge shading, 3x."""
	layout = [
		"...........",
		"....s....p.",
		"....s....p.",
		"sssssssppppp",
		"....s....p.",
		"....s....p.",
		"...........",
	]
	Wd, H = 12, len(layout)
	out = Image.new("RGBA", (Wd * T, H * T))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	for yy in range(0, H * T, g.height):
		for xx in range(0, Wd * T, g.width):
			out.paste(g, (xx, yy))

	def at(cx, cy):
		return layout[cy][cx] if 0 <= cy < H and 0 <= cx < len(layout[cy]) else "."

	for cy in range(H):
		for cx in range(Wd):
			c = at(cx, cy)
			if c == ".":
				continue
			src = stone if c == "s" else paved_img
			var = int(h(cx, cy, 99) * VARIANTS)
			tile = src.crop((var * T, 0, var * T + T, T))
			# edge shading where the road meets grass (same bands as PieceLayer)
			shade = Image.new("RGBA", (T, T), (0, 0, 0, 0))
			sp = shade.load()
			for side, (dx, dy) in (("n", (0, -1)), ("e", (1, 0)), ("s", (0, 1)), ("w", (-1, 0))):
				if at(cx + dx, cy + dy) != ".":
					continue
				for i, alpha in enumerate((90, 40)):
					for j in range(T):
						x, y = {"n": (j, i), "s": (j, T - 1 - i), "w": (i, j), "e": (T - 1 - i, j)}[side]
						sp[x, y] = (0, 0, 0, max(sp[x, y][3], alpha))
			tile.alpha_composite(shade)
			out.alpha_composite(tile, (cx * T, cy * T))
	return out.resize((out.width * 3, out.height * 3), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	s, p = strip(cobbles), strip(paved)
	s.save(os.path.join(OUT_DIR, "road_stone.png"))
	p.save(os.path.join(OUT_DIR, "road_paved.png"))
	preview(s, p).save(PREVIEW)
	print("wrote road_stone.png, road_paved.png and", PREVIEW)
