class_name Kingdoms
## Kingdom formation, joining, leadership and collapse.

const NAME_A := ["Ald", "Bren", "Cor", "Dun", "Eld", "Fen", "Gar", "Hal", "Ith", "Kar", "Lun", "Mor", "Nor", "Ost", "Ral", "Sil", "Tor", "Val", "Wen", "Yr"]
const NAME_B := ["mark", "holt", "wick", "dale", "ford", "heim", "moor", "gard", "stead", "reach"]


static func make_name(rng: RandomNumberGenerator) -> String:
	return NAME_A[rng.randi() % NAME_A.size()] + NAME_B[rng.randi() % NAME_B.size()]


## A successful ally roll between two groups (agreed rules): two independent groups form a
## kingdom; an independent group joins the other's kingdom if it has room. Kingdoms never
## merge and gangs never ally.
static func try_ally(fa: Faction, fb: Faction) -> void:
	if fa.solo or fb.solo or fa.is_gang() or fb.is_gang() or Wars.at_war(fa, fb):
		return
	if fa.kingdom == null and fb.kingdom == null:
		form(fa, fb)
	elif fa.kingdom == null and fb.kingdom.has_room():
		join(fa, fb.kingdom)
	elif fb.kingdom == null and fa.kingdom.has_room():
		join(fb, fa.kingdom)


static func form(fa: Faction, fb: Faction) -> Kingdom:
	var k := Kingdom.new(World.rng)
	World.kingdoms[k.id] = k
	for f in [fa, fb]:
		Wars.drop_side(Wars.side(f))
		k.groups.append(f.id)
		f.kingdom = k
	recompute(k, false)
	World.zones_dirty = true
	World.buildings_version += 1
	EventBus.social(&"kingdom_form", "%s and %s form the kingdom of %s." % [fa.name, fb.name, k.name], [], [k])
	Cities.on_formed(k)
	return k


static func join(f: Faction, k: Kingdom) -> void:
	Wars.drop_side(Wars.side(f))
	k.groups.append(f.id)
	f.kingdom = k
	recompute(k)
	World.zones_dirty = true
	World.buildings_version += 1
	EventBus.social(&"kingdom_join", "%s joins the kingdom of %s (%d groups)." % [f.name, k.name, k.groups.size()], [], [f, k])
	Cities.on_joined(k, f)


static func leave(f: Faction, why: String = "") -> void:
	var k := f.kingdom
	if k == null:
		return
	f.kingdom = null
	k.groups.erase(f.id)
	for t in k.board.tasks.duplicate():
		if t.claimed_by != -1 and f.members.has(t.claimed_by):
			t.claimed_by = -1
	World.zones_dirty = true
	World.buildings_version += 1
	Cities.on_left(k, f)
	EventBus.social(&"kingdom_leave", ("%s leaves %s (%s)." % [f.name, k.name, why]) if why != "" else "", [], [f, k])
	if k.groups.size() < 2:
		dissolve(k)
	else:
		recompute(k)


static func dissolve(k: Kingdom) -> void:
	# Falling apart mid-war (a group turned gang, groups died out) counts as losing (§1.8).
	var ek := KingdomWars.enemy(k)
	if ek and not KingdomWars.is_scattering(k):
		KingdomWars.scatter(k, ek, true)
		return
	EventBus.social(&"kingdom_dissolve", "The kingdom of %s dissolves." % k.name, [], [k])
	for f in k.members():
		f.kingdom = null
	k.groups.clear()
	k.board.clear()
	Wars.drop_side(Wars.kingdom_side(k))
	World.kingdoms.erase(k.id)
	World.zones_dirty = true
	World.buildings_version += 1
	Cities.on_dissolved(k)


## Leading group = highest total AUTH; king = highest rank in it (agreed). A group the
## player founded always leads, and the player is king (Player Group Plan D3).
static func recompute(k: Kingdom, announce: bool = true) -> void:
	var best: Faction = null
	var best_auth := -1
	var king: Agent = null
	for f in k.members():
		var p := Factions.player_in(f) if f.player_led else null
		if p:
			best = f
			king = p
			break
		var total := f.total_auth()
		if total > best_auth:
			best_auth = total
			best = f
	if best == null:
		return
	k.leading_fid = best.id
	if king == null:
		for mid in best.members:
			var m: Agent = World.agents.get(mid)
			if m and (king == null or Factions.outranks(m, king)):
				king = m
	if king and king.id != k.king_id:
		k.king_id = king.id
		if announce:
			EventBus.social(&"king", "%s is now king of %s." % [king.short(), k.name], [king], [k])


## Every couple of seconds: gangs drop out, leadership follows AUTH, tiny kingdoms dissolve.
static func update_all() -> void:
	for k in World.kingdoms.values():
		for f in k.members():
			if f.is_gang():
				leave(f, "turned to banditry")
		for fid in k.groups.duplicate():
			if not World.factions.has(fid):
				k.groups.erase(fid)
				World.buildings_version += 1
		if not World.kingdoms.has(k.id):
			continue
		if k.groups.size() < 2:
			dissolve(k)
		else:
			recompute(k)
			k.capital = KingdomWars.capital(k)
			Cities.update(k)


## Workshops the kingdom aims for: 1, plus 1 more per 4 groups (agreed).
static func workshop_target(k: Kingdom) -> int:
	return 1 + k.groups.size() / 4


static func count() -> int:
	return World.kingdoms.size()
