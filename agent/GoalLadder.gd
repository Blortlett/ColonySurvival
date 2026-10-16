class_name GoalLadder
## Fallback goals for an agent with nothing better to do (agreed).

static func next(a: Agent) -> Job:
	# 1. Keep some food on hand.
	if a.inv.count("berry") < 3:
		return Brain._gather_job("berry", 6)
	# 2-3. Tools (a spare from the home chest first).
	var ch := Stock.home_chest(a)
	for t in ["axe", "pickaxe"]:
		if not a.inv.has_tool(t):
			if ch and ch.store.has_tool(t) and a.free_space() > 0:
				return Brain.chest_job(ch, {"tool:" + t: -1})
			return craft_or_gather(a, t)
	# 4. A weapon. Angry agents prefer clubs/bows, others spears.
	if not Stock.has_weapon(a.inv):
		if ch and a.free_space() > 0:
			for w in Stock.WEAPONS:
				if ch.store.has_tool(w):
					return Brain.chest_job(ch, {"tool:" + w: -1})
		var w := "spear"
		if a.is_angry():
			w = "club" if a.id % 2 == 0 else "bow"
		return craft_or_gather(a, w)
	if a.inv.has_tool("bow") and a.inv.count("arrow") < 10:
		return craft_or_gather(a, "arrow")
	# 5. A home. Solo agents found their own; factions plan houses in housekeeping.
	if a.home() == null and a.faction.solo:
		var planned := false
		for h in a.faction.houses:
			if h.state == House.State.PLANNED:
				planned = true
		if not planned:
			var h := Factions.plan_house(a.faction, 1)
			if h:
				h.occupants.append(a.id)
				return null # the new task gets picked up next think
	# Group steps 2-3: the chest is placed by a board task; then stock it (agreed).
	var sj := _stock_job(a, ch)
	if sj:
		return sj
	# 6. Stockpile fuel.
	if a.inv.count("wood") < 10:
		return Brain._gather_job("wood", 10)
	return null


## Deposit what the chest needs (or surplus once we're getting full); otherwise go get what it lacks.
static func _stock_job(a: Agent, ch: Furniture) -> Job:
	if ch == null:
		return null
	var plan := Stock.deposit_plan(a, ch)
	if not plan.is_empty():
		return Brain.chest_job(ch, plan)
	var room := ch.free_slots()
	if room <= 0:
		return null # chest full (a basic chest can't hold the whole goal for a big group)
	var need := Stock.shortfall(ch, a.faction)
	if need.has("berry") and a.free_space() > 2:
		return Brain._gather_job("berry", Cfg.KEEP_BERRIES + min(min(need.berry, room), 10))
	for t in Stock.SPARE_TOOLS:
		if need.has("tool:" + t):
			return craft_or_gather(a, t)
	if need.has("weapon"):
		return craft_or_gather(a, "spear")
	return null


## Craft if we can afford it, otherwise gather the first missing material.
static func craft_or_gather(a: Agent, item: String) -> Job:
	var cost: Dictionary = Items.RECIPES[item]
	if a.inv.has_cost(cost):
		a.inv.pay(cost)
		if item == "arrow":
			a.inv.add("arrow", Items.ARROWS_PER_CRAFT)
		else:
			a.inv.add_tool(item)
		var j := Job.new(Job.Kind.IDLE, Job.PRIO_LADDER)
		j.timer = 2.0 # crafting time
		return j
	if a.free_space() < 4:
		drop_junk(a, cost)
	for k in cost:
		if a.inv.count(k) < cost[k]:
			return Brain._gather_job(k, cost[k])
	return null


## Inventory full: drop half of the most plentiful stackable we don't currently need.
static func drop_junk(a: Agent, keep: Dictionary) -> void:
	var worst := ""
	var worst_n := 0
	for k in a.inv.stacks:
		if keep.has(k) or k == "berry":
			continue
		if a.inv.stacks[k] > worst_n:
			worst_n = a.inv.stacks[k]
			worst = k
	if worst == "":
		return
	var n := int(ceil(worst_n / 2.0))
	a.inv.remove(worst, n)
	World.drop_loot(a.cell(), {worst: n}, [], a.id, "dumped junk")
	Brain._blacklist_cell(a, a.cell()) # don't immediately pick it back up
