extends RefCounted
## Sheet-to-animation mapping for agent sprites (Summer Roadmap §3). Pure data: swapping the
## placeholder sci-fi art for fantasy art should only mean editing this file.
##
## Each sheet is a horizontal strip of square frames (frame size = sheet height, frame count =
## width / height), drawn centred on the agent with the art facing +X. Per set:
##   weight  - how often agents get this body (picked by agent id, so it is stable)
##   scale   - world px per art px (1.0 = one art pixel per world pixel at CELL 32)
##   angle   - radians to add if the art doesn't face +X (e.g. -PI/2 for art facing up)
##   tints   - modulate colours picked per agent for variety (keep them light)
##   legs    - idle, walk, run
##   torso   - idle, walk, run, attack, use, pain, death
## Each animation: sheet (path), fps, loop. Optional:
##   alt     - a second sheet for attack, alternated each swing (left / right punch)
##   stride  - legs only: cells/s at which the walk/run cycle plays at `fps` (faster feet when quicker)
## A torso animation may be missing; AgentLayer falls back (pain -> idle with a red flash,
## use -> attack, attack -> use, walk -> run, run -> walk). idle and death must exist.

const DIR := "res://art/characters/"

const SETS := {
	"player": {
		"weight": 5,
		"scale": 1.0,
		"angle": 0.0,
		"tints": [Color(1, 1, 1), Color(0.85, 0.95, 1.1), Color(1.1, 0.95, 0.85), Color(0.9, 1.05, 0.9), Color(1.15, 1.15, 1.15)],
		"legs": {
			"idle": {"sheet": "player/player_legs_idle_Sheet.png", "fps": 1, "loop": true},
			"walk": {"sheet": "player/player_legs_walk_Sheet.png", "fps": 10, "loop": true, "stride": 3.0},
			"run": {"sheet": "player/player_legs_run_Sheet.png", "fps": 12, "loop": true, "stride": 3.6},
		},
		"torso": {
			"idle": {"sheet": "player/player_idle_unarmed_Sheet.png", "fps": 1, "loop": true},
			"walk": {"sheet": "player/player_run_unarmed_Sheet.png", "fps": 8, "loop": true},
			"run": {"sheet": "player/player_run_unarmed_Sheet.png", "fps": 12, "loop": true},
			"attack": {"sheet": "player/player_unarmed_left_punch_Sheet.png", "alt": "player/player_unarmed_right_punch_Sheet.png", "fps": 14, "loop": false},
			"use": {"sheet": "player/player_use_Sheet.png", "fps": 5, "loop": true},
			"death": {"sheet": "player/player_death_Sheet.png", "fps": 8, "loop": false},
		},
	},
	"scientist": {
		"weight": 4,
		"scale": 1.0,
		"angle": 0.0,
		"tints": [Color(1, 1, 1), Color(0.8, 0.85, 1.0), Color(1.0, 0.9, 0.75), Color(0.8, 0.95, 0.8), Color(0.7, 0.7, 0.75)],
		"legs": {
			"idle": {"sheet": "scientist/npc_scientist_legs_idle_Sheet.png", "fps": 1, "loop": true},
			"walk": {"sheet": "scientist/npc_scientist_legs_walk_Sheet.png", "fps": 10, "loop": true, "stride": 3.0},
			"run": {"sheet": "scientist/npc_scientist_legs_run_Sheet.png", "fps": 12, "loop": true, "stride": 3.6},
		},
		"torso": {
			"idle": {"sheet": "scientist/npc_scientist_idle_Sheet.png", "fps": 4, "loop": true},
			"walk": {"sheet": "scientist/npc_scientist_walk_Sheet.png", "fps": 10, "loop": true},
			"run": {"sheet": "scientist/npc_scientist_run_Sheet.png", "fps": 12, "loop": true},
			"use": {"sheet": "scientist/npc_scientist_use_Sheet.png", "fps": 5, "loop": true},
			"pain": {"sheet": "scientist/npc_scientist_pain_Sheet.png", "fps": 12, "loop": false},
			"death": {"sheet": "scientist/npc_scientist_death_Sheet.png", "fps": 8, "loop": false},
		},
	},
	"brute": {
		"weight": 2,
		"scale": 1.0,
		"angle": 0.0,
		"tints": [Color(1, 1, 1), Color(1.1, 0.95, 0.8), Color(0.85, 0.9, 1.1), Color(0.95, 0.8, 0.8)],
		"legs": {
			"idle": {"sheet": "brute/enemy_legs_idle_Sheet.png", "fps": 1, "loop": true},
			"walk": {"sheet": "brute/enemy_legs_walk_Sheet.png", "fps": 10, "loop": true, "stride": 3.0},
			"run": {"sheet": "brute/enemy_legs_run_Sheet.png", "fps": 12, "loop": true, "stride": 3.6},
		},
		"torso": {
			"idle": {"sheet": "brute/enemy_idle_Sheet.png", "fps": 4, "loop": true},
			"walk": {"sheet": "brute/enemy_walk_Sheet.png", "fps": 10, "loop": true},
			"run": {"sheet": "brute/enemy_run_Sheet.png", "fps": 12, "loop": true},
			"attack": {"sheet": "brute/enemy_attack_Sheet.png", "fps": 16, "loop": false},
			"pain": {"sheet": "brute/enemy_pain_Sheet.png", "fps": 12, "loop": false},
			"death": {"sheet": "brute/enemy_death_Sheet.png", "fps": 8, "loop": false},
		},
	},
}
