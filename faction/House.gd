class_name House
extends RefCounted
## A rectangle of walls with one door and a house fire in the middle.

enum State { PLANNED, BUILDING, COMPLETE }

static var _next_id := 1

var id: int
var faction_id: int
var state := State.PLANNED
var interior: Rect2i
var fire_cell: Vector2i
var door_cell: Vector2i
var wall_cells: Array[Vector2i] = []
var capacity: int
var occupants: Array[int] = []
var fire: Campfire = null


func _init(fid: int, interior_rect: Rect2i, cap: int) -> void:
	id = _next_id
	_next_id += 1
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


## Interior size needed: CELLS_PER_OCCUPANT per occupant + 1 cell for the fire.
static func interior_size(cap: int) -> Vector2i:
	var area := Cfg.CELLS_PER_OCCUPANT * cap + 1
	var w := int(ceil(sqrt(float(area))))
	var h := int(ceil(float(area) / w))
	return Vector2i(w, h)


func footprint() -> Rect2i:
	return interior.grow(1)


func has_room() -> bool:
	return occupants.size() < capacity
