extends RefCounted
## Packs every sheet named in BodySets into one mipmapped texture, so all agent sprites draw
## in one MultiMesh call, and compiles each set's animations into UV rects with fallbacks
## resolved (see BodySets.gd).
##
## Compiled anim: {"uv": Array[Vector4] (u, v, w, h per frame), "fps", "loop", "px" (frame
## size in world px), "alt": Array[Vector4] or [], "stride" (0 = fixed rate)}.
## Compiled set: {"name", "weight", "angle", "tints", "legs": {idle, walk, run}, "torso": {...},
## "items": {torso anim name -> anim drawn over it}, "outfits": {slot -> outfit -> {anim name ->
## anim}}}. Outfit anims play frame for frame with their body anim (legs slot: the legs anim,
## plus "death" with the torso death; torso / head slots: the torso anim), so they copy its
## fps, loop and stride, and a frame-count mismatch is an assert, as for items.
##
## Packing: sheets are shelf-packed into rows of a WIDTH px wide atlas (several strips side by
## side), each placed on a 16 px grid so mips don't bleed. ~200 48 px sheets fit in about
## 2048 x 1200.

const BodySets := preload("res://render/BodySets.gd")

const ALIGN := 16 # strips start on a 16 px grid so mip levels up to 4 don't bleed between them
const WIDTH := 2048 # atlas width (grows to the widest sheet if one is wider)

static var texture: ImageTexture = null
static var sets: Array = [] # compiled sets, in BodySets order
static var total_weight := 0


static func ensure() -> void:
	if texture != null:
		return
	# 1. Load every distinct sheet.
	var paths: Array[String] = []
	for s in BodySets.SETS.values():
		var anims := []
		for part in ["legs", "torso", "items"]:
			anims.append_array(s.get(part, {}).values())
		for slot in s.get("outfits", {}).values():
			for outfit in slot.values():
				anims.append_array(outfit.values())
		for anim in anims:
			for key in ["sheet", "alt"]:
				if anim.has(key) and not paths.has(anim[key]):
					paths.append(anim[key])
	var images := {}
	var width := WIDTH
	for p in paths:
		var tex: Texture2D = load(BodySets.DIR + p)
		assert(tex != null, "SpriteAtlas: can't load %s" % p)
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		images[p] = img
		width = maxi(width, _aligned(img.get_width()))
	# 2. Shelf packing: tallest first, then widest; strips side by side, a new shelf when full.
	var order := paths.duplicate()
	order.sort_custom(func(a, b):
		var ia: Image = images[a]
		var ib: Image = images[b]
		if ia.get_height() != ib.get_height():
			return ia.get_height() > ib.get_height()
		if ia.get_width() != ib.get_width():
			return ia.get_width() > ib.get_width()
		return a < b)
	var rows := {} # path -> Vector2i top-left
	var x := 0
	var y := 0
	var shelf := 0
	for p in order:
		var img: Image = images[p]
		var w := _aligned(img.get_width())
		if x + w > width:
			x = 0
			y += shelf
			shelf = 0
		rows[p] = Vector2i(x, y)
		x += w
		shelf = maxi(shelf, _aligned(img.get_height()))
	var height := y + shelf
	var atlas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for p in order:
		var img: Image = images[p]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), rows[p])
	atlas.generate_mipmaps()
	texture = ImageTexture.create_from_image(atlas)
	print("SpriteAtlas: %d sheets in %d x %d" % [paths.size(), width, height])
	# 3. Compile the sets.
	var size := Vector2(width, height)
	for set_name in BodySets.SETS:
		var s: Dictionary = BodySets.SETS[set_name]
		var c := {"name": set_name, "weight": int(s.get("weight", 1)), "angle": float(s.get("angle", 0.0)),
			"tints": s.get("tints", [Color.WHITE]), "legs": {}, "torso": {}, "items": {}, "outfits": {}}
		var scale: float = s.get("scale", 1.0)
		for part in ["legs", "torso", "items"]:
			for anim_name in s.get(part, {}):
				c[part][anim_name] = _compile(s[part][anim_name], images, rows, size, scale)
		var t: Dictionary = c.torso
		var l: Dictionary = c.legs
		# An item plays frame-for-frame with its torso animation: same rate, same looping.
		for anim_name in c.items:
			assert(t.has(anim_name), "BodySets %s: item %s has no torso animation" % [set_name, anim_name])
			var it: Dictionary = c.items[anim_name]
			assert(it.uv.size() == t[anim_name].uv.size(), "BodySets %s: item %s frame count differs from the torso" % [set_name, anim_name])
			it.fps = t[anim_name].fps
			it.loop = t[anim_name].loop
		# An outfit plays frame-for-frame with the body anim it was diffed against.
		var outfits: Dictionary = s.get("outfits", {})
		for slot in outfits:
			assert(slot in ["legs", "torso", "head"], "BodySets %s: unknown outfit slot %s" % [set_name, slot])
			c.outfits[slot] = {}
			for outfit_name in outfits[slot]:
				var oc := {}
				for anim_name in outfits[slot][outfit_name]:
					var body: Dictionary = l.get(anim_name, {}) if slot == "legs" and anim_name != "death" else t.get(anim_name, {})
					var what := "BodySets %s: %s outfit %s anim %s" % [set_name, slot, outfit_name, anim_name]
					assert(not body.is_empty(), what + " has no body animation")
					var o := _compile(outfits[slot][outfit_name][anim_name], images, rows, size, scale)
					assert(o.uv.size() == body.uv.size(), what + ": frame count differs from the body")
					assert(o.alt.size() == body.alt.size(), what + ": alt frame count differs from the body")
					o.fps = body.fps
					o.loop = body.loop
					o.stride = body.stride
					oc[anim_name] = o
				c.outfits[slot][outfit_name] = oc
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
		var at: Vector2i = rows[path]
		out.append(Vector4((at.x + i * fs) / size.x, at.y / size.y, fs / size.x, fs / size.y))
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
