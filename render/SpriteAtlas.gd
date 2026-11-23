extends RefCounted
## Packs every sheet named in BodySets into one mipmapped texture, so all agent sprites draw
## in one MultiMesh call, and compiles each set's animations into UV rects with fallbacks
## resolved (see BodySets.gd).
##
## Compiled anim: {"uv": Array[Vector4] (u, v, w, h per frame), "fps", "loop", "px" (frame
## size in world px), "alt": Array[Vector4] or [], "stride" (0 = fixed rate)}.
## Compiled set: {"name", "weight", "angle", "tints", "legs": {idle, walk, run}, "torso": {...}}.

const BodySets := preload("res://render/BodySets.gd")

const ALIGN := 16 # rows start on 16 px so mip levels up to 4 don't bleed between rows

static var texture: ImageTexture = null
static var sets: Array = [] # compiled sets, in BodySets order
static var total_weight := 0


static func ensure() -> void:
	if texture != null:
		return
	# 1. Load every distinct sheet.
	var paths: Array[String] = []
	for s in BodySets.SETS.values():
		for part in ["legs", "torso"]:
			for anim in s[part].values():
				for key in ["sheet", "alt"]:
					if anim.has(key) and not paths.has(anim[key]):
						paths.append(anim[key])
	var images := {}
	var width := 0
	var height := 0
	for p in paths:
		var tex: Texture2D = load(BodySets.DIR + p)
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		images[p] = img
		width = maxi(width, img.get_width())
		height += _aligned(img.get_height())
	# 2. One strip per row.
	var atlas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var rows := {} # path -> y
	var y := 0
	for p in paths:
		var img: Image = images[p]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		rows[p] = y
		y += _aligned(img.get_height())
	atlas.generate_mipmaps()
	texture = ImageTexture.create_from_image(atlas)
	# 3. Compile the sets.
	var size := Vector2(width, height)
	for set_name in BodySets.SETS:
		var s: Dictionary = BodySets.SETS[set_name]
		var c := {"name": set_name, "weight": int(s.get("weight", 1)), "angle": float(s.get("angle", 0.0)),
			"tints": s.get("tints", [Color.WHITE]), "legs": {}, "torso": {}}
		var scale: float = s.get("scale", 1.0)
		for part in ["legs", "torso"]:
			for anim_name in s[part]:
				c[part][anim_name] = _compile(s[part][anim_name], images, rows, size, scale)
		var t: Dictionary = c.torso
		var l: Dictionary = c.legs
		assert(t.has("idle") and t.has("death") and l.has("idle"), "BodySets %s needs torso idle/death and legs idle" % set_name)
		for pair in [["walk", "run"], ["run", "walk"], ["walk", "idle"], ["run", "idle"]]:
			if not t.has(pair[0]) and t.has(pair[1]):
				t[pair[0]] = t[pair[1]]
			if not l.has(pair[0]) and l.has(pair[1]):
				l[pair[0]] = l[pair[1]]
		if not t.has("use") and t.has("attack"):
			t["use"] = _looped(t.attack, 6.0) # e.g. claws working at a node
		if not t.has("attack") and t.has("use"):
			var atk: Dictionary = t.use.duplicate()
			atk.loop = false
			atk.fps = 12.0
			t["attack"] = atk
		if not t.has("use"):
			t["use"] = t.idle
		if not t.has("attack"):
			t["attack"] = t.idle
		# pain may stay missing: AgentLayer flashes red instead.
		sets.append(c)
		total_weight += c.weight


## The body set for an agent id: stable across frames and runs, weighted by BodySets weight.
static func set_for(id: int) -> Dictionary:
	var h := _hash(id)
	var w := h % total_weight
	for s in sets:
		w -= s.weight
		if w < 0:
			return s
	return sets[0]


static func tint_for(id: int, s: Dictionary) -> Color:
	var tints: Array = s.tints
	return tints[(_hash(id) / 7) % tints.size()]


## Frame UV rect for anim at time t; returns the last frame once a one-shot has finished.
static func frame(anim: Dictionary, t: float, use_alt := false) -> Vector4:
	var uv: Array = anim.alt if use_alt and not anim.alt.is_empty() else anim.uv
	var i := int(t * anim.fps)
	return uv[i % uv.size()] if anim.loop else uv[mini(i, uv.size() - 1)]


static func finished(anim: Dictionary, t: float) -> bool:
	return not anim.loop and t * anim.fps >= anim.uv.size()


static func _compile(a: Dictionary, images: Dictionary, rows: Dictionary, size: Vector2, scale: float) -> Dictionary:
	var c := {"uv": _strip(a.sheet, images, rows, size), "fps": float(a.get("fps", 8)), "loop": bool(a.get("loop", true)),
		"px": float(images[a.sheet].get_height()) * scale, "alt": [], "stride": float(a.get("stride", 0.0))}
	if a.has("alt"):
		c.alt = _strip(a.alt, images, rows, size)
	return c


static func _strip(path: String, images: Dictionary, rows: Dictionary, size: Vector2) -> Array:
	var img: Image = images[path]
	var fs := img.get_height()
	var out := []
	for i in img.get_width() / fs:
		out.append(Vector4(i * fs / size.x, rows[path] / size.y, fs / size.x, fs / size.y))
	return out


static func _looped(a: Dictionary, fps: float) -> Dictionary:
	var c := a.duplicate()
	c.loop = true
	c.fps = fps
	return c


static func _aligned(h: int) -> int:
	return int(ceil(h / float(ALIGN))) * ALIGN


static func _hash(id: int) -> int:
	var x := (id * 2654435761) & 0x7fffffff
	x ^= x >> 13
	return (x * 1274126177) & 0x7fffffff
