extends Node2D
## Trees, rocks, hemp and berry bushes, in Cfg.CHUNK-cell chunks (render/Chunks.gd). Only
## redrawn when nodes (or berry counts) change, at most every REDRAW_SECS, and then only
## the chunks on screen.

const REDRAW_SECS := 0.25 # node changes redraw at most this often (B1)
## Top-down pines: a strip of PINE_VARIANTS 64 px sprites (tools/tilekit/pine_tree.py),
## drawn 2x2 cells, centred on the tree's cell so the canopy spills over its neighbours.
const PINES := preload("res://art/trees/pine.png")
const PINE_PX := 64.0
const PINE_VARIANTS := 4
const PINE_CELLS := 2.0
const PINE_SHADOW_OFFSET := Vector2(3, 4) # sprite px, down-right (light from the top-left)
## Stone and iron: one 64 px image per depletion stage, index = ResourceNode.stage() - 1
## (tools/tilekit/stone_node.py, iron_node.py). Hemp: one 42 px image (hemp_plant.py).
## All sprites are drawn at 1 sprite px = 1 px of a 32 px cell, centred on the node's cell.
const STONE: Array[Texture2D] = [
	preload("res://art/resources/stone_1.png"), preload("res://art/resources/stone_2.png"),
	preload("res://art/resources/stone_3.png"), preload("res://art/resources/stone_4.png"),
]
const IRON: Array[Texture2D] = [
	preload("res://art/resources/iron_1.png"), preload("res://art/resources/iron_2.png"),
	preload("res://art/resources/iron_3.png"), preload("res://art/resources/iron_4.png"),
]
const HEMP_TEX := preload("res://art/resources/hemp.png")
## Berry bushes: 42 px, index = berries shown, 0..4 (tools/tilekit/berry_bush.py).
const BUSH_TEX: Array[Texture2D] = [
	preload("res://art/resources/bush_0.png"), preload("res://art/resources/bush_1.png"),
	preload("res://art/resources/bush_2.png"), preload("res://art/resources/bush_3.png"),
	preload("res://art/resources/bush_4.png"),
]
const ART_CELL_PX := 32.0 # sprite px per cell
const SHADOW := Color(0, 0, 0, 0.35)
const LOW_SHADOW_OFFSET := Vector2(2, 3) # rocks and hemp sit lower than a pine's canopy

var _since := INF
var _chunks: Chunks
var _ci: CanvasItem # the chunk being drawn


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS # pixel-art sprites
	_chunks = Chunks.new(self, _draw_chunk)


func _process(dt: float) -> void:
	_since += dt
	if World.static_dirty and _since >= REDRAW_SECS:
		World.static_dirty = false
		_since = 0.0
		_chunks.mark_all()
	_chunks.update(Cfg.CELL * PINE_CELLS)


func _draw_chunk(ci: CanvasItem, chunk: Vector2i) -> void:
	var t := Time.get_ticks_usec()
	_ci = ci
	_draw_body(_chunk_nodes(chunk))
	World.prof_add("draw_static", t)


## The chunk's nodes, read from the World.node_buckets that overlap it.
func _chunk_nodes(chunk: Vector2i) -> Array:
	var out := []
	var lo := chunk * Cfg.CHUNK
	var hi := lo + Vector2i.ONE * (Cfg.CHUNK - 1)
	var exact := Cfg.CHUNK % World.NODE_BUCKET == 0 # whole buckets: no per-node check
	for b: Dictionary in World.node_buckets:
		for bx in range(lo.x / World.NODE_BUCKET, hi.x / World.NODE_BUCKET + 1):
			for by in range(lo.y / World.NODE_BUCKET, hi.y / World.NODE_BUCKET + 1):
				var arr = b.get(Vector2i(bx, by))
				if arr == null:
					continue
				if exact:
					out.append_array(arr)
					continue
				for n in arr:
					if Chunks.of(n.cell) == chunk:
						out.append(n)
	return out


func _draw_body(nodes: Array) -> void:
	var s := float(Cfg.CELL)
	var px: float = s / ART_CELL_PX # screen px per sprite px
	var size := Vector2.ONE * s * PINE_CELLS
	# All shadows first, so no sprite is darkened by a neighbour's shadow.
	for n in nodes:
		match n.type:
			ResourceNode.Type.TREE:
				_draw_pine(n.cell, s, size, PINE_SHADOW_OFFSET * px, SHADOW)
			_:
				_draw_sprite(_low_texture(n), n.cell, s, px, LOW_SHADOW_OFFSET * px, SHADOW)
	# Rocks, iron, hemp and bushes, then trees last so canopies sit over their neighbours.
	for n in nodes:
		if n.type != ResourceNode.Type.TREE:
			_draw_sprite(_low_texture(n), n.cell, s, px, Vector2.ZERO, Color.WHITE)
	for n in nodes:
		if n.type == ResourceNode.Type.TREE:
			_draw_pine(n.cell, s, size, Vector2.ZERO, Color.WHITE)


## The sprite for a non-tree node: stone and iron shrink as they're mined, bushes lose
## berries as they're picked (Cfg.BUSH_BERRIES spread over the 4 drawn; any left shows one).
func _low_texture(n: ResourceNode) -> Texture2D:
	match n.type:
		ResourceNode.Type.ROCK: return STONE[n.stage() - 1]
		ResourceNode.Type.METAL: return IRON[n.stage() - 1]
		ResourceNode.Type.BUSH:
			return BUSH_TEX[clampi(ceili(4.0 * n.amount / Cfg.BUSH_BERRIES), 0, 4)]
	return HEMP_TEX


## A whole texture at sprite scale, centred on cell c.
func _draw_sprite(tex: Texture2D, c: Vector2i, s: float, px: float, off: Vector2, tint: Color) -> void:
	var size := tex.get_size() * px
	var centre := (Vector2(c) + Vector2(0.5, 0.5)) * s
	_ci.draw_texture_rect(tex, Rect2(centre - size * 0.5 + off, size), false, tint)


func _draw_pine(c: Vector2i, s: float, size: Vector2, off: Vector2, tint: Color) -> void:
	var v := posmod(c.x * 73856093 ^ c.y * 19349663, PINE_VARIANTS)
	var src := Rect2(Vector2(v * PINE_PX, 0), Vector2.ONE * PINE_PX)
	var centre := (Vector2(c) + Vector2(0.5, 0.5)) * s
	_ci.draw_texture_rect_region(PINES, Rect2(centre - size * 0.5 + off, size), src, tint)
