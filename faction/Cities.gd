class_name Cities
## City grids for kingdoms. v3 (agreed): 10x10 plots grouped in 2x2 blocks. The plots of a
## block touch and their houses sit wall to wall in the block's inner corner, doors facing
## the block's outer ring road. Plot (0,0) is the king group's house, the bottom-left plot
## of block (0,0). Plot assignment, relocation into the city, clearing, demolition and roads
## (plaza, then a ring road around each block, then a spur from each door, then paving).

const PLOT := 10
const BLOCK := 21 # two plots plus the ring road
const MAX_BLOCK_RING := 2
const CLOSE_BLOCK_RING := 1 # "close enough" to the leader's house (v3 §1.2)
const NONE := Vector2i(-9999, -9999)
const MAX_ROAD_TASKS := 30
const MAX_CLEAR_TASKS := 20
const MAX_DEMOLISH_TASKS := 20

static var demolished := 0


# --- Kingdom hooks ---

static func on_formed(k: Kingdom) -> void:
	found(k)


static func on_joined(k: Kingdom, f: Faction) -> void:
	f.evicted_by = -1
	k.pushouts.erase(f.id)
	if k.has_city:
		assign_house_plot(k, f)


static func on_left(k: Kingdom, f: Faction) -> void:
	for idx in k.plots.keys():
		if k.plots[idx].fid == f.id:
			k.plots.erase(idx)
	for h in f.houses:
		h.plot_kid = -1


static func on_dissolved(k: Kingdom) -> void:
	for idx in k.plots:
		var h: House = k.plots[idx].house
		if h:
			h.plot_kid = -1
	k.plots.clear()
	k.has_city = false


## A plot's house was destroyed: the plot stays the group's, ready for a new house.
static func on_house_gone(h: House) -> void:
	var k: Kingdom = World.kingdoms.get(h.plot_kid)
	if k and k.plots.has(h.plot) and k.plots[h.plot].house == h:
		k.plots[h.plot].house = null


# --- Grid ---

static func block_of(idx: Vector2i) -> Vector2i:
	return Vector2i(floori(idx.x / 2.0), floori((idx.y + 1) / 2.0))


## Position inside the block: x 0 = left, 1 = right; y 0 = top, 1 = bottom.
static func sub_of(idx: Vector2i) -> Vector2i:
	return Vector2i(posmod(idx.x, 2), posmod(idx.y + 1, 2))


static func block_plots(b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for sy in 2:
		for sx in 2:
			out.append(Vector2i(b.x * 2 + sx, b.y * 2 + sy - 1))
	return out


static func block_rect(k: Kingdom, b: Vector2i) -> Rect2i:
	return Rect2i(k.city_origin - Vector2i(0, PLOT) + b * BLOCK, Vector2i(PLOT * 2, PLOT * 2))


static func plot_rect(k: Kingdom, idx: Vector2i) -> Rect2i:
	return Rect2i(block_rect(k, block_of(idx)).position + sub_of(idx) * PLOT, Vector2i(PLOT, PLOT))


## Block ring of a plot (0 = the leader's block).
static func ring(idx: Vector2i) -> int:
	var b := block_of(idx)
	return max(abs(b.x), abs(b.y))


## The king's house fire (or the centre plot if that house is gone).
static func centre_cell(k: Kingdom) -> Vector2i:
	var p = k.plots.get(Vector2i.ZERO)
	if p and p.house:
		return p.house.fire_cell
	return plot_rect(k, Vector2i.ZERO).get_center()


## The city area: the leader's and adjacent blocks plus every block with a plot, ring roads included.
static func city_rect(k: Kingdom) -> Rect2i:
	var blocks := {}
	for bx in range(-CLOSE_BLOCK_RING, CLOSE_BLOCK_RING + 1):
		for by in range(-CLOSE_BLOCK_RING, CLOSE_BLOCK_RING + 1):
			blocks[Vector2i(bx, by)] = true
	for idx in k.plots:
		blocks[block_of(idx)] = true
	var r := block_rect(k, Vector2i.ZERO).grow(1)
	for b in blocks:
		r = r.merge(block_rect(k, b).grow(1))
	return r


## Lay out the grid on the king group's house: it becomes plot (0,0), the bottom-left plot
## of block (0,0), sitting in that plot's inner (top-right) corner so its bottom door faces
## the outer road.
static func found(k: Kingdom) -> void:
	var anchor: House = null
	var order: Array[Faction] = []
	var lead: Faction = World.factions.get(k.leading_fid)
	if lead:
		order.append(lead)
	order.append_array(k.members())
	for f in order:
		for h in f.homes():
			if h.state != House.State.PLANNED:
				anchor = h
				break
		if anchor:
			break
	if anchor == null:
		return
	k.has_city = true
	var fp := anchor.footprint()
	k.city_origin = Vector2i(fp.end.x - PLOT, fp.position.y)
	k.plots[Vector2i.ZERO] = {"kind": "house", "fid": anchor.faction_id, "house": anchor}
	anchor.plot_kid = k.id
	anchor.plot = Vector2i.ZERO
	# The plaza goes just across the road from the king's door, so the leader's own block
	# stays free for houses (v3 §1.2).
	var plaza := Vector2i(0, 1) if _plot_ok(k, Vector2i(0, 1)) else _search_plot(k, 1, 1)
	if plaza != NONE:
		k.plots[plaza] = {"kind": "plaza", "fid": -1, "house": null}
	for f in k.members():
		assign_house_plot(k, f)
	EventBus.log_event("%s lays out a city grid around %s's house." % [k.name, World.factions[anchor.faction_id].name])


static func _plot_of(k: Kingdom, f: Faction, kind: String, unbuilt_only: bool = false) -> Vector2i:
	for idx in k.plots:
		var p: Dictionary = k.plots[idx]
		if p.fid == f.id and p.kind == kind and (not unbuilt_only or p.house == null):
			return idx
	return NONE


## Every group gets a house plot: the leader's block first, then the adjacent blocks, then
## the nearest free plot anywhere (agreed order). No free plot close by: push neighbours out.
static func assign_house_plot(k: Kingdom, f: Faction) -> void:
	var cur := _plot_of(k, f, "house")
	if cur != NONE:
		# Not built on yet and far out: take a closer plot if one has come free.
		if k.plots[cur].house == null and ring(cur) > CLOSE_BLOCK_RING:
			var near := _nearer_plot(k, CLOSE_BLOCK_RING)
			if near != NONE:
				k.plots.erase(cur)
				k.plots[near] = {"kind": "house", "fid": f.id, "house": null}
		return
	var idx := _house_plot(k)
	if idx != NONE:
		k.plots[idx] = {"kind": "house", "fid": f.id, "house": null}


static func _house_plot(k: Kingdom) -> Vector2i:
	if SimClock.time < k.plot_retry_at:
		return NONE
	var idx := _free_plot(k, 0, MAX_BLOCK_RING)
	if idx == NONE or ring(idx) > CLOSE_BLOCK_RING:
		k.room_short_until = SimClock.time + 60.0
	return idx


## Nearest free, buildable plot between the given block rings. A failed search (crowded
## map) isn't repeated for a while.
static func _free_plot(k: Kingdom, min_ring: int, max_ring: int) -> Vector2i:
	if SimClock.time < k.plot_retry_at:
		return NONE
	var idx := _search_plot(k, min_ring, max_ring)
	if idx == NONE:
		k.plot_retry_at = SimClock.time + 30.0
	return idx


## Candidate plots: nearer block rings first, blocks already started before new ones (fill
## a block first), then distance from the centre plot.
static func _search_plot(k: Kingdom, min_ring: int, max_ring: int) -> Vector2i:
	for idx in candidate_plots(k, min_ring, max_ring):
		if _plot_ok(k, idx):
			return idx
	return NONE


static func candidate_plots(k: Kingdom, min_ring: int, max_ring: int) -> Array[Vector2i]:
	var started := {}
	for idx in k.plots:
		started[block_of(idx)] = true
	var centre := Vector2(plot_rect(k, Vector2i.ZERO).get_center())
	var cands: Array = []
	for bx in range(-max_ring, max_ring + 1):
		for by in range(-max_ring, max_ring + 1):
			var b := Vector2i(bx, by)
			var r: int = max(abs(bx), abs(by))
			if r < min_ring:
				continue
			for idx in block_plots(b):
				if k.plots.has(idx):
					continue
				var d := World.dist(centre, Vector2(plot_rect(k, idx).get_center()))
				cands.append([r * 10000.0 + (0.0 if started.has(b) else 5000.0) + d, idx])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	var out: Array[Vector2i] = []
	for c in cands:
		out.append(c[1])
	return out


static func _plot_ok(k: Kingdom, idx: Vector2i) -> bool:
	if k.plots.has(idx):
		return false
	var r := plot_rect(k, idx)
	if r.position.x < 2 or r.position.y < 2 or r.end.x > Cfg.MAP_W - 2 or r.end.y > Cfg.MAP_H - 2:
		return false
	var fid: int = k.groups[0]
	# Other kingdoms' cities (their plots and ring roads).
	for ok in World.kingdoms.values():
		if ok != k and ok.has_city:
			for oidx in ok.plots:
				if World.rects_meet(plot_rect(ok, oidx).grow(1), r.grow(1)):
					return false
	if not World.house_fire_spacing_ok(r.get_center(), null, fid):
		return false
	if World.footprint_clash(r.grow(-1)):
		return false
	# Neighbouring plots' houses sit right against the edge, so only the plot itself is checked.
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var c := Vector2i(x, y)
			if World.walls.has(World.wc(c)) or World.fires.has(World.wc(c)):
				return false
			var po := World.privilege_owner(c)
			if po != 0 and not World.same_side(po, fid):
				return false
	return true


## Plan a house or workshop on a city plot (called instead of a free site search). The
## building sits in the plot's inner corner (wall to wall with the block's other houses)
## with its door on the outer side nearest the road (agreed).
static func plan_on_plot(f: Faction, cap: int, kind: int) -> House:
	var k := f.kingdom
	var idx := NONE
	var plot_kind := "house"
	if kind == House.Kind.WORKSHOP:
		plot_kind = "workshop"
	elif kind == House.Kind.SMELTERY:
		plot_kind = "smeltery"
	if kind == House.Kind.HOUSE:
		idx = _plot_of(k, f, "house", true)
		if idx == NONE:
			idx = _house_plot(k)
	else:
		idx = _free_plot(k, 1, MAX_BLOCK_RING) # workshops and smelteries further out
	if idx == NONE:
		return null
	var r := plot_rect(k, idx)
	var size: Vector2i = House.size_for(kind, cap)
	var outer := size + Vector2i(2, 2)
	var sub := sub_of(idx)
	var pos := Vector2i(r.end.x - outer.x if sub.x == 0 else r.position.x, r.end.y - outer.y if sub.y == 0 else r.position.y)
	var side_h := Vector2i(-1, 0) if sub.x == 0 else Vector2i(1, 0)
	var side_v := Vector2i(0, -1) if sub.y == 0 else Vector2i(0, 1)
	var dir := side_h if PLOT - outer.x < PLOT - outer.y else side_v
	var h := House.new(f.id, Rect2i(pos + Vector2i.ONE, size), cap, kind, dir)
	h.plot_kid = k.id
	h.plot = idx
	k.plots[idx] = {"kind": plot_kind, "fid": f.id, "house": h}
	f.houses.append(h)
	World.buildings_version += 1
	f.board.post(Task.new(Task.Type.PLACE_HOUSE_FIRE, h.fire_cell, h))
	return h


## Relocation (agreed): a kingdom group builds its plot house first and only abandons the
## old house once the new one is COMPLETE.
static func relocate(f: Faction) -> void:
	var k := f.kingdom
	if k == null or not k.has_city:
		return
	var on_plot: Array[House] = []
	for h in f.homes():
		if h.plot_kid == k.id:
			on_plot.append(h)
	if on_plot.is_empty():
		assign_house_plot(k, f)
		Factions.plan_house(f, clamp(f.members.size() + 1, 2, Cfg.FACTION_MAX))
		return
	# A free plot in a nearer block ring than every home: build there and move in (the
	# city packs around the leader's house over time).
	var best := 99
	for h in on_plot:
		best = min(best, ring(h.plot))
	if best > 0 and not f.houses.any(func(h): return h.state == House.State.PLANNED):
		var near := _nearer_plot(k, best - 1)
		if near != NONE:
			k.plots[near] = {"kind": "house", "fid": f.id, "house": null}
			Factions.plan_house(f, clamp(f.members.size() + 1, 2, Cfg.FACTION_MAX))
	# Keep the nearest ring of homes whose finished houses hold everyone; leave the rest.
	var keep_ring := -1
	for r in range(0, MAX_BLOCK_RING + 1):
		var room := 0
		for h in on_plot:
			if ring(h.plot) <= r and h.state == House.State.COMPLETE:
				room += h.capacity
		if room >= f.members.size():
			keep_ring = r
			break
	if keep_ring == -1:
		if not on_plot.any(func(h): return h.state == House.State.COMPLETE):
			return
		keep_ring = MAX_BLOCK_RING # not enough room near the leader yet: only leave off-plot homes
	for h in f.homes():
		var keep := h.plot_kid == k.id and ring(h.plot) <= keep_ring
		if keep or (h.state == House.State.PLANNED and h.plot_kid == k.id):
			continue
		Factions.abandon_house(h)
		f.houses.erase(h)
		World.buildings_version += 1
		f.board.remove_for_house(h)
		if h.plot_kid == k.id and k.plots.has(h.plot) and k.plots[h.plot].house == h:
			k.plots.erase(h.plot)
		EventBus.log_event("%s moves %s the city of %s." % [f.name, "closer in" if h.plot_kid == k.id else "into", k.name])


## A free plot no further out than this block ring (throttled like any search).
static func _nearer_plot(k: Kingdom, max_ring: int) -> Vector2i:
	if SimClock.time < k.close_retry_at:
		return NONE
	var idx := _search_plot(k, 0, max_ring)
	if idx == NONE:
		k.close_retry_at = SimClock.time + 30.0
	return idx


static func has_house_plot(f: Faction) -> bool:
	return f.kingdom != null and f.kingdom.has_city


# --- City works: clearing, demolition and roads ---

static func update(k: Kingdom) -> void:
	if not k.has_city:
		found(k)
		return
	for f in k.members():
		assign_house_plot(k, f)
	var board := k.board
	var have := {}
	var roads_open := 0
	var clears_open := 0
	for t in board.tasks:
		have[Vector3i(t.cell.x, t.cell.y, t.type)] = true
		if t.type == Task.Type.BUILD_ROAD or t.type == Task.Type.UPGRADE_ROAD:
			roads_open += 1
		elif t.type == Task.Type.CLEAR_NODE:
			clears_open += 1
	# Trees and rocks on plots being built, and on the roads we want next (agreed).
	var to_clear: Array[Vector2i] = []
	for idx in k.plots:
		var p: Dictionary = k.plots[idx]
		var h: House = p.house
		if p.kind == "plaza" or (h != null and h.state != House.State.COMPLETE):
			var r := plot_rect(k, idx)
			for x in range(r.position.x, r.end.x):
				for y in range(r.position.y, r.end.y):
					if World.nodes.has(World.wc(Vector2i(x, y))):
						to_clear.append(Vector2i(x, y))
	var targets := road_targets(k)
	for c in targets:
		if World.nodes.has(World.wc(c)):
			to_clear.append(c)
	for c in to_clear:
		if clears_open >= MAX_CLEAR_TASKS:
			break
		if not have.has(Vector3i(c.x, c.y, Task.Type.CLEAR_NODE)):
			board.post(Task.new(Task.Type.CLEAR_NODE, c, null))
			have[Vector3i(c.x, c.y, Task.Type.CLEAR_NODE)] = true
			clears_open += 1
	# Kingdom board at the plaza (4 wood).
	var plaza := plaza_plot(k)
	if plaza != NONE:
		var bc := plot_rect(k, plaza).get_center()
		var fu: Furniture = World.furniture.get(World.wc(bc))
		if (fu == null or fu.kind != Furniture.Kind.BOARD) and not have.has(Vector3i(bc.x, bc.y, Task.Type.PLACE_BOARD)):
			board.post(Task.new(Task.Type.PLACE_BOARD, bc, null))
	# Roads for the current stage; once all are built, pave the roads linking the city's
	# buildings (needs a working workshop for the cut stone).
	for c in targets:
		if roads_open >= MAX_ROAD_TASKS:
			break
		if not World.nodes.has(World.wc(c)) and not have.has(Vector3i(c.x, c.y, Task.Type.BUILD_ROAD)):
			board.post(Task.new(Task.Type.BUILD_ROAD, c, null))
			roads_open += 1
	if targets.is_empty() and _kingdom_has_workshop(k):
		for c in paving_cells(k):
			if roads_open >= MAX_ROAD_TASKS:
				break
			if World.roads.get(World.wc(c), 0) == 1 and not have.has(Vector3i(c.x, c.y, Task.Type.UPGRADE_ROAD)):
				board.post(Task.new(Task.Type.UPGRADE_ROAD, c, null))
				roads_open += 1
	if SimClock.time >= k.push_check_at:
		k.push_check_at = SimClock.time + Cfg.PUSH_CHECK_SECS
		_post_demolish(k, have)
		PushOut.update(k)
	Tax.update(k)


## DEMOLISH (agreed): every piece in the city area that belongs to no live building
## (abandoned houses, burnt-out ones, stray walls) is torn down, no refund.
static func _post_demolish(k: Kingdom, have: Dictionary) -> void:
	var open := 0
	for t in k.board.tasks:
		if t.type == Task.Type.DEMOLISH:
			open += 1
	if open >= MAX_DEMOLISH_TASKS:
		return
	var area := city_rect(k)
	var cells: Array[Vector2i] = []
	for c in World.walls:
		if World.rect_has(area, c):
			cells.append(c)
	for c in World.fires:
		var f: Campfire = World.fires[World.wc(c)]
		if f.is_house and f.house == null and World.rect_has(area, c):
			cells.append(c)
	for c in World.furniture:
		var fu: Furniture = World.furniture[World.wc(c)]
		if fu.kind != Furniture.Kind.BOARD and not _live_mailbox(fu) and World.rect_has(area, c):
			cells.append(c)
	for c in World.floors:
		if World.rect_has(area, c):
			cells.append(c)
	if cells.is_empty():
		return
	var live: Array[Rect2i] = []
	for h in World.all_houses():
		if World.rects_meet(h.footprint(), area):
			live.append(h.footprint())
	for c in cells:
		if open >= MAX_DEMOLISH_TASKS:
			break
		if have.has(Vector3i(c.x, c.y, Task.Type.DEMOLISH)) or live.any(func(r): return World.rect_has(r, c)):
			continue
		k.board.post(Task.new(Task.Type.DEMOLISH, c, null))
		have[Vector3i(c.x, c.y, Task.Type.DEMOLISH)] = true
		open += 1


## Something at the cell to tear down that no live building owns.
static func is_junk(c: Vector2i) -> bool:
	var f: Campfire = World.fires.get(World.wc(c))
	var fu: Furniture = World.furniture.get(World.wc(c))
	var piece := World.walls.has(World.wc(c)) or World.floors.has(World.wc(c)) or (fu != null and fu.kind != Furniture.Kind.BOARD and not _live_mailbox(fu)) or (f != null and f.is_house and f.house == null)
	if not piece:
		return false
	for h in World.all_houses():
		if World.rect_has(h.footprint(), c):
			return false
	return true



## A mailbox stands outside its building's walls (D10), so it's only junk once its house is gone.
static func _live_mailbox(fu: Furniture) -> bool:
	return fu.kind == Furniture.Kind.MAILBOX and fu.house != null and fu.house.alive()


## Tear down whatever stands at the cell (chests spill their contents).
static func demolish(c: Vector2i) -> void:
	var w: Wall = World.walls.get(World.wc(c))
	if w:
		World.remove_wall(w)
	var f: Campfire = World.fires.get(World.wc(c))
	if f and f.is_house and f.house == null:
		World.remove_fire(f)
	var fu: Furniture = World.furniture.get(World.wc(c))
	if fu and fu.kind != Furniture.Kind.BOARD:
		World.remove_furniture(fu, "chest destroyed")
	World.floors.erase(World.wc(c))
	World.pieces_version += 1
	demolished += 1


static func _kingdom_has_workshop(k: Kingdom) -> bool:
	for f in k.members():
		for w in f.workshops():
			if w.operational():
				return true
	return false


static func plaza_plot(k: Kingdom) -> Vector2i:
	for idx in k.plots:
		if k.plots[idx].kind == "plaza":
			return idx
	return NONE


## Unbuilt road cells for the current build stage (agreed order): the plaza, then the
## ring roads around blocks, then a spur from each door to its ring road.
static func road_targets(k: Kingdom) -> Array[Vector2i]:
	var stages: Array = [_plaza_cells(k), _ring_cells(k), _spur_cells(k)]
	for cells in stages:
		var out: Array[Vector2i] = []
		for c in cells:
			if not World.roads.has(World.wc(c)) and _road_ok(c):
				out.append(c)
		if not out.is_empty():
			return out
	return []


static func city_road_cells(k: Kingdom) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(_plaza_cells(k))
	out.append_array(_ring_cells(k))
	out.append_array(_spur_cells(k))
	return out


## Roads worth paving: the shortest stone-road links from the king's door to every other
## finished building's door. The plaza and roads nobody needs to reach a building stay
## unpaved, so cut stone goes to the smeltery and the stone tier first.
static func paving_cells(k: Kingdom) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var plaza := {}
	for c in _plaza_cells(k):
		plaza[c] = true
	var net := {}
	var order := city_road_cells(k)
	for c in order:
		if World.roads.has(World.wc(c)) and not plaza.has(c):
			net[c] = true
	var doors: Array[Vector2i] = []
	var root := NONE
	for idx in k.plots:
		var h: House = k.plots[idx].house
		if h == null or h.state != House.State.COMPLETE:
			continue
		var d := h.door_outside()
		if not net.has(d):
			continue
		if idx == Vector2i.ZERO:
			root = d
		doors.append(d)
	if doors.is_empty():
		return out
	if root == NONE:
		root = doors[0]
	var parent := {root: root}
	var queue: Array[Vector2i] = [root]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dir
			if net.has(n) and not parent.has(n):
				parent[n] = c
				queue.append(n)
	var keep := {}
	for d in doors:
		if not parent.has(d):
			continue
		var c := d
		while not keep.has(c):
			keep[c] = true
			if c == root:
				break
			c = parent[c]
	for c in order:
		if keep.has(c):
			out.append(c)
			keep.erase(c)
	return out


static func _road_ok(c: Vector2i) -> bool:
	return World.in_bounds(c) and not World.walls.has(World.wc(c)) and not World.fires.has(World.wc(c)) and not World.floors.has(World.wc(c))


static func _plaza_cells(k: Kingdom) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var idx := plaza_plot(k)
	if idx == NONE:
		return out
	var r := plot_rect(k, idx)
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			out.append(Vector2i(x, y))
	return out


## The 1-cell ring road around every block that has a finished building (or the plaza).
## Roads run only around blocks, never between a block's plots (agreed).
static func _ring_cells(k: Kingdom) -> Array[Vector2i]:
	var blocks := {}
	for idx in k.plots:
		var p: Dictionary = k.plots[idx]
		var h: House = p.house
		if p.kind == "plaza" or (h != null and h.state == House.State.COMPLETE):
			blocks[block_of(idx)] = true
	var seen := {}
	var out: Array[Vector2i] = []
	for b in blocks:
		var g := block_rect(k, b).grow(1)
		for x in range(g.position.x, g.end.x):
			for y in [g.position.y, g.end.y - 1]:
				_add_once(Vector2i(x, y), seen, out)
		for y in range(g.position.y + 1, g.end.y - 1):
			for x in [g.position.x, g.end.x - 1]:
				_add_once(Vector2i(x, y), seen, out)
	return out


## From each door straight out to the block's ring road.
static func _spur_cells(k: Kingdom) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for idx in k.plots:
		var h: House = k.plots[idx].house
		if h == null or h.state != House.State.COMPLETE:
			continue
		var br := block_rect(k, block_of(idx))
		var c := h.door_outside()
		while World.rect_has(br, c):
			out.append(c)
			c += h.door_dir
	return out


static func _add_once(c: Vector2i, seen: Dictionary, out: Array[Vector2i]) -> void:
	if not seen.has(c):
		seen[c] = true
		out.append(c)


## True if the cell is on a city plot or road line (resource respawns avoid these; agreed).
static func in_city(c: Vector2i) -> bool:
	if World.roads.has(World.wc(c)):
		return true
	for k in World.kingdoms.values():
		if not k.has_city:
			continue
		var rel: Vector2i = c - (k.city_origin - Vector2i(0, PLOT))
		var b := Vector2i(floori(rel.x / float(BLOCK)), floori(rel.y / float(BLOCK)))
		if max(abs(b.x), abs(b.y)) > MAX_BLOCK_RING + 1:
			continue
		var w := Vector2i(posmod(rel.x, BLOCK), posmod(rel.y, BLOCK))
		if w.x == PLOT * 2 or w.y == PLOT * 2:
			return true # a ring road line
		if k.plots.has(Vector2i(b.x * 2 + w.x / PLOT, b.y * 2 + w.y / PLOT - 1)):
			return true
	return false
