class_name Factions
## Faction membership, leadership, houses and servants.

# --- Membership ---

static func make_solo(a: Agent) -> void:
	var f := Faction.new(World.rng)
	f.solo = true
	f.members.append(a.id)
	f.leader_id = a.id
	World.factions[f.id] = f
	a.faction = f


## Highest authority leads, no exceptions; charisma breaks ties, then lowest id (agreed).
static func recompute_leader(f: Faction) -> void:
	if f == null or f.members.is_empty():
		return
	var best: Agent = null
	for mid in f.members:
		var m: Agent = World.agents.get(mid)
		if m == null:
			continue
		if best == null or m.stats.auth > best.stats.auth \
				or (m.stats.auth == best.stats.auth and m.stats.cha > best.stats.cha):
			best = m
	if best and best.id != f.leader_id:
		var had_leader := f.leader_id != -1 and not f.solo
		f.leader_id = best.id
		if had_leader:
			EventBus.log_event("%s now leads %s." % [best.short(), f.name])


## Two unfactioned agents form a faction. The leader's solo faction (and its house) becomes the team's.
static func form(a: Agent, b: Agent) -> Faction:
	var lead := a
	if b.stats.auth > a.stats.auth or (b.stats.auth == a.stats.auth and b.stats.cha > a.stats.cha):
		lead = b
	var other := b if lead == a else a
	var f := lead.faction
	f.solo = false
	EventBus.log_event("%s and %s form faction %s." % [lead.short(), other.short(), f.name])
	join(other, f)
	return f


## Willing join (only unfactioned agents can do this). Their own house is abandoned.
static func join(a: Agent, f: Faction) -> void:
	if not a.faction.solo or not f.has_room() or a.faction == f:
		return
	leave(a)
	f.members.append(a.id)
	a.faction = f
	a.change_mood(10.0)
	recompute_leader(f)
	for mid in f.members:
		if mid != a.id:
			a.change_opinion(mid, 10.0)
			var m: Agent = World.agents.get(mid)
			if m:
				m.change_opinion(a.id, 10.0)
	if f.members.size() > 2:
		EventBus.log_event("%s joins %s (%d members)." % [a.short(), f.name, f.members.size()])


static func leave(a: Agent) -> void:
	var f := a.faction
	if f == null:
		return
	f.board.release(a.id)
	for h in f.houses:
		h.occupants.erase(a.id)
	f.members.erase(a.id)
	a.faction = null
	if f.members.is_empty():
		disband(f)
	else:
		recompute_leader(f)


static func disband(f: Faction) -> void:
	for h in f.houses.duplicate():
		abandon_house(h)
	f.houses.clear()
	f.board.tasks.clear()
	World.factions.erase(f.id)
	if not f.solo:
		EventBus.log_event("Faction %s is gone." % f.name)


## Called on death. Frees servants, unlinks the master, leaves the faction.
static func on_agent_removed(a: Agent) -> void:
	for sid in a.servants.duplicate():
		var s: Agent = World.agents.get(sid)
		if s and s.alive:
			free_agent(s)
	a.servants.clear()
	if a.is_servant():
		var m: Agent = World.agents.get(a.master_id)
		if m:
			m.servants.erase(a.id)
		a.master_id = -1
	leave(a)


## A servant whose master is gone becomes a free agent: no faction, no home, keeps items, goals reset (agreed).
static func free_agent(s: Agent) -> void:
	var m: Agent = World.agents.get(s.master_id)
	if m:
		m.servants.erase(s.id)
	s.master_id = -1
	leave(s)
	make_solo(s)
	s.job = null
	s.path.clear()
	EventBus.log_event("%s is a free agent again." % s.short())


## The defeated victim becomes the master's servant and joins the master's faction.
static func make_servant(v: Agent, master: Agent) -> void:
	for sid in v.servants.duplicate(): # servants can't have servants
		var s: Agent = World.agents.get(sid)
		if s:
			free_agent(s)
	if v.is_servant():
		var old: Agent = World.agents.get(v.master_id)
		if old:
			old.servants.erase(v.id)
	leave(v)
	var f := master.faction
	if f.solo:
		f.solo = false
		EventBus.log_event("%s founds faction %s with a servant." % [master.short(), f.name])
	f.members.append(v.id)
	v.faction = f
	v.master_id = master.id
	master.servants.append(v.id)
	v.job = null
	v.path.clear()
	recompute_leader(f)
	EventBus.log_event("%s is now %s's servant." % [v.short(), master.short()])


# --- Houses ---

static func plan_house(f: Faction, cap: int) -> House:
	if SimClock.time < f.plan_retry_at:
		return null
	var t0 := Time.get_ticks_usec()
	var h := _plan_house(f, cap)
	World.prof_add("plan_house_ok" if h else "plan_house_fail", t0)
	if h == null:
		f.plan_retry_at = SimClock.time + 20.0 # crowded map: don't search every think
	return h


static func _plan_house(f: Faction, cap: int) -> House:
	var leader: Agent = World.agents.get(f.leader_id)
	if leader == null:
		return null
	var anchor := leader.cell()
	for h in f.houses:
		if h.state != House.State.PLANNED:
			anchor = h.fire_cell
			break
	var size := House.interior_size(cap)
	var best: Rect2i
	var best_d := INF
	for i in 80:
		var r := Cfg.HOUSE_SITE_SEARCH
		var c := anchor + Vector2i(World.rng.randi_range(-r, r), World.rng.randi_range(-r, r))
		var interior := Rect2i(c - size / 2, size)
		var d := Vector2(anchor).distance_to(Vector2(c))
		if d < best_d and _site_ok(interior, f):
			best_d = d
			best = interior
	if best_d == INF:
		return null
	var h := House.new(f.id, best, cap)
	f.houses.append(h)
	f.board.post(Task.new(Task.Type.PLACE_HOUSE_FIRE, h.fire_cell, h))
	return h


static func _site_ok(interior: Rect2i, f: Faction) -> bool:
	var outer := interior.grow(1)
	if outer.position.x < 1 or outer.position.y < 1 or outer.end.x > Cfg.MAP_W - 1 or outer.end.y > Cfg.MAP_H - 1:
		return false
	var fire_cell := interior.position + Vector2i(interior.size.x / 2, interior.size.y / 2)
	if not World.house_fire_spacing_ok(fire_cell):
		return false
	for x in range(outer.position.x, outer.end.x):
		for y in range(outer.position.y, outer.end.y):
			var c := Vector2i(x, y)
			if World.is_solid(c) or World.loot.has(c):
				return false
			var po := World.privilege_owner(c)
			if po != 0 and po != f.id:
				return false
	return World.nearest_node(ResourceNode.Type.TREE, fire_cell, Cfg.HOUSE_MAX_TREE_DIST) != null


static func on_house_fire_placed(h: House, fire: Campfire) -> void:
	h.fire = fire
	fire.house = h
	h.state = House.State.BUILDING
	var f: Faction = World.factions.get(h.faction_id)
	if f == null:
		return
	for c in h.wall_cells:
		f.board.post(Task.new(Task.Type.BUILD_WALL, c, h))
	f.board.post(Task.new(Task.Type.BUILD_DOOR, h.door_cell, h))


## Fire burnt out or house cancelled: the house is gone, its walls stay and decay.
static func destroy_house(h: House) -> void:
	var f: Faction = World.factions.get(h.faction_id)
	if h.fire:
		h.fire.house = null
	if f == null:
		return
	f.board.remove_for_house(h)
	f.houses.erase(h)
	if h.state != House.State.PLANNED and not f.solo:
		EventBus.log_event("%s lost a house (fire went out)." % f.name)


## Leaving a house behind: nobody refuels it, doors stay locked, it decays.
static func abandon_house(h: House) -> void:
	h.occupants.clear()
	if h.fire:
		h.fire.house = null
		h.fire.owner_id = 0
		World.zones_dirty = true
	for c in h.wall_cells + [h.door_cell]:
		var w: Wall = World.walls.get(c)
		if w:
			w.owner_id = 0


## Runs every 2 s per faction: occupant lists, new house blueprints, refuel tasks, completion.
static func housekeeping(f: Faction) -> void:
	for mid in f.members.duplicate():
		if not World.agents.has(mid):
			f.members.erase(mid)
	if f.members.is_empty():
		disband(f)
		return
	var planned := false
	for h in f.houses.duplicate():
		for oid in h.occupants.duplicate():
			if not oid in f.members:
				h.occupants.erase(oid) # removed straight away (agreed)
		if h.state == House.State.PLANNED:
			planned = true
			if not World.house_fire_spacing_ok(h.fire_cell, h) or World.is_solid(h.fire_cell):
				destroy_house(h)
				planned = false
				continue
		elif h.fire:
			if h.fire.wood_left() <= Cfg.FIRE_REFUEL_AT_WOOD and f.board.find(Task.Type.REFUEL, h.fire_cell) == null:
				f.board.post(Task.new(Task.Type.REFUEL, h.fire_cell, h))
			if h.state == House.State.BUILDING and _house_built(h):
				h.state = House.State.COMPLETE
				if not f.solo:
					EventBus.log_event("%s finished a house for %d." % [f.name, h.capacity])
	# Fill free slots with homeless members.
	var homeless: Array[int] = []
	for mid in f.members:
		if f.house_of(mid) == null:
			homeless.append(mid)
	for h in f.houses:
		while h.has_room() and homeless.size() > 0:
			h.occupants.append(homeless.pop_front())
	# Not enough room → start a new house (solo agents decide this themselves in the goal ladder).
	if homeless.size() > 0 and not planned and not f.solo:
		var cap: int = clamp(homeless.size() + 1, 2, Cfg.FACTION_MAX)
		var h := plan_house(f, cap)
		if h:
			while h.has_room() and homeless.size() > 0:
				h.occupants.append(homeless.pop_front())


static func _house_built(h: House) -> bool:
	for c in h.wall_cells + [h.door_cell]:
		if not World.walls.has(c):
			return false
	return true


## Faction members' moods slowly drift toward the faction average (once a minute).
static func mood_drift() -> void:
	for f in World.factions.values():
		if f.solo or f.members.size() < 2:
			continue
		var total := 0.0
		var ms: Array[Agent] = []
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m:
				ms.append(m)
				total += m.mood
		var avg: float = total / max(1, ms.size())
		for m in ms:
			if abs(avg - m.mood) > 1.0:
				m.change_mood(sign(avg - m.mood))


static func real_count() -> int:
	var n := 0
	for f in World.factions.values():
		if not f.solo:
			n += 1
	return n
