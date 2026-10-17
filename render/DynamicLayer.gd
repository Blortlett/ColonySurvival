extends Node2D
## Per-frame drawing: fires, the furnace glow, crate iron marks, raid outlines and
## loot bags. Zone overlays, roads, floors, walls, doors and furniture are cached in the
## PieceLayer child, drawn behind this layer; bushes are in StaticLayer.

const Disc := preload("res://render/Disc.gd")

const LOOT := Color(0.85, 0.75, 0.45)
const METAL := Color(0.62, 0.62, 0.66)
const GLOW := Color(1.0, 0.45, 0.08)
const PieceLayer := preload("res://render/PieceLayer.gd")

var show_zones := true
var pieces: Node2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pieces = PieceLayer.new()
	add_child(pieces)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_usec()
	_draw_body()
	World.prof_add("draw_dynamic", t)


func _draw_body() -> void:
	var s := float(Cfg.CELL)
	var half := Vector2(s, s) * 0.5
	for fu in pieces.furnaces:
		if World.furniture.get(fu.cell) == fu and PieceLayer.furnace_lit(fu):
			var p := Vector2(fu.cell) * s
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006 + fu.cell.y)
			draw_rect(Rect2(p + Vector2(s * 0.25, s * 0.45), Vector2(s * 0.5, s * 0.35)), Color(GLOW, pulse))
			Disc.draw(self, p + Vector2(s * 0.5, s * 0.62), s * 0.32, Color(GLOW, 0.18 * pulse))
	for fu in pieces.crates:
		if World.furniture.get(fu.cell) == fu and fu.store.count("iron_bar") + fu.store.count("raw_iron") > 0:
			var p := Vector2(fu.cell) * s
			draw_rect(Rect2(p + Vector2(s * 0.35, s * 0.4), Vector2(s * 0.3, s * 0.2)), METAL)
	# Raids: the target house outlined in red, a line from the rally point.
	for r in Raids.active:
		var fp := r.target.footprint()
		var rect := Rect2(Vector2(fp.position) * s, Vector2(fp.size) * s).grow(3)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		draw_rect(rect, Color(1, 0.15, 0.1, pulse), false, 3.0)
		draw_dashed_line(World.center(r.rally) * s, World.center(r.target.fire_cell) * s, Color(1, 0.2, 0.1, 0.5), 2.0, 8.0)
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
