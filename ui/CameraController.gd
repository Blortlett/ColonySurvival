extends Camera2D
## Follows the controlled agent with a slight look-ahead towards the mouse (Player
## Controller Plan §6). In free camera mode (debug watch mode, or with no player):
## scroll to zoom toward the cursor, hold right mouse to pan.

const ZOOM_MIN := 0.08
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.15
const FOLLOW_RATE := 10.0 # higher = tighter follow

var player: PlayerController = null
var free_camera := true
var _panning := false
var _shake := 0.0


func _ready() -> void:
	position = Vector2(Cfg.MAP_W, Cfg.MAP_H) * Cfg.CELL * 0.5
	var vp := get_viewport_rect().size
	var fit: float = min(vp.x / (Cfg.MAP_W * Cfg.CELL), vp.y / (Cfg.MAP_H * Cfg.CELL))
	zoom = Vector2.ONE * clamp(fit, ZOOM_MIN, ZOOM_MAX)


## Start following the player (called when play begins).
func follow(p: PlayerController) -> void:
	player = p
	free_camera = false
	zoom = Vector2.ONE * Cfg.PLAYER_ZOOM
	if p.alive():
		position = p.body.pos * Cfg.CELL


## Visual-only screen shake hook (§3 feel).
func shake(px: float = Cfg.PLAYER_SHAKE) -> void:
	_shake = max(_shake, px)


func _following() -> bool:
	return not free_camera and player != null and player.alive()


func _process(dt: float) -> void:
	if _following():
		var target := player.body.pos * Cfg.CELL
		var mouse := get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
		var lean := mouse / zoom.x * Cfg.PLAYER_LOOK_AHEAD
		target += lean.limit_length(Cfg.PLAYER_LOOK_MAX * Cfg.CELL)
		position = position.lerp(target, 1.0 - exp(-FOLLOW_RATE * dt))
	if _shake > 0.0:
		offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, dt * 60.0)
	else:
		offset = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed and not _following()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		position -= event.relative / zoom.x


func _zoom_at(factor: float) -> void:
	if _following():
		zoom = Vector2.ONE * clamp(zoom.x * factor, 0.5, ZOOM_MAX) # zoom about the player
		return
	var off := get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	var world_under_mouse := position + off / zoom.x
	zoom = Vector2.ONE * clamp(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	position = world_under_mouse - off / zoom.x
