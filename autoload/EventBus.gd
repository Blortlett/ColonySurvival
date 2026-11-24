extends Node
## Global event log feeding the HUD, plus social events as plain data for the player's
## social feed (Player Controller Plan §5.1). The sim only reports what happened and who
## was involved; the feed (ui/SocialFeed.gd) decides what concerns the controlled agent.

signal logged(text: String)
## ev: {kind: StringName, text: String, actors: Array[int], names: Array[String],
##      fids: Array[int], kids: Array[int], gnames: Array[String] (the groups passed in),
##      pos: Vector2 (INF if none), n: int, t: float (sim time)}
signal social_event(ev: Dictionary)

const MAX_LINES := 200
const NO_POS := Vector2.INF
var lines: Array[String] = []
## True while something listens for social events (the feed). Off in --bench / --shot /
## --frames, so building the event costs nothing there.
var feed_on := false


func log_event(text: String) -> void:
	var line := "[%s] %s" % [SimClock.time_string(), text]
	lines.append(line)
	if lines.size() > MAX_LINES:
		lines.pop_front()
	logged.emit(line)


## Logs `text` (if any) and reports a social event. `actors` are Agents in sentence order
## (usually doer, then target). `groups` holds Factions and Kingdoms involved: a Faction also
## brings its kingdom and a Kingdom all its groups, so "your side" can be matched even after
## the event changed membership. `pos` defaults to the last actor's position.
func social(kind: StringName, text: String, actors: Array = [], groups: Array = [], pos: Vector2 = NO_POS, n: int = 0) -> void:
	if text != "":
		log_event(text)
	if not feed_on:
		return
	var ids: Array[int] = []
	var names: Array[String] = []
	for a in actors:
		if a:
			ids.append(a.id)
			names.append(a.short())
			if pos == NO_POS:
				pos = a.pos
	var fids: Array[int] = []
	var kids: Array[int] = []
	var gnames: Array[String] = []
	for g in groups:
		if g is Faction or g is Kingdom:
			gnames.append(g.name)
		var k = g
		if g is Faction:
			fids.append(g.id)
			k = g.kingdom
		if k is Kingdom and not kids.has(k.id):
			kids.append(k.id)
			fids.append_array(k.groups)
	social_event.emit({"kind": kind, "text": text, "actors": ids, "names": names, "fids": fids, "kids": kids,
		"gnames": gnames, "pos": pos, "n": n, "t": SimClock.time})
