class_name Cfg
## All sim tunables live here. See Docs/Anarchy_Colony_Sim_Plan.md.
## "(agreed)" values were decided in design; the rest are starting values for tuning.

# --- World ---
const MAP_W := 200
const MAP_H := 200
const CELL := 16
const START_AGENTS := 120
const SEED := 12345 # set to 0 for a random seed each run

const DENSITY_TREE := 0.06
const DENSITY_ROCK := 0.03
const DENSITY_HEMP := 0.015
const DENSITY_BUSH := 0.01
const DENSITY_METAL := 0.005 # about 1/6 of rock density (v3, start)
const METAL_MIN_GAP := 6 # metal rock is dispersed, never clustered (agreed)

const TREE_CAPACITY := 20
const ROCK_CAPACITY := 20
const HEMP_CAPACITY := 3
const BUSH_BERRIES := 5
const METAL_CAPACITY := 15 # raw iron per node (v3, start)
const BUSH_REGROW_SECS := 60.0
const NODE_RESPAWN_MIN := 180.0
const NODE_RESPAWN_MAX := 360.0

# --- Gathering (seconds per unit) ---
const GATHER_WOOD := 4.0
const GATHER_STONE := 5.0
const GATHER_HEMP := 3.0 # same with any tool (agreed)
const GATHER_BERRY := 1.0
const GATHER_METAL := 8.0 # raw iron, with the tier-2 pickaxe only (v3, start)
const TOOL_GATHER_MULT := 2.0

# --- Stats ---
const STAT_MIN := 5 # (agreed)
const STAT_MAX := 10 # (agreed)
const STAT_SOFT_CAP := 30 # (agreed)
const XP_SOFT_CAP_MULT := 3.0
const XP_GATHER := 1.0
const XP_MELEE_HIT := 2.0
const XP_PER_CELL := 0.05
const XP_BOW_SHOT := 2.0
const XP_CHA_WIN := 3.0

# --- Needs (agreed unless noted) ---
const WARMTH_DRAIN_SECS := 240.0
const WARMTH_SEEK := 0.3
const WARM_SIT_SECS := 10.0
const WARM_RADIUS := 2
const DESPERATE_WARMTH := 0.15
const HUNGER_DRAIN_SECS := 480.0
const BERRY_FOOD := 0.2
const HUNGER_EAT := 0.5 # eat from inventory below this (starting value)
const HUNGER_SEEK := 0.4 # go find berries below this (starting value)
const MAX_HP := 100.0
const HP_DRAIN_PER_NEED := 0.5
const HP_REGEN := 0.2

# --- Fires (agreed) ---
const FIRE_SECS_PER_WOOD := 180.0
const HOUSE_FIRE_MAX_WOOD := 10
const WILD_FIRE_MAX_WOOD := 3
const FIRE_UNLIT_DESTROY_SECS := 60.0
const FIRE_REFUEL_AT_WOOD := 3
const PRIVILEGE_RADIUS := 8
const WALL_DECAY_SECS := 600.0

# --- Houses ---
const CELLS_PER_OCCUPANT := 4 # (agreed concept, starting value)
const HOUSE_SITE_SEARCH := 30
const HOUSE_MAX_TREE_DIST := 25
const FURNITURE_PER_HOUSE := 1 # the chest (agreed)

# --- Workshops (Phase C) ---
const WORKSHOP_SIZE := Vector2i(5, 4) # fixed interior: fire + sawmill + stone cutter (agreed, starting value)
const SMELTERY_SIZE := Vector2i(6, 5) # fire, furnace, anvil, 2 crates (v3, start)
const KINGDOM_SMELTERIES := 1 # smelteries a kingdom aims for (v3, start)
const WORKSHOP_RANGE := 90.0 # how far agents walk to a workshop to process or craft
const RAID_AXES_PER_GANG := 3 # gangs craft up to this many raiding axes (or one per member)
const MINERS_PER_GROUP := 1 # members with a tier-2 pickaxe a group aims for (v3, start)
const IRON_STOCK_GOAL := 20 # raw iron a group keeps mining towards (v3, start)
const BAR_STOCK_GOAL := 6 # iron bars a side keeps in its smeltery crates (v3, start)
const SMELT_BATCH := 4 # iron bars one furnace trip makes at most
const SMITH_CLAIM_SECS := 120.0 # one agent per smeltery machine for this long

# --- Relations and kingdoms (Phase D) ---
const REL_TRADE := 5.0 # (agreed)
const REL_SHARED_FIRE := 3.0 # (agreed)
const REL_DEFEND := 10.0 # (agreed)
const REL_ROB := -15.0 # (agreed)
const REL_SERVANT := -25.0 # (agreed)
const REL_KILL := -30.0 # (agreed)
const GROUP_MEET_COOLDOWN := 60.0 # (agreed)
const ALLY_AT := 40.0 # (agreed)
const WAR_AT := -40.0 # (agreed)
const ALLY_CHANCE := 0.2 # (agreed)
const WAR_CHANCE := 0.2 # (agreed)
const KINGDOM_MAX_GROUPS := 6 # (agreed)
const PEACE_SECS := 600.0 # war ends after 10 min without raids (agreed)
const PEACE_RELATION := -20.0 # relation after peace (agreed)
const BYSTANDER_DEFEND_OPINION := 30.0 # happy bystanders defend agents they like this much

# --- Raids (Phase F) ---
const RAID_CHECK_SECS := 30.0 # how often a group with raiding axes considers a raid
const RAID_CHANCE := 0.3 # with 1 raiding axe
const RAID_CHANCE_PER_AXE := 0.15 # each extra axe raises the chance (agreed concept)
const RAID_RANGE := 80.0 # gangs look for targets this close to home
const RAID_MAX_SECS := 180.0 # a raid is lost after 3 minutes (agreed)
const RAID_SMELTERY_SIZE_BONUS := 4 # gangs take on groups this much bigger for a smeltery (v3, start)
const RAID_IRON_WEIGHT := 3.0 # in a gang's target score, a unit of iron counts this much (gear double; v3 start)
const KINGDOM_DEFEND_RANGE := 30 # same-kingdom groups this close send help (agreed)

# --- Territorial kingdoms (v3 Phase 1) ---
const PUSH_RADIUS := 22 # foreign houses this close to the king's house are pushed out
const PUSH_POWER_RATIO := 1.5 # a group leaves if the kingdom is this much stronger
const REL_LEAVE := -10.0 # relation change when a group agrees to leave
const PUSH_CHECK_SECS := 10.0 # how often a kingdom checks its land (one ladder step per check)
const PUSH_LEAVE_SECS := 360.0 # a group still there this long after agreeing to leave means war
const PUSH_TRUCE_SECS := 300.0 # after peace, wait this long before demanding again
const INVITE_MIN_RELATION := -10.0 # an invited group joins if relations are at least this
const DEMOLISH_SECS := 2.0 # time to tear down one piece

# --- Chests (Phase B) ---
const STOCK_BERRIES_PER_MEMBER := 5 # (agreed)
const HOME_RANGE := 40.0 # how far from home an agent still uses the chest
const KEEP_BERRIES := 4 # berries an agent keeps on itself; the rest is surplus
const KEEP_STACKS := {"wood": 15, "stone": 10, "hemp": 5, "arrow": 15, "raw_iron": 0}

# --- Social ---
const SOCIAL_RANGE := 5.0
const PAIR_COOLDOWN := 30.0
const AUTH_DOMINANCE := 1.5 # (agreed)
const TALK_DOWN_MULT := 0.5 # happy agent's "tiny chance" to talk an angry one down
const TALK_DOWN_FLEE := 10 # (agreed)
const DEMAND_FRACTION := 0.5
const FACTION_MAX := 8 # includes servants (agreed)
const GRUDGE := -50.0
const DEFEND_RADIUS := 10.0

const MOOD_HAPPY := 33.0
const MOOD_ANGRY := -33.0

# --- Combat ---
const PLEAD_HP := 0.2 # (agreed)
const SURRENDER_ACCEPT := 0.5 # (agreed)
const SURRENDER_OPINION_SWING := 0.1
const CHASE_GIVE_UP := 20.0
const LOOT_DESPAWN := 120.0 # 2 minutes (agreed)
const RESPAWN_MIN_DIST := 15
const REBEL_STR_RATIO := 1.5
const REBEL_CHECK_SECS := 120.0
const REBEL_CHANCE := 0.1

# --- AI ---
const THINK_INTERVAL := 0.25
const WANDER_RADIUS := 10
const LOOT_SEEK_RADIUS := 10
const MAX_SIM_STEP := 0.1
