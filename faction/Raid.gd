class_name Raid
extends RefCounted
## One raid: a group's party rallies, marches on a target house, breaches the door or the
## weakest wall and pushes inside (Phase F).

enum Phase { RALLY, MARCH, ASSAULT }

static var _next_id := 1

var id: int
var attacker: Faction
var target: House
var target_fid: int
var party: Array[int] = []
var keeper_id := -1
var phase := Phase.RALLY
var started := 0.0
var phase_since := 0.0
var rally := Vector2i.ZERO
var size0 := 0
var alerted := false
var breach := Vector2i(-1, -1)
# Kingdom-wide raids (Kingdom Wars Plan §1.6): the whole kingdom's party, moving from target
# to target; what each raider took, to carry home to the capital's chest.
var kingdom: Kingdom = null
var loot := {} # agent id -> {item: count}
var sacked := 0


func _init(f: Faction, h: House) -> void:
	id = _next_id
	_next_id += 1
	attacker = f
	target = h
	target_fid = h.faction_id
	started = SimClock.time
	phase_since = started


func target_faction() -> Faction:
	return World.factions.get(target_fid)


func label() -> String:
	return kingdom.name if kingdom else attacker.name


func phase_name() -> String:
	return Phase.keys()[phase].to_lower()
