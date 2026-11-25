extends RefCounted
## Wrap checks (Summer Roadmap §4.1), headless: godot --headless --path . -- --seamtest
## Paths and walking across both seams, wrapped lookups, distances, spatial queries,
## rect checks and node searches near the corner. Prints PASS/FAIL per check.

static var _fails := 0


## Runs on the world Main just set up; returns the number of failed checks.
static func run() -> int:
	var w = World
	if not Cfg.WRAP:
		print("WRAP is off; nothing to test")
		return 0
	var W := Cfg.MAP_W
	var H := Cfg.MAP_H

	# Geometry.
	_check(is_equal_approx(w.dist(Vector2(1, 5), Vector2(W - 1, 5)), 2.0), "dist across the x seam is 2")
	_check(w.delta(Vector2(5, 1), Vector2(5, H - 1)) == Vector2(0, -2), "delta across the y seam points up")
	_check(w.cheb(Vector2i(0, 0), Vector2i(W - 1, H - 1)) == 1, "corner cells are neighbours")
	_check(w.wc(Vector2i(-1, H)) == Vector2i(W - 1, 0), "wc wraps both axes")
	_check(w.rect_has(Rect2i(W - 2, 10, 4, 4), Vector2i(1, 11)), "rect_has finds a cell past the seam")
	_check(w.rects_meet(Rect2i(W - 2, 10, 4, 4), Rect2i(0, 12, 2, 2)), "rects_meet across the seam")

	# Clear a corridor across both seams so the walk is about wrapping, not obstacles.
	for x in range(-12, 13):
		for y in range(-12, 13):
			var c: Vector2i = w.wc(Vector2i(x, y))
			var n = w.nodes.get(c)
			if n:
				w.remove_node(n)

	# A wall just past the x seam is found from the other side.
	w.place_wall(Vector2i(-3, 6), false, 0)
	_check(w.walls.has(Vector2i(W - 3, 6)), "a wall placed at x = -3 lands on x = W - 3")
	_check(w.blocks_walk(Vector2i(-3, 6)), "blocks_walk sees it through an alias")

	# Pathfinding and walking across the corner.
	var a = w.spawn_agent(0, Vector2i(W - 5, H - 5))
	var dest := Vector2i(4, 4)
	var path: Array[Vector2i] = w.find_path(a, dest)
	_check(not path.is_empty(), "a path exists from (W-5, H-5) to (4, 4)")
	_check(path.size() <= 12, "it crosses the seam (%d steps, the long way is ~%d)" % [path.size(), W - 9])
	_check(path.all(func(c): return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H), "path cells are canonical")
	var steps := 0
	while Actions.move_path(a, dest, 0.1) == Actions.Move.MOVING and steps < 2000:
		steps += 1
	_check(a.cell() == dest, "the agent walks there (at %s after %d steps)" % [a.cell(), steps])
	_check(a.pos.x >= 0.0 and a.pos.x < W and a.pos.y >= 0.0 and a.pos.y < H, "its position stays canonical")

	# Spatial hash: an agent just across the seam is found nearby.
	var b = w.spawn_agent(0, Vector2i(W - 1, 4))
	w.spatial.rebuild(w.agent_list)
	_check(w.agents_near(a.pos, 6.0).has(b), "agents_near finds an agent across the seam")

	# Node search: a node across the seam is the nearest.
	var bush = w.add_node(ResourceNode.Type.BUSH, Vector2i(W - 2, 4))
	var found = w.nearest_node(ResourceNode.Type.BUSH, a.cell(), 10.0)
	_check(found == bush, "nearest_node looks across the seam")

	# Zones wrap: a fire near the corner claims cells on the far side.
	var f = w.place_fire(Vector2i(1, 1), true, a.faction.id)
	f.fuel_secs = 100.0
	w.zones_dirty = true
	_check(w.privilege_owner(Vector2i(W - 3, H - 3)) == a.faction.id, "a zone reaches across the corner")

	print("seam test: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	return _fails


static func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print(("  ok   " if ok else "  FAIL ") + what)
