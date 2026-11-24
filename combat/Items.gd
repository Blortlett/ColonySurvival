class_name Items
## Item, recipe and weapon definitions.

const STACKABLES := ["wood", "stone", "hemp", "berry", "arrow", "plank", "handle", "cut_stone", "raw_iron", "iron_bar", "metal_door"]

# Recipes for crafted tools/weapons/ammo (agreed costs).
const RECIPES := {
	"axe": {"wood": 3, "stone": 2, "hemp": 1},
	"pickaxe": {"wood": 3, "stone": 2, "hemp": 1},
	"spear": {"wood": 3, "hemp": 1},
	"club": {"wood": 4, "stone": 1},
	"bow": {"wood": 4, "hemp": 3},
	"arrow": {"wood": 1, "stone": 1}, # yields ARROWS_PER_CRAFT
	"raiding_axe": {"plank": 2, "cut_stone": 2, "handle": 1}, # (agreed)
	"pickaxe_t2": {"plank": 1, "cut_stone": 2, "handle": 1}, # tier-2 pickaxe (v3, start)
	# Anvil (v3, agreed recipes): crafted only at a smeltery.
	"sword": {"iron_bar": 1, "handle": 1},
	"helmet": {"iron_bar": 1},
	"chest_armor": {"iron_bar": 1},
	"leg_armor": {"iron_bar": 1},
	"iron_raiding_axe": {"iron_bar": 2, "handle": 1},
	# Cloth (2026-11-24, start): weak peasant armour, hand-crafted from hemp anywhere.
	"tunic": {"hemp": 4},
	"trousers": {"hemp": 3},
	"hood": {"hemp": 2},
}
const WORKSHOP_RECIPES := ["raiding_axe", "pickaxe_t2"] # must be crafted at a workshop (agreed)
const ANVIL_RECIPES := ["sword", "helmet", "chest_armor", "leg_armor", "iron_raiding_axe"] # (agreed)
const ARMOR := ["helmet", "chest_armor", "leg_armor"] # the worn slots (Agent.worn keys), and the iron piece for each
## Cloth goes in the same worn slots as iron; iron replaces it (agreed 2026-11-24).
const CLOTH := ["tunic", "trousers", "hood"]
const WEAR_SLOT := {"tunic": "chest_armor", "trousers": "leg_armor", "hood": "helmet"}
const GEAR_SET := ["sword", "helmet", "chest_armor", "leg_armor"] # one spare set per smeltery's crates
const RAID_AXES := ["raiding_axe", "iron_raiding_axe"]
## Per worn piece (item type); they add up: -40% for an iron set (v3, start), -12% for cloth (start).
const ARMOR_REDUCTION := {"helmet": 0.10, "chest_armor": 0.20, "leg_armor": 0.10,
	"hood": 0.03, "tunic": 0.06, "trousers": 0.03}
const ARROWS_PER_CRAFT := 5

# Build costs (agreed).
const BUILD_COSTS := {
	"wall": {"wood": 2},
	"door": {"wood": 3, "hemp": 1},
	"wild_fire": {"wood": 2},
	"house_fire": {"wood": 5, "stone": 3},
	"base_fire": {"wood": 5, "stone": 3}, # the player's house_fire: founds their group's base
	"floor": {"wood": 1}, # per tile (agreed)
	"chest": {"wood": 5}, # (agreed)
	# Reinforced pieces (agreed concept, Phase C).
	"wall_r": {"plank": 2},
	"door_r": {"plank": 2, "handle": 1},
	"chest_r": {"plank": 4, "handle": 1},
	# City (Phase E).
	"road": {"stone": 1}, # 1.3x speed (agreed)
	"road_r": {"cut_stone": 1}, # paved, 1.5x speed (agreed)
	"board": {"wood": 4}, # kingdom board (agreed)
	"mailbox": {"wood": 2}, # outside every building's door (Player Group Base Plan D10, start)
	# Workshop machines (starting values).
	"sawmill": {"wood": 6, "stone": 2},
	"cutter": {"wood": 4, "stone": 4},
	# Stone tier (v3, agreed pieces, start numbers).
	"wall_s": {"cut_stone": 2}, # stone wall; smeltery walls are always stone (agreed)
	"door_m": {"metal_door": 1}, # metal door, made at the anvil from 2 iron bars (agreed)
	"chest_i": {"iron_bar": 2, "plank": 2}, # iron-bound chest
	# Smeltery machines and crates (v3, start).
	"furnace": {"cut_stone": 4, "stone": 4},
	"anvil": {"raw_iron": 4, "wood": 2},
	"crate": {"plank": 4, "handle": 1},
}
const WALL_HP := [100.0, 250.0, 400.0] # basic, reinforced (agreed), stone (v3, start)
const DOOR_HP := [80.0, 200.0, 500.0] # basic, reinforced (agreed), metal (v3, start)
const FLOOR_HP := 50.0
const FURNITURE_HP := 60.0
const CHEST_SLOTS := [12, 24, 36] # slots (6 wide): basic, reinforced, iron-bound. Were item counts 30 / 60 / 90 before slots (start)
const CRATE_SLOTS := 24 # slots: smeltery storage crate. Was 60 items before slots (start)
const UPGRADE_COSTS := {
	"wall": ["wall", "wall_r", "wall_s"],
	"door": ["door", "door_r", "door_m"],
	"chest": ["chest", "chest_r", "chest_i"],
}

const DURABILITY := {"axe": 100, "pickaxe": 100, "spear": 60, "club": 60, "bow": 80, "raiding_axe": 60, "pickaxe_t2": 150,
	"sword": 150, "helmet": 100, "chest_armor": 100, "leg_armor": 100, "iron_raiding_axe": 80, # v3 (start)
	"tunic": 40, "trousers": 40, "hood": 40} # cloth (start)

# Workshop processing: machine, input per batch, output per batch, seconds per batch.
const PROCESS := {
	"plank": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 2}, "out": 1, "secs": 4.0},
	"handle": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 1}, "out": 2, "secs": 4.0},
	"cut_stone": {"machine": Furniture.Kind.CUTTER, "in": {"stone": 2}, "out": 1, "secs": 5.0}, # (agreed)
	"iron_bar": {"machine": Furniture.Kind.FURNACE, "in": {"raw_iron": 1, "wood": 1}, "out": 1, "secs": 8.0}, # (agreed, time start)
	"metal_door": {"machine": Furniture.Kind.ANVIL, "in": {"iron_bar": 2}, "out": 1, "secs": 6.0}, # (agreed, time start)
}

# Walls and doors take damage from melee weapons; the raiding axe does x5 (agreed).
const RAID_AXE_DAMAGE := 12.5 # x5 = 62.5: about 4 hits on a reinforced wall
const RAID_AXE_WALL_MULT := 5.0
const IRON_RAID_AXE_DAMAGE := 25.0 # x5 = 125: about 4 hits on a metal door (v3, start)

const ROAD_SPEED := [1.0, 1.3, 1.5] # none, stone, paved (agreed)

# Weapons: damage, reach in cells (center distance), cooldown seconds.
const WEAPONS := {
	"unarmed": {"damage": 4.0, "reach": 1.5, "cooldown": 1.0},
	"spear": {"damage": 9.0, "reach": 2.5, "cooldown": 1.0},
	"club": {"damage": 14.0, "reach": 1.5, "cooldown": 1.2},
	"sword": {"damage": 20.0, "reach": 1.5, "cooldown": 1.0}, # v3 (start)
	"bow": {"damage": 10.0, "reach": 0.0, "cooldown": 1.5}, # reach from AGI
}

static func is_tool(item: String) -> bool:
	return DURABILITY.has(item)


## The worn slot (an ARMOR entry) an item goes in, or "" if it isn't worn.
static func wear_slot(item: String) -> String:
	if item in ARMOR:
		return item
	return WEAR_SLOT.get(item, "")


## Iron (1) beats cloth (0) in the same slot.
static func armor_tier(item: String) -> int:
	return 0 if item in CLOTH else 1


## Highest door / chest tier the economy can make yet (metal needs the anvil's recipes).
static func max_door_tier() -> int:
	return 2 if PROCESS.has("metal_door") else 1


static func max_chest_tier() -> int:
	return 2 if PROCESS.has("iron_bar") else 1


const LABELS := {"pickaxe_t2": "tier-2 pickaxe", "chest_armor": "chest piece", "leg_armor": "leg armour"}


static func label(item: String) -> String:
	return LABELS.get(item, item.replace("_", " "))
