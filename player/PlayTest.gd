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

	# 5. Fight: swing at an NPC in front; it fights back. The player gets a sword so the
	# rest of the test usually survives (an unarmed player tends to lose).
	a.inv.add_tool("sword")
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
		# 6. Social defaults (§5): refuse to join, refuse demands and fight.
		var other: Agent = null
		for o in World.agent_list:
			if o != a and o.faction.solo and o.alive:
				other = o
				break
		if other:
			a.mood = 60.0
			other.mood = 60.0
			Social._happy_meets(other, a)
			_check(a.faction.solo, "refused a happy invite (still solo)")
			Social._demand(other, a, false)
			_check(other.job != null and other.job.kind == Job.Kind.FIGHT and other.job.target_id == a.id, "refused a demand: the NPC attacks")
			Brain.set_job(other, null)
		await _feed_checks(a)
		# 7. Watch mode: the AI drives the body, then hands it back.
		pc.set_watching(true)
		_steps(60)
		_check(a.controller == null and a.last_think > 0.0, "watch mode: the AI thinks for the body")
		pc.set_watching(false)
		_check(a.controller == pc and a.job == null, "back from watch mode: the player drives again")
	await _death_tests(main)
	print("PLAYTEST %s (%d failed)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	_main.get_tree().quit()


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
		a.mood = 60.0
		other.mood = 60.0
		Social._happy_meets(other, a)
		_check(_has(feed, 1, "invites you to join them. You refuse"), "feed: the refused invite is tier 1 (gold): %s" % _last(feed))
		Social._demand(other, a, false)
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
	# Chest: stock it with the pickaxe and the spare handle, take the handle back.
	a.pos = World.center(p0 + Vector2i(1, 2))
	pc.aim_point = World.center(chest.cell)
	pc._use = 1
	_steps(1)
	_check(pc.station.open == chest, "E opens the chest panel")
	panels.click("put:tool:pickaxe_t2:1")
	_steps(1)
	panels.click("put:handle:all")
	_steps(1)
	await _shot("playtest_chest")
	_check(chest.store.has_tool("pickaxe_t2") and chest.store.count("handle") == 1 and not a.inv.has_tool("pickaxe_t2") and a.inv.count("handle") == 0, "stocked the chest by hand (%s)" % chest.store.summary())
	panels.click("take:handle:1")
	_steps(1)
	_check(chest.store.count("handle") == 0 and a.inv.count("handle") == 1, "took one handle back out")
	pc._use = -1
	_steps(1)
	_check(pc.station.open == null, "E closes the panel")
	# Someone else's chest is refused.
	var other_fid := -1
	for o in World.agent_list:
		if not World.same_side(o.faction.id, f.id):
			other_fid = o.faction.id
			break
	var foreign := World.place_furniture(p0 + Vector2i(4, 3), Furniture.Kind.CHEST, other_fid, null)
	var why: String = pc.station.try_open(a, foreign)
	_check(why != "" and pc.station.open == null, "a chest of another side is refused (%s)" % why)
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


## `-- --inputtest`: the same controller driven through Godot's real input path (key and
## mouse events injected with Input.parse_input_event, sim stepped by Main at 1x), so the
## per-frame input reading, LMB / E / number keys and the F1 menu are covered too.
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
	# E opens a chest beside the body; a mouse click on its panel moves items (and doesn't
	# swing); Esc closes it.
	var ch := World.place_furniture(a.cell() + Vector2i(-1, 0), Furniture.Kind.CHEST, a.faction.id, null)
	_key(KEY_E, true)
	_key(KEY_E, false)
	await _frames(3)
	var panels: CanvasLayer = main._panels
	_check(pc.station.open == ch and panels.visible, "E opens the chest panel")
	await _frames(8)
	await _shot("inputtest_chest")
	var b: Button = panels._buttons.get("put:wood:1")
	if b:
		var cd := a.last_swing
		_click(MOUSE_BUTTON_LEFT, b.get_global_rect().get_center())
		await _frames(3)
		_check(ch.store.count("wood") == 1 and a.last_swing == cd, "a click on the panel's button moved 1 wood (no swing)")
	else:
		_check(false, "the chest panel has a put-wood button")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(pc.station.open == null and not panels.visible, "Esc closes the panel")
	World.remove_furniture(ch)
	# F1 opens the menu; while open, 2 is a speed key (refused: not watching), V watches.
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	await _frames(2)
	var menu: CanvasLayer = main._debug
	_check(menu.visible and pc.keys_blocked, "F1 opens the debug menu")
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
	_key(KEY_V, true)
	_key(KEY_V, false)
	await _frames(2)
	_check(not pc.watching and a.controller == pc and SimClock.speed == 1.0, "back to playing at 1x")
	_key(KEY_F1, true)
	_key(KEY_F1, false)
	await _frames(2)
	_check(not menu.visible and not pc.keys_blocked, "F1 closes the menu")
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
	_key(KEY_A, true)
	await _seconds(0.5)
	_key(KEY_A, false)
	_check(nb.pos.distance_to(start) > 0.3, "A moves the new body (%.2f cells)" % nb.pos.distance_to(start))
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
