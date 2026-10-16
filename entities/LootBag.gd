class_name LootBag
extends RefCounted
## Dropped inventory. Anyone can pick it up; despawns after a while.

var cell: Vector2i
var stacks := {} # item -> count
var tools: Array = [] # [{type, dur}]
var timer := Cfg.LOOT_DESPAWN
var dropper_id := -1 # agent whose stuff this was
var reason := "" # "killed by #X" / "died of cold" / "died of hunger" / "dumped junk"


func _init(c: Vector2i) -> void:
	cell = c


func is_empty() -> bool:
	return stacks.is_empty() and tools.is_empty()
