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
		# 7. Watch mode: the AI drives the body, then hands it back.
		pc.set_watching(true)
		_steps(60)
		_check(a.controller == null and a.last_think > 0.0, "watch mode: the AI thinks for the body")
		pc.set_watching(false)
		_check(a.controller == pc and a.job == null, "back from watch mode: the player drives again")
	print("PLAYTEST %s (%d failed)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	_main.get_tree().quit()


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
	# Number key picks a piece, LMB places it under the cursor.
	a.inv.add("wood", 4)
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames(2)
	_check(pc.build_piece == "wall", "1 picks the wall piece")
	await _seconds(1.0) # let the camera's look-ahead settle so the cell under the cursor holds still
	var target := pc.hover_cell
	_click(MOUSE_BUTTON_LEFT, screen)
	await _frames(3)
	_check(World.walls.has(target), "LMB places a wall at the cursor (%s; target %s, hover %s, body %s)" % [pc.message, target, pc.hover_cell, a.cell()])
	_key(KEY_X, true)
	_key(KEY_X, false)
	await _frames(2)
	_check(pc.build_piece == "", "X stops building")
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
	print("INPUTTEST %s (%d failed)" % ["PASSED" if _fails == 0 else "FAILED", _fails])
	main.get_tree().quit()


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
