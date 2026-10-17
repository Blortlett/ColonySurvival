class_name Furniture
extends RefCounted
## A piece of furniture on a floor tile: a chest (with storage) or a workshop machine.
## Walkable (agents stand on or next to it). Decays like walls when unprotected.

enum Kind { CHEST, SAWMILL, CUTTER, BOARD }

var cell: Vector2i
var kind: Kind
var tier := 0 # 0 basic, 1 reinforced
var owner_id: int # faction id
var _house: WeakRef = null
## House (or workshop) it belongs to. Weak, to avoid a House <-> chest reference loop.
var house = null:
	get: return _house.get_ref() if _house else null
	set(v): _house = weakref(v) if v else null
var store := Inventory.new() # chest contents
var hp: float
var max_hp: float


func _init(c: Vector2i, k: Kind, owner: int, t: int = 0) -> void:
	cell = c
	kind = k
	owner_id = owner
	tier = t
	max_hp = Items.FURNITURE_HP * (2.5 if t > 0 else 1.0)
	hp = max_hp


func slots() -> int:
	if kind != Kind.CHEST:
		return 0
	return Items.CHEST_SLOTS[tier]


func free_slots() -> int:
	return max(0, slots() - store.total())


func label() -> String:
	match kind:
		Kind.CHEST: return "reinforced chest" if tier > 0 else "basic chest"
		Kind.SAWMILL: return "sawmill"
		Kind.CUTTER: return "stone cutter"
		Kind.BOARD: return "kingdom board"
	return "furniture"
