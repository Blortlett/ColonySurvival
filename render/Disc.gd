extends RefCounted
## Filled circles as one shared white disc texture, tinted per draw. draw_circle builds a
## polygon per call that doesn't batch; thousands of trees, bushes and agents made frames
## slow (Performance Plan B1). Mipmapped so small discs stay smooth when zoomed out; layers
## using it set TEXTURE_FILTER_LINEAR_WITH_MIPMAPS.

const SIZE := 64

static var _tex: ImageTexture = null


static func texture() -> ImageTexture:
	if _tex == null:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var r := SIZE * 0.5
		for y in SIZE:
			for x in SIZE:
				var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(r - d, 0.0, 1.0)))
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	return _tex


static func draw(ci: CanvasItem, centre: Vector2, radius: float, col: Color) -> void:
	ci.draw_texture_rect(texture(), Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, col)
