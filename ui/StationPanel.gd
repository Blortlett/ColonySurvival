extends CanvasLayer
## Machine panels (Player Controller Plan §4, phase 4). Shows the player's open
## station (player/Station.gd) and turns button presses into requests; the sim step applies
## them through Actions. Nothing here changes the sim directly, and nothing pauses.
##
## Chests and crates are shown by the slot UI instead (ui/InventoryUI.gd).
## Machine (sawmill, stone cutter, furnace, anvil): process batches (1 or until the input
## runs out, with a progress bar) and craft the machine's recipes.
## Buttons have keys ("put:wood:all", "process:plank:1", "craft:pickaxe_t2") so the
## playtest can press them: see click().

var player: PlayerController

var _panel: PanelContainer
var _box: VBoxContainer
var _bar: ProgressBar
var _buttons := {} # key -> Button
var _sig := ""
var _refresh := 0.0


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -470
	_panel.offset_right = -12
	_panel.offset_top = 90
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.92)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_panel.add_child(_box)
	visible = false


func _station():
	return player.station if player else null


func _process(dt: float) -> void:
	var st = _station()
	visible = st != null and st.open != null and st.is_machine() and player.alive() and not player.watching
	if not visible:
		_sig = ""
		return
	if _bar and st.job != "":
		_bar.value = st.progress()
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.1
		refresh()


## Rebuild the rows if anything they show has changed.
func refresh() -> void:
	var st = _station()
	if st == null or st.open == null or player.body == null:
		return
	var a := player.body
	var sig := "%d|%s|%s|%s|%d" % [st.open.get_instance_id(), a.inv.summary(), st.open.store.summary(), st.job, st.left]
	if st.is_machine():
		sig += "|" + Actions.can_use_machine(a, st.open)
	if sig == _sig:
		return
	_sig = sig
	_buttons.clear()
	_bar = null
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if st.is_machine():
		_build_machine(a, st)


## Press a panel button by key, as a click would. Returns false if it's missing or greyed out.
func click(key: String) -> bool:
	_sig = ""
	refresh()
	var b: Button = _buttons.get(key)
	if b == null or b.disabled:
		return false
	b.pressed.emit()
	return true


func has_button(key: String, enabled := true) -> bool:
	_sig = ""
	refresh()
	var b: Button = _buttons.get(key)
	return b != null and (not enabled or not b.disabled)


# --- Machine ---

func _build_machine(a: Agent, st) -> void:
	var m: Furniture = st.open
	var h: House = m.house
	_header("%s  (%s)" % [m.label().capitalize(), h.label() if h else "?"])
	var why := Actions.can_use_machine(a, m)
	if why != "":
		_label(_box, "Can't work it: %s." % why, 12).modulate = Color(1, 0.5, 0.4)
	var menu := Actions.machine_menu(m.kind)
	if not menu.process.is_empty():
		_label(_box, "Process", 13).add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	for k in menu.process:
		var p: Dictionary = Items.PROCESS[k]
		var ok: bool = why == "" and a.inv.has_cost(p["in"])
		var row := _row(_box, "%s -> %d %s (%.0f s)   have %s" % [Actions.cost_text(p["in"]), p.out, Items.label(k), p.secs, _have(a, p["in"])])
		_button(row, "1", "process:%s:1" % k, func(): st.request_process(k, 1), ok)
		_button(row, "All", "process:%s:all" % k, func(): st.request_process(k, -1), ok)
	if st.job != "":
		var row := HBoxContainer.new()
		_box.add_child(row)
		var left: String = "until the input runs out" if st.left < 0 else "%d to go" % st.left
		var l := _label(row, "Making %s, %s" % [Items.label(st.job), left], 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(row, "Stop", "stop", func(): st.request_stop())
		_bar = ProgressBar.new()
		_bar.max_value = 1.0
		_bar.show_percentage = false
		_bar.custom_minimum_size.y = 8
		_bar.value = st.progress()
		_box.add_child(_bar)
	if not menu.craft.is_empty():
		_label(_box, "Craft", 13).add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	for k in menu.craft:
		var cost: Dictionary = Items.RECIPES[k]
		var row := _row(_box, "%s: %s   have %s" % [Items.label(k), Actions.cost_text(cost), _have(a, cost)])
		_button(row, "Craft", "craft:" + k, func(): st.request_craft(k), why == "" and a.inv.has_cost(cost))
	_label(_box, "Pack (%d/%d slots): %s" % [a.inv.used_slots(), a.capacity(), a.inv.summary()], 11).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint("Same recipes and times as everyone.  Walking away, or a hard hit, closes this.  E / Esc close.")


static func _have(a: Agent, cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d" % a.inv.count(k))
	return "/".join(parts)


# --- Widgets ---

func _header(text: String) -> void:
	var row := HBoxContainer.new()
	_box.add_child(row)
	var l := _label(row, text, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "x", "close", func(): player._use = -1)


func _hint(text: String) -> void:
	var l := _label(_box, text, 11)
	l.modulate = Color(0.65, 0.65, 0.65)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _row(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := _label(row, text, 12)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return row


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, key: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS # rows rebuild after a transfer; fire on press
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	_buttons[key] = b
	return b
