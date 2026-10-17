class_name Kingdom
extends RefCounted
## An alliance of up to 6 groups (agreed). Every group keeps its own houses; territory,
## workshops and a kingdom task board are shared.

static var _next_id := 1

var id: int
var name := ""
var groups: Array[int] = [] # faction ids
var leading_fid := -1 # group with the highest total AUTH (agreed)
var king_id := -1 # highest AUTH agent in the leading group (agreed)
var color: Color
var board := TaskBoard.new()
var founded := 0.0
# City grid (Phase E).
var has_city := false
var city_origin := Vector2i.ZERO # top-left cell of the centre plot
var plots := {} # Vector2i plot index -> {kind: "house"/"plaza"/"workshop", fid: int, house: House}
var plot_retry_at := 0.0 # after a failed plot search, wait before searching again


func _init(rng: RandomNumberGenerator) -> void:
	id = _next_id
	_next_id += 1
	color = Color.from_hsv(rng.randf(), rng.randf_range(0.7, 0.95), 1.0)
	name = Kingdoms.make_name(rng)
	founded = SimClock.time


func has_room() -> bool:
	return groups.size() < Cfg.KINGDOM_MAX_GROUPS


func members() -> Array[Faction]:
	var out: Array[Faction] = []
	for fid in groups:
		var f: Faction = World.factions.get(fid)
		if f:
			out.append(f)
	return out
