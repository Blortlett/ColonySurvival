class_name TaskBoard
extends RefCounted
## Shared task list so faction members don't double up on work.

var tasks: Array[Task] = []


func post(t: Task) -> void:
	t.board = self
	tasks.append(t)


func find(type: int, cell: Vector2i) -> Task:
	for t in tasks:
		if t.type == type and t.cell == cell:
			return t
	return null


func complete(t: Task) -> void:
	t.done = true
	tasks.erase(t)


func remove_for_house(h: House) -> void:
	for t in tasks.duplicate():
		if t.house == h:
			t.done = true
			tasks.erase(t)


func release(agent_id: int) -> void:
	for t in tasks:
		if t.claimed_by == agent_id:
			t.claimed_by = -1


## Claim the best unclaimed task for this agent (highest priority, then nearest).
func claim(agent_id: int, from: Vector2i, allowed: Callable = Callable()) -> Task:
	var best: Task = null
	var best_score := -INF
	for t in tasks:
		if t.claimed_by != -1:
			if SimClock.time - t.claim_time > Task.CLAIM_TIMEOUT or not World.agents.has(t.claimed_by):
				t.claimed_by = -1
			else:
				continue
		if t.blocked():
			continue # a CLEAR_NODE task clears the cell first
		if t.type == Task.Type.BUILD_DOOR and not _shell_done(t.house):
			continue # door goes in last: fire -> walls -> floors -> door (agreed build order)
		if allowed.is_valid() and not allowed.call(t.cell):
			continue
		var score := t.priority() * 10.0 - from.distance_to(t.cell)
		if score > best_score:
			best_score = score
			best = t
	if best:
		best.claimed_by = agent_id
		best.claim_time = SimClock.time
	return best


func _shell_done(h: House) -> bool:
	for t in tasks:
		if t.house == h and (t.type == Task.Type.BUILD_WALL or t.type == Task.Type.BUILD_FLOOR):
			return false
	return true


## Cells that already have a task of this type (to avoid posting duplicates).
func cells_of(type: int) -> Dictionary:
	var out := {}
	for t in tasks:
		if t.type == type:
			out[t.cell] = true
	return out
