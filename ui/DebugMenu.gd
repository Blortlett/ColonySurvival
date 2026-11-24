extends CanvasLayer
## Debug menu (Player Controller Plan §6a): F3 toggles it (F1 / F2 answer social prompts), also in exported test builds.
## It holds what used to be observer controls: speed-up, pause, watch / free camera and the
## zone and label overlays. Watch mode hands the player's body to the AI and frees the
## camera; leaving it takes the body back. The player always runs at 1x, so speed-up only
## works while watching and resets to 1x on return.
## "Take control" moves the player to the agent selected in watch mode (LMB inspect), the
## same controller swap as a death takeover (§5a); handy for testing.
## Shortcuts while the menu is open: Space pause, 1-5 speed, V watch, C take control,
## Z zones, L labels, G the social feed's "witnessed nearby" tier.

var player: PlayerController
var camera: Node # ui/CameraController.gd
var agent_layer: Node2D
var dynamic_layer: Node2D
var feed: CanvasLayer # ui/SocialFeed.gd, null without a player

var _panel: PanelContainer
var _state: Label
var _watch: Button
var _control: Button
var _pause: Button
var _zones: Button
var _labels: Button
var _sprites: Button
var _nearby: Button
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
	title.text = "Debug (F3)"
	title.add_theme_font_size_override("font_size", 15)
	box.add_child(title)
	_state = Label.new()
	_state.add_theme_font_size_override("font_size", 12)
	box.add_child(_state)
	_watch = _button(box, "Watch / free camera [V]", _toggle_watch)
	_control = _button(box, "Take control of selected [C]", take_selected)
	_pause = _button(box, "Pause [Space]", func(): SimClock.toggle_pause())
	var row := HBoxContainer.new()
	box.add_child(row)
	for i in SimClock.SPEEDS.size():
		var sp: float = SimClock.SPEEDS[i]
		_speeds.append(_button(row, "%dx" % int(sp), func(): set_speed(i)))
	_zones = _button(box, "Zones [Z]", func(): dynamic_layer.show_zones = not dynamic_layer.show_zones)
	_labels = _button(box, "Labels [L]", func(): agent_layer.show_labels = not agent_layer.show_labels)
	_sprites = _button(box, "Agents [K]", func(): agent_layer.cycle_mode())
	_nearby = _button(box, "Feed: nearby [G]", _toggle_nearby)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.text = "Speed-up works in watch mode only:\nthe player always runs at 1x.\nIn watch mode: LMB inspect, RMB pan,\nC takes control of the selected agent.\nNumpad 1: debug kit (weapons, tools,\narrows, wood, stone)."
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


## Speed-up is allowed with no player or in watch mode. Not while dead: the sim runs at 1x
## behind the death panel (§5a).
func watching() -> bool:
	return player == null or player.watching


func set_speed(i: int) -> void:
	if not watching():
		SimClock.set_speed(1.0)
		if player:
			player.say("Speed-up only works in watch mode.")
		return
	SimClock.set_speed(SimClock.SPEEDS[i])


## Take control of the agent selected in watch mode (the controller swap of §5a): the camera,
## HUD and player layer follow the new body; watch mode and speed-up end.
func take_selected() -> void:
	if player == null:
		return
	var a: Agent = World.agents.get(agent_layer.selected_id)
	if a == null or not a.alive:
		player.say("Select an agent first (watch mode: LMB).")
		return
	if a == player.body and not player.watching:
		return
	player.take_over(a)
	camera.free_camera = false
	agent_layer.selected_id = -1


func _toggle_watch() -> void:
	if player == null or not player.alive():
		return
	player.set_watching(not player.watching)
	camera.free_camera = player.watching
	if not player.watching:
		SimClock.set_speed(1.0) # the player always runs at 1x (agreed)
		agent_layer.selected_id = -1


const KIT_TOOLS := ["spear", "club", "sword", "bow", "axe", "pickaxe", "pickaxe_t2"]
const KIT_STACKS := {"arrow": 60, "wood": 40, "stone": 40} # wood/stone: 2 full stacks each


## Numpad 1: every weapon and gathering tool, arrows, wood and stone into the player's pack.
## Says what didn't fit if the pack fills up.
func give_kit() -> void:
	if player == null or not player.alive():
		return
	var inv: Inventory = player.body.inv
	var missed: Array[String] = []
	for t in KIT_TOOLS:
		if not inv.add_tool(t):
			missed.append(t)
	for item in KIT_STACKS:
		var short: int = KIT_STACKS[item] - inv.add(item, KIT_STACKS[item])
		if short > 0:
			missed.append("%d %s" % [short, item])
	player.say("Debug kit added." if missed.is_empty() else "Debug kit: pack full, missed %s." % ", ".join(missed))


## Tier 3 of the social feed (witnessed nearby, grey) on or off.
func _toggle_nearby() -> void:
	if feed:
		feed.show_nearby = not feed.show_nearby


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F3:
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
		KEY_C: take_selected()
		KEY_Z: dynamic_layer.show_zones = not dynamic_layer.show_zones
		KEY_L: agent_layer.show_labels = not agent_layer.show_labels
		KEY_K: agent_layer.cycle_mode()
		KEY_G: _toggle_nearby()
		KEY_KP_1: give_kit()
		_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if not visible:
		return
	_state.text = "%s  %s\nMode: %s" % [SimClock.time_string(), "PAUSED" if SimClock.paused else "x%d" % int(SimClock.speed),
		"watching (AI drives your body)" if player and player.watching else ("free camera" if watching() else ("dead" if player.dead() else "playing"))]
	_watch.text = ("Back to playing [V]" if player and player.watching else "Watch / free camera [V]")
	var sel: Agent = World.agents.get(agent_layer.selected_id)
	_control.disabled = player == null or sel == null
	_control.text = ("Take control of %s [C]" % sel.short()) if sel else "Take control of selected [C]"
	_pause.text = "Resume [Space]" if SimClock.paused else "Pause [Space]"
	_zones.text = "Zones: %s [Z]" % ("on" if dynamic_layer.show_zones else "off")
	_labels.text = "Labels: %s [L]" % ("on" if agent_layer.show_labels else "off")
	_sprites.text = "Agents: %s [K]" % agent_layer.mode_name()
	_nearby.visible = feed != null
	if feed:
		_nearby.text = "Feed, witnessed nearby: %s [G]" % ("on" if feed.show_nearby else "off")
	for i in _speeds.size():
		_speeds[i].disabled = not watching()
		_speeds[i].modulate = Color(1, 0.85, 0.3) if SimClock.speed == SimClock.SPEEDS[i] else Color.WHITE
