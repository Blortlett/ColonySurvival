class_name ResourceNode
extends RefCounted
## A tree, rock, hemp plant, berry bush or metal rock occupying one cell.

enum Type { TREE, ROCK, HEMP, BUSH, METAL }

var type: Type
var cell: Vector2i
var amount: int
var regrow_timer := 0.0


func _init(t: Type, c: Vector2i) -> void:
	type = t
	cell = c
	amount = capacity()


## Full amount for this type (what a fresh node starts with).
func capacity() -> int:
	match type:
		Type.TREE: return Cfg.TREE_CAPACITY
		Type.ROCK: return Cfg.ROCK_CAPACITY
		Type.HEMP: return Cfg.HEMP_CAPACITY
		Type.METAL: return Cfg.METAL_CAPACITY
	return Cfg.BUSH_BERRIES


## Depletion art stage, 4 (full) down to 1 (nearly spent): stone and iron shrink as mined.
func stage() -> int:
	return clampi(ceili(4.0 * amount / capacity()), 1, 4)


## Agents walk through it (Player Group Base Plan R7). It still blocks building.
func walk_through() -> bool:
	return type == Type.HEMP


func item() -> String:
	match type:
		Type.TREE: return "wood"
		Type.ROCK: return "stone"
		Type.HEMP: return "hemp"
		Type.METAL: return "raw_iron"
	return "berry"


static func type_for_item(item_name: String) -> int:
	match item_name:
		"wood": return Type.TREE
		"stone": return Type.ROCK
		"hemp": return Type.HEMP
		"berry": return Type.BUSH
		"raw_iron": return Type.METAL
	return -1
