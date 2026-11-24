extends CanvasLayer
## The player's HUD (Player Controller Plan §6): HP, hunger and warmth bars in their own
## panel at the bottom right, a hint line (what's in hand, what E would do, the build piece,
## the controls) and short messages above the hotbar. The hotbar, pack, armour and stats are
## ui/InventoryUI.gd. Always about "the controlled agent" (Summer Roadmap §2.5).

const BAR_W := 220.0
const HP_COL := Color(0.85, 0.2, 0.2)
const HUNGER_COL := Color(0.85, 0.6, 0.2)
const WARM_COL := Color(1.0, 0.45, 0.15)

var player: PlayerController
var inv_ui: CanvasLayer # ui/InventoryUI.gd: the text sits above it

var _vitals: PanelContainer
var _bars: Control
var _hint: Label
var _msg: Label
var _refresh := 0.0


func _ready() -> void:
	_vitals = PanelContainer.new()
	_vitals.anchor_left = 1.0
	_vitals.anchor_right = 1.0
	_vitals.anchor_top = 1.0
	_vitals.anchor_bottom = 1.0
	_vitals.offset_left = -10
	_vitals.offset_right = -10
	_vitals.offset_top = -10
	_vitals.offset_bottom = -10
	_vitals.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.88)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	_vitals.add_theme_stylebox_override("panel", sb)
	add_child(_vitals)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(BAR_W + 76, 66)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	_vitals.add_child(_bars)
	_hint = _centre_label(12, Color(0.85, 0.85, 0.85))
	_msg = _centre_label(15, Color(1, 0.9, 0.5))


func _centre_label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -420
	l.offset_right = 420
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(l)
	return l


func _process(dt: float) -> void:
	var t := Time.get_ticks_usec()
	visible = player != null and player.body != null
	if not visible:
		return
	_bars.queue_redraw()
	_msg.text = player.message if player.message_t > 0.0 else ""
	var top: float = inv_ui.top_y() if inv_ui and inv_ui.visible else get_viewport().get_visible_rect().size.y - 10.0
	_hint.offset_top = top - 22
	_hint.offset_bottom = top - 4
	_msg.offset_top = top - 46
	_msg.offset_bottom = top - 24
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.15
		_hint.text = _hint_text()
	World.prof_add("hud", t)


func _hint_text() -> String:
	var a := player.body
	if not a.alive:
		return "You died. Choose how to carry on in the panel above (T take over, N start fresh)."
	if player.watching:
		return "WATCHING: the AI drives your body (F3 to return)"
	if player.radial_id != -1:
		return "Move the mouse to an option, LMB to confirm, release F to cancel"
	if player.build_piece != "":
		return "Building %s (%s): LMB place, RMB / X stop" % [Items.label(player.build_piece), Actions.cost_text(Items.BUILD_COSTS[player.build_piece])]
	var e = player.held_entry()
	var hand := "punch"
	if e != null:
		if Inventory.is_tool_entry(e):
			hand = Items.label(e.type) + (" (shoot, %d arrows)" % a.inv.count("arrow") if e.type == "bow" else "")
		elif e.item == "berry":
			hand = "eat a berry"
	var use: String = ("E open %s   " % player.use_target.label()) if player.use_target else ""
	return "%sLMB %s   1-6 hand   hold E harvest   hold F talk   Tab inventory   B build   F3 debug" % [use, hand]


func _draw_bars() -> void:
	if player == null or player.body == null:
		return
	var a := player.body
	var font := ThemeDB.fallback_font
	var rows := [["HP", a.hp / Cfg.MAX_HP, HP_COL, "%d" % ceil(a.hp)], ["Food", a.hunger, HUNGER_COL, "%d%%" % int(a.hunger * 100)],
		["Warm", a.warmth, WARM_COL, "%d%%" % int(a.warmth * 100)]]
	for i in rows.size():
		var y := 4.0 + i * 21.0
		var r: Array = rows[i]
		_bars.draw_string(font, Vector2(0, y + 12), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		var box := Rect2(40, y, BAR_W, 14)
		_bars.draw_rect(box, Color(0.15, 0.15, 0.15))
		_bars.draw_rect(Rect2(box.position, Vector2(BAR_W * clampf(r[1], 0.0, 1.0), 14)), r[2] if r[1] > 0.25 or int(Time.get_ticks_msec() / 300) % 2 == 0 else Color.WHITE)
		_bars.draw_string(font, Vector2(BAR_W + 46, y + 12), r[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
