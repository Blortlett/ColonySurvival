class_name Raids
## Raids (Phase F): who raids whom, the raid party, breaching, defence and the outcome.

static var active: Array[Raid] = []
static var started_count := 0
static var won_count := 0
static var lost_count := 0
static var _acc := 0.0


static func find(id: int) -> Raid:
	for r in active:
		if r.id == id:
			return r
	return null


static func of_attacker(f: Faction) -> Raid:
	for r in active:
		if r.attacker == f:
			return r
	return null


static func against(f: Faction) -> Raid:
	for r in active:
		if r.target_fid == f.id:
			return r
	return null


# --- Starting a raid ---

## Every RAID_CHECK_SECS per group: with at least one raiding axe (agreed), gangs pick the
## weakest nearby group with the richest chest; groups at war pick the nearest enemy house.
static func consider(f: Faction) -> void:
	if f.solo or SimClock.time < f.raid_check_at or of_attacker(f) or against(f):
		return
	f.raid_check_at = SimClock.time + Cfg.RAID_CHECK_SECS
	var axes := GoalLadder.raid_axes(f)
	if axes < 1:
		return
	var gang := f.is_gang()
	if not gang and Wars.enemies_of(f).is_empty():
		return # normal groups and kingdoms must declare war first (agreed)
	var chance := Cfg.RAID_CHANCE + (axes - 1) * Cfg.RAID_CHANCE_PER_AXE
	if World.rng.randf() >= chance:
		return
	var party := _party(f)
	if party.size() < 2:
		return
	var h := _gang_target(f, party.size(), axes) if gang else _war_target(f)
	if h:
		start(f, h, party)


static func _home_cell(f: Faction) -> Vector2i:
	for h in f.homes():
		if h.fire:
			return h.fire_cell
	var l: Agent = World.agents.get(f.leader_id)
	return l.cell() if l else World.NO_CELL


static func _gang_target(f: Faction, party_size: int, axes: int) -> House:
	var home := _home_cell(f)
	if home == World.NO_CELL:
		return null
	var best: House = null
	var best_score := -INF
	for g in World.factions.values():
		if g == f or g.solo or World.same_side(g.id, f.id) or against(g):
			continue
		# More axes let a gang take on tougher targets.
		if g.members.size() > party_size + axes:
			continue
		for h in g.homes():
			if h.state != House.State.COMPLETE or h.fire == null or not h.fire.burning():
				continue
			var d := Vector2(home).distance_to(Vector2(h.fire_cell))
			if d > Cfg.RAID_RANGE:
				continue
			var ch: Furniture = h.live_chest()
			var rich: int = ch.store.total() if ch else 0
			var score: float = (rich + 5.0) / (1.0 + g.members.size()) - d * 0.05
			if score > best_score:
				best_score = score
				best = h
	return best


static func _war_target(f: Faction) -> House:
	var home := _home_cell(f)
	if home == World.NO_CELL:
		return null
	var best: House = null
	var best_d := Cfg.RAID_RANGE * 1.5
	for g in World.factions.values():
		if g.solo or not Wars.at_war(f, g) or against(g):
			continue
		for h in g.homes():
			if h.state != House.State.COMPLETE or h.fire == null or not h.fire.burning():
				continue
			var d := Vector2(home).distance_to(Vector2(h.fire_cell))
			if d < best_d:
				best_d = d
				best = h
	return best


## Every member above 50% HP joins; with 4+ members one keeper stays home (agreed).
static func _party(f: Faction) -> Array[int]:
	var healthy: Array[Agent] = []
	for mid in f.members:
		var m: Agent = World.agents.get(mid)
		if m and m.hp > Cfg.MAX_HP * 0.5:
			healthy.append(m)
	var out: Array[int] = []
	if healthy.is_empty():
		return out
	var keeper: Agent = null
	if f.members.size() >= 4:
		for m in healthy:
			if keeper == null or m.power() < keeper.power():
				keeper = m
	for m in healthy:
		if m != keeper:
			out.append(m.id)
	return out


static func start(f: Faction, h: House, party: Array[int]) -> void:
	var r := Raid.new(f, h)
	r.party = party
	r.size0 = party.size()
	r.rally = _home_cell(f)
	var l: Agent = World.agents.get(f.leader_id)
	if r.rally == World.NO_CELL or (l and l.pos.distance_to(World.center(r.rally)) > 40.0):
		r.rally = l.cell() if l else World.agents[party[0]].cell()
	active.append(r)
	started_count += 1
	for mid in party:
		var m: Agent = World.agents.get(mid)
		m.raid_id = r.id
		if not m.in_combat():
			Brain.set_job(m, raider_job(r))
	var tf: Faction = World.factions.get(h.faction_id)
	Wars.note_raid(f, tf)
	EventBus.log_event("%s %s sets out to raid %s (%d raiders)!" % ["Gang" if f.is_gang() else "Group", f.name, tf.name if tf else "?", party.size()])


static func raider_job(r: Raid) -> Job:
	var j := Job.new(Job.Kind.RAID, Job.PRIO_ORDER)
	j.raid = r
	return j


static func defender_job(r: Raid) -> Job:
	var j := Job.new(Job.Kind.DEFEND, Job.PRIO_CRITICAL)
	j.raid = r
	return j


# --- Running ---

## Twice a second: membership, phase changes, defence recall, win/loss.
static func update(dt: float) -> void:
	_acc += dt
	if _acc < 0.5:
		return
	_acc = 0.0
	for r in active.duplicate():
		_update_raid(r)


static func _update_raid(r: Raid) -> void:
	for mid in r.party.duplicate():
		var m: Agent = World.agents.get(mid)
		if m == null or m.faction != r.attacker:
			r.party.erase(mid)
			if m:
				m.raid_id = -1
	var tf := r.target_faction()
	if not World.factions.has(r.attacker.id):
		end_raid(r, false, "the raiders' group is gone")
		return
	if tf == null and r.alerted and r.target.fire != null:
		_win(r) # every defender is dead or taken as a servant: the house is theirs
		return
	if tf == null or not tf.houses.has(r.target) or r.target.fire == null:
		end_raid(r, false, "the target is gone")
		return
	if r.party.size() * 2 <= r.size0 and r.size0 > 1 or r.party.is_empty():
		end_raid(r, false, "half the raiders are down")
		return
	if SimClock.time - r.started > Cfg.RAID_MAX_SECS:
		end_raid(r, false, "time ran out")
		return
	var raiders := _raiders(r)
	match r.phase:
		Raid.Phase.RALLY:
			var near := 0
			for m in raiders:
				if World.cheb(m.cell(), r.rally) <= 4:
					near += 1
			if near * 10 >= raiders.size() * 7 or SimClock.time - r.phase_since > 25.0:
				_set_phase(r, Raid.Phase.MARCH)
		Raid.Phase.MARCH:
			var fp := r.target.footprint().grow(3)
			for m in raiders:
				if fp.has_point(m.cell()):
					_set_phase(r, Raid.Phase.ASSAULT)
					break
		Raid.Phase.ASSAULT:
			if r.breach == Vector2i(-1, -1) or not _breach_ok(r):
				r.breach = _pick_breach(r.target)
	# Raiders entering the target's zone call every defender home (agreed).
	if not r.alerted and r.phase != Raid.Phase.RALLY:
		for m in raiders:
			var po := World.privilege_owner(m.cell())
			if po != 0 and World.same_side(po, r.target_fid):
				_alert(r)
				break
	# Win: a raider inside while no defenders are standing in the zone (agreed).
	if r.phase == Raid.Phase.ASSAULT:
		for m in raiders:
			if r.target.interior.has_point(m.cell()):
				if _defenders_standing(r) == 0:
					_win(r)
				break


static func _raiders(r: Raid) -> Array[Agent]:
	var out: Array[Agent] = []
	for mid in r.party:
		var m: Agent = World.agents.get(mid)
		if m:
			out.append(m)
	return out


static func _set_phase(r: Raid, p: int) -> void:
	r.phase = p
	r.phase_since = SimClock.time
	if p == Raid.Phase.ASSAULT:
		r.breach = _pick_breach(r.target)


## The door or the weakest wall (corners excluded), lowest HP first; ties go to the door.
static func _pick_breach(h: House) -> Vector2i:
	var best := h.door_cell
	var dw: Wall = World.walls.get(h.door_cell)
	if dw == null:
		return h.door_cell # already open
	var best_hp := dw.hp
	var outer := h.footprint()
	for c in h.wall_cells:
		var corner := (c.x == outer.position.x or c.x == outer.end.x - 1) and (c.y == outer.position.y or c.y == outer.end.y - 1)
		if corner:
			continue
		var w: Wall = World.walls.get(c)
		if w == null:
			return c # a gap: walk straight in
		if w.hp < best_hp:
			best_hp = w.hp
			best = c
	return best


static func _breach_ok(r: Raid) -> bool:
	return r.target.wall_cells.has(r.breach) or r.breach == r.target.door_cell


## Members of the target group in the zone and not running away (allied helpers count too).
static func _defenders_standing(r: Raid) -> int:
	var n := 0
	for a in World.agent_list:
		var defending := a.faction.id == r.target_fid or a.defend_raid == r.id
		if not defending or World.cheb(a.cell(), r.target.fire_cell) > Cfg.PRIVILEGE_RADIUS:
			continue
		if a.job and a.job.kind == Job.Kind.FLEE:
			continue
		n += 1
	return n


## Defence (agreed): every member of the target group drops everything and goes home;
## same-kingdom groups within 30 cells send their healthy members.
static func _alert(r: Raid) -> void:
	r.alerted = true
	var tf := r.target_faction()
	EventBus.log_event("%s's house is under attack! Everyone home to defend." % tf.name)
	Relations.encounter(tf, r.attacker) # the two groups meet: a war roll if relations are bad
	var helpers: Array[Faction] = [tf]
	if tf.kingdom:
		for g in tf.kingdom.members():
			if g == tf:
				continue
			for h in g.homes():
				if h.fire and World.cheb(h.fire_cell, r.target.fire_cell) <= Cfg.KINGDOM_DEFEND_RANGE:
					helpers.append(g)
					break
	for g in helpers:
		for mid in g.members:
			var m: Agent = World.agents.get(mid)
			if m == null or m.raid_id != -1:
				continue
			if g != tf and m.hp <= Cfg.MAX_HP * 0.5:
				continue
			m.defend_raid = r.id
			if not m.in_combat():
				Brain.set_job(m, defender_job(r))


static func _win(r: Raid) -> void:
	var tf := r.target_faction()
	var tname := tf.name if tf else "a broken group"
	var h := r.target
	h.fire.fuel_secs = 0.0 # the fire is put out: the zone dies and the house decays (agreed)
	World.zones_dirty = true
	var taken := 0
	var ch: Furniture = World.furniture.get(h.chest_cell)
	if ch and ch.kind != Furniture.Kind.CHEST:
		ch = null
	if ch:
		for m in _raiders(r):
			if m.pos.distance_to(World.center(ch.cell)) > 12.0:
				continue
			var plan := {}
			for k in ch.store.stacks:
				plan[k] = -ch.store.stacks[k]
			for t in ch.store.tools:
				plan["tool:" + t.type] = plan.get("tool:" + t.type, 0) - 1
			taken += Stock.transfer(m, ch, plan)
	if tf:
		Relations.change(r.attacker, tf, Cfg.REL_ROB)
		Wars.note_raid(r.attacker, tf)
	won_count += 1
	EventBus.log_event("%s sack %s's house: the fire is out and %d items are taken." % [r.attacker.name, tname, taken])
	end_raid(r, true, "")


static func end_raid(r: Raid, won: bool, why: String) -> void:
	active.erase(r)
	if not won:
		lost_count += 1
		EventBus.log_event("%s's raid on %s fails (%s); they retreat." % [r.attacker.name, World.factions[r.target_fid].name if World.factions.has(r.target_fid) else "?", why])
	for a in World.agent_list:
		if a.raid_id == r.id:
			a.raid_id = -1
			if a.job and a.job.kind == Job.Kind.RAID:
				Brain.set_job(a, null)
		if a.defend_raid == r.id:
			a.defend_raid = -1
			if a.job and a.job.kind == Job.Kind.DEFEND:
				Brain.set_job(a, null)


# --- Agent behaviour ---

## Raider: rally, march, then breach and push inside; fight defenders on the way.
static func run_raider(a: Agent, j: Job, dt: float) -> void:
	var r: Raid = j.raid
	if r == null or not active.has(r) or a.raid_id != r.id:
		Brain.set_job(a, null)
		return
	if r.phase != Raid.Phase.RALLY:
		var e := _enemy_near(a, r, 5.0)
		if e:
			Combat.start_fight(a, e)
			return
	var h := r.target
	match r.phase:
		Raid.Phase.RALLY:
			if World.cheb(a.cell(), r.rally) > 3:
				_walk(a, j, r.rally, 3, dt)
		Raid.Phase.MARCH:
			_walk(a, j, h.door_cell + Vector2i(0, 2), 2, dt, h)
		Raid.Phase.ASSAULT:
			if h.interior.has_point(a.cell()):
				return # inside: hold until the defenders are gone
			var w: Wall = World.walls.get(r.breach)
			if w == null:
				# Open: push inside through the gap.
				var inside := Vector2i(clamp(r.breach.x, h.interior.position.x, h.interior.end.x - 1), clamp(r.breach.y, h.interior.position.y, h.interior.end.y - 1))
				if inside == h.fire_cell:
					inside += Vector2i(1, 0)
				if Brain.move_to(a, inside, dt) == Brain.Move.FAILED:
					a.path.clear()
				return
			if World.cheb(a.cell(), r.breach) <= 1 and a.pos.distance_to(World.center(r.breach)) <= 1.6:
				Combat.attack_wall(a, w)
			else:
				_walk(a, j, r.breach, 1, dt, h)


## Walk to a cell near `target`; with `outside_of`, never pick a cell inside that building
## (its interior looks walkable but is sealed until breached).
static func _walk(a: Agent, j: Job, target: Vector2i, radius: int, dt: float, outside_of: House = null) -> void:
	j.repath_t -= dt
	if j.repath_t <= 0.0 or j.cell == Vector2i.ZERO or World.cheb(j.cell, target) > radius:
		j.repath_t = 2.0
		j.cell = _approach_outside(a, target, radius, outside_of)
		a.path.clear()
	if j.cell != World.NO_CELL and Brain.move_to(a, j.cell, dt) == Brain.Move.FAILED:
		j.repath_t = 0.0
		j.cell = World.approach_cell(a, target, radius + 2) # try another spot next step


static func _approach_outside(a: Agent, target: Vector2i, radius: int, h: House) -> Vector2i:
	if h == null:
		return World.approach_cell(a, target, radius)
	var fp := h.footprint()
	var best := World.NO_CELL
	var best_d := INF
	for x in range(target.x - radius, target.x + radius + 1):
		for y in range(target.y - radius, target.y + radius + 1):
			var c := Vector2i(x, y)
			if c == target or fp.has_point(c) or World.house_at(c) != null or not World.passable(a, c):
				continue
			var d := a.pos.distance_squared_to(World.center(c))
			if d < best_d:
				best_d = d
				best = c
	return best


## Defender: go home and fight any raider that comes close.
static func run_defender(a: Agent, j: Job, dt: float) -> void:
	var r: Raid = j.raid
	if r == null or not active.has(r):
		a.defend_raid = -1
		Brain.set_job(a, null)
		return
	for o in World.agents_near(a.pos, 8.0):
		if o.raid_id == r.id and o.alive:
			Combat.start_fight(a, o)
			return
	if World.cheb(a.cell(), r.target.fire_cell) > 3:
		_walk(a, j, r.target.fire_cell, 3, dt)


## A defender (target group member or helper) close to this raider.
static func _enemy_near(a: Agent, r: Raid, radius: float) -> Agent:
	var best: Agent = null
	var best_d := radius
	for o in World.agents_near(a.pos, radius):
		if not o.alive or o.raid_id == r.id:
			continue
		if o.faction.id != r.target_fid and o.defend_raid != r.id:
			continue
		var d := a.pos.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	return best
