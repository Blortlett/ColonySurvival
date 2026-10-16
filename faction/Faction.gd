class_name Faction
extends RefCounted
## Every agent always belongs to a Faction. A "solo" faction is an unfactioned
## agent on its own (with its own board and house). Real factions cap at 8 incl. servants.

static var _next_id := 1

var id: int
var solo := true
var name := ""
var members: Array[int] = []
var leader_id := -1
var color: Color
var board := TaskBoard.new()
var houses: Array[House] = []
var plan_retry_at := 0.0


func _init(rng: RandomNumberGenerator) -> void:
	id = _next_id
	_next_id += 1
	color = Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 1.0))
	name = "F%d" % id


func has_room() -> bool:
	return members.size() < Cfg.FACTION_MAX


func housed_capacity() -> int:
	var n := 0
	for h in houses:
		n += h.capacity
	return n


func house_of(agent_id: int) -> House:
	for h in houses:
		if agent_id in h.occupants:
			return h
	return null


## A gang: a real group whose leader is angry (agreed).
func is_gang() -> bool:
	if solo:
		return false
	var l: Agent = World.agents.get(leader_id)
	return l != null and l.is_angry()


func homes() -> Array[House]:
	var out: Array[House] = []
	out.assign(houses.filter(func(h): return not h.is_workshop()))
	return out


func workshops() -> Array[House]:
	var out: Array[House] = []
	out.assign(houses.filter(func(h): return h.is_workshop()))
	return out


func display_name() -> String:
	return "solo" if solo else name
