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

const TREE_CAPACITY := 20
const ROCK_CAPACITY := 20
const HEMP_CAPACITY := 3
const BUSH_BERRIES := 5
const BUSH_REGROW_SECS := 60.0
const NODE_RESPAWN_MIN := 180.0
const NODE_RESPAWN_MAX := 360.0

# --- Gathering (seconds per unit) ---
const GATHER_WOOD := 4.0
const GATHER_STONE := 5.0
const GATHER_HEMP := 3.0 # same with any tool (agreed)
const GATHER_BERRY := 1.0
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
