extends CanvasLayer
## Top bar (time, speed, counts), event log, and the inspector (agent, fire/group or loot bag).

var agent_layer: Node2D
var dynamic_layer: Node2D
var selected_fire: Campfire = null
var selected_loot: LootBag = null
var selected_furniture: Furniture = null

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
	if selected_fire and World.fires.get(selected_fire.cell) != selected_fire:
		selected_fire = null # burned out / destroyed
	if selected_loot and World.loot.get(selected_loot.cell) != selected_loot:
		selected_loot = null # picked up / despawned
	if selected_furniture and World.furniture.get(selected_furniture.cell) != selected_furniture:
		selected_furniture = null
	_inspector.visible = a != null or selected_fire != null or selected_loot != null or selected_furniture != null
	if a == null:
		if selected_fire:
			_insp_label.text = _fire_text(selected_fire)
		elif selected_loot:
			_insp_label.text = _loot_text(selected_loot)
		elif selected_furniture:
			_insp_label.text = _furniture_text(selected_furniture)
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


func _fire_text(f: Campfire) -> String:
	var lines: Array[String] = []
	if not f.is_house:
		lines.append("Wild fire   (%s)" % ("burning" if f.burning() else "out"))
		var by: Agent = World.agents.get(f.placed_by)
		lines.append("Placed by: %s" % ("#%d" % f.placed_by if by else ("#%d (dead)" % f.placed_by if f.placed_by != -1 else "unknown")))
		lines.append("Fuel: %d/%d wood" % [f.wood_left(), f.max_wood()])
		return "
".join(lines)
	var g: Faction = World.factions.get(f.house.faction_id if f.house else f.owner_id)
	if g == null:
		return "House fire (no group)"
	var leader: Agent = World.agents.get(g.leader_id)
	var gang := not g.solo and leader != null and leader.is_angry()
	lines.append("Group %s%s" % [g.display_name(), "   [GANG]" if gang else ""])
	lines.append("Leader: %s   Members %d/%d" % [leader.short() if leader else "—", g.members.size(), Cfg.FACTION_MAX])
	lines.append("Kingdom: —   Relations: —")
	for id in g.members:
		var m: Agent = World.agents.get(id)
		if m == null:
			continue
		var role := "leader" if id == g.leader_id and not g.solo else "member"
		if m.is_servant():
			role = "servant of #%d" % m.master_id
		elif m.servants.size() > 0:
			role += ", master of %s" % ", ".join(m.servants.map(func(i): return "#%d" % i))
		lines.append("  %s  %s  (%s %d)" % [m.short(), role, m.mood_label(), m.mood])
	lines.append("Houses:")
	for h in g.houses:
		var fuel := "no fire" if h.fire == null else "%d/%d wood%s" % [h.fire.wood_left(), h.fire.max_wood(), "" if h.fire.burning() else " (out)"]
		var reinforced := 0
		for c in h.wall_cells + [h.door_cell]:
			var w: Wall = World.walls.get(c)
			if w and w.tier > 0:
				reinforced += 1
		var tiers := "" if reinforced == 0 else "  reinforced %d/%d" % [reinforced, h.wall_cells.size() + 1]
		if h.is_workshop():
			lines.append("  workshop %d%s  %s  %s%s%s" % [h.id, " *" if h.fire == f else "", House.State.keys()[h.state], fuel, tiers, "  [working]" if h.operational() else ""])
			continue
		lines.append("  house %d%s  %s  %d/%d  %s%s" % [h.id, " *" if h.fire == f else "", House.State.keys()[h.state], h.occupants.size(), h.capacity, fuel, tiers])
		var ch := h.live_chest()
		lines.append("    chest: %s" % ("none" if ch == null else "%s %d/%d — %s" % [ch.label(), ch.store.total(), ch.slots(), ch.store.summary()]))
	var counts := {}
	var claimed := 0
	for t in g.board.tasks:
		counts[t.label()] = counts.get(t.label(), 0) + 1
		if t.claimed_by != -1:
			claimed += 1
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [k, counts[k]])
	lines.append("Board: %d tasks (%d claimed)%s" % [g.board.tasks.size(), claimed, "" if parts.is_empty() else "
  " + ", ".join(parts)])
	return "
".join(lines)


func _loot_text(b: LootBag) -> String:
	var lines: Array[String] = []
	lines.append("Loot bag   (despawns in %ds)" % int(ceil(b.timer)))
	lines.append("Dropped by: %s" % ("unknown" if b.dropper_id == -1 else "#%d" % b.dropper_id))
	lines.append("Why: %s" % (b.reason if b.reason != "" else "unknown"))
	var parts: Array[String] = []
	for k in b.stacks:
		parts.append("%s x%d" % [k, b.stacks[k]])
	lines.append("Items: %s" % ("none" if parts.is_empty() else ", ".join(parts)))
	if b.tools.size() > 0:
		var tp: Array[String] = []
		for t in b.tools:
			tp.append("%s (%d/%d)" % [t.type, t.dur, Items.DURABILITY[t.type]])
		lines.append("Tools: %s" % ", ".join(tp))
	return "
".join(lines)


func _furniture_text(fu: Furniture) -> String:
	var lines: Array[String] = []
	var g: Faction = World.factions.get(fu.owner_id)
	lines.append("%s   (HP %d/%d)" % [fu.label().capitalize(), fu.hp, fu.max_hp])
	lines.append("Owner: %s" % (g.display_name() if g else "abandoned"))
	if fu.kind == Furniture.Kind.CHEST:
		lines.append("Slots: %d/%d" % [fu.store.total(), fu.slots()])
		lines.append("Contents: %s" % fu.store.summary())
	else:
		for item in Items.PROCESS:
			var p: Dictionary = Items.PROCESS[item]
			if p.machine == fu.kind:
				var ins: Array[String] = []
				for k in p["in"]:
					ins.append("%d %s" % [p["in"][k], k])
				lines.append("Recipe: %s -> %d %s  (%.0f s)" % [", ".join(ins), p.out, item, p.secs])
		if fu.kind == Furniture.Kind.SAWMILL:
			lines.append("Also: raiding axes are crafted here")
	return "
".join(lines)
