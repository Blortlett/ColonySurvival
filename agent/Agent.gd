class_name Agent
extends RefCounted
## One autonomous agent: stats, needs, mood, memory, inventory and current job.

const STATS := ["str", "agi", "cha", "auth"]

var id: int
var pos: Vector2 # in cell units; cell centre is cell + 0.5
var alive := true

var stats := {"str": 5, "agi": 5, "cha": 5, "auth": 5}
var xp := {"str": 0.0, "agi": 0.0, "cha": 0.0}

var hp := Cfg.MAX_HP
var hunger := 1.0 # 1 = full
var warmth := 1.0 # 1 = warm
var mood := 0.0 # -100..100

var faction: Faction
var master_id := -1
var servants: Array[int] = []
var opinions := {} # agent id -> -100..100 (pairwise memory)
var cooldowns := {} # agent id -> sim time when interaction is allowed again
var death_match := {} # agent ids we're fighting to the death with
var pleaded := {} # attacker ids we've already pleaded to

var inv := Inventory.new()
var worn := {} # armour slot (helmet / chest_armor / leg_armor) -> {type, dur}; takes no inventory slots (v3)
var job: Job = null
var path: Array[Vector2i] = []
var path_i := 0
var think_t := 0.0
var last_think := -1.0 # sim time of the last think (B3: intervals vary by job)
var social_t := 0.0 # social scans keep the base 0.25 s between slower thinks (B3)
var attack_cd := 0.0
var last_attacker := -1
var rebel_t := 0.0
var meet_t := 0.0 # next group-level meeting check
var raid_id := -1 # raid this agent is part of
var defend_raid := -1 # raid this agent is defending against
var kills := 0


func cell() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


# --- Mood ---

func mood_label() -> String:
	if mood > Cfg.MOOD_HAPPY:
		return "happy"
	if mood < Cfg.MOOD_ANGRY:
		return "angry"
	return "neutral"


func is_happy() -> bool:
	return mood > Cfg.MOOD_HAPPY


func is_angry() -> bool:
	return mood < Cfg.MOOD_ANGRY


func is_neutral() -> bool:
	return not is_happy() and not is_angry()


func change_mood(d: float) -> void:
	mood = clamp(mood + d, -100.0, 100.0)


# --- Stats ---

func gather_mult() -> float:
	return 1.0 + (stats.str - 5) * 0.05


func melee_mult() -> float:
	return 1.0 + (stats.str - 5) * 0.06


func capacity() -> int:
	return 20 + stats.str * 2


func free_space() -> int:
	return max(0, capacity() - inv.total())


func speed() -> float:
	return 3.0 * (1.0 + (stats.agi - 5) * 0.04) * Items.ROAD_SPEED[World.roads.get(cell(), 0)]


func bow_mult() -> float:
	return 1.0 + (stats.agi - 5) * 0.06


func bow_range() -> float:
	return 6.0 + stats.agi * 0.3


func bow_hit_chance() -> float:
	return clamp(0.5 + stats.agi * 0.02, 0.0, 0.95)


static func xp_to_next(level: int) -> float:
	var x := 10.0 * pow(level, 1.5)
	if level >= Cfg.STAT_SOFT_CAP:
		x *= Cfg.XP_SOFT_CAP_MULT
	return x


func add_xp(stat: String, amount: float) -> void:
	xp[stat] += amount
	while xp[stat] >= xp_to_next(stats[stat]):
		xp[stat] -= xp_to_next(stats[stat])
		stats[stat] += 1


func gain_authority() -> void:
	stats.auth += 1 # agreed: +1 per kill or accepted surrender, nothing else


# --- Combat helpers ---

func melee_weapon() -> String:
	if inv.has_tool("sword"):
		return "sword" # preferred when owned (v3)
	if inv.has_tool("club"):
		return "club"
	if inv.has_tool("spear"):
		return "spear"
	return "unarmed"


func has_bow_ready() -> bool:
	return inv.has_tool("bow") and inv.count("arrow") > 0


func best_damage() -> float:
	var d: float = Items.WEAPONS[melee_weapon()].damage * melee_mult()
	if has_bow_ready():
		d = max(d, Items.WEAPONS["bow"].damage * bow_mult() * bow_hit_chance())
	return d


## Rough fighting strength used for comply / flee / fight decisions.
func power() -> float:
	var allies := 0
	for other in World.agents_near(pos, Cfg.DEFEND_RADIUS):
		if other != self and other.faction == faction and not faction.solo:
			allies += 1
	return fight_power() * (1.0 + allies * 0.5)


## Strength on its own, without nearby allies (group and kingdom strength checks).
## Includes gear (agreed): the sword's damage and the armour's damage reduction.
func fight_power() -> float:
	return (hp / Cfg.MAX_HP) * best_damage() / (1.0 - armor_reduction())


## Damage taken is cut by this fraction (worn pieces add up).
func armor_reduction() -> float:
	var r := 0.0
	for slot in worn:
		r += Items.ARMOR_REDUCTION[slot]
	return r


func is_armoured() -> bool:
	return not worn.is_empty()


## Put on any armour carried for an empty slot (agents equip the best they own; agreed).
func auto_equip() -> void:
	for t in inv.tools.duplicate():
		if t.type in Items.ARMOR and not worn.has(t.type):
			inv.tools.erase(t)
			worn[t.type] = t


## Every hit taken costs each worn piece 1 durability; a piece at 0 breaks (agreed).
func wear_armor() -> void:
	for slot in worn.keys():
		worn[slot].dur -= 1
		if worn[slot].dur <= 0:
			worn.erase(slot)
			EventBus.log_event("%s's %s broke." % [short(), Items.label(slot)])


# --- Social memory ---

func opinion_of(other_id: int) -> float:
	return opinions.get(other_id, 0.0)


func change_opinion(other_id: int, d: float) -> void:
	opinions[other_id] = clamp(opinion_of(other_id) + d, -100.0, 100.0)


func can_interact(other_id: int) -> bool:
	return SimClock.time >= cooldowns.get(other_id, 0.0)


func set_cooldown(other_id: int, secs: float = Cfg.PAIR_COOLDOWN) -> void:
	cooldowns[other_id] = SimClock.time + secs


func is_servant() -> bool:
	return master_id != -1


func in_combat() -> bool:
	return job != null and (job.kind == Job.Kind.FIGHT or job.kind == Job.Kind.FLEE) and job.prio >= Job.PRIO_CRITICAL


func home() -> House:
	return faction.house_of(id)


func short() -> String:
	return "#%d" % id
