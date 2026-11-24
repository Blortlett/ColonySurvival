class_name Names
## Random first and last names for agents, from res://data/first_names.txt and
## res://data/last_names.txt (one name per line; lines starting with # are ignored).
##
## Names use their own random generator, seeded from the world seed, so the same seed
## gives the same names while the sim's own rolls (World.rng) are untouched: --bench
## numbers don't change because of names. If a list is missing or empty, agents keep
## their "#id" (Agent.short()).

const FIRST_PATH := "res://data/first_names.txt"
const LAST_PATH := "res://data/last_names.txt"
const TRIES := 12 # re-rolls to avoid a full name a living agent already has

static var rng := RandomNumberGenerator.new()
static var _first: PackedStringArray = []
static var _last: PackedStringArray = []
static var _loaded := false


## World.setup: same seed, same names.
static func reset(seed: int) -> void:
	rng.seed = hash("names:%d" % seed)
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_first = _read(FIRST_PATH)
	_last = _read(LAST_PATH)
	if _first.is_empty() or _last.is_empty():
		push_warning("Names: %s or %s is missing or empty; agents keep their #id." % [FIRST_PATH, LAST_PATH])


static func _read(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "" and not line.begins_with("#"):
			out.append(line)
	return out


## Gives `a` a first and last name no living agent has (after a few tries, any name).
static func assign(a: Agent) -> void:
	_load()
	if _first.is_empty() or _last.is_empty():
		return
	for i in TRIES:
		a.first_name = _first[rng.randi() % _first.size()]
		a.last_name = _last[rng.randi() % _last.size()]
		if not _taken(a):
			return


static func _taken(a: Agent) -> bool:
	var full := a.short()
	for o in World.agent_list:
		if o != a and o.alive and o.short() == full:
			return true
	return false
