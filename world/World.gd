extends Node
## Autoload that owns all sim state (grid, entities, agents, factions) and steps the sim.

const NODE_BUCKET := 16
const NO_CELL := Vector2i(-1, -1)

## Emitted at the end of kill_agent, after the body has left its group and a newcomer has
## spawned. `group` and `kingdom` are what the body belonged to just before it died.
## The PlayerController listens for its own body (Player Controller Plan §5a).
signal agent_died(a: Agent, killer: Agent, group: Faction, kingdom: Kingdom, newcomer: Agent)

var rng := RandomNumberGenerator.new()
var astar := AStarGrid2D.new()
var spatial := SpatialHash.new()

var nodes := {} # Vector2i -> ResourceNode
var node_buckets: Array = [{}, {}, {}, {}, {}] # per ResourceNode.Type: bucket -> Array
var bushes: Array[ResourceNode] = []
var walls := {} # Vector2i -> Wall (walls and doors)
var floors := {} # Vector2i -> Floor
var roads := {} # Vector2i -> tier (1 stone, 2 paved)
var furniture := {} # Vector2i -> Furniture (chests, machines, boards, mailboxes)
var fires := {} # Vector2i -> Campfire
var house_fires: Array[Campfire] = []
var loot := {} # Vector2i -> LootBag
var agents := {} # id -> Agent
var agent_list: Array[Agent] = []
var factions := {} # id -> Faction
var kingdoms := {} # id -> Kingdom
var respawn_queue: Array = [] # [{type, at}]

var static_dirty := true
var pieces_version := 0 # bumps when walls, floors, roads, furniture or fires change (PieceLayer redraws)
var started := false
var deaths := 0
var death_causes := {"killed": 0, "cold": 0, "hunger": 0}
var social_counts := {"trades": 0, "robberies": 0, "group_meetings": 0, "fights": 0, "thinks": 0} # bench rates (B3)
var fight_sources := {} # caller of Combat.start_fight -> count (bench diagnostics)
var swing_stats := {"swings": 0, "hits": 0, "extra_hits": 0} # directional melee: hits beyond the intended target (bench)
var gear_fights := {"armoured_won": 0, "armoured_lost": 0} # kills between armoured and unarmoured agents (v3)

# Cached privilege-zone owner per cell, rebuilt when a house fire starts/stops burning.
var zone_map := PackedInt32Array()
var zones_dirty := true
var zone_version := 0 # bumps on every zone rebuild (renderers cache outlines on it)
var _hk_index := 0

# Event-driven decay (Performance Plan B2): the pieces outside protection, in dict order.
# Rebuilt when zones or protection change (protect_version: owners, factions); new pieces
# are checked on the next tick and appended (new dict keys go last, so order is kept).
var protect_version := 0
## Bumps when any group's building list, kingdom membership or furniture changes; the
## group lookup caches (Factions.shared_*, Stock.storages) are cleared on it (B4).
var buildings_version := 0
var _decay_seen := Vector2i(-1, -1) # zone_version, protect_version at the last rebuild
var _decay_walls: Array[Wall] = []
var _decay_floors: Array[Floor] = []
var _decay_furniture: Array[Furniture] = []
var _new_walls: Array[Wall] = []
var _new_floors: Array[Floor] = []
var _new_furniture: Array[Furniture] = []
var _kingdom_acc := 0.0

var _next_agent_id := 1
var _second_acc := 0.0
var _faction_acc := 0.0
var _mood_acc := 0.0


func setup() -> void:
	var seed: int = Cfg.SEED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed = int(arg.get_slice("=", 1)) # bench comparisons across seeds
	rng.seed = seed if seed != 0 else randi()
	Names.reset(rng.seed) # its own generator: names never shift the sim's rolls
	var pad := Cfg.PATH_PAD if Cfg.WRAP else 0
	astar.region = Rect2i(-pad, -pad, Cfg.MAP_W + pad * 2, Cfg.MAP_H + pad * 2)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	WorldGen.generate(rng)
	_spawn_start_agents()
	spatial.rebuild(agent_list)
	started = true
	EventBus.log_event("%d agents spawn into the wild." % Cfg.START_AGENTS)


# --- Stepping ---

var prof := {} # section -> total usec (bench profiling)


var profiling := false # enabled by --bench


func prof_add(key: String, since_usec: int) -> void:
	if profiling:
		prof[key] = prof.get(key, 0) + Time.get_ticks_usec() - since_usec


func step(dt: float) -> void:
	SimClock.time += dt
	var t := Time.get_ticks_usec()
	spatial.rebuild(agent_list)
	prof_add("spatial", t)
	t = Time.get_ticks_usec()
	Scheduler.update_agents(dt)
	prof_add("agents", t)
	t = Time.get_ticks_usec()
	_update_fires(dt)
	_second_acc += dt
	if _second_acc >= 1.0:
		_per_second(_second_acc)
		_second_acc = 0.0
	prof_add("world_timers", t)
	t = Time.get_ticks_usec()
	# Each faction gets housekeeping every ~2 s, spread across steps to avoid spikes.
	_faction_acc += dt * factions.size() / 2.0
	if _faction_acc >= 1.0:
		var fl := factions.values()
		while _faction_acc >= 1.0 and fl.size() > 0:
			_faction_acc -= 1.0
			_hk_index = (_hk_index + 1) % fl.size()
			Factions.housekeeping(fl[_hk_index])
	prof_add("housekeeping", t)
	Raids.update(dt)
	_kingdom_acc += dt
	if _kingdom_acc >= 2.0:
		_kingdom_acc = 0.0
		Kingdoms.update_all()
	_mood_acc += dt
	if _mood_acc >= 60.0:
		_mood_acc = 0.0
		Factions.mood_drift()


func _update_fires(dt: float) -> void:
	for f in fires.values().duplicate():
		if f.fuel_secs > 0.0:
			f.fuel_secs = max(0.0, f.fuel_secs - dt)
			if f.fuel_secs <= 0.0 and f.is_house:
				zones_dirty = true
		else:
			f.unlit_secs += dt
			if f.unlit_secs >= Cfg.FIRE_UNLIT_DESTROY_SECS:
				remove_fire(f)


func _per_second(s: float) -> void:
	var t := Time.get_ticks_usec()
	# Bushes regrow berries.
	for b in bushes:
		if b.amount < Cfg.BUSH_BERRIES:
			b.regrow_timer += s
			if b.regrow_timer >= Cfg.BUSH_REGROW_SECS:
				b.regrow_timer = 0.0
				b.amount += 1
				static_dirty = true # berries are drawn in StaticLayer
	# Walls outside any burning house fire's zone decay (agreed: 10 min to 0); so do abandoned
	# pieces and pieces standing in another side's zone. Floors and furniture too.
	_update_decay_sets()
	for w in _decay_walls:
		if walls.get(w.cell) == w:
			w.hp -= w.max_hp / Cfg.WALL_DECAY_SECS * s
			pieces_version += 1
			if w.hp <= 0.0:
				remove_wall(w)
	for fl in _decay_floors:
		if floors.get(fl.cell) == fl:
			fl.hp -= fl.max_hp / Cfg.WALL_DECAY_SECS * s
			pieces_version += 1
			if fl.hp <= 0.0:
				floors.erase(fl.cell)
	for fu in _decay_furniture:
		if furniture.get(fu.cell) == fu:
			fu.hp -= fu.max_hp / Cfg.WALL_DECAY_SECS * s
			if fu.hp <= 0.0:
				remove_furniture(fu)
	prof_add("decay", t)
	t = Time.get_ticks_usec()
	Wars.update()
	KingdomWars.per_second(s)
	prof_add("wars", t)
	# Loot bags despawn.
	for bag in loot.values().duplicate():
		bag.timer -= s
		if bag.timer <= 0.0 or bag.is_empty():
			loot.erase(bag.cell)
	# Resource node respawns.
	for r in respawn_queue.duplicate():
		if SimClock.time >= r.at:
			respawn_queue.erase(r)
			_respawn_node(r.type)


## Bring the unprotected-piece lists up to date: a full scan when zones or protection
## changed, else just check the pieces placed since the last tick. Gone pieces are dropped.
func _update_decay_sets() -> void:
	privilege_owner(Vector2i.ZERO) # rebuild zones if dirty, so zone_version is current
	var seen := Vector2i(zone_version, protect_version)
	if seen != _decay_seen:
		_decay_seen = seen
		_decay_walls.clear()
		_decay_floors.clear()
		_decay_furniture.clear()
		for w in walls.values():
			if _unprotected(w.cell, w.owner_id):
				_decay_walls.append(w)
		for fl in floors.values():
			if _unprotected(fl.cell, fl.owner_id):
				_decay_floors.append(fl)
		for fu in furniture.values():
			if fu.kind != Furniture.Kind.BOARD and _unprotected(fu.cell, fu.owner_id):
				_decay_furniture.append(fu)
		if profiling:
			prof["decay_rebuilds (count)"] = prof.get("decay_rebuilds (count)", 0) + 1000 # prints as N.0 ms
	else:
		_decay_walls = _decay_walls.filter(func(w): return walls.get(w.cell) == w)
		_decay_floors = _decay_floors.filter(func(fl): return floors.get(fl.cell) == fl)
		_decay_furniture = _decay_furniture.filter(func(fu): return furniture.get(fu.cell) == fu)
		for w in _new_walls:
			if walls.get(w.cell) == w and _unprotected(w.cell, w.owner_id):
				_decay_walls.append(w)
		for fl in _new_floors:
			if floors.get(fl.cell) == fl and _unprotected(fl.cell, fl.owner_id):
				_decay_floors.append(fl)
		for fu in _new_furniture:
			if furniture.get(fu.cell) == fu and fu.kind != Furniture.Kind.BOARD and _unprotected(fu.cell, fu.owner_id):
				_decay_furniture.append(fu)
	_new_walls.clear()
	_new_floors.clear()
	_new_furniture.clear()


# --- Grid queries ---

## With WRAP every cell is on the map (it's an alias of a canonical cell, see wc).
func in_bounds(c: Vector2i) -> bool:
	return Cfg.WRAP or (c.x >= 0 and c.y >= 0 and c.x < Cfg.MAP_W and c.y < Cfg.MAP_H)


## The canonical cell: every cell-keyed store (walls, nodes, zone_map, A*...) uses these.
## Cells made by local arithmetic (neighbours, radius scans) go through this before a lookup.
static func wc(c: Vector2i) -> Vector2i:
	if not Cfg.WRAP:
		return c
	return Vector2i(posmod(c.x, Cfg.MAP_W), posmod(c.y, Cfg.MAP_H))


## The canonical position (agents keep theirs canonical after every move).
static func wrap_pos(p: Vector2) -> Vector2:
	if not Cfg.WRAP:
		return p
	return Vector2(fposmod(p.x, Cfg.MAP_W), fposmod(p.y, Cfg.MAP_H))


## The copy of cell c nearest `anchor`: for local geometry that mixes a canonical cell with
## cells counted from an anchor (clamping into a rect, walking a line).
static func near_cell(c: Vector2i, anchor: Vector2i) -> Vector2i:
	return anchor + cdelta(anchor, c)


## Shortest cell offset from a to b.
static func cdelta(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	if Cfg.WRAP:
		d.x -= Cfg.MAP_W * int(roundf(float(d.x) / Cfg.MAP_W))
		d.y -= Cfg.MAP_H * int(roundf(float(d.y) / Cfg.MAP_H))
	return d


## --- View (render only; the sim never reads these) ---
## The camera's centre and visible rect in world px, set by CameraController every frame.
## Renderers draw everything at its copy nearest view_center, so the seam never shows.
var view_center := Vector2.ZERO
var view_rect := Rect2()


## Offset (world px) that moves world-px point p to its copy nearest the camera.
func px_shift(p: Vector2) -> Vector2:
	if not Cfg.WRAP:
		return Vector2.ZERO
	var mw := float(Cfg.MAP_W * Cfg.CELL)
	var mh := float(Cfg.MAP_H * Cfg.CELL)
	return Vector2(mw * roundf((view_center.x - p.x) / mw), mh * roundf((view_center.y - p.y) / mh))


## World px of position p (cells) at its copy nearest the camera: what every per-frame
## renderer draws at.
func px(p: Vector2) -> Vector2:
	var q := p * Cfg.CELL
	return q + px_shift(q)


## Rect2i.has_point that also finds c on the other side of the seam.
static func rect_has(r: Rect2i, c: Vector2i) -> bool:
	if not Cfg.WRAP:
		return r.has_point(c)
	return posmod(c.x - r.position.x, Cfg.MAP_W) < r.size.x and posmod(c.y - r.position.y, Cfg.MAP_H) < r.size.y


## Rect2i.intersects, wrap-aware.
static func rects_meet(a: Rect2i, b: Rect2i) -> bool:
	if not Cfg.WRAP:
		return a.intersects(b)
	if a.size.x <= 0 or a.size.y <= 0 or b.size.x <= 0 or b.size.y <= 0:
		return false
	var x := posmod(b.position.x - a.position.x, Cfg.MAP_W) < a.size.x or posmod(a.position.x - b.position.x, Cfg.MAP_W) < b.size.x
	var y := posmod(b.position.y - a.position.y, Cfg.MAP_H) < a.size.y or posmod(a.position.y - b.position.y, Cfg.MAP_H) < b.size.y
	return x and y


## Blocks building (and site checks). Walking uses passable / blocks_walk: hemp doesn't
## block it (R7).
func is_solid(c: Vector2i) -> bool:
	if nodes.has(wc(c)) or walls.has(wc(c)) or fires.has(wc(c)):
		return true
	var fu: Furniture = furniture.get(wc(c))
	return fu != null and fu.is_solid()


func is_walkable(c: Vector2i) -> bool:
	return in_bounds(c) and not is_solid(c)


## Wrap-aware geometry (Summer Roadmap §2): the shortest offset from a to b, the short way
## round the seam when the map wraps. All code measures distance and direction through these.
static func delta(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	if Cfg.WRAP:
		d.x -= Cfg.MAP_W * roundf(d.x / Cfg.MAP_W)
		d.y -= Cfg.MAP_H * roundf(d.y / Cfg.MAP_H)
	return d


static func dist(a: Vector2, b: Vector2) -> float:
	return delta(a, b).length()


static func dist_sq(a: Vector2, b: Vector2) -> float:
	return delta(a, b).length_squared()


static func cheb(a: Vector2i, b: Vector2i) -> int:
	var d := cdelta(a, b)
	return max(abs(d.x), abs(d.y))


## Trees, rocks and iron all draw as 2x2-cell sprites.
static func is_big_node(type: int) -> bool:
	return type == ResourceNode.Type.TREE or type == ResourceNode.Type.ROCK or type == ResourceNode.Type.METAL


## True if a big node stands within Cfg.BIG_NODE_MIN_GAP - 1 cells of c (Chebyshev), i.e. a
## big node placed at c would overlap its sprite.
func big_node_too_close(c: Vector2i) -> bool:
	var r := Cfg.BIG_NODE_MIN_GAP - 1
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var n: ResourceNode = nodes.get(wc(c + Vector2i(dx, dy)))
			if n != null and is_big_node(n.type):
				return true
	return false


static func center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


func _node_blocks_walk(c: Vector2i) -> bool:
	var n: ResourceNode = nodes.get(wc(c))
	return n != null and not n.walk_through()


## Blocks walking for everyone (doors count as blocking): walls, fires, and resource nodes
## other than hemp (R7). Loot bags can lie wherever people can walk.
func blocks_walk(c: Vector2i) -> bool:
	return _node_blocks_walk(c) or walls.has(wc(c)) or fires.has(wc(c))


## Can this agent step onto the cell? Doors open for their faction, or to let a trapped agent out.
func passable(a: Agent, c: Vector2i) -> bool:
	if not in_bounds(c) or _node_blocks_walk(c) or fires.has(wc(c)):
		return false
	var fu: Furniture = furniture.get(wc(c))
	if fu and fu.is_solid():
		return false
	var w: Wall = walls.get(wc(c))
	if w == null:
		return true
	if not w.is_door:
		return false
	if w.owner_id == a.faction.id or (w.shared and same_side(w.owner_id, a.faction.id)):
		return true
	var trap := house_at(a.cell())
	return trap != null and trap.door_cell == c


func agent_on(c: Vector2i) -> bool:
	for a in spatial.query(center(c), 1.2):
		if a.cell() == c:
			return true
	return false


func agents_near(p: Vector2, radius: float) -> Array:
	return spatial.query(p, radius)


func _unprotected(c: Vector2i, owner: int) -> bool:
	var po := privilege_owner(c)
	if po == owner:
		return po == 0
	return po == 0 or owner == 0 or not same_side(po, owner)


## Same group, or groups of the same kingdom (shared territory, workshops, no fire spacing).
func same_side(fa: int, fb: int) -> bool:
	if fa == fb:
		return true
	var a: Faction = factions.get(fa)
	if a == null or a.kingdom == null:
		return false
	var b: Faction = factions.get(fb)
	return b != null and b.kingdom == a.kingdom


## Faction id whose burning house fire claims this cell, or 0.
func privilege_owner(c: Vector2i) -> int:
	if zones_dirty:
		_rebuild_zones()
	if not in_bounds(c):
		return 0
	c = wc(c)
	return zone_map[c.y * Cfg.MAP_W + c.x]


func _rebuild_zones() -> void:
	zones_dirty = false
	zone_version += 1
	zone_map.resize(Cfg.MAP_W * Cfg.MAP_H)
	zone_map.fill(0)
	var r := Cfg.PRIVILEGE_RADIUS
	# House fires first; workshop fires only claim cells no house fire claims.
	for pass_workshops in [false, true]:
		for f in house_fires:
			if not f.burning() or _is_workshop_fire(f) != pass_workshops:
				continue
			for yy in range(f.cell.y - r, f.cell.y + r + 1):
				if not Cfg.WRAP and (yy < 0 or yy >= Cfg.MAP_H):
					continue
				var y := posmod(yy, Cfg.MAP_H)
				for xx in range(f.cell.x - r, f.cell.x + r + 1):
					if not Cfg.WRAP and (xx < 0 or xx >= Cfg.MAP_W):
						continue
					var i := y * Cfg.MAP_W + posmod(xx, Cfg.MAP_W)
					if not pass_workshops or zone_map[i] == 0:
						zone_map[i] = f.owner_id


## Workshop and smeltery fires: their zones yield to house zones.
static func _is_workshop_fire(f: Campfire) -> bool:
	return f.house != null and not f.house.is_home()


func can_build(c: Vector2i, fid: int) -> bool:
	if not in_bounds(c) or is_solid(c) or loot.has(wc(c)) or furniture.has(wc(c)):
		return false
	var po := privilege_owner(c)
	if po != 0 and not same_side(po, fid):
		return false
	return not agent_on(c)


func all_houses() -> Array[House]:
	var out: Array[House] = []
	for f in factions.values():
		out.append_array(f.houses)
	return out


func house_at(c: Vector2i) -> House:
	for f in factions.values():
		for h in f.houses:
			if rect_has(h.interior, c):
				return h
	return null


## Bresenham line between cell centres; walls and doors block arrows.
func line_clear(a: Vector2i, b: Vector2i) -> bool:
	b = near_cell(b, a)
	var dx: int = abs(b.x - a.x)
	var dy: int = -abs(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while p != b:
		if p != a and walls.has(wc(p)):
			return false
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return true


# --- Pathfinding ---

## A* runs on the map plus a PATH_PAD margin copied from the far side (Cfg.WRAP), so every
## write to it goes to each copy of the cell inside the padded grid.
func _astar_aliases(c: Vector2i) -> Array[Vector2i]:
	if not Cfg.WRAP:
		return [c]
	var out: Array[Vector2i] = []
	var r := astar.region
	for kx in [-1, 0, 1]:
		var x: int = c.x + kx * Cfg.MAP_W
		if x < r.position.x or x >= r.end.x:
			continue
		for ky in [-1, 0, 1]:
			var y: int = c.y + ky * Cfg.MAP_H
			if y >= r.position.y and y < r.end.y:
				out.append(Vector2i(x, y))
	return out


func _astar_solid(c: Vector2i, on: bool) -> void:
	if not Cfg.WRAP:
		astar.set_point_solid(c, on)
		return
	for ac in _astar_aliases(wc(c)):
		astar.set_point_solid(ac, on)


var _path_fail := {} # Vector4i(agent, start, dest) -> expiry; failed searches flood the map, so don't repeat them


func find_path(a: Agent, dest: Vector2i) -> Array[Vector2i]:
	var start := a.cell()
	if not in_bounds(dest) or not in_bounds(start):
		return []
	dest = wc(dest)
	var fail_key := Vector4i(a.id, start.x * 65536 + start.y, dest.x, dest.y)
	if SimClock.time < _path_fail.get(fail_key, -1.0):
		return []
	var ts := Time.get_ticks_usec()
	var opened: Array[Vector2i] = []
	for h in a.faction.houses + Factions.machine_houses(a.faction):
		if walls.has(h.door_cell) and astar.is_point_solid(h.door_cell) and passable(a, h.door_cell):
			opened.append(h.door_cell)
	var trap := house_at(start)
	if trap and trap.faction_id != a.faction.id and walls.has(trap.door_cell):
		opened.append(trap.door_cell)
	if astar.is_point_solid(start):
		opened.append(start)
	for c in opened:
		_astar_solid(c, false)
	prof_add("path_doors", ts)
	var p: Array[Vector2i] = []
	var t := Time.get_ticks_usec()
	# With WRAP, aim at the copy of dest nearest the start: inside the padded grid the path
	# crosses the seam. Beyond the pad, the canonical dest (the long way round) still works.
	var goal := dest
	if Cfg.WRAP:
		var near := near_cell(dest, start)
		if astar.region.has_point(near):
			goal = near
	if not astar.is_point_solid(goal):
		p = astar.get_id_path(start, goal)
		if Cfg.WRAP:
			for i in p.size():
				p[i] = wc(p[i])
	prof_add("astar", t)
	if p.is_empty():
		_path_fail[fail_key] = SimClock.time + 10.0
		if _path_fail.size() > 5000:
			_path_fail.clear()
		if profiling:
			var k: String = Job.Kind.keys()[a.job.kind] if a.job else "none"
			prof_add("astar_FAIL_" + k, t)
	for c in opened:
		_astar_solid(c, true)
	return p


## A walkable cell within `radius` of target, nearest to the agent.
func approach_cell(a: Agent, target: Vector2i, radius: int = 1) -> Vector2i:
	var here := a.cell()
	if cheb(here, target) <= radius and here != target and passable(a, here):
		return here
	var best := NO_CELL
	var best_d := INF
	for x in range(target.x - radius, target.x + radius + 1):
		for y in range(target.y - radius, target.y + radius + 1):
			var c := Vector2i(x, y)
			if c == target or not passable(a, c):
				continue
			var d := dist_sq(a.pos, center(c))
			if d < best_d:
				best_d = d
				best = c
	return wc(best) if best != NO_CELL else NO_CELL


func random_walkable_near(c: Vector2i, radius: int) -> Vector2i:
	for i in 20:
		var t := c + Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
		if is_walkable(t):
			return wc(t)
	return NO_CELL


# --- Resource nodes ---

func _bucket(c: Vector2i) -> Vector2i:
	return Vector2i(c.x / NODE_BUCKET, c.y / NODE_BUCKET)


## The stored bucket key for an unwrapped bucket coordinate (ring searches run past the seam).
static func _bucket_key(b: Vector2i) -> Vector2i:
	if not Cfg.WRAP:
		return b
	return Vector2i(posmod(b.x, Cfg.MAP_W / NODE_BUCKET), posmod(b.y, Cfg.MAP_H / NODE_BUCKET))


func add_node(type: int, c: Vector2i) -> ResourceNode:
	c = wc(c)
	var n := ResourceNode.new(type, c)
	nodes[wc(c)] = n
	var key := _bucket(c)
	if not node_buckets[type].has(key):
		node_buckets[type][key] = []
	node_buckets[type][key].append(n)
	if type == ResourceNode.Type.BUSH:
		bushes.append(n)
	if not n.walk_through():
		_astar_solid(c, true)
	static_dirty = true
	return n


func remove_node(n: ResourceNode) -> void:
	if nodes.get(n.cell) != n:
		return
	nodes.erase(n.cell)
	node_buckets[n.type][_bucket(n.cell)].erase(n)
	_astar_solid(n.cell, false)
	static_dirty = true
	respawn_queue.append({"type": n.type, "at": SimClock.time + rng.randf_range(Cfg.NODE_RESPAWN_MIN, Cfg.NODE_RESPAWN_MAX)})


func nearest_node(type: int, from: Vector2i, max_r: float, pred: Callable = Callable()) -> ResourceNode:
	var bf := _bucket(from)
	var best: ResourceNode = null
	var best_d := INF
	var max_ring := int(ceil(max_r / NODE_BUCKET)) + 1
	var fp := Vector2(from)
	var buckets: Dictionary = node_buckets[type]
	for ring in range(0, max_ring + 1):
		if best != null and (ring - 1) * NODE_BUCKET > best_d:
			break
		# Same bucket order as a full square scan that skips the inside (B5), but only the
		# ring's edge, and buckets that can't hold anything closer are skipped.
		for bx in range(bf.x - ring, bf.x + ring + 1):
			var edge_col: bool = abs(bx - bf.x) == ring
			var by := bf.y - ring
			while by <= bf.y + ring:
				var key := Vector2i(bx, by)
				by = by + 1 if edge_col or by == bf.y + ring else bf.y + ring
				var arr = buckets.get(_bucket_key(key))
				if arr == null:
					continue
				var lo := Vector2(key * NODE_BUCKET)
				var gap := Vector2(maxf(maxf(lo.x - fp.x, fp.x - (lo.x + NODE_BUCKET - 1)), 0.0), maxf(maxf(lo.y - fp.y, fp.y - (lo.y + NODE_BUCKET - 1)), 0.0)).length()
				if gap > max_r or gap > best_d:
					continue
				for n in arr:
					if n.amount <= 0:
						continue
					var d := dist(Vector2(from), Vector2(n.cell))
					if d < best_d and d <= max_r and (pred.is_null() or pred.call(n)):
						best = n
						best_d = d
	return best


func _respawn_node(type: int) -> void:
	# Prefer regrowing near an existing node of the same type to keep clusters (metal stays dispersed).
	var anchor := NO_CELL
	var keys: Array = node_buckets[type].keys()
	if keys.size() > 0 and type != ResourceNode.Type.METAL:
		var arr: Array = node_buckets[type][keys[rng.randi() % keys.size()]]
		if arr.size() > 0:
			anchor = arr[rng.randi() % arr.size()].cell
	for i in 30:
		var c: Vector2i
		if anchor != NO_CELL and i < 20:
			c = anchor + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
		else:
			c = Vector2i(rng.randi_range(0, Cfg.MAP_W - 1), rng.randi_range(0, Cfg.MAP_H - 1))
		c = wc(c)
		if is_big_node(type) and big_node_too_close(c):
			continue
		if is_walkable(c) and not loot.has(wc(c)) and privilege_owner(c) == 0 and house_at(c) == null and not agent_on(c) and not Cities.in_city(c):
			add_node(type, c)
			return
	respawn_queue.append({"type": type, "at": SimClock.time + 30.0})


# --- Buildings ---

func place_wall(c: Vector2i, door: bool, fid: int, tier: int = 0, shared: bool = false) -> Wall:
	c = wc(c)
	var w := Wall.new(c, door, fid, tier)
	w.shared = shared
	walls[wc(c)] = w
	_astar_solid(c, true)
	pieces_version += 1
	_new_walls.append(w)
	return w


func remove_wall(w: Wall) -> void:
	if walls.get(w.cell) != w:
		return
	walls.erase(w.cell)
	_astar_solid(w.cell, false)
	pieces_version += 1


## Roads: walkable, faster, and cheaper for A* so agents prefer them (agreed).
func place_road(c: Vector2i, tier: int) -> void:
	c = wc(c)
	roads[wc(c)] = tier
	pieces_version += 1
	for ac in _astar_aliases(c):
		astar.set_point_weight_scale(ac, 1.0 / Items.ROAD_SPEED[tier])


func place_floor(c: Vector2i, fid: int) -> Floor:
	c = wc(c)
	var fl := Floor.new(c, fid)
	floors[wc(c)] = fl
	pieces_version += 1
	_new_floors.append(fl)
	return fl


## Floors are walkable, so they can go under a standing agent.
func can_floor(c: Vector2i, fid: int) -> bool:
	if not in_bounds(c) or is_solid(c) or floors.has(wc(c)):
		return false
	var po := privilege_owner(c)
	return po == 0 or same_side(po, fid)


func place_furniture(c: Vector2i, kind: int, fid: int, house, tier: int = 0) -> Furniture:
	c = wc(c)
	var fu := Furniture.new(c, kind, fid, tier)
	fu.house = house
	furniture[wc(c)] = fu
	if fu.is_solid():
		_astar_solid(c, true)
	pieces_version += 1
	buildings_version += 1
	_new_furniture.append(fu)
	return fu


## Chest decayed or smashed: its contents spill as a loot bag.
func remove_furniture(fu: Furniture, reason: String = "chest destroyed") -> void:
	if furniture.get(fu.cell) != fu:
		return
	furniture.erase(fu.cell)
	if fu.is_solid() and not is_solid(fu.cell):
		_astar_solid(fu.cell, false)
	pieces_version += 1
	buildings_version += 1
	if fu.is_storage() and fu.store.total() > 0:
		drop_loot(fu.cell, fu.store.stacks.duplicate(), fu.store.tools.duplicate(), -1, reason)
		fu.set_store(Inventory.new())


func place_fire(c: Vector2i, house_fire: bool, fid: int) -> Campfire:
	c = wc(c)
	var f := Campfire.new(c, house_fire, fid)
	fires[wc(c)] = f
	_astar_solid(c, true)
	pieces_version += 1
	if house_fire:
		house_fires.append(f)
		zones_dirty = true
	return f


func remove_fire(f: Campfire) -> void:
	if fires.get(f.cell) != f:
		return
	fires.erase(f.cell)
	_astar_solid(f.cell, false)
	pieces_version += 1
	if f.is_house:
		house_fires.erase(f)
		zones_dirty = true
		if f.house:
			# The mailbox stands outside the walls: it goes with the house.
			var mb: Furniture = f.house.live_mailbox()
			if mb:
				remove_furniture(mb, "mailbox removed")
			Factions.destroy_house(f.house)


## Valid spot for a house fire: no other side's house (planned or built) within 2R+1 (agreed).
## A group's own buildings (and in Phase D its kingdom's) may sit closer together.
## A workshop fire only has to stay outside other sides' zones (R+1); its zone yields to houses.
func house_fire_spacing_ok(c: Vector2i, ignore: House = null, fid: int = -1, workshop: bool = false) -> bool:
	var gap := Cfg.PRIVILEGE_RADIUS + 1 if workshop else Cfg.PRIVILEGE_RADIUS * 2 + 1
	for f in factions.values():
		for h in f.houses:
			if h != ignore and cheb(h.fire_cell, c) < gap and not same_side(h.faction_id, fid):
				return false
	for f in house_fires:
		if (ignore == null or f.house != ignore) and not same_side(f.owner_id, fid) and cheb(f.cell, c) < gap:
			return false
	return true


## True if the rect (grown by a 1-cell margin) overlaps any building footprint.
func footprint_clash(outer: Rect2i, ignore: House = null) -> bool:
	var r := outer.grow(1)
	for f in factions.values():
		for h in f.houses:
			if h != ignore and rects_meet(h.footprint(), r):
				return true
	return false


# --- Loot ---

func drop_loot(c: Vector2i, stacks: Dictionary, tools: Array, dropper_id: int = -1, reason: String = "") -> void:
	if stacks.is_empty() and tools.is_empty():
		return
	c = wc(c)
	if blocks_walk(c):
		var alt := random_walkable_near(c, 1)
		if alt == NO_CELL:
			return
		c = alt
	var bag: LootBag = loot.get(wc(c))
	if bag == null:
		bag = LootBag.new(c)
		loot[wc(c)] = bag
	for k in stacks:
		bag.stacks[k] = bag.stacks.get(k, 0) + stacks[k]
	bag.tools.append_array(tools)
	bag.timer = Cfg.LOOT_DESPAWN
	bag.dropper_id = dropper_id
	bag.reason = reason


func take_loot(a: Agent, bag: LootBag) -> void:
	for t in bag.tools.duplicate():
		if not a.inv.put_tool(t):
			break
		bag.tools.erase(t)
	for k in bag.stacks.keys():
		var n: int = min(bag.stacks[k], a.free_space(k))
		if n <= 0:
			continue
		n = a.inv.add(k, n)
		bag.stacks[k] -= n
		if bag.stacks[k] <= 0:
			bag.stacks.erase(k)
	if bag.is_empty():
		loot.erase(bag.cell)


# --- Agents ---

## Start layout: the cluster sizes in Cfg.SPAWN_CLUSTERS start bunched around centres
## spread across the map; everyone else starts dispersed, away from clusters and each other.
func _spawn_start_agents() -> void:
	var centres: Array[Vector2i] = []
	var clustered := 0
	for size: int in Cfg.SPAWN_CLUSTERS:
		var centre := _open_cell_away(centres, Cfg.CLUSTER_GAP, 6)
		centres.append(centre)
		for i in size:
			if clustered >= Cfg.START_AGENTS:
				return
			spawn_agent(0, _cluster_cell(centre))
			clustered += 1
	for i in Cfg.START_AGENTS - clustered:
		spawn_agent(0, _dispersed_cell(centres))


## A free cell within CLUSTER_RADIUS of `centre` (the centre itself if nothing else fits).
func _cluster_cell(centre: Vector2i) -> Vector2i:
	for i in 100:
		var c := centre + Vector2i(rng.randi_range(-Cfg.CLUSTER_RADIUS, Cfg.CLUSTER_RADIUS),
				rng.randi_range(-Cfg.CLUSTER_RADIUS, Cfg.CLUSTER_RADIUS))
		if _spawnable(c):
			return c
	return centre if _spawnable(centre) else _spawn_cell(0)


## A free cell at least CLUSTER_CLEARANCE from every cluster centre and DISPERSED_GAP from
## every agent. Gaps shrink step by step if the map is too full to honour them.
func _dispersed_cell(centres: Array[Vector2i]) -> Vector2i:
	var gap := float(Cfg.DISPERSED_GAP)
	var clear := float(Cfg.CLUSTER_CLEARANCE)
	while gap >= 4.0:
		for i in 300:
			var c := Vector2i(rng.randi_range(2, Cfg.MAP_W - 3), rng.randi_range(2, Cfg.MAP_H - 3))
			if not _spawnable(c):
				continue
			var p := center(c)
			if centres.any(func(k: Vector2i) -> bool: return dist(p, center(k)) < clear):
				continue
			if agent_list.any(func(o: Agent) -> bool: return dist(p, o.pos) < gap):
				continue
			return c
		gap *= 0.8
		clear *= 0.8
	return _spawn_cell(0)


## A free cell at least `gap` from each of `taken`, kept `margin` cells off the map edge.
func _open_cell_away(taken: Array[Vector2i], gap: float, margin: int) -> Vector2i:
	var best := NO_CELL
	var best_d := -1.0
	for i in 300:
		var c := Vector2i(rng.randi_range(margin, Cfg.MAP_W - 1 - margin), rng.randi_range(margin, Cfg.MAP_H - 1 - margin))
		if not _spawnable(c):
			continue
		var d := INF
		for k in taken:
			d = min(d, dist(center(c), center(k)))
		if d >= gap:
			return c
		if d > best_d: # fallback: the most open spot seen
			best_d = d
			best = c
	return best if best != NO_CELL else _spawn_cell(0)


func _spawnable(c: Vector2i) -> bool:
	return in_bounds(c) and is_walkable(c) and privilege_owner(c) == 0 and house_at(c) == null


## `at`: a start cell picked by the caller (the start layout); otherwise a random free cell
## at least `min_dist` from every agent (respawns).
func spawn_agent(min_dist: int, at: Vector2i = NO_CELL) -> Agent:
	var a := Agent.new()
	a.id = _next_agent_id
	_next_agent_id += 1
	for s in Agent.STATS:
		a.stats[s] = rng.randi_range(Cfg.STAT_MIN, Cfg.STAT_MAX)
	var r := rng.randf()
	var base := 60.0 if r < 0.5 else (0.0 if r < 0.8 else -60.0) # 50/30/20 (agreed)
	a.mood = base + rng.randf_range(-15.0, 15.0)
	a.pos = wrap_pos(center(at if at != NO_CELL else _spawn_cell(min_dist)))
	a.think_t = rng.randf() * Cfg.THINK_INTERVAL
	a.inv.add("berry", 2)
	Names.assign(a)
	Factions.make_solo(a)
	agents[a.id] = a
	agent_list.append(a)
	return a


func _spawn_cell(min_dist: int) -> Vector2i:
	var fallback := NO_CELL
	for i in 300:
		var c := Vector2i(rng.randi_range(2, Cfg.MAP_W - 3), rng.randi_range(2, Cfg.MAP_H - 3))
		if not is_walkable(c) or privilege_owner(c) != 0 or house_at(c) != null:
			continue
		fallback = c
		if min_dist <= 0:
			return c
		var ok := true
		for other in agent_list:
			if dist(other.pos, center(c)) < min_dist:
				ok = false
				break
		if ok:
			return c
	return fallback if fallback != NO_CELL else Vector2i(Cfg.MAP_W / 2, Cfg.MAP_H / 2)


func kill_agent(a: Agent, killer: Agent) -> void:
	if not a.alive:
		return
	a.alive = false
	deaths += 1
	var group := a.faction
	var kingdom: Kingdom = group.kingdom if group else null
	var why := ("killed by %s" % killer.short()) if killer else ("died of %s" % ("cold" if a.warmth <= 0.0 else "hunger"))
	# Worn gear drops into the loot bag too, so killers can strip armoured victims (agreed).
	drop_loot(a.cell(), a.inv.stacks.duplicate(), a.inv.tools.duplicate() + a.worn.values(), a.id, why)
	if killer:
		if killer.is_armoured() and not a.is_armoured():
			gear_fights.armoured_won += 1
		elif a.is_armoured() and not killer.is_armoured():
			gear_fights.armoured_lost += 1
	if killer and KingdomWars.enemies(a, killer):
		KingdomWars.deaths += 1
	if killer:
		Relations.change(a.faction, killer.faction, Cfg.REL_KILL)
	if killer:
		death_causes.killed += 1
	else:
		death_causes["cold" if a.warmth <= 0.0 else "hunger"] += 1
	if killer and killer.alive:
		killer.kills += 1
		killer.gain_authority()
		EventBus.social(&"killed", "%s killed %s." % [killer.short(), a.short()], [killer, a], [], a.pos)
	else:
		EventBus.social(&"died", "%s died of %s." % [a.short(), "cold" if a.warmth <= 0.0 else "hunger"], [a])
	Factions.on_agent_removed(a)
	if killer and killer.alive:
		Factions.recompute_leader(killer.faction)
	agents.erase(a.id)
	agent_list.erase(a)
	for other in agent_list:
		other.opinions.erase(a.id)
		other.cooldowns.erase(a.id)
		other.death_match.erase(a.id)
		other.pleaded.erase(a.id)
	# Constant population: a fresh agent appears somewhere else (agreed).
	var fresh := spawn_agent(Cfg.RESPAWN_MIN_DIST)
	EventBus.log_event("%s wanders in from the wilds." % fresh.short())
	agent_died.emit(a, killer, group, kingdom, fresh)


func agent_at_point(p: Vector2, radius: float) -> Agent:
	var best: Agent = null
	var best_d := radius
	for a in agent_list:
		var d := dist(a.pos, p)
		if d < best_d:
			best_d = d
			best = a
	return best
