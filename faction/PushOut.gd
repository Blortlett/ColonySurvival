class_name PushOut
## Territorial kingdoms (v3 §1.3). Foreign houses near the king's house, or blocking plots
## the city wants, go through the agreed ladder: invite (independent non-gang groups, if
## the kingdom has room), demand they leave, then war. Gangs get war straight away.
## Each step waits one check (PUSH_CHECK_SECS), so the group panel shows the state.

static var invited := 0
static var joined := 0
static var left := 0
static var wars := 0


## Every PUSH_CHECK_SECS per kingdom (from Cities.update).
static func update(k: Kingdom) -> void:
	var lead: Faction = World.factions.get(k.leading_fid)
	if lead == null:
		return
	var centre := Cities.centre_cell(k)
	var targets := {} # fid -> nearest House in the way
	for f in World.factions.values():
		if World.same_side(f.id, lead.id):
			continue
		for h in f.houses:
			if h.state == House.State.PLANNED:
				continue
			if World.cheb(h.fire_cell, centre) <= Cfg.PUSH_RADIUS:
				var cur: House = targets.get(f.id)
				if cur == null or World.cheb(h.fire_cell, centre) < World.cheb(cur.fire_cell, centre):
					targets[f.id] = h
	# Houses on plots the city wants: kept while the city is short of close plots.
	for fid in k.pushouts:
		var e: Dictionary = k.pushouts[fid]
		var g: Faction = World.factions.get(fid)
		if e.get("wanted", false) and g and not targets.has(fid):
			var h := _house_by_id(g, e.house)
			if h:
				targets[fid] = h
	if SimClock.time < k.room_short_until and not k.pushouts.values().any(func(e): return e.get("wanted", false)):
		var b := _nearest_blocker(k, centre)
		if b and not targets.has(b.faction_id):
			targets[b.faction_id] = b
			k.pushouts[b.faction_id] = {"stage": "", "since": SimClock.time, "wanted": true, "house": b.id}
	for fid in k.pushouts.keys():
		if not targets.has(fid):
			k.pushouts.erase(fid) # gone, joined or moved away
	for fid in targets:
		var g: Faction = World.factions[fid]
		if not k.pushouts.has(fid):
			k.pushouts[fid] = {"stage": "", "since": SimClock.time, "wanted": false, "house": targets[fid].id}
		_step(k, lead, g, k.pushouts[fid])


static func _house_by_id(g: Faction, id: int) -> House:
	for h in g.houses:
		if h.id == id:
			return h
	return null


## The foreign house nearest the centre that blocks a free plot in the close blocks (fire
## spacing or footprint). Other kingdoms' city houses are left alone.
static func _nearest_blocker(k: Kingdom, centre: Vector2i) -> House:
	var plots := Cities.candidate_plots(k, 0, Cities.CLOSE_BLOCK_RING)
	var best: House = null
	var best_d := INF
	for h in World.all_houses():
		if h.state == House.State.PLANNED or World.same_side(h.faction_id, k.groups[0]):
			continue
		var g: Faction = World.factions.get(h.faction_id)
		if g == null or g.kingdom != null:
			continue
		var d := World.cheb(h.fire_cell, centre)
		if d >= best_d:
			continue
		for idx in plots:
			var r := Cities.plot_rect(k, idx)
			if World.cheb(h.fire_cell, r.get_center()) < Cfg.PRIVILEGE_RADIUS * 2 + 1 or h.footprint().intersects(r):
				best = h
				best_d = d
				break
	return best


static func _step(k: Kingdom, lead: Faction, g: Faction, e: Dictionary) -> void:
	var waited := SimClock.time - float(e.since) >= Cfg.PUSH_CHECK_SECS - 0.01
	if g.is_gang() and e.stage != "war" and e.stage != "truce":
		_war(k, lead, g, e, "%s will not suffer the gang %s near its land: war!" % [k.name, g.name])
		return
	match e.stage:
		"":
			if g.kingdom != null and _on_own_plot(g):
				_war(k, lead, g, e, "%s's city stands too close to %s: war!" % [g.kingdom.name, k.name])
			elif g.kingdom == null and not g.solo and k.has_room():
				_stage(e, "inviting")
				invited += 1
				EventBus.log_event("%s invites %s to join the kingdom." % [k.name, g.name])
			else:
				_stage(e, "demanding")
				EventBus.log_event("%s demands that %s leave its land." % [k.name, g.display_name() if not g.solo else "a lone settler"])
		"inviting":
			if not waited:
				return
			if k.has_room() and g.kingdom == null and Relations.score(lead, g) >= Cfg.INVITE_MIN_RELATION and not Wars.at_war(lead, g):
				joined += 1
				EventBus.log_event("%s accepts the invitation of %s." % [g.name, k.name])
				Kingdoms.join(g, k) # it rebuilds on a city plot and abandons its old house (agreed)
				return
			_stage(e, "demanding")
			EventBus.log_event("%s declines; %s demands that it leave." % [g.name, k.name])
		"demanding":
			if not waited:
				return
			var kp := kingdom_power(k)
			var gp := group_power(g)
			if kp >= gp * Cfg.PUSH_POWER_RATIO:
				_stage(e, "leaving")
				g.evicted_by = k.id
				Relations.change(lead, g, Cfg.REL_LEAVE)
				EventBus.log_event("%s agrees to leave %s's land (%.0f vs %.0f power)." % [g.display_name() if not g.solo else "A lone settler", k.name, kp, gp])
			else:
				_war(k, lead, g, e, "%s refuses to leave %s's land: war!" % [g.name, k.name])
		"leaving":
			if SimClock.time - float(e.since) > Cfg.PUSH_LEAVE_SECS:
				_war(k, lead, g, e, "%s is still on %s's land: war!" % [g.display_name(), k.name])
		"war":
			if not Wars.at_war(lead, g):
				_stage(e, "truce")
		"truce":
			if SimClock.time - float(e.since) > Cfg.PUSH_TRUCE_SECS:
				_stage(e, "")


static func _stage(e: Dictionary, stage: String) -> void:
	e.stage = stage
	e.since = SimClock.time


## A refused demand is a war declaration in its own right (agreed): no relation roll needed.
static func _war(k: Kingdom, lead: Faction, g: Faction, e: Dictionary, msg: String) -> void:
	_stage(e, "war")
	g.evicted_by = k.id # if it rebuilds, it rebuilds outside
	if g.solo:
		_stage(e, "leaving") # a lone settler can't wage war; it just has to go
		return
	if not Wars.at_war(lead, g):
		EventBus.log_event(msg)
		Wars.declare(lead, g)
		wars += 1


static func _on_own_plot(g: Faction) -> bool:
	for h in g.homes():
		if h.plot_kid == g.kingdom.id:
			return true
	return false


## Combined fighting strength of every member (v3 §1.3 strength check).
static func group_power(f: Faction) -> float:
	var p := 0.0
	for mid in f.members:
		var m: Agent = World.agents.get(mid)
		if m:
			p += m.fight_power()
	return p


static func kingdom_power(k: Kingdom) -> float:
	var p := 0.0
	for f in k.members():
		p += group_power(f)
	return p


## Housekeeping for a group told to leave: plan a house outside, then abandon the old one
## once the new house is COMPLETE (the v2 relocation rule).
static func leave_step(f: Faction) -> void:
	var k: Kingdom = World.kingdoms.get(f.evicted_by)
	if k == null or not k.has_city or f.kingdom == k:
		f.evicted_by = -1
		return
	var e: Dictionary = k.pushouts.get(f.id, {})
	var centre := Cities.centre_cell(k)
	var inside: Array[House] = []
	var outside_any := false
	var outside_done := false
	for h in f.homes():
		if World.cheb(h.fire_cell, centre) <= Cfg.PUSH_RADIUS or h.id == e.get("house", -1):
			inside.append(h)
		else:
			outside_any = true
			outside_done = outside_done or h.state == House.State.COMPLETE
	if inside.is_empty():
		f.evicted_by = -1
		return
	if outside_done:
		for h in inside:
			Factions.abandon_house(h)
			f.houses.erase(h)
			World.buildings_version += 1
			f.board.remove_for_house(h)
		f.evicted_by = -1
		k.pushouts.erase(f.id)
		left += 1
		EventBus.log_event("%s moves out of %s's land." % [f.display_name() if not f.solo else "A lone settler", k.name])
		return
	if not outside_any and e.get("stage", "") == "leaving":
		Factions.plan_house(f, 1 if f.solo else clamp(f.members.size() + 1, 2, Cfg.FACTION_MAX))


## Groups being pushed out, for the group panel ("demanding F12 leave", "F12 refused: war").
static func describe(k: Kingdom) -> Array[String]:
	var out: Array[String] = []
	for fid in k.pushouts:
		var e: Dictionary = k.pushouts[fid]
		var g: Faction = World.factions.get(fid)
		var n: String = (g.display_name() if not g.solo else "settler #%d" % g.leader_id) if g else "?"
		match e.stage:
			"inviting": out.append("inviting %s" % n)
			"demanding": out.append("demanding %s leave" % n)
			"leaving": out.append("%s leaving" % n)
			"war": out.append("%s refused: war" % n)
			"truce": out.append("%s: truce" % n)
	return out
