class_name KingdomWars
## Kingdom against kingdom (Kingdom Wars Plan §1). Every kingdom hates every other one, so no
## relations are kept: once a minute a free kingdom declares on the weakest free rival it can
## match. A kingdom is only ever in one kingdom war, as attacker or defender.

static var declared := 0
static var ended_peace := 0
static var deaths := 0 # agents killed by an enemy kingdom's member
static var scattered := 0 # kingdoms broken up (§1.8)
static var scattered_agents := 0
static var _check_acc := 0.0
static var _truces := {} # Vector2i(low kingdom id, high kingdom id) -> sim time the pair may fight again
static var _enemy := {} # kingdom id -> enemy kingdom id, for every kingdom war (rebuilt by refresh)
static var _scattering := {} # kingdom id -> true while it breaks up


## Once a second (from World): the war check every KWAR_CHECK_SECS.
static func per_second(s: float) -> void:
	_check_acc += s
	if _check_acc >= Cfg.KWAR_CHECK_SECS:
		_check_acc = 0.0
		check()
	for w in Wars.wars.duplicate():
		if w.get("kingdom", false):
			_scatter_check(w)
	for k in World.kingdoms.values():
		var ek := enemy(k)
		if ek and Raids.of_kingdom(k) == null and _raid_ready(k):
			Raids.start_kingdom(k, ek)


## The loser scatters (§1.8): a quarter or less of its members at the start of the war are
## alive, and the enemy has twice its living members. Both low and even: they fight on.
static func _scatter_check(w: Dictionary) -> void:
	var ka: Kingdom = World.kingdoms.get(int(w.a.substr(1)))
	var kb: Kingdom = World.kingdoms.get(int(w.b.substr(1)))
	if ka == null or kb == null:
		return
	var na := living_members(ka)
	var nb := living_members(kb)
	if na <= w.start[w.a] * Cfg.KWAR_LOSS_SHARE and nb >= na * Cfg.KWAR_OUTNUMBER:
		scatter(ka, kb)
	elif nb <= w.start[w.b] * Cfg.KWAR_LOSS_SHARE and na >= nb * Cfg.KWAR_OUTNUMBER:
		scatter(kb, ka)


static func is_scattering(k: Kingdom) -> bool:
	return _scattering.has(k.id)


## A beaten kingdom breaks up (§1.8): every group disbands, its houses are abandoned and
## servants freed, and each survivor runs off alone in its own random direction. The winner
## doesn't chase them, and they never join it.
static func scatter(k: Kingdom, winner: Kingdom, fell_apart: bool = false) -> void:
	if _scattering.has(k.id):
		return
	_scattering[k.id] = true
	var agents: Array[Agent] = []
	for f in k.members():
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m:
				agents.append(m)
	if fell_apart:
		EventBus.social(&"scatter", "The kingdom of %s falls apart mid-war with %s! Its %d survivors scatter to the winds." % [k.name, winner.name if winner else "?", agents.size()], [], [k, winner])
	else:
		EventBus.social(&"scatter", "The kingdom of %s is broken%s! Its %d survivors scatter to the winds." % [k.name, (" by %s" % winner.name) if winner else "", agents.size()], [], [k, winner])
	for r in Raids.active.duplicate():
		if r.kingdom == k or (winner and r.kingdom == winner):
			Raids.end_raid(r, r.kingdom == winner, "")
	var gone := {}
	for a in agents:
		gone[a.id] = true
	for a in agents:
		if a.is_servant():
			Factions.free_agent(a)
	for a in agents:
		if not a.faction.solo:
			Factions.leave(a) # the last one out disbands the group: houses abandoned
			Factions.make_solo(a)
	if World.kingdoms.has(k.id):
		Kingdoms.dissolve(k)
	# Nobody chases them.
	for x in World.agent_list:
		if gone.has(x.id):
			continue
		for id in gone:
			x.death_match.erase(id)
		if x.job and x.job.kind == Job.Kind.FIGHT and gone.has(x.job.target_id):
			Brain.set_job(x, null)
	for a in agents:
		a.death_match.clear()
		a.raid_id = -1
		a.defend_raid = -1
		var dir := Vector2.RIGHT.rotated(World.rng.randf() * TAU)
		var dist := World.rng.randi_range(Cfg.SCATTER_MIN, Cfg.SCATTER_MAX)
		Brain.flee(a, a.pos - dir, -1, Job.PRIO_CRITICAL, dist)
		a.job.timer = dist / 2.0
	scattered += 1
	scattered_agents += agents.size()
	World.zones_dirty = true
	World.buildings_version += 1
	_scattering.erase(k.id)


## The next kingdom raid goes once 70% of the members are above half HP (start).
static func _raid_ready(k: Kingdom) -> bool:
	var n := 0
	var fit := 0
	for f in k.members():
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m:
				n += 1
				if m.hp > Cfg.MAX_HP * 0.5:
					fit += 1
	return n > 0 and fit >= n * Cfg.KWAR_RAID_READY


## The capital (§1.7): the king's group's finished city house nearest the centre, its fire
## burning. Null while it is down (raids then go for the smeltery and workshop).
static func capital(k: Kingdom) -> House:
	var lead: Faction = World.factions.get(k.leading_fid)
	if lead == null:
		return null
	var best: House = null
	for h in lead.homes():
		if h.plot_kid != k.id or h.state != House.State.COMPLETE or h.fire == null or not h.fire.burning():
			continue
		if best == null or Cities.ring(h.plot) < Cities.ring(best.plot):
			best = h
	return best


static func in_grace(k: Kingdom) -> bool:
	return SimClock.time - k.founded < Cfg.KWAR_GRACE_SECS


static func grace_left(k: Kingdom) -> float:
	return max(0.0, Cfg.KWAR_GRACE_SECS - (SimClock.time - k.founded))


static func at_war(k: Kingdom) -> bool:
	return k != null and _enemy.has(k.id)


static func enemy(k: Kingdom) -> Kingdom:
	return World.kingdoms.get(_enemy.get(k.id, -1)) if k else null


## True if the two agents belong to kingdoms at war with each other.
static func enemies(a: Agent, b: Agent) -> bool:
	var ka := a.faction.kingdom if a.faction else null
	var kb := b.faction.kingdom if b.faction else null
	return ka != null and kb != null and _enemy.get(ka.id, -1) == kb.id


static func _pair(ka: Kingdom, kb: Kingdom) -> Vector2i:
	return Vector2i(mini(ka.id, kb.id), maxi(ka.id, kb.id))


static func truce_left(ka: Kingdom, kb: Kingdom) -> float:
	return max(0.0, _truces.get(_pair(ka, kb), 0.0) - SimClock.time)


## Free kingdoms, strongest first, each pick the weakest free rival; the declaration needs
## at least KWAR_POWER_RATIO of its power (agreed). Strongest first, so when two could
## declare on each other the stronger one does.
static func check() -> void:
	var power := {}
	var free: Array[Kingdom] = []
	for k in World.kingdoms.values():
		if not at_war(k) and not in_grace(k):
			power[k.id] = PushOut.kingdom_power(k)
			free.append(k)
	free.sort_custom(func(x, y): return power[x.id] > power[y.id])
	for k in free:
		if at_war(k):
			continue
		var target: Kingdom = null
		for o in free:
			if o == k or at_war(o) or truce_left(k, o) > 0.0:
				continue
			if target == null or power[o.id] < power[target.id]:
				target = o
		if target and power[k.id] >= power[target.id] * Cfg.KWAR_POWER_RATIO:
			declare(k, target, power[k.id], power[target.id])


static func declare(k: Kingdom, target: Kingdom, kp: float, tp: float) -> void:
	Wars.declare_kingdom(k, target)
	declared += 1
	EventBus.social(&"war", "The kingdom of %s declares war on %s (%.0f vs %.0f power)! No prisoners." % [k.name, target.name, kp, tp], [], [k, target])


## Ten minutes without raids (Wars.update): a truce for the pair (agreed).
static func on_peace(w: Dictionary) -> void:
	var ka: Kingdom = World.kingdoms.get(int(w.a.substr(1)))
	var kb: Kingdom = World.kingdoms.get(int(w.b.substr(1)))
	if ka and kb:
		_truces[_pair(ka, kb)] = SimClock.time + Cfg.KWAR_TRUCE_SECS
	ended_peace += 1


## Rebuild the enemy map from the war list (Wars calls this whenever a war starts or ends).
static func refresh() -> void:
	_enemy.clear()
	for w in Wars.wars:
		if w.get("kingdom", false):
			var a := int(w.a.substr(1))
			var b := int(w.b.substr(1))
			_enemy[a] = b
			_enemy[b] = a


static func living_members(k: Kingdom) -> int:
	var n := 0
	for f in k.members():
		n += f.members.size()
	return n


## Attack on sight (§1.5): a member of a kingdom at war drops everything to fight the
## nearest enemy kingdom member in range, or flees from it when badly hurt (§1.4).
## True if it started a fight or a flight.
static func sight(a: Agent) -> bool:
	var k := a.faction.kingdom
	if k == null or not _enemy.has(k.id):
		return false
	var ek: int = _enemy[k.id]
	var best: Agent = null
	var best_d := Cfg.KWAR_SIGHT
	for o in World.agents_near(a.pos, Cfg.KWAR_SIGHT):
		if not o.alive or o.faction.kingdom == null or o.faction.kingdom.id != ek:
			continue
		var d := World.dist(a.pos, o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return false
	if a.hp < Cfg.KWAR_FLEE_HP * Cfg.MAX_HP:
		Brain.flee(a, best.pos, best.id)
	else:
		Combat.start_fight(a, best, true)
	return true
