extends Node2D
## Per-frame drawing: fires, the furnace glow, crate iron marks, raid outlines and
## loot bags. Zone overlays, roads, floors, walls, doors and furniture are cached in the
## PieceLayer child, drawn behind this layer; bushes are in StaticLayer.

const Disc := preload("res://render/Disc.gd")

const LOOT := Color(0.85, 0.75, 0.45)
const METAL := Color(0.62, 0.62, 0.66)
const GLOW := Color(1.0, 0.45, 0.08)
const PieceLayer := preload("res://render/PieceLayer.gd")
## House fires and wild campfires share one animated sprite: CAMPFIRE_FRAMES 32 px frames
## left to right, plus an unlit image for a fire out of wood (tools/tilekit/campfire.py).
const CAMPFIRE := preload("res://art/structures/campfire.png")
const CAMPFIRE_OUT := preload("res://art/structures/campfire_out.png")
const CAMPFIRE_FRAMES := 8
const CAMPFIRE_FPS := 10.0
const FIRE_GLOW_CELLS := 1.6 # radius of the warm light a burning fire throws on the ground

var show_zones := true # the Z toggle; zones draw only in debug mode
var debug := true # set by the debug menu (ui/DebugMenu.gd apply_view)
var pieces: Node2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS # pixel-art fire
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
	# Lit furnaces: a warm glow round them, and the animated flames over the unlit image.
	var furnace_frame := int(Time.get_ticks_msec() * 0.001 * 9.0)
	for fu in pieces.furnaces:
		if World.furniture.get(fu.cell) == fu and PieceLayer.furnace_lit(fu):
			var p := World.px(Vector2(fu.cell))
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006 + fu.cell.y)
			Disc.draw(self, p + half, s * 1.1, Color(GLOW, 0.10 * pulse))
			var f: int = (furnace_frame + fu.cell.x) % PieceLayer.FURNACE_FRAMES
			draw_texture_rect_region(PieceLayer.FURNACE_TEX, Rect2(p, Vector2(s, s)), Rect2(f * 32.0, 0, 32.0, 32.0))
	# Sawmills spin while their workshop runs (built, fire burning): draw the moving frame
	# over the still one PieceLayer cached.
	var saw_frame := int(Time.get_ticks_msec() * 0.001 * 12.0)
	for fu in pieces.sawmills:
		if World.furniture.get(fu.cell) == fu and fu.house != null and fu.house.operational():
			var f: int = (saw_frame + fu.cell.x) % PieceLayer.SAWMILL_FRAMES
			if f != 0:
				draw_texture_rect_region(PieceLayer.SAWMILL_TEX, Rect2(World.px(Vector2(fu.cell)), Vector2(s, s)), Rect2(f * 32.0, 0, 32.0, 32.0))
	for fu in pieces.crates:
		if World.furniture.get(fu.cell) == fu and fu.store.count("iron_bar") + fu.store.count("raw_iron") > 0:
			var p := World.px(Vector2(fu.cell))
			draw_rect(Rect2(p + Vector2(s * 0.35, s * 0.4), Vector2(s * 0.3, s * 0.2)), METAL)
	# Raids: the target house outlined in red, a line from the rally point.
	for r in Raids.active:
		var fp := r.target.footprint()
		var rect := Rect2(World.px(Vector2(fp.position)), Vector2(fp.size) * s).grow(3.0 * Cfg.PX)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		draw_rect(rect, Color(1, 0.15, 0.1, pulse), false, 3.0 * Cfg.PX)
		draw_dashed_line(World.px(World.center(r.rally)), World.px(World.center(r.target.fire_cell)), Color(1, 0.2, 0.1, 0.5), 2.0 * Cfg.PX, 8.0 * Cfg.PX)
	var now := Time.get_ticks_msec() * 0.001
	for f in World.fires.values():
		var p := World.px(Vector2(f.cell))
		var rect := Rect2(p, Vector2(s, s))
		if not f.burning():
			draw_texture_rect(CAMPFIRE_OUT, rect, false)
			continue
		# Warm light on the ground, flickering; each fire runs out of step with the others.
		var phase := posmod(f.cell.x * 7 + f.cell.y * 13, CAMPFIRE_FRAMES)
		var flick := 0.8 + 0.2 * sin(now * 9.0 + phase) * sin(now * 5.3 + phase * 0.7)
		Disc.draw(self, p + half, s * FIRE_GLOW_CELLS * (0.95 + 0.05 * flick), Color(GLOW, 0.10 * flick))
		Disc.draw(self, p + half, s * FIRE_GLOW_CELLS * 0.6, Color(GLOW, 0.10 * flick))
		var fr := (int(now * CAMPFIRE_FPS) + phase) % CAMPFIRE_FRAMES
		draw_texture_rect_region(CAMPFIRE, rect, Rect2(fr * 32.0, 0, 32.0, 32.0))
	for bag in World.loot.values():
		var p := World.px(Vector2(bag.cell))
		draw_rect(Rect2(p + Vector2(s * 0.3, s * 0.3), Vector2(s * 0.4, s * 0.4)), LOOT)
