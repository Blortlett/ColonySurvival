class_name Task
extends RefCounted
## One claimable job on a faction task board.

enum Type { PLACE_HOUSE_FIRE, BUILD_WALL, BUILD_DOOR, REFUEL, BUILD_FLOOR, PLACE_CHEST, PLACE_MACHINE, UPGRADE_WALL, UPGRADE_DOOR, UPGRADE_CHEST, CLEAR_NODE, BUILD_ROAD, UPGRADE_ROAD, PLACE_BOARD, DEMOLISH, PLACE_MAILBOX }

const PRIORITY := {
	Type.PLACE_HOUSE_FIRE: 60,
	Type.BUILD_WALL: 50,
	Type.BUILD_DOOR: 50,
	Type.REFUEL: 100,
	Type.BUILD_FLOOR: 45,
	Type.PLACE_CHEST: 40,
	Type.PLACE_MACHINE: 40, # workshop / smeltery machines and crates
	Type.UPGRADE_WALL: 30,
	Type.UPGRADE_DOOR: 31, # door before walls
	Type.UPGRADE_CHEST: 32,
	Type.CLEAR_NODE: 55, # trees and rocks must go before anything is built there (agreed)
	Type.PLACE_BOARD: 35,
	Type.BUILD_ROAD: 25,
	Type.UPGRADE_ROAD: 15,
	Type.DEMOLISH: 52, # walls first (+2), so floors and chests inside can be reached
	Type.PLACE_MAILBOX: 38, # after the chest and machines
}
const CLAIM_TIMEOUT := 90.0

var _board: WeakRef = null
## The board it was posted on (group or kingdom). Weak: the board holds its tasks.
var board: TaskBoard:
	get: return _board.get_ref() if _board else null
	set(v): _board = weakref(v) if v else null
var type: Type
var cell: Vector2i
var house: House
var tier := 1 # upgrade tasks: the tier the piece becomes
var claimed_by := -1
var claim_time := 0.0
var done := false


func _init(t: Type, c: Vector2i, h: House) -> void:
	type = t
	cell = c
	house = h


func priority() -> int:
	var p: int = PRIORITY[type]
	# An almost-empty fire is an emergency.
	if type == Type.REFUEL and house and house.fire and house.fire.fuel_secs < Cfg.FIRE_SECS_PER_WOOD:
		p += 50
	if type == Type.DEMOLISH and World.walls.has(cell):
		p += 2
	return p


func cost() -> Dictionary:
	match type:
		Type.PLACE_HOUSE_FIRE: return Items.BUILD_COSTS["house_fire"]
		Type.BUILD_WALL: return Items.BUILD_COSTS["wall_s" if house and house.is_smeltery() else "wall"]
		Type.BUILD_DOOR: return Items.BUILD_COSTS["door"]
		Type.BUILD_FLOOR: return Items.BUILD_COSTS["floor"]
		Type.PLACE_CHEST: return Items.BUILD_COSTS["chest"]
		Type.PLACE_MACHINE: return Items.BUILD_COSTS[Furniture.cost_key(house.furniture_kind_at(cell))] if house else {}
		Type.UPGRADE_WALL: return Items.BUILD_COSTS[Items.UPGRADE_COSTS["wall"][tier]]
		Type.UPGRADE_DOOR: return Items.BUILD_COSTS[Items.UPGRADE_COSTS["door"][tier]]
		Type.UPGRADE_CHEST: return Items.BUILD_COSTS[Items.UPGRADE_COSTS["chest"][tier]]
		Type.CLEAR_NODE, Type.DEMOLISH: return {}
		Type.BUILD_ROAD: return Items.BUILD_COSTS["road"]
		Type.UPGRADE_ROAD: return Items.BUILD_COSTS["road_r"]
		Type.PLACE_BOARD: return Items.BUILD_COSTS["board"]
		Type.PLACE_MAILBOX: return Items.BUILD_COSTS["mailbox"]
	return {"wood": 1}


## Something still has to be cleared off the cell first.
func blocked() -> bool:
	if type == Type.PLACE_MAILBOX:
		return house != null and house.mailbox_site() == World.NO_CELL # else it uses the free side
	return type != Type.CLEAR_NODE and type != Type.REFUEL and World.nodes.has(cell)


func label() -> String:
	var s: String = Type.keys()[type]
	if type in [Type.UPGRADE_WALL, Type.UPGRADE_DOOR, Type.UPGRADE_CHEST] and tier > 1:
		s += "_T%d" % tier
	return s
