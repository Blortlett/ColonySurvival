extends Node2D
## Ground, trees, rocks and hemp. Only redrawn when nodes change.

const GRASS := Color(0.30, 0.42, 0.22)
const TREE := Color(0.08, 0.26, 0.10)
const ROCK := Color(0.52, 0.52, 0.55)
const HEMP := Color(0.72, 0.80, 0.35)


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
			ResourceNode.Type.ROCK:
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(s - 2, s - 2)), ROCK)
			ResourceNode.Type.HEMP:
				draw_circle(p + Vector2(s, s) * 0.5, s * 0.25, HEMP)
