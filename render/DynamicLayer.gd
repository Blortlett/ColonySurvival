extends Node2D
## Bushes, walls, doors, fires, loot bags, plus optional privilege-zone and blueprint overlays.

const BUSH := Color(0.15, 0.38, 0.15)
const BERRY := Color(0.85, 0.12, 0.25)
const WALL := Color(0.45, 0.29, 0.14)
const DOOR := Color(0.70, 0.50, 0.28)
const LOOT := Color(0.85, 0.75, 0.45)
const ROAD := Color(0.38, 0.35, 0.29)
const ROAD_DOT := Color(0.30, 0.27, 0.22)
const PAVED := Color(0.47, 0.46, 0.44)
const PAVED_LINE := Color(0.33, 0.32, 0.31)
const BOARD_POST := Color(0.35, 0.22, 0.10)
const BOARD_SIGN := Color(0.80, 0.70, 0.45)
const FLOOR := Color(0.50, 0.36, 0.22)
const FLOOR_LINE := Color(0.40, 0.28, 0.16)
const CHEST := Color(0.55, 0.33, 0.12)
const CHEST_BAND := Color(0.25, 0.15, 0.06)
const WALL_R := Color(0.33, 0.22, 0.12)
const DOOR_R := Color(0.52, 0.36, 0.20)
const METAL := Color(0.62, 0.62, 0.66)
const SAWMILL := Color(0.62, 0.48, 0.30)
const CUTTER := Color(0.45, 0.45, 0.50)

var show_zones := true
var _outline_version := -1
var _outline := {} # kingdom id -> PackedVector2Array of line segments


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var s := float(Cfg.CELL)
	var half := Vector2(s, s) * 0.5
	if show_zones:
		for f in World.house_fires:
			if not f.burning():
				continue
			var fac: Faction = World.factions.get(f.owner_id)
			var col: Color = fac.color if fac else Color.WHITE
			var r := Cfg.PRIVILEGE_RADIUS
			var rect := Rect2(Vector2(f.cell - Vector2i(r, r)) * s, Vector2(r * 2 + 1, r * 2 + 1) * s)
			draw_rect(rect, Color(col, 0.08))
			draw_rect(rect, Color(col, 0.35), false, 1.0)
		_draw_kingdom_outlines()
		for k in World.kingdoms.values():
			if k.has_city:
				for idx in k.plots:
					var r := Cities.plot_rect(k, idx)
					draw_rect(Rect2(Vector2(r.position) * s, Vector2(r.size) * s), Color(k.color, 0.18), false, 1.0)
		for h in World.all_houses():
			if h.state == House.State.PLANNED or h.state == House.State.BUILDING:
				var outer := h.footprint()
				draw_rect(Rect2(Vector2(outer.position) * s, Vector2(outer.size) * s), Color(1, 1, 1, 0.25), false, 1.0)
	for c in World.roads:
		var p := Vector2(c) * s
		if World.roads[c] >= 2:
			draw_rect(Rect2(p, Vector2(s, s)), PAVED)
			draw_line(p + Vector2(0, s * 0.5), p + Vector2(s, s * 0.5), PAVED_LINE, 1.0)
			var off: float = s * (0.25 if (c.y % 2) == 0 else 0.75)
			draw_line(p + Vector2(off, 0), p + Vector2(off, s * 0.5), PAVED_LINE, 1.0)
			draw_line(p + Vector2(s - off, s * 0.5), p + Vector2(s - off, s), PAVED_LINE, 1.0)
		else:
			draw_rect(Rect2(p, Vector2(s, s)), ROAD)
			var h: int = (c.x * 7 + c.y * 13) % 5
			draw_rect(Rect2(p + Vector2(s * (0.15 + h * 0.12), s * 0.3), Vector2(2, 2)), ROAD_DOT)
			draw_rect(Rect2(p + Vector2(s * (0.7 - h * 0.1), s * 0.7), Vector2(2, 2)), ROAD_DOT)
	for fl in World.floors.values():
		var p := Vector2(fl.cell) * s
		draw_rect(Rect2(p, Vector2(s, s)), FLOOR.darkened(0.4 * (1.0 - fl.hp / fl.max_hp)))
		draw_line(p + Vector2(0, s * 0.5), p + Vector2(s, s * 0.5), FLOOR_LINE, 1.0)
	for fu in World.furniture.values():
		_draw_furniture(fu, Vector2(fu.cell) * s, s)
	for b in World.bushes:
		var p := Vector2(b.cell) * s
		draw_circle(p + half, s * 0.42, BUSH)
		for i in b.amount:
			var ang := TAU * i / Cfg.BUSH_BERRIES
			draw_circle(p + half + Vector2(cos(ang), sin(ang)) * s * 0.22, s * 0.09, BERRY)
	for w in World.walls.values():
		var p := Vector2(w.cell) * s
		var col: Color
		if w.tier > 0:
			col = DOOR_R if w.is_door else WALL_R
		else:
			col = DOOR if w.is_door else WALL
		col = col.darkened(0.5 * (1.0 - w.hp / w.max_hp))
		draw_rect(Rect2(p, Vector2(s, s)), col)
		if w.tier > 0:
			# Plank seams, and iron bands on doors.
			draw_line(p + Vector2(s * 0.5, 0), p + Vector2(s * 0.5, s), col.darkened(0.35), 1.0)
			draw_rect(Rect2(p, Vector2(s, s)), METAL if w.is_door else col.darkened(0.3), false, 1.0)
		if w.is_door:
			var fac: Faction = World.factions.get(w.owner_id)
			if fac:
				draw_rect(Rect2(p + Vector2(s * 0.3, s * 0.3), Vector2(s * 0.4, s * 0.4)), fac.color)
	for f in World.fires.values():
		var p := Vector2(f.cell) * s
		if f.burning():
			var flick := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.01 + f.cell.x)
			var size := (0.8 if f.is_house else 0.55) * s * flick
			draw_rect(Rect2(p + half - Vector2(size, size) * 0.5, Vector2(size, size)), Color(1.0, 0.5, 0.1) if f.is_house else Color(1.0, 0.75, 0.2))
		else:
			draw_rect(Rect2(p + half - Vector2(s, s) * 0.3, Vector2(s, s) * 0.6), Color(0.2, 0.2, 0.2))
	for bag in World.loot.values():
		var p := Vector2(bag.cell) * s
		draw_rect(Rect2(p + Vector2(s * 0.3, s * 0.3), Vector2(s * 0.4, s * 0.4)), LOOT)


func _kingdom_of(fid: int) -> Kingdom:
	var f: Faction = World.factions.get(fid)
	return f.kingdom if f else null


## Outline of each kingdom's merged territory, rebuilt only when the zones change.
func _draw_kingdom_outlines() -> void:
	World.privilege_owner(Vector2i.ZERO) # rebuild zones if dirty
	if _outline_version != World.zone_version:
		_outline_version = World.zone_version
		_build_outlines()
	for kid in _outline:
		var k: Kingdom = World.kingdoms.get(kid)
		if k:
			draw_multiline(_outline[kid], k.color, 2.0)


func _build_outlines() -> void:
	_outline.clear()
	if World.kingdoms.is_empty():
		return
	var s := float(Cfg.CELL)
	var w := Cfg.MAP_W
	var kmap := PackedInt32Array()
	kmap.resize(w * Cfg.MAP_H)
	for i in kmap.size():
		var owner := World.zone_map[i]
		if owner != 0:
			var f: Faction = World.factions.get(owner)
			if f and f.kingdom:
				kmap[i] = f.kingdom.id
	for y in Cfg.MAP_H:
		for x in w:
			var k := kmap[y * w + x]
			if k == 0:
				continue
			if not _outline.has(k):
				_outline[k] = PackedVector2Array()
			var seg: PackedVector2Array = _outline[k]
			var p := Vector2(x, y) * s
			if x == 0 or kmap[y * w + x - 1] != k:
				seg.append_array([p, p + Vector2(0, s)])
			if x == w - 1 or kmap[y * w + x + 1] != k:
				seg.append_array([p + Vector2(s, 0), p + Vector2(s, s)])
			if y == 0 or kmap[(y - 1) * w + x] != k:
				seg.append_array([p, p + Vector2(s, 0)])
			if y == Cfg.MAP_H - 1 or kmap[(y + 1) * w + x] != k:
				seg.append_array([p + Vector2(0, s), p + Vector2(s, s)])
			_outline[k] = seg


func _draw_furniture(fu: Furniture, p: Vector2, s: float) -> void:
	match fu.kind:
		Furniture.Kind.CHEST:
			var r := Rect2(p + Vector2(s * 0.15, s * 0.25), Vector2(s * 0.7, s * 0.55))
			draw_rect(r, CHEST)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.35), Vector2(r.size.x, s * 0.1)), CHEST_BAND)
			if fu.tier > 0:
				draw_rect(r, METAL, false, 1.5)
		Furniture.Kind.BOARD:
			draw_rect(Rect2(p + Vector2(s * 0.45, s * 0.35), Vector2(s * 0.1, s * 0.6)), BOARD_POST)
			draw_rect(Rect2(p + Vector2(s * 0.1, s * 0.05), Vector2(s * 0.8, s * 0.45)), BOARD_SIGN)
			var k := _kingdom_of(fu.owner_id)
			if k:
				draw_rect(Rect2(p + Vector2(s * 0.1, s * 0.05), Vector2(s * 0.8, s * 0.45)), k.color, false, 1.5)
		Furniture.Kind.SAWMILL:
			draw_rect(Rect2(p + Vector2(s * 0.1, s * 0.3), Vector2(s * 0.8, s * 0.4)), SAWMILL)
			draw_circle(p + Vector2(s * 0.5, s * 0.5), s * 0.28, METAL)
			draw_circle(p + Vector2(s * 0.5, s * 0.5), s * 0.08, SAWMILL.darkened(0.4))
		Furniture.Kind.CUTTER:
			draw_rect(Rect2(p + Vector2(s * 0.12, s * 0.12), Vector2(s * 0.76, s * 0.76)), CUTTER)
			draw_rect(Rect2(p + Vector2(s * 0.12, s * 0.45), Vector2(s * 0.76, s * 0.1)), CUTTER.darkened(0.5))
