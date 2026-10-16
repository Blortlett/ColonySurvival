class_name Stock
## Group chests: the stocking goal, surplus deposits and withdrawals.
## Transfer plans map item -> count (positive = deposit, negative = withdraw); tools use "tool:<type>".

const SPARE_TOOLS := ["axe", "pickaxe"]
const WEAPONS := ["spear", "club", "bow"]


## The agent's home chest, if it has one and is close enough to use it.
static func home_chest(a: Agent) -> Furniture:
	var h := a.home()
	if h == null:
		return null
	var ch := h.live_chest()
	if ch == null or a.pos.distance_to(World.center(ch.cell)) > Cfg.HOME_RANGE or Brain._blacklisted(a, ch.cell):
		return null
	return ch


## Any chest of the agent's group holding `item`, within range.
static func group_chest_with(a: Agent, item: String) -> Furniture:
	var best: Furniture = null
	var best_d := Cfg.HOME_RANGE
	for h in a.faction.houses:
		var ch := h.live_chest()
		if ch == null or ch.store.count(item) <= 0 or Brain._blacklisted(a, ch.cell):
			continue
		var d := a.pos.distance_to(World.center(ch.cell))
		if d <= best_d:
			best_d = d
			best = ch
	return best


## What the chest still lacks for the stocking goal (agreed): 5 berries per member,
## 1 spare axe, 1 spare pickaxe, 1 spare weapon.
static func shortfall(ch: Furniture, f: Faction) -> Dictionary:
	var out := {}
	var b: int = Cfg.STOCK_BERRIES_PER_MEMBER * f.members.size() - ch.store.count("berry")
	if b > 0:
		out["berry"] = b
	for t in SPARE_TOOLS:
		if not ch.store.has_tool(t):
			out["tool:" + t] = 1
	if not has_weapon(ch.store):
		out["weapon"] = 1
	return out


static func has_weapon(inv: Inventory) -> bool:
	for w in WEAPONS:
		if inv.has_tool(w):
			return true
	return false


## Items the agent carries beyond what it keeps on itself.
static func surplus(a: Agent) -> Dictionary:
	var out := {}
	var b := a.inv.count("berry") - Cfg.KEEP_BERRIES
	if b > 0:
		out["berry"] = b
	for k in Cfg.KEEP_STACKS:
		var n: int = a.inv.count(k) - Cfg.KEEP_STACKS[k]
		if n > 0:
			out[k] = n
	var seen := {}
	for t in a.inv.tools:
		seen[t.type] = seen.get(t.type, 0) + 1
	for k in seen:
		if seen[k] > 1:
			out["tool:" + k] = seen[k] - 1
	return out


## Deposit plan: stocking needs first, then other surplus once the agent is getting full.
static func deposit_plan(a: Agent, ch: Furniture) -> Dictionary:
	var room := ch.free_slots()
	var sur := surplus(a)
	var need := shortfall(ch, a.faction)
	var plan := {}
	var reserve := 0
	for k in need:
		reserve += need[k]
	for k in sur:
		var want := 0
		if k == "berry":
			want = need.get("berry", 0)
		elif k.begins_with("tool:"):
			var t: String = k.substr(5)
			if need.has(k) or (need.has("weapon") and t in WEAPONS):
				want = 1
		var n: int = min(sur[k], min(want, room))
		if n > 0:
			plan[k] = n
			room -= n
			reserve -= n
	if a.inv.total() >= a.capacity() * 0.6:
		var extra: int = room - max(0, reserve)
		for k in sur:
			var n: int = min(sur[k] - plan.get(k, 0), extra)
			if n > 0:
				plan[k] = plan.get(k, 0) + n
				extra -= n
	return plan


## Move items between agent and chest. Returns how many units moved.
static func transfer(a: Agent, ch: Furniture, plan: Dictionary) -> int:
	var moved := 0
	for k in plan:
		var n: int = plan[k]
		if k.begins_with("tool:"):
			var t: String = k.substr(5)
			for i in abs(n):
				if n > 0:
					var tool = _spare_tool(a.inv, t)
					if tool == null or ch.free_slots() <= 0:
						break
					a.inv.tools.erase(tool)
					ch.store.tools.append(tool)
				else:
					var tool = ch.store.get_tool(t)
					if tool == null or a.free_space() <= 0:
						break
					ch.store.tools.erase(tool)
					a.inv.tools.append(tool)
				moved += 1
		elif n > 0:
			var m: int = min(n, min(a.inv.count(k), ch.free_slots()))
			a.inv.remove(k, m)
			ch.store.add(k, m)
			moved += m
		else:
			var m: int = min(-n, min(ch.store.count(k), a.free_space()))
			ch.store.remove(k, m)
			a.inv.add(k, m)
			moved += m
	return moved


## The freshest copy of a tool: spares in the chest should be in good shape; the agent keeps using the worn one.
static func _spare_tool(inv: Inventory, t: String):
	var best = null
	for tool in inv.tools:
		if tool.type == t and (best == null or tool.dur > best.dur):
			best = tool
	return best
