class_name Wall
extends RefCounted
## A wood wall or door. Doors open only for their owner faction.

var cell: Vector2i
var is_door: bool
var owner_id: int # faction id
var hp: float
var max_hp: float


func _init(c: Vector2i, door: bool, owner: int) -> void:
	cell = c
	is_door = door
	owner_id = owner
	max_hp = Items.DOOR_HP if door else Items.WALL_HP
	hp = max_hp
