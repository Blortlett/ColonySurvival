extends Node2D
## The grass ground: one rect over the whole map, textured by render/ground.gdshader.
## Drawn once; the grid size (Cfg.CELL) and the grass tile size are independent.

const ATLAS := preload("res://art/ground/grass_atlas.png") # 5 variants of 80x80, left to right
const SHADER := preload("res://render/ground.gdshader")
const PATCH_PX := 1400.0 # brightness patch size (ground.gdshader patch_px default)
const TILE_PX := 80.0
# Variant weights, in atlas order: plain, lush, clumps, flowers, dry.
const WEIGHTS := [5.0, 3.0, 3.0, 1.0, 1.0]


func _ready() -> void:
	var total := 0.0
	for w in WEIGHTS:
		total += w
	var cum := PackedFloat32Array()
	var run := 0.0
	for w in WEIGHTS:
		run += w
		cum.append(run / total)
	while cum.size() < 8:
		cum.append(1.0)

	var noise := FastNoiseLite.new()
	noise.seed = Cfg.SEED
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var patch := NoiseTexture2D.new()
	patch.width = 256
	patch.height = 256
	patch.seamless = true
	patch.noise = noise

	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("atlas", ATLAS)
	mat.set_shader_parameter("variants", WEIGHTS.size())
	mat.set_shader_parameter("tile_px", TILE_PX)
	mat.set_shader_parameter("cum", cum)
	mat.set_shader_parameter("patch_noise", patch)
	if Cfg.WRAP:
		# The shader wraps tile picks at the map size, and the brightness patches repeat a
		# whole number of times across it, so the ground has no seam.
		var map := Vector2(Cfg.MAP_W, Cfg.MAP_H) * Cfg.CELL
		mat.set_shader_parameter("map_px", map)
		mat.set_shader_parameter("patch_px", map.x / maxf(1.0, roundf(map.x / PATCH_PX)))
	material = mat


var _drawn := Rect2()


## With WRAP the ground is one quad over the camera's view (it can be anywhere on the
## endless plane), redrawn when the view leaves the last quad.
func _process(_dt: float) -> void:
	if Cfg.WRAP and not _drawn.encloses(World.view_rect):
		queue_redraw()


func _draw() -> void:
	if not Cfg.WRAP:
		draw_rect(Rect2(0, 0, Cfg.MAP_W * Cfg.CELL, Cfg.MAP_H * Cfg.CELL), Color.WHITE)
		return
	_drawn = World.view_rect.grow(maxf(World.view_rect.size.x, World.view_rect.size.y) * 0.5)
	draw_rect(_drawn, Color.WHITE)
