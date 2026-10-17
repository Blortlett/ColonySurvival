extends Node2D
## Ground, trees, rocks and hemp. Only redrawn when nodes change.

# Darker, Songs of Syx-leaning palette (Phase E visual pass).
const GRASS := Color(0.23, 0.31, 0.17)
const TREE := Color(0.06, 0.18, 0.08)
const TREE_HI := Color(0.10, 0.25, 0.11)
const ROCK := Color(0.40, 0.40, 0.42)
const ROCK_HI := Color(0.50, 0.50, 0.52)
const HEMP := Color(0.58, 0.63, 0.30)


func _process(_dt: float) -> void:
	if World.static_dirty:
		World.static_dirty = false
		queue_redraw()


func _draw() -> void:
	var s := float(Cfg.CELL)
	draw_rect(Rect2(0, 0, Cfg.MAP_W * s, Cfg.MAP_H * s), GRASS)
	for n in World.nodes.values():
		var p := Vector2(n.cell) * s
		match n.type:
			ResourceNode.Type.TREE:
				draw_circle(p + Vector2(s, s) * 0.5, s * 0.48, TREE)
				draw_circle(p + Vector2(s * 0.42, s * 0.42), s * 0.22, TREE_HI)
			ResourceNode.Type.ROCK:
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(s - 2, s - 2)), ROCK)
				draw_rect(Rect2(p + Vector2(2, 2), Vector2(s * 0.45, s * 0.35)), ROCK_HI)
			ResourceNode.Type.HEMP:
				draw_circle(p + Vector2(s, s) * 0.5, s * 0.25, HEMP)
