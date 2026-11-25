class_name Factions
## Faction membership, leadership, houses and servants.

## Group lookups that callers repeat many times per step (B4): [fid, kind] -> Array,
## cleared whenever World.buildings_version moves. Callers must not change the arrays.
static var _cache := {}
static var _cache_version := -1
const CACHE_WORKSHOPS := 0
const CACHE_SMELTERIES := 1
const CACHE_MACHINE_HOUSES := 2
const CACHE_STORAGES := 3


static func cache_get(f: Faction, kind: int):
	if _cache_version != World.buildings_version:
		_cache_version = World.buildings_version
		_cache.clear()
	return _cache.get(Vector2i(f.id, kind))


static func cache_put(f: Faction, kind: int, v: Array) -> void:
	_cache[Vector2i(f.id, kind)] = v

# --- Membership ---

static func make_solo(a: Agent) -> void:
	var f := Faction.new(World.rng)
	f.solo = true
	f.members.append(a.id)
	f.leader_id = a.id
	World.factions[f.id] = f
	a.faction = f


## Rank order shared by group leaders, kings and the player's takeover: higher AUTH, then
## higher CHA, then the lower id (agreed). True if `a` outranks `b`.
static func outranks(a: Agent, b: Agent) -> bool:
	if a.stats.auth != b.stats.auth:
		return a.stats.auth > b.stats.auth
	if a.stats.cha != b.stats.cha:
		return a.stats.cha > b.stats.cha
	return a.id < b.id


## The player's body if it is a member of `f`, else null.
static func player_in(f: Faction) -> Agent:
	for mid in f.members:
		var m: Agent = World.agents.get(mid)
		if m and m.is_player():
			return m
	return null


## Highest rank leads (`outranks`), except in a group the player founded: the player
## leads it (Player Group Plan D1). In an NPC gang the player was asked into, rank decides (D2).
static func recompute_leader(f: Faction) -> void:
	if f == null or f.members.is_empty():
		return
	var best: Agent = null
	var p := player_in(f)
	if p and not f.player_led and not f.solo and f.leader_id == p.id:
		# The player founded this group with a servant (make_servant): everyone else serves them.
		var only_servants := true
		for mid in f.members:
			if mid != p.id and not (mid in p.servants):
				only_servants = false
				break
		f.player_led = only_servants
	if p and f.player_led:
		best = p
	else:
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m == null:
				continue
			if best == null or outranks(m, best):
				best = m
	if best and best.id != f.leader_id:
		var had_leader := f.leader_id != -1 and not f.solo
		f.leader_id = best.id
		if had_leader:
			EventBus.social(&"leader", "%s now leads %s." % [best.short(), f.name], [best], [f])


## Two unfactioned agents form a faction. The leader's solo faction (and its house) becomes the team's.
## `by_player`: the player formed it through their own invite or recruit, so the player's
## faction becomes the group and the player leads it (D1). Otherwise (NPCs, or the player
## accepting an NPC's gang ask) the higher rank leads (D2).
static func form(a: Agent, b: Agent, by_player: bool = false) -> Faction:
	var lead := a
	if by_player:
		lead = a if a.is_player() else b
	elif outranks(b, a):
		lead = b
	var other := b if lead == a else a
	var f := lead.faction
	f.solo = false
	f.player_led = by_player
	f.leader_id = lead.id
	EventBus.social(&"group_form", "%s and %s form faction %s." % [lead.short(), other.short(), f.name], [lead, other], [f])
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
	EventBus.social(&"group_join", ("%s joins %s (%d members)." % [a.short(), f.name, f.members.size()]) if f.members.size() > 2 else "", [a], [f])
	recompute_leader(f)
	for mid in f.members:
		if mid != a.id:
			a.change_opinion(mid, 10.0)
			var m: Agent = World.agents.get(mid)
			if m:
				m.change_opinion(a.id, 10.0)


static func leave(a: Agent) -> void:
	var f := a.faction
	if f == null:
		return
	f.board.release(a.id)
	for h in f.houses:
		h.occupants.erase(a.id)
	f.members.erase(a.id)
	a.faction = null
	if not f.solo:
		EventBus.social(&"group_leave", "", [a], [f])
	if f.members.is_empty():
		disband(f)
	else:
		recompute_leader(f)


static func disband(f: Faction) -> void:
	Kingdoms.leave(f)
	Wars.drop_side(Wars.side(f))
	for h in f.houses.duplicate():
		abandon_house(h)
	f.houses.clear()
	f.board.clear()
	World.factions.erase(f.id)
	World.buildings_version += 1
	World.protect_version += 1
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
	EventBus.social(&"freed", "%s is a free agent again." % s.short(), [s])


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
	var old := v.faction
	if old and not old.solo and old != master.faction:
		Relations.change(old, master.faction, Cfg.REL_SERVANT)
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
	EventBus.social(&"servant", "%s is now %s's servant." % [v.short(), master.short()], [v, master], [f])


# --- Houses ---

static func plan_house(f: Faction, cap: int, kind: int = House.Kind.HOUSE) -> House:
	if SimClock.time < f.plan_retry_at:
		return null
	var t0 := Time.get_ticks_usec()
	var h := _plan_house(f, cap, kind)
	World.prof_add("plan_house_ok" if h else "plan_house_fail", t0)
	if h == null:
		f.plan_retry_at = SimClock.time + 20.0 # crowded map: don't search every think
	return h


static func _plan_house(f: Faction, cap: int, kind: int) -> House:
	if f.kingdom and f.kingdom.has_city:
		return Cities.plan_on_plot(f, cap, kind)
	var leader: Agent = World.agents.get(f.leader_id)
	if leader == null:
		return null
	var anchor := leader.cell()
	for h in f.houses:
		if h.state != House.State.PLANNED:
			anchor = h.fire_cell
			break
	# Told to leave a kingdom's land: look further out, away from the king's house.
	var ek: Kingdom = World.kingdoms.get(f.evicted_by)
	if ek and ek.has_city:
		var centre := Cities.centre_cell(ek)
		var away := Vector2(anchor - centre).normalized()
		if away == Vector2.ZERO:
			away = Vector2.RIGHT.rotated(World.rng.randf() * TAU)
		anchor = centre + Vector2i(away * (Cfg.PUSH_RADIUS + 12))
	var workshop := kind != House.Kind.HOUSE # workshops and smelteries follow the workshop rules
	var size := House.size_for(kind, cap)
	var best: Rect2i
	var best_dir := Vector2i(0, 1)
	var best_d := INF
	for i in 120 if workshop else 80:
		var r := Cfg.HOUSE_SITE_SEARCH
		var c := World.wc(anchor + Vector2i(World.rng.randi_range(-r, r), World.rng.randi_range(-r, r)))
		var interior := Rect2i(c - size / 2, size)
		var d := World.dist(Vector2(anchor), Vector2(c))
		if d < best_d:
			# Round 2 R3/R4: a random door side, the other three if it doesn't fit.
			var pick := site_side(interior, f, workshop, side_order(House.SIDES[World.rng.randi_range(0, 3)]))
			if pick[1] == "":
				best_d = d
				best = interior
				best_dir = pick[0]
	if best_d == INF:
		return null
	var h := House.new(f.id, best, cap, kind, best_dir)
	f.houses.append(h)
	World.buildings_version += 1
	f.board.post(Task.new(Task.Type.PLACE_HOUSE_FIRE, h.fire_cell, h))
	return h


static func _site_ok(interior: Rect2i, f: Faction, workshop: bool = false) -> bool:
	return site_why(interior, f, workshop) == ""


## Why a building with its door on side `dir` can't go on this interior ("" if it can).
## Shared by the AI's site search and the player's base fire (Player Group Base Plan D7),
## so both follow the same rules.
static func site_why(interior: Rect2i, f: Faction, workshop: bool = false, dir: Vector2i = Vector2i(0, 1)) -> String:
	var order: Array[Vector2i] = [dir]
	return site_side(interior, f, workshop, order)[1]


## `first`, then the other door sides (House.SIDES order).
static func side_order(first: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [first]
	for s in House.SIDES:
		if s != first:
			out.append(s)
	return out


## Why the doorway on side `dir` doesn't work ("" if it does). Cells come from
## House.door_layout, so they match where the building puts its door and mailbox.
static func _door_why(interior: Rect2i, dir: Vector2i, clear_nodes: bool = false) -> String:
	var lay := House.door_layout(interior, dir)
	# The cell outside the door must stay open, or the house is sealed (diagonals past walls are blocked).
	if not _open(lay[1], clear_nodes):
		return "the doorway would be blocked"
	# The mailbox goes beside the cell outside the door (D10): one side must be free.
	if not (_open(lay[2], clear_nodes) and not World.furniture.has(World.wc(lay[2]))) \
			and not (_open(lay[3], clear_nodes) and not World.furniture.has(World.wc(lay[3]))):
		return "no room for a mailbox by the door"
	# The way to the door must not run into another building (R4).
	var two_out := lay[1] + (lay[1] - lay[0])
	for h in World.all_houses():
		if World.rect_has(h.footprint(), two_out):
			return "the doorway would face another building"
	return ""


## Walkable, or (with `clear_nodes`) only a resource node stands there, which the builders
## clear once the fire is placed (_ensure_piece_tasks).
static func _open(c: Vector2i, clear_nodes: bool) -> bool:
	return World.is_walkable(c) or (clear_nodes and World.in_bounds(c) and World.nodes.has(World.wc(c)))


## The first door side in `order` whose doorway works, and why the site fails ("" if it
## doesn't): [side, reason]. The side is Vector2i.ZERO when no doorway works.
## `clear_nodes` (the player's base only): resource nodes don't block; they get cleared.
static func site_side(interior: Rect2i, f: Faction, workshop: bool, order: Array[Vector2i], clear_nodes: bool = false) -> Array:
	var outer := interior.grow(1)
	if outer.position.x < 1 or outer.position.y < 1 or outer.end.x > Cfg.MAP_W - 1 or outer.end.y > Cfg.MAP_H - 1:
		return [Vector2i.ZERO, "it would straddle the map seam" if Cfg.WRAP else "too close to the map edge"]
	# All checks are pure, so the cheap per-cell ones go first (B5); the result is unchanged.
	var dir := Vector2i.ZERO
	var door_why := ""
	for d in order:
		var why := _door_why(interior, d, clear_nodes)
		if why == "":
			dir = d
			break
		if door_why == "":
			door_why = why
	if dir == Vector2i.ZERO:
		return [dir, door_why]
	return [dir, _ground_why(interior, f, workshop, clear_nodes)]


## The side-independent part of the site check ("" if the ground is fine).
static func _ground_why(interior: Rect2i, f: Faction, workshop: bool, clear_nodes: bool = false) -> String:
	var outer := interior.grow(1)
	var fire_cell := interior.position + Vector2i(interior.size.x / 2, interior.size.y / 2)
	for x in range(outer.position.x, outer.end.x):
		for y in range(outer.position.y, outer.end.y):
			var c := Vector2i(x, y)
			if not _open(c, clear_nodes) or World.loot.has(World.wc(c)):
				return "something is in the way"
			var po := World.privilege_owner(c)
			if po != 0 and not World.same_side(po, f.id):
				return "another group owns this land"
	# Nobody settles on a foreign kingdom's land (v3 §1.3).
	for k in World.kingdoms.values():
		if k.has_city and f.kingdom != k and World.cheb(fire_cell, Cities.centre_cell(k)) <= Cfg.PUSH_RADIUS + 2:
			return "too close to %s's city" % k.name
	if not World.house_fire_spacing_ok(fire_cell, null, f.id, workshop):
		return "too close to another group's base"
	if World.footprint_clash(outer):
		return "too close to another building"
	if World.nearest_node(ResourceNode.Type.TREE, fire_cell, Cfg.HOUSE_MAX_TREE_DIST) == null:
		return "no trees nearby"
	return ""


## The player's base fire (D7): an interior of the right size centred on this fire cell.
static func base_interior(f: Faction, fire_cell: Vector2i) -> Rect2i:
	var size := House.size_for(House.Kind.HOUSE, base_capacity(f))
	return Rect2i(fire_cell - Vector2i(size.x / 2, size.y / 2), size)


static func base_capacity(f: Faction) -> int:
	return clamp(f.members.size() + 1, 2, Cfg.FACTION_MAX)


## Why `a` can't found their group's base with a fire on this cell ("" if they can).
static func base_why(a: Agent, fire_cell: Vector2i) -> String:
	var f := a.faction
	if f == null or f.solo or f.leader_id != a.id:
		return "you need followers to found a base"
	if not f.homes().is_empty():
		return "your group already has a home"
	return base_site(a, fire_cell)[1]


## The side `a` stands on, seen from the fire cell: the larger axis wins, ties go to
## north/south, and standing on the fire cell means south.
static func base_facing(a: Agent, fire_cell: Vector2i) -> Vector2i:
	var to := World.cdelta(fire_cell, a.cell())
	if abs(to.x) > abs(to.y):
		return Vector2i(signi(to.x), 0)
	if to.y < 0:
		return Vector2i(0, -1)
	return Vector2i(0, 1)


## The base fire's door side and site check (R6): the door faces the side `a` stands on
## relative to the fire, else the other sides. base_why and found_base both use this, so
## they agree. [side, reason] as in site_side.
static func base_site(a: Agent, fire_cell: Vector2i) -> Array:
	var f := a.faction
	return site_side(base_interior(f, fire_cell), f, false, side_order(base_facing(a, fire_cell)), true)


## The player founds their group's base (D8): plan the house around the fire, place it, and
## the members build the rest through the board like any group. Call base_why first.
static func found_base(a: Agent, fire_cell: Vector2i) -> House:
	var f := a.faction
	var dir: Vector2i = base_site(a, fire_cell)[0]
	if dir == Vector2i.ZERO:
		dir = Vector2i(0, 1)
	var h := House.new(f.id, base_interior(f, fire_cell), base_capacity(f), House.Kind.HOUSE, dir)
	f.houses.append(h)
	World.buildings_version += 1
	for mid in f.members:
		if h.has_room() and f.house_of(mid) == null:
			h.occupants.append(mid)
	var fire: Campfire = World.place_fire(h.fire_cell, true, f.id)
	on_house_fire_placed(h, fire)
	if not f.solo:
		EventBus.log_event("%s founds a base for %s." % [a.short(), f.name])
	return h


static func on_house_fire_placed(h: House, fire: Campfire) -> void:
	h.fire = fire
	fire.house = h
	h.state = House.State.BUILDING
	var f: Faction = World.factions.get(h.faction_id)
	if f:
		_ensure_piece_tasks(f, h)


## Post a task for every missing wall, floor, door (and the chest once complete). Also repairs.
static func _ensure_piece_tasks(f: Faction, h: House) -> void:
	var have := {}
	for t in f.board.tasks:
		if t.house == h or t.type == Task.Type.CLEAR_NODE:
			have[Vector3i(t.cell.x, t.cell.y, t.type)] = true
	# Anything grown on a building cell is cleared first. The player's base is sited over
	# nodes (base_site), so its doorstep and mailbox spots are cleared too.
	var cells := h.wall_cells + h.floor_cells + [h.door_cell]
	var lead: Agent = World.agents.get(f.leader_id)
	if lead and lead.is_player():
		cells += [h.door_outside(), h.mailbox_cell, h.mailbox_cell_alt]
	for c in cells:
		if World.nodes.has(World.wc(c)) and not have.has(Vector3i(c.x, c.y, Task.Type.CLEAR_NODE)):
			f.board.post(Task.new(Task.Type.CLEAR_NODE, c, null))
	for c in h.wall_cells:
		if not World.walls.has(World.wc(c)) and not have.has(Vector3i(c.x, c.y, Task.Type.BUILD_WALL)):
			f.board.post(Task.new(Task.Type.BUILD_WALL, c, h))
	for c in h.floor_cells:
		if not World.floors.has(World.wc(c)) and not have.has(Vector3i(c.x, c.y, Task.Type.BUILD_FLOOR)):
			f.board.post(Task.new(Task.Type.BUILD_FLOOR, c, h))
	var d := h.door_cell
	if not World.walls.has(World.wc(d)) and not have.has(Vector3i(d.x, d.y, Task.Type.BUILD_DOOR)):
		f.board.post(Task.new(Task.Type.BUILD_DOOR, d, h))
	if h.state != House.State.COMPLETE:
		return
	if h.is_home():
		var cc := h.chest_cell
		if h.live_chest() == null and not have.has(Vector3i(cc.x, cc.y, Task.Type.PLACE_CHEST)):
			f.board.post(Task.new(Task.Type.PLACE_CHEST, cc, h))
	else:
		for mc in h.machine_cells.values() + h.crate_cells:
			if not World.furniture.has(World.wc(mc)) and not have.has(Vector3i(mc.x, mc.y, Task.Type.PLACE_MACHINE)):
				f.board.post(Task.new(Task.Type.PLACE_MACHINE, mc, h))
	# Every building gets a mailbox by its door (D10). Matched by house, not cell: the
	# runner may move the task to the other side.
	if h.live_mailbox() == null and not f.board.tasks.any(func(t): return t.house == h and t.type == Task.Type.PLACE_MAILBOX):
		var mc := h.mailbox_site()
		if mc != World.NO_CELL:
			f.board.post(Task.new(Task.Type.PLACE_MAILBOX, mc, h))
	if h.upgrade_to <= 0:
		return
	# Upgrades, one task per piece below the target tier (break, then replace; agreed).
	for c in h.wall_cells:
		var w: Wall = World.walls.get(World.wc(c))
		if w and w.owner_id == f.id:
			_post_upgrade(f, h, have, Task.Type.UPGRADE_WALL, c, w.tier, h.upgrade_to)
	var dw: Wall = World.walls.get(World.wc(d))
	if dw and dw.owner_id == f.id:
		_post_upgrade(f, h, have, Task.Type.UPGRADE_DOOR, d, dw.tier, min(h.upgrade_to, Items.max_door_tier()))
	var ch := h.live_chest()
	if ch:
		_post_upgrade(f, h, have, Task.Type.UPGRADE_CHEST, ch.cell, ch.tier, min(h.upgrade_to, Items.max_chest_tier()))


## Post (or raise the target of) an upgrade task for a piece below the target tier.
static func _post_upgrade(f: Faction, h: House, have: Dictionary, type: int, c: Vector2i, cur: int, target: int) -> void:
	if cur >= target:
		return
	if have.has(Vector3i(c.x, c.y, type)):
		var t := f.board.find(type, c)
		if t and t.claimed_by == -1 and t.tier < target:
			t.tier = target
		return
	var t := Task.new(type, c, h)
	t.tier = target
	f.board.post(t)


## Fire burnt out or house cancelled: the house is gone, its walls stay and decay.
static func destroy_house(h: House) -> void:
	var f: Faction = World.factions.get(h.faction_id)
	if h.fire:
		h.fire.house = null
	World.pieces_version += 1
	Cities.on_house_gone(h)
	if f == null:
		return
	f.board.remove_for_house(h)
	f.houses.erase(h)
	World.buildings_version += 1
	if h.state != House.State.PLANNED and not f.solo:
		EventBus.log_event("%s lost a house (fire went out)." % f.name)


## Leaving a house behind: nobody refuels it, doors stay locked, it decays.
static func abandon_house(h: House) -> void:
	h.occupants.clear()
	var ch := h.live_chest()
	if ch:
		ch.owner_id = 0
	h.chest = null
	if h.fire:
		h.fire.house = null
		h.fire.owner_id = 0
		World.zones_dirty = true
	for c in h.wall_cells + [h.door_cell]:
		var w: Wall = World.walls.get(World.wc(c))
		if w:
			w.owner_id = 0
	World.pieces_version += 1
	World.protect_version += 1
	World.buildings_version += 1


## Runs every 2 s per faction: occupant lists, new house blueprints, refuel tasks, completion.
static func housekeeping(f: Faction) -> void:
	for mid in f.members.duplicate():
		if not World.agents.has(mid):
			f.members.erase(mid)
	if f.members.is_empty():
		disband(f)
		return
	var planned := false
	var t := Time.get_ticks_usec()
	for h in f.houses.duplicate():
		for oid in h.occupants.duplicate():
			if not oid in f.members:
				h.occupants.erase(oid) # removed straight away (agreed)
		if h.state == House.State.PLANNED:
			planned = true
			var blocked: bool = World.walls.has(h.fire_cell) or World.fires.has(h.fire_cell) or (h.plot_kid == -1 and World.nodes.has(h.fire_cell))
			if not World.house_fire_spacing_ok(h.fire_cell, h, f.id, not h.is_home()) or blocked:
				destroy_house(h)
				planned = false
				continue
		elif h.fire:
			if h.fire.wood_left() <= Cfg.FIRE_REFUEL_AT_WOOD and f.board.find(Task.Type.REFUEL, h.fire_cell) == null:
				f.board.post(Task.new(Task.Type.REFUEL, h.fire_cell, h))
			if h.state == House.State.BUILDING and _house_built(h):
				h.state = House.State.COMPLETE
				if not h.is_home():
					EventBus.log_event("%s finished a %s." % [f.name, h.label()])
				elif not f.solo:
					EventBus.log_event("%s finished a house for %d." % [f.name, h.capacity])
			_ensure_piece_tasks(f, h)
	World.prof_add("hk_houses", t)
	t = Time.get_ticks_usec()
	# Fill free slots with homeless members.
	var homeless: Array[int] = []
	for mid in f.members:
		if f.house_of(mid) == null:
			homeless.append(mid)
	for h in f.houses:
		while h.has_room() and homeless.size() > 0:
			h.occupants.append(homeless.pop_front())
	# Not enough room → start a new house (solo agents decide this themselves in the goal ladder).
	# A player-led group's first home waits for the player's base fire (D9).
	var awaits_player := f.player_led and f.homes().is_empty()
	if homeless.size() > 0 and not planned and not f.solo and not awaits_player:
		var cap: int = clamp(homeless.size() + 1, 2, Cfg.FACTION_MAX)
		var h := plan_house(f, cap)
		if h:
			while h.has_room() and homeless.size() > 0:
				h.occupants.append(homeless.pop_front())
	World.prof_add("hk_plan_house", t)
	t = Time.get_ticks_usec()
	if not f.solo and not planned:
		_workshop_goals(f)
	World.prof_add("hk_workshop_goals", t)
	t = Time.get_ticks_usec()
	if f.kingdom:
		Cities.relocate(f)
	if f.evicted_by != -1:
		PushOut.leave_step(f)
	World.prof_add("hk_relocate", t)
	t = Time.get_ticks_usec()
	Raids.consider(f)
	World.prof_add("hk_raids", t)


## Group ladder steps 4-6 (agreed): build a workshop (or use the kingdom's), then reinforce
## the house, then the workshop. v3: then a smeltery (gangs go for it straight after the
## workshop), then the stone tier: houses, the smeltery's door, then the workshop (agreed).
static func _workshop_goals(f: Faction) -> void:
	var homes := f.homes()
	if homes.is_empty():
		return
	var main: House = homes[0]
	var ch := main.live_chest()
	if main.state != House.State.COMPLETE or ch == null:
		return
	if ch.store.total() < min(ch.slots() * Inventory.stack_of("berry"), Cfg.STOCK_BERRIES_PER_MEMBER * f.members.size()) / 2:
		return # stock the chest first
	var shops := shared_workshops(f)
	var want := 1 if f.kingdom == null else Kingdoms.workshop_target(f.kingdom)
	if shops.size() < want and not shops.any(func(w): return w.state != House.State.COMPLETE):
		plan_house(f, 0, House.Kind.WORKSHOP) # one at a time per kingdom
	if shops.is_empty():
		return
	if not shops.any(func(w): return w.operational()):
		return
	var reinforced := _upgrade(homes, 1) and _upgrade(f.workshops(), 1)
	if not reinforced and not f.is_gang():
		return
	var smelts := shared_smelteries(f)
	var want_s := 1 if f.kingdom == null else Cfg.KINGDOM_SMELTERIES
	if smelts.size() < want_s and not smelts.any(func(s): return s.state != House.State.COMPLETE):
		plan_house(f, 0, House.Kind.SMELTERY)
	if not reinforced or not smelts.any(func(s): return s.operational()):
		return
	if _upgrade(homes, 2) and _upgrade(f.smelteries(), 2):
		_upgrade(f.workshops(), 2)


## Raise the target tier of these finished buildings; true once all of them are there.
static func _upgrade(list: Array[House], tier: int) -> bool:
	var done := true
	for h in list:
		if h.state == House.State.COMPLETE:
			h.upgrade_to = max(h.upgrade_to, tier)
			if not h.fully_upgraded(tier):
				done = false
	return done


## Workshops this group may use: its own, plus every workshop in its kingdom (agreed).
static func shared_workshops(f: Faction) -> Array[House]:
	var hit = cache_get(f, CACHE_WORKSHOPS)
	if hit != null:
		return hit
	var out: Array[House] = []
	if f.kingdom == null:
		out = f.workshops()
	else:
		for g in f.kingdom.members():
			out.append_array(g.workshops())
	cache_put(f, CACHE_WORKSHOPS, out)
	return out


## Smelteries this group may use: its own, plus every smeltery in its kingdom.
static func shared_smelteries(f: Faction) -> Array[House]:
	var hit = cache_get(f, CACHE_SMELTERIES)
	if hit != null:
		return hit
	var out: Array[House] = []
	if f.kingdom == null:
		out = f.smelteries()
	else:
		for g in f.kingdom.members():
			out.append_array(g.smelteries())
	cache_put(f, CACHE_SMELTERIES, out)
	return out


## Shared workshops then shared smelteries (machine search order).
static func machine_houses(f: Faction) -> Array[House]:
	var hit = cache_get(f, CACHE_MACHINE_HOUSES)
	if hit != null:
		return hit
	var out: Array[House] = shared_workshops(f) + shared_smelteries(f)
	cache_put(f, CACHE_MACHINE_HOUSES, out)
	return out


## Nearest usable machine of this kind for the agent, within range.
static func nearest_machine(a: Agent, kind: int) -> Furniture:
	var best: Furniture = null
	var best_d := Cfg.WORKSHOP_RANGE
	for w in machine_houses(a.faction):
		if not w.operational():
			continue
		var m := w.machine(kind)
		if m == null:
			continue
		var d := World.dist(a.pos, World.center(m.cell))
		if d < best_d and not Brain._blacklisted(a, m.cell):
			best_d = d
			best = m
	return best


static func _house_built(h: House) -> bool:
	for c in h.wall_cells + [h.door_cell]:
		if not World.walls.has(World.wc(c)):
			return false
	for c in h.floor_cells:
		if not World.floors.has(World.wc(c)):
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


# --- Group ladder status (Mailbox UI, package C): a pure read for the Command tab ---

## The group ladder in _workshop_goals order: home, stock chest, workshop, reinforce,
## smeltery, stone tier. Reads only; changes nothing. One Dictionary per step:
##   id: String      stable key ("home", "stock", "workshop", "reinforce", "smeltery", "stone")
##   label: String   what the panel shows
##   state: String   "done", "in_progress" or "locked"
##   note: String    one short line (what it waits for), may be ""
##   tasks: Array    [{label: String, done: int, total: int, open: int}]: progress and open
##                   board tasks for this step's buildings ("Walls 7/14", 3 open). total 0 =
##                   no progress count, only open tasks.
##   enabled: bool   always true for now; a later pass may let the leader toggle steps
##   order: int      position in the ladder; a later pass may let the leader reorder steps
## A step is "done" when its condition holds, else "in_progress" when every earlier step is
## done (gangs go on past reinforce, as in _workshop_goals), else "locked".
static func ladder_status(f: Faction) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var homes := f.homes()
	var main: House = homes[0] if not homes.is_empty() else null
	var ch: Furniture = main.live_chest() if main else null
	var shops := shared_workshops(f)
	var smelts := shared_smelteries(f)
	var gang := f.is_gang()

	var home_done := main != null and main.state == House.State.COMPLETE and ch != null
	var home_note := ""
	if main == null:
		home_note = "place a base fire to found the base" if f.player_led else "no home planned yet"
	elif not home_done:
		home_note = "%s, %s" % [(House.State.keys()[main.state] as String).to_lower(), "chest placed" if ch else "no chest yet"]
	out.append(_ladder_step("home", "Home", home_done, home_note, _ladder_build_tasks(f, [main] if main else [])))

	var want_stock := 0
	if ch:
		want_stock = min(ch.slots() * Inventory.stack_of("berry"), Cfg.STOCK_BERRIES_PER_MEMBER * f.members.size()) / 2
	var stock_done := home_done and ch.store.total() >= want_stock
	var stock_tasks: Array = []
	if ch:
		stock_tasks.append({"label": "Chest stock", "done": mini(ch.store.total(), want_stock), "total": want_stock, "open": 0})
	out.append(_ladder_step("stock", "Stock the chest", stock_done, "" if ch else "needs the home's chest", stock_tasks))

	var shop_done := shops.any(func(w): return w.operational())
	var shop_note := ""
	if not shop_done:
		if shops.is_empty():
			shop_note = "none planned yet"
		elif shops.any(func(w): return w.state == House.State.COMPLETE):
			shop_note = "built; needs its machines and a burning fire"
	if f.kingdom and not shops.is_empty():
		shop_note += ("" if shop_note == "" else "; ") + "shared with %s" % f.kingdom.name
	out.append(_ladder_step("workshop", "Workshop", shop_done, shop_note, _ladder_build_tasks(f, shops)))

	var r_list: Array[House] = []
	r_list.append_array(homes)
	r_list.append_array(f.workshops())
	var reinforced := _ladder_tier_done(r_list, 1)
	out.append(_ladder_step("reinforce", "Reinforce", reinforced,
		"gangs may skip it" if gang and not reinforced else "", _ladder_tier_tasks(f, r_list, 1)))

	var smelt_done := smelts.any(func(s): return s.operational())
	var smelt_note := ""
	if not smelt_done:
		if smelts.is_empty():
			smelt_note = "none planned yet"
		elif smelts.any(func(s): return s.state == House.State.COMPLETE):
			smelt_note = "built; needs its machines and a burning fire"
	out.append(_ladder_step("smeltery", "Smeltery", smelt_done, smelt_note, _ladder_build_tasks(f, smelts)))

	var s_list: Array[House] = []
	s_list.append_array(homes)
	s_list.append_array(f.smelteries())
	s_list.append_array(f.workshops())
	var stone := reinforced and smelt_done and _ladder_tier_done(s_list, 2)
	out.append(_ladder_step("stone", "Stone tier", stone, "", _ladder_tier_tasks(f, s_list, 2)))

	# The real gates are sequential: a later step only opens once the earlier ones are done.
	# The stone tier also needs reinforce, even for gangs (_workshop_goals).
	var prev_done := true
	for i in out.size():
		var s := out[i]
		s.order = i
		if s.state != "done":
			s.state = "in_progress" if prev_done and (s.id != "stone" or reinforced) else "locked"
		if s.id != "reinforce" or not gang:
			prev_done = prev_done and s.state == "done"
	return out


static func _ladder_step(id: String, label: String, done: bool, note: String, tasks: Array) -> Dictionary:
	return {"id": id, "label": label, "state": "done" if done else "locked", "note": note,
		"tasks": tasks, "enabled": true, "order": 0}


## Every building in the list is finished and at this tier (an empty list is not done).
static func _ladder_tier_done(list: Array[House], tier: int) -> bool:
	if list.is_empty():
		return false
	for h in list:
		if h.state != House.State.COMPLETE or not h.fully_upgraded(tier):
			return false
	return true


## Build progress of these buildings: walls and doors standing, plus open board tasks by type.
static func _ladder_build_tasks(f: Faction, list: Array) -> Array:
	var rows: Array = []
	if list.is_empty():
		return rows
	var walls := 0
	var wall_total := 0
	var doors := 0
	for h in list:
		wall_total += h.wall_cells.size()
		for c in h.wall_cells:
			if World.walls.has(World.wc(c)):
				walls += 1
		if World.walls.has(h.door_cell):
			doors += 1
	var open := _ladder_open(f, list)
	rows.append({"label": "Walls", "done": walls, "total": wall_total, "open": open.get(Task.Type.BUILD_WALL, 0)})
	rows.append({"label": "Door", "done": doors, "total": list.size(), "open": open.get(Task.Type.BUILD_DOOR, 0)})
	for t in open:
		if t != Task.Type.BUILD_WALL and t != Task.Type.BUILD_DOOR:
			rows.append({"label": _ladder_task_label(t), "done": 0, "total": 0, "open": open[t]})
	return rows


## Upgrade progress to `tier`: wall and door pieces at that tier, plus open upgrade tasks.
static func _ladder_tier_tasks(f: Faction, list: Array[House], tier: int) -> Array:
	var rows: Array = []
	var at := 0
	var total := 0
	for h in list:
		if h.state != House.State.COMPLETE:
			continue
		for c in h.wall_cells:
			total += 1
			var w: Wall = World.walls.get(World.wc(c))
			if w and w.tier >= tier:
				at += 1
		total += 1
		var dw: Wall = World.walls.get(h.door_cell)
		if dw and dw.tier >= mini(tier, Items.max_door_tier()):
			at += 1
	if total == 0:
		return rows
	var open := _ladder_open(f, list, tier)
	var up := 0
	for t in open:
		up += open[t]
	rows.append({"label": "Walls at T%d" % tier, "done": at, "total": total, "open": up})
	return rows


## Open (not done) board tasks for these buildings, by Task.Type, on the group's board and
## its kingdom's. With `tier`, only upgrade tasks to that tier; without, no upgrade tasks.
static func _ladder_open(f: Faction, list: Array, tier: int = -1) -> Dictionary:
	var counts := {}
	var boards: Array = [f.board]
	if f.kingdom:
		boards.append(f.kingdom.board)
	for b in boards:
		for t in b.tasks:
			if t.done or t.house == null or not list.has(t.house):
				continue
			var up: bool = t.type in [Task.Type.UPGRADE_WALL, Task.Type.UPGRADE_DOOR, Task.Type.UPGRADE_CHEST]
			if up != (tier != -1) or (up and t.tier != tier):
				continue
			counts[t.type] = counts.get(t.type, 0) + 1
	return counts


static func _ladder_task_label(t: int) -> String:
	return (Task.Type.keys()[t] as String).replace("_", " ").capitalize()
