class_name Cities
## City grids for kingdoms (Phase E): 10x10 plots on an 11-cell pitch separated by 1-cell
## roads, anchored on the king group's house fire. Plot assignment, relocation into the
## city, clearing trees and rocks, and roads (plaza, then roads between plots, then a
## spur to each door, then paving).

const PITCH := 11
const PLOT := 10
const MAX_RING := 4
const NONE := Vector2i(-9999, -9999)
const MAX_ROAD_TASKS := 30
const MAX_CLEAR_TASKS := 20


# --- Kingdom hooks ---

static func on_formed(k: Kingdom) -> void:
	found(k)


static func on_joined(k: Kingdom, f: Faction) -> void:
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

static func plot_rect(k: Kingdom, idx: Vector2i) -> Rect2i:
	return Rect2i(k.city_origin + idx * PITCH, Vector2i(PLOT, PLOT))


static func ring(idx: Vector2i) -> int:
	return max(abs(idx.x), abs(idx.y))


## Lay out the grid on the king group's house (that house is the centre plot).
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
	k.city_origin = anchor.fire_cell - Vector2i(PLOT / 2, PLOT / 2)
	k.plots[Vector2i.ZERO] = {"kind": "house", "fid": anchor.faction_id, "house": anchor}
	anchor.plot_kid = k.id
	anchor.plot = Vector2i.ZERO
	var plaza := _free_plot(k, 1, 1)
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


## Every group gets a house plot, nearest the centre first.
static func assign_house_plot(k: Kingdom, f: Faction) -> void:
	if _plot_of(k, f, "house") != NONE:
		return
	var idx := _free_plot(k, 1, MAX_RING)
	if idx != NONE:
		k.plots[idx] = {"kind": "house", "fid": f.id, "house": null}


## Nearest free, buildable plot between the given rings. A failed search (crowded map)
## isn't repeated for a while.
static func _free_plot(k: Kingdom, min_ring: int, max_ring: int) -> Vector2i:
	if SimClock.time < k.plot_retry_at:
		return NONE
	var idx := _search_plot(k, min_ring, max_ring)
	if idx == NONE:
		k.plot_retry_at = SimClock.time + 30.0
	return idx


static func _search_plot(k: Kingdom, min_ring: int, max_ring: int) -> Vector2i:
	for r in range(min_ring, max_ring + 1):
		var cands: Array[Vector2i] = []
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if max(abs(x), abs(y)) == r:
					cands.append(Vector2i(x, y))
		cands.sort_custom(func(a, b): return abs(a.x) + abs(a.y) < abs(b.x) + abs(b.y))
		for idx in cands:
			if _plot_ok(k, idx):
				return idx
	return NONE


static func _plot_ok(k: Kingdom, idx: Vector2i) -> bool:
	if k.plots.has(idx):
		return false
	var r := plot_rect(k, idx)
	if r.position.x < 2 or r.position.y < 2 or r.end.x > Cfg.MAP_W - 2 or r.end.y > Cfg.MAP_H - 2:
		return false
	var fid: int = k.groups[0]
	var g := r.grow(1)
	# Other kingdoms' plots.
	for ok in World.kingdoms.values():
		if ok != k and ok.has_city:
			for oidx in ok.plots:
				if plot_rect(ok, oidx).grow(1).intersects(g):
					return false
	if not World.house_fire_spacing_ok(r.get_center(), null, fid):
		return false
	if World.footprint_clash(r.grow(-1)):
		return false
	for x in range(g.position.x, g.end.x):
		for y in range(g.position.y, g.end.y):
			var c := Vector2i(x, y)
			if World.walls.has(c) or World.fires.has(c):
				return false
			var po := World.privilege_owner(c)
			if po != 0 and not World.same_side(po, fid):
				return false
	return true


## Plan a house or workshop on a city plot (called instead of a free site search).
static func plan_on_plot(f: Faction, cap: int, kind: int) -> House:
	var k := f.kingdom
	var idx := NONE
	var plot_kind := "workshop" if kind == House.Kind.WORKSHOP else "house"
	if kind == House.Kind.HOUSE:
		idx = _plot_of(k, f, "house", true)
		if idx == NONE:
			idx = _free_plot(k, 1, MAX_RING)
	else:
		idx = _free_plot(k, 2, MAX_RING)
	if idx == NONE:
		return null
	var r := plot_rect(k, idx)
	var size: Vector2i = Cfg.WORKSHOP_SIZE if kind == House.Kind.WORKSHOP else House.interior_size(cap)
	var outer := size + Vector2i(2, 2)
	var interior := Rect2i(r.position + (r.size - outer) / 2 + Vector2i.ONE, size)
	var h := House.new(f.id, interior, cap, kind)
	h.plot_kid = k.id
	h.plot = idx
	k.plots[idx] = {"kind": plot_kind, "fid": f.id, "house": h}
	f.houses.append(h)
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
	if not on_plot.any(func(h): return h.state == House.State.COMPLETE):
		return
	for h in f.homes():
		if h.plot_kid != k.id:
			Factions.abandon_house(h)
			f.houses.erase(h)
			f.board.remove_for_house(h)
			EventBus.log_event("%s moves into the city of %s." % [f.name, k.name])


static func has_house_plot(f: Faction) -> bool:
	return f.kingdom != null and f.kingdom.has_city


# --- City works: clearing and roads ---

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
					if World.nodes.has(Vector2i(x, y)):
						to_clear.append(Vector2i(x, y))
	var targets := road_targets(k)
	for c in targets:
		if World.nodes.has(c):
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
		var fu: Furniture = World.furniture.get(bc)
		if (fu == null or fu.kind != Furniture.Kind.BOARD) and not have.has(Vector3i(bc.x, bc.y, Task.Type.PLACE_BOARD)):
			board.post(Task.new(Task.Type.PLACE_BOARD, bc, null))
	# Roads for the current stage; once all are built, pave (needs a working workshop).
	for c in targets:
		if roads_open >= MAX_ROAD_TASKS:
			break
		if not World.nodes.has(c) and not have.has(Vector3i(c.x, c.y, Task.Type.BUILD_ROAD)):
			board.post(Task.new(Task.Type.BUILD_ROAD, c, null))
			roads_open += 1
	if targets.is_empty() and _kingdom_has_workshop(k):
		for c in city_road_cells(k):
			if roads_open >= MAX_ROAD_TASKS:
				break
			if World.roads.get(c, 0) == 1 and not have.has(Vector3i(c.x, c.y, Task.Type.UPGRADE_ROAD)):
				board.post(Task.new(Task.Type.UPGRADE_ROAD, c, null))
				roads_open += 1


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
## roads between plots, then a spur from each door to the road below its plot.
static func road_targets(k: Kingdom) -> Array[Vector2i]:
	var stages: Array = [_plaza_cells(k), _ring_cells(k), _spur_cells(k)]
	for cells in stages:
		var out: Array[Vector2i] = []
		for c in cells:
			if not World.roads.has(c) and _road_ok(c):
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


static func _road_ok(c: Vector2i) -> bool:
	return World.in_bounds(c) and not World.walls.has(c) and not World.fires.has(c) and not World.floors.has(c)


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


## The 1-cell road ring around every plot that has a finished building (or the plaza).
static func _ring_cells(k: Kingdom) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for idx in k.plots:
		var p: Dictionary = k.plots[idx]
		var h: House = p.house
		if p.kind != "plaza" and (h == null or h.state != House.State.COMPLETE):
			continue
		var g := plot_rect(k, idx).grow(1)
		for x in range(g.position.x, g.end.x):
			for y in [g.position.y, g.end.y - 1]:
				_add_once(Vector2i(x, y), seen, out)
		for y in range(g.position.y + 1, g.end.y - 1):
			for x in [g.position.x, g.end.x - 1]:
				_add_once(Vector2i(x, y), seen, out)
	return out


## From each door straight down to the next road row of the grid.
static func _spur_cells(k: Kingdom) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for idx in k.plots:
		var h: House = k.plots[idx].house
		if h == null or h.state != House.State.COMPLETE:
			continue
		var top := h.door_cell.y + 1
		var rel := top - (k.city_origin.y - 1)
		var road_y := k.city_origin.y - 1 + int(ceil(rel / float(PITCH))) * PITCH
		for y in range(top, road_y + 1):
			out.append(Vector2i(h.door_cell.x, y))
	return out


static func _add_once(c: Vector2i, seen: Dictionary, out: Array[Vector2i]) -> void:
	if not seen.has(c):
		seen[c] = true
		out.append(c)


## True if the cell is on a city plot or road line (resource respawns avoid these; agreed).
static func in_city(c: Vector2i) -> bool:
	if World.roads.has(c):
		return true
	for k in World.kingdoms.values():
		if not k.has_city:
			continue
		var rel: Vector2i = c - k.city_origin
		var idx := Vector2i(floori(rel.x / float(PITCH)), floori(rel.y / float(PITCH)))
		if ring(idx) > MAX_RING + 1:
			continue
		if k.plots.has(idx):
			return true
		if posmod(rel.x, PITCH) == PLOT or posmod(rel.y, PITCH) == PLOT:
			return true # a road line
	return false
