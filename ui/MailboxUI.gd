extends CanvasLayer
## Mailbox group panel (Player Group & Base Plan, package C, D11). E on any mailbox opens it
## through the player's station (player/Station.gd), like a chest; E or Esc closes it, and so
## does walking out of reach. Nothing pauses.
##
## Tabs: Members, Faction, Command. Command is view-only for now and reads
## Factions.ladder_status(). A mailbox of the player's own side (their group, or a group of
## their kingdom) shows every tab; a foreign one shows a read-only summary of Members and
## Faction only. Refreshed every 0.3 s while open, like the build menu.

const TABS := ["members", "faction", "command"]
const TAB_TITLES := {"members": "Members", "faction": "Faction", "command": "Command"}
const STATE_TEXT := {"done": "[color=#8fd18f]done[/color]", "in_progress": "[color=#f2d16b]in progress[/color]", "locked": "[color=#888888]locked[/color]"}
const STATE_ICON := {"done": "[color=#8fd18f]✔[/color]", "in_progress": "[color=#f2d16b]▶[/color]", "locked": "[color=#888888]·[/color]"}

var player: PlayerController
var tab := "members"

var _panel: PanelContainer
var _title: Label
var _tab_buttons := {} # tab -> Button
var _body: RichTextLabel
var _refresh := 0.0
var _seen: Furniture = null # the mailbox shown last frame (a new one resets the tab)


func _ready() -> void:
	layer = 6
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -640
	_panel.offset_right = -12
	_panel.offset_top = 90
	_panel.offset_bottom = 90 + 440
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.92)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for t in TABS:
		var b := Button.new()
		b.text = TAB_TITLES[t]
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): select_tab(t))
		row.add_child(b)
		_tab_buttons[t] = b
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 12)
	_body.add_theme_font_size_override("bold_font_size", 12)
	box.add_child(_body)
	var hint := Label.new()
	hint.text = "E / Esc close.  Command is view-only for now."
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.65, 0.65, 0.65)
	box.add_child(hint)
	visible = false


## The open mailbox, or null.
func mailbox() -> Furniture:
	if player == null or player.station == null or not player.station.is_mailbox():
		return null
	return player.station.open


## The group whose mailbox this is.
func group() -> Faction:
	var mb := mailbox()
	if mb == null:
		return null
	var fid: int = mb.house.faction_id if mb.house else mb.owner_id
	return World.factions.get(fid)


## Own side: the player's group, or a group of the player's kingdom.
func own_side() -> bool:
	var f := group()
	return f != null and player.body != null and player.body.faction != null \
			and World.same_side(player.body.faction.id, f.id)


## The tabs this mailbox shows: all of them on the own side, Members and Faction otherwise.
func tabs() -> Array:
	return TABS if own_side() else ["members", "faction"]


func select_tab(t: String) -> bool:
	if not t in tabs():
		_update()
		return false
	tab = t
	_update()
	return true


## The panel's current text without markup (for the playtest).
func text() -> String:
	return _body.get_parsed_text()


func _process(dt: float) -> void:
	var mb := mailbox()
	var on := mb != null and player.alive() and not player.watching and group() != null
	visible = on
	if not on:
		_seen = null
		return
	if mb != _seen:
		_seen = mb
		tab = "members"
		_refresh = 0.0
	_refresh -= dt
	if _refresh <= 0.0:
		_refresh = 0.3
		_update()


func _update() -> void:
	var f := group()
	if f == null:
		return
	var own := own_side()
	if not tab in tabs():
		tab = "members"
	var mb := mailbox()
	var where := (" — %s" % mb.house.label()) if mb and mb.house else ""
	_title.text = "Mailbox: %s%s%s" % [f.display_name(), where, "" if own else "  (foreign, read-only)"]
	for t in TABS:
		var b: Button = _tab_buttons[t]
		b.visible = t in tabs()
		b.button_pressed = t == tab
	var s := ""
	match tab:
		"members": s = _members_text(f, own)
		"faction": s = _faction_text(f, own)
		"command": s = _command_text(f)
	if s != _body.text:
		var scroll := _body.get_v_scroll_bar().value
		_body.text = s
		_body.get_v_scroll_bar().value = scroll


# --- Members ---

func _members_text(f: Faction, own: bool) -> String:
	var ms: Array[Agent] = []
	for mid in f.members:
		var m: Agent = World.agents.get(mid)
		if m and m.alive:
			ms.append(m)
	# Leader first, then members, then servants; by name inside each.
	ms.sort_custom(func(x, y):
		var rx := _role_rank(f, x)
		var ry := _role_rank(f, y)
		return rx < ry if rx != ry else x.short() < y.short())
	var lines: Array[String] = ["[b]%d member%s[/b]" % [ms.size(), "" if ms.size() == 1 else "s"]]
	var cols := 7 if own else 4
	var t := "[table=%d]" % cols
	var head := ["Name", "Role", "Mood", "Home"] if not own else ["Name", "Role", "Mood", "AUTH / CHA", "Combat", "Doing", "Home"]
	for h in head:
		t += "[cell][color=#f2d16b]%s[/color]  [/cell]" % h
	for m in ms:
		var who := m.short() + (" (you)" if m.is_player() else "")
		var cells := [who, _role(f, m), _mood(m)]
		if own:
			cells.append("%d / %d" % [m.stats.auth, m.stats.cha])
			cells.append("STR %d AGI %d  pow %.1f" % [m.stats.str, m.stats.agi, m.fight_power()])
			cells.append(_doing(m))
		cells.append(_home(f, m))
		for c in cells:
			t += "[cell]%s  [/cell]" % c
	t += "[/table]"
	lines.append(t)
	return "\n".join(lines)


func _role_rank(f: Faction, m: Agent) -> int:
	if f.leader_id == m.id:
		return 0
	return 2 if m.is_servant() else 1


func _role(f: Faction, m: Agent) -> String:
	var r := "member"
	if f.leader_id == m.id and not f.solo:
		r = "leader"
	elif m.is_servant():
		var master: Agent = World.agents.get(m.master_id)
		r = "servant" + (" of %s" % master.short() if master else "")
	if f.kingdom and f.kingdom.king_id == m.id:
		r += ", king"
	return r


func _mood(m: Agent) -> String:
	var col := "#8fd18f" if m.is_happy() else ("#e07a6a" if m.is_angry() else "#cccccc")
	return "[color=%s]%s %+d[/color]" % [col, m.mood_label(), int(m.mood)]


func _doing(m: Agent) -> String:
	if m.is_player():
		return "-"
	if m.job == null:
		return "thinking"
	return m.job.label().replace("_", " ").to_lower()


func _home(f: Faction, m: Agent) -> String:
	var h := f.house_of(m.id)
	if h == null:
		return "none"
	return "%s %d (%s)" % [h.label(), h.id, (House.State.keys()[h.state] as String).to_lower()]


# --- Faction ---

func _faction_text(f: Faction, own: bool) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]%s" % [f.display_name(), "  (gang)" if f.is_gang() else ""])
	var leader: Agent = World.agents.get(f.leader_id)
	lines.append("Leader: %s" % (leader.short() if leader else "none"))
	var k := f.kingdom
	if k:
		var king: Agent = World.agents.get(k.king_id)
		lines.append("Kingdom: %s   King: %s   (%d groups)" % [k.name, king.short() if king else "none", k.groups.size()])
	else:
		lines.append("Kingdom: none")
	lines.append("Buildings: %d house%s, %d workshop%s, %d smelter%s" % [
		f.homes().size(), "" if f.homes().size() == 1 else "s",
		f.workshops().size(), "" if f.workshops().size() == 1 else "s",
		f.smelteries().size(), "y" if f.smelteries().size() == 1 else "ies"])
	lines.append("")
	lines.append("[color=#f2d16b]Relations[/color]")
	var me: Faction = player.body.faction if player.body else null
	if not own and me and not me.solo and me != f:
		lines.append("  With your group: %+d" % int(Relations.score(f, me)))
	var top := Relations.top(f, 3)
	if top.is_empty():
		lines.append("  no strong feelings about anyone")
	for r in top:
		var o: Faction = r[0]
		var col := "#8fd18f" if r[1] > 0 else "#e07a6a"
		lines.append("  [color=%s]%+d[/color]  %s" % [col, int(r[1]), o.name])
	var wars := Wars.enemies_of(f)
	lines.append("Wars: %s" % (", ".join(wars) if not wars.is_empty() else "none"))
	if own:
		lines.append("")
		lines.append("[color=#f2d16b]Chest stock[/color]")
		var any := false
		for h in f.houses:
			var ch := h.live_chest()
			if ch:
				any = true
				lines.append("  %s %d chest: %s" % [h.label(), h.id, _stock(ch.store)])
			for cr in h.crates():
				any = true
				lines.append("  %s %d crate: %s" % [h.label(), h.id, _stock(cr.store)])
		if not any:
			lines.append("  no chest yet")
	return "\n".join(lines)


func _stock(inv: Inventory) -> String:
	var parts: Array[String] = []
	var keys := inv.stacks.keys()
	keys.sort()
	for item in keys:
		parts.append("%d %s" % [inv.stacks[item], Items.label(item)])
	for tool in inv.tools:
		parts.append(Items.label(tool.type))
	return ", ".join(parts) if not parts.is_empty() else "empty"


# --- Command (view-only) ---

func _command_text(f: Faction) -> String:
	var lines: Array[String] = ["[b]Group goals[/b]  [color=#888888](in order; view-only)[/color]"]
	for s in Factions.ladder_status(f):
		var head := "%s  [b]%d. %s[/b]  %s" % [STATE_ICON[s.state], s.order + 1, s.label, STATE_TEXT[s.state]]
		if s.note != "":
			head += "  [color=#aaaaaa]— %s[/color]" % s.note
		lines.append(head)
		if s.state == "locked":
			continue
		for t in s.tasks:
			var part := "      %s" % t.label
			if t.total > 0:
				part += " %d/%d" % [t.done, t.total]
			if t.open > 0:
				part += "  [color=#aaaaaa](%d open task%s)[/color]" % [t.open, "" if t.open == 1 else "s"]
			if t.total > 0 or t.open > 0:
				lines.append(part)
	return "\n".join(lines)
