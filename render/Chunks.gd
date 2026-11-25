class_name Chunks
extends RefCounted
## Splits a cached layer (StaticLayer, PieceLayer) into Cfg.CHUNK-cell square canvas items.
## - Godot skips off-screen chunks, so zoomed in only a few chunks are sent each frame.
## - A change only redraws the chunks on screen; the rest redraw when they come into view.
## - With Cfg.WRAP each chunk sits at its copy nearest the camera (World.px_shift), so the
##   map wraps with no duplicate drawing: draw code keeps drawing at canonical positions.

var items: Array[Node2D] = []
var _dirty: Array[bool] = []
var _n := Vector2i(Cfg.MAP_W / Cfg.CHUNK, Cfg.MAP_H / Cfg.CHUNK)


## draw_fn(ci: CanvasItem, chunk: Vector2i) draws one chunk's content onto ci.
func _init(owner: Node2D, draw_fn: Callable) -> void:
	for y in _n.y:
		for x in _n.x:
			var ci := Node2D.new()
			ci.name = "Chunk_%d_%d" % [x, y]
			ci.draw.connect(draw_fn.bind(ci, Vector2i(x, y)))
			owner.add_child(ci)
			items.append(ci)
			_dirty.append(true)


func count() -> Vector2i:
	return _n


## Chunk holding canonical cell c.
static func of(c: Vector2i) -> Vector2i:
	return Vector2i(c.x / Cfg.CHUNK, c.y / Cfg.CHUNK)


func index(chunk: Vector2i) -> int:
	return chunk.y * _n.x + chunk.x


func mark_all() -> void:
	_dirty.fill(true)


## Per frame: place each chunk at its copy nearest the camera, hide the off-screen ones and
## redraw the dirty ones on screen. `margin` (px) covers sprites spilling past a chunk edge.
func update(margin: float) -> void:
	var size := float(Cfg.CHUNK * Cfg.CELL)
	var view := World.view_rect
	var all_visible := view.size == Vector2.ZERO # no camera has reported yet
	for i in items.size():
		var ci := items[i]
		var origin := Vector2(i % _n.x, i / _n.x) * size
		var shift := World.px_shift(origin + Vector2(size, size) * 0.5)
		if ci.position != shift:
			ci.position = shift
		var on := all_visible or view.intersects(Rect2(origin + shift, Vector2(size, size)).grow(margin))
		if ci.visible != on:
			ci.visible = on
		if on and _dirty[i]:
			_dirty[i] = false
			ci.queue_redraw()
