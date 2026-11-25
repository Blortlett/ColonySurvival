extends CanvasLayer
## A groupmate's gear (Player Group Base Plan R2): Trade on a member of the player's own
## group opens this two-sided panel. Left: the player's armour, hotbar and pack. Right: the
## member's. Drag and drop moves anything either way (worn pieces and hotbar tools
## included); right click moves a whole stack across. Same slot boxes and look as the
## inventory UI (ui/InventoryUI.gd); every move is a request applied in the sim step
## (player/InvMoves.gd, places "minv" / "mworn" for the member).
## Closes when the member walks out of reach, dies or leaves the group (player/Station.gd).

const InvUI := preload("res://ui/InventoryUI.gd")
const InvMoves := preload("res://player/InvMoves.gd")

var player: PlayerController
var inv_ui: CanvasLayer # ui/InventoryUI.gd: item looks and tooltips

var _panel: PanelContainer
var _mine: Label
var _theirs: Label
var _boxes: Array = []
var _drag = null
var _ghost: Control
var _refresh := 0.0


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = InvUI.BG
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label(head, "Groupmate's gear   (drag to move, right click: whole stack across)", 13)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := Button.new()
	x.text = "x"
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(func(): player._use = -1)
	head.add_child(x)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 18)
	v.add_child(sides)
	_mine = _side(sides, InvMoves.WORN, InvMoves.INV)
	_theirs = _side(sides, InvMoves.M_WORN, InvMoves.M_INV)
	var hint := _label(v, "They may re-equip or craft with what they're given.  Walking away closes this.  E / Esc close.", 11)
	hint.modulate = Color(0.65, 0.65, 0.65)
	_ghost = Control.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.size = Vector2(InvUI.SLOT, InvUI.SLOT)
	_ghost.draw.connect(_draw_ghost)
	_ghost.visible = false
	add_child(_ghost)
	visible = false


## One side: a title, the armour row, the hotbar row and the 6 x 4 pack.
func _side(parent: Control, worn: String, inv: String) -> Label:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", InvUI.GAP)
	parent.add_child(v)
	var title := _label(v, "", 12)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	v.add_child(_grid(worn, 0, Items.ARMOR.size(), 6))
	_label(v, "Hotbar", 11).modulate = Color(0.7, 0.7, 0.7)
	v.add_child(_grid(inv, 0, Cfg.HOTBAR_SLOTS, 6))
	_label(v, "Pack", 11).modulate = Color(0.7, 0.7, 0.7)
	v.add_child(_grid(inv, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS - Cfg.HOTBAR_SLOTS, 6))
	return title


func _grid(place: String, first: int, count: int, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", InvUI.GAP)
	g.add_theme_constant_override("v_separation", InvUI.GAP)
	for i in count:
		var b = InvUI.SlotBox.new(self, place, first + i)
		_boxes.append(b)
		g.add_child(b)
	return g


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _process(dt: float) -> void:
	var st = player.station if player else null
	visible = st != null and st.is_member() and player.alive() and not player.watching
	if not visible:
		_drag = null
		_ghost.visible = false
		return
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.2
		var a := player.body
		var m: Agent = st.member
		_mine.text = "You   (armour -%d%%)" % int(round(a.armor_reduction() * 100))
		_theirs.text = "%s%s   (armour -%d%%)" % [m.short(), " (servant)" if m.is_servant() else "", int(round(m.armor_reduction() * 100))]
	if _drag != null and not _drag.is_visible_in_tree():
		_drag = null
	_ghost.visible = _drag != null
	if _drag:
		_ghost.position = _ghost.get_viewport().get_mouse_position() - Vector2(InvUI.SLOT, InvUI.SLOT) * 0.5
		_ghost.queue_redraw()
	for b in _boxes:
		b.queue_redraw()


# --- Slots (the SlotBox callbacks) ---

func entry_at(place: String, i: int):
	if player == null or player.body == null:
		return null
	var st = player.station
	match place:
		InvMoves.INV:
			return player.body.inv.entry(i)
		InvMoves.WORN:
			return player.body.worn.get(Items.ARMOR[i])
		InvMoves.M_INV:
			return st.member.inv.entry(i) if st.is_member() else null
		InvMoves.M_WORN:
			return st.member.worn.get(Items.ARMOR[i]) if st.is_member() else null
	return null


func describe(e) -> String:
	return inv_ui.describe(e) if inv_ui else ""


func draw_slot(b) -> void:
	if player == null or player.body == null:
		return
	var r := Rect2(Vector2.ZERO, b.size)
	b.draw_rect(r, InvUI.SLOT_BG)
	var held: bool = b.place == InvMoves.INV and b.index == player.held
	var hover: bool = b.get_global_rect().has_point(b.get_viewport().get_mouse_position())
	var edge := InvUI.HELD_EDGE if held else (InvUI.HOVER_EDGE if hover else InvUI.SLOT_EDGE)
	b.draw_rect(r, edge, false, 2.0 if held or hover else 1.0)
	var font := ThemeDB.fallback_font
	var e = entry_at(b.place, b.index)
	if e == null:
		if b.place == InvMoves.WORN or b.place == InvMoves.M_WORN:
			b.draw_string(font, Vector2(0, b.size.y * 0.5 + 4), InvUI.WORN_EMPTY[b.index], HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 11, Color(1, 1, 1, 0.3))
		return
	if inv_ui:
		inv_ui._draw_item(b, e, Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10)), 0.35 if _drag == b else 1.0)


func _draw_ghost() -> void:
	if _drag == null or inv_ui == null:
		return
	var e = entry_at(_drag.place, _drag.index)
	if e != null:
		inv_ui._draw_item(_ghost, e, Rect2(Vector2(5, 5), _ghost.size - Vector2(10, 10)), 0.9)


func start_drag(b) -> void:
	if entry_at(b.place, b.index) != null:
		_drag = b


func end_drag(at: Vector2) -> void:
	if _drag == null:
		return
	var src = _drag
	_drag = null
	for b in _boxes:
		if b != src and b.is_visible_in_tree() and b.get_global_rect().has_point(at):
			player.request_move(src.place, src.index, b.place, b.index)
			return


func quick(b) -> void:
	if entry_at(b.place, b.index) != null:
		player.request_quick(b.place, b.index)


## The slot box for (place, index), for the playtest.
func box(place: String, i: int) -> Control:
	for b in _boxes:
		if b.place == place and b.index == i:
			return b
	return null
