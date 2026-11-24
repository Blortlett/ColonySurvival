class_name Tax
## Kingdom tax (Kingdom Wars Plan §3). Every TAX_SECS a kingdom taxes each independent group
## with a house in the ring around its capital. The group pays (whatever it has; an empty
## chest still counts as paid) or, if the kingdom is weak around it, resists: a tax war.

static var paid := 0
static var nothing := 0 # paid, but the chest held nothing to take
static var resisted := 0
static var items := 0


## From Cities.update, on the kingdom's own timer.
static func update(k: Kingdom) -> void:
	if SimClock.time < k.tax_at:
		return
	k.tax_at = SimClock.time + Cfg.TAX_SECS
	var cap := KingdomWars.capital(k)
	var lead: Faction = World.factions.get(k.leading_fid)
	if cap == null or lead == null:
		return
	for g in World.factions.values():
		if g.solo or g.kingdom != null or g.is_gang() or Wars.at_war(lead, g):
			continue
		var h := _taxed_house(k, cap, g)
		if h:
			_tax(k, lead, g, h)


## The group's house with a chest in this kingdom's ring (outside the push-out radius), if
## this kingdom's capital is the nearest one (agreed).
static func _taxed_house(k: Kingdom, cap: House, g: Faction) -> House:
	var best: House = null
	var best_d := Cfg.TAX_RADIUS + 1
	for h in g.homes():
		if h.state == House.State.PLANNED or h.live_chest() == null:
			continue
		var d := World.cheb(h.fire_cell, cap.fire_cell)
		if d > Cfg.PUSH_RADIUS and d < best_d:
			best_d = d
			best = h
	if best == null:
		return null
	for o in World.kingdoms.values():
		if o != k and o.capital and World.cheb(best.fire_cell, o.capital.fire_cell) < best_d:
			return null
	return best


## Resist or pay (§3.3): group power x anger factor against the kingdom's power near the
## group's house x the courage threshold.
static func _tax(k: Kingdom, lead: Faction, g: Faction, h: House) -> void:
	g.taxed_at = g.taxed_at.filter(func(t): return SimClock.time - t < Cfg.TAX_REPEAT_WINDOW)
	var angry := 0
	for mid in g.members:
		var m: Agent = World.agents.get(mid)
		if m and m.is_angry():
			angry += 1
	var anger: float = 1.0 + Cfg.TAX_ANGER_SHARE * angry / maxf(1.0, g.members.size()) + Cfg.TAX_ANGER_REPEAT * g.taxed_at.size()
	var near := 0.0
	for a in World.agents_near(World.center(h.fire_cell), Cfg.TAX_NEAR_RADIUS):
		if a.faction.kingdom == k:
			near += a.fight_power()
	g.taxed_at.append(SimClock.time)
	var gp := PushOut.group_power(g)
	if gp * anger > near * Cfg.TAX_COURAGE:
		resisted += 1
		g.last_tax = "refused %s" % k.name
		Relations.change(lead, g, Cfg.TAX_RESIST_REL)
		EventBus.social(&"tax_refused", "%s refuses to pay %s's tax (%.0f x %.1f vs %.0f nearby): war!" % [g.name, k.name, gp, anger, near], [], [g, k])
		Wars.declare(lead, g)
		return
	var n := _collect(k, lead, g, h.live_chest())
	paid += 1
	items += n
	if n == 0:
		nothing += 1
	g.last_tax = "%d items to %s" % [n, k.name]
	for mid in g.members:
		var m: Agent = World.agents.get(mid)
		if m:
			m.change_mood(Cfg.TAX_MOOD)
	Relations.change(lead, g, Cfg.TAX_REL)
	EventBus.social(&"tax", "%s taxes %s: %d items taken." % [k.name, g.name, n], [], [g, k], World.center(h.fire_cell), n)


## What the kingdom needs first (its capital chest's stocking shortfall), then the baseline,
## capped at the baseline's worth per member. Taken straight from the chest: iron into the
## smeltery crates if there is room, everything else into the capital's chest (no limit).
static func _collect(k: Kingdom, lead: Faction, g: Faction, ch: Furniture) -> int:
	var cap := KingdomWars.capital(k)
	var dest := cap.live_chest() if cap else null
	if dest == null or ch == null:
		return 0
	var limit := 0
	for item in Cfg.TAX_BASE:
		limit += Cfg.TAX_BASE[item] * g.members.size()
	var taken := 0
	# Needs: berries, spare tools and a weapon the capital chest lacks.
	var need := Stock.shortfall(dest, lead)
	for key in need:
		if key == "berry":
			taken += _take(ch, dest, "berry", min(need[key], limit - taken))
		elif key == "weapon":
			for w in Stock.WEAPONS:
				if ch.store.has_tool(w) and taken < limit:
					taken += _take_tool(ch, dest, w)
					break
		elif key.begins_with("tool:") and taken < limit:
			taken += _take_tool(ch, dest, key.substr(5))
	# Baseline: wood, berries and iron per member.
	for item in Cfg.TAX_BASE:
		var want: int = min(Cfg.TAX_BASE[item] * g.members.size(), limit - taken)
		if want <= 0:
			break
		var to := dest
		if item == "raw_iron":
			for c in Stock.side_crates(lead):
				if c.free_slots() > 0:
					to = c
					break
		taken += _take(ch, to, item, want)
	return taken


static func _take(from: Furniture, to: Furniture, item: String, n: int) -> int:
	var m: int = min(n, min(from.store.count(item), to.free_for(item)))
	if m <= 0:
		return 0
	from.store.remove(item, m)
	to.store.add(item, m)
	return m


static func _take_tool(from: Furniture, to: Furniture, t: String) -> int:
	var tool = from.store.get_tool(t)
	if tool == null or to.free_slots() <= 0:
		return 0
	from.store.take_tool(tool)
	to.store.put_tool(tool)
	return 1
