extends RefCounted
## Scripted check of the PlayerController (`-- --playtest`, headless or windowed): sets the
## controller's intents the way input would and steps the real sim at 60 steps / s, then
## prints PASS / FAIL per feature. Windowed, it also saves screenshots to user://.

var _main: Node
var _pc: PlayerController
var _fails := 0
var _shots := false


func run(main: Node, pc: PlayerController, cam: Node) -> void:
	_main = main
	_pc = pc
	_shots = DisplayServer.get_name() != "headless"
	pc.scripted = true
	SimClock.paused = true # Main stops stepping; this script steps the sim itself
	await main.get_tree().process_frame
	var a := pc.body
	var site := _open_site(a.cell())
	_check(site != World.NO_CELL, "found an open test site")
	a.pos = World.center(site)
	cam.position = a.pos * Cfg.CELL
	pc.aim_point = a.pos + Vector2.RIGHT * 5.0

	# 1. Snappy acceleration and speed.
	var start := a.pos
	pc._move_in = Vector2.RIGHT
	_steps(3)
	_check(absf(pc.vel.x - a.speed()) < 0.01, "full speed after 0.05 s (vel %.2f, speed %.2f)" % [pc.vel.x, a.speed()])
	_steps(57)
	var dx := a.pos.x - start.x
	_check(dx > a.speed() * 0.9, "walked %.2f cells in 1 s at speed %.2f" % [dx, a.speed()])
	pc._move_in = Vector2.ZERO
	_steps(3)
	_check(pc.vel == Vector2.ZERO, "stops within 0.05 s")

	# 2. Walls block, and the body slides along them.
	var c := a.cell()
	var wx := c.x + 2
	for y in range(c.y - 3, c.y + 4):
		World.place_wall(Vector2i(wx, y), false, 0)
	pc._move_in = Vector2.RIGHT
	_steps(60)
	_check(a.pos.x <= wx - Actions.PLAYER_HALF + 0.01 and a.pos.x > wx - Actions.PLAYER_HALF - 0.05, "stopped at the wall (x %.3f, wall at %d)" % [a.pos.x, wx])
	var y0 := a.pos.y
	pc._move_in = Vector2(1, 1).normalized()
	_steps(30)
	_check(a.pos.y - y0 > 0.5 and a.pos.x <= wx - Actions.PLAYER_HALF + 0.01, "slid along the wall (dy %.2f)" % (a.pos.y - y0))
	pc._move_in = Vector2.ZERO
	_steps(5)
	await _shot("playtest_walls")

	# 3. Placing a wall by hand: costs, zones, not on yourself.
	a.inv.add("wood", 6)
	var wood := a.inv.count("wood")
	pc.build_piece = "wall"
	pc.hover_cell = a.cell() + Vector2i(-2, 0)
	pc.aim_point = World.center(pc.hover_cell)
	await _shot("playtest_build")
	pc._place = true
	_steps(1)
	var w: Wall = World.walls.get(a.cell() + Vector2i(-2, 0))
	_check(w != null and w.owner_id == a.faction.id and a.inv.count("wood") == wood - 2, "placed a wall for 2 wood")
	pc.hover_cell = a.cell()
	pc._place = true
	_steps(1)
	_check(not World.walls.has(a.cell()), "refused to build on the player's own cell (%s)" % pc.message)
	pc.hover_cell = a.cell() + Vector2i(-8, 0)
	pc._place = true
	_steps(1)
	_check(not World.walls.has(a.cell() + Vector2i(-8, 0)), "refused to build out of reach (%s)" % pc.message)
	pc.build_piece = ""

	# 4. Hold E to harvest a tree.
	var tree := World.nearest_node(ResourceNode.Type.TREE, a.cell(), 60.0)
	var spot := World.NO_CELL
	if tree:
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if World.is_walkable(tree.cell + d):
				spot = tree.cell + d
				break
	_check(spot != World.NO_CELL, "found a tree to harvest")
	if spot != World.NO_CELL:
		a.pos = World.center(spot)
		cam.position = a.pos * Cfg.CELL
		pc.aim_point = World.center(tree.cell)
		wood = a.inv.count("wood")
		var secs: float = Actions.harvest_secs(a, tree)[0]
		pc._harvest_held = true
		_steps(int(ceil(secs * 2.0 * 60.0)) + 2)
		await _shot("playtest_harvest")
		pc._harvest_held = false
		_check(a.inv.count("wood") - wood == 2, "harvested 2 wood in %.1f s (got %d)" % [secs * 2.0, a.inv.count("wood") - wood])

	# 4b. Interaction panels (phase 4): craft at a machine and stock a chest, all through
	# the panels' buttons.
	await _panels(a, cam)
	await _mailbox_checks(a, cam)
	_inventory_access_checks(a, cam)

	# 5. Fight: swing at an NPC in front; it fights back. The player gets a sword so the
	# rest of the test usually survives (an unarmed player tends to lose).
	_slots(a)
	a.inv.add_tool("sword")
	pc.select_slot(a.inv.slot_of(a.inv.get_tool("sword")))
	_steps(1)
	_check(a.melee_weapon() == "sword", "the sword is in hand (hotbar slot %d)" % (pc.held + 1))
	var foe: Agent = null
	for o in World.agent_list:
		if o != a and not World.same_side(o.faction.id, a.faction.id) and (foe == null or World.dist(o.pos, a.pos) < World.dist(foe.pos, a.pos)):
			foe = o
	a.pos = World.center(site) + Vector2(0, 2)
	foe.pos = a.pos + Vector2(1.0, 0.0)
	Brain.set_job(foe, null)
	cam.position = a.pos * Cfg.CELL
	var foe_hp := foe.hp
	var my_hp := a.hp
	pc.aim_point = foe.pos
	pc._swing_t = 0.25
	_steps(1)
	_check(foe.hp < foe_hp, "a swing in the facing direction hit (%.0f -> %.0f HP)" % [foe_hp, foe.hp])
	var reaction: String = Job.Kind.keys()[foe.job.kind] if foe.job else "none"
	_check(foe.job != null and foe.job.target_id == a.id and foe.job.kind in [Job.Kind.FIGHT, Job.Kind.FLEE], "the NPC reacts: %s" % reaction)
	await _shot("playtest_swing")
	# A swing facing away misses.
	foe_hp = foe.hp
	_steps(70)
	pc.aim_point = a.pos - Vector2(3, 0)
	pc._swing_t = 0.25
	_steps(1)
	_check(foe.hp >= foe_hp - 0.01 or foe.hp > foe_hp - 1.0, "a swing facing away missed")
	var killed := false
	var fought_back := false
	for i in 60 * 40:
		if not foe.alive or not a.alive:
			break
		pc.aim_point = foe.pos
		var gap := World.delta(a.pos, foe.pos)
		pc._move_in = gap.normalized() if gap.length() > 1.1 else Vector2.ZERO # chase
		if a.attack_cd <= 0.0 and gap.length() <= 1.5:
			pc._swing_t = 0.25
		_steps(1)
		fought_back = fought_back or a.hp < my_hp
	pc._move_in = Vector2.ZERO
	killed = not foe.alive
	print("    fight: NPC %s, player HP %.0f -> %.0f" % ["fought back" if fought_back else "never landed a hit", my_hp, a.hp])
	print("    fight result: %s (player HP %.0f, kills %d)" % ["NPC killed" if killed else ("player died" if not a.alive else "no kill in 40 s"), a.hp, a.kills])

	if a.alive:
		# 6. Social prompts (Player Social Plan §3), then the demand default (§5, until phase 4).
		await _social_checks(a)
		var other := _free_npc(a)
		if other:
			Social._demand(other, a, false)
			pc.offers.answer(false)
			_steps(1)
			_check(other.job != null and other.job.kind == Job.Kind.FIGHT and other.job.target_id == a.id, "refused a demand: the NPC attacks")
			Brain.set_job(other, null)
		await _feed_checks(a)
		# 7. Watch mode: the AI drives the body, then hands it back.
		pc.set_watching(true)
		_steps(60)
		_check(a.controller == null and a.last_think > 0.0, "watch mode: the AI thinks for the body")
		pc.set_watching(false)
		_check(a.controller == pc and a.job == null, "back from watch mode: the player drives again")
		# 8. The base fire (Player Group Base Plan); it runs sim time, so it goes last.
		await _base_fire_checks(a, cam)
		_round2_main_checks(a)
		_door_side_checks(a)
	await _death_tests(main)
	print("PLAYTEST %s (%d failed)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	_main.get_tree().quit()


## Player Group Base Plan R1 and R7: an NPC meeting the player doesn't use up the player's
## invite cooldown; a refused invite can be retried after 10 s; hemp and mailboxes don't
## block walking but still block building. No sim time.
func _round2_main_checks(a: Agent) -> void:
	_solo(a)
	var t := _free_npc(a)
	if t == null:
		_check(false, "found an NPC for the cooldown checks")
		return
	t.pos = a.pos + Vector2(1.5, 0)
	t.mood = 60.0
	t.cooldowns.erase(a.id)
	a.action_cooldowns.erase(t.id)
	Brain.set_job(t, null)
	Social.scan(t)
	_check(not "Ask again" in Social.player_why(a, t, &"invite"), "an NPC meeting the player leaves the player's invite open: %s" % Social.player_why(a, t, &"invite"))
	t.stats.auth = a.stats.auth + 5 # outranks the player: always refuses
	var said := Social.player_act(a, t, &"invite")
	var wait: float = a.action_cooldowns.get(t.id, 0.0) - SimClock.time
	_check("less standing" in said and wait > 0.0 and wait <= Cfg.PLAYER_INVITE_RETRY + 0.01, "a refused invite can be retried after %.0f s" % wait)
	# Hemp: walk through, can't build on it.
	var hemp: ResourceNode = null
	for n in World.nodes.values():
		if n.type == ResourceNode.Type.HEMP:
			hemp = n
			break
	if hemp:
		_check(World.passable(a, hemp.cell) and not World.astar.is_point_solid(hemp.cell), "hemp doesn't block walking or paths")
		_check(not World.can_build(hemp.cell, a.faction.id), "hemp still blocks building")
	else:
		print("    (no hemp on the map to test)")
	# Mailbox: walk through, can't build on it.
	var c := World.random_walkable_near(a.cell() + Vector2i(4, 4), 3)
	if c != World.NO_CELL and not World.furniture.has(c):
		var mb := World.place_furniture(c, Furniture.Kind.MAILBOX, a.faction.id, null)
		_check(World.passable(a, c) and not World.astar.is_point_solid(c), "a mailbox doesn't block walking or paths")
		_check(not World.can_build(c, a.faction.id), "a mailbox still blocks building")
		World.remove_furniture(mb)


## Social feed (Player Controller Plan §5.1): which tier an event lands in, and what never
## shows. Uses the real sim calls (Social, Combat.start_fight, Factions.join / leave).
func _feed_checks(a: Agent) -> void:
	var feed = _main._feed
	_check(feed != null and EventBus.feed_on, "the social feed listens to the sim")
	if feed == null:
		return
	feed.entries.clear()
	# Tier 1: a join request the placeholder refuses, and a refused demand.
	var other: Agent = null
	for o in World.agent_list:
		if o != a and o.faction.solo and o.alive and not o.in_combat():
			other = o
			break
	if other:
		Social._demand(other, a, false)
		_pc.offers.answer(false)
		_steps(1)
		_check(_has(feed, 1, "demands your goods"), "feed: the refused demand is tier 1: %s" % _last(feed))
		Brain.set_job(other, null)
	# Tier 3: a fight between two NPCs a few cells away.
	var pair := _two_npcs(a, func(o): return o.faction.solo)
	if pair.size() == 2:
		pair[0].pos = a.pos + Vector2(4, 0)
		pair[1].pos = a.pos + Vector2(5, 0)
		var n: int = feed.entries.size()
		Combat.start_fight(pair[0], pair[1])
		_check(feed.entries.size() > n and feed.entries.back().tier == 3 and pair[1].short() in feed.entries.back().text,
			"feed: a fight %.0f cells away is tier 3 (grey): %s" % [World.dist(a.pos, pair[1].pos), _last(feed)])
		feed.show_nearby = false
		n = feed.entries.size()
		Combat.start_fight(pair[1], pair[0])
		_check(feed.entries.size() == n, "feed: the debug toggle hides tier 3")
		feed.show_nearby = true
		for o in pair:
			Brain.set_job(o, null)
	# Joining a group is tier 1; a groupmate being attacked far away is not shown.
	var group: Faction = null
	for f in World.factions.values():
		if not f.solo and f.has_room() and f.kingdom == null and not f.is_gang():
			group = f
			break
	_check(group != null, "found a group for the player to join")
	if group:
		Factions.join(a, group)
		_check(a.faction == group and _has(feed, 1, "You join %s" % group.name), "feed: joining a group is tier 1: %s" % _last(feed))
		var mate: Agent = null
		for mid in group.members:
			if mid != a.id and World.agents.has(mid):
				mate = World.agents[mid]
				break
		var foe := _two_npcs(a, func(o): return o.faction != group and not World.same_side(o.faction.id, group.id))
		if mate and not foe.is_empty():
			mate.pos = a.pos + Vector2(FEED_FAR, 0) if a.pos.x + FEED_FAR < Cfg.MAP_W else a.pos - Vector2(FEED_FAR, 0)
			foe[0].pos = mate.pos + Vector2(0, 1)
			var n: int = feed.entries.size()
			Combat.start_fight(foe[0], mate)
			_check(feed.entries.size() == n, "feed: a groupmate attacked %.0f cells away is not shown" % World.dist(a.pos, mate.pos))
			Brain.set_job(foe[0], null)
			Brain.set_job(mate, null)
		Factions.leave(a)
		Factions.make_solo(a)
		_check(a.faction.solo and _has(feed, 1, "You leave %s" % group.name), "feed: leaving the group is tier 1: %s" % _last(feed))
	# Spam collapses: the same line again within a few seconds counts up.
	feed.add_line("Bram hits you", 1, feed.GOLD)
	feed.add_line("Bram hits you", 1, feed.GOLD)
	feed.add_line("Bram hits you", 1, feed.GOLD)
	_check(feed.entries.back().count == 3, "feed: repeats collapse (x%d)" % feed.entries.back().count)
	await _shot("playtest_feed")
	print("    feed now:")
	for e in feed.entries:
		print("      [tier %d] %s%s" % [e.tier, e.text, ("  x%d" % e.count) if e.count > 1 else ""])


const FEED_FAR := 40.0 # cells: well outside the feed's "nearby" radius


func _has(feed, tier: int, part: String) -> bool:
	for e in feed.entries:
		if e.tier == tier and part in e.text:
			return true
	return false


func _last(feed) -> String:
	return "\"%s\"" % feed.entries.back().text if not feed.entries.is_empty() else "(empty)"


## Two living, idle NPCs (not the player) that pass `ok`.
## A solo NPC free to talk: alive, not fighting, not a servant.
func _free_npc(a: Agent, skip: Agent = null) -> Agent:
	for o in World.agent_list:
		if o != a and o != skip and o.alive and o.faction.solo and not o.in_combat() and not o.is_servant() and o.controller == null:
			return o
	return null


## Player Social Plan §3 and §5: invites and gang offers ask the player through the prompt;
## decline, timeout and accept (by clicking the button) each do the right thing; groupmates
## defend the player; the hover pick finds the character under the mouse.
func _social_checks(a: Agent) -> void:
	var pc := _pc
	var feed = _main._feed
	var prompt = _main._prompt
	# Start solo: the fight test may have left the player with a servant (which makes a group).
	for sid in a.servants.duplicate():
		var s: Agent = World.agents.get(sid)
		if s:
			Factions.free_agent(s)
	if not a.faction.solo:
		Factions.leave(a)
		Factions.make_solo(a)
	pc.offers.clear() # NPCs may have asked the player something during the earlier tests
	var other := _free_npc(a)
	_check(other != null, "found a solo NPC to talk to")
	if other == null:
		return
	other.pos = a.pos + Vector2(2, 0)
	a.mood = 60.0
	other.mood = 60.0
	# NPCs never invite the player (Player Group Plan D4): a happy meeting asks nothing
	# and doesn't pull the player into a group.
	Social._happy_meets(other, a)
	_check(not pc.offers.has_from(other.id) and a.faction.solo, "a happy NPC doesn't invite the player")
	# The one ask left is the gang ask (D2). Decline it.
	other.mood = -60.0
	a.mood = -60.0
	Social._angry_meets(other, a)
	var o: Dictionary = pc.offers.current()
	_check(o.get("kind", &"") == &"gang" and o.get("from_id", -1) == other.id, "a gang ask asks the player instead of refusing")
	_check(other.job != null and other.job.kind == Job.Kind.IDLE and other.job.item == Social.WAIT_ANSWER, "the asker waits for the answer")
	await _main.get_tree().process_frame
	_check(prompt._panel.visible and prompt._yes.text == "[F1] Join" and other.short() in prompt._text.text, "the prompt card shows the gang ask: %s" % prompt._text.get_parsed_text())
	pc.hover_id = other.id
	if _shots:
		await _seconds(0.3) # let the card fade in
	await _shot("playtest_prompt")
	pc.hover_id = -1
	pc.offers.answer(false)
	_steps(1)
	_check(a.faction.solo and not pc.offers.has_from(other.id), "declining keeps the player solo")
	_check(_has(feed, 1, "You refuse to run with %s" % other.short()), "feed: the declined gang ask is tier 1: %s" % _last(feed))
	_check(other.job == null or other.job.item != Social.WAIT_ANSWER, "the asker stops waiting")
	_calm(a, other)
	# Timeout: the default rule (refuse).
	other.mood = -60.0
	a.mood = -60.0
	Social._angry_meets(other, a)
	_check(pc.offers.has_from(other.id), "a second gang ask is queued")
	a.hp = Cfg.MAX_HP
	other.set_cooldown(a.id, 60.0) # the angry asker would otherwise rob the player while waiting
	_steps(int(Cfg.OFFER_SECS_GANG * 60.0) + 5)
	if not a.alive or a.faction == null:
		_check(false, "the player survives the gang-ask timeout (hp %.0f, feed %s)" % [a.hp, _last(feed)])
		for e in feed.entries.slice(-8):
			print("      [tier %d] %s" % [e.tier, e.text])
		return
	_check(a.faction.solo and not pc.offers.has_from(other.id) and _has(feed, 1, "gang offer runs out"),
		"an unanswered gang ask runs out and is refused: %s" % _last(feed))
	_calm(a, other)
	a.mood = 60.0
	# Invite (D1): the player founds the group and leads it.
	if not other.alive or other.in_combat() or not other.faction.solo:
		other = _free_npc(a)
	if other:
		other.pos = a.pos + Vector2(2, 0)
		other.mood = 60.0
		other.change_opinion(a.id, 60.0)
		_below(other, a)
		Social._player_invite(a, other)
		_check(not a.faction.solo and a.faction == other.faction and a.faction.player_led and a.faction.leader_id == a.id,
			"inviting %s founds the player's group, led by the player" % other.short())
		# Groupmates defend the player (agreed 2026-11-24).
		var foe := _free_npc(a, other)
		if foe and not a.faction.solo:
			Brain.set_job(other, null)
			other.hp = Cfg.MAX_HP
			other.pos = a.pos + Vector2(1, 0)
			foe.pos = a.pos + Vector2(0, 2)
			Combat.start_fight(foe, a)
			_check(other.job != null and other.job.kind == Job.Kind.FIGHT and other.job.target_id == foe.id, "a groupmate defends the player")
			Brain.set_job(foe, null)
			Brain.set_job(other, null)
			Brain.set_job(a, null)
		if not a.faction.solo:
			_rank_checks(a, other)
		_solo(a)
	# Gang offer (angry player), accepted.
	var g := _free_npc(a)
	if g:
		g.pos = a.pos + Vector2(-2, 0)
		g.mood = -60.0
		a.mood = -60.0
		g.stats.auth = a.stats.auth + 3 # D2: in an NPC's gang, rank decides who leads
		Social._angry_meets(g, a)
		_check(pc.offers.current().get("kind", &"") == &"gang", "an angry NPC asks the angry player to run as a gang")
		await _main.get_tree().process_frame
		for x in [a, g]: # a passer-by may have started a fight during the frame
			if x.in_combat():
				Brain.set_job(x, null)
		prompt._yes.pressed.emit()
		pc.offers.step(a) # apply it now: a full sim step lets passers-by pick a fight with the angry pair first
		_check(not a.faction.solo and a.faction == g.faction, "clicking Join on the gang ask joins %s (%s)" % [g.short(), pc.message])
		_check(not a.faction.player_led and a.faction.leader_id == g.id, "in an NPC's gang the higher-ranked NPC leads (%d)" % a.faction.leader_id)
		Factions.leave(a)
		Factions.make_solo(a)
		a.mood = 60.0
		# Hover: the character nearest the mouse within reach, never the player's own body.
		g.pos = a.pos + Vector2(3, 0)
		_steps(1) # files g under its new position in the spatial index
		g.pos = a.pos + Vector2(3, 0)
		_check(pc.pick_agent(g.pos + Vector2(0.3, 0.2)) == g, "the hover pick finds the character under the mouse")
		_check(pc.pick_agent(a.pos) != a, "the hover pick skips the player's own body")
	_check(_overlay_words(), "hover card words: mood and opinion")
	await _prompt_checks_4(a)
	await _radial_checks(a)


## Stops any fight, wait or open ask between the player and `o` (a refused ask may start a fight).
func _calm(a: Agent, o: Agent) -> void:
	if _pc.offers.has_from(o.id):
		_pc.offers.clear()
	Brain.set_job(o, null)
	Brain.set_job(a, null)
	o.death_match.erase(a.id)
	a.death_match.erase(o.id)


## `t` ranks below the player (lower AUTH), so an invite isn't refused on rank (D6).
func _below(t: Agent, a: Agent) -> void:
	if a.stats.auth < 2:
		a.stats.auth = 2
	t.stats.auth = a.stats.auth - 1
	a.set_cooldown(t.id, 0.0)
	a.set_action_cooldown(t.id, 0.0)
	t.set_cooldown(a.id, 0.0)
	Brain.set_job(t, null)


## Player Group Plan D1, D3, D6, with the player leading a group with `mate`: a higher-ranked
## NPC refuses the invite; one that joins anyway doesn't take over; the player is king.
func _rank_checks(a: Agent, mate: Agent) -> void:
	var f := a.faction
	var h := _free_npc(a, mate)
	if h == null:
		_check(false, "found an NPC for the rank checks")
		return
	h.pos = a.pos + Vector2(-1.5, 0)
	h.mood = 60.0
	h.change_opinion(a.id, 60.0)
	Brain.set_job(h, null)
	h.stats.auth = a.stats.auth + 3
	a.set_cooldown(h.id, 0.0)
	a.set_action_cooldown(h.id, 0.0)
	h.set_cooldown(a.id, 0.0)
	_check(Social.player_why(a, h, &"invite") == "", "invite stays open on someone who outranks you: %s" % Social.player_why(a, h, &"invite"))
	_pc._social = [&"invite", h.id]
	_steps(1)
	_check(h.faction.solo and "less standing" in _pc.message, "a higher-ranked NPC refuses the invite: %s" % _pc.message)
	Factions.join(h, f)
	_check(h.faction == f and f.leader_id == a.id, "the player still leads after higher-AUTH %s joins (leader %d)" % [h.short(), f.leader_id])
	# Kingdom: an NPC group with far more AUTH; the player's group still leads it (D3).
	var x := _free_npc(a, h)
	var y: Agent = _free_npc(a, x) if x else null
	if x == null or y == null:
		_check(false, "found two NPCs for the kingdom check")
		return
	x.stats.auth = a.stats.auth + 10
	y.stats.auth = a.stats.auth + 10
	var g2 := Factions.form(x, y)
	var k := Kingdoms.form(f, g2)
	_check(k.king_id == a.id and k.leading_fid == f.id, "the player is king of %s (king %d, leading %d)" % [k.name, k.king_id, k.leading_fid])
	Kingdoms.recompute(k)
	_check(k.king_id == a.id, "the player stays king on a recompute")
	Kingdoms.dissolve(k)


## Makes `t` a pushover for a demand: neutral, slow, weak (so it doesn't talk you down,
## run or stand up), carrying 10 stone.
func _pushover(a: Agent, t: Agent) -> void:
	t.pos = a.pos + Vector2(1.5, 0)
	t.mood = 0.0
	t.stats.agi = 1
	t.hp = 40.0
	for k in Items.STACKABLES: # only the stone, so the demand drops exactly 5 of it
		t.inv.remove(k, t.inv.count(k))
	t.inv.add("stone", 10)
	Brain.set_job(t, null)
	a.set_cooldown(t.id, 0.0)
	a.set_action_cooldown(t.id, 0.0)
	t.set_cooldown(a.id, 0.0)


## Phase 4: demands and pleas ask the player (Player Social Plan §3.1).
func _prompt_checks_4(a: Agent) -> void:
	var pc := _pc
	var feed = _main._feed
	pc.offers.clear()
	# Demand: hand over.
	var d := _free_npc(a)
	if d == null:
		_check(false, "found an NPC to make demands")
		return
	d.pos = a.pos + Vector2(2, 0)
	a.inv.remove("wood", a.inv.count("wood"))
	a.inv.add("wood", 10)
	Social._demand(d, a, false)
	_check(pc.offers.current().get("kind", &"") == &"demand", "a demand asks the player (and jumps the queue)")
	_check(d.job != null and d.job.kind == Job.Kind.IDLE and d.job.prio == Job.PRIO_NEEDS, "the robber holds its ground for the answer")
	pc.offers.answer(true)
	_steps(1)
	_check(a.inv.count("wood") == 5 and _has(feed, 1, "You hand"), "handing over gives up half (wood 10 -> %d): %s" % [a.inv.count("wood"), _last(feed)])
	# Demand: no answer means a refusal and a fight.
	Social._demand(d, a, false)
	_steps(int(Cfg.OFFER_SECS_DEMAND * 60.0) + 5)
	_check(not pc.offers.has_from(d.id) and d.job != null and d.job.kind == Job.Kind.FIGHT and d.job.target_id == a.id,
		"an unanswered demand is a refusal: the NPC attacks")
	_check(_has(feed, 1, "You don't answer"), "feed: the unanswered demand: %s" % _last(feed))
	Brain.set_job(d, null)
	Brain.set_job(a, null)
	# Plea: spare.
	var v := _free_npc(a, d)
	if v == null:
		return
	v.pos = a.pos + Vector2(1, 0)
	v.hp = Cfg.MAX_HP * Cfg.PLEAD_HP + 5.0
	Combat.apply_damage(v, 10.0, a)
	_check(pc.offers.current().get("kind", &"") == &"plead" and pc.offers.current().from_id == v.id, "a beaten NPC begs the player (prompt)")
	_check(v.job != null and v.job.kind == Job.Kind.IDLE and v.job.prio == Job.PRIO_CRITICAL, "the pleading NPC stops fighting")
	_check(_has(feed, 1, "begs you for mercy"), "feed: the plea: %s" % _last(feed))
	pc.offers.answer(true)
	_steps(1)
	_check(v.master_id == a.id or _has(feed, 1, "spares"), "sparing makes %s your servant (master %d)" % [v.short(), v.master_id])
	# Plea: hitting them again finishes it.
	var v2 := _free_npc(a, v)
	if v2:
		v2.pos = a.pos + Vector2(-1, 0)
		v2.hp = Cfg.MAX_HP * Cfg.PLEAD_HP + 5.0
		Combat.apply_damage(v2, 10.0, a)
		_check(pc.offers.has_from(v2.id), "a second NPC begs")
		Combat.apply_damage(v2, 1.0, a)
		_check(not pc.offers.has_from(v2.id) and v2.job != null and v2.job.kind == Job.Kind.FIGHT and v2.job.to_death,
			"hitting a pleading NPC finishes it: a fight to the death")
		_check(_has(feed, 1, "You refuse %s's plea" % v2.short()), "feed: the refused plea: %s" % _last(feed))
		Brain.set_job(v2, null)
		v2.death_match.erase(a.id)
		a.death_match.erase(v2.id)
	# Plea: no answer, the usual roll decides.
	var v3 := _free_npc(a, v2)
	if v3:
		v3.pos = a.pos + Vector2(0, 1)
		v3.hp = Cfg.MAX_HP * Cfg.PLEAD_HP + 5.0
		Combat.apply_damage(v3, 10.0, a)
		_steps(int(Cfg.OFFER_SECS_PLEAD * 60.0) + 5)
		var spared := v3.master_id == a.id or (v3.job != null and v3.job.kind == Job.Kind.FLEE)
		var fought := v3.job != null and v3.job.kind == Job.Kind.FIGHT and v3.job.to_death
		_check(not pc.offers.has_from(v3.id) and (spared or fought or not v3.alive), "an unanswered plea falls back to the 50/50 roll (%s)" % ("spared" if spared else "refused"))
		Brain.set_job(v3, null)
		v3.death_match.erase(a.id)
		a.death_match.erase(v3.id)
	_solo(a)


## Back to a solo player with no servants.
func _solo(a: Agent) -> void:
	for sid in a.servants.duplicate():
		var s: Agent = World.agents.get(sid)
		if s:
			Factions.free_agent(s)
	if not a.faction.solo:
		Factions.leave(a)
		Factions.make_solo(a)
	Brain.set_job(a, null)


## Phase 5: the radial menu's actions (Player Social Plan §4), through the same intent the
## menu sets; and the menu's direction pick.
func _radial_checks(a: Agent) -> void:
	var pc := _pc
	var feed = _main._feed
	var R = preload("res://ui/SocialRadial.gd")
	var n := Social.PLAYER_OPTIONS.size()
	var picks: bool = R.pick(Vector2.ZERO, Vector2(5, 5), n) == -1
	for i in n:
		picks = picks and R.pick(Vector2.ZERO, R.dir_of(i, n) * 60.0, n) == i
	_check(picks, "radial: the mouse direction picks the option (dead zone picks none)")
	var r: float = R.radius_for(n)
	var apart := true
	for i in n:
		var d: Vector2 = (R.dir_of(i, n) - R.dir_of((i + 1) % n, n)) * r
		apart = apart and (absf(d.x) >= R.BUBBLE.x or absf(d.y) >= R.BUBBLE.y)
	_check(apart, "radial: %d bubbles don't overlap (radius %.0f)" % [n, r])
	# Demand goods: a pushover drops half its stone at its feet and backs off.
	var t := _free_npc(a)
	if t == null:
		return
	_pushover(a, t)
	var cell := t.cell()
	_check(Social.player_why(a, t, &"demand") == "", "demand is available on a solo stranger")
	pc._social = [&"demand", t.id]
	_steps(1)
	var bag: LootBag = World.loot.get(cell)
	_check(bag != null and bag.stacks.get("stone", 0) == 5 and t.inv.count("stone") == 5, "demand: %s drops 5 stone at its feet (%s)" % [t.short(), pc.message])
	_check(_has(feed, 1, "%s drops" % t.short()) and _has(feed, 1, "5 stone"), "feed: the demand: %s" % _last(feed))
	_check(Social.player_why(a, t, &"invite").begins_with("Ask again"), "the pair cooldown greys out the next action: %s" % Social.player_why(a, t, &"invite"))
	if bag:
		World.loot.erase(cell)
	# Invite: a happy NPC that likes you joins.
	var u := _free_npc(a, t)
	if u:
		u.pos = a.pos + Vector2(0, 1.5)
		u.mood = 60.0
		u.change_opinion(a.id, 60.0)
		_below(u, a)
		pc._social = [&"invite", u.id]
		_steps(1)
		_check(not a.faction.solo and u.faction == a.faction, "invite: %s joins you (%s)" % [u.short(), pc.message])
		_check(Social.player_why(a, u, &"challenge") != "" and Social.player_why(a, u, &"trade") == "They're in your group.", "greyed: no challenging or trading with your own group")
		_solo(a)
	# Greyed reasons.
	var w := _free_npc(a, t)
	if w:
		w.pos = a.pos + Vector2(1, 1)
		w.mood = 0.0
		a.mood = 60.0
		a.set_cooldown(w.id, 0.0)
		a.set_action_cooldown(w.id, 0.0)
		_check(Social.player_why(a, w, &"recruit") == "Only angry people run gangs.", "greyed: recruiting needs you angry")
		_check(Social.player_why(a, w, &"trade") == "Trade is between groups.", "greyed: trade needs two groups")
		w.pos = a.pos + Vector2(20, 0)
		_check(Social.player_why(a, w, &"invite") == "Too far away.", "greyed: too far away")
	# The menu itself: open on a target, a greyed hover shows the reason, LMB confirms.
	var q := _free_npc(a, t)
	if q:
		q.pos = a.pos + Vector2(2, 0)
		a.set_cooldown(q.id, 0.0)
		a.set_action_cooldown(q.id, 0.0)
		q.set_cooldown(a.id, 0.0)
		pc.radial_id = q.id
		await _main.get_tree().process_frame
		var radial = _main._radial
		_check(radial._options.size() == 5 and not radial._options.any(func(x): return x.id == &"ask_join"),
			"the radial menu lists 5 options (no Ask to join) for %s" % q.short())
		if _shots:
			await _seconds(0.1)
		await _shot("playtest_radial")
		pc.close_radial()


static func _overlay_words() -> bool:
	var ov = preload("res://ui/SocialOverlay.gd")
	return ov.opinion_word(-60.0) == "Hostile" and ov.opinion_word(-20.0) == "Wary" and ov.opinion_word(0.0) == "Indifferent" 		and ov.opinion_word(40.0) == "Friendly"


func _two_npcs(a: Agent, ok: Callable) -> Array[Agent]:
	var out: Array[Agent] = []
	for o in World.agent_list:
		if o != a and o.alive and not o.in_combat() and ok.call(o):
			out.append(o)
			if out.size() == 2:
				break
	return out


## Phase 4: builds a finished workshop (sawmill, stone cutter, burning fire) with a chest for
## the player's faction, then cuts stone, saws a plank and handles, crafts a tier-2 pickaxe
## and stocks the chest, pressing the panels' buttons. Also: walking away and a hard hit
## close a panel, foreign chests are refused, and the build menu greys out what you can't afford.
func _panels(a: Agent, cam: Node) -> void:
	var panels: CanvasLayer = _main._panels
	var pc := _pc
	var site := _open_site(a.cell() + Vector2i(0, 24))
	_check(site != World.NO_CELL, "found a site for a test workshop")
	if site == World.NO_CELL:
		return
	var f := a.faction
	var h := House.new(f.id, Rect2i(site + Vector2i(-7, -2), Cfg.WORKSHOP_SIZE), 0, House.Kind.WORKSHOP)
	f.houses.append(h)
	for c in h.wall_cells:
		World.place_wall(c, false, f.id)
	World.place_wall(h.door_cell, true, f.id)
	for c in h.floor_cells:
		World.place_floor(c, f.id)
	h.fire = World.place_fire(h.fire_cell, true, f.id)
	for k in h.machine_cells:
		World.place_furniture(h.machine_cells[k], k, f.id, h)
	h.state = House.State.COMPLETE
	World.buildings_version += 1
	var p0 := h.interior.position
	var chest := World.place_furniture(p0 + Vector2i(0, 3), Furniture.Kind.CHEST, f.id, null)
	_check(h.operational(), "test workshop is operational")
	for k in ["wood", "stone", "plank", "handle", "cut_stone"]:
		a.inv.remove(k, a.inv.count(k))
	a.inv.add("wood", 3)
	a.inv.add("stone", 4)
	# Stone cutter: E opens it, "All" cuts until the stone runs out (2 batches of 5 s).
	a.pos = World.center(p0 + Vector2i(3, 1))
	cam.position = a.pos * Cfg.CELL
	pc.aim_point = World.center(p0 + Vector2i(4, 0))
	pc._use = 1
	_steps(1)
	var cutter: Furniture = h.machine(Furniture.Kind.CUTTER)
	_check(pc.station.open == cutter and panels.has_button("process:cut_stone:all"), "E opens the stone cutter panel")
	_check(panels.click("process:cut_stone:all"), "pressed: cut stone, all")
	_steps(int(2 * Items.PROCESS.cut_stone.secs * 60) + 5)
	await _shot("playtest_cutter")
	_check(a.inv.count("cut_stone") == 2 and a.inv.count("stone") == 0 and pc.station.job == "", "cut 2 stone blocks in 10 s, then stopped (out of stone)")
	# Walking out of reach closes the panel.
	pc._move_in = Vector2.LEFT
	for i in 120:
		if a.pos.x <= p0.x + 1.5:
			break
		_steps(1)
	pc._move_in = Vector2.ZERO
	_steps(5)
	_check(pc.station.open == null, "walking away closed the panel (%s)" % pc.message)
	# Sawmill: a plank, then handles, then craft the tier-2 pickaxe.
	pc.aim_point = World.center(p0)
	pc._use = 1
	_steps(1)
	var saw: Furniture = h.machine(Furniture.Kind.SAWMILL)
	_check(pc.station.open == saw and not panels.has_button("craft:pickaxe_t2"), "E opens the sawmill; the pickaxe is greyed out without the parts")
	panels.click("process:plank:1")
	_steps(int(Items.PROCESS.plank.secs * 60) + 3)
	panels.click("process:handle:1")
	_steps(int(Items.PROCESS.handle.secs * 60) + 3)
	_check(a.inv.count("plank") == 1 and a.inv.count("handle") == 2 and a.inv.count("wood") == 0, "sawed 1 plank and 2 handles from 3 wood")
	_check(panels.click("craft:pickaxe_t2"), "pressed: craft tier-2 pickaxe")
	_steps(1)
	await _shot("playtest_sawmill")
	_check(a.inv.has_tool("pickaxe_t2") and a.inv.count("cut_stone") == 0 and a.inv.count("plank") == 0 and a.inv.count("handle") == 1, "crafted a tier-2 pickaxe at the sawmill")
	# A hard hit closes the panel.
	a.hp -= Cfg.PANEL_CLOSE_HIT + 1.0
	_steps(1)
	_check(pc.station.open == null, "a hard hit closed the panel (%s)" % pc.message)
	a.hp = Cfg.MAX_HP
	# Chest (slot UI): opening it opens the inventory; right click moves the pickaxe and the
	# spare handle across; dragging takes the handle back into a chosen pack slot.
	a.pos = World.center(p0 + Vector2i(1, 2))
	pc.aim_point = World.center(chest.cell)
	pc.set_inventory(false)
	pc._use = 1
	_steps(1)
	_check(pc.station.open == chest and pc.inv_open, "E opens the chest, and the inventory with it")
	pc.request_quick("inv", a.inv.slot_of(a.inv.get_tool("pickaxe_t2")))
	pc.request_quick("inv", _slot_with(a.inv, "handle"))
	_steps(1)
	await _shot("playtest_chest")
	_check(chest.store.has_tool("pickaxe_t2") and chest.store.count("handle") == 1 and not a.inv.has_tool("pickaxe_t2") and a.inv.count("handle") == 0, "right click stocked the chest (%s)" % chest.store.summary())
	var free_slot := -1
	for i in range(Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS):
		if a.inv.entry(i) == null:
			free_slot = i
			break
	pc.request_move("chest", _slot_with(chest.store, "handle"), "inv", free_slot)
	_steps(1)
	_check(chest.store.count("handle") == 0 and a.inv.count("handle") == 1 and a.inv.entry(free_slot) != null, "dragged the handle back into pack slot %d" % free_slot)
	pc._use = -1
	_steps(1)
	_check(pc.station.open == null and not pc.inv_open, "E closes the chest, and the inventory it opened")
	# Someone else's chest is refused.
	var other_fid := -1
	for o in World.agent_list:
		if not World.same_side(o.faction.id, f.id):
			other_fid = o.faction.id
			break
	var foreign := World.place_furniture(p0 + Vector2i(4, 3), Furniture.Kind.CHEST, other_fid, null)
	var why: String = pc.station.try_open(a, foreign)
	_check(why == "" and pc.station.open == foreign, "a chest of another side opens for the player (R8: %s)" % why)
	pc.station.close("")
	World.remove_furniture(foreign)
	# Build menu: greyed out without wood, picks a piece with it.
	var menu: CanvasLayer = _main._build
	var wood := a.inv.count("wood")
	a.inv.remove("wood", wood)
	menu.toggle()
	menu._update()
	_check(menu.visible and menu._buttons["wall"].disabled and not menu.pick("wall") and pc.build_piece == "", "build menu greys out the wall without wood")
	a.inv.add("wood", wood + 2)
	menu._update()
	_check(menu.pick("wall") and pc.build_piece == "wall" and not menu.visible, "build menu picks the wall and closes")
	pc.build_piece = ""


## Mailbox group panel (package C): the ladder of a fresh group, E on an own mailbox opens
## all three tabs, a foreign one only Members and Faction.
func _mailbox_checks(a: Agent, cam: Node) -> void:
	var pc := _pc
	var ui: CanvasLayer = _main._mailbox
	var fresh := Faction.new(World.rng) # not registered: a group with no buildings yet
	fresh.solo = false
	var steps := Factions.ladder_status(fresh)
	var ids := steps.map(func(s): return s.id)
	var states := steps.map(func(s): return s.state)
	_check(ids == ["home", "stock", "workshop", "reinforce", "smeltery", "stone"], "ladder_status lists the six steps in order (%s)" % [ids])
	_check(states == ["in_progress", "locked", "locked", "locked", "locked", "locked"], "a fresh group is working on its home, the rest locked (%s)" % [states])
	# An own mailbox: put one by the test workshop's door (from _panels).
	var f := a.faction
	var h: House = null
	for x in f.houses:
		if x.is_workshop() and x.state == House.State.COMPLETE:
			h = x
	var mc := h.mailbox_site() if h else World.NO_CELL
	_check(mc != World.NO_CELL, "found a mailbox spot by the test workshop")
	if mc == World.NO_CELL:
		return
	var mb := World.place_furniture(mc, Furniture.Kind.MAILBOX, f.id, h)
	h.mailbox = mb
	pc.station.close("")
	a.pos = World.center(h.door_outside())
	cam.position = a.pos * Cfg.CELL
	pc.aim_point = World.center(mc)
	_steps(1)
	_check(preload("res://player/Station.gd").target(a) == mb, "E targets the mailbox")
	pc._use = 1
	_steps(1)
	await _frames(2)
	_check(pc.station.open == mb and ui.visible and ui.tabs().size() == 3, "E opens the mailbox panel with all three tabs")
	_check(ui.text().contains(a.short()), "Members lists the player")
	_check(ui.select_tab("faction") and ui.text().contains("Chest stock"), "Faction tab shows the chest stock")
	_check(ui.select_tab("command") and ui.text().contains("Stone tier"), "Command tab shows the ladder")
	await _shot("playtest_mailbox")
	pc._use = -1
	_steps(1)
	await _frames(1)
	_check(pc.station.open == null and not ui.visible, "E closes the mailbox panel")
	# A foreign mailbox opens too, read-only: no Command tab.
	var other: Faction = null
	for o in World.agent_list:
		if not o.faction.solo and not World.same_side(o.faction.id, f.id):
			other = o.faction
			break
	World.remove_furniture(mb)
	h.mailbox = null
	if other == null:
		print("    (no foreign group to test a foreign mailbox)")
		return
	var fm := World.place_furniture(mc, Furniture.Kind.MAILBOX, other.id, null)
	pc._use = 1
	_steps(1)
	await _frames(2)
	_check(pc.station.open == fm and ui.visible and ui.tabs() == ["members", "faction"] and not ui.select_tab("command"), "a foreign mailbox opens without the Command tab")
	pc._use = -1
	_steps(1)
	World.remove_furniture(fm)
	await _frames(1)


## Player Group Base Plan R2 and R8: Trade on a groupmate opens their gear and items move
## both ways (worn pieces, hotbar tools); another group's chest opens, putting in is free,
## taking is theft once per opening (relations drop, a watching owner attacks); an abandoned
## chest is free to loot. Moves run straight through InvMoves. No sim time and no random
## rolls, and every agent, group and relation is put back afterwards: anything that shifts
## the world here changes how the later checks (fights, deaths) play out.
func _inventory_access_checks(a: Agent, cam: Node) -> void:
	const IM := preload("res://player/InvMoves.gd")
	var pc := _pc
	var st = pc.station
	st.close("")
	pc.set_inventory(false)
	var start_pos := a.pos
	var snap := _snap_world()
	var f := a.faction
	var f_solo := f.solo
	var mate: Agent = null
	for o in World.agent_list:
		if o != a and o.alive and o.faction.solo and o.faction.houses.is_empty() and not o.in_combat() and not o.is_servant() and o.controller == null:
			mate = o
			break
	if mate == null:
		_check(false, "found an NPC for the groupmate gear checks")
		return
	# Into the player's group by hand (Factions.form / leave roll new groups from World.rng).
	var mf := mate.faction
	mf.members.erase(mate.id)
	f.members.append(mate.id)
	mate.faction = f
	f.solo = false
	mate.pos = a.pos + Vector2(1.5, 0.0)
	var trade: Dictionary = Social.player_options(a, mate).filter(func(o): return o.id == &"trade")[0]
	_check(trade.why == "" and Social.player_why(a, mate, &"trade") == "They're in your group.", "the radial offers Trade on a groupmate (%s)" % trade.why)
	pc._social = [&"trade", mate.id]
	pc.control(a, 0.0) # the controller's own step, without running the world

	_check(st.is_member() and st.member == mate and st.open == null, "Trade on a groupmate opens their gear (%s)" % pc.message)
	_check(_main._member != null and _main._member.box(IM.M_WORN, 0) != null, "the member panel has the groupmate's armour slots")
	# A worn piece both ways: the player's helmet onto them (worn to worn), back off them
	# into the player's pack (worn to pack).
	var head: String = Items.ARMOR[0]
	var old_mine = a.worn.get(head)
	var old_theirs = mate.worn.get(head)
	a.worn[head] = {"type": "helmet", "dur": Items.DURABILITY.get("helmet", 10)}
	mate.worn.erase(head)
	var helm = a.worn[head]
	_check(IM.move(a, st, IM.WORN, 0, IM.M_WORN, 0) and mate.worn.get(head) == helm and not a.worn.has(head), "moved the player's worn helmet onto the groupmate")
	var free := _free_pack_slot(a.inv)
	_check(IM.move(a, st, IM.M_WORN, 0, IM.INV, free) and a.inv.entry(free) == helm and not mate.worn.has(head), "took the groupmate's worn helmet into the player's pack")
	a.inv.take_slot(free)
	# A hotbar tool both ways: the player's hotbar slot 0 to theirs, and back.
	var tool := {"type": "axe", "dur": Items.DURABILITY.get("axe", 10)}
	var mine0 = a.inv.take_slot(0)
	var theirs0 = mate.inv.take_slot(0)
	a.inv.put_slot(0, tool)
	_check(IM.move(a, st, IM.INV, 0, IM.M_INV, 0) and mate.inv.entry(0) == tool and a.inv.entry(0) == null, "moved a hotbar tool to the groupmate's hotbar")
	_check(IM.quick(a, st, IM.M_INV, 0) and a.inv.slot_of(tool) >= 0 and mate.inv.entry(0) == null, "right click took the tool back from the groupmate (%s)" % a.inv.summary())
	a.inv.take_slot(a.inv.slot_of(tool))
	if mine0 != null:
		a.inv.put_slot(0, mine0)
	if theirs0 != null:
		mate.inv.put_slot(0, theirs0)
	if old_mine != null:
		a.worn[head] = old_mine
	if old_theirs != null:
		mate.worn[head] = old_theirs
	# Walking out of reach closes it; so does leaving the group.
	mate.pos = a.pos + Vector2(Cfg.SOCIAL_RANGE * 2.0, 0.0)
	st.step(a, 1.0 / 60.0)
	_check(not st.is_member() and st.why_closed != "", "the gear panel closes when the groupmate is out of reach (%s)" % st.why_closed)
	st.why_closed = ""
	mate.pos = a.pos + Vector2(1.5, 0.0)
	st.open_member(a, mate)
	f.members.erase(mate.id) # back to their own group
	mf.members.append(mate.id)
	mate.faction = mf
	f.solo = f_solo
	st.step(a, 1.0 / 60.0)
	_check(not st.is_member(), "the gear panel closes when they leave the group (%s)" % st.why_closed)
	st.why_closed = ""
	_restore_world(snap)

	# R8: another live group's chest by the player, with one of its members watching.
	var other: Faction = null
	for o in World.agent_list:
		if not o.faction.solo and not World.same_side(o.faction.id, a.faction.id) and o.alive and not o.in_combat():
			other = o.faction
			break
	var site := _open_site(a.cell())
	var c := site + Vector2i(1, 0)
	if other == null or site == World.NO_CELL or World.furniture.has(c):
		_check(false, "found a foreign group and a free cell for a test chest")
		a.pos = start_pos
		return
	a.pos = World.center(site)
	cam.position = a.pos * Cfg.CELL
	var w: Agent = World.agents.get(other.members[0])
	w.pos = a.pos + Vector2(-2.0, 0.0)
	var ch := World.place_furniture(c, Furniture.Kind.CHEST, other.id, null)
	ch.store.add("stone", 5)
	var rel0 := Relations.score(a.faction, other)
	_check(st.try_open(a, ch) == "" and st.open == ch, "another group's chest opens")
	_check(_main._panels.text().contains("theft"), "the panel says taking is theft")
	a.inv.add("wood", 2)
	var ws := _slot_with(a.inv, "wood")
	_check(IM.quick(a, st, IM.INV, ws) and ch.store.count("wood") >= 2 and Relations.score(a.faction, other) == rel0 and not w.in_combat(), "putting into it is free")
	_check(IM.quick(a, st, IM.CHEST, _slot_with(ch.store, "stone")) and a.inv.count("stone") >= 5, "took the stone out")
	var rel1 := Relations.score(a.faction, other)
	_check(rel1 < rel0, "theft drops relations with the owner (%.0f -> %.0f)" % [rel0, rel1])
	_check(w.job != null and w.job.kind == Job.Kind.FIGHT and w.job.target_id == a.id, "the owner's member who saw it attacks")
	IM.quick(a, st, IM.CHEST, _slot_with(ch.store, "wood"))
	_check(Relations.score(a.faction, other) == rel1, "a second take in the same opening costs nothing more")
	st.close("")
	World.remove_furniture(ch)
	a.inv.remove("stone", 5)
	a.inv.remove("wood", 2)
	_restore_world(snap) # undo the fight (and anyone who joined in) and the relations drop
	# An abandoned chest (owner 0): free to loot.
	var ab := World.place_furniture(c, Furniture.Kind.CHEST, 0, null)
	ab.store.add("stone", 3)
	var rel_before := Relations.score(a.faction, other)
	_check(st.try_open(a, ab) == "" and not st.is_theft(a) and _main._panels.text().contains("free"), "an abandoned chest opens, free to take")
	_check(IM.quick(a, st, IM.CHEST, _slot_with(ab.store, "stone")) and a.inv.count("stone") >= 3 and not st.stolen and Relations.score(a.faction, other) == rel_before, "looted the abandoned chest with no penalty")
	st.close("")
	World.remove_furniture(ab)
	a.inv.remove("stone", 3)
	_restore_world(snap)
	a.pos = start_pos
	cam.position = a.pos * Cfg.CELL


## Every agent's job, place, mood and memories, every group's relations and the fight count,
## to put back with _restore_world.
func _snap_world() -> Dictionary:
	var agents := {}
	for o in World.agent_list:
		var task = o.job.task if o.job and o.job.kind == Job.Kind.TASK and o.job.task else null
		agents[o] = {"job": o.job, "task": task, "claimed": task.claimed_by if task else -1,
			"path": o.path.duplicate(), "path_i": o.path_i, "think_t": o.think_t, "pos": o.pos,
			"mood": o.mood, "opinions": o.opinions.duplicate(), "death_match": o.death_match.duplicate(),
			"last_attacker": o.last_attacker, "cooldowns": o.cooldowns.duplicate(), "action_cooldowns": o.action_cooldowns.duplicate()}
	var rels := {}
	for fx in World.factions.values():
		rels[fx] = fx.relations.duplicate()
	return {"agents": agents, "rels": rels, "counts": World.social_counts.duplicate(), "sources": World.fight_sources.duplicate()}


func _restore_world(s: Dictionary) -> void:
	for o in s.agents:
		var x: Dictionary = s.agents[o]
		o.job = x.job
		if x.task:
			x.task.claimed_by = x.claimed
		o.path = x.path.duplicate()
		o.path_i = x.path_i
		o.think_t = x.think_t
		o.pos = x.pos
		o.mood = x.mood
		o.opinions = x.opinions.duplicate()
		o.death_match = x.death_match.duplicate()
		o.last_attacker = x.last_attacker
		o.cooldowns = x.cooldowns.duplicate()
		o.action_cooldowns = x.action_cooldowns.duplicate()
	for fx in s.rels:
		fx.relations = s.rels[fx].duplicate()
	World.social_counts = s.counts.duplicate()
	World.fight_sources = s.sources.duplicate()


static func _free_pack_slot(inv: Inventory) -> int:
	for i in range(Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS):
		if inv.entry(i) == null:
			return i
	return -1


## Player Group Base Plan D7-D10: the base fire is refused alone, the AI waits for it in a
## player-led group, placing it plans the house and posts the build tasks, members build,
## and a finished building posts its mailbox task. Cleans up after itself.
func _base_fire_checks(a: Agent, cam: Node) -> void:
	var pc := _pc
	var start_pos := a.pos
	pc.station.close("")
	_solo(a)
	_check("base_fire" in Actions.PIECES, "the build menu offers a base fire")
	_check("followers" in Factions.base_why(a, a.cell()), "no base fire without followers: %s" % Factions.base_why(a, a.cell()))
	var mate := _free_npc(a)
	if mate == null:
		_check(false, "found an NPC for the base fire checks")
		return
	var f := Factions.form(a, mate, true)
	_check(f.player_led and f.leader_id == a.id, "the player leads the new group")
	Factions.housekeeping(f)
	_check(f.homes().is_empty(), "the AI doesn't plan a player-led group's first home (D9)")
	# A site the rules accept, near the player.
	var site := World.NO_CELL
	var from := a.cell()
	var best_d := INF
	for x in range(from.x - 40, from.x + 41, 2):
		for y in range(from.y - 40, from.y + 41, 2):
			var c := Vector2i(x, y)
			var d := Vector2(c - from).length()
			if d < best_d and World.in_bounds(c) and Factions.base_why(a, c) == "":
				best_d = d
				site = c
	_check(site != World.NO_CELL, "found a valid base site near the player")
	if site == World.NO_CELL:
		_solo(a)
		return
	a.inv.add("wood", 5)
	a.inv.add("stone", 3)
	a.pos = World.center(site) + Vector2(2.0, 0.0)
	cam.position = a.pos * Cfg.CELL
	pc.build_piece = "base_fire"
	pc.hover_cell = site
	pc._place_piece(a)
	pc.build_piece = ""
	var homes := f.homes()
	var h: House = homes[0] if not homes.is_empty() else null
	_check(h != null and h.fire_cell == site and h.state == House.State.BUILDING, "placing the base fire plans the house around it")
	if h == null:
		_solo(a)
		return
	var fire: Campfire = World.fires.get(site)
	_check(fire != null and fire.is_house and fire.house == h, "a house fire burns at the site")
	_check(mate.id in h.occupants, "the follower gets a room")
	var walls := f.board.tasks.filter(func(t): return t.house == h and t.type == Task.Type.BUILD_WALL).size()
	_check(walls == h.wall_cells.size(), "wall tasks posted for the house (%d of %d)" % [walls, h.wall_cells.size()])
	_check("already has a home" in Factions.base_why(a, site + Vector2i(0, 30)), "a second base fire is refused")
	# The follower can take the house's work from the board (no sim time here: running the
	# sim shifts moods and positions, which upsets the death tests that follow).
	var t := f.board.claim(mate.id, mate.cell())
	_check(t != null and (t.house == h or t.type == Task.Type.CLEAR_NODE), "the follower can claim the house's building work (%s)" % (Task.Type.keys()[t.type] if t else "nothing"))
	f.board.release(mate.id)
	await _shot("playtest_base_fire")
	# Finished buildings get a mailbox task (D10).
	h.state = House.State.COMPLETE
	Factions._ensure_piece_tasks(f, h)
	_check(f.board.tasks.any(func(t): return t.house == h and t.type == Task.Type.PLACE_MAILBOX), "a finished house posts its mailbox task")
	# Clean up: the house, its pieces and the group.
	for c in h.wall_cells + [h.door_cell]:
		var w: Wall = World.walls.get(c)
		if w:
			World.remove_wall(w)
	for c in h.floor_cells:
		World.floors.erase(c)
	if World.fires.get(site) == fire:
		World.remove_fire(fire)
	World.pieces_version += 1
	Factions.leave(mate)
	Factions.make_solo(mate)
	Brain.set_job(mate, null)
	_solo(a)
	a.pos = start_pos
	cam.position = a.pos * Cfg.CELL


## Player Group Base Plan R3-R6: buildings planned outside a city get random door sides and
## mailbox sides, every planned doorway is open, and the base fire's door faces the player.
## Plans are undone right away; no sim time (it upsets the death tests that follow).
func _door_side_checks(a: Agent) -> void:
	_solo(a)
	var start_pos := a.pos
	var f := a.faction # a solo group: no kingdom, so _plan_house takes the non-city path
	var sides := {}
	var mail_sides := {}
	var plans := 0
	var doors_ok := true
	var bad := ""
	for i in 16:
		var kind: int = House.Kind.HOUSE if i % 2 == 0 else House.Kind.WORKSHOP
		var h := Factions._plan_house(f, 2, kind)
		if h == null:
			continue
		plans += 1
		sides[h.door_dir] = true
		var lay := House.door_layout(h.interior, h.door_dir)
		mail_sides["left" if h.mailbox_cell == lay[2] else "right"] = true
		var two_out := h.door_outside(2)
		var clash := false
		for o in World.all_houses():
			if o != h and o.footprint().has_point(two_out):
				clash = true
		if lay[0] != h.door_cell or not World.is_walkable(h.door_outside()) or clash:
			doors_ok = false
			bad = "door %s facing %s" % [h.door_cell, h.door_dir]
		f.board.remove_for_house(h)
		f.houses.erase(h)
		World.buildings_version += 1
	_check(plans >= 6, "the AI plans buildings outside a city (%d of 16)" % plans)
	_check(sides.size() > 1, "planned buildings face more than one side (%s)" % [sides.keys()])
	_check(mail_sides.size() == 2, "the mailbox lands on both sides of the door (%s)" % [mail_sides.keys()])
	_check(doors_ok, "every planned doorway is open with room in front %s" % bad)
	# The base fire's door faces the player, wherever they stand (when that side works).
	var site := World.NO_CELL
	var from := a.cell()
	var best_d := INF
	for x in range(from.x - 40, from.x + 41, 2):
		for y in range(from.y - 40, from.y + 41, 2):
			var c := Vector2i(x, y)
			var d := Vector2(c - from).length()
			if d < best_d and World.in_bounds(c) and Factions.base_site(a, c)[1] == "":
				best_d = d
				site = c
	_check(site != World.NO_CELL, "found a base fire site for the door check")
	if site == World.NO_CELL:
		return
	var interior := Factions.base_interior(f, site)
	var faced := 0
	var faces_ok := true
	for side in House.SIDES:
		a.pos = World.center(site + side * 6)
		var pick := Factions.base_site(a, site)
		var dir: Vector2i = pick[0]
		if Factions._door_why(interior, side) == "":
			faced += 1
			var h := House.new(f.id, interior, 2, House.Kind.HOUSE, dir)
			var to := Vector2(a.cell() - h.door_cell)
			if dir != side or to.dot(Vector2(side)) <= 0.0:
				faces_ok = false
	a.pos = start_pos
	_check(faced > 0 and faces_ok, "the base fire's door faces the player (%d sides tried)" % faced)


## The first slot holding a stack of `item`, or -1.
static func _slot_with(inv: Inventory, item: String) -> int:
	for i in inv.slots.size():
		var e = inv.slots[i]
		if e != null and not Inventory.is_tool_entry(e) and e.item == item:
			return i
	return -1


## The slot inventory (agreed 2026-11-24): 30 slots, the hotbar slot in hand decides the
## weapon, LMB eats held berries, drag merges and swaps, right click moves stacks between
## hotbar and pack, armour goes on and off, a full pack refuses more.
func _slots(a: Agent) -> void:
	var pc := _pc
	_check(a.inv.cap() == 30, "every agent has 30 slots (%d)" % a.inv.cap())
	# A club in the hotbar: in hand only when its slot is picked.
	a.inv.add_tool("club")
	var club := a.inv.slot_of(a.inv.get_tool("club"))
	_check(club >= 0 and club < Cfg.HOTBAR_SLOTS, "a new tool lands in the hotbar (slot %d)" % (club + 1))
	var empty := -1
	for i in Cfg.HOTBAR_SLOTS:
		if a.inv.entry(i) == null:
			empty = i
			break
	pc.select_slot(empty)
	_steps(1)
	var bare := a.melee_weapon()
	pc.select_slot(club)
	_steps(1)
	_check(bare == "unarmed" and a.melee_weapon() == "club", "the weapon is the one in hand (empty slot: %s, club slot: %s)" % [bare, a.melee_weapon()])
	# Berries in hand: LMB eats one.
	a.inv.remove("berry", a.inv.count("berry"))
	a.inv.add("berry", 3)
	var b := _slot_with(a.inv, "berry")
	pc.request_move("inv", b, "inv", empty)
	_steps(1)
	pc.select_slot(empty)
	a.hunger = 0.3
	a.attack_cd = 0.0
	pc._swing_t = 0.25
	_steps(1)
	_check(a.inv.count("berry") == 2 and a.hunger > 0.3, "LMB with berries in hand eats one")
	# Right click: hotbar <-> pack.
	pc.request_quick("inv", empty)
	_steps(1)
	var moved := _slot_with(a.inv, "berry")
	_check(moved >= Cfg.HOTBAR_SLOTS and a.inv.entry(empty) == null, "right click moves a hotbar stack into the pack (slot %d)" % moved)
	# Drag: same item merges, different items swap.
	a.inv.remove("stone", a.inv.count("stone"))
	var s1 := _first_free(a.inv, Cfg.HOTBAR_SLOTS)
	a.inv.put_slot(s1, {"item": "stone", "n": 5})
	var s2 := _first_free(a.inv, s1 + 1)
	a.inv.put_slot(s2, {"item": "stone", "n": 4})
	pc.request_move("inv", s2, "inv", s1)
	_steps(1)
	_check(a.inv.entry(s2) == null and a.inv.entry(s1) != null and a.inv.entry(s1).n == 9, "dragging stone onto stone merges the stacks")
	pc.request_move("inv", s1, "inv", moved)
	_steps(1)
	var at_moved = a.inv.entry(moved)
	var at_s1 = a.inv.entry(s1)
	_check(at_moved != null and at_moved.item == "stone" and at_s1 != null and at_s1.item == "berry", "dragging stone onto berries swaps them")
	a.inv.remove("stone", 9)
	# Armour: right click puts a helmet on and takes it off again.
	a.inv.add_tool("helmet")
	pc.request_quick("inv", a.inv.slot_of(a.inv.get_tool("helmet")))
	_steps(1)
	var on := a.worn.has("helmet") and not a.inv.has_tool("helmet")
	pc.request_quick("worn", Items.ARMOR.find("helmet"))
	_steps(1)
	_check(on and not a.worn.has("helmet") and a.inv.has_tool("helmet"), "right click puts armour on, and takes it off")
	a.inv.take_tool(a.inv.get_tool("helmet"))
	a.inv.take_tool(a.inv.get_tool("club"))
	# Hand crafting (Tab inventory): an axe from the pack, anywhere; a workshop recipe isn't
	# offered by hand.
	for k in ["wood", "stone", "hemp"]:
		a.inv.remove(k, a.inv.count(k))
	a.inv.add("wood", 3)
	a.inv.add("stone", 2)
	a.inv.add("hemp", 1)
	var axes := 0
	for t in a.inv.tools:
		if t.type == "axe":
			axes += 1
	pc.request_craft("axe")
	pc.request_craft("raiding_axe")
	_steps(1)
	var axes_now := 0
	for t in a.inv.tools:
		if t.type == "axe":
			axes_now += 1
	_check(axes_now == axes + 1 and a.inv.count("wood") == 0 and not a.inv.has_tool("raiding_axe"), "hand-crafted an axe from the pack (workshop recipes aren't offered by hand)")
	for t in a.inv.tools.duplicate():
		if t.type == "axe" and axes_now > axes:
			a.inv.take_tool(t)
			axes_now -= 1
	# A full pack refuses more, and nothing is lost.
	var before := a.inv.used_slots()
	var got := a.inv.add("hemp", 30 * 20)
	var full := a.inv.free_slots() == 0
	var more := a.inv.add("hemp", 5)
	_check(full and more == 0 and a.inv.count("hemp") == got, "a full pack refuses more (%d hemp in %d free slots)" % [got, 30 - before])
	a.inv.remove("hemp", got)


static func _first_free(inv: Inventory, from: int) -> int:
	for i in range(from, inv.cap()):
		if inv.entry(i) == null:
			return i
	return -1


## `-- --inputtest`: the same controller driven through Godot's real input path (key and
## mouse events injected with Input.parse_input_event, sim stepped by Main at 1x), so the
## per-frame input reading, LMB / E / number keys and the F3 menu are covered too.
func run_input(main: Node, pc: PlayerController, cam: Node) -> void:
	_main = main
	_pc = pc
	_shots = DisplayServer.get_name() != "headless"
	var a := pc.body
	var site := _open_site(a.cell())
	a.pos = World.center(site)
	cam.position = a.pos * Cfg.CELL
	await _frames(5)
	var start := a.pos
	_key(KEY_D, true)
	await _seconds(1.0)
	_key(KEY_D, false)
	_check(a.pos.x - start.x > a.speed() * 0.8, "D walks right (%.2f cells in 1 s)" % (a.pos.x - start.x))
	# Mouse aims: put the cursor to the left of the body.
	var screen := main.get_viewport().get_canvas_transform() * ((a.pos + Vector2(-3, 0)) * Cfg.CELL)
	_mouse_move(screen)
	await _frames(5)
	_check(a.facing.x < -0.9, "the mouse sets facing (%.2f, %.2f)" % [a.facing.x, a.facing.y])
	# B opens the build menu, 1 picks a piece, LMB places it under the cursor.
	a.inv.add("wood", 4)
	_key(KEY_B, true)
	_key(KEY_B, false)
	await _frames(2)
	_check(main._build.visible, "B opens the build menu")
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(2)
	_check(pc.build_piece == "wall" and not main._build.visible, "1 picks the wall piece and closes the menu")
	await _seconds(1.0) # let the camera's look-ahead settle so the cell under the cursor holds still
	var target := pc.hover_cell
	_click(MOUSE_BUTTON_LEFT, screen)
	await _frames(3)
	_check(World.walls.has(target), "LMB places a wall at the cursor (%s; target %s, hover %s, body %s)" % [pc.message, target, pc.hover_cell, a.cell()])
	_key(KEY_X, true)
	_key(KEY_X, false)
	await _frames(2)
	_check(pc.build_piece == "", "X stops building")
	# Tab opens the inventory; 2 picks hotbar slot 2.
	var inv_ui: CanvasLayer = main._inv_ui
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	await _frames(2)
	_check(pc.inv_open and inv_ui._pack.visible and inv_ui._equip.visible, "Tab opens the inventory (pack, armour, stats)")
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _frames(2)
	_check(pc.held == 1, "2 picks hotbar slot 2")
	_key(KEY_TAB, true)
	_key(KEY_TAB, false)
	await _frames(2)
	_check(not pc.inv_open and not inv_ui._pack.visible and inv_ui._hotbar.visible, "Tab closes it; the hotbar stays")
	# E opens a chest beside the body, and the inventory with it. Right click on the wood's
	# slot moves the stack into the chest (and doesn't swing); a drag brings it back into a
	# chosen pack slot; Esc closes both.
	var ch := World.place_furniture(a.cell() + Vector2i(-1, 0), Furniture.Kind.CHEST, a.faction.id, null)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	_check(pc.station.open == ch and pc.inv_open and inv_ui._chest.visible, "E opens the chest on the right, and the inventory")
	await _frames(8)
	await _shot("inputtest_chest")
	var wood_slot := _slot_with(a.inv, "wood")
	var wood_n := a.inv.count("wood")
	var src: Control = inv_ui.box("inv", wood_slot)
	if src:
		var cd := a.last_swing
		_click(MOUSE_BUTTON_RIGHT, src.get_global_rect().get_center())
		await _frames(3)
		_check(ch.store.count("wood") == wood_n and a.inv.count("wood") == 0 and a.last_swing == cd, "right click on the slot moved %d wood into the chest (no swing)" % wood_n)
		var from: Control = inv_ui.box("chest", _slot_with(ch.store, "wood"))
		var to: Control = inv_ui.box("inv", Cfg.AGENT_SLOTS - 1)
		if from and to:
			_drag(from.get_global_rect().get_center(), to.get_global_rect().get_center())
			await _frames(3)
			var e = a.inv.entry(Cfg.AGENT_SLOTS - 1)
			_check(e != null and e.item == "wood" and ch.store.count("wood") == 0, "dragged the wood back into the last pack slot")
		else:
			_check(false, "the chest and pack slots are on screen")
	else:
		_check(false, "the pack slot with the wood is on screen")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(pc.station.open == null and not inv_ui._chest.visible and not pc.inv_open, "Esc closes the chest and the inventory")
	World.remove_furniture(ch)
	# F3 opens the menu and goes straight into watch mode; V toggles back to playing (where
	# 2 is refused as a speed key and doesn't pick a piece) and into watch again.
	_key(KEY_F3, true)
	_key(KEY_F3, false)
	await _frames(2)
	var menu: CanvasLayer = main._debug
	_check(menu.visible and pc.keys_blocked, "F3 opens the debug menu")
	_check(pc.watching and a.controller == null and cam.free_camera, "F3 enters watch mode (AI drives, free camera)")
	_key(KEY_V, true)
	_key(KEY_V, false)
	await _frames(2)
	_check(not pc.watching and a.controller == pc, "V in the menu goes back to playing")
	_key(KEY_2, true)
	_key(KEY_2, false)
	await _frames(2)
	_check(SimClock.speed == 1.0 and pc.build_piece == "", "while playing, speed stays 1x and 2 doesn't pick a piece")
	_key(KEY_V, true)
	_key(KEY_V, false)
	await _frames(2)
	_key(KEY_3, true)
	_key(KEY_3, false)
	await _frames(2)
	_check(pc.watching and a.controller == null and cam.free_camera and SimClock.speed == 4.0, "V watches (AI drives, free camera), 3 sets 4x")
	await _shot("inputtest_watch")
	_key(KEY_F3, true)
	_key(KEY_F3, false)
	await _frames(2)
	_check(not menu.visible and not pc.keys_blocked, "F3 closes the menu")
	_check(not pc.watching and a.controller == pc and not cam.free_camera and SimClock.speed == 1.0, "closing the menu goes back to playing at 1x")
	# Social prompt keys (Player Social Plan §3): F2 declines a gang ask, F1 accepts one
	# (NPCs no longer invite the player, Player Group Plan D4).
	var npc := _free_npc(a)
	if npc:
		npc.pos = a.pos + Vector2(2, 0)
		a.mood = -60.0
		npc.mood = -60.0
		Social._angry_meets(npc, a)
		_check(pc.offers.has_from(npc.id), "a gang ask shows a prompt")
		_key(KEY_F2, true)
		_key(KEY_F2, false)
		await _frames(4)
		_check(not pc.offers.has_from(npc.id) and a.faction.solo, "F2 declines the gang ask")
		_calm(a, npc)
		# The sim runs in real time here, so the NPC may join someone else before F1 lands
		# (accepting then fails its re-check, as it should): try a fresh NPC if so.
		for attempt in 3:
			npc.pos = a.pos + Vector2(2, 0)
			npc.mood = -60.0
			a.mood = -60.0
			Social._angry_meets(npc, a)
			_key(KEY_F1, true)
			_key(KEY_F1, false)
			await _frames(4)
			if not a.faction.solo:
				break
			_calm(a, npc)
			npc = _free_npc(a, npc)
			if npc == null:
				break
		_check(npc != null and not a.faction.solo and a.faction == npc.faction, "F1 accepts the gang ask (%s)" % pc.message)
		Factions.leave(a)
		Factions.make_solo(a)
		a.mood = 60.0
	# Radial menu (Player Social Plan §4): hold F over an NPC, move the mouse down to
	# "Demand goods", LMB confirms it (no swing) and closes the menu; releasing F closes it.
	var rt := _free_npc(a)
	if rt:
		pc.offers.clear()
		_pushover(a, rt)
		rt.pos = a.pos + Vector2(2, 0)
		var cpos: Vector2 = main.get_viewport().get_canvas_transform() * (rt.pos * Cfg.CELL)
		_mouse_move(cpos)
		await _frames(3)
		_check(pc.hover_id == rt.id, "hovering %s picks them" % rt.short())
		_key(KEY_F, true)
		await _frames(3)
		var radial: CanvasLayer = main._radial
		_check(pc.radial_id == rt.id and radial._options.size() == 5, "holding F opens the radial menu on %s" % rt.short())
		_mouse_move(radial.option_pos(2))
		await _frames(3)
		_check(pc.radial_sel == &"demand", "moving the mouse to it highlights Demand goods (%s %s)" % [pc.radial_sel, pc.radial_why])
		var swung := a.last_swing
		_click(MOUSE_BUTTON_LEFT, radial.option_pos(2))
		await _frames(4)
		_check(pc.radial_id == -1 and not a.can_act_on(rt.id) and a.last_swing == swung,
			"LMB confirms the option and closes the menu, without a swing (%s)" % pc.message)
		_key(KEY_F, false)
		await _frames(2)
		var rt2 := _free_npc(a, rt)
		if rt2:
			rt2.pos = a.pos + Vector2(-2, 0)
			Brain.set_job(rt2, null)
			_mouse_move(main.get_viewport().get_canvas_transform() * (rt2.pos * Cfg.CELL))
			await _frames(3)
			_key(KEY_F, true)
			await _frames(3)
			var opened := pc.radial_id == rt2.id
			_key(KEY_F, false)
			await _frames(3)
			_check(opened and pc.radial_id == -1, "releasing F closes the menu without choosing")
	# Death (§5a): the panel shows; N starts fresh as a solo agent, which WASD then moves.
	var old := pc.body
	World.kill_agent(old, null)
	await _frames(3)
	var panel: CanvasLayer = main._death_panel
	_check(panel.visible and SimClock.speed == 1.0, "death shows the death panel at 1x")
	_key(KEY_N, true)
	_key(KEY_N, false)
	await _frames(3)
	var nb := pc.body
	_check(nb != old and nb.alive and nb.controller == pc and nb.faction.solo and not panel.visible, "N starts fresh as %s (solo)" % nb.short())
	start = nb.pos
	# Walk towards open ground: the respawn spot is random and may have a wall or node beside it.
	var walk: Key = KEY_A
	for kd in [[KEY_A, Vector2i(-1, 0)], [KEY_D, Vector2i(1, 0)], [KEY_W, Vector2i(0, -1)], [KEY_S, Vector2i(0, 1)]]:
		if World.is_walkable(nb.cell() + kd[1]) and World.is_walkable(nb.cell() + kd[1] * 2):
			walk = kd[0]
			break
	_key(walk, true)
	await _seconds(0.5)
	_key(walk, false)
	_check(nb.pos.distance_to(start) > 0.3, "%s moves the new body (%.2f cells)" % [OS.get_keycode_string(walk), nb.pos.distance_to(start)])
	print("INPUTTEST %s (%d failed)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	main.get_tree().quit()


# --- Death and takeover (§5a) ---

## Kill the player in a kingdom: takeover picks the highest-AUTH living member and the new
## body works; respawn gives a solo agent with no kingdom; a group without a kingdom falls
## back to the group; a solo death offers no takeover; the debug menu takes control too.
func _death_tests(main: Node) -> void:
	var panel: CanvasLayer = main._death_panel
	if not _pc.alive():
		_pc.respawn()
	_check(_pc.alive() and _pc.death.is_empty(), "the player has a living body to start the death tests (%s)" % _pc.body.short())

	# 1. A kingdom of three groups; the player's group has one other member.
	var free := _free_agents(6)
	_check(free.size() == 6, "found 6 solo agents to build a kingdom from")
	if free.size() < 6:
		return
	var me := _pc.body
	var mine := Factions.form(me, free[0])
	var g2 := Factions.form(free[1], free[2])
	var g3 := Factions.form(free[3], free[4])
	var k := Kingdoms.form(mine, g2)
	Kingdoms.join(g3, k)
	_check(me.faction.kingdom == k and k.groups.size() == 3, "the player is in the kingdom of %s (3 groups)" % k.name)
	for o in [me, free[0], free[1], free[2], free[3], free[4]]:
		o.stats.auth = 5
		o.stats.cha = 5
	var best: Agent = free[3] # in another group: the pick is kingdom-wide
	best.stats.auth = 40
	free[0].stats.auth = 30 # the player's own group mate comes second
	best.inv.add("stone", 7)
	var best_stone := best.inv.count("stone")
	var best_group := best.faction
	_steps(5)
	best.raid_id = 9999 # stale AI state that the takeover must drop
	best.job = Job.new(Job.Kind.DEFEND, Job.PRIO_CRITICAL)
	World.kill_agent(me, null)
	_check(_pc.dead() and not _pc.death.is_empty(), "the player's death is recorded (%s)" % _pc.death.get("cause", "?"))
	_check(SimClock.speed == 1.0, "the sim runs at 1x behind the death panel")
	var cand := _pc.takeover_candidate()
	_check(cand == best, "takeover picks the highest-AUTH kingdom member (%s, AUTH %d)" % [cand.short() if cand else "nobody", cand.stats.auth if cand else 0])
	await _frames(2)
	panel.refresh()
	_check(panel.visible and panel._take.visible and best.short() in panel._take.text, "the panel offers it: %s / %s" % [panel._take.text, panel._who.text])
	_check("cells away" in panel._who.text and "AUTH 40" in panel._who.text, "the panel shows role, AUTH and distance")
	await _shot("playtest_death_panel")
	# Nothing in the sim still points at the dead body.
	_check(not _any_ref(me), "no group, kingdom or raid still holds the dead player %s" % me.short())
	panel._on_take()
	_check(_pc.body == best and best.controller == _pc and me.controller == null, "takeover: the controller moved to %s" % best.short())
	_check(best.job == null and best.path.is_empty() and best.raid_id == -1, "takeover: the AI's job, path and raid are dropped")
	_check(best.faction == best_group and best.inv.count("stone") == best_stone and best.stats.auth == 40, "takeover: the body keeps its group, inventory and AUTH")
	_check(_pc.death.is_empty() and not _pc.dead(), "takeover clears the death state")
	await _frames(2)
	_check(not panel.visible, "the death panel closes")
	await _controls_work(best, "the new body")

	# 2. Fresh respawn from inside the kingdom: a solo agent with no kingdom.
	World.kill_agent(best, null)
	_check(_pc.takeover_candidate() != null, "a takeover is offered again (%s)" % _pc.takeover_candidate().short() if _pc.takeover_candidate() else "nobody")
	var newcomer: Agent = World.agents.get(_pc.death.newcomer_id)
	_pc.respawn()
	var fresh := _pc.body
	_check(fresh != best and fresh.alive and fresh.controller == _pc, "respawn: playing %s" % fresh.short())
	_check(fresh == newcomer, "respawn: it is the newcomer the death spawned (population stays %d)" % World.agent_list.size())
	_check(fresh.faction.solo and fresh.faction.kingdom == null and not fresh.is_servant(), "respawn: on their own, no kingdom")
	_check(World.kingdoms.has(k.id), "the old kingdom carries on under the AI")
	await _controls_work(fresh, "the respawned body")

	# 3. In a group but no kingdom: the group's highest AUTH member.
	var free2 := _free_agents(2)
	if free2.size() == 2:
		var grp := Factions.form(fresh, free2[0])
		Factions.join(free2[1], grp)
		fresh.stats.auth = 50
		free2[0].stats.auth = 3
		free2[1].stats.auth = 20
		World.kill_agent(fresh, null)
		_check(_pc.takeover_candidate() == free2[1], "no kingdom: takeover picks the group's highest AUTH (%s)" % free2[1].short())
		_pc.take_over(free2[1])
		_check(_pc.body == free2[1] and free2[1].controller == _pc, "took over %s (%s)" % [free2[1].short(), _pc.role_of(free2[1])])

	# 4. Solo: no takeover offered.
	var b := _pc.body
	World.kill_agent(b, null)
	_pc.respawn()
	World.kill_agent(_pc.body, null)
	_check(_pc.takeover_candidate() == null, "a solo death offers no takeover")
	await _frames(2)
	panel.refresh()
	_check(panel.visible and not panel._take.visible, "the panel only offers a fresh start")
	_pc.respawn()

	# 5. Debug menu: take control of the selected agent.
	var other: Agent = null
	for o in World.agent_list:
		if o != _pc.body and o.alive:
			other = o
			break
	var menu: CanvasLayer = main._debug
	menu.agent_layer.selected_id = other.id
	menu.take_selected()
	_check(_pc.body == other and other.controller == _pc and menu.agent_layer.selected_id == -1, "debug: took control of the selected agent %s" % other.short())


## Some solo, free, living agents that aren't the player.
func _free_agents(n: int) -> Array[Agent]:
	var out: Array[Agent] = []
	for o in World.agent_list:
		if o.alive and o != _pc.body and o.faction.solo and not o.is_servant() and o.raid_id == -1:
			out.append(o)
			if out.size() == n:
				break
	return out


func _any_ref(dead: Agent) -> bool:
	for f in World.factions.values():
		if dead.id in f.members or f.leader_id == dead.id:
			return true
	for kk in World.kingdoms.values():
		if kk.king_id == dead.id:
			return true
	for r in Raids.active:
		if dead.id in r.party:
			return true
	return World.agents.has(dead.id) or dead.faction != null


## Move (any open direction) and swing on a body the controller just took.
func _controls_work(a: Agent, what: String) -> void:
	var moved := 0.0
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var p0 := a.pos
		_pc._move_in = d
		_steps(30)
		_pc._move_in = Vector2.ZERO
		_steps(5)
		moved = max(moved, a.pos.distance_to(p0))
		if moved > 0.5:
			break
	_check(moved > 0.5, "%s walks (%.2f cells)" % [what, moved])
	a.attack_cd = 0.0
	_pc.aim_point = a.pos + Vector2.RIGHT * 3.0
	_pc._swing_t = 0.25
	_steps(1)
	_check(absf(a.last_swing - SimClock.time) < 0.05 and a.facing.x > 0.9, "%s swings where it aims" % what)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
	_main.get_viewport().warp_mouse(p)


func _click(b: MouseButton, p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = b
		e.position = p
		e.global_position = p
		e.pressed = down
		Input.parse_input_event(e)


## Press at p1, move to p2, release there (a drag and drop).
func _drag(p1: Vector2, p2: Vector2) -> void:
	_mouse_move(p1)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = p1
	e.global_position = p1
	e.pressed = true
	Input.parse_input_event(e)
	_mouse_move(p2)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.position = p2
	u.global_position = p2
	u.pressed = false
	Input.parse_input_event(u)


func _frames(n: int) -> void:
	for i in n:
		await _main.get_tree().process_frame


func _seconds(s: float) -> void:
	await _main.get_tree().create_timer(s).timeout


func _steps(n: int) -> void:
	for i in n:
		World.step(1.0 / 60.0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(name: String) -> void:
	if not _shots:
		return
	for i in 3:
		await _main.get_tree().process_frame
	_main.get_viewport().get_texture().get_image().save_png("user://%s.png" % name)


## The nearest cell to `from` with open, unclaimed ground around it (13 x 9 cells).
func _open_site(from: Vector2i) -> Vector2i:
	var best := World.NO_CELL
	var best_d := INF
	for x in range(10, Cfg.MAP_W - 10, 2):
		for y in range(6, Cfg.MAP_H - 6, 2):
			var c := Vector2i(x, y)
			var d := Vector2(c - from).length()
			if d < best_d and _open(c):
				best_d = d
				best = c
	return best


func _open(c: Vector2i) -> bool:
	for x in range(c.x - 9, c.x + 4):
		for y in range(c.y - 4, c.y + 5):
			var p := Vector2i(x, y)
			if not World.is_walkable(p) or World.privilege_owner(p) != 0 or World.agent_on(p) or World.loot.has(p):
				return false
	return true
