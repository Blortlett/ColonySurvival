"""Furniture: basic chest, storage crate and sawmill. 32x32, straight top-down, dark palette.

Each piece has a dark outline and a soft shadow baked in (down-right, light from the
top-left), and its wood is a different tone from the floor planks so it reads on a floor.

  chest_basic.png - a wooden chest seen from above: a domed plank lid inside a darker frame,
                    with an iron latch on the front edge
  crate.png       - a pale pine storage crate: plank top in a frame with a diagonal brace
  sawmill.png     - SAW_FRAMES frames: a plank table with a feed slot along the middle and the
                    circular blade poking up through it (seen edge-on, so a toothed sliver);
                    the teeth run along it as it spins and sawdust kicks out behind. A log waits
                    on the infeed side, cut planks lie on the outfeed side. Frame 0 doubles as
                    the idle (still) image.

Run:  python tools/tilekit/furniture.py
      writes those into art/structures/ and tools/tilekit/preview/furniture_preview.png (+ .gif)
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 32
SAW_FRAMES = 4

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "art", "structures")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "furniture_preview.png")

OUTLINE = (16, 11, 8)
SHADOW = (0, 0, 0, 95)
# chest: warm, reddish oak - lighter and redder than the floor
OAK = [(58, 32, 20), (80, 46, 28), (104, 62, 36), (128, 80, 46), (150, 98, 58)]
OAK_FRAME = [(40, 23, 15), (54, 32, 20), (70, 42, 26)]
IRON = [(24, 25, 29), (44, 45, 51), (78, 80, 88), (126, 128, 136)]
# crate: pale pine
PINE = [(82, 62, 36), (104, 80, 48), (128, 100, 62), (150, 120, 76), (172, 142, 92)]
# sawmill: a mid, slightly grey wood table, steel blade
TABLE = [(52, 40, 30), (68, 53, 40), (84, 66, 50), (100, 80, 61), (116, 94, 72)]
STEEL = [(40, 42, 48), (90, 94, 102), (150, 156, 166), (206, 212, 220)]
SAWDUST = [(150, 120, 80), (186, 156, 108), (214, 190, 140)]
LOG_BARK = [(40, 27, 17), (56, 38, 24)]
LOG_END = [(120, 86, 52), (146, 108, 66)]


def shade(pal, v):
	return pal[max(0, min(len(pal) - 1, int(round(v))))]


def finish(img, solid):
	"""Outline around `solid` and a soft shadow down-right, under everything."""
	px = img.load()
	for (x, y) in list(solid):
		for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			q = (x + ox, y + oy)
			if q not in solid and 0 <= q[0] < F and 0 <= q[1] < F:
				px[q] = OUTLINE
	outline = {(x, y) for y in range(F) for x in range(F) if px[x, y][3] == 255}
	for (x, y) in outline:
		for q in ((x + 1, y + 1), (x + 1, y + 2), (x + 2, y + 2)):
			if q not in outline and 0 <= q[0] < F and 0 <= q[1] < F and px[q][3] == 0:
				px[q] = SHADOW


def rect(x0, y0, x1, y1):
	return {(x, y) for y in range(y0, y1) for x in range(x0, x1)}


# ---------------------------------------------------------------- chest
def chest():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	x0, y0, x1, y1 = 4, 7, 28, 25
	solid = rect(x0, y0, x1, y1)
	for (x, y) in solid:
		fx, fy = x - x0, y - y0
		w, hh = x1 - x0, y1 - y0
		if fx < 2 or fy < 2 or fx >= w - 2 or fy >= hh - 2:
			# frame: lit on top/left, dark bottom/right
			v = 2 if (fx < 2 or fy < 2) else 0
			if fx in (0, w - 1) or fy in (0, hh - 1):
				v -= 1
			px[x, y] = shade(OAK_FRAME, v + 0.5)
			continue
		# lid: planks running left-right, domed (lighter across the middle rows)
		u = (fy - 2) / (hh - 5) * 2 - 1                    # -1 top .. 1 bottom of the lid
		v = 3.1 - 1.6 * u * u - 0.5 * u
		if (fy - 2) % 4 == 3:
			v -= 1.4                                        # plank seam
		v += (h(x, y, 1) - 0.5) * 0.6
		if (fy - 2) % 4 == 0:
			v += 0.3
		px[x, y] = shade(OAK, v)
	# iron corner plates
	for cx, cy in ((x0, y0), (x1 - 3, y0), (x0, y1 - 3), (x1 - 3, y1 - 3)):
		for (x, y) in rect(cx, cy, cx + 3, cy + 3):
			px[x, y] = IRON[2] if (x - cx) + (y - cy) < 2 else IRON[1]
	# latch on the front (bottom) edge, centred
	for (x, y) in rect(14, y1 - 5, 18, y1):
		px[x, y] = IRON[1]
	for (x, y) in rect(15, y1 - 4, 17, y1 - 1):
		px[x, y] = IRON[3] if y == y1 - 4 else IRON[2]
	px[15, y1 - 2] = IRON[0]
	finish(img, solid)
	return img


# ---------------------------------------------------------------- crate
def crate():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	x0, y0, x1, y1 = 4, 4, 28, 28
	solid = rect(x0, y0, x1, y1)
	n = x1 - x0
	for (x, y) in solid:
		fx, fy = x - x0, y - y0
		frame = fx < 3 or fy < 3 or fx >= n - 3 or fy >= n - 3
		brace = abs(fx - fy) <= 1 and not frame           # one diagonal brace, top-left to bottom-right
		if frame or brace:
			v = 3.2
			if frame and (fx < 1 or fy < 1):
				v += 0.6
			if frame and (fx >= n - 1 or fy >= n - 1):
				v -= 1.4
			if brace and fx - fy == 1:
				v -= 1.2                                    # the brace's shadow side
			if frame and (fx, fy) in ((2, 2), (n - 3, 2), (2, n - 3), (n - 3, n - 3)):
				v = 0                                       # nail heads
			v += (h(x, y, 2) - 0.5) * 0.5
			px[x, y] = shade(PINE, v)
		else:
			# inset top planks, running vertically, a step lower so a touch darker
			v = 2.0
			if (fx - 3) % 6 == 0:
				v -= 1.3                                    # gap between planks
			v += (h(x, y, 3) - 0.5) * 0.7
			if fx == 3 or fy == 3:
				v -= 0.8                                    # the frame's shadow on the planks
			px[x, y] = shade(PINE, v)
	finish(img, solid)
	return img


# ---------------------------------------------------------------- sawmill
TABLE_BOX = (2, 5, 30, 27)
SLOT_Y = 15                     # the blade slot: rows SLOT_Y-1 .. SLOT_Y+2
BLADE_X = (10, 22)


def sawmill(f, running=True):
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	x0, y0, x1, y1 = TABLE_BOX
	solid = rect(x0, y0, x1, y1)
	for (x, y) in solid:
		fy = y - y0
		v = 2.4
		if fy % 5 == 4:
			v -= 1.2                                        # table plank seams, along the feed
		if fy % 5 == 0:
			v += 0.4
		if x == x0 or y == y0:
			v += 0.7
		if x == x1 - 1 or y == y1 - 1:
			v -= 1.0
		v += (h(x, y, 4) - 0.5) * 0.6
		px[x, y] = shade(TABLE, v)
	# steel throat plate round the slot, and the dark slot itself
	bx0, bx1 = BLADE_X
	for x in range(bx0 - 3, bx1 + 4):
		for y in range(SLOT_Y - 2, SLOT_Y + 4):
			edge = y in (SLOT_Y - 2, SLOT_Y + 3) or x in (bx0 - 3, bx1 + 3)
			px[x, y] = IRON[2] if (edge and (y == SLOT_Y - 2 or x == bx0 - 3)) else IRON[1] if edge else (18, 15, 13)
	# the blade poking up through the slot, edge-on: a 2-px steel sliver with teeth on both
	# long edges. The teeth run along it as it spins, one step per frame.
	for x in range(bx0, bx1 + 1):
		step = (x + (f if running else 0)) % 3
		px[x, SLOT_Y] = STEEL[3] if step == 0 else STEEL[2]       # lit top face of the blade
		px[x, SLOT_Y + 1] = STEEL[1] if step != 2 else STEEL[2]
		px[x, SLOT_Y - 1] = STEEL[2] if step == 1 else (18, 15, 13)  # teeth catching light above
		px[x, SLOT_Y + 2] = STEEL[0] if step == 2 else (18, 15, 13)  # and below, in shadow
	# a log waiting on the infeed (left), lying along the feed: bark, lit top, sawn end grain
	for (x, y) in rect(3, 7, 12, 13):
		ly = y - 7
		if ly == 0 or ly == 5:
			px[x, y] = OUTLINE
		else:
			px[x, y] = LOG_BARK[1] if ly in (1, 2) else LOG_BARK[0]
			if (x * 3 + ly) % 5 == 0:
				px[x, y] = LOG_BARK[0]
		if x == 11 and 0 < ly < 5:
			px[x, y] = LOG_END[1] if ly in (1, 2) else LOG_END[0]
	# cut planks stacked on the outfeed (right), below the slot
	for i, py in enumerate((20, 23)):
		for x in range(17, 29):
			px[x, py - 1] = OUTLINE if x in (17, 28) else LOG_END[1 - i * 0 if i == 0 else 1]
			px[x, py] = OUTLINE if x in (17, 28) else LOG_END[0]
			px[x, py + 1] = OUTLINE
	# sawdust heap behind the blade, and specks flying while it runs
	for (x, y) in ((24, 13), (25, 12), (26, 13), (25, 14), (24, 18), (25, 17), (26, 18)):
		px[x, y] = SAWDUST[0] if (x + y) % 2 else SAWDUST[1]
	if running:
		for k in range(5):
			a = (h(f, k, 5) - 0.5) * 1.8
			d = 2 + h(f, k, 6) * 5
			sx = int(bx1 + 4 + math.cos(a) * d)
			sy = int(SLOT_Y + 0.5 + math.sin(a) * d)
			if (sx, sy) in solid:
				px[sx, sy] = SAWDUST[1 + int(h(f, k, 7) < 0.4)]
	finish(img, solid)
	return img


def preview(chest_im, crate_im, saw):
	floor = Image.open(os.path.join(OUT_DIR, "wood_floor.png")).convert("RGBA")
	W, H = 6 * 32, 2 * 32
	out = Image.new("RGBA", (W, H))
	for yy in range(0, H, 32):
		for xx in range(0, W, 32):
			out.paste(floor.crop((((xx // 32 + yy // 32) % 4) * 32, 0, ((xx // 32 + yy // 32) % 4) * 32 + 32, 32)), (xx, yy))
	base = out.copy()
	out.alpha_composite(chest_im, (16, 16))
	out.alpha_composite(crate_im, (80, 16))
	out.alpha_composite(saw.crop((0, 0, F, F)), (144, 16))
	still = out.resize((W * 5, H * 5), Image.NEAREST)
	gif = []
	for f in range(SAW_FRAMES):
		fr = base.crop((128, 0, 192, 64)).copy()
		fr.alpha_composite(saw.crop((f * F, 0, f * F + F, F)), (16, 16))
		gif.append(fr.resize((320, 320), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
	return still, gif


if __name__ == "__main__":
	os.makedirs(OUT_DIR, exist_ok=True)
	c, k = chest(), crate()
	c.save(os.path.join(OUT_DIR, "chest_basic.png"))
	k.save(os.path.join(OUT_DIR, "crate.png"))
	saw = Image.new("RGBA", (F * SAW_FRAMES, F), (0, 0, 0, 0))
	for f in range(SAW_FRAMES):
		saw.alpha_composite(sawmill(f), (f * F, 0))
	saw.save(os.path.join(OUT_DIR, "sawmill.png"))
	still, gif = preview(c, k, saw)
	still.save(PREVIEW)
	gif[0].save(PREVIEW.replace(".png", ".gif"), save_all=True, append_images=gif[1:], duration=80, loop=0)
	print("wrote chest_basic.png, crate.png, sawmill.png and previews")
