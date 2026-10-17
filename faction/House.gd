class_name House
extends RefCounted
## A rectangle of walls with one door, a fire in the middle, wood floors and furniture.
## A WORKSHOP is the same building with a sawmill and stone cutter instead of a chest and
## occupants; a SMELTERY (v3) has stone walls, a furnace, an anvil and two storage crates.

enum State { PLANNED, BUILDING, COMPLETE }
enum Kind { HOUSE, WORKSHOP, SMELTERY }

static var _next_id := 1

var id: int
var kind := Kind.HOUSE
var faction_id: int
var state := State.PLANNED
var interior: Rect2i
var fire_cell: Vector2i
var door_cell: Vector2i
var door_dir := Vector2i(0, 1) # the side the door faces (city houses face their block's outer road)
var wall_cells: Array[Vector2i] = []
var floor_cells: Array[Vector2i] = [] # every interior cell except the fire (agreed)
var chest_cell: Vector2i
var capacity: int
var occupants: Array[int] = []
var fire: Campfire = null
var chest: Furniture = null
var machine_cells := {} # Furniture.Kind -> cell (workshop and smeltery machines)
var crate_cells: Array[Vector2i] = [] # smeltery storage crates
var workers := {} # smeltery: Furniture.Kind -> [agent id, until] (one worker per machine)
var upgrade_to := 0 # target tier for walls, door and chest: 1 reinforced, 2 stone / metal (v3)
var plot_kid := -1 # kingdom id whose city plot this building stands on
var plot := Vector2i.ZERO # plot index in that city


func _init(fid: int, interior_rect: Rect2i, cap: int, k: Kind = Kind.HOUSE, dir: Vector2i = Vector2i(0, 1)) -> void:
	id = _next_id
	_next_id += 1
	kind = k
	faction_id = fid
	interior = interior_rect
	capacity = cap
	fire_cell = interior.position + Vector2i(interior.size.x / 2, interior.size.y / 2)
	var outer := interior.grow(1)
	door_dir = dir
	# Door one column (or row) beside the fire so the cell inside the door is never the
	# fire (otherwise the interior is only reachable diagonally = sealed off).
	var dx := fire_cell.x + 1 if fire_cell.x + 1 < interior.end.x else fire_cell.x - 1
	var dy := fire_cell.y + 1 if fire_cell.y + 1 < interior.end.y else fire_cell.y - 1
	match dir:
		Vector2i(0, -1): door_cell = Vector2i(dx, outer.position.y)
		Vector2i(1, 0): door_cell = Vector2i(outer.end.x - 1, dy)
		Vector2i(-1, 0): door_cell = Vector2i(outer.position.x, dy)
		_: door_cell = Vector2i(dx, outer.end.y - 1)
	for x in range(outer.position.x, outer.end.x):
		for y in range(outer.position.y, outer.end.y):
			var c := Vector2i(x, y)
			if interior.has_point(c) or c == door_cell:
				continue
			wall_cells.append(c)
	for x in range(interior.position.x, interior.end.x):
		for y in range(interior.position.y, interior.end.y):
			var c := Vector2i(x, y)
			if c != fire_cell:
				floor_cells.append(c)
	var top_left := interior.position
	var top_right := interior.position + Vector2i(interior.size.x - 1, 0)
	chest_cell = Vector2i(-1, -1)
	match kind:
		Kind.WORKSHOP:
			machine_cells = {Furniture.Kind.SAWMILL: top_left, Furniture.Kind.CUTTER: top_right}
		Kind.SMELTERY:
			machine_cells = {Furniture.Kind.FURNACE: top_left, Furniture.Kind.ANVIL: top_right}
			crate_cells = [interior.position + Vector2i(0, interior.size.y - 1), interior.end - Vector2i.ONE]
		_:
			chest_cell = top_left # away from the door


## Interior size needed: CELLS_PER_OCCUPANT per occupant + 1 for the fire + 1 per furniture piece.
static func interior_size(cap: int) -> Vector2i:
	var area := Cfg.CELLS_PER_OCCUPANT * cap + 1 + Cfg.FURNITURE_PER_HOUSE
	var w := int(ceil(sqrt(float(area))))
	var h := int(ceil(float(area) / w))
	return Vector2i(w, h)


static func size_for(k: int, cap: int) -> Vector2i:
	match k:
		Kind.WORKSHOP: return Cfg.WORKSHOP_SIZE
		Kind.SMELTERY: return Cfg.SMELTERY_SIZE
	return interior_size(cap)


## The cell just outside the door (must stay walkable).
func door_outside(dist: int = 1) -> Vector2i:
	return door_cell + door_dir * dist


func footprint() -> Rect2i:
	return interior.grow(1)


func has_room() -> bool:
	return occupants.size() < capacity


func is_home() -> bool:
	return kind == Kind.HOUSE


func is_workshop() -> bool:
	return kind == Kind.WORKSHOP


func is_smeltery() -> bool:
	return kind == Kind.SMELTERY


func label() -> String:
	match kind:
		Kind.WORKSHOP: return "workshop"
		Kind.SMELTERY: return "smeltery"
	return "house"


## Tier a newly built wall gets: smeltery walls are stone from the start (agreed).
func base_wall_tier() -> int:
	return 2 if kind == Kind.SMELTERY else 0


## A machine of this building, if it's still standing.
func machine(k: int) -> Furniture:
	if not machine_cells.has(k):
		return null
	var fu: Furniture = World.furniture.get(machine_cells[k])
	return fu if fu and fu.kind == k and fu.house == self else null


## The furniture kind that belongs on this cell (machines and crates), or -1.
func furniture_kind_at(c: Vector2i) -> int:
	for k in machine_cells:
		if machine_cells[k] == c:
			return k
	if c in crate_cells:
		return Furniture.Kind.CRATE
	return -1


## Ready for processing: built, fire burning, every machine in place.
func operational() -> bool:
	if kind == Kind.HOUSE or state != State.COMPLETE or fire == null or not fire.burning():
		return false
	for k in machine_cells:
		if machine(k) == null:
			return false
	return true


## Claim a machine for smeltery work; false if someone else is working it.
func claim_worker(k: int, agent_id: int) -> bool:
	var w: Array = workers.get(k, [-1, 0.0])
	if w[0] != agent_id and w[0] != -1 and SimClock.time < w[1] and World.agents.has(w[0]):
		return false
	workers[k] = [agent_id, SimClock.time + Cfg.SMITH_CLAIM_SECS]
	return true


## The smeltery's storage crates that are still standing.
func crates() -> Array[Furniture]:
	var out: Array[Furniture] = []
	for c in crate_cells:
		var fu: Furniture = World.furniture.get(c)
		if fu and fu.kind == Furniture.Kind.CRATE and fu.house == self:
			out.append(fu)
	return out


## Every wall, the door and the chest are at least this tier (as far as it can be made yet).
func fully_upgraded(tier: int) -> bool:
	for c in wall_cells:
		var w: Wall = World.walls.get(c)
		if w == null or w.tier < tier:
			return false
	var dw: Wall = World.walls.get(door_cell)
	if dw == null or dw.tier < min(tier, Items.max_door_tier()):
		return false
	if kind != Kind.HOUSE:
		return true
	var ch := live_chest()
	return ch != null and ch.tier >= min(tier, Items.max_chest_tier())


## The chest, if it's still standing.
func live_chest() -> Furniture:
	if chest and World.furniture.get(chest.cell) == chest:
		return chest
	chest = null
	return null
