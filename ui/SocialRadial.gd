extends CanvasLayer
## The social radial menu (Player Social Plan §4), open while the player holds F over a
## character. It's centred on that character and shows Social.PLAYER_OPTIONS evenly round
## a circle, clockwise from the top, in list order. The option in the mouse's direction is highlighted; inside a small dead zone
## nothing is. Usable options set player.radial_sel (LMB confirms it in PlayerController);
## greyed ones show why they can't be used. The game keeps running and WASD still moves.

const RADIUS := 84.0 # px from the centre to an option bubble (at least; see radius_for)
const DEAD_ZONE := 24.0 # px: closer to the centre than this selects nothing (start)
const BUBBLE := Vector2(116, 26)
const GOLD := Color(1.0, 0.82, 0.3)

var player: PlayerController

var _canvas: Control
var _font: Font
var _options: Array = []
var _hi := -1 # highlighted option index, -1 for none
var radius := RADIUS # px, for the current option count


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)


func target() -> Agent:
	if player == null or player.radial_id == -1 or not player.alive():
		return null
	return World.agents.get(player.radial_id)


## Screen position of the menu's centre: the target, kept on screen.
func centre() -> Vector2:
	var t := target()
	if t == null:
		return Vector2.ZERO
	var p := _canvas.get_viewport().get_canvas_transform() * (t.pos * Cfg.CELL)
	var vr := _canvas.get_viewport().get_visible_rect().size
	var m := Vector2(radius + BUBBLE.x * 0.5 + 4.0, radius + BUBBLE.y)
	return p.clamp(m, vr - m)


## Smallest radius (from RADIUS up) at which `n` bubbles evenly round the circle don't overlap.
static func radius_for(n: int) -> float:
	var r := RADIUS
	while r < RADIUS * 3.0:
		var clear := true
		for i in n:
			var d := dir_of(i, n) * r - dir_of((i + 1) % n, n) * r
			if absf(d.x) < BUBBLE.x + 4.0 and absf(d.y) < BUBBLE.y + 4.0:
				clear = false
				break
		if clear:
			return r
		r += 2.0
	return r


## Direction from the centre to option `i` of `n` (0 straight up, clockwise).
static func dir_of(i: int, n: int) -> Vector2:
	return Vector2.from_angle(-PI / 2 + TAU * i / n)


## Screen position of option `i`'s bubble.
func option_pos(i: int) -> Vector2:
	return centre() + dir_of(i, maxi(_options.size(), 1)) * radius


## Which option index a screen point picks (-1 in the dead zone).
static func pick(c: Vector2, mouse: Vector2, n: int) -> int:
	var v := mouse - c
	if v.length() < DEAD_ZONE or n == 0:
		return -1
	var ang := atan2(v.x, -v.y) # 0 straight up, clockwise
	return posmod(roundi(ang / (TAU / n)), n)


func _process(_dt: float) -> void:
	var t := target()
	if t == null:
		_options = []
		_hi = -1
		_canvas.queue_redraw()
		return
	_options = Social.player_options(player.body, t)
	radius = radius_for(_options.size())
	_hi = pick(centre(), _canvas.get_viewport().get_mouse_position(), _options.size())
	var o: Dictionary = _options[_hi] if _hi != -1 else {}
	player.radial_sel = o.id if not o.is_empty() and o.why == "" else &""
	player.radial_why = o.why if not o.is_empty() else ""
	_canvas.queue_redraw()


func _draw_menu() -> void:
	var t := target()
	if t == null or _options.is_empty():
		return
	var c := centre()
	_canvas.draw_circle(c, radius + 22.0, Color(0.04, 0.04, 0.06, 0.35))
	_canvas.draw_arc(c, radius, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0)
	_canvas.draw_arc(c, DEAD_ZONE, 0, TAU, 24, Color(1, 1, 1, 0.25), 1.0)
	# The target's name in the middle.
	var name := t.short()
	var nw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_canvas.draw_string(_font, c + Vector2(-nw * 0.5, -DEAD_ZONE - 6.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var n := _options.size()
	for i in n:
		var o: Dictionary = _options[i]
		var p := c + dir_of(i, n) * radius
		var ok: bool = o.why == ""
		var hi := i == _hi
		var box := Rect2(p - BUBBLE * 0.5, BUBBLE)
		var bg := Color(0.08, 0.08, 0.11, 0.92)
		if hi:
			bg = Color(0.22, 0.18, 0.08, 0.95) if ok else Color(0.18, 0.08, 0.08, 0.95)
		_canvas.draw_rect(box, bg)
		_canvas.draw_rect(box, (GOLD if ok else Color(0.85, 0.4, 0.35)) if hi else Color(1, 1, 1, 0.2), false, 1.5 if hi else 1.0)
		var col := Color.WHITE if ok else Color(0.55, 0.55, 0.55)
		var label: String = o.label
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_canvas.draw_string(_font, p + Vector2(-lw * 0.5, 4.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# Pointer from the centre towards the highlighted option.
	if _hi != -1:
		var dir := dir_of(_hi, n)
		_canvas.draw_line(c + dir * DEAD_ZONE, c + dir * (radius - BUBBLE.y * 0.6), Color(GOLD, 0.6), 2.0)
		var why: String = _options[_hi].why
		if why != "":
			var ww := _font.get_string_size(why, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var at := c + Vector2(-ww * 0.5, radius + BUBBLE.y + 10.0)
			_canvas.draw_rect(Rect2(at + Vector2(-6, -13), Vector2(ww + 12, 18)), Color(0.05, 0.05, 0.08, 0.85))
			_canvas.draw_string(_font, at, why, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.5))
