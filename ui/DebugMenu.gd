extends CanvasLayer
## Debug menu (Player Controller Plan §6a): F1 toggles it, also in exported test builds.
## It holds what used to be observer controls: speed-up, pause, watch / free camera and the
## zone and label overlays. Watch mode hands the player's body to the AI and frees the
## camera; leaving it takes the body back. The player always runs at 1x, so speed-up only
## works while watching and resets to 1x on return.
## Shortcuts while the menu is open: Space pause, 1-5 speed, V watch, Z zones, L labels.

var player: PlayerController
var camera: Node # ui/CameraController.gd
var agent_layer: Node2D
var dynamic_layer: Node2D

var _panel: PanelContainer
var _state: Label
var _watch: Button
var _pause: Button
var _zones: Button
var _labels: Button
var _sprites: Button
var _speeds: Array[Button] = []


func _ready() -> void:
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(8, 36)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Debug (F1)"
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 12)
	box.add_child(_state)
	_watch = _button(box, "Watch / free camera [V]", _toggle_watch)
	_pause = _button(box, "Pause [Space]", func(): SimClock.toggle_pause())
	var row := HBoxContainer.new()
	box.add_child(row)
	for i in SimClock.SPEEDS.size():
		var sp: float = SimClock.SPEEDS[i]
		_speeds.append(_button(row, "%dx" % int(sp), func(): set_speed(i)))
	_zones = _button(box, "Zones [Z]", func(): dynamic_layer.show_zones = not dynamic_layer.show_zones)
	_labels = _button(box, "Labels [L]", func(): agent_layer.show_labels = not agent_layer.show_labels)
	_sprites = _button(box, "Agents [K]", func(): agent_layer.cycle_mode())
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.text = "Speed-up works in watch mode only:\nthe player always runs at 1x.\nIn watch mode: LMB inspect, RMB pan."
	box.add_child(hint)
	visible = false


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func toggle() -> void:
	visible = not visible
	if player:
		player.keys_blocked = visible


func watching() -> bool:
	return player == null or player.watching or not player.alive()


func set_speed(i: int) -> void:
	if not watching():
		SimClock.set_speed(1.0)
		if player:
			player.say("Speed-up only works in watch mode.")
		return
	SimClock.set_speed(SimClock.SPEEDS[i])


func _toggle_watch() -> void:
	if player == null or not player.alive():
		return
	player.set_watching(not player.watching)
	camera.free_camera = player.watching
	if not player.watching:
		SimClock.set_speed(1.0) # the player always runs at 1x (agreed)
		agent_layer.selected_id = -1


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F1:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	var handled := true
	match event.physical_keycode:
		KEY_SPACE: SimClock.toggle_pause()
		KEY_1: set_speed(0)
		KEY_2: set_speed(1)
		KEY_3: set_speed(2)
		KEY_4: set_speed(3)
		KEY_5: set_speed(4)
		KEY_V: _toggle_watch()
		KEY_Z: dynamic_layer.show_zones = not dynamic_layer.show_zones
		KEY_L: agent_layer.show_labels = not agent_layer.show_labels
		KEY_K: agent_layer.cycle_mode()
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if not visible:
		return
	_state.text = "%s  %s\nMode: %s" % [SimClock.time_string(), "PAUSED" if SimClock.paused else "x%d" % int(SimClock.speed),
		"watching (AI drives your body)" if player and player.watching else ("free camera" if watching() else "playing")]
	_watch.text = ("Back to playing [V]" if player and player.watching else "Watch / free camera [V]")
	_pause.text = "Resume [Space]" if SimClock.paused else "Pause [Space]"
	_zones.text = "Zones: %s [Z]" % ("on" if dynamic_layer.show_zones else "off")
	_labels.text = "Labels: %s [L]" % ("on" if agent_layer.show_labels else "off")
	_sprites.text = "Agents: %s [K]" % agent_layer.mode_name()
	for i in _speeds.size():
		_speeds[i].disabled = not watching()
		_speeds[i].modulate = Color(1, 0.85, 0.3) if SimClock.speed == SimClock.SPEEDS[i] else Color.WHITE
