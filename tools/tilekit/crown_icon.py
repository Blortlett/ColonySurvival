"""Crown icon for the Windows .exe: 64x64 pixel art, front view, transparent background.

A gold crown with five points, each tipped with a ball; a jewelled band (a red stone in the
middle, two blue either side, small studs between); dark outline; lit from the top-left,
shaded like a curved band so it reads round. Matches the game's dark, chunky pixel style.

Run:  python tools/tilekit/crown_icon.py
      writes art/icon/crown_icon.png (64x64), art/icon/crown_icon.ico (16-256, for the
      Windows export's application/icon) and tools/tilekit/preview/crown_icon_preview.png
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 64
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "icon")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "crown_icon_preview.png")

OUTLINE = (36, 20, 6)
GOLD = [(84, 50, 12), (124, 78, 20), (170, 114, 30), (214, 158, 50), (242, 200, 92), (255, 234, 160)]
RED = [(92, 10, 20), (160, 24, 36), (214, 52, 60), (255, 150, 150)]
BLUE = [(16, 30, 84), (34, 70, 160), (66, 120, 216), (170, 205, 255)]

X0, X1 = 7, 57              # crown body, left/right
BAND = (39, 51)             # band top/bottom rows
PEAKS = [(9, 21), (20, 15), (32, 9), (44, 15), (55, 21)]   # (x, tip y) of the five points
VALLEY_Y = 33               # how low the dips between points go


def top_edge(x):
	"""The crown's upper outline at column x: straight lines from tip to valley to tip."""
	pts = []
	for i, (px, py) in enumerate(PEAKS):
		pts.append((px, py))
		if i < len(PEAKS) - 1:
			pts.append(((px + PEAKS[i + 1][0]) / 2, VALLEY_Y))
	pts = [(X0, PEAKS[0][1] + 2)] + pts + [(X1, PEAKS[-1][1] + 2)]
	for (ax, ay), (bx, by) in zip(pts, pts[1:]):
		if ax <= x + 0.5 <= bx:
			t = (x + 0.5 - ax) / max(bx - ax, 1e-6)
			return ay + (by - ay) * t
	return 99


def icon():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	solid = set()
	# body: the points and the band, shaded as a curved gold band
	for y in range(F):
		for x in range(X0, X1):
			if y >= top_edge(x) and y < BAND[1]:
				u = (x + 0.5 - (X0 + X1) / 2) / ((X1 - X0) / 2)    # -1 left .. 1 right
				v = 3.4 - 1.5 * u - 0.9 * u * u                    # round: lit left, dark right
				if y < BAND[0]:
					v -= 0.25 * (BAND[0] - y) / 10.0               # points a touch darker up top
					# a facet line down the middle of each point
					for pxk, pyk in PEAKS:
						if x == pxk and y > pyk + 2:
							v += 0.9
						if x == pxk + 1 and y > pyk + 2:
							v -= 0.6
				else:
					if y == BAND[0] or y == BAND[0] + 1:
						v += 1.0 if y == BAND[0] else -0.4         # band's top rim
					if y == BAND[1] - 1 or y == BAND[1] - 2:
						v += 0.8 if y == BAND[1] - 2 else -0.8     # bottom rim
				v += (h(x, y, 1) - 0.5) * 0.35
				px[x, y] = GOLD[max(0, min(5, int(round(v))))]
				solid.add((x, y))
	# a dark shadow line where the points meet the band
	for x in range(X0, X1):
		if (x, BAND[0] - 1) in solid:
			r, g, b, a = px[x, BAND[0] - 1]
			px[x, BAND[0] - 1] = (int(r * 0.7), int(g * 0.7), int(b * 0.7), a)
	# balls on the tips
	for i, (pxk, pyk) in enumerate(PEAKS):
		cx, cy, r = pxk + 0.5, pyk - 2.0, 3.3 if i == 2 else 2.8
		for y in range(int(cy - r) - 1, int(cy + r) + 2):
			for x in range(int(cx - r) - 1, int(cx + r) + 2):
				d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
				if d <= r:
					lit = -((x + 0.5 - cx) + (y + 0.5 - cy)) / r
					px[x, y] = GOLD[max(0, min(5, int(round(3 + lit * 1.6))))]
					solid.add((x, y))
		px[int(cx) - 1, int(cy) - 1] = GOLD[5]
	# gems on the band
	def gem(cx, cy, rx, ry, pal):
		for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
			for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
				d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
				if d <= 1.0:
					lit = -((x + 0.5 - cx) / rx + (y + 0.5 - cy) / ry)
					px[x, y] = pal[max(0, min(3, int(round(1.6 + lit * 1.0))))]
				elif d <= 1.6:
					px[x, y] = GOLD[1]                          # the setting
		px[int(cx - rx * 0.4), int(cy - ry * 0.4)] = pal[3]
	mid = (BAND[0] + BAND[1]) / 2
	gem(32.0, mid, 4.2, 3.6, RED)
	gem(19.5, mid, 3.0, 2.8, BLUE)
	gem(44.5, mid, 3.0, 2.8, BLUE)
	for sx in (12, 26, 38, 52):                               # small studs
		px[sx, int(mid)] = GOLD[5]
		px[sx, int(mid) + 1] = GOLD[2]
	# outline
	for y in range(F):
		for x in range(F):
			if (x, y) not in solid and any((x + ox, y + oy) in solid for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
				px[x, y] = OUTLINE + (255,)
	# centre the crown in the canvas
	box = img.getbbox()
	out = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	out.paste(img.crop(box), ((F - (box[2] - box[0])) // 2, (F - (box[3] - box[1])) // 2))
	return out


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	im = icon()
	im.save(os.path.join(OUT_DIR, "crown_icon.png"))
	# .ico: a crisp 256 (nearest-neighbour from the 64) with smaller sizes for Explorer/taskbar
	big = im.resize((256, 256), Image.NEAREST)
	big.save(os.path.join(OUT_DIR, "crown_icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
	bg = Image.new("RGBA", (F + 16, F + 16), (30, 32, 38, 255))
	bg.alpha_composite(im, (8, 8))
	small = Image.new("RGBA", (F + 16, F + 16), (30, 32, 38, 255))
	small.alpha_composite(im.resize((32, 32), Image.LANCZOS), (24, 24))
	out = Image.new("RGBA", ((F + 16) * 8 * 2 + 16, (F + 16) * 8), (14, 14, 16, 255))
	out.paste(bg.resize(((F + 16) * 8, (F + 16) * 8), Image.NEAREST), (0, 0))
	out.paste(small.resize(((F + 16) * 8, (F + 16) * 8), Image.NEAREST), ((F + 16) * 8 + 16, 0))
	out.save(PREVIEW)
	print("wrote crown_icon.png, crown_icon.ico and preview")
