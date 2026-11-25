"""Campfire: an animated top-down fire, shared by house fires and wild campfires.

32x32 px, dark pixel-art palette, straight down. A ring of stones around a tepee of logs
(seen from above, logs radiating from the middle like spokes), and over them a burning
fire: a white-yellow core fading through orange to deep red, with flame tongues licking
outward that waver and pulse each frame, and a few sparks. FRAMES frames loop seamlessly
(every moving part uses whole-cycle periods). A separate unlit image shows the same ring
with charred logs on grey ash, for a fire that's out of wood.

Run:  python tools/tilekit/campfire.py
      writes art/structures/campfire.png (FRAMES x 32, left to right), campfire_out.png
      and tools/tilekit/preview/campfire_preview.png (+ campfire_preview.gif)
"""
import math
import os

from PIL import Image

from wood_walls import h

F = 32
C = 16.0
FRAMES = 8

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "structures", "campfire.png")
OUT_OFF = os.path.join(ROOT, "art", "structures", "campfire_out.png")
PREVIEW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview", "campfire_preview.png")

OUTLINE = (13, 14, 17)
STONE = [(40, 41, 47), (55, 56, 62), (72, 73, 79), (92, 93, 98), (112, 112, 116)]
LOG_OUT = (20, 12, 8)
LOG = [(46, 29, 18), (66, 43, 27), (88, 59, 37)]
CHAR = [(22, 18, 17), (34, 28, 26)]
ASH = [(46, 45, 46), (62, 61, 61), (80, 78, 77)]
EMBER = (150, 44, 16)
# fire ramp, by heat: deep red -> red -> orange -> yellow -> pale core
FIRE = [(116, 26, 12), (176, 50, 16), (226, 96, 26), (250, 156, 44), (255, 210, 92), (255, 242, 186)]
FIRE_CUT = [0.16, 0.30, 0.45, 0.60, 0.76, 0.90]   # heat needed for each step

STONES = 12
RING_R = 13.0
LOGS = 5


def ring(px):
	"""Stones around the pit: each a small lit blob with an outline."""
	cover = set()
	for i in range(STONES):
		a = i / STONES * 6.283 + 0.35 + (h(i, 1) - 0.5) * 0.25
		cx = C + math.cos(a) * RING_R
		cy = C + math.sin(a) * RING_R
		r = 1.9 + h(i, 2) * 0.6
		mine = set()
		for y in range(int(cy - r) - 1, int(cy + r) + 2):
			for x in range(int(cx - r) - 1, int(cx + r) + 2):
				dx, dy = x + 0.5 - cx, y + 0.5 - cy
				d = math.hypot(dx * 0.9, dy)
				if d <= r and 0 <= x < F and 0 <= y < F:
					v = 2.2 - (dx + dy) / r * 1.1 + (h(i, x, y, 3) - 0.5) * 0.7
					px[x, y] = STONE[max(0, min(4, int(round(v))))]
					mine.add((x, y))
		for (x, y) in mine:
			for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				q = (x + ox, y + oy)
				if q not in mine and q not in cover and 0 <= q[0] < F and 0 <= q[1] < F:
					px[q] = OUTLINE
		cover |= mine
	return cover


def pit(px, burnt):
	"""Ash bed inside the ring, and the logs: spokes from the centre, charred inner ends."""
	for y in range(F):
		for x in range(F):
			d = math.hypot(x + 0.5 - C, y + 0.5 - C)
			if d < RING_R - 2.0:
				v = 1.0 + (h(x, y, 4) - 0.5) * 1.4 - (0.6 if d > RING_R - 4 else 0)
				px[x, y] = ASH[max(0, min(2, int(round(v))))]
	for i in range(LOGS):
		a = i / LOGS * 6.283 + 0.9
		dx, dy = math.cos(a), math.sin(a)
		for y in range(F):
			for x in range(F):
				pxx, pyy = x + 0.5 - C, y + 0.5 - C
				along = pxx * dx + pyy * dy
				across = -pxx * dy + pyy * dx
				if 0.5 < along < 9.5 and abs(across) < 1.9:
					if abs(across) > 1.2:
						px[x, y] = LOG_OUT
					elif burnt or along < 4.5:
						px[x, y] = CHAR[int(h(x, y, 5) < 0.5)]
					else:
						px[x, y] = LOG[1 + (1 if across < 0 else 0) - (1 if across > 0.6 else 0)]
					if burnt and along < 4 and h(x, y, 6) < 0.15:
						px[x, y] = EMBER


def heat(x, y, f):
	"""Fire heat 0..1 at a pixel on frame f. Core falloff, flame tongues that rotate and
	waver, and pulses that run outward. All periodic in FRAMES so the loop is seamless."""
	t = f / FRAMES * 6.283
	dx, dy = x + 0.5 - C, y + 0.5 - C
	r = math.hypot(dx, dy)
	th = math.atan2(dy, dx)
	# flame reach by angle: a few tongues, each wavering at its own whole-number speed
	reach = 8.2
	reach += 2.2 * math.sin(5 * th + 1 * t + 0.4)
	reach += 1.1 * math.sin(3 * th - 2 * t + 1.9)
	reach += 0.8 * math.sin(7 * th + 3 * t + 4.1)
	reach += 0.6 * math.sin(2 * t + 1.3)                     # the whole fire breathes
	v = 1.0 - r / max(reach, 2.5)
	# outward-running pulses: brighter bands that drift from the core
	v += 0.10 * math.sin(r * 1.1 - 2 * t)
	# flicker noise, changing every frame
	v += (h(x, y, f, 7) - 0.5) * 0.22
	return v


def frame(f):
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	pit(px, burnt=False)
	ring(px)
	for y in range(F):
		for x in range(F):
			v = heat(x, y, f)
			step = -1
			for i, cut in enumerate(FIRE_CUT):
				if v >= cut:
					step = i
			if step >= 0:
				px[x, y] = FIRE[step]
	# sparks: a few bright pixels flying out, different each frame
	for k in range(3):
		a = h(f, k, 8) * 6.283
		d = 6 + h(f, k, 9) * 7
		sx, sy = int(C + math.cos(a) * d), int(C + math.sin(a) * d)
		if 0 <= sx < F and 0 <= sy < F:
			px[sx, sy] = FIRE[4] if h(f, k, 10) < 0.5 else FIRE[3]
	return img


def out_image():
	img = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	px = img.load()
	pit(px, burnt=True)
	ring(px)
	return img


def preview(strip, off):
	"""Every frame and the unlit fire on darkened grass at 6x, plus an animated GIF."""
	g = Image.open(os.path.join(ROOT, "art", "ground", "grass_a_plain.png")).convert("RGBA")
	r, gg, b, a = g.split()
	g = Image.merge("RGBA", [c.point(lambda v: int(v * 0.66)) for c in (r, gg, b)] + [a])
	W = (FRAMES + 1) * 40
	out = Image.new("RGBA", (W, 40))
	for xx in range(0, W, g.width):
		out.paste(g.crop((0, 0, min(g.width, W - xx), 40)), (xx, 0))
	for f in range(FRAMES):
		out.alpha_composite(strip.crop((f * F, 0, f * F + F, F)), (4 + f * 40, 4))
	out.alpha_composite(off, (4 + FRAMES * 40, 4))
	out = out.resize((W * 6, 240), Image.NEAREST)
	gif = []
	for f in range(FRAMES):
		fr = g.crop((0, 0, 40, 40)).copy()
		fr.alpha_composite(strip.crop((f * F, 0, f * F + F, F)), (4, 4))
		gif.append(fr.resize((320, 320), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
	return out, gif


if __name__ == "__main__":
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	strip = Image.new("RGBA", (F * FRAMES, F), (0, 0, 0, 0))
	for f in range(FRAMES):
		strip.alpha_composite(frame(f), (f * F, 0))
	strip.save(OUT)
	off = out_image()
	off.save(OUT_OFF)
	still, gif = preview(strip, off)
	still.save(PREVIEW)
	gif[0].save(PREVIEW.replace(".png", ".gif"), save_all=True, append_images=gif[1:], duration=100, loop=0)
	print("wrote", OUT, OUT_OFF, "and previews")
