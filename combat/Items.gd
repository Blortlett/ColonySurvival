class_name Items
## Item, recipe and weapon definitions.

const STACKABLES := ["wood", "stone", "hemp", "berry", "arrow", "plank", "handle", "cut_stone"]

# Recipes for crafted tools/weapons/ammo (agreed costs).
const RECIPES := {
	"axe": {"wood": 3, "stone": 2, "hemp": 1},
	"pickaxe": {"wood": 3, "stone": 2, "hemp": 1},
	"spear": {"wood": 3, "hemp": 1},
	"club": {"wood": 4, "stone": 1},
	"bow": {"wood": 4, "hemp": 3},
	"arrow": {"wood": 1, "stone": 1}, # yields ARROWS_PER_CRAFT
	"raiding_axe": {"plank": 2, "cut_stone": 2, "handle": 1}, # (agreed)
}
const WORKSHOP_RECIPES := ["raiding_axe"] # must be crafted at a workshop (agreed)
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
	# Workshop machines (starting values).
	"sawmill": {"wood": 6, "stone": 2},
	"cutter": {"wood": 4, "stone": 4},
}
const WALL_HP := [100.0, 250.0] # basic, reinforced (agreed)
const DOOR_HP := [80.0, 200.0] # basic, reinforced (agreed)
const FLOOR_HP := 50.0
const FURNITURE_HP := 60.0
const CHEST_SLOTS := [30, 60] # basic, reinforced (agreed)

const DURABILITY := {"axe": 100, "pickaxe": 100, "spear": 60, "club": 60, "bow": 80, "raiding_axe": 60}

# Workshop processing: machine, input per batch, output per batch, seconds per batch.
const PROCESS := {
	"plank": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 2}, "out": 1, "secs": 4.0},
	"handle": {"machine": Furniture.Kind.SAWMILL, "in": {"wood": 1}, "out": 2, "secs": 4.0},
	"cut_stone": {"machine": Furniture.Kind.CUTTER, "in": {"stone": 2}, "out": 1, "secs": 5.0}, # (agreed)
}

# Walls and doors take damage from melee weapons; the raiding axe does x5 (agreed).
const RAID_AXE_DAMAGE := 12.5 # x5 = 62.5: about 4 hits on a reinforced wall
const RAID_AXE_WALL_MULT := 5.0

# Weapons: damage, reach in cells (center distance), cooldown seconds.
const WEAPONS := {
	"unarmed": {"damage": 4.0, "reach": 1.5, "cooldown": 1.0},
	"spear": {"damage": 9.0, "reach": 2.5, "cooldown": 1.0},
	"club": {"damage": 14.0, "reach": 1.5, "cooldown": 1.2},
	"bow": {"damage": 10.0, "reach": 0.0, "cooldown": 1.5}, # reach from AGI
}

static func is_tool(item: String) -> bool:
	return DURABILITY.has(item)
