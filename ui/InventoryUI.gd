extends CanvasLayer
## The player's slot UI (agreed with the user 2026-11-24):
## - Hotbar: 6 slots, bottom centre, always shown. 1-6 pick the slot in hand (highlighted).
## - Pack: 6 x 4 slots just above the hotbar, shown while the inventory is open (Tab).
## - Equipment: the armour slots plus the body's stats (STR, AGI, kills...), on the left,
##   shown with the inventory.
## - Chest: the open chest's slots on the right, only while a chest is open. Opening a chest
##   opens the inventory too.
## Drag and drop moves items between any of these; right click moves a whole stack across
## (pack <-> chest; with no chest, pack <-> hotbar; armour on / off). Everything is a
## request to the controller, applied in the sim step (player/InvMoves.gd).
## Always about "the controlled agent" (Summer Roadmap §2.5).

const InvMoves := preload("res://player/InvMoves.gd")

const SLOT := 46.0
const GAP := 4
const MARGIN := 8
const CHEST_ROWS_MAX := 8 # taller chests (the capital's has no limit) scroll

const BG := Color(0.06, 0.06, 0.09, 0.88)
const SLOT_BG := Color(0.16, 0.16, 0.2, 0.95)
const SLOT_EDGE := Color(0.32, 0.32, 0.38)
const HELD_EDGE := Color(1.0, 0.85, 0.35)
const HOVER_EDGE := Color(0.8, 0.85, 1.0)

## Placeholder item looks until there is item art: a colour and a short name.
const LOOK := {
	"wood": [Color(0.55, 0.36, 0.2), "Wood"], "stone": [Color(0.55, 0.55, 0.58), "Stone"],
	"hemp": [Color(0.55, 0.65, 0.25), "Hemp"], "berry": [Color(0.75, 0.15, 0.25), "Berry"],
	"arrow": [Color(0.7, 0.6, 0.4), "Arrow"], "plank": [Color(0.75, 0.55, 0.3), "Plank"],
	"handle": [Color(0.6, 0.45, 0.25), "Handle"], "cut_stone": [Color(0.7, 0.7, 0.72), "Block"],
	"raw_iron": [Color(0.55, 0.35, 0.28), "Ore"], "iron_bar": [Color(0.6, 0.65, 0.72), "Bar"],
	"metal_door": [Color(0.4, 0.42, 0.48), "Door"],
	"axe": [Color(0.45, 0.5, 0.6), "Axe"], "pickaxe": [Color(0.45, 0.5, 0.6), "Pick"],
	"pickaxe_t2": [Color(0.55, 0.62, 0.75), "Pick II"], "spear": [Color(0.55, 0.45, 0.35), "Spear"],
	"club": [Color(0.5, 0.35, 0.22), "Club"], "bow": [Color(0.6, 0.45, 0.25), "Bow"],
	"sword": [Color(0.7, 0.75, 0.85), "Sword"], "raiding_axe": [Color(0.6, 0.35, 0.3), "R.Axe"],
	"iron_raiding_axe": [Color(0.7, 0.45, 0.4), "IR.Axe"], "helmet": [Color(0.5, 0.55, 0.65), "Helm"],
	"chest_armor": [Color(0.5, 0.55, 0.65), "Chest"], "leg_armor": [Color(0.5, 0.55, 0.65), "Legs"],
	"tunic": [Color(0.82, 0.78, 0.66), "Tunic"], "trousers": [Color(0.72, 0.66, 0.54), "Pants"],
	"hood": [Color(0.72, 0.66, 0.54), "Hood"],
}
const WORN_EMPTY := ["Head", "Body", "Legs"] # shown in empty armour slots, Items.ARMOR order


## One slot on screen. Draws whatever is in (place, index) and reports clicks to the UI.
class SlotBox extends Control:
	var ui
	var place := ""
	var index := 0

	func _init(u, p: String, i: int) -> void:
		ui = u
		place = p
		index = i
		custom_minimum_size = Vector2(SLOT, SLOT)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					ui.start_drag(self)
				else:
					ui.end_drag(event.global_position)
				accept_event()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				ui.quick(self)
				accept_event()

	func _get_tooltip(_at: Vector2) -> String:
		return ui.describe(ui.entry_at(place, index))

	func _draw() -> void:
		ui.draw_slot(self)


var player: PlayerController

var _hotbar: PanelContainer
var _pack: PanelContainer
var _equip: PanelContainer
var _chest: PanelContainer
var _chest_title: Label
var _chest_grid: GridContainer
var _chest_scroll: ScrollContainer
var _chest_sig := ""
var _stats: Label
var _craft: PanelContainer
var _craft_buttons := {} # recipe -> Button
var _ghost: Control
var _boxes: Array = [] # every SlotBox, for drop targets and redraws
var _drag: SlotBox = null
var _refresh := 0.0


func _ready() -> void:
	layer = 5
	_hotbar = _panel_at(Vector2(0.5, 1.0), Vector2(0, -MARGIN), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_hotbar.add_child(_grid(InvMoves.INV, 0, Cfg.HOTBAR_SLOTS, Cfg.HOTBAR_SLOTS))

	_pack = _panel_at(Vector2(0.5, 1.0), Vector2(0, -(MARGIN * 3 + SLOT + 12)), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	var pv := _vbox(_pack)
	_title(pv, "Pack   (drag to move, right click: whole stack across)")
	pv.add_child(_grid(InvMoves.INV, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS - Cfg.HOTBAR_SLOTS, 6))

	# Hand crafting, right of the pack: the recipes anyone can make anywhere (axe, pickaxe,
	# spear, club, bow, arrows), instantly from the pack, as the AI does.
	_craft = _panel_at(Vector2(0.5, 1.0), Vector2(6 * SLOT / 2 + 3 * GAP + 18, -(MARGIN * 3 + SLOT + 12)), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	var crv := _vbox(_craft)
	_title(crv, "Craft")
	for k in PlayerController.hand_recipes():
		var item: String = k
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func(): player.request_craft(item))
		crv.add_child(b)
		_craft_buttons[item] = b

	_equip = _panel_at(Vector2(0.0, 0.0), Vector2(MARGIN + 2, 40), Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_END)
	var ev := _vbox(_equip)
	_title(ev, "Equipment")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	ev.add_child(row)
	for i in Items.ARMOR.size():
		var b := SlotBox.new(self, InvMoves.WORN, i)
		_boxes.append(b)
		row.add_child(b)
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 12)
	_stats.custom_minimum_size.x = 230
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(_stats)

	_chest = _panel_at(Vector2(1.0, 0.5), Vector2(-MARGIN - 2, 0), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BOTH)
	var cv := _vbox(_chest)
	_chest_title = _title(cv, "Chest")
	_chest_scroll = ScrollContainer.new()
	_chest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cv.add_child(_chest_scroll)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 6
	_chest_grid.add_theme_constant_override("h_separation", GAP)
	_chest_grid.add_theme_constant_override("v_separation", GAP)
	_chest_scroll.add_child(_chest_grid)
	var buttons := HBoxContainer.new()
	cv.add_child(buttons)
	_button(buttons, "Take all", func(): player.request_take_all())
	_button(buttons, "Put pack in", func(): player.request_put_all())

	_ghost = Control.new()
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.size = Vector2(SLOT, SLOT)
	_ghost.draw.connect(_draw_ghost)
	_ghost.visible = false
	add_child(_ghost)
	visible = false # until _process sees a player


# --- Building ---

func _panel_at(anchor: Vector2, offset: Vector2, grow_h: int, grow_v: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = anchor.x
	p.anchor_right = anchor.x
	p.anchor_top = anchor.y
	p.anchor_bottom = anchor.y
	p.offset_left = offset.x
	p.offset_right = offset.x
	p.offset_top = offset.y
	p.offset_bottom = offset.y
	p.grow_horizontal = grow_h
	p.grow_vertical = grow_v
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_content_margin_all(6)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	add_child(p)
	return p


func _vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	parent.add_child(v)
	return v


func _title(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	parent.add_child(l)
	return l


func _grid(place: String, first: int, count: int, cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", GAP)
	g.add_theme_constant_override("v_separation", GAP)
	for i in count:
		var b := SlotBox.new(self, place, first + i)
		_boxes.append(b)
		g.add_child(b)
	return g


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)


## Size the chest grid to the open chest: its slot count (the capital's unlimited chest shows
## what it holds plus a free row), scrolling past CHEST_ROWS_MAX rows.
func _fit_chest(ch: Furniture) -> void:
	var inv := ch.store
	var n := ch.slots()
	if n > Inventory.PREFILL_MAX:
		var last := -1
		for i in inv.slots.size():
			if inv.slots[i] != null:
				last = i
		n = (int((last + 1) / 6.0) + 2) * 6
	var sig := "%d|%d" % [ch.get_instance_id(), n]
	if sig == _chest_sig:
		return
	_chest_sig = sig
	for c in _chest_grid.get_children():
		_boxes.erase(c)
		_chest_grid.remove_child(c)
		c.queue_free()
	for i in n:
		var b := SlotBox.new(self, InvMoves.CHEST, i)
		_boxes.append(b)
		_chest_grid.add_child(b)
	var rows := ceili(n / 6.0)
	_chest_scroll.custom_minimum_size = Vector2(6 * SLOT + 5 * GAP + 12, mini(rows, CHEST_ROWS_MAX) * (SLOT + GAP))


# --- Per frame ---

func _process(dt: float) -> void:
	var t := Time.get_ticks_usec()
	var on := player != null and player.alive() and not player.watching
	visible = on
	if not on:
		_drag = null
		_ghost.visible = false
		World.prof_add("hud", t)
		return
	var st = player.station
	var chest_open: bool = st.is_chest()
	_pack.visible = player.inv_open
	_equip.visible = player.inv_open
	_craft.visible = player.inv_open
	_chest.visible = chest_open
	if chest_open:
		_fit_chest(st.open)
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.2
		_stats.text = _stats_text()
		if _craft.visible:
			_update_craft()
		if chest_open:
			var ch: Furniture = st.open
			var cap := "no limit" if ch.slots() > Inventory.PREFILL_MAX else "%d/%d slots" % [ch.store.used_slots(), ch.slots()]
			_chest_title.text = "%s   (%s)" % [ch.label().capitalize(), cap]
	if _drag != null and not _drag.is_visible_in_tree():
		_drag = null
	_ghost.visible = _drag != null
	if _drag:
		_ghost.position = _ghost.get_viewport().get_mouse_position() - Vector2(SLOT, SLOT) * 0.5
		_ghost.queue_redraw()
	for b in _boxes:
		if b.is_visible_in_tree():
			b.queue_redraw()
	World.prof_add("hud", t)


func _update_craft() -> void:
	var a := player.body
	for k in _craft_buttons:
		var b: Button = _craft_buttons[k]
		var cost: Dictionary = Items.RECIPES[k]
		var name := ("%d arrows" % Items.ARROWS_PER_CRAFT) if k == "arrow" else Items.label(k).capitalize()
		b.text = "%s   %s" % [name, Actions.cost_text(cost)]
		b.disabled = not a.inv.has_cost(cost)


## The top edge (screen y) of the bottom-centre UI, so the HUD can put its text above it.
func top_y() -> float:
	var p: Control = _pack if _pack.visible and visible else _hotbar
	return p.get_global_rect().position.y


func _stats_text() -> String:
	var a := player.body
	var lines: Array[String] = []
	lines.append("On your own" if a.faction.solo else a.faction.display_name())
	lines.append("STR %d   AGI %d   CHA %d   AUTH %d" % [a.stats.str, a.stats.agi, a.stats.cha, a.stats.auth])
	lines.append("Kills %d" % a.kills)
	lines.append("Armour: -%d%% damage taken" % int(round(a.armor_reduction() * 100)))
	lines.append("In hand: %s" % describe(player.held_entry()) if player.held_entry() != null else "In hand: nothing (punch)")
	lines.append("Slots used %d/%d" % [a.inv.used_slots(), a.capacity()])
	return "\n".join(lines)


# --- Slots ---

func entry_at(place: String, i: int):
	if player == null or player.body == null:
		return null
	match place:
		InvMoves.INV:
			return player.body.inv.entry(i)
		InvMoves.CHEST:
			var st = player.station
			return st.open.store.entry(i) if st.is_chest() else null
		InvMoves.WORN:
			return player.body.worn.get(Items.ARMOR[i])
	return null


func describe(e) -> String:
	if e == null:
		return ""
	if Inventory.is_tool_entry(e):
		return "%s (%d/%d)" % [Items.label(e.type).capitalize(), e.dur, Items.DURABILITY.get(e.type, e.dur)]
	return "%s x%d" % [Items.label(e.item).capitalize(), e.n]


func draw_slot(b: SlotBox) -> void:
	if player == null or player.body == null:
		return
	var r := Rect2(Vector2.ZERO, b.size)
	b.draw_rect(r, SLOT_BG)
	var held: bool = b.place == InvMoves.INV and b.index == player.held
	var hover := b.get_global_rect().has_point(b.get_viewport().get_mouse_position())
	var edge := HELD_EDGE if held else (HOVER_EDGE if hover else SLOT_EDGE)
	b.draw_rect(r, edge, false, 2.0 if held or hover else 1.0)
	var font := ThemeDB.fallback_font
	if b.place == InvMoves.INV and b.index < Cfg.HOTBAR_SLOTS:
		b.draw_string(font, Vector2(3, 11), str(b.index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.5))
	var e = entry_at(b.place, b.index)
	if e == null:
		if b.place == InvMoves.WORN:
			b.draw_string(font, Vector2(0, b.size.y * 0.5 + 4), WORN_EMPTY[b.index], HORIZONTAL_ALIGNMENT_CENTER, b.size.x, 11, Color(1, 1, 1, 0.3))
		return
	if _drag == b:
		_draw_item(b, e, Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10)), 0.35)
	else:
		_draw_item(b, e, Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10)), 1.0)


func _draw_item(c: CanvasItem, e, r: Rect2, alpha: float) -> void:
	var key: String = e.type if Inventory.is_tool_entry(e) else e.item
	var look: Array = LOOK.get(key, [Color.from_hsv(float(hash(key) % 360) / 360.0, 0.4, 0.7), Items.label(key).capitalize().left(6)])
	var col: Color = look[0]
	col.a = alpha
	c.draw_rect(r, col)
	c.draw_rect(r, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	var font := ThemeDB.fallback_font
	c.draw_string(font, r.position + Vector2(0, r.size.y * 0.5 + 2), look[1], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color(1, 1, 1, alpha))
	if Inventory.is_tool_entry(e):
		var full: float = Items.DURABILITY.get(e.type, e.dur)
		var f := clampf(e.dur / full, 0.0, 1.0)
		var bar := Rect2(r.position + Vector2(2, r.size.y - 5), Vector2((r.size.x - 4) * f, 3))
		c.draw_rect(bar, Color(0.3, 0.9, 0.3, alpha).lerp(Color(0.95, 0.25, 0.2, alpha), 1.0 - f))
	elif e.n > 1:
		c.draw_string(font, r.position + Vector2(0, r.size.y - 2), str(e.n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 2, 11, Color(1, 1, 1, alpha))


func _draw_ghost() -> void:
	if _drag == null:
		return
	var e = entry_at(_drag.place, _drag.index)
	if e != null:
		_draw_item(_ghost, e, Rect2(Vector2(5, 5), _ghost.size - Vector2(10, 10)), 0.9)


# --- Drag and drop, right click ---

func start_drag(b: SlotBox) -> void:
	if entry_at(b.place, b.index) != null:
		_drag = b


## Drop where the button came up (viewport position).
func end_drag(at: Vector2) -> void:
	if _drag == null:
		return
	var src := _drag
	_drag = null
	for b in _boxes:
		if b != src and b.is_visible_in_tree() and b.get_global_rect().has_point(at):
			player.request_move(src.place, src.index, b.place, b.index)
			return


func quick(b: SlotBox) -> void:
	if entry_at(b.place, b.index) != null:
		player.request_quick(b.place, b.index)


## The slot box for (place, index), for the playtest's real clicks.
func box(place: String, i: int) -> Control:
	for b in _boxes:
		if b.place == place and b.index == i:
			return b
	return null
