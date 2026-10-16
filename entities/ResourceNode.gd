class_name ResourceNode
extends RefCounted
## A tree, rock, hemp plant or berry bush occupying one cell.

enum Type { TREE, ROCK, HEMP, BUSH }

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


func item() -> String:
	match type:
		Type.TREE: return "wood"
		Type.ROCK: return "stone"
		Type.HEMP: return "hemp"
	return "berry"


static func type_for_item(item_name: String) -> int:
	match item_name:
		"wood": return Type.TREE
		"stone": return Type.ROCK
		"hemp": return Type.HEMP
		"berry": return Type.BUSH
	return -1
