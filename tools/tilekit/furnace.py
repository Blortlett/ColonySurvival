"""Furnace (smeltery): straight top-down, 32x32, dark palette, animated when lit.

A squat stone furnace seen from above: a rounded square body of rough-cut stone bricks, a
round throat in the top with a brick lip, and the stoking mouth on the front (bottom) edge.
Lit: flames boil up in the throat (white-hot core through orange to red, wavering, loops over
FRAMES frames), the bricks round the throat catch a warm glow, and the mouth glows and pulses.
Unlit: the throat is dark with a few dull coals, the mouth black.

Run:  python tools/tilekit/furnace.py
      writes art/structures/furnace.png (FRAMES x 32 lit frames), furnace_out.png and
      tools/tilekit/preview/furnace_preview.png (+ .gif)
"""
import math
import os

from PIL import Image

from wood_walls import h
from campfire import FIRE, FIRE_CUT
from furniture import finish, OUTLINE

F = 32
FRAMES = 6
C = 15.5                  # centre of the throat (pixel coords)
CY = 14.0
THROAT = 6.2              # throat radius

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "structures", "furnace.png")
OUT_OFF = os.path.join(ROOT, "art", "structures", "furnace_out.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "furnace_preview.png")

BRICK = [(34, 32, 32), (48, 45, 44), (62, 58, 56), (78, 73, 70), (96, 90, 85), (116, 109, 102)]
MORTAR = (24, 22, 22)
SOOT = [(14, 12, 12), (24, 20, 19)]
COAL = [(40, 22, 16), (90, 34, 16)]
WARM = (255, 120, 40)


def body_mask():
	"""Rounded square body, 28x28."""
	m = set()
	x0, y0, x1, y1, r = 2, 2, 30, 30, 5
	for y in range(y0, y1):
		for x in range(x0, x1):
			cx = min(max(x + 0.5, x0 + r), x1 - r)
			cy = min(max(y + 0.5, y0 + r), y1 - r)
			if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r:
				m.add((x, y))
	return m


def brick_shade(x, y):
	"""Running-bond bricks on top of the body, rows of 4 px, bricks 7 px; lit top-left."""
	row = y // 4
	k = y % 4
	off = 3 * (row % 2)
	j = (x + off) % 7
	if k == 0 or j == 0:
		return None                                        # mortar
	v = 2.6 + (h(row, (x + off) // 7, 1) - 0.5) * 1.2
	v += 0.6 if (k == 1 or j == 1) else 0
	v -= 0.6 if (k == 3 or j == 6) else 0
	v += (h(x, y, 2) - 0.5) * 0.5
	return v


def heat(x, y, f):
	"""Flame heat in the throat, periodic over FRAMES."""
	t = f / FRAMES * 6.283
	dx, dy = x + 0.5 - C, y + 0.5 - CY
	r = math.hypot(dx, dy)
	th = math.atan2(dy, dx)
	reach = THROAT * 0.95
	reach += 1.3 * math.sin(4 * th + t + 0.3)
	reach += 0.9 * math.sin(6 * th - 2 * t + 2.0)
	reach += 0.5 * math.sin(t * 2 + 1.0)
	v = 1.05 - r / max(reach, 2.0)
	v += 0.12 * math.sin(r * 1.4 - 2 * t)
	v += (h(x, y, f, 3) - 0.5) * 0.22
	return v


def furnace(f=None):
	"""f=None draws the unlit furnace; otherwise lit frame f."""
	lit = f is not None
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	body = body_mask()
	# body: bricks, darker toward the bottom-right rim, warm near the throat when lit
	for (x, y) in body:
		rim = min(x - 2, y - 2, 29 - x, 29 - y)
		v = brick_shade(x, y)
		if v is None:
			px[x, y] = MORTAR
			continue
		if rim < 2:
			v += 0.8 if (x < 4 or y < 4) else -1.0
		d = math.hypot(x + 0.5 - C, y + 0.5 - CY)
		col = BRICK[max(0, min(5, int(round(v))))]
		if lit and d < THROAT + 5:
			a = max(0.0, 1.0 - (d - THROAT) / 5.0) * 0.45   # firelight on the bricks
			col = tuple(int(c * (1 - a) + w * a * (0.55 + 0.45 * (c / 120))) for c, w in zip(col, WARM))
		px[x, y] = col
	# throat lip: a ring of dark soot-stained brick, then the hole
	for (x, y) in body:
		d = math.hypot(x + 0.5 - C, y + 0.5 - CY)
		if THROAT <= d < THROAT + 1.4:
			px[x, y] = SOOT[1] if (x < C and y < CY) else SOOT[0]
		elif d < THROAT:
			if lit:
				v = heat(x, y, f)
				step = -1
				for i, cut in enumerate(FIRE_CUT):
					if v >= cut:
						step = i
				px[x, y] = FIRE[step] if step >= 0 else COAL[1]
			else:
				px[x, y] = COAL[1] if h(x, y, 4) < 0.12 else COAL[0] if h(x, y, 5) < 0.4 else SOOT[0]
	# stoking mouth on the front edge: an arch cut into the body
	for x in range(12, 20):
		for y in range(24, 30):
			if (x, y) not in body:
				continue
			u = (x + 0.5 - 16) / 4.0
			if y >= 26 - (1 - u * u) * 2:
				if lit:
					pulse = 0.5 + 0.5 * math.sin(f / FRAMES * 6.283 * 2 + x * 0.6)
					px[x, y] = FIRE[2 + int(pulse * 1.5)] if y > 26 else FIRE[1]
				else:
					px[x, y] = SOOT[0]
	# lintel stone over the mouth
	for x in range(11, 21):
		px[x, 23] = BRICK[4] if x < 16 else BRICK[3]
	finish(img, body)
	return img


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	strip = Image.new("RGBA", (F * FRAMES, F), (0, 0, 0, 0))
	for f in range(FRAMES):
		strip.alpha_composite(furnace(f), (f * F, 0))
	strip.save(OUT)
	off = furnace()
	off.save(OUT_OFF)
	floor = Image.open(os.path.join(ROOT, "art", "structures", "wood_floor.png")).convert("RGBA")
	W = (FRAMES + 1) * 40
	out = Image.new("RGBA", (W, 40))
	for xx in range(0, W, 32):
		for yy in (0, 32):
			out.paste(floor.crop(((xx // 32 % 4) * 32, 0, (xx // 32 % 4) * 32 + 32, 32)), (xx, yy))
	base = out.copy()
	for f in range(FRAMES):
		out.alpha_composite(strip.crop((f * F, 0, f * F + F, F)), (4 + f * 40, 4))
	out.alpha_composite(off, (4 + FRAMES * 40, 4))
	out.resize((W * 6, 240), Image.NEAREST).save(PREVIEW)
	gif = []
	for f in range(FRAMES):
		fr = base.crop((0, 0, 40, 40)).copy()
		fr.alpha_composite(strip.crop((f * F, 0, f * F + F, F)), (4, 4))
		gif.append(fr.resize((320, 320), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
	gif[0].save(PREVIEW.replace(".png", ".gif"), save_all=True, append_images=gif[1:], duration=110, loop=0)
	print("wrote furnace sprites and previews")
