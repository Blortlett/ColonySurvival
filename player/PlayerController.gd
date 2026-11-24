class_name PlayerController
extends Node2D
## Drives one agent's body from input instead of the AI (Player Controller Plan §1, §2, §4).
## Input is read every frame into intents; the body acts on them only inside the sim step
## (Scheduler -> control()), through the same Actions the AI uses. So the sim never
## depends on rendering, and every rule (costs, durability, damage, zones) is shared.
##
## Controls: WASD move, mouse aims, LMB swing (or place, with a piece picked), RMB shoot a
## bow, hold E harvest, E on a chest or machine opens its panel (E / Esc close it), B opens
## the build menu (ui/BuildMenu.gd sets build_piece), X / Esc stop building, F eat a berry.
## Movement keeps working while a panel is open; walking out of reach closes it. Social choices use the default rules for now (§5): refuse to join,
## fight back when attacked.

signal hit_landed # the player's swing or shot hit someone (camera shake)
signal hurt # the player took damage
signal died # the controlled body died; the death panel offers takeover or respawn (§5a)
signal body_changed # the controller now drives another body (takeover, respawn, debug)

const Station := preload("res://player/Station.gd")

var body: Agent = null
var watching := false # debug watch mode: the AI drives the body (§6a)
var keys_blocked := false # the debug menu has the number keys
var scripted := false # --playtest sets the intents itself instead of reading input

var vel := Vector2.ZERO # cells / s
var aim_point := Vector2.ZERO # cells
var build_piece := "" # selected piece, "" = not building
var hover_cell := Vector2i.ZERO
var harvest_node: ResourceNode = null # what E is working on
var harvest_t := 0.0
var harvest_secs := 0.0
var warm_t := 0.0
var station := Station.new() # the open chest or machine panel (phase 4)
var use_target: Furniture = null # what E would open right now (HUD hint)
var message := ""
var message_t := 0.0
## Set when the controlled body dies, cleared when the player picks a new body (§5a):
## {cause, pos, fids (groups it could pass to), kingdom, newcomer_id}.
var death := {}

# Intents, filled from input each frame and used up by the sim step.
var _move_in := Vector2.ZERO
var _swing_t := 0.0 # a click is buffered this long if the weapon is still cooling down
var _shoot_t := 0.0
var _place := false
var _harvest_held := false
var _eat := false
var _use := 0 # 1 open what's in reach, -1 close the panel
var _e_latch := false # this E press opened or closed a panel: don't harvest until it's released
var _xp_dist := 0.0
var _last_hp := 0.0


func _ready() -> void:
	World.agent_died.connect(_on_agent_died)


func possess(a: Agent) -> void:
	if body and body.controller == self:
		body.controller = null
	body = a
	vel = Vector2.ZERO
	harvest_node = null
	station.close("")
	harvest_t = 0.0
	warm_t = 0.0
	build_piece = ""
	_move_in = Vector2.ZERO
	_swing_t = 0.0
	_shoot_t = 0.0
	_place = false
	_eat = false
	_xp_dist = 0.0
	if a == null:
		return
	_last_hp = a.hp
	aim_point = a.pos + a.facing
	if not watching:
		_take(a)


func _take(a: Agent) -> void:
	a.controller = self
	Brain.set_job(a, null) # drops any task claim too
	a.path.clear()


## Watch mode (§6a): hand the body to the AI while watching, take it back on return.
func set_watching(on: bool) -> void:
	watching = on
	station.close("")
	if body == null or not body.alive:
		return
	if on:
		body.controller = null
		Brain.set_job(body, null)
		body.think_t = 0.0
	else:
		_take(body)
	vel = Vector2.ZERO


func alive() -> bool:
	return body != null and body.alive


func say(text: String, secs := 2.5) -> void:
	message = text
	message_t = secs


# --- Death and takeover (Player Controller Plan §5a) ---

func _on_agent_died(a: Agent, killer: Agent, group: Faction, kingdom: Kingdom, newcomer: Agent) -> void:
	if a != body:
		return
	# The body is handled like any death (World.kill_agent). Leader slots were recomputed
	# as it left its group; the king slot is only refreshed every 2 s, so do it now, and
	# take the body out of raid parties straight away rather than on the next raid tick.
	if kingdom and World.kingdoms.has(kingdom.id):
		Kingdoms.recompute(kingdom)
	for r in Raids.active:
		r.party.erase(a.id)
	var fids: Array[int] = []
	if kingdom:
		fids.assign(kingdom.groups)
	elif group and not group.solo:
		fids.append(group.id)
	death = {
		"cause": ("killed by %s" % killer.short()) if killer else ("died of %s" % ("cold" if a.warmth <= 0.0 else "hunger")),
		"pos": a.pos,
		"fids": fids,
		"kingdom": kingdom,
		"newcomer_id": newcomer.id if newcomer else -1,
	}
	watching = false # the body is gone: nothing to hand back
	SimClock.set_speed(1.0) # the sim keeps running at 1x behind the death panel (agreed)
	build_piece = ""
	died.emit()


func dead() -> bool:
	return body != null and not body.alive


## Option A: the living member with the highest AUTH in the kingdom the body died in (or its
## group, if it wasn't in a kingdom). Same order as Factions.recompute_leader: AUTH, then
## CHA, then lowest id. Null if there is nobody (solo, or everyone is dead).
func takeover_candidate() -> Agent:
	if death.is_empty():
		return null
	var fids: Array[int] = death.fids
	var k: Kingdom = death.kingdom
	if k and World.kingdoms.has(k.id):
		fids = k.groups # the kingdom as it is now (groups may have joined or left)
	var best: Agent = null
	for fid in fids:
		var f: Faction = World.factions.get(fid)
		if f == null or f.solo:
			continue
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m == null or not m.alive or m == body:
				continue
			if best == null or m.stats.auth > best.stats.auth 					or (m.stats.auth == best.stats.auth and (m.stats.cha > best.stats.cha 					or (m.stats.cha == best.stats.cha and m.id < best.id))):
				best = m
	return best


## "king of Ash", "leader of F12 (Ash)", "member of F12".
func role_of(a: Agent) -> String:
	var f := a.faction
	var k: Kingdom = f.kingdom if f else null
	if f == null or f.solo:
		return "on their own"
	var in_k := (" (%s)" % k.name) if k else ""
	if k and k.king_id == a.id:
		return "king of %s" % k.name
	if f.leader_id == a.id:
		return "leader of %s%s" % [f.name, in_k]
	return "member of %s%s" % [f.name, in_k]


## Take control of another living body (death option A, and the debug menu). The body keeps
## its inventory, stats, faction and rank; its AI state is dropped.
func take_over(a: Agent) -> void:
	if a == null or not a.alive:
		return
	var was_dead := dead()
	watching = false
	possess(a)
	_reset_ai(a)
	SimClock.set_speed(1.0)
	var line := "You now play %s, %s." % [a.short(), role_of(a)]
	EventBus.social(&"takeover", ("You died. " if was_dead else "") + line, [a])
	say(line, 4.0)
	death = {}
	body_changed.emit()


## Option B: a fresh solo agent at a random free spot, with no ties to the old kingdom. It is
## the newcomer the death spawned (population stays constant) if that one is still a free,
## solo agent; otherwise a new agent is spawned.
func respawn() -> void:
	var a: Agent = World.agents.get(death.get("newcomer_id", -1))
	if a == null or not a.alive or not a.faction.solo or a.is_servant() or a.controller != null:
		a = World.spawn_agent(Cfg.RESPAWN_MIN_DIST)
	watching = false
	possess(a)
	_reset_ai(a)
	SimClock.set_speed(1.0)
	EventBus.social(&"respawn", "You start again as %s, a newcomer on their own." % a.short(), [a])
	say("A fresh start as %s." % a.short(), 4.0)
	death = {}
	body_changed.emit()


## Drop what the AI was doing with this body: job (and task claim, in possess), path,
## raid duties. Fights it is already in (death_match) belong to the body and stay.
func _reset_ai(a: Agent) -> void:
	a.think_t = 0.0
	if a.raid_id != -1:
		var r := Raids.find(a.raid_id)
		if r:
			r.party.erase(a.id)
		a.raid_id = -1
	a.defend_raid = -1
	aim_point = a.pos + a.facing


# --- Input (per frame) ---

func _process(dt: float) -> void:
	message_t -= dt
	if scripted:
		return
	if not alive() or watching:
		_move_in = Vector2.ZERO
		_harvest_held = false
		return
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): m.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): m.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): m.x += 1.0
	_move_in = m.normalized()
	var e := Input.is_physical_key_pressed(KEY_E)
	if not e:
		_e_latch = false
	_harvest_held = e and not _e_latch and station.open == null
	use_target = Station.target(body) if station.open == null else null
	aim_point = get_global_mouse_position() / Cfg.CELL
	hover_cell = Vector2i(aim_point.floor())
	if body.hp < _last_hp - 0.01:
		hurt.emit()
	_last_hp = body.hp


func _unhandled_input(event: InputEvent) -> void:
	if not alive() or watching:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if build_piece != "":
				_place = true
			else:
				_swing_t = 0.25
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if build_piece != "":
				build_piece = ""
			else:
				_shoot_t = 0.25
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_E:
			if station.open != null:
				_use = -1
				_e_latch = true
			elif Station.target(body) != null:
				_use = 1
				_e_latch = true
		elif k == KEY_ESCAPE and station.open != null:
			_use = -1
			get_viewport().set_input_as_handled()
		elif k == KEY_X or k == KEY_ESCAPE:
			build_piece = ""
		elif k == KEY_F:
			_eat = true


# --- Sim step (called by Scheduler.update instead of Brain) ---

func control(a: Agent, dt: float) -> void:
	_job_hygiene(a, dt)
	_move(a, dt)
	a.facing = _aim_dir(a)
	_swing_t -= dt
	_shoot_t -= dt
	if _swing_t > 0.0 and a.attack_cd <= 0.0:
		_swing_t = 0.0
		if Actions.swing(a, a.facing, a.melee_weapon()) > 0:
			hit_landed.emit()
	if _shoot_t > 0.0 and a.attack_cd <= 0.0:
		_shoot_t = 0.0
		_shoot(a)
	if _place:
		_place = false
		_place_piece(a)
	if _eat:
		_eat = false
		if not Actions.eat(a):
			say("No berries to eat.")
	_use_station(a, dt)
	_harvest(a, dt)
	_warm(a, dt)
	var bag: LootBag = World.loot.get(a.cell())
	if bag:
		World.take_loot(a, bag)


func _aim_dir(a: Agent) -> Vector2:
	var d := World.delta(a.pos, aim_point)
	return d.normalized() if d.length() > 0.05 else a.facing


## Snappy acceleration and friction (start: 0.05 s to full speed), agent speed formula
## (AGI and road bonus), sliding collision against cells the body can't pass.
func _move(a: Agent, dt: float) -> void:
	var top := a.speed()
	vel = vel.move_toward(_move_in * top, top / Cfg.PLAYER_ACCEL_SECS * dt)
	if vel == Vector2.ZERO:
		return
	var want := vel * dt
	var moved := Actions.move_free(a, want)
	for axis in 2:
		if absf(moved[axis]) < absf(want[axis]) * 0.5:
			vel[axis] = 0.0 # blocked on this axis: don't keep pushing into the wall
	_xp_dist += moved.length()
	while _xp_dist >= 1.0:
		_xp_dist -= 1.0
		a.add_xp("agi", Cfg.XP_PER_CELL) # same AGI training per cell as path movement


## Bows fire at the agent nearest the aim point (within reach and line of sight).
func _shoot(a: Agent) -> void:
	if not a.has_bow_ready():
		say("No bow and arrows.")
		return
	var best: Agent = null
	var best_d := 1.5
	for o in World.agents_near(aim_point, 1.5):
		if o == a or World.same_side(o.faction.id, a.faction.id):
			continue
		var d := World.dist(o.pos, aim_point)
		if d < best_d and World.dist(a.pos, o.pos) <= a.bow_range():
			best_d = d
			best = o
	if best == null:
		say("Nothing to shoot at there.")
		return
	if Actions.shoot(a, best):
		hit_landed.emit()
	else:
		say("No line of sight.")


func _place_piece(a: Agent) -> void:
	var why := Actions.can_place(a, build_piece, hover_cell, Cfg.PLAYER_BUILD_REACH)
	if why != "":
		say("Can't place %s: %s." % [Items.label(build_piece), why])
		return
	Actions.place(a, build_piece, hover_cell, Items.BUILD_COSTS[build_piece])


## The node E works on: within reach, the one most in front of the body.
func harvest_target(a: Agent) -> ResourceNode:
	var best: ResourceNode = null
	var best_score := -INF
	var c := a.cell()
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var n: ResourceNode = World.nodes.get(c + Vector2i(dx, dy))
			if n == null or n.amount <= 0:
				continue
			var d := World.delta(a.pos, World.center(n.cell))
			var len := d.length()
			if len > Cfg.PLAYER_HARVEST_REACH:
				continue
			var score := a.facing.dot(d / len) - len * 0.5
			if score > best_score:
				best_score = score
				best = n
	return best


## Hold E: gather times, tool use and durability as for everyone (Actions).
func _harvest(a: Agent, dt: float) -> void:
	var n: ResourceNode = harvest_target(a) if _harvest_held else null
	if n != harvest_node:
		harvest_node = n
		harvest_t = 0.0
	if n == null:
		return
	if not Actions.can_harvest(a, n):
		say("Metal needs a tier-2 pickaxe.")
		harvest_node = null
		return
	if a.free_space() <= 0:
		say("Your pack is full.")
		return
	var g := Actions.harvest_secs(a, n)
	harvest_secs = g[0]
	harvest_t += dt
	if harvest_t >= harvest_secs:
		harvest_t -= harvest_secs
		if Actions.harvest_unit(a, n, g[1], true, n.type != ResourceNode.Type.BUSH):
			harvest_node = null


## E opens the chest or machine in reach (or closes the open one); the open panel's
## requests run here, inside the sim step.
func _use_station(a: Agent, dt: float) -> void:
	if _use == -1:
		station.close("")
	elif _use == 1:
		var fu := Station.target(a)
		if fu != null:
			build_piece = ""
			var why: String = station.try_open(a, fu)
			if why != "":
				say("Can't use the %s: %s." % [fu.label(), why])
	_use = 0
	station.step(a, dt)
	if station.why_closed != "":
		say("Panel closed: %s." % station.why_closed)
		station.why_closed = ""


## Standing by a burning fire warms the body like an NPC's WARM job (10 s next to it).
func _warm(a: Agent, dt: float) -> void:
	var c := a.cell()
	var r := Cfg.WARM_RADIUS
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var f: Campfire = World.fires.get(c + Vector2i(dx, dy))
			if f and f.burning():
				warm_t += dt
				if warm_t >= Cfg.WARM_SIT_SECS:
					warm_t = 0.0
					Actions.finish_warming(a, f)
				return
	warm_t = 0.0


## Other systems set jobs on every agent (fight back, flee, defend). On the player's body a
## job is only a marker that tells the sim it is fighting (so it isn't drafted or chatted
## to mid-fight); it never runs. Drop it when the fight is over, like the AI would.
func _job_hygiene(a: Agent, dt: float) -> void:
	var j := a.job
	if j == null:
		return
	var keep := false
	if j.kind == Job.Kind.FIGHT:
		var t: Agent = World.agents.get(j.target_id)
		keep = t != null and t.alive and World.dist(a.pos, t.pos) <= Cfg.CHASE_GIVE_UP
	elif j.kind == Job.Kind.FLEE:
		j.timer -= dt
		keep = j.timer > 0.0
	if not keep:
		Brain.set_job(a, null)
