"""Wall autotile sheets: wood, reinforced wood and stone.

32x32 px tiles, dark pixel-art palette, straight top-down view: each wall fills its cell and
we only see its top. The top is shaded as if slightly arced (rounded like a log/bolster):
brightest along the middle, falling off toward every open edge, with a soft light from the
top-left. Inner corners round off too, so joins read as one continuous wall.

Sheet layout: 4x4 tiles (128x128), tile index = connection mask
    N=1, E=2, S=4, W=8        column = mask % 4, row = mask // 4
so the game picks a tile with:  mask = int(n) | int(e)<<1 | int(s)<<2 | int(w)<<3.
That covers isolated posts, end caps, straights, corners, T-joins and crosses. The four
diagonals are assumed open (walls are one cell thick).

Plank grain follows the wall's direction; corners and T-joins are mitred like a frame.

Three materials share the shape, arc shading and mitred joints; only the top surface
differs (MATERIALS): wood planks; reinforced wood, darker planks bound by riveted iron straps;
stone, courses of cut blocks with mortar joints.

Run:  python tools/tilekit/wood_walls.py
      writes art/structures/{wood,reinforced,stone}_walls.png and a preview of each in
      tools/tilekit/preview/
"""
import math
import os

from PIL import Image

T = 32                 # tile size
PLANK = 8              # plank width
ARC = 12               # how far in from an open edge the rounding reaches, in px

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "structures")
PREVIEW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview")

N, E, S, W = 1, 2, 4, 8

# ---------------------------------------------------------------- palette (dark theme)
OUTLINE = (18, 12, 9)
# Wood shades, darkest -> lightest. The arc and the grain both index into this ramp.
WOOD = [
	(34, 22, 15),
	(46, 30, 20),
	(58, 39, 26),
	(70, 47, 31),
	(83, 56, 37),
	(97, 66, 43),
	(112, 78, 51),
]
SEAM_DROP = 1.5        # plank seams sit this many shades darker than the wood around them
KNOT_DROP = 2.0
# Reinforced: older, darker planks, bound with iron straps.
WOOD_DARK = [
	(26, 17, 12),
	(36, 24, 16),
	(47, 31, 21),
	(58, 39, 26),
	(70, 47, 31),
	(83, 56, 37),
	(97, 66, 43),
]
IRON = [
	(16, 17, 20),
	(24, 25, 29),
	(33, 34, 39),
	(44, 45, 51),
	(57, 58, 64),
	(72, 73, 79),
	(98, 99, 104),
]
STRAP_AT = (14, 15, 16)   # one strap per cell, centred along the wall: dark edge, face, shadow
# Stone: cool grey cut blocks, as the rocks.
STONE = [
	(30, 31, 36),
	(42, 43, 49),
	(55, 56, 62),
	(69, 70, 76),
	(85, 86, 91),
	(102, 103, 107),
	(122, 122, 125),
]
STONE_OUTLINE = (13, 14, 17)
COURSE = 8             # stone course height (across the wall)
BLOCK = 16             # block length (along); alternate courses offset by half


def h(*v):
	"""Small deterministic hash -> [0, 1)."""
	x = 0x9E3779B1
	for n in v:
		x ^= (n + 0x7F4A7C15 + (x << 6) + (x >> 2)) & 0xFFFFFFFF
		x = (x * 0x85EBCA6B) & 0xFFFFFFFF
		x ^= x >> 13
	return (x & 0xFFFF) / 65536.0


def grain(along, across):
	"""Grain brightness offset (in shades) for a plank pixel. `along` runs the length of the
	plank (periodic in T so neighbouring tiles line up), `across` is across the planks."""
	p = across // PLANK
	k = across % PLANK
	if k == 0:
		return -SEAM_DROP
	if along == int(h(p, 7) * T):             # butt joint, staggered between planks
		return -SEAM_DROP
	kx = int(h(p, 3) * T)                     # knots
	if h(p, 5) < 0.45 and abs(along - kx) <= 1 and k in (2, 3) and not (abs(along - kx) == 1 and k == 3):
		return -KNOT_DROP
	ph = h(p, k) * 6.283
	v = 0.55 * math.sin(6.283 * 2 * along / T + ph) + 0.35 * math.sin(6.283 * 5 * along / T + ph * 1.7)
	v += (h(along, across, 11) - 0.5) * 0.8   # pixel noise, like the grass
	v += 0.35 if k == 1 else 0.0              # each plank's edge catches a little light
	v -= 0.35 if k == PLANK - 1 else 0.0
	return v


def reinforced(along, across):
	"""Darker planks, bound once per cell by a riveted iron strap across the wall."""
	if along in STRAP_AT:
		i = STRAP_AT.index(along)
		v = (0.2, 0.0, -0.9)[i] - 0.4 + (h(along, across, 12) - 0.5) * 0.4
		if i == 0 and across % COURSE == 4:
			v += 2.0                               # rivet head
		return v, IRON
	if along == STRAP_AT[-1] + 1:
		return grain(along, across) - 1.0, None   # the strap's shadow on the wood
	return grain(along, across), None


def stone(along, across):
	"""Courses of cut blocks in running bond, mortar between, each block its own tone."""
	row = across // COURSE
	k = across % COURSE
	off = (BLOCK // 2) * (row % 2)
	a = (along + off) % T
	j = a % BLOCK
	if k == 0 or j == 0:
		return -2.2, None                          # mortar joint
	v = (h(row, a // BLOCK, 13) - 0.5) * 1.1      # per-block tone
	v += 0.55 if (k == 1 or j == 1) else 0.0      # bevel: top-left edges of the block lit
	v -= 0.5 if (k == COURSE - 1 or j == BLOCK - 1) else 0.0
	v += (h(along, across, 14) - 0.5) * 0.7       # stone grain
	if h(along // 2, across // 2, row, 15) < 0.04:
		v -= 1.0                                   # small pits
	return v, None


MATERIALS = {
	"wood": dict(palette=WOOD, outline=OUTLINE, surface=lambda a, c: (grain(a, c), None)),
	"reinforced": dict(palette=WOOD_DARK, outline=OUTLINE, surface=reinforced),
	"stone": dict(palette=STONE, outline=STONE_OUTLINE, surface=stone),
}


def sector_vertical(x, y, m):
	"""Which grain direction this pixel uses: True = vertical planks. Mitred by sector."""
	dx = x - (T - 1) / 2
	dy = y - (T - 1) / 2
	# A connected sector uses its own axis; an open sector borrows the perpendicular axis
	# when that axis has a connection (gives a clean mitre at corners), else keeps its own.
	if abs(dy) > abs(dx):          # N or S sector
		d = N if dy < 0 else S
		return bool(m & d) or not (m & (E | W))
	d = W if dx < 0 else E
	return not (m & d) and bool(m & (N | S))


def edge_dist(x, y, m):
	"""Distance from pixel centre to the nearest open edge (or open inner corner), plus which
	side it is, for the arc shading. Returns (distance, light) where light is +1 for edges
	facing the top-left light, -1 for bottom-right, 0 otherwise."""
	best, light = 99.0, 0.0
	cx, cy = x + 0.5, y + 0.5
	if not m & N and cy < best:
		best, light = cy, 1.0
	if not m & W and cx < best:
		best, light = cx, 1.0
	if not m & S and T - cy < best:
		best, light = T - cy, -1.0
	if not m & E and T - cx < best:
		best, light = T - cx, -1.0
	# inner corners: both sides connected, the diagonal cell open -> round off around the
	# corner point so the arc carries through the join.
	for a, b, px, py, lt in ((N, E, T, 0, 0.0), (N, W, 0, 0, 1.0), (S, E, T, T, -1.0), (S, W, 0, T, 0.0)):
		if m & a and m & b:
			d = math.hypot(cx - px, cy - py)
			if d < best:
				best, light = d, lt
	return best, light


def tile(m, material="wood"):
	mat = MATERIALS[material]
	img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
	px = img.load()
	mid = len(mat["palette"]) - 2.2           # shade at the crown of the arc
	for y in range(T):
		for x in range(T):
			d, light = edge_dist(x, y, m)
			if d < 1.0:
				px[x, y] = mat["outline"]
				continue
			# Arc: a quarter-circle profile from the edge up to the crown.
			t = min(1.0, (d - 1.0) / ARC)
			arc = math.sqrt(1.0 - (1.0 - t) ** 2)            # 0 at the edge, 1 on top
			v = 0.3 + (mid + 0.6 - 0.3) * arc
			v += light * 1.3 * (1.0 - arc)                   # top-left rims lit, bottom-right shaded
			if 1.0 <= d < 2.0 and light > 0:                 # thin highlight just inside lit edges
				v += 0.8
			g, pal = mat["surface"](y, x) if sector_vertical(x, y, m) else mat["surface"](x, y)
			v += g * (0.55 + 0.45 * arc)                     # surface detail fades a bit on the rim
			pal = pal or mat["palette"]
			px[x, y] = pal[max(0, min(len(pal) - 1, int(round(v))))]
	return img


def sheet(material="wood"):
	img = Image.new("RGBA", (T * 4, T * 4), (0, 0, 0, 0))
	for m in range(16):
		img.paste(tile(m, material), ((m % 4) * T, (m // 4) * T))
	return img


def preview(sheet_img):
	"""A little test base on darkened grass, plus the raw sheet, scaled up 3x."""
	layout = [
		"..............",
		".#######......",
		".#.....#..#...",
		".#.....####...",
		".#.....#..#...",
		".###.###..#...",
		"..........#...",
		".#....#####...",
		"..............",
		".####.#.#.#...",
		"......###.....",
		".#......#.....",
		"..............",
	]
	H, Wd = len(layout), len(layout[0])
	ground = Image.new("RGBA", (Wd * T, H * T))
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.6)) for c in (r, gg, b)] + [a])   # darker grass trial
	for yy in range(0, H * T, g.height):
		for xx in range(0, Wd * T, g.width):
			ground.paste(g, (xx, yy))
	gpx = ground.load()

	def wall(cx, cy):
		return 0 <= cy < H and 0 <= cx < Wd and layout[cy][cx] == "#"

	# soft ambient shadow hugging the walls on every side (top-down: no long cast shadow)
	R = 4
	for Y in range(H * T):
		for X in range(Wd * T):
			if wall(X // T, Y // T):
				continue
			d = R + 1
			for cy in range(Y // T - 1, Y // T + 2):
				for cx in range(X // T - 1, X // T + 2):
					if wall(cx, cy):
						dx = max(cx * T - X, 0, X - (cx * T + T - 1))
						dy = max(cy * T - Y, 0, Y - (cy * T + T - 1))
						d = min(d, max(dx, dy))
			if d <= R:
				f = 0.55 + 0.45 * (d - 1) / R
				rr, g2, bb, aa = gpx[X, Y]
				gpx[X, Y] = (int(rr * f), int(g2 * f), int(bb * f), aa)

	for cy in range(H):
		for cx in range(Wd):
			if not wall(cx, cy):
				continue
			m = (N if wall(cx, cy - 1) else 0) | (E if wall(cx + 1, cy) else 0) \
				| (S if wall(cx, cy + 1) else 0) | (W if wall(cx - 1, cy) else 0)
			t = sheet_img.crop(((m % 4) * T, (m // 4) * T, (m % 4 + 1) * T, (m // 4 + 1) * T))
			ground.alpha_composite(t, (cx * T, cy * T))

	gap = 16
	out = Image.new("RGBA", (ground.width + gap + sheet_img.width, max(ground.height, sheet_img.height)), (14, 14, 16, 255))
	out.paste(ground, (0, 0))
	out.alpha_composite(sheet_img, (ground.width + gap, 0))
	return out.resize((out.width * 3, out.height * 3), Image.NEAREST)


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	os.makedirs(PREVIEW_DIR, exist_ok=True)
	for material in MATERIALS:
		s = sheet(material)
		s.save(os.path.join(OUT_DIR, "%s_walls.png" % material))
		preview(s).save(os.path.join(PREVIEW_DIR, "%s_walls_preview.png" % material))
		print("wrote", material, "walls")
