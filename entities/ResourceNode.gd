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
	match t:
		Type.TREE: amount = Cfg.TREE_CAPACITY
		Type.ROCK: amount = Cfg.ROCK_CAPACITY
		Type.HEMP: amount = Cfg.HEMP_CAPACITY
		Type.BUSH: amount = Cfg.BUSH_BERRIES
		Type.METAL: amount = Cfg.METAL_CAPACITY


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
