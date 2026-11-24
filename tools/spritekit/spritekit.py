"""Procedural top-down human spritekit (test batch).

Draws a small rigged human, facing +X in 48x48 frames like the Sci-Fi TDS pack, from
primitive shapes (ellipses, capsules, polygons) with per-part outlines and banded shading.
Every animation is a list of poses; every layer (legs, body, item) is written as its own
horizontal strip so the game can stack them:  legs -> body -> (outfit) -> item.
The item layer has hands/head occlusion baked in, so it can always draw on top.

Run:  python tools/spritekit/spritekit.py            (writes art/characters/human/)
"""
import math
import os
import sys

from PIL import Image

F = 48                      # frame size
C = 24.0                    # frame centre
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "art", "characters", "human")

# ---------------------------------------------------------------- palettes
# Each material: outline, shadow, base, light.
SKINS = {
	"light": [(46, 26, 24), (168, 108, 84), (214, 156, 122), (238, 196, 162)],
	"dark": [(24, 12, 10), (100, 62, 42), (142, 94, 64), (180, 130, 92)],
}
HAIR = {
	"light": [(30, 20, 16), (64, 44, 30), (92, 64, 42), (122, 88, 58)],
	"dark": [(14, 10, 10), (30, 24, 22), (46, 38, 34), (66, 56, 50)],
}
WOOD = [(42, 26, 16), (96, 62, 34), (134, 90, 50), (170, 122, 72)]
IRON = [(22, 22, 30), (92, 96, 108), (148, 154, 166), (214, 220, 230)]


# ---------------------------------------------------------------- shapes
# A shape answers sdf-ish queries: inside(px, py) -> None or a "height" 0..1 used for shading.

def ellipse(cx, cy, rx, ry, rot=0.0):
	c, s = math.cos(rot), math.sin(rot)

	def f(px, py):
		dx, dy = px - cx, py - cy
		u, v = (dx * c + dy * s) / rx, (-dx * s + dy * c) / ry
		d2 = u * u + v * v
		return math.sqrt(1 - d2) if d2 <= 1 else None
	return f


def capsule(ax, ay, bx, by, r):
	def f(px, py):
		vx, vy = bx - ax, by - ay
		L2 = vx * vx + vy * vy
		t = 0 if L2 == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L2))
		dx, dy = px - (ax + vx * t), py - (ay + vy * t)
		d2 = (dx * dx + dy * dy) / (r * r)
		return math.sqrt(1 - d2) if d2 <= 1 else None
	return f


def polygon(pts, height=0.7):
	def f(px, py):
		inside = False
		j = len(pts) - 1
		for i in range(len(pts)):
			xi, yi = pts[i]
			xj, yj = pts[j]
			if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
				inside = not inside
			j = i
		return height if inside else None
	return f


def union(*shapes):
	def f(px, py):
		best = None
		for s in shapes:
			h = s(px, py)
			if h is not None and (best is None or h > best):
				best = h
		return best
	return f


# ---------------------------------------------------------------- layers

def _mix(a, b, t=0.45):
	return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


class Layer:
	"""A 48x48 RGBA buffer plus a coverage mask (for occlusion)."""

	def __init__(self):
		self.px = {}  # (x, y) -> rgba

	def draw_part(self, shape, material, bands=(0.45, 0.88), outline=True, inner=(), seam=None):
		"""Rasterise one part with its own 1px outline, painted over what's already here.
		`material` is a palette list or a function (x, y, h) -> palette.
		Outline only goes on the exterior: where the ring lands on `inner` pixels (a part this
		one lies over, like an arm over the torso) it uses the soft shadow tone instead, and
		where `seam(x, y)` is true (a joint, like the shoulder) it is left out entirely."""
		filled = {}
		for y in range(F):
			for x in range(F):
				h = shape(x + 0.5, y + 0.5)
				if h is None:
					continue
				pal = material(x + 0.5, y + 0.5, h) if callable(material) else material
				tone = 1 if h < bands[0] else (2 if h < bands[1] else 3)
				filled[(x, y)] = pal[tone]
		if outline:
			for (x, y) in list(filled):
				for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
					if (nx, ny) not in filled and 0 <= nx < F and 0 <= ny < F:
						if seam is not None and seam(nx + 0.5, ny + 0.5):
							continue
						pal = material(nx + 0.5, ny + 0.5, 0) if callable(material) else material
						self.px[(nx, ny)] = (_mix(pal[0], pal[1]) if (nx, ny) in inner else pal[0]) + (255,)
		for k, c in filled.items():
			self.px[k] = c + (255,)
		return set(filled)

	def image(self):
		im = Image.new("RGBA", (F, F), (0, 0, 0, 0))
		for (x, y), c in self.px.items():
			im.putpixel((x, y), c)
		return im


def footprint(shape):
	"""Pixels a part would cover, including its outline ring."""
	cov = set()
	for y in range(F):
		for x in range(F):
			if shape(x + 0.5, y + 0.5) is not None:
				cov.add((x, y))
	ring = set()
	for (x, y) in cov:
		ring |= {(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)}
	return cov | ring


# ---------------------------------------------------------------- rig

def rot(px, py, a, ox=C, oy=C):
	c, s = math.cos(a), math.sin(a)
	dx, dy = px - ox, py - oy
	return ox + dx * c - dy * s, oy + dx * s + dy * c


SHOULDER_L = (22.8, 17.2)   # left = -Y when facing +X
SHOULDER_R = (22.8, 30.8)
UPPER, FORE = 5.0, 5.2      # arm bone lengths (px)
MAX_BEND = 1.6              # how far an elbow may stick out from the shoulder-hand line


def elbow(sh, hand, side, max_bend=None):
	"""Two-bone IK: elbow position for a shoulder and hand, bending outward (side = +1
	for the right arm, which bends towards +Y; -1 for the left)."""
	dx, dy = hand[0] - sh[0], hand[1] - sh[1]
	d = math.hypot(dx, dy) or 1e-6
	a, b = UPPER, FORE
	if d >= a + b:  # out of reach: straight arm
		return sh[0] + dx * a / (a + b), sh[1] + dy * a / (a + b)
	x = (a * a - b * b + d * d) / (2 * d)
	h = min(math.sqrt(max(0.0, a * a - x * x)), MAX_BEND if max_bend is None else max_bend)
	ux, uy = dx / d, dy / d
	nx, ny = -uy, ux
	if ny * side < 0:
		nx, ny = -nx, -ny
	return sh[0] + ux * x + nx * h, sh[1] + uy * x + ny * h
HIP_L = (22.5, 21.5)
HIP_R = (22.5, 26.5)


def body_layer(skin, pose):
	"""pose: twist (rad), hand_l, hand_r (x, y)."""
	tw = pose.get("twist", 0.0)
	lay = Layer()
	sk, hr = SKINS[skin], HAIR[skin]
	# torso + shoulders (twisted around the centre)
	torso = union(
		ellipse(C - 1.6, C, 4.6, 8.4, tw),
		ellipse(*rot(22.6, 17.6, tw), 2.9, 2.9),
		ellipse(*rot(22.6, 30.4, tw), 2.9, 2.9),
	)
	body = lay.draw_part(torso, sk)
	# arms: shoulder -> elbow -> hand, one continuous part each (no inner outline at the
	# elbow or the shoulder); right arm first so the left reads on top where hands meet
	arm_cov = set()
	for sh, hand, side in ((rot(*SHOULDER_R, tw), pose["hand_r"], 1), (rot(*SHOULDER_L, tw), pose["hand_l"], -1)):
		el = elbow(sh, hand, side, pose.get("bend"))
		arm = union(capsule(*sh, *el, 1.45), capsule(*el, *hand, 1.25), ellipse(*hand, 1.6, 1.6))
		seam = lambda x, y, sh=sh: (x - sh[0]) ** 2 + (y - sh[1]) ** 2 < 2.3 ** 2
		arm_cov |= footprint(arm)
		body |= lay.draw_part(arm, sk, bands=(0.5, 0.86), inner=body, seam=seam)
	# head: hair over the back/top, face and nose at the front
	hx, hy = rot(C + 0.2, C, tw * 0.5)
	head = union(ellipse(hx, hy, 3.2, 3.5), ellipse(hx + 3.0, hy, 0.9, 0.7))

	def head_mat(px, py, h):
		dx, dy = px - hx, (py - hy) / 3.5
		return hr if dx < 0.9 - 1.6 * dy * dy else sk
	head_cov = footprint(head)
	lay.draw_part(head, head_mat, bands=(0.4, 0.9))
	return lay, arm_cov | head_cov


def legs_layer(skin, pose):
	"""pose: dl, dr = forward offset of each foot (px)."""
	lay = Layer()
	sk = SKINS[skin]
	for (hx, hy), d in ((HIP_L, pose["dl"]), (HIP_R, pose["dr"])):
		fx = hx + d
		leg = union(capsule(hx, hy, fx, hy, 1.7), ellipse(fx + 0.6 * (1 if d >= 0 else -1), hy, 2.0, 1.5))
		lay.draw_part(leg, sk, bands=(0.4, 0.85))
	return lay


# ---------------------------------------------------------------- items

def axe(pommel, ang):
	"""Two-handed felling axe, pommel at `pommel`, pointing along `ang`. Blade on the
	leading (-v) side for a right-to-left (counter-clockwise) swing."""
	ux, uy = math.cos(ang), math.sin(ang)
	vx, vy = -uy, ux
	px, py = pommel

	def P(u, v):
		return px + ux * u + vx * v, py + uy * u + vy * v
	L = 15.0
	haft = capsule(*P(0, 0), *P(L + 0.5, 0), 0.75)
	head = polygon([P(L - 2.0, 2.2), P(L + 0.4, 2.2), P(L + 0.6, -1.2), P(L + 2.6, -4.6),
		P(L - 4.6, -4.6), P(L - 2.2, -1.2)])
	edge = lambda x, y: (x - px) * vx + (y - py) * vy < -3.6
	return haft, head, edge


def item_layer(item, occlude):
	lay = Layer()
	haft, head, edge = item
	lay.draw_part(haft, WOOD, bands=(0.3, 0.75))
	lay.draw_part(head, lambda x, y, h: [IRON[0], IRON[1], IRON[3] if edge(x, y) else IRON[2], IRON[3]])
	for k in occlude:
		lay.px.pop(k, None)
	return lay


def grip(pommel, ang, a=0.8, b=3.4):
	"""Hand positions on a haft: left near the pommel, right further up."""
	ux, uy = math.cos(ang), math.sin(ang)
	return (pommel[0] + ux * a, pommel[1] + uy * a), (pommel[0] + ux * b, pommel[1] + uy * b)


# ---------------------------------------------------------------- animations

IDLE_HANDS = {"hand_l": (29.0, 16.0), "hand_r": (29.0, 32.0)}


def walk_poses(n=6):
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.10 * s,
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)), "hand_r": (27.5 - 3.0 * s, 32.5 + 0.5 * abs(s)),
			"dl": -5.0 * s, "dr": 5.0 * s,
		})
	return out


def gather_poses(n=8):
	"""Unarmed gather: both hands in front of the chest working hand over hand, like
	untangling a rope. Each hand circles a small loop (forward on top, back underneath),
	half a cycle apart, with a slight lean and shoulder rock."""
	out = []
	for i in range(n):
		a = 2 * math.pi * i / n
		out.append({
			"twist": 0.035 * math.sin(a),
			"bend": 0.7,
			"hand_l": (32.0 + 1.0 * math.cos(a), 20.8 + 0.8 * math.sin(a)),
			"hand_r": (32.0 + 1.0 * math.cos(a + math.pi), 27.2 + 0.8 * math.sin(a + math.pi)),
		})
	return out


D = math.radians
# Horizontal two-handed chop: wind up over the right shoulder, sweep across to the front.
AXE_SWING = [
	{"twist": D(14), "pommel": (25.0, 30.5), "ang": D(110)},   # ready / lift
	{"twist": D(30), "pommel": (22.5, 32.0), "ang": D(158)},   # wind-up
	{"twist": D(8), "pommel": (26.5, 30.0), "ang": D(70)},     # swing
	{"twist": D(-12), "pommel": (28.0, 26.0), "ang": D(4)},    # impact (straight ahead)
	{"twist": D(-20), "pommel": (27.5, 23.0), "ang": D(-30)},  # follow-through
	{"twist": D(-4), "pommel": (27.0, 27.5), "ang": D(40)},    # recover
]
AXE_IDLE = {"twist": D(6), "pommel": (26.0, 31.5), "ang": D(60)}


def axe_pose(p):
	hl, hr = grip(p["pommel"], p["ang"])
	return dict(p, hand_l=hl, hand_r=hr)


# ---------------------------------------------------------------- output

def strip(frames):
	im = Image.new("RGBA", (F * len(frames), F), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		im.alpha_composite(f, (i * F, 0))
	return im


def build():
	os.makedirs(OUT, exist_ok=True)
	sheets = {}
	walk = walk_poses()
	sheets["human_legs_idle"] = {s: [legs_layer(s, {"dl": 0.5, "dr": -0.5}).image()] for s in SKINS}
	sheets["human_legs_walk"] = {s: [legs_layer(s, p).image() for p in walk] for s in SKINS}
	sheets["human_body_idle"] = {s: [body_layer(s, IDLE_HANDS)[0].image()] for s in SKINS}
	sheets["human_body_walk"] = {s: [body_layer(s, p)[0].image() for p in walk] for s in SKINS}
	sheets["human_body_gather"] = {s: [body_layer(s, p)[0].image() for p in gather_poses()] for s in SKINS}
	for name, poses in (("axe_idle", [AXE_IDLE]), ("axe_swing", AXE_SWING)):
		body, item = {}, []
		for s in SKINS:
			body[s] = []
			for p in poses:
				p = axe_pose(p)
				lay, occ = body_layer(s, p)
				body[s].append(lay.image())
				if s == "light":
					item.append(item_layer(axe(p["pommel"], p["ang"]), occ).image())
		sheets["human_body_" + name] = body
		sheets["item_" + name] = {"": item}
	for name, by_skin in sheets.items():
		for s, frames in by_skin.items():
			fn = f"{name}_{s}_Sheet.png" if s else f"{name}_Sheet.png"
			strip(frames).save(os.path.join(OUT, fn))
	return sheets


def preview(sheets, path, scale=8):
	"""Composited legs+body+item per skin for idle, walk, axe idle and swing."""
	rows = []
	for s in SKINS:
		legs_i = sheets["human_legs_idle"][s][0]
		rows.append([Image.alpha_composite(legs_i, b) for b in sheets["human_body_idle"][s]])
		rows.append([Image.alpha_composite(l, b) for l, b in zip(sheets["human_legs_walk"][s], sheets["human_body_walk"][s])])
		rows.append([Image.alpha_composite(legs_i, b) for b in sheets["human_body_gather"][s]])
		for name in ("axe_idle", "axe_swing"):
			rows.append([Image.alpha_composite(Image.alpha_composite(legs_i, b), it)
				for b, it in zip(sheets["human_body_" + name][s], sheets["item_" + name][""])])
	cols = max(len(r) for r in rows)
	pad = 4
	W, H = cols * (F * scale + pad), len(rows) * (F * scale + pad)
	canvas = Image.new("RGBA", (W, H), (78, 96, 62, 255))
	for j, r in enumerate(rows):
		for i, f in enumerate(r):
			canvas.alpha_composite(f.resize((F * scale, F * scale), Image.NEAREST), (i * (F * scale + pad), j * (F * scale + pad)))
	canvas.save(path)


if __name__ == "__main__":
	sh = build()
	if len(sys.argv) > 1:
		preview(sh, sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8)
	print("wrote", OUT)
