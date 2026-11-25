class_name Agent
extends RefCounted
## One autonomous agent: stats, needs, mood, memory, inventory and current job.

const STATS := ["str", "agi", "cha", "auth"]

var id: int
var first_name := "" # from core/Names.gd; "" until named (then short() is "#id")
var last_name := ""
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
var action_cooldowns := {} # the player's own actions: agent id -> sim time (R1)
var death_match := {} # agent ids we're fighting to the death with
var pleaded := {} # attacker ids we've already pleaded to

var inv := Inventory.new(Cfg.AGENT_SLOTS)
## Hotbar slot the body holds (0-5), set by the player's controller. -1: the AI, which
## always fights with its best weapon.
var held := -1
var worn := {} # armour slot (helmet / chest_armor / leg_armor) -> {type, dur}; takes no inventory slots (v3). Cloth (hood / tunic / trousers) uses the same slots (Items.WEAR_SLOT)
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
var facing := Vector2.RIGHT # aim / swing direction (torso); NPCs turn to face their target
var move_dir := Vector2.RIGHT # last direction of travel (legs)
var last_swing := -1.0 # sim time of the last melee swing (renderers flash the arc)
## Who drives this body: null = the AI (Brain); otherwise an object with
## control(a: Agent, dt: float), e.g. the PlayerController (Player Controller Plan §1).
var controller: Object = null


func cell() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))


func is_player() -> bool:
	return controller != null


## Needs drain, starving or freezing hurts, being fed and warm heals. Runs for every body,
## whoever controls it.
func tick_needs(dt: float) -> void:
	warmth = max(0.0, warmth - dt / Cfg.WARMTH_DRAIN_SECS)
	hunger = max(0.0, hunger - dt / Cfg.HUNGER_DRAIN_SECS)
	var empty := int(warmth <= 0.0) + int(hunger <= 0.0)
	if empty > 0:
		hp -= Cfg.HP_DRAIN_PER_NEED * empty * dt
		if hp <= 0.0:
			World.kill_agent(self, null)
	elif warmth > 0.5 and hunger > 0.5:
		hp = min(Cfg.MAX_HP, hp + Cfg.HP_REGEN * dt)


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


## Slots (the slot inventory replaced the old 20 + STR x 2 item count).
func capacity() -> int:
	return inv.cap()


## How many of `item` still fit; without an item, the room for a fresh 20-stack per free slot.
func free_space(item := "") -> int:
	return inv.free_units() if item == "" else inv.room_for(item)


func speed() -> float:
	return 3.0 * (1.0 + (stats.agi - 5) * 0.04) * Items.ROAD_SPEED[World.roads.get(World.wc(cell()), 0)]


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
	if held >= 0:
		var e = inv.entry(held) # the player fights with what is in hand
		if Inventory.is_tool_entry(e) and Items.WEAPONS.has(e.type) and e.type != "bow":
			return e.type
		return "unarmed"
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
		r += Items.ARMOR_REDUCTION[worn[slot].type]
	return r


func is_armoured() -> bool:
	return not worn.is_empty()


## Put on any armour carried for an empty slot (agents equip the best they own; agreed).
## Iron replaces cloth in its slot; the cloth goes back into the pack where the iron was.
func auto_equip() -> void:
	for t in inv.tools.duplicate():
		var slot := Items.wear_slot(t.type)
		if slot == "":
			continue
		var old = worn.get(slot)
		if old == null:
			inv.take_tool(t)
			worn[slot] = t
		elif Items.armor_tier(t.type) > Items.armor_tier(old.type):
			var i := inv.slot_of(t)
			inv.take_slot(i)
			inv.put_slot(i, old)
			worn[slot] = t


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


## Player-started social actions have their own cooldown layer (Player Group Base Plan R1):
## NPCs meeting the player never use it up; only the player's own actions do.
func can_act_on(other_id: int) -> bool:
	return SimClock.time >= action_cooldowns.get(other_id, 0.0)


func set_action_cooldown(other_id: int, secs: float = Cfg.PAIR_COOLDOWN) -> void:
	action_cooldowns[other_id] = SimClock.time + secs


func is_servant() -> bool:
	return master_id != -1


func in_combat() -> bool:
	return job != null and (job.kind == Job.Kind.FIGHT or job.kind == Job.Kind.FLEE) and job.prio >= Job.PRIO_CRITICAL


func home() -> House:
	return faction.house_of(id)


## The agent's name as every log, feed line and UI label shows it: "Bram Holt", or "#12" if
## it has none (no name lists).
func short() -> String:
	if first_name == "":
		return "#%d" % id
	return "%s %s" % [first_name, last_name]
