class_name Task
extends RefCounted
## One claimable job on a faction task board.

enum Type { PLACE_HOUSE_FIRE, BUILD_WALL, BUILD_DOOR, REFUEL }

const PRIORITY := {
	Type.PLACE_HOUSE_FIRE: 60,
	Type.BUILD_WALL: 50,
	Type.BUILD_DOOR: 50,
	Type.REFUEL: 100,
}
const CLAIM_TIMEOUT := 90.0

var type: Type
var cell: Vector2i
var house: House
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
	return p


func cost() -> Dictionary:
	match type:
		Type.PLACE_HOUSE_FIRE: return Items.BUILD_COSTS["house_fire"]
		Type.BUILD_WALL: return Items.BUILD_COSTS["wall"]
		Type.BUILD_DOOR: return Items.BUILD_COSTS["door"]
	return {"wood": 1}


func label() -> String:
	return Type.keys()[type]
