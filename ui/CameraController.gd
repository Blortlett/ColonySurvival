extends Camera2D
## Scroll to zoom toward the cursor, hold right mouse to pan.

const ZOOM_MIN := 0.08
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.15

var _panning := false


func _ready() -> void:
	position = Vector2(Cfg.MAP_W, Cfg.MAP_H) * Cfg.CELL * 0.5
	var vp := get_viewport_rect().size
	var fit: float = min(vp.x / (Cfg.MAP_W * Cfg.CELL), vp.y / (Cfg.MAP_H * Cfg.CELL))
	zoom = Vector2.ONE * clamp(fit, ZOOM_MIN, ZOOM_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		position -= event.relative / zoom.x


func _zoom_at(factor: float) -> void:
	var offset := get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	var world_under_mouse := position + offset / zoom.x
	zoom = Vector2.ONE * clamp(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	position = world_under_mouse - offset / zoom.x
