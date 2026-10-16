class_name Wall
extends RefCounted
## A wall or door, basic (wood) or reinforced (planks). House doors open only for their
## owner group; workshop doors ("shared") open for the owner's whole kingdom.

var cell: Vector2i
var is_door: bool
var owner_id: int # faction id
var tier := 0
var shared := false # workshop door
var hp: float
var max_hp: float


func _init(c: Vector2i, door: bool, owner: int, t: int = 0) -> void:
	cell = c
	is_door = door
	owner_id = owner
	tier = t
	max_hp = Items.DOOR_HP[t] if door else Items.WALL_HP[t]
	hp = max_hp
