class_name Job
extends RefCounted
## What an agent is currently doing. Executed every sim step by Brain.

enum Kind { WANDER, GATHER, WARM, PLACE_WILD_FIRE, TASK, FIGHT, FLEE, LOOT, DELIVER, FOLLOW, IDLE, CHEST }

# Priority layers (agreed decision order). Higher interrupts lower.
const PRIO_IDLE := 0
const PRIO_LADDER := 10
const PRIO_TASK := 20
const PRIO_ORDER := 30
const PRIO_NEEDS := 50
const PRIO_CRITICAL := 100

var kind: Kind
var prio := PRIO_LADDER
var cell := Vector2i.ZERO # destination / target cell
var target_id := -1 # agent target
var item := "" # gather item
var amount := 0 # gather until inventory has this many of item
var timer := 0.0
var task: Task = null
var fire: Campfire = null
var node: ResourceNode = null
var flee_from := Vector2.ZERO
var to_death := false
var arrived := false
var phase := 0
var repath_t := 0.0
var then_craft := "" # craft this after gathering
var chest: Furniture = null # CHEST job, or a task fetching materials from a chest
var transfer := {} # Stock transfer plan


func _init(k: Kind, p: int = PRIO_LADDER) -> void:
	kind = k
	prio = p


func label() -> String:
	var s: String = Kind.keys()[kind]
	match kind:
		Kind.GATHER: s += " " + item
		Kind.TASK: s += " " + (task.label() if task else "?")
		Kind.CHEST: s += " " + ("deposit" if transfer.values().any(func(v): return v > 0) else "take")
		Kind.FIGHT, Kind.FOLLOW, Kind.DELIVER: s += " #%d" % target_id
	if to_death:
		s += " (to the death)"
	return s
