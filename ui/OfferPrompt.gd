extends CanvasLayer
## The incoming social prompt (Player Social Plan §3.3): a small card at the top centre
## showing what the first queued offer asks, with clickable [F1] / [F2] buttons and a timer
## bar that runs down to the default answer. Obvious but not intrusive: the game never
## pauses, the card takes no keyboard focus, and movement keeps working.

const FADE_IN := 0.2 # real seconds
const BAR_H := 3.0
const GOLD := Color(1.0, 0.82, 0.3)

var player: PlayerController

var _panel: PanelContainer
var _text: RichTextLabel
var _yes: Button
var _no: Button
var _more: Label
var _bar: Control
var _shown_id := -1
var _shown_at := 0


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_top = 40
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.9)
	sb.border_color = Color(GOLD, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8 + BAR_H
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 14)
	_text.add_theme_font_size_override("bold_font_size", 14)
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_yes = _button(row, Color(0.35, 0.75, 0.4), func(): _answer(true))
	_no = _button(row, Color(0.8, 0.35, 0.3), func(): _answer(false))
	_more = Label.new()
	_more.add_theme_font_size_override("font_size", 11)
	_more.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_more)
	# The timer bar along the bottom edge, drawn over the panel's bottom margin.
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.draw.connect(_draw_bar)
	_panel.add_child(_bar)
	_panel.visible = false


func _button(row: HBoxContainer, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE # keys stay with the game
	b.custom_minimum_size = Vector2(110, 26)
	b.add_theme_font_size_override("font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col, 0.25)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	var hov := sb.duplicate()
	hov.bg_color = Color(col, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.pressed.connect(cb)
	row.add_child(b)
	return b


func _answer(yes: bool) -> void:
	if player:
		player.offers.answer(yes)


## The offer on screen, or {} (also used by the social overlay's "!" marker).
func shown() -> Dictionary:
	if player == null or not player.alive() or player.watching:
		return {}
	return player.offers.current()


func _process(_dt: float) -> void:
	var o := shown()
	_panel.visible = not o.is_empty()
	if o.is_empty():
		_shown_id = -1
		return
	if o.id != _shown_id:
		_shown_id = o.id
		_shown_at = Time.get_ticks_msec()
		var name: String = o.who.replace("[", "[lb]")
		_text.text = "[center][color=#%s][b]%s[/b][/color]%s[/center]" % [Color(o.color).to_html(false), name, String(o.text).replace("[", "[lb]")]
		_yes.text = "[F1] %s" % o.yes
		_no.text = "[F2] %s" % o.no
	var n: int = player.offers.queue.size() - 1
	_more.text = ("+%d more" % n) if n > 0 else ""
	_panel.modulate.a = clampf((Time.get_ticks_msec() - _shown_at) / (FADE_IN * 1000.0), 0.0, 1.0)
	_bar.queue_redraw()


func _draw_bar() -> void:
	var o := shown()
	if o.is_empty():
		return
	var t := clampf((o.expires - SimClock.time) / o.secs, 0.0, 1.0)
	# _bar sits inside the panel's content area: reach the panel's own bottom edge.
	var w := _panel.size.x
	var y := _panel.size.y - BAR_H - _bar.position.y - 2.0
	var x0 := -_bar.position.x + 2.0
	_bar.draw_rect(Rect2(x0, y, w - 4.0, BAR_H), Color(1, 1, 1, 0.12))
	_bar.draw_rect(Rect2(x0, y, (w - 4.0) * t, BAR_H), GOLD if t > 0.3 else Color(1.0, 0.45, 0.3))
