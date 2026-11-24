extends CanvasLayer
## The player's social feed (Player Controller Plan §5.1). Listens to EventBus.social_event
## (plain data from the sim) and keeps the events that concern the controlled agent, in
## three colour-coded tiers:
##   1. involves you (gold): you are one of the actors, or your group is taxed / pushed out
##   2. your group or kingdom (faction colour): only events about your standing (leader,
##      king, joining or leaving a kingdom, war, peace, scattering), not a groupmate's fight
##   3. witnessed nearby (grey): fights, robberies, kills, sacks within FEED_NEAR cells of
##      you (wrap-aware World.dist)
## Always follows `player.body`, so it keeps working after a takeover (Summer Roadmap §2.5).

const FEED_MAX := 8 # entries kept (start)
const FEED_LIFE := 20.0 # real seconds an entry stays at full strength (start)
const FEED_FADE := 4.0 # ...then it fades out over this long
const FEED_NEAR := 16.0 # cells: "within view" at play zoom (start)
const DEDUPE_SECS := 8.0 # the same line again within this long collapses into "x2", "x3"...
const DEDUPE_DEPTH := 3 # how many of the newest entries a repeat may collapse into

const GOLD := Color(1.0, 0.82, 0.3)
const GREY := Color(0.68, 0.68, 0.68)
const NO_SIDE := Color(0.6, 0.8, 1.0) # tier 2 colour if the player's group has none

## Tier 1 by group: events that land on your group as a whole (your goods, your land).
const DIRECT_GROUP := [&"tax", &"tax_refused", &"pushout"]
## Tier 2: your side's standing. kingdom_join / kingdom_leave count only for your own group.
const STANDING := [&"leader", &"king", &"kingdom_form", &"kingdom_join", &"kingdom_leave",
	&"kingdom_dissolve", &"scatter", &"war", &"peace"]
## Tier 3: things worth seeing happen nearby. Single hits are left out (fights cover them).
const WITNESS := [&"fight", &"killed", &"robbed", &"demand", &"plead", &"surrender", &"rebel", &"sack", &"breach"]

var player: PlayerController:
	set(v):
		player = v
		_connect()
## Debug menu toggle: show tier 3 (witnessed nearby).
var show_nearby := true
## {text, tier, color, count, seen (msec of the latest repeat)}, oldest first.
var entries: Array[Dictionary] = []

var _label: RichTextLabel
var _dirty := false
var _refresh := 0.0


func _ready() -> void:
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.scroll_active = false
	_label.fit_content = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.anchor_left = 0.0 # bottom left, where the whole-world log was (agreed)
	_label.anchor_right = 0.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 10
	_label.offset_right = 450
	_label.offset_top = -260
	_label.offset_bottom = -10
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.add_theme_font_size_override("normal_font_size", 13)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	_connect()


func _exit_tree() -> void:
	EventBus.feed_on = false


func _connect() -> void:
	if not is_inside_tree() or player == null:
		return
	if not EventBus.social_event.is_connected(_on_event):
		EventBus.social_event.connect(_on_event)
	EventBus.feed_on = true


## Which tier this event is for the controlled agent: 1, 2, 3, or 0 (not shown).
func tier_of(ev: Dictionary) -> int:
	var me := player.body if player else null
	if me == null or not me.alive and not ev.actors.has(me.id):
		return 0
	if ev.actors.has(me.id):
		return 1
	var fid: int = me.faction.id if me.faction else -1
	var kid: int = me.faction.kingdom.id if me.faction and me.faction.kingdom else -1
	var kind: StringName = ev.kind
	if kind in DIRECT_GROUP and ev.fids.has(fid):
		return 1
	if kind in STANDING and (ev.fids.has(fid) or (kid != -1 and ev.kids.has(kid))):
		if kind in [&"kingdom_join", &"kingdom_leave"] and ev.fids[0] != fid:
			return 0 # another group joining or leaving your kingdom isn't about you
		return 2
	if kind in WITNESS and ev.pos != EventBus.NO_POS and World.dist(me.pos, ev.pos) <= FEED_NEAR:
		return 3
	return 0


func _on_event(ev: Dictionary) -> void:
	var tier := tier_of(ev)
	if tier == 0 or (tier == 3 and not show_nearby):
		return
	var text := _format(ev, tier)
	if text == "":
		return
	add_line(text, tier, _colour(tier))


func add_line(text: String, tier: int, col: Color) -> void:
	var now := Time.get_ticks_msec()
	for i in range(entries.size() - 1, maxi(-1, entries.size() - 1 - DEDUPE_DEPTH), -1):
		var e: Dictionary = entries[i]
		if e.text == text and now - e.seen <= DEDUPE_SECS * 1000.0:
			e.count += 1
			e.seen = now
			entries.remove_at(i)
			entries.append(e) # a repeat moves back to the newest line
			_dirty = true
			return
	entries.append({"text": text, "tier": tier, "color": col, "count": 1, "seen": now})
	while entries.size() > FEED_MAX:
		entries.pop_front()
	_dirty = true


func _colour(tier: int) -> Color:
	if tier == 1:
		return GOLD
	if tier == 3:
		return GREY
	var f: Faction = player.body.faction
	if f and f.kingdom:
		return f.kingdom.color.lightened(0.35)
	if f and not f.solo:
		return f.color.lightened(0.35)
	return NO_SIDE


## Short second-person lines for tier 1 and 2; the sim's own log text otherwise.
func _format(ev: Dictionary, tier: int) -> String:
	var me := player.body
	var i: int = ev.actors.find(me.id)
	var other := ""
	for j in ev.names.size():
		if j != i:
			other = ev.names[j]
			break
	var g0: String = ev.gnames[0] if ev.gnames.size() > 0 else ""
	var g1: String = ev.gnames[1] if ev.gnames.size() > 1 else ""
	match tier:
		1:
			match ev.kind:
				&"invite": return ("%s's invite runs out. You don't join." if ev.n == 1 else "You turn down %s's invite.") % other
				&"gang_refused": return ("%s's gang offer runs out. You don't join." if ev.n == 1 else "You refuse to run with %s.") % other
				&"demand": return ("%s demands your goods. You don't answer, and they attack!" if ev.n == 1 else "%s demands your goods. You refuse and fight back!") % other
				&"fight": return ("%s attacks you! You fight back." % other) if i == 1 else ("You attack %s." % other)
				&"hit": return ("%s hits you" % other) if i == 1 else ("You hit %s" % other)
				&"killed": return ("%s killed you." % other) if i == 1 else ("You killed %s." % other)
				&"robbed": return ("%s robbed you: %d items." % [other, ev.n]) if i == 1 else ("You take %d items from %s." % [ev.n, other])
				&"plead": return ("You refuse %s's plea." % other) if i == 1 else ("You beg %s for mercy." % other)
				&"surrender": return ("%s surrenders to you." % other) if i == 1 else ("You surrender to %s." % other)
				&"servant": return ("%s is now your servant." % other) if i == 1 else ("You are now %s's servant." % other)
				&"freed": return "You are a free agent again."
				&"group_form": return "You and %s form %s." % [other, g0]
				&"group_join": return "You join %s." % g0
				&"group_leave": return "You leave %s." % g0
				&"leader": return "You now lead %s." % g0
				&"king": return "You are now king of %s." % g0
				&"tax": return "%s taxes your group: %d items taken." % [g1, ev.n]
				&"tax_refused": return "Your group refuses %s's tax: war!" % g1
				&"takeover", &"respawn": return ev.text # already written for you (phase 6)
			if String(ev.kind).begins_with("p_"):
				return ev.text # player-social lines are written for you (Player Social Plan)
			return _you(ev.text, me.short())
		2:
			match ev.kind:
				&"leader": return "%s now leads your group (%s)." % [other, g0]
				&"king": return "%s is now king of your kingdom (%s)." % [other, g0]
				&"kingdom_form": return "Your group forms the kingdom of %s." % g0
				&"kingdom_join": return "Your group joins the kingdom of %s." % g1
				&"kingdom_leave": return "Your group leaves %s." % g1
				&"kingdom_dissolve": return "Your kingdom (%s) dissolves." % g0
				&"scatter":
					if ev.kids.size() > 0 and me.faction.kingdom and ev.kids[0] == me.faction.kingdom.id:
						return "Your kingdom (%s) is broken! Everyone scatters." % g0
					return "Your kingdom breaks %s!" % g0
			return ev.text
	if ev.text != "":
		return ev.text
	if ev.kind == &"fight" and ev.names.size() == 2:
		return "%s attacks %s." % [ev.names[0], ev.names[1]]
	return ""


## Fallback for tier 1 lines without a template: the log text with your name as "you".
static func _you(text: String, who: String) -> String:
	if text.begins_with(who + " "):
		text = "You" + text.substr(who.length())
	return text.replace(who + "'s", "your").replace(who, "you")


func _process(dt: float) -> void:
	visible = player != null and player.body != null
	if not visible:
		return
	_refresh -= dt
	if not _dirty and _refresh > 0.0:
		return
	_refresh = 0.25
	_dirty = false
	var now := Time.get_ticks_msec()
	while not entries.is_empty() and now - entries[0].seen > (FEED_LIFE + FEED_FADE) * 1000.0:
		entries.pop_front()
	var out: Array[String] = []
	for e in entries:
		var age: float = (now - e.seen) / 1000.0
		var c: Color = e.color
		c.a = clampf(1.0 - (age - FEED_LIFE) / FEED_FADE, 0.0, 1.0)
		var line: String = e.text.replace("[", "[lb]")
		if e.count > 1:
			line += "  x%d" % e.count
		out.append("[color=#%s]%s[/color]" % [c.to_html(true), line])
	_label.text = "\n".join(out)
