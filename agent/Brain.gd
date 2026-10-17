class_name Brain
## Agent decision making (priority layers) and job execution.

enum Move { ARRIVED, MOVING, FAILED }
enum Obtain { WORKING, DONE, FAILED }

const BLACKLIST_SECS := 60.0
const NODE_SEARCH := 70.0

static var _blacklist := {} # "agent_id:cell" -> expiry time


static func update(a: Agent, dt: float) -> void:
	_needs(a, dt)
	if not a.alive:
		return
	a.attack_cd -= dt
	a.think_t -= dt
	if a.think_t <= 0.0:
		a.think_t += Cfg.THINK_INTERVAL
		var t := Time.get_ticks_usec()
		think(a)
		World.prof_add("think", t)
	if a.job:
		if World.profiling:
			var t2 := Time.get_ticks_usec()
			var k := a.job.kind
			_run(a, dt)
			World.prof_add("run_" + Job.Kind.keys()[k], t2)
		else:
			_run(a, dt)


static func _needs(a: Agent, dt: float) -> void:
	a.warmth = max(0.0, a.warmth - dt / Cfg.WARMTH_DRAIN_SECS)
	a.hunger = max(0.0, a.hunger - dt / Cfg.HUNGER_DRAIN_SECS)
	var empty := int(a.warmth <= 0.0) + int(a.hunger <= 0.0)
	if empty > 0:
		a.hp -= Cfg.HP_DRAIN_PER_NEED * empty * dt
		if a.hp <= 0.0:
			World.kill_agent(a, null)
	elif a.warmth > 0.5 and a.hunger > 0.5:
		a.hp = min(Cfg.MAX_HP, a.hp + Cfg.HP_REGEN * dt)


static func set_job(a: Agent, j: Job) -> void:
	if a.job and a.job.kind == Job.Kind.TASK and a.job.task and (j == null or j.task != a.job.task):
		if a.job.task.claimed_by == a.id:
			a.job.task.claimed_by = -1
	a.job = j
	a.path.clear()


static func flee(a: Agent, from: Vector2, from_id: int, prio: int = Job.PRIO_CRITICAL, dist: int = 10) -> void:
	var j := Job.new(Job.Kind.FLEE, prio)
	j.flee_from = from
	j.target_id = from_id
	var dir := (a.pos - from).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT.rotated(World.rng.randf() * TAU)
	var goal := Vector2i(a.pos + dir * dist)
	goal.x = clamp(goal.x, 1, Cfg.MAP_W - 2)
	goal.y = clamp(goal.y, 1, Cfg.MAP_H - 2)
	var c := World.random_walkable_near(goal, 2)
	j.cell = c if c != World.NO_CELL else a.cell()
	j.timer = 15.0
	set_job(a, j)


# --- Thinking ---

static func think(a: Agent) -> void:
	if a.job and a.job.prio >= Job.PRIO_CRITICAL:
		return
	# Needs layer.
	if a.hunger < Cfg.HUNGER_EAT and a.inv.count("berry") > 0:
		a.inv.remove("berry", 1)
		a.hunger = min(1.0, a.hunger + Cfg.BERRY_FOOD)
	var busy_prio := a.job.prio if a.job else -1
	if busy_prio < Job.PRIO_NEEDS:
		if a.warmth < Cfg.WARMTH_SEEK:
			set_job(a, _warm_job(a))
			return
		if a.hunger < Cfg.HUNGER_SEEK and a.inv.count("berry") == 0:
			# At home, eat from the chest before going out for berries (agreed).
			var ch := Stock.home_chest(a)
			if ch and ch.store.count("berry") > 0:
				set_job(a, chest_job(ch, {"berry": -3}, Job.PRIO_NEEDS))
				return
			var g := _gather_job("berry", 4, Job.PRIO_NEEDS)
			set_job(a, g)
			return
	# Social layer (may start fights).
	var ts := Time.get_ticks_usec()
	Relations.meet(a)
	Social.scan(a)
	World.prof_add("think_social", ts)
	if not a.alive or (a.job and a.job.prio >= Job.PRIO_CRITICAL):
		return
	if a.is_servant():
		_rebellion_check(a)
		if a.job and a.job.prio >= Job.PRIO_CRITICAL:
			return
	if a.job:
		return
	var j: Job = null
	var raid := Raids.find(a.raid_id) if a.raid_id != -1 else null
	var defend := Raids.find(a.defend_raid) if a.defend_raid != -1 else null
	if defend:
		j = Raids.defender_job(defend)
	elif raid:
		j = Raids.raider_job(raid)
	if j == null and a.is_servant():
		j = _servant_job(a)
	if j == null:
		j = _task_job(a)
	if j == null:
		j = _loot_job(a)
	if j == null:
		j = GoalLadder.next(a)
	if j == null:
		j = _roam_job(a)
	if j == null:
		j = _wander_job(a)
	set_job(a, j)


static func _warm_job(a: Agent) -> Job:
	var f := choose_fire(a)
	if f:
		var j := Job.new(Job.Kind.WARM, Job.PRIO_NEEDS)
		j.fire = f
		return j
	if a.inv.has_cost(Items.BUILD_COSTS["wild_fire"]):
		return Job.new(Job.Kind.PLACE_WILD_FIRE, Job.PRIO_NEEDS)
	return _gather_job("wood", a.inv.count("wood") + 2, Job.PRIO_NEEDS)


## Own faction's house fire first; wild fires if they're ours, shared happily, or we're desperate.
static func choose_fire(a: Agent) -> Campfire:
	var best: Campfire = null
	var best_d := INF
	var desperate := a.warmth < Cfg.DESPERATE_WARMTH
	for f in World.fires.values():
		if not f.burning() or _blacklisted(a, f.cell):
			continue
		var d := a.pos.distance_to(World.center(f.cell))
		if f.is_house:
			if f.owner_id != a.faction.id or d > 60.0:
				continue
			d *= 0.5 # strongly prefer home
		else:
			if d > 25.0:
				continue
			if f.owner_id != a.faction.id and not desperate and not (a.is_happy() and _happy_company(f, a)):
				continue
		if d < best_d:
			best_d = d
			best = f
	return best


static func _happy_company(f: Campfire, a: Agent) -> bool:
	for o in World.agents_near(World.center(f.cell), Cfg.WARM_RADIUS + 1):
		if o != a and not o.is_happy():
			return false
	return true


static func _rebellion_check(a: Agent) -> void:
	a.rebel_t += Cfg.THINK_INTERVAL
	if a.rebel_t < Cfg.REBEL_CHECK_SECS:
		return
	a.rebel_t = 0.0
	var m: Agent = World.agents.get(a.master_id)
	if m and a.stats.str >= m.stats.str * Cfg.REBEL_STR_RATIO and World.rng.randf() < Cfg.REBEL_CHANCE:
		EventBus.log_event("%s rebels against their master %s!" % [a.short(), m.short()])
		Combat.start_fight(a, m)


## Servant orders: help the master fight, do faction work, gather & deliver, or follow.
static func _servant_job(a: Agent) -> Job:
	var m: Agent = World.agents.get(a.master_id)
	if m == null:
		return null
	if m.job and m.job.kind == Job.Kind.FIGHT and World.agents.has(m.job.target_id):
		var f := Job.new(Job.Kind.FIGHT, Job.PRIO_ORDER)
		f.target_id = m.job.target_id
		return f
	var t := _task_job(a)
	if t:
		t.prio = Job.PRIO_ORDER
		return t
	if m.free_space() > 5 and World.rng.randf() < 0.7:
		var d := Job.new(Job.Kind.DELIVER, Job.PRIO_ORDER)
		d.target_id = m.id
		d.item = "wood" if m.inv.count("wood") <= m.inv.count("stone") else "stone"
		d.amount = min(8, a.free_space())
		return d
	var fj := Job.new(Job.Kind.FOLLOW, Job.PRIO_ORDER)
	fj.target_id = m.id
	fj.timer = 10.0
	return fj


static func _task_job(a: Agent) -> Job:
	var ok := func(c): return not _blacklisted(a, c)
	var t := a.faction.board.claim(a.id, a.cell(), ok)
	if t == null and a.faction.kingdom:
		t = a.faction.kingdom.board.claim(a.id, a.cell(), ok)
	if t == null:
		return null
	var j := Job.new(Job.Kind.TASK, Job.PRIO_TASK)
	j.task = t
	return j


static func _loot_job(a: Agent) -> Job:
	if a.free_space() <= 0:
		return null
	var best: LootBag = null
	var best_d := float(Cfg.LOOT_SEEK_RADIUS)
	for bag in World.loot.values():
		var d := a.pos.distance_to(World.center(bag.cell))
		if d < best_d and not _blacklisted(a, bag.cell):
			best_d = d
			best = bag
	if best == null:
		return null
	var j := Job.new(Job.Kind.LOOT, Job.PRIO_LADDER)
	j.cell = best.cell
	return j


## Nothing left on the ladder: angry agents prowl for victims, happy ones seek company
## (recruits, or other groups to trade with once their own group is full).
static func _roam_job(a: Agent) -> Job:
	if a.is_servant() or a.is_neutral():
		return null
	if a.is_happy() and World.rng.randf() > 0.3:
		return null
	var traders := a.is_happy() and not a.faction.solo and not a.faction.has_room()
	var best: Agent = null
	var best_d := 40.0 if a.is_angry() else 25.0
	for o in World.agents_near(a.pos, best_d):
		if o == a or World.same_side(o.faction.id, a.faction.id) or not a.can_interact(o.id):
			continue
		if a.is_happy() and o.is_angry():
			continue
		if traders and o.faction.solo:
			continue
		var d := a.pos.distance_to(o.pos)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return null
	var j := Job.new(Job.Kind.WANDER, Job.PRIO_IDLE)
	j.cell = World.approach_cell(a, best.cell(), 2)
	if j.cell == World.NO_CELL:
		return null
	j.timer = 15.0
	return j


## Idle wandering; settled agents hang around home.
static func _wander_job(a: Agent) -> Job:
	var j := Job.new(Job.Kind.WANDER, Job.PRIO_IDLE)
	var h := a.home()
	var around := a.cell()
	var radius := Cfg.WANDER_RADIUS
	if h and h.fire and h.state == House.State.COMPLETE:
		around = h.fire_cell
		radius = 6
	var c := World.random_walkable_near(around, radius)
	j.cell = c if c != World.NO_CELL else a.cell()
	j.timer = 20.0
	return j


static func chest_job(ch: Furniture, plan: Dictionary, prio: int = Job.PRIO_LADDER) -> Job:
	var j := Job.new(Job.Kind.CHEST, prio)
	j.chest = ch
	j.transfer = plan
	return j


static func _gather_job(item: String, amount: int, prio: int = Job.PRIO_LADDER) -> Job:
	var j := Job.new(Job.Kind.GATHER, prio)
	j.item = item
	j.amount = amount
	return j


# --- Running jobs ---

static func _run(a: Agent, dt: float) -> void:
	var j := a.job
	match j.kind:
		Job.Kind.WANDER: _run_wander(a, j, dt)
		Job.Kind.IDLE:
			j.timer -= dt
			if j.timer <= 0.0:
				_done(a)
		Job.Kind.GATHER:
			if _gather_step(a, j, dt):
				_done(a)
		Job.Kind.WARM: _run_warm(a, j, dt)
		Job.Kind.PLACE_WILD_FIRE: _run_place_wild_fire(a)
		Job.Kind.TASK: _run_task(a, j, dt)
		Job.Kind.FIGHT: _run_fight(a, j, dt)
		Job.Kind.FLEE: _run_flee(a, j, dt)
		Job.Kind.LOOT: _run_loot(a, j, dt)
		Job.Kind.DELIVER: _run_deliver(a, j, dt)
		Job.Kind.FOLLOW: _run_follow(a, j, dt)
		Job.Kind.CHEST:
			if _chest_step(a, j, dt):
				_done(a)
		Job.Kind.CRAFT: _run_craft(a, j, dt)
		Job.Kind.RAID: Raids.run_raider(a, j, dt)
		Job.Kind.DEFEND: Raids.run_defender(a, j, dt)


static func _done(a: Agent) -> void:
	set_job(a, null)


static func _run_wander(a: Agent, j: Job, dt: float) -> void:
	j.timer -= dt
	if j.timer <= 0.0 or move_to(a, j.cell, dt) != Move.MOVING:
		_done(a)


## Shared gathering logic. Returns true when finished (or impossible).
static func _gather_step(a: Agent, j: Job, dt: float) -> bool:
	if a.inv.count(j.item) >= j.amount:
		return true
	if a.free_space() <= 0:
		return true
	if j.item == "raw_iron" and not a.inv.has_tool("pickaxe_t2"):
		return true # nobody mines metal without a tier-2 pickaxe (agreed)
	if j.node == null or j.node.amount <= 0 or World.nodes.get(j.node.cell) != j.node:
		var type := ResourceNode.type_for_item(j.item)
		j.node = World.nearest_node(type, a.cell(), NODE_SEARCH, func(n): return not _blacklisted(a, n.cell))
		j.timer = 0.0
		j.arrived = false
		if j.node == null:
			return true
		j.cell = World.approach_cell(a, j.node.cell)
		if j.cell == World.NO_CELL:
			_blacklist_cell(a, j.node.cell)
			j.node = null
			return false
	if not j.arrived:
		var m := move_to(a, j.cell, dt)
		if m == Move.FAILED:
			_blacklist_cell(a, j.node.cell)
			j.node = null
			return false
		if m == Move.MOVING:
			return false
		j.arrived = true
	# Gathering at the node.
	var g := _gather_secs(a, j.node)
	var secs: float = g[0]
	var tool: String = g[1]
	j.timer += dt
	if j.timer >= secs:
		j.timer -= secs
		j.node.amount -= 1
		a.inv.add(j.item, 1)
		if j.node.type != ResourceNode.Type.BUSH:
			a.add_xp("str", Cfg.XP_GATHER)
		if tool != "" and a.inv.has_tool(tool) and a.inv.wear(tool):
			EventBus.log_event("%s's %s broke." % [a.short(), tool])
		if j.task:
			j.task.claim_time = SimClock.time
		if j.node.amount <= 0 and j.node.type != ResourceNode.Type.BUSH:
			World.remove_node(j.node)
			j.node = null
	return false


## Get everything in `cost` into the inventory: group chest first, then gather raw
## materials, processing them at a workshop machine for planks / handles / cut stone.
static func _obtain_step(a: Agent, j: Job, cost: Dictionary, dt: float, bulk: int = 1) -> int:
	if a.inv.has_cost(cost):
		j.chest = null
		j.machine = null
		return Obtain.DONE
	if j.chest:
		if _chest_step(a, j, dt):
			j.chest = null
			j.item = ""
		return Obtain.WORKING
	if j.machine:
		var r := _process_step(a, j, dt)
		if r != Obtain.WORKING:
			j.machine = null
			j.item = ""
			j.timer = 0.0
		return Obtain.FAILED if r == Obtain.FAILED else Obtain.WORKING
	if j.item == "" or a.inv.count(j.item) >= j.amount:
		if not _pick_material(a, j, cost, bulk):
			return Obtain.FAILED
		if j.chest or j.machine or j.item == "":
			return Obtain.WORKING
	if a.free_space() <= 0:
		GoalLadder.drop_junk(a, _keep_for(cost))
	if _gather_step(a, j, dt) and a.inv.count(j.item) < j.amount and not a.inv.has_cost(cost):
		return Obtain.FAILED
	return Obtain.WORKING


## Decide the next material step for the first missing item. False if it can't be had.
static func _pick_material(a: Agent, j: Job, cost: Dictionary, bulk: int) -> bool:
	j.item = ""
	j.node = null
	j.arrived = false
	for k in cost:
		var have := a.inv.count(k)
		if have >= cost[k]:
			continue
		var want: int = max(min(cost[k] * bulk, have + a.free_space()), cost[k])
		if a.free_space() > 0:
			var ch := Stock.group_chest_with(a, k)
			if ch:
				j.chest = ch
				j.transfer = {k: -(want - have)}
				return true
		if not Items.PROCESS.has(k):
			if ResourceNode.type_for_item(k) < 0 or (k == "raw_iron" and not a.inv.has_tool("pickaxe_t2")):
				return false
			j.item = k
			j.amount = want
			return true
		var p: Dictionary = Items.PROCESS[k]
		var raw_missing := ""
		for rk in p["in"]:
			if a.inv.count(rk) < p["in"][rk]:
				raw_missing = rk
		if raw_missing == "":
			var m := Factions.nearest_machine(a, p.machine)
			if m == null:
				return false
			j.machine = m
			j.item = k
			j.amount = want
			j.timer = 0.0
			return true
		var batches := int(ceil(float(want - have) / p.out))
		var raw_want: int = max(min(p["in"][raw_missing] * batches, a.inv.count(raw_missing) + a.free_space()), p["in"][raw_missing])
		if a.free_space() > 0:
			var ch := Stock.group_chest_with(a, raw_missing)
			if ch:
				j.chest = ch
				j.transfer = {raw_missing: -(raw_want - a.inv.count(raw_missing))}
				return true
		j.item = raw_missing
		j.amount = raw_want
		return true
	return true


## Items not to throw away while collecting `cost` (including raw inputs of processed items).
static func _keep_for(cost: Dictionary) -> Dictionary:
	var keep := cost.duplicate()
	for k in cost:
		if Items.PROCESS.has(k):
			for rk in Items.PROCESS[k]["in"]:
				keep[rk] = 1
	return keep


## Stand at the machine and run batches until we have j.amount of j.item or run out of input.
static func _process_step(a: Agent, j: Job, dt: float) -> int:
	var m := j.machine
	if not Items.PROCESS.has(j.item):
		return Obtain.DONE
	if m == null or World.furniture.get(m.cell) != m or m.house == null or not m.house.operational():
		return Obtain.FAILED
	var mv := move_to(a, m.cell, dt)
	if mv == Move.FAILED:
		_blacklist_cell(a, m.cell)
		return Obtain.FAILED
	if mv == Move.MOVING:
		return Obtain.WORKING
	var p: Dictionary = Items.PROCESS[j.item]
	if a.inv.count(j.item) >= j.amount or not a.inv.has_cost(p["in"]):
		return Obtain.DONE
	j.timer += dt
	if j.timer >= p.secs:
		j.timer = 0.0
		a.inv.pay(p["in"])
		a.inv.add(j.item, p.out)
		if j.task:
			j.task.claim_time = SimClock.time
	return Obtain.WORKING


## Workshop-only recipes (raiding axe): collect materials, then craft at a workshop.
static func _run_craft(a: Agent, j: Job, dt: float) -> void:
	var cost: Dictionary = Items.RECIPES[j.then_craft]
	var r := _obtain_step(a, j, cost, dt)
	if r == Obtain.FAILED:
		_done(a)
		return
	if r == Obtain.WORKING:
		return
	var m := Factions.nearest_machine(a, Furniture.Kind.SAWMILL)
	if m == null:
		_done(a)
		return
	var mv := move_to(a, m.cell, dt)
	if mv == Move.FAILED:
		_blacklist_cell(a, m.cell)
		_done(a)
	elif mv == Move.ARRIVED:
		a.inv.pay(cost)
		a.inv.add_tool(j.then_craft)
		EventBus.log_event("%s crafts a %s." % [a.short(), Items.label(j.then_craft)])
		_done(a)


## Walk to j.chest and apply j.transfer. Returns true when finished (or impossible).
static func _chest_step(a: Agent, j: Job, dt: float) -> bool:
	var ch := j.chest
	if ch == null or World.furniture.get(ch.cell) != ch:
		return true
	var m := move_to(a, ch.cell, dt)
	if m == Move.FAILED:
		_blacklist_cell(a, ch.cell)
		return true
	if m == Move.MOVING:
		return false
	Stock.transfer(a, ch, j.transfer)
	return true


## [seconds per unit, tool used] for harvesting this node.
static func _gather_secs(a: Agent, n: ResourceNode) -> Array:
	var secs: float
	var tool := ""
	match n.type:
		ResourceNode.Type.TREE:
			secs = Cfg.GATHER_WOOD
			tool = "axe"
		ResourceNode.Type.ROCK:
			secs = Cfg.GATHER_STONE
			tool = "pickaxe" if a.inv.has_tool("pickaxe") or not a.inv.has_tool("pickaxe_t2") else "pickaxe_t2"
		ResourceNode.Type.METAL:
			secs = Cfg.GATHER_METAL
			tool = "pickaxe_t2" # the only tool that mines metal (agreed)
		ResourceNode.Type.HEMP:
			secs = Cfg.GATHER_HEMP
		_:
			secs = Cfg.GATHER_BERRY
	secs /= a.gather_mult()
	if tool != "" and a.inv.has_tool(tool):
		secs /= Cfg.TOOL_GATHER_MULT
	return [secs, tool]


static func _run_warm(a: Agent, j: Job, dt: float) -> void:
	var f := j.fire
	if f == null or not f.burning() or World.fires.get(f.cell) != f:
		_done(a)
		return
	if not j.arrived:
		if j.cell == Vector2i.ZERO or World.cheb(j.cell, f.cell) > Cfg.WARM_RADIUS:
			j.cell = World.approach_cell(a, f.cell, Cfg.WARM_RADIUS)
			if j.cell == World.NO_CELL:
				_blacklist_cell(a, f.cell)
				_done(a)
				return
		var m := move_to(a, j.cell, dt)
		if m == Move.FAILED:
			_blacklist_cell(a, f.cell)
			_done(a)
			return
		if m == Move.MOVING:
			return
		j.arrived = true
	j.timer += dt
	if j.timer >= Cfg.WARM_SIT_SECS:
		a.warmth = 1.0
		for o in World.agents_near(World.center(f.cell), Cfg.WARM_RADIUS + 1):
			if o.faction != a.faction and not o.faction.solo and not a.faction.solo:
				Relations.shared_fire(a.faction, o.faction)
		if a.is_happy():
			for o in World.agents_near(World.center(f.cell), Cfg.WARM_RADIUS + 1):
				if o != a and o.is_happy() and o.faction != a.faction:
					a.change_opinion(o.id, 5.0)
					o.change_opinion(a.id, 5.0)
		_done(a)


static func _run_place_wild_fire(a: Agent) -> void:
	var cost: Dictionary = Items.BUILD_COSTS["wild_fire"]
	if not a.inv.has_cost(cost):
		_done(a)
		return
	var here := a.cell()
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c: Vector2i = here + d
		if World.can_build(c, a.faction.id):
			a.inv.pay(cost)
			var f := World.place_fire(c, false, a.faction.id)
			f.placed_by = a.id
			var j := Job.new(Job.Kind.WARM, Job.PRIO_NEEDS)
			j.fire = f
			set_job(a, j)
			return
	# Nowhere to put it here; step somewhere else and try again next think.
	set_job(a, _wander_job(a))
	a.job.prio = Job.PRIO_NEEDS
	a.job.timer = 3.0


static func _run_task(a: Agent, j: Job, dt: float) -> void:
	var t := j.task
	if t == null or t.done or t.claimed_by != a.id or t.board == null:
		_done(a)
		return
	# Gather materials first.
	var cost := t.cost()
	if t.type == Task.Type.REFUEL:
		var fire: Campfire = World.fires.get(t.cell)
		if fire == null:
			t.board.complete(t)
			_done(a)
			return
		cost = {"wood": max(1, min(fire.wood_space(), a.capacity() / 2))}
	if not a.inv.has_cost(cost):
		# Gather a bit extra for walls/floors so one trip covers several tasks.
		var bulk := 4 if t.type in [Task.Type.BUILD_WALL, Task.Type.BUILD_FLOOR, Task.Type.UPGRADE_WALL] else 1
		if _obtain_step(a, j, cost, dt, bulk) == Obtain.FAILED:
			_blacklist_cell(a, t.cell)
			_done(a) # couldn't get materials
		return
	j.item = ""
	# Go to the site.
	if not j.arrived or World.cheb(a.cell(), t.cell) > 1:
		if j.cell == Vector2i.ZERO or World.cheb(j.cell, t.cell) > 1:
			j.cell = World.approach_cell(a, t.cell)
			if j.cell == World.NO_CELL:
				j.timer += dt
				if j.timer > 10.0:
					_blacklist_cell(a, t.cell)
					_done(a)
				return
		var m := move_to(a, j.cell, dt)
		if m == Move.FAILED:
			_blacklist_cell(a, t.cell)
			_done(a)
			return
		if m == Move.MOVING:
			return
		j.arrived = true
	_perform_task(a, j, t, cost, dt)


static func _perform_task(a: Agent, j: Job, t: Task, cost: Dictionary, dt: float) -> void:
	var board := t.board
	var fid := a.faction.id
	match t.type:
		Task.Type.BUILD_FLOOR:
			if World.floors.has(t.cell):
				board.complete(t)
				_done(a)
				return
			if not World.can_floor(t.cell, fid):
				if World.is_solid(t.cell) or World.privilege_owner(t.cell) not in [0, fid]:
					board.complete(t)
					_done(a)
					return
				j.timer += dt
				if j.timer > 20.0:
					_done(a)
				return
			a.inv.pay(cost)
			World.place_floor(t.cell, fid)
			board.complete(t)
			_done(a)
		Task.Type.PLACE_CHEST:
			if World.furniture.has(t.cell) or t.house == null or t.house.live_chest() != null:
				board.complete(t)
				_done(a)
				return
			if not World.floors.has(t.cell):
				_done(a) # floor first; housekeeping re-posts it
				return
			a.inv.pay(cost)
			t.house.chest = World.place_furniture(t.cell, Furniture.Kind.CHEST, fid, t.house)
			board.complete(t)
			_done(a)
		Task.Type.CLEAR_NODE:
			var n: ResourceNode = World.nodes.get(t.cell)
			if n == null or n.amount <= 0:
				if n:
					World.remove_node(n)
				board.complete(t)
				_done(a)
				return
			# Chop or mine it down to nothing; keep what fits.
			var g := _gather_secs(a, n)
			j.timer += dt
			if j.timer >= g[0]:
				j.timer = 0.0
				n.amount -= 1
				if a.free_space() > 0 and (n.type != ResourceNode.Type.METAL or a.inv.has_tool("pickaxe_t2")):
					a.inv.add(n.item(), 1)
				a.add_xp("str", Cfg.XP_GATHER)
				if g[1] != "" and a.inv.has_tool(g[1]) and a.inv.wear(g[1]):
					EventBus.log_event("%s's %s broke." % [a.short(), g[1]])
				t.claim_time = SimClock.time
				if n.amount <= 0:
					World.remove_node(n)
					board.complete(t)
					_done(a)
		Task.Type.DEMOLISH:
			if not Cities.is_junk(t.cell):
				board.complete(t) # gone already, or part of a live building again
				_done(a)
				return
			j.timer += dt
			t.claim_time = SimClock.time
			if j.timer >= Cfg.DEMOLISH_SECS:
				Cities.demolish(t.cell) # no refund (agreed)
				board.complete(t)
				_done(a)
		Task.Type.BUILD_ROAD, Task.Type.UPGRADE_ROAD:
			var tier := 1 if t.type == Task.Type.BUILD_ROAD else 2
			if World.roads.get(t.cell, 0) >= tier or World.walls.has(t.cell) or World.fires.has(t.cell):
				board.complete(t)
				_done(a)
				return
			if World.nodes.has(t.cell):
				_done(a) # being cleared
				return
			# Paving breaks the stone road first (agreed upgrade rule).
			a.inv.pay(cost)
			World.place_road(t.cell, tier)
			board.complete(t)
			_done(a)
		Task.Type.PLACE_BOARD:
			var fu: Furniture = World.furniture.get(t.cell)
			if fu or World.is_solid(t.cell):
				board.complete(t)
				_done(a)
				return
			a.inv.pay(cost)
			World.place_furniture(t.cell, Furniture.Kind.BOARD, fid, null)
			board.complete(t)
			_done(a)
		Task.Type.PLACE_MACHINE:
			if World.furniture.has(t.cell) or t.house == null or t.house.furniture_kind_at(t.cell) < 0:
				board.complete(t)
				_done(a)
				return
			if not World.floors.has(t.cell):
				_done(a)
				return
			a.inv.pay(cost)
			World.place_furniture(t.cell, t.house.furniture_kind_at(t.cell), fid, t.house)
			board.complete(t)
			_done(a)
		Task.Type.UPGRADE_WALL, Task.Type.UPGRADE_DOOR:
			var w: Wall = World.walls.get(t.cell)
			if (w and (w.tier >= t.tier or w.owner_id != fid)) or (w == null and not World.can_build(t.cell, fid)):
				board.complete(t)
				_done(a)
				return
			# Break the old piece (no refund), then place the reinforced one (agreed).
			if w:
				World.remove_wall(w)
			a.inv.pay(cost)
			var door := t.type == Task.Type.UPGRADE_DOOR
			World.place_wall(t.cell, door, fid, t.tier, door and t.house != null and not t.house.is_home())
			board.complete(t)
			_done(a)
		Task.Type.UPGRADE_CHEST:
			var old: Furniture = t.house.live_chest() if t.house else null
			if old == null or old.tier >= t.tier:
				board.complete(t)
				_done(a)
				return
			a.inv.pay(cost)
			World.furniture.erase(old.cell)
			var nc := World.place_furniture(old.cell, Furniture.Kind.CHEST, fid, t.house, t.tier)
			nc.store = old.store # contents carry over
			t.house.chest = nc
			board.complete(t)
			_done(a)
		Task.Type.REFUEL:
			var fire: Campfire = World.fires.get(t.cell)
			if fire:
				var n: int = min(a.inv.count("wood"), fire.wood_space())
				a.inv.remove("wood", n)
				fire.add_wood(n)
			board.complete(t)
			_done(a)
		Task.Type.PLACE_HOUSE_FIRE, Task.Type.BUILD_WALL, Task.Type.BUILD_DOOR:
			if World.walls.has(t.cell) or World.fires.has(t.cell):
				board.complete(t) # already there
				_done(a)
				return
			if World.loot.has(t.cell):
				World.take_loot(a, World.loot[t.cell])
			if not World.can_build(t.cell, fid):
				if World.nodes.has(t.cell) or (World.privilege_owner(t.cell) not in [0, fid]):
					if t.type == Task.Type.PLACE_HOUSE_FIRE:
						Factions.destroy_house(t.house)
					else:
						board.complete(t)
					_done(a)
					return
				j.timer += dt # someone standing there; wait for them to move
				if j.timer > 20.0:
					_done(a)
				return
			if t.type == Task.Type.PLACE_HOUSE_FIRE and not World.house_fire_spacing_ok(t.cell, t.house, fid, not t.house.is_home()):
				Factions.destroy_house(t.house)
				_done(a)
				return
			a.inv.pay(cost)
			if t.type == Task.Type.PLACE_HOUSE_FIRE:
				var f := World.place_fire(t.cell, true, fid)
				board.complete(t)
				Factions.on_house_fire_placed(t.house, f)
				if not a.faction.solo:
					EventBus.log_event("%s claims land for %s." % [a.short(), a.faction.name])
			else:
				var door := t.type == Task.Type.BUILD_DOOR
				var tier: int = 0 if door or t.house == null else t.house.base_wall_tier()
				World.place_wall(t.cell, door, fid, tier, door and t.house != null and not t.house.is_home())
				board.complete(t)
			_done(a)


static func _run_fight(a: Agent, j: Job, dt: float) -> void:
	var t: Agent = World.agents.get(j.target_id)
	if t == null or not t.alive or t == a:
		_done(a)
		return
	var d := a.pos.distance_to(t.pos)
	if d > Cfg.CHASE_GIVE_UP:
		_done(a)
		return
	if a.attack_cd <= 0.0:
		if a.has_bow_ready() and d > 1.6 and d <= a.bow_range():
			if Combat.attack(a, t, "bow"):
				return
		var w := a.melee_weapon()
		if d <= Items.WEAPONS[w].reach:
			Combat.attack(a, t, w)
			return
	elif d <= Items.WEAPONS[a.melee_weapon()].reach or (a.has_bow_ready() and d <= a.bow_range() and d > 1.6):
		return # in range, waiting for cooldown
	# Chase.
	j.repath_t -= dt
	if j.repath_t <= 0.0 or a.path.is_empty():
		j.repath_t = 0.5
		j.cell = World.approach_cell(a, t.cell())
		a.path.clear()
	if j.cell != World.NO_CELL:
		move_to(a, j.cell, dt)


static func _run_flee(a: Agent, j: Job, dt: float) -> void:
	j.timer -= dt
	if j.timer <= 0.0 or move_to(a, j.cell, dt) != Move.MOVING:
		_done(a)


static func _run_loot(a: Agent, j: Job, dt: float) -> void:
	var bag: LootBag = World.loot.get(j.cell)
	if bag == null:
		_done(a)
		return
	var m := move_to(a, j.cell, dt)
	if m == Move.FAILED:
		_blacklist_cell(a, j.cell)
		_done(a)
	elif m == Move.ARRIVED:
		World.take_loot(a, bag)
		_done(a)


static func _run_deliver(a: Agent, j: Job, dt: float) -> void:
	var m: Agent = World.agents.get(j.target_id)
	if m == null or not a.is_servant():
		_done(a)
		return
	if j.phase == 0:
		if _gather_step(a, j, dt):
			j.phase = 1 # done gathering → deliver
			a.path.clear()
		return
	if a.pos.distance_to(m.pos) <= 1.6:
		var n: int = min(a.inv.count(j.item), m.free_space())
		a.inv.remove(j.item, n)
		m.inv.add(j.item, n)
		_done(a)
		return
	j.repath_t -= dt
	if j.repath_t <= 0.0 or a.path.is_empty():
		j.repath_t = 1.0
		j.cell = World.approach_cell(a, m.cell())
		a.path.clear()
	if j.cell == World.NO_CELL or move_to(a, j.cell, dt) == Move.FAILED:
		_done(a)


static func _run_follow(a: Agent, j: Job, dt: float) -> void:
	var m: Agent = World.agents.get(j.target_id)
	j.timer -= dt
	if m == null or j.timer <= 0.0:
		_done(a)
		return
	if a.pos.distance_to(m.pos) <= 3.0:
		return
	j.repath_t -= dt
	if j.repath_t <= 0.0 or a.path.is_empty():
		j.repath_t = 1.0
		j.cell = World.approach_cell(a, m.cell(), 2)
		a.path.clear()
	if j.cell != World.NO_CELL:
		move_to(a, j.cell, dt)


# --- Movement ---

static func move_to(a: Agent, dest: Vector2i, dt: float) -> int:
	if dest == World.NO_CELL:
		return Move.FAILED
	var goal := World.center(dest)
	if a.cell() == dest and a.pos.distance_to(goal) < 0.15:
		return Move.ARRIVED
	if a.path.is_empty() or a.path[a.path.size() - 1] != dest:
		a.path = World.find_path(a, dest)
		a.path_i = 1
		if a.path.is_empty():
			return Move.FAILED
	var step := a.speed() * dt
	while step > 0.0:
		var next: Vector2i = a.path[a.path_i] if a.path_i < a.path.size() else dest
		if next != a.cell() and not World.passable(a, next):
			a.path.clear() # blocked; repath next step
			return Move.MOVING
		var target := World.center(next)
		var to := target - a.pos
		var dist := to.length()
		if dist <= step:
			a.pos = target
			step -= dist
			a.add_xp("agi", Cfg.XP_PER_CELL)
			if a.path_i >= a.path.size():
				return Move.ARRIVED
			a.path_i += 1
		else:
			a.pos += to / dist * step
			step = 0.0
	return Move.MOVING


# --- Blacklist (unreachable targets) ---

static func _blacklisted(a: Agent, c: Vector2i) -> bool:
	var key := "%d:%d,%d" % [a.id, c.x, c.y]
	var t = _blacklist.get(key)
	if t == null:
		return false
	if SimClock.time > t:
		_blacklist.erase(key)
		return false
	return true


static func _blacklist_cell(a: Agent, c: Vector2i) -> void:
	_blacklist["%d:%d,%d" % [a.id, c.x, c.y]] = SimClock.time + BLACKLIST_SECS
