extends CanvasLayer
## Death panel (Player Controller Plan §5a): shown while the controlled body is dead. The
## sim keeps running at 1x behind it, so the death animation plays on.
##   [T] take over the living member with the highest AUTH in your kingdom (or group),
##       showing who it is (name, role, distance) first. Hidden if nobody qualifies.
##   [N] start fresh as a new solo agent, leaving the kingdom behind.
## Always about "the controlled agent" (Summer Roadmap §2.5): it only reads the controller.

var player: PlayerController

var _panel: PanelContainer
var _title: Label
var _cause: Label
var _take: Button
var _who: Label
var _fresh: Button
var _candidate: Agent = null
var _refresh := 0.0


func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -230
	_panel.offset_right = 230
	_panel.offset_top = 70
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.02, 0.02, 0.85)
	sb.border_color = Color(0.6, 0.15, 0.1)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(14)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.text = "You died"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	box.add_child(_title)
	_cause = _label(box, 12, Color(0.8, 0.8, 0.8))
	_take = _button(box, "", _on_take)
	_who = _label(box, 12, Color(1, 0.9, 0.6))
	_fresh = _button(box, "Start fresh as a newcomer on your own [N]", _on_fresh)
	var note := _label(box, 11, Color(0.6, 0.6, 0.6))
	note.text = "A fresh start leaves your kingdom behind: it carries on under the AI."
	visible = false


func _label(parent: Control, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _process(dt: float) -> void:
	var want := player != null and player.dead()
	if want != visible:
		visible = want
		_refresh = 0.0
	if not visible:
		return
	_refresh -= dt
	if _refresh > 0.0:
		return
	_refresh = 0.25 # the candidate can die or move while the panel is open
	refresh()


## Re-reads who option A would pick (also called by the play test).
func refresh() -> void:
	_candidate = player.takeover_candidate()
	_cause.text = "%s %s." % [player.body.short(), player.death.get("cause", "died")]
	_take.visible = _candidate != null
	_who.visible = _candidate != null
	if _candidate:
		var d := World.dist(player.death.get("pos", _candidate.pos), _candidate.pos)
		_take.text = "Take over %s [T]" % _candidate.short()
		_who.text = "%s, %s, AUTH %d, %d cells away" % [_candidate.short(), player.role_of(_candidate), _candidate.stats.auth, int(round(d))]


func candidate() -> Agent:
	return _candidate


func _on_take() -> void:
	refresh()
	if _candidate and _candidate.alive:
		player.take_over(_candidate)


func _on_fresh() -> void:
	player.respawn()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_T:
			if _take.visible:
				_on_take()
			get_viewport().set_input_as_handled()
		KEY_N:
			_on_fresh()
			get_viewport().set_input_as_handled()
