extends Node2D
## Bushes, walls, doors, fires, loot bags, plus optional privilege-zone and blueprint overlays.

const BUSH := Color(0.15, 0.38, 0.15)
const BERRY := Color(0.85, 0.12, 0.25)
const WALL := Color(0.45, 0.29, 0.14)
const DOOR := Color(0.70, 0.50, 0.28)
const LOOT := Color(0.85, 0.75, 0.45)
const FLOOR := Color(0.50, 0.36, 0.22)
const FLOOR_LINE := Color(0.40, 0.28, 0.16)
const CHEST := Color(0.55, 0.33, 0.12)
const CHEST_BAND := Color(0.25, 0.15, 0.06)

var show_zones := true


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
		for h in World.all_houses():
			if h.state == House.State.PLANNED or h.state == House.State.BUILDING:
				var outer := h.footprint()
				draw_rect(Rect2(Vector2(outer.position) * s, Vector2(outer.size) * s), Color(1, 1, 1, 0.25), false, 1.0)
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
		var col := DOOR if w.is_door else WALL
		col = col.darkened(0.5 * (1.0 - w.hp / w.max_hp))
		draw_rect(Rect2(p, Vector2(s, s)), col)
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


func _draw_furniture(fu: Furniture, p: Vector2, s: float) -> void:
	match fu.kind:
		Furniture.Kind.CHEST:
			var r := Rect2(p + Vector2(s * 0.15, s * 0.25), Vector2(s * 0.7, s * 0.55))
			draw_rect(r, CHEST)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.35), Vector2(r.size.x, s * 0.1)), CHEST_BAND)
			if fu.tier > 0:
				draw_rect(r, Color(0.7, 0.7, 0.75), false, 1.5)
