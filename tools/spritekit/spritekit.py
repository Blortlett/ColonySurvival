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
STRING = (226, 220, 198)
FLETCH = (176, 52, 44)
DARK_WOOD = [(30, 18, 12), (70, 44, 26), (104, 68, 38), (138, 96, 56)]  # club: reads against skin
IRON = [(22, 22, 30), (92, 96, 108), (148, 154, 166), (214, 220, 230)]
# Peasant cloth, drawn light and undyed so the game can tint (multiply) it toward earth tones.
LINEN = [(48, 40, 32), (170, 160, 136), (208, 200, 176), (232, 226, 206)]   # tunic
WOOL = [(44, 34, 28), (146, 130, 106), (180, 166, 140), (202, 190, 164)]    # trousers, hood
ROPE = (128, 108, 78)                                                       # belt (darker band)


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


def _leg(lay, sk, hip, foot, toe, trousers):
	"""One leg, hip -> foot (bare foot ellipse ahead of it along `toe` = +-1). Trousers draw
	over it in wool to the ankle; their cuff over the foot is a soft line, not an outline."""
	leg = union(capsule(*hip, *foot, 1.7), ellipse(foot[0] + 0.6 * toe, foot[1], 2.0, 1.5))
	skin_px = lay.draw_part(leg, sk, bands=(0.4, 0.85))
	if trousers:
		ax, ay = foot[0] - 0.5 * toe, foot[1]  # ankle, just behind the foot's centre
		lay.draw_part(union(capsule(*hip, ax, ay, 1.95), ellipse(*hip, 2.1, 2.1)), WOOL, bands=(0.4, 0.85), inner=skin_px)


def body_layer(skin, pose, outfit=()):
	"""pose: twist (rad), hand_l, hand_r (x, y). Optional (used by death): ox shifts the
	whole body along x, torso_rx stretches the torso, feet draws legs under it (lying down).
	outfit: garments to draw dressed ("tunic", "hood", "trousers" for the death legs), in the
	same draw order as the naked body, so outfit layer = dressed - naked (see outfit_layer)."""
	tunic, hood = "tunic" in outfit, "hood" in outfit
	tw = pose.get("twist", 0.0)
	ox = pose.get("ox", 0.0)
	trx = pose.get("torso_rx", 4.6)
	lie = pose.get("lie", 0.0)  # 0 standing .. 1 flat on the back (head and shoulders to -x)
	sdx, sdy = -lie * trx * 0.6, lie * 2.4
	lay = Layer()
	sk, hr = SKINS[skin], HAIR[skin]
	if "feet" in pose:
		for hy, foot in zip((21.5, 26.5), pose["feet"]):
			hip = (C - 1.6 + ox + trx * 0.45, C + (hy - C) * 0.8)
			_leg(lay, sk, hip, foot, 1, "trousers" in outfit)
	# torso + shoulders (twisted around the centre); the tunic is the same shape grown a little
	g = 0.6 if tunic else 0.0
	tcx = C - 1.6 + ox
	torso = union(
		ellipse(tcx, C, trx + g, 8.4 - 2.4 * lie + g, tw),
		ellipse(*rot(22.6 + ox + sdx, 17.6 + sdy, tw), 2.9 + g, 2.9 + g),
		ellipse(*rot(22.6 + ox + sdx, 30.4 - sdy, tw), 2.9 + g, 2.9 + g),
	)
	if tunic:
		ca, sa = math.cos(tw), math.sin(tw)

		def torso_mat(px, py, h):
			u = (px - tcx) * ca + (py - C) * sa  # along the facing, in the twisted torso frame
			if abs(u - BELT_U) < 0.5 and h > 0:
				return [LINEN[0], ROPE, ROPE, ROPE]
			return LINEN
		body = lay.draw_part(torso, torso_mat)
	else:
		body = lay.draw_part(torso, sk)
	# a tool held low on the right (spear) passes under the right shoulder
	under = footprint(ellipse(*rot(22.6 + ox + sdx, 30.4 - sdy, tw), 2.9, 2.9)) if pose.get("under_r_shoulder") else set()
	# head: hair over the back/top, face and nose at the front
	hx, hy = rot(C + 0.2 + ox - lie * (trx + 3.2), C, tw * 0.5)
	head = union(ellipse(hx, hy, 3.2, 3.5), ellipse(hx + 3.0, hy, 0.9, 0.7))

	def head_mat(px, py, h):
		dx, dy = px - hx, (py - hy) / 3.5
		return hr if dx < 0.9 - 1.6 * dy * dy else sk
	head_cov = footprint(head)

	def face_open(px, py):
		"""The hood's face opening: its edge sits HOOD_OPEN ahead of the head centre in the
		middle and sweeps back toward the sides (HOOD_SIDE), so the cheeks show too."""
		dx, dy = px - hx, (py - hy) / 3.5
		return dx > HOOD_OPEN - HOOD_SIDE * dy * dy

	def draw_head():
		if not hood:
			return lay.draw_part(head, head_mat, bands=(0.4, 0.9))
		# hooded: the whole opening is face (the hair is tucked under the cloth)
		px_ = lay.draw_part(head, lambda px, py, h: sk if face_open(px, py) else hr, bands=(0.4, 0.9))
		cap = ellipse(hx - 0.7, hy, 4.0, 4.0)  # round cowl, falling a little onto the back
		px_ |= lay.draw_part(lambda px, py: None if face_open(px, py) else cap(px, py), WOOL, bands=(0.35, 0.93), inner=px_)
		return px_
	# arms raised over the head ("over": an overhead swing) draw after it, so on top
	tunic_px = set(body)  # the tunic's own cloth: a sleeve lying on it draws no line there
	tunic_col = {k: lay.px[k] for k in tunic_px}
	over = pose.get("over", False)
	if over:
		body |= draw_head()
	# arms: shoulder -> elbow -> hand, one continuous part each (no inner outline at the
	# elbow or the shoulder); right arm first so the left reads on top where hands meet
	arm_cov, hand_cov = set(), set()
	for sh, hand, side in ((rot(SHOULDER_R[0] + ox + sdx, SHOULDER_R[1] - sdy, tw), pose["hand_r"], 1), (rot(SHOULDER_L[0] + ox + sdx, SHOULDER_L[1] + sdy, tw), pose["hand_l"], -1)):
		el = elbow(sh, hand, side, pose.get("bend"))
		arm = union(capsule(*sh, *el, 1.45), capsule(*el, *hand, 1.25), ellipse(*hand, 1.6, 1.6))
		seam = lambda x, y, sh=sh: (x - sh[0]) ** 2 + (y - sh[1]) ** 2 < 2.3 ** 2
		arm_cov |= footprint(arm)
		hand_cov |= footprint(ellipse(*hand, 1.6, 1.6))
		arm_px = lay.draw_part(arm, sk, bands=(0.5, 0.86), inner=body, seam=seam)
		if tunic:  # short sleeve from the shoulder to just above the elbow; its hem is a soft line
			cuff = (sh[0] + (el[0] - sh[0]) * SLEEVE, sh[1] + (el[1] - sh[1]) * SLEEVE)
			sleeve = capsule(*sh, *cuff, 1.7)
			sl_px = lay.draw_part(sleeve, LINEN, bands=(0.5, 0.86), inner=body | arm_px,
				seam=lambda x, y, seam=seam: seam(x, y) or (int(x), int(y)) in tunic_px)
			# along the sleeve's sides on the tunic, the bare arm's soft outline would peek out
			# where the sleeve drew no line: the tunic shows there (not at the hem)
			vx, vy = cuff[0] - sh[0], cuff[1] - sh[1]
			L2 = vx * vx + vy * vy or 1e-6
			for k in footprint(sleeve) - sl_px - arm_px - (body - tunic_px):
				if k in tunic_px and ((k[0] + 0.5 - sh[0]) * vx + (k[1] + 0.5 - sh[1]) * vy) / L2 < 0.8:
					lay.px[k] = tunic_col[k]
			arm_px |= sl_px
		body |= arm_px
	if pose.get("tool_on_arm"):  # resting on the shoulder/arm: only the hands cover it
		arm_cov = hand_cov
	if over:
		return lay, arm_cov | under  # the raised tool is above the head too
	draw_head()
	return lay, arm_cov | head_cov | under


def legs_layer(skin, pose, outfit=()):
	"""pose: dl, dr = forward offset of each foot (px). outfit: "trousers" draws them dressed."""
	lay = Layer()
	sk = SKINS[skin]
	for (hx, hy), d in ((HIP_L, pose["dl"]), (HIP_R, pose["dr"])):
		_leg(lay, sk, (hx, hy), (hx + d, hy), 1 if d >= 0 else -1, "trousers" in outfit)
	return lay


# Garment tuning (start values).
BELT_U = 3.6      # rope belt: distance ahead of the torso centre, along the facing
SLEEVE = 0.35     # sleeve length as a fraction of shoulder -> elbow
HOOD_OPEN = 0.4   # x of the hood's face opening at its middle, ahead of the head centre
HOOD_SIDE = 3.2   # how far back the opening sweeps toward the sides of the face

# Outfit slots and the garments drawn for each (plan §4.1).
OUTFITS = {"peasant": {"legs": ("trousers",), "torso": ("tunic",), "head": ("hood",)}}


def outfit_layer(dressed, naked):
	"""The outfit layer: every pixel of the dressed render that differs from the naked one.
	Drawn over the naked sheet it reproduces the dressed body (plan §4.2)."""
	out = Image.new("RGBA", (F, F), (0, 0, 0, 0))
	d, n = dressed.load(), naked.load()
	o = out.load()
	for y in range(F):
		for x in range(F):
			if d[x, y] != n[x, y]:
				o[x, y] = d[x, y]
	return out


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


def spear(butt, ang):
	"""Wooden spear with an iron leaf head, butt at `butt`, pointing along `ang`."""
	ux, uy = math.cos(ang), math.sin(ang)
	vx, vy = -uy, ux
	px, py = butt

	def P(u, v):
		return px + ux * u + vx * v, py + uy * u + vy * v
	L = 20.0
	shaft = capsule(*P(0, 0), *P(L, 0), 0.65)
	head = polygon([P(L - 0.8, 0.9), P(L + 1.0, 1.6), P(L + 3.8, 0), P(L + 1.0, -1.6), P(L - 0.8, -0.9)])
	edge = lambda x, y: abs((x - px) * vx + (y - py) * vy) < 0.5  # bright spine down the blade
	return shaft, head, edge


def club(pommel, ang):
	"""One-handed wooden club: a thin grip that swells into a heavy rounded head."""
	ux, uy = math.cos(ang), math.sin(ang)
	vx, vy = -uy, ux
	px, py = pommel

	def P(u, v):
		return px + ux * u + vx * v, py + uy * u + vy * v
	L = 13.0
	grip_ = capsule(*P(0, 0), *P(5.0, 0), 0.75)
	body = union(polygon([P(4.0, 0.8), P(L - 1.6, 2.2), P(L - 1.6, -2.2), P(4.0, -0.8)], 0.6),
		capsule(*P(L - 2.0, 0), *P(L - 1.0, 0), 2.3))
	knot = lambda x, y: abs((x - px) * ux + (y - py) * uy - (L - 3.2)) < 0.6 and (x - px) * vx + (y - py) * vy > 0.4
	return grip_, body, knot


def _line(lay, a, b, col):
	"""1px line with no outline (bow string, arrow shaft)."""
	n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 3) + 1
	for i in range(n + 1):
		t = i / n
		x, y = int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t)
		if 0 <= x < F and 0 <= y < F:
			lay.px[(x, y)] = col + (255,)


def bow_layer(p, occlude):
	"""Horizontal hunting bow. p: grip (left hand), ang (aim), draw (string point: the right
	hand, or None at rest), arrow (nocked arrow shown). The stave arcs across the aim line
	with its belly toward the archer; drawing pulls the tips back and in."""
	gx, gy = p["grip"]
	ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
	vx, vy = -uy, ux

	def P(u, v):
		return gx + ux * u + vx * v, gy + uy * u + vy * v
	pull = 0.0 if p.get("draw") is None else min(1.0, max(0.0, (math.hypot(p["draw"][0] - gx, p["draw"][1] - gy) - 2.4) / 6.0))
	half = 9.0 - 1.0 * pull       # tips come in as the limbs bend
	back = 1.8 + 1.8 * pull       # ... and back toward the archer
	pts = [P(-back * t * t, half * t) for t in [i / 6 - 1 for i in range(13)]]
	tip_a, tip_b = pts[0], pts[-1]
	lay = Layer()
	nock = p["draw"] if p.get("draw") is not None else ((tip_a[0] + tip_b[0]) / 2, (tip_a[1] + tip_b[1]) / 2)
	_line(lay, tip_a, nock, STRING)
	_line(lay, nock, tip_b, STRING)
	stave = union(*[capsule(*pts[i], *pts[i + 1], 0.75) for i in range(len(pts) - 1)])
	lay.draw_part(stave, WOOD, bands=(0.3, 0.75))
	if p.get("arrow"):
		a0 = nock
		a1 = (a0[0] + ux * 15.0, a0[1] + uy * 15.0)
		_line(lay, a0, a1, WOOD[3])
		lay.draw_part(polygon([(a1[0] + ux * 3.4, a1[1] + uy * 3.4), (a1[0] + vx * 1.7, a1[1] + vy * 1.7),
			(a1[0] - vx * 1.7, a1[1] - vy * 1.7)], 0.7), IRON)
		for k in (1.0, 2.0, 3.0):
			for sgn in (1, -1):
				x, y = int(a0[0] + ux * k + vx * sgn), int(a0[1] + uy * k + vy * sgn)
				lay.px[(x, y)] = FLETCH + (255,)
	for k in occlude:
		lay.px.pop(k, None)
	return lay


def pickaxe(pommel, ang, fs=1.0, scale=1.0, edge_on=False):
	"""Pickaxe: wooden haft with a curved two-spike iron head across its end. The swing is
	vertical, so `fs` foreshortens the haft (1 = lying flat in view, ~0.2 = pointing at the
	camera) and `scale` grows the whole tool as it rises toward the camera. Carried, the head
	is a T across the haft; swinging (edge_on) it lies in the swing plane, so from above it
	runs along the haft line as a curved spike leading past the end (the striking point),
	shortest when the head stands upright at the strike."""
	ux, uy = math.cos(ang), math.sin(ang)
	vx, vy = -uy, ux
	px, py = pommel

	def P(u, v):
		return px + ux * u * scale + vx * v * scale, py + uy * u * scale + vy * v * scale
	L = 14.0 * fs
	haft = capsule(*P(0, 0), *P(L + 0.6, 0), 0.75 * scale)
	if edge_on:
		k = 0.5 + 0.5 * math.sqrt(max(0.0, 1.0 - fs * fs))  # head's own foreshortening
		f, b = 6.5 * k, 5.0 * k  # striking spike ahead, back spike over the haft
		bow = 2.2 * k            # the crescent: spikes curve down from the socket
		top, bot = [], []
		for i in range(11):
			t = i / 5 - 1
			u = L + (f if t > 0 else b) * t
			vc = -bow + bow * t * t
			w = 1.5 * (1 - abs(t)) + 0.3
			top.append(P(u, vc - w))
			bot.append(P(u, vc + w))
		head = polygon(top + bot[::-1])
		tips = lambda x, y: (x - px) * ux + (y - py) * uy > (L + f * 0.55) * scale
		return haft, head, tips
	head = polygon([P(L - 1.8, -6.0), P(L + 0.4, -2.8), P(L + 2.0, -1.4), P(L + 2.0, 1.4), P(L + 0.4, 2.8),
		P(L - 1.8, 6.0), P(L - 0.4, 2.4), P(L - 1.0, 0), P(L - 0.4, -2.4)])
	tips = lambda x, y: abs((x - px) * vx + (y - py) * vy) > 4.0 * scale
	return haft, head, tips


def sword(pommel, ang):
	"""Arming sword: leather grip, iron crossguard and pommel, steel blade with a bright
	fuller down the middle, tapering to a point."""
	ux, uy = math.cos(ang), math.sin(ang)
	vx, vy = -uy, ux
	px, py = pommel

	def P(u, v):
		return px + ux * u + vx * v, py + uy * u + vy * v
	grip_ = capsule(*P(0.4, 0), *P(3.4, 0), 0.75)
	metal = union(
		polygon([P(3.9, -1.15), P(12.6, -0.95), P(15.0, 0), P(12.6, 0.95), P(3.9, 1.15)], 0.7),  # blade
		capsule(*P(3.6, -2.7), *P(3.6, 2.7), 0.75),  # crossguard
		ellipse(*P(-0.2, 0), 1.1, 1.1),              # pommel
	)
	fuller = lambda x, y: abs((x - px) * vx + (y - py) * vy) < 0.45 and (x - px) * ux + (y - py) * uy > 4.5
	return grip_, metal, fuller


SMEAR = (236, 240, 248)


def smear_arc(lay, centre, a0, a1, r0=8.0, r1=13.6, occlude=()):
	"""Pale motion arc swept by a blade from angle a0 to a1 around `centre` (thicker toward
	the tip), drawn under the blade; skips the last few degrees so it trails the blade."""
	lo, hi = min(a0, a1), max(a0, a1)
	trail = D(10)
	for y in range(F):
		for x in range(F):
			dx, dy = x + 0.5 - centre[0], y + 0.5 - centre[1]
			r = math.hypot(dx, dy)
			if not (r0 <= r <= r1) or (x, y) in lay.px or (x, y) in occlude:
				continue
			a = math.atan2(dy, dx)
			for base in (a, a + 2 * math.pi, a - 2 * math.pi):
				if lo <= base <= hi and abs(base - a1) > trail:
					t = (r - r0) / (r1 - r0)  # fade toward the inside of the arc
					lay.px[(x, y)] = SMEAR + (int(70 + 120 * t),)
					break


def item_layer(item, occlude, head_mat=None):
	lay = Layer()
	haft, head, edge = item
	lay.draw_part(haft, WOOD, bands=(0.3, 0.75))
	if head_mat == "wood":  # all-wood club: grain knot in the shadow tone
		lay.draw_part(union(haft, head), lambda x, y, h: [DARK_WOOD[0], DARK_WOOD[1], DARK_WOOD[1] if edge(x, y) else DARK_WOOD[2], DARK_WOOD[3]], bands=(0.35, 0.8))
	else:
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

# Unarmed jab with the right hand (the left guards); the left jab mirrors it.
PUNCH_R = [
	{"twist": D(10), "hand_l": (29.0, 17.5), "hand_r": (25.5, 32.0)},   # chamber
	{"twist": D(-14), "hand_l": (28.5, 18.0), "hand_r": (35.5, 25.5)},  # hit
	{"twist": D(-10), "hand_l": (28.5, 18.0), "hand_r": (34.0, 26.5)},  # hold
	{"twist": D(2), "hand_l": (29.0, 17.0), "hand_r": (29.5, 31.0)},    # back to guard
]
PUNCH_L = [{"twist": -p["twist"], "hand_l": (p["hand_r"][0], 2 * C - p["hand_r"][1]),
	"hand_r": (p["hand_l"][0], 2 * C - p["hand_l"][1])} for p in PUNCH_R]

# Falls backwards onto its back; the last frame is the corpse.
DEATH = [
	{"twist": D(8), "ox": -0.8, "hand_l": (27.5, 12.5), "hand_r": (26.5, 35.0)},
	{"ox": -1.5, "lie": 0.45, "torso_rx": 5.4, "feet": [(28.5, 21.5), (28.0, 26.5)], "hand_l": (17.0, 12.0), "hand_r": (18.0, 36.0)},
	{"ox": -2.0, "lie": 0.85, "torso_rx": 6.2, "feet": [(32.0, 21.0), (31.5, 27.0)], "hand_l": (13.0, 13.0), "hand_r": (14.0, 35.5)},
	{"ox": -2.0, "lie": 1.0, "torso_rx": 6.4, "feet": [(33.5, 20.5), (33.0, 27.5)], "hand_l": (12.0, 14.0), "hand_r": (13.0, 34.5)},
]
# Horizontal two-handed chop: wind up over the right shoulder, sweep across to the front.
AXE_SWING = [
	{"twist": D(14), "pommel": (25.0, 30.5), "ang": D(110)},   # ready / lift
	{"twist": D(30), "pommel": (22.5, 32.0), "ang": D(158)},   # wind-up
	{"twist": D(8), "pommel": (26.5, 30.0), "ang": D(70)},     # swing
	{"twist": D(-12), "pommel": (28.0, 26.0), "ang": D(4)},    # impact (straight ahead)
	{"twist": D(-20), "pommel": (27.5, 23.0), "ang": D(-30)},  # follow-through
	{"twist": D(-4), "pommel": (27.0, 27.5), "ang": D(40)},    # recover
]
# Carried low in the right hand, a third of the way up the haft, head forward past the hip.
AXE_IDLE = {"twist": D(3), "hand": (28.0, 32.6), "ang": D(16), "hand_l": (29.0, 16.0)}


def axe_walk(n=6):
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.08 * s,
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)),
			"hand": (28.0 - 1.6 * s, 32.6 + 0.3 * abs(s)),
			"ang": D(16 - 7 * s),
		})
	return out


# Two-handed spear thrust from a side-on stance: the shoulders turn left-side-forward (positive
# twist puts the right shoulder back) so the right hand sits just in front of the right
# shoulder on the butt, then the right shoulder drives through as the point goes straight
# ahead; hold, recover. The left hand guides further up the shaft and stays forward, in front
# of the head, while the shaft slides through it (grip_l = its distance from the butt).
SPEAR_THRUST = [
	{"twist": D(25), "pommel": (12.5, 26.8), "ang": D(-2), "grip_l": 15.0},   # ready (side-on)
	{"twist": D(36), "pommel": (10.5, 27.2), "ang": D(-1), "grip_l": 16.5},   # draw back: shaft slides through the left hand
	{"twist": D(14), "pommel": (18.5, 26.6), "ang": D(0), "grip_l": 11.0},    # drive: right shoulder comes through
	{"twist": D(4), "pommel": (23.0, 26.8), "ang": D(0), "grip_l": 8.0},      # full reach, arms out past the head
	{"twist": D(5), "pommel": (22.3, 26.9), "ang": D(0), "grip_l": 8.0},      # hold
	{"twist": D(16), "pommel": (16.0, 26.8), "ang": D(-1), "grip_l": 12.0},   # recover
]
# Carrying: one-handed in the right hand at its balance point, point forward, butt trailing
# past the hip (and under the right shoulder); the left arm is free.
SPEAR_IDLE = {"twist": D(3), "hand": (27.5, 34.2), "ang": D(-4), "hand_l": (29.0, 16.0)}


def spear_walk(n=6):
	"""Walk/run cycle carrying the spear: the left arm swings as usual, the spear arm swings
	a little and the point dips and rises with the step."""
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.07 * s,
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)),
			"hand": (27.5 - 1.4 * s, 34.2 + 0.3 * abs(s)),
			"ang": D(-4 + 3 * s),
		})
	return out


def axe_pose(p):
	if "hand" in p:  # one-handed carry
		ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
		h = p["hand"]
		return dict(p, hand_r=h, pommel=(h[0] - ux * 5.0, h[1] - uy * 5.0))
	hl, hr = grip(p["pommel"], p["ang"])
	return dict(p, hand_l=hl, hand_r=hr)


def spear_carry_pose(p):
	ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
	h = p["hand"]
	return dict(p, hand_r=h, pommel=(h[0] - ux * 9.0, h[1] - uy * 9.0), under_r_shoulder=True)


def spear_pose(p):
	hr, hl = grip(p["pommel"], p["ang"], 3.0, p.get("grip_l", 8.0))  # right hand near the butt, left forward
	return dict(p, hand_l=hl, hand_r=hr, under_r_shoulder=True)


# One-handed club, right hand on the grip (pose "hand"), left arm free to guard/balance.
# Swing: club cocked behind the right shoulder, whipped across the front, follow-through left.
CLUB_SWING = [
	{"twist": D(10), "hand": (27.0, 31.5), "ang": D(70), "hand_l": (28.5, 17.0)},    # ready
	{"twist": D(30), "hand": (21.5, 34.0), "ang": D(150), "hand_l": (29.5, 18.5)},   # wind-up behind the shoulder
	{"twist": D(10), "hand": (28.5, 33.0), "ang": D(75), "hand_l": (28.5, 17.5)},    # swing
	{"twist": D(-18), "hand": (33.0, 26.5), "ang": D(0), "hand_l": (26.5, 15.5)},    # impact, straight ahead
	{"twist": D(-26), "hand": (29.5, 20.5), "ang": D(-55), "hand_l": (24.5, 14.0)},  # follow-through
	{"twist": D(-4), "hand": (28.0, 29.5), "ang": D(35), "hand_l": (28.0, 16.5)},    # recover
]
CLUB_IDLE = {"twist": D(4), "hand": (27.5, 32.5), "ang": D(22), "hand_l": (29.0, 16.0)}


def club_walk(n=6):
	"""Walk/run cycle carrying the club low on the right: the left arm swings as usual, the
	club arm swings less and the club bobs with it."""
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.08 * s,
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)),
			"hand": (27.5 - 1.8 * s, 32.5 + 0.3 * abs(s)),
			"ang": D(22 - 9 * s),
		})
	return out


def club_pose(p):
	ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
	h = p["hand"]
	return dict(p, hand_r=h, pommel=(h[0] - ux * 1.6, h[1] - uy * 1.6))


# Bow, held horizontally in the left hand on an aim line just right of centre (the draw goes
# to the right cheek); the shoulders turn left-side-forward like the spear stance.
AIM_Y = 26.5
BOW_FIRE = [
	{"twist": D(12), "grip": (34.0, AIM_Y), "draw": (31.6, AIM_Y), "arrow": True},   # nock
	{"twist": D(18), "grip": (35.0, AIM_Y), "draw": (29.0, AIM_Y), "arrow": True},   # draw
	{"twist": D(22), "grip": (35.5, AIM_Y), "draw": (27.0, AIM_Y + 0.4), "arrow": True},  # full draw
	{"twist": D(22), "grip": (35.5, AIM_Y), "draw": None, "hand_r": (24.8, 29.0)},   # release
	{"twist": D(17), "grip": (35.0, AIM_Y), "draw": None, "hand_r": (25.5, 29.5)},   # follow-through
	{"twist": D(10), "grip": (34.0, AIM_Y), "draw": None, "hand_r": (29.0, 28.8)},   # recover, reach for an arrow
]
# Carried at the left side in the left hand, the hollow of the curve toward the body (tips
# pointing in) with the rear tip lifted off the shoulder, so the whole arc shows.
BOW_CARRY_ANG = D(-75)
BOW_IDLE = {"twist": D(-3), "grip": (27.0, 13.2), "bow_ang": BOW_CARRY_ANG, "hand_r": (29.0, 32.0)}


def bow_walk(n=6):
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.08 * s,
			"grip": (27.0 + 1.6 * s, 13.2 + 0.3 * abs(s)),
			"bow_ang": BOW_CARRY_ANG + D(6 * s),
			"hand_r": (27.5 - 3.0 * s, 32.5 + 0.5 * abs(s)),
		})
	return out


def bow_pose(p):
	q = dict(p, hand_l=p["grip"], ang=p.get("bow_ang", 0.0))
	if p.get("draw") is not None:
		q["hand_r"] = p["draw"]
	return q


# Pickaxe, two-handed vertical strike: lift, overhead (pick pointing back over the head),
# come over the top (pointing at the camera), bite into the ground ahead, recover. fs
# foreshortens the haft, scale grows the raised tool, ox leans the body, over draws the arms
# above the head.
PICK_SWING = [
	{"pommel": (27.5, 25.6), "ang": D(4), "fs": 0.85, "scale": 1.0, "ox": 0.0},                    # ready
	{"pommel": (26.0, 25.0), "ang": D(0), "fs": 0.30, "scale": 1.12, "ox": -0.4, "over": True},     # lift
	{"pommel": (24.6, 24.6), "ang": D(180), "fs": 0.60, "scale": 1.18, "ox": -0.9, "over": True},   # overhead, cocked back
	{"pommel": (27.5, 24.6), "ang": D(0), "fs": 0.22, "scale": 1.12, "ox": 0.2, "over": True},      # over the top
	{"pommel": (29.5, 24.8), "ang": D(0), "fs": 1.00, "scale": 1.0, "ox": 1.0},                     # strike: head in the ground
	{"pommel": (28.5, 25.2), "ang": D(2), "fs": 0.85, "scale": 1.0, "ox": 0.5},                     # recover
]
# Carried on the right shoulder: right hand on the haft in front, head resting behind.
PICK_IDLE = {"hand": (28.5, 30.0), "ang": D(166), "hand_l": (29.0, 16.0)}  # head angled out past the body


def pick_walk(n=6):
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.06 * s,
			"hand": (28.5 - 0.6 * s, 30.0 + 0.2 * abs(s)),
			"ang": D(166 + 3 * s),
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)),
		})
	return out


def pick_pose(p):
	ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
	if "hand" in p:  # shoulder carry: one hand, the pommel sticks out a little in front of it
		h = p["hand"]
		return dict(p, hand_r=h, pommel=(h[0] - ux * 2.5, h[1] - uy * 2.5), item_kw={"scale": 1.15}, tool_on_arm=True)
	fs, sc = p.get("fs", 1.0), p.get("scale", 1.0)
	q = dict(p, item_kw={"fs": fs, "scale": sc, "edge_on": True})
	q["hand_l"], q["hand_r"] = grip(p["pommel"], p["ang"], 1.0 * fs * sc, 4.2 * fs * sc)
	return q


# Sword, one-handed slash: cock to the right, then the arm reaches forward and the blade sweeps
# across the front (front-right -> ahead -> front-left, where the hit lands) with a smear;
# recover. "smear" = the blade's angle sweep this frame (from, to).
SWORD_SWING = [
	{"twist": D(6), "hand": (29.0, 29.0), "ang": D(20), "hand_l": (28.5, 17.0)},                               # ready
	{"twist": D(28), "hand": (25.5, 32.5), "ang": D(115), "hand_l": (29.5, 18.5)},                             # wind-up, cocked right
	{"twist": D(0), "hand": (32.0, 29.0), "ang": D(45), "hand_l": (28.5, 17.0), "smear": (D(115), D(45))},     # arm out, cut comes in front
	{"twist": D(-20), "hand": (32.5, 24.0), "ang": D(-8), "hand_l": (26.0, 15.5), "smear": (D(45), D(-8))},    # dead ahead: the hit
	{"twist": D(-30), "hand": (31.0, 20.5), "ang": D(-55), "hand_l": (24.5, 14.5), "smear": (D(-8), D(-55))},  # through to front-left
	{"twist": D(-6), "hand": (29.5, 27.0), "ang": D(15), "hand_l": (28.0, 16.5)},                              # recover
]
SWORD_IDLE = {"twist": D(3), "hand": (27.8, 32.6), "ang": D(26), "hand_l": (29.0, 16.0)}


def sword_walk(n=6):
	out = []
	for i in range(n):
		s = math.sin(2 * math.pi * i / n)
		out.append({
			"twist": -0.08 * s,
			"hand_l": (27.5 + 3.0 * s, 15.5 - 0.5 * abs(s)),
			"hand": (27.8 - 1.6 * s, 32.6 + 0.3 * abs(s)),
			"ang": D(26 - 6 * s),
		})
	return out


def sword_pose(p):
	ux, uy = math.cos(p["ang"]), math.sin(p["ang"])
	h = p["hand"]
	return dict(p, hand_r=h, pommel=(h[0] - ux * 1.9, h[1] - uy * 1.9))


# name -> (item drawing, pose -> hands); each tool has <tool>_idle and an action strip.
TOOL_ANIMS = [
	("axe_idle", axe, axe_pose, [AXE_IDLE]),
	("axe_walk", axe, axe_pose, axe_walk()),
	("axe_swing", axe, axe_pose, AXE_SWING),
	("spear_idle", spear, spear_carry_pose, [SPEAR_IDLE]),
	("spear_walk", spear, spear_carry_pose, spear_walk()),
	("spear_thrust", spear, spear_pose, SPEAR_THRUST),
	("club_idle", club, club_pose, [CLUB_IDLE]),
	("club_walk", club, club_pose, club_walk()),
	("club_swing", club, club_pose, CLUB_SWING),
	("pickaxe_idle", pickaxe, pick_pose, [PICK_IDLE]),
	("pickaxe_walk", pickaxe, pick_pose, pick_walk()),
	("pickaxe_swing", pickaxe, pick_pose, PICK_SWING),
	("sword_idle", sword, sword_pose, [SWORD_IDLE]),
	("sword_walk", sword, sword_pose, sword_walk()),
	("sword_swing", sword, sword_pose, SWORD_SWING),
	("bow_idle", "bow", bow_pose, [BOW_IDLE]),
	("bow_walk", "bow", bow_pose, bow_walk()),
	("bow_fire", "bow", bow_pose, BOW_FIRE),
]
WOOD_TOOLS = {"club"}


# ---------------------------------------------------------------- output

def strip(frames):
	im = Image.new("RGBA", (F * len(frames), F), (0, 0, 0, 0))
	for i, f in enumerate(frames):
		im.alpha_composite(f, (i * F, 0))
	return im


LEGS_IDLE = {"dl": 0.5, "dr": -0.5}


def outfit_sheets(sheets, outfit, kind, anim, poses):
	"""Per-slot outfit sheets for one animation, frame for frame with its naked sheet, per
	skin: kind "legs" diffs legs_layer (legs slot only), kind "body" diffs body_layer for the
	torso and head slots, plus the legs slot when the body draws legs itself (death)."""
	slots = OUTFITS[outfit]
	naked = sheets[f"human_{kind}_{anim}"]
	if kind == "legs":
		todo = [("legs", lambda s, p: legs_layer(s, p, slots["legs"]).image())]
	else:
		todo = [(slot, lambda s, p, g=slots[slot]: body_layer(s, p, g)[0].image()) for slot in ("torso", "head")]
		if any("feet" in p for p in poses):
			todo.insert(0, ("legs", lambda s, p: body_layer(s, p, slots["legs"])[0].image()))
	for slot, dressed in todo:
		sheets[f"human_outfit_{slot}_{outfit}_{anim}"] = {
			s: [outfit_layer(dressed(s, p), n) for p, n in zip(poses, naked[s])] for s in SKINS}


def build():
	os.makedirs(OUT, exist_ok=True)
	sheets = {}
	walk = walk_poses()
	body_anims = [("idle", [IDLE_HANDS]), ("walk", walk), ("gather", gather_poses()),
		("punch_right", PUNCH_R), ("punch_left", PUNCH_L), ("death", DEATH)]
	sheets["human_legs_idle"] = {s: [legs_layer(s, LEGS_IDLE).image()] for s in SKINS}
	sheets["human_legs_walk"] = {s: [legs_layer(s, p).image() for p in walk] for s in SKINS}
	for anim, poses in body_anims:
		sheets["human_body_" + anim] = {s: [body_layer(s, p)[0].image() for p in poses] for s in SKINS}
	outfit_jobs = [("legs", "idle", [LEGS_IDLE]), ("legs", "walk", walk)] + [("body", a, ps) for a, ps in body_anims]
	for name, draw_item, to_pose, poses in TOOL_ANIMS:
		body, item = {}, []
		outfit_jobs.append(("body", name, [to_pose(p) for p in poses]))
		for s in SKINS:
			body[s] = []
			for p in poses:
				p = to_pose(p)
				lay, occ = body_layer(s, p)
				body[s].append(lay.image())
				if s == "light" and draw_item == "bow":
					item.append(bow_layer(p, occ).image())
				elif s == "light":
					il = item_layer(draw_item(p["pommel"], p["ang"], **p.get("item_kw", {})), occ,
						"wood" if name.split("_")[0] in WOOD_TOOLS else None)
					if "smear" in p:
						smear_arc(il, p["hand"], *p["smear"], occlude=occ)
					item.append(il.image())
		sheets["human_body_" + name] = body
		sheets["item_" + name] = {"": item}
	for outfit in OUTFITS:
		for kind, anim, poses in outfit_jobs:
			outfit_sheets(sheets, outfit, kind, anim, poses)
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
		rows.append([Image.alpha_composite(legs_i, b) for b in sheets["human_body_punch_right"][s] + sheets["human_body_punch_left"][s]])
		rows.append(list(sheets["human_body_death"][s]))
		for name in [t[0] for t in TOOL_ANIMS]:
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


GRASS = (78, 96, 62)
# Concept tints (multiplied onto the cloth layers as the game's modulate would): legs, torso, head.
EARTH = {
	"undyed": ((255, 255, 255), (255, 255, 255), (255, 255, 255)),
	"brown": ((150, 118, 88), (196, 160, 120), (150, 118, 88)),
	"green": ((150, 134, 108), (132, 146, 112), (120, 130, 100)),
	"ochre": ((140, 128, 110), (232, 190, 112), (190, 150, 96)),
}


def _tint(im, rgb):
	r, g, b, a = im.split()
	r = r.point(lambda v: v * rgb[0] // 255)
	g = g.point(lambda v: v * rgb[1] // 255)
	b = b.point(lambda v: v * rgb[2] // 255)
	return Image.merge("RGBA", (r, g, b, a))


def outfit_frames(skin, outfit, body_poses, legs_poses):
	"""Naked legs/body plus one outfit layer per slot, frame for frame:
	[(legs, legs_outfit, body, torso_outfit, head_outfit), ...]."""
	slots = OUTFITS[outfit]
	out = []
	for bp, lp in zip(body_poses, legs_poses):
		legs = legs_layer(skin, lp).image()
		body = body_layer(skin, bp)[0].image()
		out.append((legs, outfit_layer(legs_layer(skin, lp, slots["legs"]).image(), legs),
			body, outfit_layer(body_layer(skin, bp, slots["torso"])[0].image(), body),
			outfit_layer(body_layer(skin, bp, slots["head"])[0].image(), body)))
	return out


def _stack(fr, tint):
	legs, lo, body, to, ho = fr
	im = Image.alpha_composite(legs, _tint(lo, tint[0]))
	im = Image.alpha_composite(im, body)
	im = Image.alpha_composite(im, _tint(to, tint[1]))
	return Image.alpha_composite(im, _tint(ho, tint[2]))


def peasant_preview(png_path, gif_path, scale=7):
	"""Look test: clothed peasant idle + walk, both skins, in several earth-tone tints.
	Still sheet: one row per skin x tint (naked first), idle then the 6 walk frames.
	GIF: the walk at 10 fps, tints across, skins down."""
	walk = walk_poses()
	idle_l = {"dl": 0.5, "dr": -0.5}
	S, pad = F * scale, 4
	big = lambda im: im.resize((S, S), Image.NEAREST)
	rows, gif_cells = [], {}
	for s in SKINS:
		frames = outfit_frames(s, "peasant", [IDLE_HANDS] + walk, [idle_l] + walk)
		rows.append([Image.alpha_composite(f[0], f[2]) for f in frames])
		for t, tint in EARTH.items():
			rows.append([_stack(f, tint) for f in frames])
			gif_cells[(s, t)] = rows[-1][1:]
	cols = max(len(r) for r in rows)
	canvas = Image.new("RGBA", (cols * (S + pad), len(rows) * (S + pad)), GRASS + (255,))
	for j, r in enumerate(rows):
		for i, f in enumerate(r):
			canvas.alpha_composite(big(f), (i * (S + pad), j * (S + pad)))
	canvas.save(png_path)
	gif = []
	for k in range(len(walk)):
		im = Image.new("RGBA", (len(EARTH) * S, len(SKINS) * S), GRASS + (255,))
		for j, s in enumerate(SKINS):
			for i, t in enumerate(EARTH):
				im.alpha_composite(big(gif_cells[(s, t)][k]), (i * S, j * S))
		gif.append(im.convert("RGB"))
	gif[0].save(gif_path, save_all=True, append_images=gif[1:], duration=100, loop=0, disposal=2, optimize=False)


# Outfit review GIFs: (gif name, [(body anim, fps, loops)]); a 1-frame idle holds ~0.8 s and
# death holds its last frame. Walk anims use the walk legs, the rest the idle legs.
OUTFIT_GIFS = [("unarmed", [("idle", 1, 1), ("walk", 10, 2), ("gather", 9, 2), ("punch_right", 14, 2),
	("punch_left", 14, 2), ("death", 8, 1)])] + [
	(t, [(f"{t}_idle", 1, 1), (f"{t}_walk", 10, 2), (act, fps, 3)]) for t, act, fps in (
		("axe", "axe_swing", 10), ("pickaxe", "pickaxe_swing", 9), ("spear", "spear_thrust", 14),
		("club", "club_swing", 14), ("sword", "sword_swing", 16), ("bow", "bow_fire", 10))]


def outfit_gifs(sheets, outfit, out_dir, scale=7):
	"""One GIF per entry of OUTFIT_GIFS: naked, then dressed, light skin then dark, side by side,
	every layer composited in game order (legs, legs outfit, body, torso, head outfit, item)."""
	S = F * scale
	big = lambda im: im.resize((S, S), Image.NEAREST)
	paths = []
	for gif_name, seq in OUTFIT_GIFS:
		frames, durs = [], []
		for anim, fps, loops in seq:
			legs = "walk" if anim.endswith("walk") else "idle"
			body = sheets["human_body_" + anim]
			n = len(body["light"])
			for _ in range(loops):
				for i in range(n):
					im = Image.new("RGBA", (4 * S, S), GRASS + (255,))
					for j, (s, dressed) in enumerate((("light", False), ("light", True), ("dark", False), ("dark", True))):
						ls = sheets["human_legs_" + legs][s]
						parts = [] if anim == "death" else [ls[i % len(ls)]]  # the corpse draws its own legs
						if dressed and parts:
							parts.append(sheets[f"human_outfit_legs_{outfit}_{legs}"][s][i % len(ls)])
						parts.append(body[s][i])
						if dressed:
							if anim == "death":
								parts.append(sheets[f"human_outfit_legs_{outfit}_death"][s][i])
							parts += [sheets[f"human_outfit_{sl}_{outfit}_{anim}"][s][i] for sl in ("torso", "head")]
						if "item_" + anim in sheets:
							parts.append(sheets["item_" + anim][""][i])
						c = Image.new("RGBA", (F, F), (0, 0, 0, 0))
						for p in parts:
							c = Image.alpha_composite(c, p)
						im.alpha_composite(big(c), (j * S, 0))
					frames.append(im.convert("RGB"))
					durs.append(800 if n == 1 else (1200 if anim == "death" and i == n - 1 else round(1000 / fps)))
		path = os.path.join(out_dir, f"{outfit}_{gif_name}.gif")
		frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0, disposal=2, optimize=False)
		paths.append(path)
	return paths


if __name__ == "__main__":
	if len(sys.argv) > 1 and sys.argv[1] == "--outfit-gifs":  # rebuilds art/, then the outfit review GIFs
		d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview")
		for p in outfit_gifs(build(), "peasant", d):
			print("wrote", p)
		sys.exit(0)
	if len(sys.argv) > 1 and sys.argv[1] == "--peasant":  # look test only; leaves art/ untouched
		d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "preview")
		peasant_preview(os.path.join(d, "peasant_preview.png"), os.path.join(d, "peasant_walk.gif"))
		print("wrote peasant preview to", d)
		sys.exit(0)
	sh = build()
	if len(sys.argv) > 1:
		preview(sh, sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 8)
	print("wrote", OUT)
