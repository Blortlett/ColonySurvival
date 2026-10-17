class_name House
extends RefCounted
## A rectangle of walls with one door, a fire in the middle, wood floors and furniture.
## A WORKSHOP is the same building with a sawmill and stone cutter instead of a chest and occupants.

enum State { PLANNED, BUILDING, COMPLETE }
enum Kind { HOUSE, WORKSHOP }

static var _next_id := 1

var id: int
var kind := Kind.HOUSE
var faction_id: int
var state := State.PLANNED
var interior: Rect2i
var fire_cell: Vector2i
var door_cell: Vector2i
var wall_cells: Array[Vector2i] = []
var floor_cells: Array[Vector2i] = [] # every interior cell except the fire (agreed)
var chest_cell: Vector2i
var capacity: int
var occupants: Array[int] = []
var fire: Campfire = null
var chest: Furniture = null
var saw_cell := Vector2i(-1, -1) # workshops
var cutter_cell := Vector2i(-1, -1)
var reinforce := false # upgrade walls, door and chest to reinforced
var plot_kid := -1 # kingdom id whose city plot this building stands on
var plot := Vector2i.ZERO # plot index in that city


func _init(fid: int, interior_rect: Rect2i, cap: int, k: Kind = Kind.HOUSE) -> void:
	id = _next_id
	_next_id += 1
	kind = k
	faction_id = fid
	interior = interior_rect
	capacity = cap
	fire_cell = interior.position + Vector2i(interior.size.x / 2, interior.size.y / 2)
	var outer := interior.grow(1)
	# Door in the bottom wall, one column right of the fire so the cell inside the door is
	# never the fire (otherwise the interior is only reachable diagonally = sealed off).
	door_cell = Vector2i(fire_cell.x + 1, outer.end.y - 1)
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
	if kind == Kind.WORKSHOP:
		chest_cell = Vector2i(-1, -1)
		saw_cell = interior.position
		cutter_cell = interior.position + Vector2i(interior.size.x - 1, 0)
	else:
		chest_cell = interior.position # top-left corner, away from the door


## Interior size needed: CELLS_PER_OCCUPANT per occupant + 1 for the fire + 1 per furniture piece.
static func interior_size(cap: int) -> Vector2i:
	var area := Cfg.CELLS_PER_OCCUPANT * cap + 1 + Cfg.FURNITURE_PER_HOUSE
	var w := int(ceil(sqrt(float(area))))
	var h := int(ceil(float(area) / w))
	return Vector2i(w, h)


func footprint() -> Rect2i:
	return interior.grow(1)


func has_room() -> bool:
	return occupants.size() < capacity


func is_workshop() -> bool:
	return kind == Kind.WORKSHOP


func label() -> String:
	return "workshop" if kind == Kind.WORKSHOP else "house"


## A workshop machine, if it's still standing.
func machine(k: int) -> Furniture:
	var c := saw_cell if k == Furniture.Kind.SAWMILL else cutter_cell
	var fu: Furniture = World.furniture.get(c)
	return fu if fu and fu.kind == k and fu.house == self else null


## Workshop ready for processing: built, fire burning, both machines in place.
func operational() -> bool:
	return kind == Kind.WORKSHOP and state == State.COMPLETE and fire != null and fire.burning() 		and machine(Furniture.Kind.SAWMILL) != null and machine(Furniture.Kind.CUTTER) != null


## Every wall, the door and the chest are reinforced.
func fully_reinforced() -> bool:
	for c in wall_cells + [door_cell]:
		var w: Wall = World.walls.get(c)
		if w == null or w.tier < 1:
			return false
	var ch := live_chest()
	return kind == Kind.WORKSHOP or (ch != null and ch.tier >= 1)


## The chest, if it's still standing.
func live_chest() -> Furniture:
	if chest and World.furniture.get(chest.cell) == chest:
		return chest
	chest = null
	return null
