class_name Floor
extends RefCounted
## A wood floor tile inside a building. Walkable; decays like walls when unprotected.

var cell: Vector2i
var owner_id: int # faction id
var hp: float
var max_hp: float


func _init(c: Vector2i, owner: int) -> void:
	cell = c
	owner_id = owner
	max_hp = Items.FLOOR_HP
	hp = max_hp
