extends CanvasLayer
## Top bar (time, speed, counts), event log, and the inspector (agent, fire/group or loot bag).

var agent_layer: Node2D
var dynamic_layer: Node2D
var selected_fire: Campfire = null
var selected_loot: LootBag = null
var selected_furniture: Furniture = null
## The whole-world event log, bottom left. Off while playing (agreed): the player's own
## feed (ui/SocialFeed.gd) takes its place. The watch-only modes (--bench, --shot) keep it.
var show_log := true
## Debug mode (F3 menu open, or no player): the top stats bar shows only then.
var debug := true

var _top: Label
var _top_bg: ColorRect
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
	_top_bg = bg

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
	var t := Time.get_ticks_usec()
	_update(dt)
	World.prof_add("hud", t)


func _update(dt: float) -> void:
	_refresh -= dt
	if _refresh > 0.0:
		return
	_refresh = 0.2
	_top.visible = debug
	_top_bg.visible = debug
	_log.visible = show_log
	if show_log:
		var lines := EventBus.lines.slice(max(0, EventBus.lines.size() - 12))
		_log.text = "\n".join(lines)
	_update_inspector()
	if debug:
		_update_top()


func _update_top() -> void:
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
	_top.text = "%s  %s  |  Agents %d (happy %d / neutral %d / angry %d)  |  Groups %d  Kingdoms %d  Wars %d  Raids %d  Servants %d  Houses %d  Deaths %d  |  [F3] debug menu: speed, pause, watch, overlays, sprites/discs  |  Wheel zoom" % [
		SimClock.time_string(), "PAUSED" if SimClock.paused else "x%d" % int(SimClock.speed),
		World.agent_list.size(), happy, neutral, angry, Factions.real_count(), World.kingdoms.size(), Wars.wars.size(), Raids.active.size(), servants, houses, World.deaths]


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
	lines.append("Group: %s%s  (%d members)%s" % [f.display_name(), "  [LEADER]" if f.leader_id == a.id and not f.solo else "", f.members.size(),
		("   Kingdom: %s%s" % [f.kingdom.name, "  [KING]" if f.kingdom.king_id == a.id else ""]) if f.kingdom else ""])
	if a.is_servant():
		lines.append("Servant of #%d" % a.master_id)
	if a.raid_id != -1:
		lines.append("On a raid")
	if a.defend_raid != -1:
		lines.append("Defending home against a raid")
	if a.servants.size() > 0:
		lines.append("Servants: %s" % ", ".join(a.servants.map(func(i): return _who(i))))
	var h := a.home()
	lines.append("Home: %s" % ("none" if h == null else "house %d (%s, %d/%d)" % [h.id, House.State.keys()[h.state], h.occupants.size(), h.capacity]))
	if h and h.fire:
		lines.append("Home fire: %d wood" % h.fire.wood_left())
	lines.append("Gear: %s" % _gear_text(a))
	lines.append("Capacity %d/%d" % [a.inv.total(), a.capacity()])
	lines.append("Inv: %s" % a.inv.summary())
	lines.append("Doing: %s" % (a.job.label() if a.job else "thinking"))
	lines.append("Tasks on board: %d" % f.board.tasks.size())
	var ops := a.opinions.keys()
	ops.sort_custom(func(x, y): return abs(a.opinions[x]) > abs(a.opinions[y]))
	if ops.size() > 0:
		var parts: Array[String] = []
		for k in ops.slice(0, 5):
			parts.append("%s:%+d" % [_who(k), a.opinions[k]])
		lines.append("Opinions: %s" % " ".join(parts))
	_insp_label.text = "\n".join(lines)


func _fire_text(f: Campfire) -> String:
	var lines: Array[String] = []
	if not f.is_house:
		lines.append("Wild fire   (%s)" % ("burning" if f.burning() else "out"))
		var by: Agent = World.agents.get(f.placed_by)
		lines.append("Placed by: %s" % (_who(f.placed_by) if by else ("#%d (dead)" % f.placed_by if f.placed_by != -1 else "unknown")))
		lines.append("Fuel: %d/%d wood" % [f.wood_left(), f.max_wood()])
		return "\n".join(lines)
	if f.house and f.house.is_smeltery():
		return smeltery_text(f.house)
	var g: Faction = World.factions.get(f.house.faction_id if f.house else f.owner_id)
	if g == null:
		return "House fire (no group)"
	var leader: Agent = World.agents.get(g.leader_id)
	var gang := not g.solo and leader != null and leader.is_angry()
	lines.append("Group %s%s" % [g.display_name(), "   [GANG]" if gang else ""])
	lines.append("Leader: %s   Members %d/%d" % [leader.short() if leader else "—", g.members.size(), Cfg.FACTION_MAX])
	if g.kingdom:
		var k := g.kingdom
		var king: Agent = World.agents.get(k.king_id)
		var lead: Faction = World.factions.get(k.leading_fid)
		lines.append("Kingdom: %s   King: %s   Leading group: %s" % [k.name, king.short() if king else "—", lead.name if lead else "—"])
		lines.append("  Groups (%d/%d): %s" % [k.groups.size(), Cfg.KINGDOM_MAX_GROUPS, ", ".join(k.members().map(func(x): return "%s (AUTH %d)" % [x.name, x.total_auth()]))])
		if k.has_city:
			var road_cells := Cities.city_road_cells(k)
			var built := 0
			var paved := 0
			for c in road_cells:
				built += 1 if World.roads.has(c) else 0
				paved += 1 if World.roads.get(c, 0) >= 2 else 0
			lines.append("  City: %d plots   roads %d/%d (paved %d)" % [k.plots.size(), built, road_cells.size(), paved])
			var push := PushOut.describe(k)
			if not push.is_empty():
				lines.append("  Land: %s" % ", ".join(push))
		var ek := KingdomWars.enemy(k)
		if ek:
			var w := Wars.kingdom_war(k)
			var start: Dictionary = w.get("start", {})
			lines.append("  AT WAR with %s: %d/%d alive vs %d/%d" % [ek.name, KingdomWars.living_members(k), start.get(Wars.kingdom_side(k), 0), KingdomWars.living_members(ek), start.get(Wars.kingdom_side(ek), 0)])
		elif KingdomWars.in_grace(k):
			lines.append("  Grace: %ds left (no kingdom wars)" % KingdomWars.grace_left(k))
	else:
		lines.append("Kingdom: none%s" % ("  (gangs never ally)" if gang else ""))
		if g.last_tax != "":
			var recent := g.taxed_at.filter(func(t): return SimClock.time - t < Cfg.TAX_REPEAT_WINDOW).size()
			lines.append("  Tax: last %s, taxed %d times in 30 min" % [g.last_tax, recent])
	var ek: Kingdom = World.kingdoms.get(g.evicted_by)
	if ek:
		lines.append("Told to leave the land of %s" % ek.name)
	var out_raid := Raids.of_attacker(g)
	var in_raid := Raids.against(g)
	if out_raid:
		var tf := out_raid.target_faction()
		lines.append("RAIDING %s: %s, %d/%d raiders, %ds" % [tf.name if tf else "?", out_raid.phase_name(), out_raid.party.size(), out_raid.size0, SimClock.time - out_raid.started])
	if in_raid:
		lines.append("UNDER ATTACK by %s (%s)" % [in_raid.attacker.name, in_raid.phase_name()])
	var wars := Wars.enemies_of(g)
	lines.append("Allies: %s   Wars: %s" % [g.kingdom.name if g.kingdom else "—", ", ".join(wars) if wars.size() > 0 else "none"])
	var rel: Array[String] = []
	for r in Relations.top(g, 3):
		rel.append("%s %+d" % [r[0].name, r[1]])
	lines.append("Relations: %s" % (", ".join(rel) if rel.size() > 0 else "—"))
	for id in g.members:
		var m: Agent = World.agents.get(id)
		if m == null:
			continue
		var role := "leader" if id == g.leader_id and not g.solo else "member"
		if m.is_servant():
			role = "servant of #%d" % m.master_id
		elif m.servants.size() > 0:
			role += ", master of %s" % ", ".join(m.servants.map(func(i): return _who(i)))
		lines.append("  %s  %s  (%s %d)" % [m.short(), role, m.mood_label(), m.mood])
	lines.append("Houses:")
	for h in g.houses:
		var fuel := "no fire" if h.fire == null else "%d/%d wood%s" % [h.fire.wood_left(), h.fire.max_wood(), "" if h.fire.burning() else " (out)"]
		var tiers := _tier_text(h)
		if h.is_workshop():
			lines.append("  workshop %d%s  %s  %s%s%s" % [h.id, " *" if h.fire == f else "", House.State.keys()[h.state], fuel, tiers, "  [working]" if h.operational() else ""])
			continue
		if h.is_smeltery():
			var held := 0
			var slots := 0
			for c in h.crates():
				held += c.store.total()
				slots += c.slots()
			lines.append("  smeltery %d%s  %s  %s%s%s  crates %d/%d" % [h.id, " *" if h.fire == f else "", House.State.keys()[h.state], fuel, tiers, "  [working]" if h.operational() else "", held, slots])
			continue
		lines.append("  house %d%s%s  %s  %d/%d  %s%s" % [h.id, " *" if h.fire == f else "", " [plot %d,%d]" % [h.plot.x, h.plot.y] if h.plot_kid != -1 else "", House.State.keys()[h.state], h.occupants.size(), h.capacity, fuel, tiers])
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
	lines.append("Board: %d tasks (%d claimed)%s" % [g.board.tasks.size(), claimed, "" if parts.is_empty() else "\n  " + ", ".join(parts)])
	if g.kingdom:
		lines.append("Kingdom board: %s" % _board_summary(g.kingdom.board))
	return "\n".join(lines)


## Equipped weapon and worn armour with durability (v3 agent panel).
func _gear_text(a: Agent) -> String:
	var parts: Array[String] = []
	var w := a.melee_weapon()
	var tool = a.inv.get_tool(w)
	parts.append("%s%s" % [w, " (%d/%d)" % [tool.dur, Items.DURABILITY[w]] if tool else ""])
	for slot in Items.ARMOR:
		if a.worn.has(slot):
			parts.append("%s (%d/%d)" % [Items.label(slot), a.worn[slot].dur, Items.DURABILITY[slot]])
	if a.is_armoured():
		parts.append("-%d%% damage" % int(round(a.armor_reduction() * 100)))
	return ", ".join(parts)


## "reinforced 12/20, stone 4/20, metal door" for a building's walls and door.
func _tier_text(h: House) -> String:
	var t1 := 0
	var t2 := 0
	for c in h.wall_cells:
		var w: Wall = World.walls.get(c)
		if w and w.tier == 1:
			t1 += 1
		elif w and w.tier >= 2:
			t2 += 1
	var parts: Array[String] = []
	if t1 > 0:
		parts.append("reinforced %d/%d" % [t1, h.wall_cells.size()])
	if t2 > 0:
		parts.append("stone %d/%d" % [t2, h.wall_cells.size()])
	var dw: Wall = World.walls.get(h.door_cell)
	if dw and dw.tier > 0:
		parts.append(["", "reinforced door", "metal door"][dw.tier])
	return "" if parts.is_empty() else "  " + ", ".join(parts)


## Smeltery panel (v3 §6): crates, what the furnace is processing, who works there, recipes.
func smeltery_text(h: House) -> String:
	var lines: Array[String] = []
	var g: Faction = World.factions.get(h.faction_id)
	var fuel := "no fire" if h.fire == null else "%d/%d wood%s" % [h.fire.wood_left(), h.fire.max_wood(), "" if h.fire.burning() else " (out)"]
	lines.append("Smeltery %d   %s%s" % [h.id, House.State.keys()[h.state], "   [working]" if h.operational() else ""])
	lines.append("Owner: %s%s" % [g.display_name() if g else "abandoned", ("   Kingdom: %s" % g.kingdom.name) if g and g.kingdom else ""])
	lines.append("Fire: %s%s" % [fuel, _tier_text(h)])
	var fu := h.machine(Furniture.Kind.FURNACE)
	var an := h.machine(Furniture.Kind.ANVIL)
	lines.append("Machines: furnace %s, anvil %s" % ["placed" if fu else "missing", "placed" if an else "missing"])
	var i := 1
	for c in h.crates():
		lines.append("Crate %d: %d/%d — %s" % [i, c.store.total(), c.slots(), c.store.summary()])
		i += 1
	var at_furnace: Array[String] = []
	var at_anvil: Array[String] = []
	for a in World.agent_list:
		if a.job == null or a.job.machine == null:
			continue
		if a.job.machine == fu:
			at_furnace.append("%s (%s)" % [a.short(), a.job.item.replace("_", " ")])
		elif a.job.machine == an:
			at_anvil.append("%s (%s)" % [a.short(), Items.label(a.job.item)])
	lines.append("Furnace: %s" % (", ".join(at_furnace) if at_furnace.size() > 0 else "idle"))
	lines.append("Anvil: %s" % (", ".join(at_anvil) if at_anvil.size() > 0 else "idle"))
	lines.append("Recipes:")
	for item in Items.PROCESS:
		var p: Dictionary = Items.PROCESS[item]
		if p.machine == Furniture.Kind.FURNACE or p.machine == Furniture.Kind.ANVIL:
			lines.append("  " + _recipe_line(item, p))
	for item in Items.ANVIL_RECIPES:
		lines.append("  anvil: %s -> %s" % [_cost_text(Items.RECIPES[item]), Items.label(item)])
	return "
".join(lines)


func _cost_text(cost: Dictionary) -> String:
	var ins: Array[String] = []
	for k in cost:
		ins.append("%d %s" % [cost[k], k.replace("_", " ")])
	return " + ".join(ins)


func _recipe_line(item: String, p: Dictionary) -> String:
	var m := "furnace" if p.machine == Furniture.Kind.FURNACE else ("anvil" if p.machine == Furniture.Kind.ANVIL else "")
	return "%s%s -> %d %s  (%.0f s)" % [m + ": " if m != "" else "", _cost_text(p["in"]), p.out, Items.label(item), p.secs]


func _board_summary(b: TaskBoard) -> String:
	var counts := {}
	for t in b.tasks:
		counts[t.label()] = counts.get(t.label(), 0) + 1
	var parts: Array[String] = []
	for k in counts:
		parts.append("%s x%d" % [k, counts[k]])
	return "%d tasks%s" % [b.tasks.size(), "" if parts.is_empty() else " — " + ", ".join(parts)]


func _loot_text(b: LootBag) -> String:
	var lines: Array[String] = []
	lines.append("Loot bag   (despawns in %ds)" % int(ceil(b.timer)))
	lines.append("Dropped by: %s" % ("unknown" if b.dropper_id == -1 else _who(b.dropper_id)))
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
	return "\n".join(lines)


func _furniture_text(fu: Furniture) -> String:
	var lines: Array[String] = []
	var g: Faction = World.factions.get(fu.owner_id)
	lines.append("%s   (HP %d/%d)" % [fu.label().capitalize(), fu.hp, fu.max_hp])
	lines.append("Owner: %s" % (g.display_name() if g else "abandoned"))
	if fu.house and fu.house.is_smeltery():
		return smeltery_text(fu.house)
	if fu.is_storage():
		lines.append("Slots: %d/%d" % [fu.store.total(), fu.slots()])
		lines.append("Contents: %s" % fu.store.summary())
	elif fu.kind == Furniture.Kind.BOARD:
		if g and g.kingdom:
			lines.append("Kingdom: %s" % g.kingdom.name)
			lines.append("Tasks: %s" % _board_summary(g.kingdom.board))
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
	return "\n".join(lines)


## An agent's name by id ("#12" if it's gone or has no name).
static func _who(id: int) -> String:
	var a: Agent = World.agents.get(id)
	return a.short() if a else "#%d" % id
