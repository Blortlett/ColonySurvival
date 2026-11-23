extends Node2D
## Trees, rocks, hemp and berry bushes. Only redrawn when nodes (or berry counts)
## change, at most every REDRAW_SECS.

const Disc := preload("res://render/Disc.gd")
const REDRAW_SECS := 0.25 # node changes redraw at most this often (B1)

# Darker, Songs of Syx-leaning palette (Phase E visual pass).
const TREE := Color(0.06, 0.18, 0.08)
const TREE_HI := Color(0.10, 0.25, 0.11)
const ROCK := Color(0.40, 0.40, 0.42)
const ROCK_HI := Color(0.50, 0.50, 0.52)
const HEMP := Color(0.58, 0.63, 0.30)
const BUSH := Color(0.15, 0.38, 0.15)
const BERRY := Color(0.85, 0.12, 0.25)
const METAL_ROCK := Color(0.33, 0.31, 0.32)
const RUST := Color(0.78, 0.40, 0.14)

var _since := INF


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(dt: float) -> void:
	_since += dt
	if World.static_dirty and _since >= REDRAW_SECS:
		World.static_dirty = false
		_since = 0.0
		queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_usec()
	_draw_body()
	World.prof_add("draw_static", t)


func _draw_body() -> void:
	var s := float(Cfg.CELL)
	for n in World.nodes.values():
		var p := Vector2(n.cell) * s
		match n.type:
			ResourceNode.Type.TREE:
				Disc.draw(self, p + Vector2(s, s) * 0.5, s * 0.48, TREE)
				Disc.draw(self, p + Vector2(s * 0.42, s * 0.42), s * 0.22, TREE_HI)
			ResourceNode.Type.ROCK:
				draw_rect(Rect2(p + Vector2.ONE * Cfg.PX, Vector2(s - 2.0 * Cfg.PX, s - 2.0 * Cfg.PX)), ROCK)
				draw_rect(Rect2(p + Vector2.ONE * 2.0 * Cfg.PX, Vector2(s * 0.45, s * 0.35)), ROCK_HI)
			ResourceNode.Type.HEMP:
				Disc.draw(self, p + Vector2(s, s) * 0.5, s * 0.25, HEMP)
			ResourceNode.Type.METAL:
				# A rock with rust-orange flecks.
				draw_rect(Rect2(p + Vector2.ONE * Cfg.PX, Vector2(s - 2.0 * Cfg.PX, s - 2.0 * Cfg.PX)), METAL_ROCK)
				draw_rect(Rect2(p + Vector2.ONE * 2.0 * Cfg.PX, Vector2(s * 0.45, s * 0.35)), ROCK)
				for f in [Vector2(0.25, 0.65), Vector2(0.6, 0.3), Vector2(0.7, 0.7), Vector2(0.45, 0.5)]:
					draw_rect(Rect2(p + f * s, Vector2(s * 0.16, s * 0.16)), RUST)
	var half := Vector2(s, s) * 0.5
	for b in World.bushes:
		var p := Vector2(b.cell) * s
		Disc.draw(self, p + half, s * 0.42, BUSH)
		for i in b.amount:
			var ang := TAU * i / Cfg.BUSH_BERRIES
			Disc.draw(self, p + half + Vector2(cos(ang), sin(ang)) * s * 0.22, s * 0.09, BERRY)
