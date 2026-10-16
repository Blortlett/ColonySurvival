extends CanvasLayer
## Top bar (time, speed, counts), event log, and the agent inspector.

var agent_layer: Node2D
var dynamic_layer: Node2D

var _top: Label
var _log: Label
var _inspector: PanelContainer
var _insp_label: Label
var _refresh := 0.0


func _ready() -> void:
	_top = _label(Vector2(8, 6), 14)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(4000, 28)
	add_child(bg)
	move_child(bg, 0)

	_log = _label(Vector2(8, 0), 12)
	_log.anchor_top = 1.0
	_log.anchor_bottom = 1.0
	_log.offset_top = -250
	_log.offset_bottom = -8
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log.add_theme_color_override("font_shadow_color", Color.BLACK)

	_inspector = PanelContainer.new()
	_inspector.anchor_left = 1.0
	_inspector.anchor_right = 1.0
	_inspector.offset_left = -380
	_inspector.offset_right = -8
	_inspector.offset_top = 36
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.7)
	sb.set_content_margin_all(8)
	_inspector.add_theme_stylebox_override("panel", sb)
	_insp_label = Label.new()
	_insp_label.add_theme_font_size_override("font_size", 12)
	_insp_label.custom_minimum_size.x = 350
	_insp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspector.add_child(_insp_label)
	_inspector.visible = false
	add_child(_inspector)


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	add_child(l)
	return l


func _process(dt: float) -> void:
	_refresh -= dt
	if _refresh > 0.0:
		return
	_refresh = 0.2
	var happy := 0
	var neutral := 0
	var angry := 0
	var servants := 0
	for a in World.agent_list:
		match a.mood_label():
			"happy": happy += 1
			"neutral": neutral += 1
			_: angry += 1
		if a.is_servant():
			servants += 1
	var houses := 0
	for h in World.all_houses():
		if h.state == House.State.COMPLETE:
			houses += 1
	_top.text = "%s  %s  |  Agents %d (happy %d / neutral %d / angry %d)  |  Factions %d  Servants %d  Houses %d  Deaths %d  |  [Space] pause [1-5] speed [Z] zones [L] labels  LMB inspect  RMB pan  Wheel zoom" % [
		SimClock.time_string(), "PAUSED" if SimClock.paused else "x%d" % int(SimClock.speed),
		World.agent_list.size(), happy, neutral, angry, Factions.real_count(), servants, houses, World.deaths]
	var lines := EventBus.lines.slice(max(0, EventBus.lines.size() - 12))
	_log.text = "\n".join(lines)
	_update_inspector()


func _update_inspector() -> void:
	var a: Agent = World.agents.get(agent_layer.selected_id)
	_inspector.visible = a != null
	if a == null:
		return
	var f := a.faction
	var lines: Array[String] = []
	lines.append("Agent %s   (%s)" % [a.short(), a.mood_label().to_upper()])
	lines.append("HP %d   Hunger %d%%   Warmth %d%%   Mood %d" % [a.hp, a.hunger * 100, a.warmth * 100, a.mood])
	lines.append("STR %d  AGI %d  CHA %d  AUTH %d   Kills %d" % [a.stats.str, a.stats.agi, a.stats.cha, a.stats.auth, a.kills])
	lines.append("XP  str %.0f/%.0f  agi %.0f/%.0f  cha %.0f/%.0f" % [
		a.xp.str, Agent.xp_to_next(a.stats.str), a.xp.agi, Agent.xp_to_next(a.stats.agi), a.xp.cha, Agent.xp_to_next(a.stats.cha)])
	lines.append("Faction: %s%s  (%d members)" % [f.display_name(), "  [LEADER]" if f.leader_id == a.id and not f.solo else "", f.members.size()])
	if a.is_servant():
		lines.append("Servant of #%d" % a.master_id)
	if a.servants.size() > 0:
		lines.append("Servants: %s" % ", ".join(a.servants.map(func(i): return "#%d" % i)))
	var h := a.home()
	lines.append("Home: %s" % ("none" if h == null else "house %d (%s, %d/%d)" % [h.id, House.State.keys()[h.state], h.occupants.size(), h.capacity]))
	if h and h.fire:
		lines.append("Home fire: %d wood" % h.fire.wood_left())
	lines.append("Capacity %d/%d" % [a.inv.total(), a.capacity()])
	lines.append("Inv: %s" % a.inv.summary())
	lines.append("Doing: %s" % (a.job.label() if a.job else "thinking"))
	lines.append("Tasks on board: %d" % f.board.tasks.size())
	var ops := a.opinions.keys()
	ops.sort_custom(func(x, y): return abs(a.opinions[x]) > abs(a.opinions[y]))
	if ops.size() > 0:
		var parts: Array[String] = []
		for k in ops.slice(0, 5):
			parts.append("#%d:%+d" % [k, a.opinions[k]])
		lines.append("Opinions: %s" % " ".join(parts))
	_insp_label.text = "\n".join(lines)
