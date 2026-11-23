class_name Actions
## Shared verbs (Player Controller Plan §1): the only way a body changes the world.
## The AI (Brain, Raids) and the PlayerController both call these, so costs, durability,
## damage, privileges and build rules stay identical for everyone.
## Distances and directions go through World.delta / World.dist (Summer Roadmap §2).

enum Move { ARRIVED, MOVING, FAILED }

const PLAYER_HALF := 0.3 # half the player's collision box, in cells
const PIECES := ["wall", "door", "floor", "wild_fire"] # what the player can place by hand


# --- Movement ---

## Path movement for NPCs (agreed): A* through cell centres, no wall collision needed.
static func move_path(a: Agent, dest: Vector2i, dt: float) -> int:
	if dest == World.NO_CELL:
		return Move.FAILED
	var goal := World.center(dest)
	if a.cell() == dest and World.dist(a.pos, goal) < 0.15:
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
		var to := World.delta(a.pos, target)
		var dist := to.length()
		if dist <= step:
			a.pos = target
			step -= dist
			a.add_xp("agi", Cfg.XP_PER_CELL)
			if a.path_i >= a.path.size():
				return Move.ARRIVED
			a.path_i += 1
		else:
			a.move_dir = to / dist
			a.pos += a.move_dir * step
			step = 0.0
	return Move.MOVING


## Free movement for the player (agreed): move by `motion` cells, colliding with cells this
## agent can't pass (walls, closed doors, nodes, fires, the map edge) and sliding along
## them. Axis by axis, so a diagonal push into a wall keeps the parallel part. Cells the
## box already overlaps don't block, so a body never gets stuck inside a new piece.
## Returns the motion actually made.
static func move_free(a: Agent, motion: Vector2) -> Vector2:
	var start := a.pos
	var stuck := _box_cells(a.pos)
	for axis in 2:
		if motion[axis] == 0.0:
			continue
		var p := a.pos
		p[axis] += motion[axis]
		if _box_clear(a, p, stuck):
			a.pos = p
		else:
			# Slide up to the blocking cell's edge instead of stopping short.
			var edge: float
			if motion[axis] > 0.0:
				edge = floor(a.pos[axis] + PLAYER_HALF + motion[axis]) - PLAYER_HALF - 0.001
				p[axis] = max(a.pos[axis], edge)
			else:
				edge = floor(a.pos[axis] - PLAYER_HALF + motion[axis]) + 1.0 + PLAYER_HALF + 0.001
				p[axis] = min(a.pos[axis], edge)
			if _box_clear(a, p, stuck):
				a.pos = p
	var moved := World.delta(start, a.pos)
	if moved != Vector2.ZERO:
		a.move_dir = moved.normalized()
	return moved


static func _box_cells(p: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(int(floor(p.x - PLAYER_HALF)), int(floor(p.x + PLAYER_HALF)) + 1):
		for y in range(int(floor(p.y - PLAYER_HALF)), int(floor(p.y + PLAYER_HALF)) + 1):
			out.append(Vector2i(x, y))
	return out


static func _box_clear(a: Agent, p: Vector2, ignore: Array[Vector2i]) -> bool:
	for c in _box_cells(p):
		if not ignore.has(c) and not World.passable(a, c):
			return false
	return true


## True if the player's box at `p` overlaps cell c.
static func box_overlaps(p: Vector2, c: Vector2i) -> bool:
	return _box_cells(p).has(c)


# --- Combat ---

## Turn to face a point (NPCs face their target before a swing or a shot).
static func face(a: Agent, point: Vector2) -> void:
	var d := World.delta(a.pos, point)
	if d != Vector2.ZERO:
		a.facing = d.normalized()


## A melee swing in direction `dir` (Player Controller Plan §3): hits every agent it can hit
## (see can_hit) inside the arc and within the weapon's reach.
## Damage, cooldown, durability, armour and plead / surrender stay in Combat.
## With no agent hit, a wall or door in front takes the blow (not the swinger's own).
## Returns the number of agents hit.
static func swing(a: Agent, dir: Vector2, weapon: String) -> int:
	if a.attack_cd > 0.0:
		return 0
	if dir != Vector2.ZERO:
		a.facing = dir.normalized()
	var w: Dictionary = Items.WEAPONS[weapon]
	var reach: float = w.reach
	var half_cos := cos(deg_to_rad(Cfg.SWING_ARC_DEG) * 0.5)
	var hit: Array[Agent] = []
	for o in World.agents_near(a.pos, reach):
		if o == a or not o.alive or not can_hit(a, o):
			continue
		var d := World.delta(a.pos, o.pos)
		var len := d.length()
		if len > reach:
			continue
		if len > 0.01 and a.facing.dot(d / len) < half_cos:
			continue
		hit.append(o)
	a.last_swing = SimClock.time
	if hit.is_empty():
		var wall: Wall = World.walls.get(Vector2i((a.pos + a.facing * 0.9).floor()))
		if wall and wall.owner_id != a.faction.id:
			Combat.attack_wall(a, wall)
		else:
			a.attack_cd = w.cooldown # a swing at the air still takes the time
		return 0
	World.swing_stats.swings += 1
	World.swing_stats.hits += hit.size()
	var aimed := a.job.target_id if a.job and a.job.kind == Job.Kind.FIGHT else -1
	for o in hit:
		if o.id != aimed:
			World.swing_stats.extra_hits += 1
	Combat.melee_swing(a, hit, weapon)
	return hit.size()


## Who a swing can hit. Anyone the two are already fighting (a servant's rebellion, a fight
## to the death inside a group) always; never anyone else on the swinger's side (group or
## kingdom). Bystanders: the player's swing hits them; an NPC's only with
## Cfg.NPC_SWING_HITS_BYSTANDERS.
static func can_hit(a: Agent, o: Agent) -> bool:
	if engaged(a, o):
		return true
	if World.same_side(o.faction.id, a.faction.id):
		return false
	return a.is_player() or Cfg.NPC_SWING_HITS_BYSTANDERS


## True if a and o are fighting each other (either one's FIGHT job, or a fight to the death).
static func engaged(a: Agent, o: Agent) -> bool:
	if a.death_match.has(o.id):
		return true
	if a.job != null and a.job.kind == Job.Kind.FIGHT and a.job.target_id == o.id:
		return true
	return o.job != null and o.job.kind == Job.Kind.FIGHT and o.job.target_id == a.id


## A bow shot at an agent (line of sight as today). Faces the target first.
static func shoot(a: Agent, t: Agent) -> bool:
	face(a, t.pos)
	return Combat.attack(a, t, "bow")


# --- Gathering ---

## [seconds per unit, tool used] for harvesting this node.
static func harvest_secs(a: Agent, n: ResourceNode) -> Array:
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


## Can this agent take anything from the node? (Metal needs the tier-2 pickaxe; agreed.)
static func can_harvest(a: Agent, n: ResourceNode) -> bool:
	return n.amount > 0 and (n.type != ResourceNode.Type.METAL or a.inv.has_tool("pickaxe_t2"))


## Take one unit off the node: `give` puts it in the inventory, `xp` trains STR, the tool
## wears. A spent tree, rock, hemp or metal node is removed (bushes regrow).
## Returns true if the node was removed.
static func harvest_unit(a: Agent, n: ResourceNode, tool: String, give: bool, xp: bool) -> bool:
	n.amount -= 1
	if n.type == ResourceNode.Type.BUSH:
		World.static_dirty = true # berries are drawn in StaticLayer
	if give:
		a.inv.add(n.item(), 1)
	if xp:
		a.add_xp("str", Cfg.XP_GATHER)
	if tool != "" and a.inv.has_tool(tool) and a.inv.wear(tool):
		EventBus.log_event("%s's %s broke." % [a.short(), tool])
	if n.amount <= 0 and n.type != ResourceNode.Type.BUSH:
		World.remove_node(n)
		return true
	return false


# --- Building ---

## Place a piece and pay for it. Callers check the site rules first (can_place for the
## player; the task runners for the AI). Returns the new piece.
static func place(a: Agent, piece: String, c: Vector2i, cost: Dictionary, tier: int = 0, shared: bool = false) -> Object:
	a.inv.pay(cost)
	var fid := a.faction.id
	match piece:
		"wall": return World.place_wall(c, false, fid, tier, shared)
		"door": return World.place_wall(c, true, fid, tier, shared)
		"floor": return World.place_floor(c, fid)
		"wild_fire":
			var f := World.place_fire(c, false, fid)
			f.placed_by = a.id
			return f
		"house_fire": return World.place_fire(c, true, fid)
	push_error("Actions.place: unknown piece " + piece)
	return null


## Why the agent can't place this piece on c by hand, or "" if it can (player build rules:
## reach, cost, can_build / can_floor, and not on top of the player's own body).
static func can_place(a: Agent, piece: String, c: Vector2i, reach: float) -> String:
	if World.dist(a.pos, World.center(c)) > reach:
		return "too far"
	if not a.inv.has_cost(Items.BUILD_COSTS[piece]):
		return "needs " + _cost_text(Items.BUILD_COSTS[piece])
	if piece == "floor":
		return "" if World.can_floor(c, a.faction.id) else "can't build here"
	if not World.can_build(c, a.faction.id):
		return "can't build here"
	if box_overlaps(a.pos, c):
		return "you're standing there"
	return ""


static func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for k in cost:
		parts.append("%d %s" % [cost[k], k.replace("_", " ")])
	return ", ".join(parts)


# --- Chests and fires ---

## Move items between an agent and a chest or crate by a Stock plan (+ deposit, - take).
static func use_chest(a: Agent, ch: Furniture, plan: Dictionary) -> int:
	return Stock.transfer(a, ch, plan)


## Done warming up at a fire: warm again, and the fire's company counts (relations, opinions).
static func finish_warming(a: Agent, f: Campfire) -> void:
	a.warmth = 1.0
	for o in World.agents_near(World.center(f.cell), Cfg.WARM_RADIUS + 1):
		if o.faction != a.faction and not o.faction.solo and not a.faction.solo:
			Relations.shared_fire(a.faction, o.faction)
	if a.is_happy():
		for o in World.agents_near(World.center(f.cell), Cfg.WARM_RADIUS + 1):
			if o != a and o.is_happy() and o.faction != a.faction:
				a.change_opinion(o.id, 5.0)
				o.change_opinion(a.id, 5.0)


## Eat one berry from the inventory.
static func eat(a: Agent) -> bool:
	if a.inv.count("berry") <= 0:
		return false
	a.inv.remove("berry", 1)
	a.hunger = min(1.0, a.hunger + Cfg.BERRY_FOOD)
	return true
