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
##   outfits - optional: slot (legs / torso / head) -> outfit name -> {anim name -> {sheet, alt}}.
##             A clothing layer drawn over that slot's body layer, frame for frame: legs-slot
##             anims follow the legs anim (plus "death", diffed against the torso death, since
##             a corpse has no legs layer); torso and head anims follow the torso anim. Like
##             items they take fps / loop from that body anim and must have as many frames.
##             The human builds it from the sheet names (_outfits), so new outfits or anims
##             need no typing here beyond OUTFITS.
## A torso animation may be missing; AgentLayer falls back (pain -> idle with a red flash,
## use -> attack, attack -> use, walk -> run, run -> walk). idle and death must exist.

const DIR := "res://art/characters/"

## Outfits the human has art for, per slot. Sheet names come from the body sheet each one is
## diffed against: human_body_<x> / human_legs_<x> -> human_outfit_<slot>_<outfit>_<x>
## (tools/spritekit/spritekit.py writes them): peasant cloth and iron armour.
const OUTFITS := {"legs": ["peasant", "iron"], "torso": ["peasant", "iron"], "head": ["peasant", "iron"]}


## The shared human (tools/spritekit/spritekit.py makes these sheets); one set per skin tone.
static func _human(skin: String, weight: int) -> Dictionary:
	var h := "human/human_"
	var s := {
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
	s.outfits = _outfits(s.legs, s.torso)
	return s


## slot -> outfit -> anim -> {sheet, alt}, one entry per body anim whose outfit sheet exists.
## The legs slot follows the legs anims plus the torso death (corpses draw no legs layer).
static func _outfits(legs: Dictionary, torso: Dictionary) -> Dictionary:
	var out := {}
	for slot in OUTFITS:
		out[slot] = {}
		var body: Dictionary = torso
		if slot == "legs":
			body = legs.duplicate()
			body["death"] = torso.death
		for outfit in OUTFITS[slot]:
			var anims := {}
			var missing: Array[String] = []
			for anim in body:
				var e := {}
				for key in ["sheet", "alt"]:
					if body[anim].has(key):
						var path := _outfit_sheet(body[anim][key], slot, outfit)
						if not ResourceLoader.exists(DIR + path):
							missing.append(path)
							e = {}
							break
						e[key] = path
				if not e.is_empty():
					anims[anim] = e
			if not missing.is_empty():
				push_warning("BodySets: %s outfit %s has no sheet for %s" % [slot, outfit, ", ".join(missing)])
			if not anims.is_empty():
				out[slot][outfit] = anims
	return out


## human/human_body_walk_light_Sheet.png -> human/human_outfit_torso_peasant_walk_light_Sheet.png
static func _outfit_sheet(body_sheet: String, slot: String, outfit: String) -> String:
	var to := "human_outfit_%s_%s_" % [slot, outfit]
	return body_sheet.replace("human_body_", to).replace("human_legs_", to)


static var SETS := {
	"human_light": _human("light", 1),
	"human_dark": _human("dark", 1),
}
