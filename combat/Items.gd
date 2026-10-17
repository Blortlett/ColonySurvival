class_name Items
## Item, recipe and weapon definitions.

const STACKABLES := ["wood", "stone", "hemp", "berry", "arrow", "plank", "handle", "cut_stone", "raw_iron"]

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
}
const WORKSHOP_RECIPES := ["raiding_axe", "pickaxe_t2"] # must be crafted at a workshop (agreed)
const ANVIL_RECIPES := [] # gear crafted at a smeltery's anvil (Phase 4)
const ARROWS_PER_CRAFT := 5

# Build costs (agreed).
const BUILD_COSTS := {
	"wall": {"wood": 2},
	"door": {"wood": 3, "hemp": 1},
	"wild_fire": {"wood": 2},
	"house_fire": {"wood": 5, "stone": 3},
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
const CHEST_SLOTS := [30, 60, 90] # basic, reinforced (agreed), iron-bound (v3, start)
const CRATE_SLOTS := 60 # smeltery storage crate (v3, start)
const UPGRADE_COSTS := {
	"wall": ["wall", "wall_r", "wall_s"],
	"door": ["door", "door_r", "door_m"],
	"chest": ["chest", "chest_r", "chest_i"],
}

const DURABILITY := {"axe": 100, "pickaxe": 100, "spear": 60, "club": 60, "bow": 80, "raiding_axe": 60, "pickaxe_t2": 150}

# Workshop processing: machine, input per batch, output per batch, seconds per batch.
const PROCESS := {
	"plank": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 2}, "out": 1, "secs": 4.0},
	"handle": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 1}, "out": 2, "secs": 4.0},
	"cut_stone": {"machine": Furniture.Kind.CUTTER, "in": {"stone": 2}, "out": 1, "secs": 5.0}, # (agreed)
}

# Walls and doors take damage from melee weapons; the raiding axe does x5 (agreed).
const RAID_AXE_DAMAGE := 12.5 # x5 = 62.5: about 4 hits on a reinforced wall
const RAID_AXE_WALL_MULT := 5.0

const ROAD_SPEED := [1.0, 1.3, 1.5] # none, stone, paved (agreed)

# Weapons: damage, reach in cells (center distance), cooldown seconds.
const WEAPONS := {
	"unarmed": {"damage": 4.0, "reach": 1.5, "cooldown": 1.0},
	"spear": {"damage": 9.0, "reach": 2.5, "cooldown": 1.0},
	"club": {"damage": 14.0, "reach": 1.5, "cooldown": 1.2},
	"bow": {"damage": 10.0, "reach": 0.0, "cooldown": 1.5}, # reach from AGI
}

static func is_tool(item: String) -> bool:
	return DURABILITY.has(item)


## Highest door / chest tier the economy can make yet (metal needs the anvil's recipes).
static func max_door_tier() -> int:
	return 2 if PROCESS.has("metal_door") else 1


static func max_chest_tier() -> int:
	return 2 if PROCESS.has("iron_bar") else 1


static func label(item: String) -> String:
	return "tier-2 pickaxe" if item == "pickaxe_t2" else item.replace("_", " ")
