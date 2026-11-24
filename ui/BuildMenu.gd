extends CanvasLayer
## Build menu (Player Controller Plan §4, phase 4): replaces the old 1-4 build keys.
## B toggles it. It lists the pieces the player can place by hand (Actions.PIECES) with
## their costs; pieces you can't afford are greyed out. Click one (or press its number
## while the menu is open) to pick it, then LMB places it as before; RMB / X stop building.
## Picking a piece closes the menu. Nothing pauses.

var player: PlayerController

var _panel: PanelContainer
var _box: VBoxContainer
var _buttons := {} # piece -> Button
var _refresh := 0.0


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -340
	_panel.offset_right = -60
	_panel.offset_bottom = -190
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.92)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_panel.add_child(_box)
	var title := Label.new()
	title.text = "Build  [B]"
	title.add_theme_font_size_override("font_size", 15)
	_box.add_child(title)
	for i in Actions.PIECES.size():
		var piece: String = Actions.PIECES[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): pick(piece))
		_box.add_child(b)
		_buttons[piece] = b
	var hint := Label.new()
	hint.text = "Pick, then LMB places.  RMB / X stop building."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.65, 0.65, 0.65)
	_box.add_child(hint)
	visible = false


func can_open() -> bool:
	return player != null and player.alive() and not player.watching


func toggle() -> void:
	visible = not visible and can_open()
	if visible:
		_update()


## Pick a piece (refused, with a message, if you can't afford it). Closes the menu.
func pick(piece: String) -> bool:
	if not can_open():
		return false
	var cost: Dictionary = Items.BUILD_COSTS[piece]
	if not player.body.inv.has_cost(cost):
		player.say("Can't build a %s: needs %s." % [Items.label(piece), Actions.cost_text(cost)])
		return false
	player.build_piece = piece
	if player.station.open != null:
		player._use = -1 # building and a panel don't mix: close it
	visible = false
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k == KEY_B:
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and k == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
	elif visible and k >= KEY_1 and k < KEY_1 + Actions.PIECES.size() and not player.keys_blocked:
		pick(Actions.PIECES[k - KEY_1])
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if visible and not can_open():
		visible = false
	if not visible:
		return
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.15
		_update()


func _update() -> void:
	var a := player.body
	for i in Actions.PIECES.size():
		var piece: String = Actions.PIECES[i]
		var cost: Dictionary = Items.BUILD_COSTS[piece]
		var b: Button = _buttons[piece]
		b.text = "%d  %s   %s%s" % [i + 1, Items.label(piece).capitalize(), Actions.cost_text(cost), "   (picked)" if player.build_piece == piece else ""]
		b.disabled = not a.inv.has_cost(cost)
