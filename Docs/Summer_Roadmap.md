# Anarchy Colony Sim — Summer Roadmap

**Status:** agreed direction (2026-11-24). Each phase gets its own detailed plan before it is built.
**Builds on:** Kingdom Wars (`Docs/Kingdom_Wars_Plan.md`), Godot 4.7.2, GDScript.

> As before, **(agreed)** marks decisions the user made and **(start)** marks starting values for tuning.

**Purpose of the project (agreed):** a sandbox for trying game ideas. Whatever proves fun here may move to the user's separate fantasy multiplayer project, so systems should be data-driven and easy to lift out.

---

## 1. Phase order (agreed)

| # | Phase | Plan doc | Done when |
|---|---|---|---|
| 1 | **Player character** | `Docs/Player_Controller_Plan.md` | You can play as one agent: walk, fight, harvest, build, die and carry on |
| 2 | **Sprites** | §3 below; detailed plan when we get there | Agents and the player are drawn as layered top-down sprites instead of discs |
| 3 | **Player social** | Player plan §5; detailed plan when we get there | The player can be recruited, join, lead and answer requests with quick replies |
| 4 | **Fantasy slice** | To write; wizard story decided then | Mythril, at least one magic weapon and burnable wood are in and playtested |
| 5 | **Bigger world** | §4 below; detailed plan when we get there | 4× map, wrapping, coarse / full sim split with no loading screens |

**Dropped (agreed): multiplayer.** An authoritative server with client prediction is a project on its own. The user's multiplayer game gets that effort. The actions layer in phase 1 is still the right shape for a server, so it is good practice anyway.

## 2. Rules from day one: build for the bigger world (agreed)

Phase 5 comes last, but these rules apply from phase 1 so it doesn't need a rewrite:

1. **The sim never depends on rendering.** Renderers read sim state and never change it. An agent that isn't drawn must behave the same.
2. **Wrap-aware distance everywhere.** Add `World.delta(a, b)` and `World.dist(a, b)` (and squared versions) in phase 1. All new code measures distance and direction through them, and old code is moved over when touched. While the map doesn't wrap they are plain subtraction; in phase 5 they pick the shortest way round.
3. **One agent scheduler.** All agent updates go through one place. For now it updates everyone every tick. Later it decides who gets updated, and how often (§4.3).
4. **Groups are real entities.** Raid parties and crews already exist as data (`Raid`, `Faction`). New group behaviour builds on these rather than on agents that happen to share a goal, so groups can later move as one.
5. **The player is just an agent with a different controller.** Anything centred on the player (camera, feed, fidelity rings) uses "the controlled agent", so it still works after taking over another body.

## 3. Sprites (phase 2, outline)

- **Placeholder art (agreed):** the sci-fi pack at `C:\Users\John\Documents\GameDev\TopDownShooter\Spritepacks\Sci-Fi-TDS-Graphics_Unity_by_valentint`. It gets swapped for fantasy art in phase 4. The user sources anything missing (bows, tools) as it comes up.
- **Two layers per agent:**
  - **Legs** (`Legs/…`: idle, walk, run) face the direction of movement.
  - **Torso** (`PlayerCustom/…` unarmed idle, run and left/right punch; `Player/…` death, use) faces the aim or target direction.
- Frames are 48×48 in horizontal strips, for example run is 6 frames and punch is 4.
- **NPC variety:** the `Enemy` and `NPC_Scientist` sets give a second and third body. Faction colour stays readable through a tint or a ring under the feet.
- **Open:** the scale. One cell is 16 px and a frame is 48 px. The likely start is drawing the body about one cell wide and relying on camera zoom, but check how it reads in play.
- **Performance:** 120+ animated agents should be drawn in a batch (one `_draw` pass or a MultiMesh), not 240 `Sprite2D` nodes. That also keeps rule 1 easy to follow.

### 3.1 Implementation notes (phase 2, first pass)
- **Files:** `render/BodySets.gd` (the data: sheet → animation per body set), `render/SpriteAtlas.gd` (packs every listed sheet into one mipmapped atlas and compiles the animations), `render/agent_sprite.gdshader`, `render/AgentLayer.gd`. The used sheets are copied into `art/characters/{player,scientist,brute}/`.
- **Swapping art:** edit `BodySets.gd` only. Each set has a weight, a scale, an angle offset (for art that doesn't face +X), tints, `legs` (idle, walk, run) and `torso` (idle, walk, run, attack, use, pain, death). Frame size comes from the sheet height, so the fantasy art can use another size. Missing torso animations fall back (walk ↔ run, use ↔ attack, pain → red flash); idle and death are required.
- **Bodies:** player (weight 5), scientist (4), brute / the pack's green monster (2). Picked by a hash of the agent id with a per-agent tint, so an agent keeps its look.
- **Scale:** one art pixel = one world pixel at `CELL = 32` (the scale question in the outline above is settled).
- **Drawing:** one `MultiMeshInstance2D` with legs then torso per agent, bodies of the dead underneath. Per-frame data goes in as one `MultiMesh.buffer` write. Filter is nearest-with-mipmaps: crisp at zoom ≥ 1, smaller mips instead of shimmer below. The rows of the atlas are 16 px aligned so mips don't bleed.
- **What plays when (all inferred in the renderer, rule 1):** legs face the movement direction and play idle / walk / run. Run is used when faster than 3.3 cells/s or on a FIGHT, FLEE, RAID or DEFEND job, and the cycle speed follows ground speed. The torso faces `facing_of()`: `Agent.facing` once phase 1 adds it, else the FIGHT target, else the last movement direction. A swing is detected as `attack_cd` jumping up (punches alternate left / right). A hit is `hp` dropping (pain animation if the set has one, plus a red flash). Standing still on GATHER, TASK, CRAFT, CHEST or LOOT plays "use". An agent vanishing from `World.agents` leaves a body playing death, which fades after 30 sim seconds (at most 60 bodies).
- **Readability:** under each agent there is a faction-coloured disc (grey if solo) with a mood-coloured rim, plus the grey armour ring. Servant (black) and leader (gold) pips sit at the top-right. The raider pennant, selection ring, path line, fight lines and labels are unchanged.
- **Zoomed out:** below camera zoom 0.3 (the whole-map view is 0.14), `AUTO` draws the old discs, because a 20 px body is 3 px there. **K** cycles auto / sprites / discs.
- **Cost:** only agents on screen (plus 96 px) animate and draw; off-screen ones just track position, hp and swings. With `--frames=10`, `draw_agents` was 0.44–0.48 ms before and is 0.45–0.49 ms after (map view in discs, city view in sprites). Frame averages are unchanged within run-to-run sim noise.
- **`--shot`** now also saves `shot_fight.png`, a 2.5× close-up of a fight.
- **Art gaps (user to source):** an unarmed walk torso for the player body (it reuses run, slower); bow draw / shoot and a held bow; tool-in-hand gathering poses (axe chop, pickaxe swing, building hammer), since "use" is a generic reach; weapon overlays (sword, axe) or per-weapon attack strips; a pain strip for the player body without the pistol (it flashes red instead); a "use" strip for the brute (it reuses attack, slowed down); armour layers or tints for helmets and chest armour; a sitting / warming pose for fires; corpse or blood decals that last after the body fades.

## 4. Bigger world (phase 5, outline)

### 4.1 Size and shape
- **4× today's area (agreed):** 400 × 400 cells, up from 200 × 200.
- **The map wraps (agreed)** on both axes. No edge or corner kingdoms, and walking keeps going.
- **The whole map stays in memory.** At this size the grid is cheap, so nothing streams and there are no loading screens. What changes with distance is only **how carefully** each part is simulated.
- **Rendering at the seam:** everything is drawn relative to the controlled agent (screen position comes from `World.delta(player, thing)`), so the seam never shows.

### 4.2 Regions and the region graph
- The map is split into regions (start: 32 × 32 cells, so 13 × 13 = 169 regions).
- A **region graph** records which neighbouring regions connect and the crossing cost. It updates when walls are built or destroyed.
- **Hierarchical pathfinding:** long trips plan region to region on the graph, then run cell A* only within the next region. This also speeds up the full sim.

### 4.3 Fidelity rings (agreed approach)

| Ring | Where (start) | How it runs |
|---|---|---|
| **Full** | The screen plus a margin of about one region | Today's sim: every tick, cell paths, real swings |
| **Reduced** | The next 1–2 regions out | Still individual agents, but time-sliced (each brain thinks every 4th–8th tick), coarse paths, no visual-only work |
| **Coarse** | Everything else | Groups and aggregates, ticked about once per second |

- The full ring always reaches past the camera edge, so **every change of mode happens off-screen**.
- **Hysteresis:** promote at distance X and demote at X plus a margin, so agents on a border don't flip back and forth.
- Promotions are spread over several frames, so there are no hitches.
- **Budget instead of hard rings (goal):** each agent gets an importance score (distance to the player, in combat, ally or enemy of the player). Each frame the scheduler spends a fixed budget on the most important agents first. The rings are the starting point. More agents or a bigger map then means distant things update less often, instead of the frame rate dropping.

### 4.4 Coarse rules
Agents are **never deleted or made up**. Every agent stays a real record (stats, inventory, faction). In coarse mode they stop running brains and are handled in bulk:

- **Group movement:** a raid party, caravan or work crew moves as one entity along a region path, at its slowest member's speed, with one path search for the whole group. When it reaches the reduced ring, members are placed in formation around the group position and their brains switch back on.
- **Coarse combat:** hostile groups in the same region roll dice each coarse tick, weighted by strength (headcount × gear tier × HP). **Losses land on the real records**: real deaths, broken gear and loot. If the player arrives mid-fight, both sides are promoted and real combat finishes it.
- **Coarse economy (the Melvor-style part):** a gatherer in a coarse region gets `rate × time`, taken from the node's remaining amount. Hunger and warmth drain in bulk and agents eat from their inventory. Building pieces finish after enough work time.
- **Always exact:** kingdom decisions (wars, tax, raids, recruitment). They are already cheap and they drive the story.

### 4.5 Not in scope
- A truly infinite world, chunk streaming and saving only the changes against a seed. The design above doesn't block them, but 4× doesn't need them.

## 5. Later ideas (not scheduled)
- **News travels:** distant events only reach the player's feed through rumours, messengers or survivors. This fits the fidelity rings.
- **Fantasy ideas to weigh in phase 4:**
  - Mythril only in one biome, so kingdoms fight over the land.
  - Fire spreads to wooden pieces, so stone building and quarries matter in sieges.
  - Frost slows; chain lightning is strong against crowds but has friendly fire.
  - Blink or dash for mobility.
  - Wizards as rare agents that kingdoms recruit or kidnap.
  - Mana or reagents as a cost per cast.
