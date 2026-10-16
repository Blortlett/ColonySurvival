class_name Items
## Item, recipe and weapon definitions.

const STACKABLES := ["wood", "stone", "hemp", "berry", "arrow"]

# Recipes for crafted tools/weapons/ammo (agreed costs).
const RECIPES := {
	"axe": {"wood": 3, "stone": 2, "hemp": 1},
	"pickaxe": {"wood": 3, "stone": 2, "hemp": 1},
	"spear": {"wood": 3, "hemp": 1},
	"club": {"wood": 4, "stone": 1},
	"bow": {"wood": 4, "hemp": 3},
	"arrow": {"wood": 1, "stone": 1}, # yields ARROWS_PER_CRAFT
}
const ARROWS_PER_CRAFT := 5

# Build costs (agreed).
const BUILD_COSTS := {
	"wall": {"wood": 2},
	"door": {"wood": 3, "hemp": 1},
	"wild_fire": {"wood": 2},
	"house_fire": {"wood": 5, "stone": 3},
}
const WALL_HP := 100.0
const DOOR_HP := 80.0

const DURABILITY := {"axe": 100, "pickaxe": 100, "spear": 60, "club": 60, "bow": 80}

# Weapons: damage, reach in cells (center distance), cooldown seconds.
const WEAPONS := {
	"unarmed": {"damage": 4.0, "reach": 1.5, "cooldown": 1.0},
	"spear": {"damage": 9.0, "reach": 2.5, "cooldown": 1.0},
	"club": {"damage": 14.0, "reach": 1.5, "cooldown": 1.2},
	"bow": {"damage": 10.0, "reach": 0.0, "cooldown": 1.5}, # reach from AGI
}

static func is_tool(item: String) -> bool:
	return DURABILITY.has(item)
