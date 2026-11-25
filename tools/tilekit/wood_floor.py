"""Wood floor tiles.

32x32 px, straight top-down, dark pixel-art palette to match wood_walls.py. Horizontal
planks, 8 px wide, so rows line up across every tile. VARIANTS tiles side by side in one
strip; they share the grain streaks (so planks run on unbroken from tile to tile) and only
differ in where butt joints and knots fall. The game picks a variant from a hash of the cell.

Flatter and a touch lighter/greyer than the walls so the walls read as standing on it.

Run:  python tools/tilekit/wood_floor.py
      writes art/structures/wood_floor.png and tools/tilekit/preview/wood_floor_preview.png
      (the preview also uses art/structures/wood_walls.png, so run wood_walls.py first)
"""
import math
import os

from PIL import Image

from wood_walls import h, N, E, S, W

T = 32
PLANK = 8
VARIANTS = 4

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "structures", "wood_floor.png")
WALLS = os.path.join(ROOT, "art", "structures", "wood_walls.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "wood_floor_preview.png")

# darkest -> lightest
WOOD = [
	(48, 35, 26),
	(62, 45, 32),
	(74, 54, 38),
	(85, 62, 44),
	(96, 71, 50),
	(108, 81, 57),
]
BASE = 3.0
SEAM = 0                       # seam shade index (gap between planks)


def pixel(x, y, var):
	p = y // PLANK
	k = y % PLANK
	if k == PLANK - 1:
		return WOOD[SEAM]          # gap between plank rows
	# butt joints: per variant, per plank row; some rows have none in this tile
	if h(var, p, 7) < 0.7 and x == 2 + int(h(var, p, 8) * (T - 4)):
		return WOOD[SEAM]
	v = BASE
	# streaks shared by every variant (periodic in T): planks flow on across tiles
	ph = h(p, k, 1) * 6.283
	v += 0.5 * math.sin(6.283 * 1 * x / T + ph) + 0.3 * math.sin(6.283 * 4 * x / T + ph * 1.3)
	# one long plank tone per row, so rows look like separate boards
	v += (h(p, 2) - 0.5) * 0.9
	v += (h(x, y, var, 11) - 0.5) * 0.7          # pixel noise, like the grass
	v += 0.5 if k == 0 else 0.0                  # top edge of each board catches the light
	v -= 0.4 if k == PLANK - 2 else 0.0          # lower edge falls into the gap
	# knots
	kx = int(h(var, p, 3) * T)
	if h(var, p, 5) < 0.3 and k in (3, 4) and abs(x - kx) <= (1 if k == 3 else 0):
		v -= 1.8
	return WOOD[max(0, min(len(WOOD) - 1, int(round(v))))]


def strip():
	img = Image.new("RGBA", (T * VARIANTS, T), (0, 0, 0, 255))
	px = img.load()
	for var in range(VARIANTS):
		for y in range(T):
			for x in range(T):
				px[var * T + x, y] = pixel(x, y, var)
	return img


def preview(floor_img):
	"""Two rooms on darkened grass: walls, floors with the in-game wall shadow, 3x."""
	layout = [
		"..............",
		".#######......",
		".#ffffff#.....",
		".#ffffff#####.",
		".#ffffffffff#.",
		".#ffffff#fff#.",
		".###f####fff#.",
		"....f...#####.",
		"..............",
	]
	H, Wd = len(layout), len(layout[0])
	walls = Image.open(WALLS).convert("RGBA")
	out = Image.new("RGBA", (Wd * T, H * T))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.65)) for c in (r, gg, b)] + [a])
	for yy in range(0, H * T, g.height):
		for xx in range(0, Wd * T, g.width):
			out.paste(g, (xx, yy))

	def at(cx, cy):
		return layout[cy][cx] if 0 <= cy < H and 0 <= cx < Wd else "."

	for cy in range(H):
		for cx in range(Wd):
			c = at(cx, cy)
			if c == "f":
				var = int(h(cx, cy, 99) * VARIANTS)
				out.alpha_composite(floor_img.crop((var * T, 0, var * T + T, T)), (cx * T, cy * T))
				# wall shadow: same bands PieceLayer draws (3 px, fading)
				shade = Image.new("RGBA", (T, T), (0, 0, 0, 0))
				sp = shade.load()
				for side, (dx, dy) in ((N, (0, -1)), (E, (1, 0)), (S, (0, 1)), (W, (-1, 0))):
					if at(cx + dx, cy + dy) != "#":
						continue
					for i, alpha in enumerate((110, 70, 35)):
						for j in range(T):
							x, y = {N: (j, i), S: (j, T - 1 - i), W: (i, j), E: (T - 1 - i, j)}[side]
							sp[x, y] = (0, 0, 0, max(sp[x, y][3], alpha))
				out.alpha_composite(shade, (cx * T, cy * T))
			elif c == "#":
				m = (N if at(cx, cy - 1) == "#" else 0) | (E if at(cx + 1, cy) == "#" else 0) \
					| (S if at(cx, cy + 1) == "#" else 0) | (W if at(cx - 1, cy) == "#" else 0)
				out.alpha_composite(walls.crop(((m % 4) * T, (m // 4) * T, (m % 4 + 1) * T, (m // 4 + 1) * T)), (cx * T, cy * T))
	return out.resize((out.width * 3, out.height * 3), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	s = strip()
	s.save(OUT)
	preview(s).save(PREVIEW)
	print("wrote", OUT, "and", PREVIEW)
