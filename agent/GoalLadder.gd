class_name GoalLadder
## Fallback goals for an agent with nothing better to do (agreed).

static func next(a: Agent) -> Job:
	# 1. Keep some food on hand.
	if a.inv.count("berry") < 3:
		return Brain._gather_job("berry", 6)
	# 2-3. Tools.
	if not a.inv.has_tool("axe"):
		return craft_or_gather(a, "axe")
	if not a.inv.has_tool("pickaxe"):
		return craft_or_gather(a, "pickaxe")
	# 4. A weapon. Angry agents prefer clubs/bows, others spears.
	var has_weapon := a.inv.has_tool("club") or a.inv.has_tool("spear") or a.inv.has_tool("bow")
	if not has_weapon:
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
	# 6. Stockpile fuel.
	if a.inv.count("wood") < 10:
		return Brain._gather_job("wood", 10)
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
	World.drop_loot(a.cell(), {worst: n}, [])
	Brain._blacklist_cell(a, a.cell()) # don't immediately pick it back up
