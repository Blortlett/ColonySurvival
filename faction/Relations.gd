class_name Relations
## Group-to-group relation scores (-100..100, agreed events) and group-level meetings.
## The v1 pairwise agent opinions are separate and unchanged.

static var _cooldown := {} # "kind:a:b" -> sim time when allowed again


static func score(fa: Faction, fb: Faction) -> float:
	return fa.relations.get(fb.id, 0.0)


## Symmetric change between two different groups (solo factions included: a solo agent's
## faction becomes its group if it founds one).
static func change(fa: Faction, fb: Faction, d: float) -> void:
	if fa == null or fb == null or fa == fb:
		return
	var s: float = clamp(score(fa, fb) + d, -100.0, 100.0)
	fa.relations[fb.id] = s
	fb.relations[fa.id] = s


static func _key(kind: String, fa: Faction, fb: Faction) -> String:
	return "%s:%d:%d" % [kind, min(fa.id, fb.id), max(fa.id, fb.id)]


## True (and starts the cooldown) if this group pair may do `kind` again.
static func ready(kind: String, fa: Faction, fb: Faction, secs: float) -> bool:
	var key := _key(kind, fa, fb)
	if SimClock.time < _cooldown.get(key, -1.0):
		return false
	_cooldown[key] = SimClock.time + secs
	if _cooldown.size() > 20000:
		_cooldown.clear()
	return true


## Sharing a fire: +3, at most once a minute per group pair.
static func shared_fire(fa: Faction, fb: Faction) -> void:
	if fa != fb and ready("fire", fa, fb, Cfg.GROUP_MEET_COOLDOWN):
		change(fa, fb, Cfg.REL_SHARED_FIRE)


## Group-level meeting (agreed): members of two different groups meet, 60 s pair cooldown.
## Relation >= +40: 20% chance to ally. Relation <= -40: 20% chance to declare war.
static func meet(a: Agent) -> void:
	if a.faction.solo or a.is_servant() or a.in_combat() or SimClock.time < a.meet_t:
		return
	a.meet_t = SimClock.time + 1.0
	var fa := a.faction
	for b in World.agents_near(a.pos, Cfg.SOCIAL_RANGE):
		var fb: Faction = b.faction
		if fb == fa or fb.solo or not b.alive:
			continue
		if encounter(fa, fb):
			return


## Two groups meet (pair cooldown): ally or war roll by relation score (agreed).
## False if the pair is still on cooldown.
static func encounter(fa: Faction, fb: Faction) -> bool:
	if fa == null or fb == null or fa == fb or fa.solo or fb.solo:
		return false
	if not ready("meet", fa, fb, Cfg.GROUP_MEET_COOLDOWN):
		return false
	World.social_counts.group_meetings += 1
	var s := score(fa, fb)
	if s >= Cfg.ALLY_AT and World.rng.randf() < Cfg.ALLY_CHANCE:
		Kingdoms.try_ally(fa, fb)
	elif s <= Cfg.WAR_AT and World.rng.randf() < Cfg.WAR_CHANCE and not Wars.at_war(fa, fb):
		if not fa.is_gang():
			Wars.declare(fa, fb)
		elif not fb.is_gang():
			Wars.declare(fb, fa)
	return true


## The strongest relations of a group: up to n best (positive) and n worst (negative).
static func top(f: Faction, n: int) -> Array:
	var rows := []
	for fid in f.relations:
		var o: Faction = World.factions.get(fid)
		if o and not o.solo and abs(f.relations[fid]) >= 1.0:
			rows.append([o, f.relations[fid]])
	rows.sort_custom(func(x, y): return x[1] > y[1])
	var best := rows.filter(func(r): return r[1] > 0.0).slice(0, n)
	var worst := rows.filter(func(r): return r[1] < 0.0)
	worst.reverse()
	return best + worst.slice(0, n)
