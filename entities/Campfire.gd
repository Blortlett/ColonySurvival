class_name Campfire
extends RefCounted
## A house fire (claims build privilege) or a wild fire (just warmth).

var cell: Vector2i
var is_house: bool
var owner_id: int # faction id of whoever placed it
var fuel_secs: float
var unlit_secs := 0.0
var _house: WeakRef = null
## House, for house fires. Weak: the house owns its fire, so a strong back-reference
## would be a RefCounted loop that never frees.
var house = null:
	get: return _house.get_ref() if _house else null
	set(v): _house = weakref(v) if v else null
var placed_by := -1 # agent id, for wild fires


func _init(c: Vector2i, house_fire: bool, owner: int) -> void:
	cell = c
	is_house = house_fire
	owner_id = owner
	fuel_secs = Cfg.FIRE_SECS_PER_WOOD # first wood comes with placement


func burning() -> bool:
	return fuel_secs > 0.0


func max_wood() -> int:
	return Cfg.HOUSE_FIRE_MAX_WOOD if is_house else Cfg.WILD_FIRE_MAX_WOOD


func wood_left() -> int:
	return int(ceil(fuel_secs / Cfg.FIRE_SECS_PER_WOOD))


## How many whole wood units can still be added.
func wood_space() -> int:
	return max_wood() - wood_left()


func add_wood(n: int) -> void:
	if n <= 0:
		return
	if fuel_secs <= 0.0 and is_house:
		World.zones_dirty = true # relit: zone comes back
	fuel_secs = min(fuel_secs + n * Cfg.FIRE_SECS_PER_WOOD, max_wood() * Cfg.FIRE_SECS_PER_WOOD)
	unlit_secs = 0.0
