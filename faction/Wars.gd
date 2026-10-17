class_name Wars
## Declared wars between sides. A side is a whole kingdom ("k<id>") or an independent
## group ("g<id>"); war is kingdom-wide (agreed). Gangs raid without declaring.

static var wars: Array = [] # [{a: side, b: side, since: float, last_raid: float}]


static func side(f: Faction) -> String:
	return kingdom_side(f.kingdom) if f.kingdom else "g%d" % f.id


static func kingdom_side(k: Kingdom) -> String:
	return "k%d" % k.id


static func find(fa: Faction, fb: Faction) -> Dictionary:
	var sa := side(fa)
	var sb := side(fb)
	if sa == sb:
		return {}
	for w in wars:
		if (w.a == sa and w.b == sb) or (w.a == sb and w.b == sa):
			return w
	return {}


static func at_war(fa: Faction, fb: Faction) -> bool:
	return not find(fa, fb).is_empty()


static func declare(by: Faction, on: Faction) -> void:
	if by.is_gang() or at_war(by, on) or side(by) == side(on):
		return
	wars.append({"a": side(by), "b": side(on), "since": SimClock.time, "last_raid": SimClock.time})
	EventBus.log_event("%s declares war on %s!" % [side_name(side(by)), side_name(side(on))])


## A raid between the sides keeps the war going (Phase F).
static func note_raid(fa: Faction, fb: Faction) -> void:
	var w := find(fa, fb)
	if not w.is_empty():
		w.last_raid = SimClock.time


## A side vanished (group disbanded, joined or left a kingdom, kingdom dissolved): its wars end.
static func drop_side(s: String) -> void:
	for w in wars.duplicate():
		if w.a == s or w.b == s:
			wars.erase(w)


## Once a second: peace after 10 min without raids (agreed); relations reset to -20.
static func update() -> void:
	for w in wars.duplicate():
		if not _side_alive(w.a) or not _side_alive(w.b):
			wars.erase(w)
			continue
		if SimClock.time - w.last_raid >= Cfg.PEACE_SECS:
			wars.erase(w)
			for fa in side_groups(w.a):
				for fb in side_groups(w.b):
					if Relations.score(fa, fb) < Cfg.PEACE_RELATION:
						fa.relations[fb.id] = Cfg.PEACE_RELATION
						fb.relations[fa.id] = Cfg.PEACE_RELATION
			EventBus.log_event("Peace between %s and %s." % [side_name(w.a), side_name(w.b)])


static func side_groups(s: String) -> Array[Faction]:
	var out: Array[Faction] = []
	var id := int(s.substr(1))
	if s.begins_with("k"):
		var k: Kingdom = World.kingdoms.get(id)
		if k:
			out = k.members()
	else:
		var f: Faction = World.factions.get(id)
		if f:
			out.append(f)
	return out


static func _side_alive(s: String) -> bool:
	return not side_groups(s).is_empty()


static func side_name(s: String) -> String:
	var id := int(s.substr(1))
	if s.begins_with("k"):
		var k: Kingdom = World.kingdoms.get(id)
		return k.name if k else "?"
	var f: Faction = World.factions.get(id)
	return f.name if f else "?"


## Names of the sides this group is at war with.
static func enemies_of(f: Faction) -> Array[String]:
	var s := side(f)
	var out: Array[String] = []
	for w in wars:
		if w.a == s:
			out.append(side_name(w.b))
		elif w.b == s:
			out.append(side_name(w.a))
	return out
