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
##   torso   - idle, walk, run, attack, use, pain, death, plus chop (axe on a tree), mine
##             (pickaxe on rock or metal) and
##             <anim>_<weapon> variants: attack_<weapon> plays instead of attack when fighting
##             with that weapon, idle/walk/run_<weapon> while carrying it (e.g. idle_club)
## Each animation: sheet (path), fps, loop. Optional:
##   alt     - a second sheet for attack, alternated each swing (left / right punch)
##   stride  - legs only: cells/s at which the walk/run cycle plays at `fps` (faster feet when quicker)
##   items   - optional: torso animation name -> {sheet} drawn over the torso with the same
##             frame (a tool in the hands); its pixels already leave out hands and head. It
##             takes fps and loop from that torso animation and must have as many frames
## A torso animation may be missing; AgentLayer falls back (pain -> idle with a red flash,
## use -> attack, attack -> use, walk -> run, run -> walk). idle and death must exist.

const DIR := "res://art/characters/"


## The shared human (tools/spritekit/spritekit.py makes these sheets); one set per skin tone.
static func _human(skin: String, weight: int) -> Dictionary:
	var h := "human/human_"
	return {
		"weight": weight,
		"scale": 1.0,
		"angle": 0.0,
		"tints": [Color(1, 1, 1)],
		"legs": {
			"idle": {"sheet": h + "legs_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk": {"sheet": h + "legs_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true, "stride": 3.0},
			"run": {"sheet": h + "legs_walk_%s_Sheet.png" % skin, "fps": 12, "loop": true, "stride": 3.6},
		},
		"torso": {
			"idle": {"sheet": h + "body_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk": {"sheet": h + "body_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run": {"sheet": h + "body_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"attack": {"sheet": h + "body_punch_right_%s_Sheet.png" % skin, "alt": h + "body_punch_left_%s_Sheet.png" % skin, "fps": 14, "loop": false},
			"use": {"sheet": h + "body_gather_%s_Sheet.png" % skin, "fps": 9, "loop": true},
			"attack_spear": {"sheet": h + "body_spear_thrust_%s_Sheet.png" % skin, "fps": 14, "loop": false},
			"attack_club": {"sheet": h + "body_club_swing_%s_Sheet.png" % skin, "fps": 14, "loop": false},
			"attack_sword": {"sheet": h + "body_sword_swing_%s_Sheet.png" % skin, "fps": 16, "loop": false},
			"idle_sword": {"sheet": h + "body_sword_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_sword": {"sheet": h + "body_sword_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_sword": {"sheet": h + "body_sword_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"idle_club": {"sheet": h + "body_club_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_club": {"sheet": h + "body_club_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_club": {"sheet": h + "body_club_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"attack_bow": {"sheet": h + "body_bow_fire_%s_Sheet.png" % skin, "fps": 10, "loop": false},
			"idle_bow": {"sheet": h + "body_bow_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_bow": {"sheet": h + "body_bow_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_bow": {"sheet": h + "body_bow_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"idle_spear": {"sheet": h + "body_spear_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_spear": {"sheet": h + "body_spear_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_spear": {"sheet": h + "body_spear_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"chop": {"sheet": h + "body_axe_swing_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"mine": {"sheet": h + "body_pickaxe_swing_%s_Sheet.png" % skin, "fps": 9, "loop": true},
			"idle_axe": {"sheet": h + "body_axe_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_axe": {"sheet": h + "body_axe_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_axe": {"sheet": h + "body_axe_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"idle_pickaxe": {"sheet": h + "body_pickaxe_idle_%s_Sheet.png" % skin, "fps": 1, "loop": true},
			"walk_pickaxe": {"sheet": h + "body_pickaxe_walk_%s_Sheet.png" % skin, "fps": 10, "loop": true},
			"run_pickaxe": {"sheet": h + "body_pickaxe_walk_%s_Sheet.png" % skin, "fps": 14, "loop": true},
			"death": {"sheet": h + "body_death_%s_Sheet.png" % skin, "fps": 8, "loop": false},
		},
		"items": {
			"chop": {"sheet": "human/item_axe_swing_Sheet.png"},
			"mine": {"sheet": "human/item_pickaxe_swing_Sheet.png"},
			"idle_axe": {"sheet": "human/item_axe_idle_Sheet.png"},
			"walk_axe": {"sheet": "human/item_axe_walk_Sheet.png"},
			"run_axe": {"sheet": "human/item_axe_walk_Sheet.png"},
			"idle_pickaxe": {"sheet": "human/item_pickaxe_idle_Sheet.png"},
			"walk_pickaxe": {"sheet": "human/item_pickaxe_walk_Sheet.png"},
			"run_pickaxe": {"sheet": "human/item_pickaxe_walk_Sheet.png"},
			"attack_spear": {"sheet": "human/item_spear_thrust_Sheet.png"},
			"attack_club": {"sheet": "human/item_club_swing_Sheet.png"},
			"attack_sword": {"sheet": "human/item_sword_swing_Sheet.png"},
			"idle_sword": {"sheet": "human/item_sword_idle_Sheet.png"},
			"walk_sword": {"sheet": "human/item_sword_walk_Sheet.png"},
			"run_sword": {"sheet": "human/item_sword_walk_Sheet.png"},
			"idle_club": {"sheet": "human/item_club_idle_Sheet.png"},
			"walk_club": {"sheet": "human/item_club_walk_Sheet.png"},
			"run_club": {"sheet": "human/item_club_walk_Sheet.png"},
			"attack_bow": {"sheet": "human/item_bow_fire_Sheet.png"},
			"idle_bow": {"sheet": "human/item_bow_idle_Sheet.png"},
			"walk_bow": {"sheet": "human/item_bow_walk_Sheet.png"},
			"run_bow": {"sheet": "human/item_bow_walk_Sheet.png"},
			"idle_spear": {"sheet": "human/item_spear_idle_Sheet.png"},
			"walk_spear": {"sheet": "human/item_spear_walk_Sheet.png"},
			"run_spear": {"sheet": "human/item_spear_walk_Sheet.png"},
		},
	}


static var SETS := {
	"human_light": _human("light", 1),
	"human_dark": _human("dark", 1),
}
