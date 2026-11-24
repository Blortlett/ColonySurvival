extends CanvasLayer
## The player's HUD (Player Controller Plan §6): HP, hunger and warmth bars, held weapon
## and armour with durability, inventory, the build piece, and short messages.
## Always about "the controlled agent" (Summer Roadmap §2.5).

const BAR_W := 220.0
const HP_COL := Color(0.85, 0.2, 0.2)
const HUNGER_COL := Color(0.85, 0.6, 0.2)
const WARM_COL := Color(1.0, 0.45, 0.15)

var player: PlayerController

var _panel: PanelContainer
var _bars: Control
var _info: Label
var _msg: Label
var _refresh := 0.0


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -340
	_panel.offset_right = 340
	_panel.offset_top = -150
	_panel.offset_bottom = -8
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(BAR_W + 70, 66)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.draw.connect(_draw_bars)
	row.add_child(_bars)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 12)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 360
	row.add_child(_info)
	_msg = Label.new()
	_msg.anchor_top = 1.0
	_msg.anchor_bottom = 1.0
	_msg.anchor_left = 0.5
	_msg.anchor_right = 0.5
	_msg.offset_left = -300
	_msg.offset_right = 300
	_msg.offset_top = -180
	_msg.offset_bottom = -154
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 15)
	_msg.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	_msg.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(_msg)


func _process(dt: float) -> void:
	var t := Time.get_ticks_usec()
	visible = player != null and player.body != null
	if not visible:
		return
	_bars.queue_redraw()
	_msg.text = player.message if player.message_t > 0.0 else ""
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.15
		_info.text = _info_text()
	World.prof_add("hud", t)


func _info_text() -> String:
	var a := player.body
	if not a.alive:
		return "You died. Choose how to carry on in the panel above (T take over, N start fresh)."
	var lines: Array[String] = []
	var w := a.melee_weapon()
	var tool = a.inv.get_tool(w)
	var held := Items.label(w) + (" (%d/%d)" % [tool.dur, Items.DURABILITY[w]] if tool else "")
	if a.has_bow_ready():
		held += "   bow, %d arrows (RMB)" % a.inv.count("arrow")
	lines.append("Weapon: " + held)
	var armour: Array[String] = []
	for slot in Items.ARMOR:
		if a.worn.has(slot):
			armour.append("%s %d/%d" % [Items.label(slot), a.worn[slot].dur, Items.DURABILITY[slot]])
	if not armour.is_empty():
		lines.append("Armour: %s (-%d%%)" % [", ".join(armour), int(round(a.armor_reduction() * 100))])
	lines.append("Pack %d/%d: %s" % [a.inv.total(), a.capacity(), a.inv.summary()])
	var group := "on your own" if a.faction.solo else a.faction.display_name()
	lines.append("%s   STR %d AGI %d CHA %d AUTH %d   kills %d" % [group, a.stats.str, a.stats.agi, a.stats.cha, a.stats.auth, a.kills])
	if player.watching:
		lines.append("WATCHING: the AI drives your body (F1 to return)")
	elif player.build_piece != "":
		lines.append("Building %s (%s): LMB place, RMB / X stop" % [Items.label(player.build_piece), _cost(Items.BUILD_COSTS[player.build_piece])])
	else:
		var use: String = ("E open %s  " % player.use_target.label()) if player.use_target else ""
		lines.append(use + "WASD move  LMB swing  hold E harvest  B build  F eat  F1 debug")
	return "\n".join(lines)


func _cost(c: Dictionary) -> String:
	var parts: Array[String] = []
	for k in c:
		parts.append("%d %s" % [c[k], k])
	return ", ".join(parts)


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
