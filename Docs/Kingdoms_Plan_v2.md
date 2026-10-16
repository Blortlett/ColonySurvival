# Anarchy Colony Sim — v2 Plan: Kingdoms, Cities and Raids

**Builds on:** `Docs/Anarchy_Colony_Sim_Plan.md` (v1, implemented in commit `c6bca34`)
**Engine:** Godot 4.7.2, GDScript
**Goal of this sprint:** groups grow into structured cities (kingdoms) with workshops, upgraded buildings and roads. Gangs and rival kingdoms raid each other. The look moves toward the Songs of Syx reference: floors inside buildings, roads, and a structured grid layout.

> As in v1, every number is a tunable in `core/Cfg.gd`. **(agreed)** marks values decided in design. The rest are starting values.

---

## 0. Terminology

| Term | Meaning |
|---|---|
| **Agent** | One AI person (unchanged) |
| **Group** | What v1 calls a `Faction`: max 8 members including servants **(agreed, unchanged)** |
| **Gang** | A group whose **leader is angry**. It can never join a kingdom **(agreed)** |
| **Kingdom** | An alliance of up to **6 groups (agreed)**. Each group keeps its own house |
| **Leading group** | The kingdom's group with the highest **total authority** (sum of members' AUTH) **(agreed)** |
| **King** | The highest-authority agent in the leading group **(agreed)** |

---

## 1. Viewer Features (Phase A)

### 1.1 Click a campfire → group panel **(agreed)**
Clicking a house fire or workshop fire shows:
- Group name, whether it's a gang, the leader, and member count (x/8).
- A member list with roles (leader, servant + master) and mood.
- Kingdom name, king, leading group, and the other groups in the kingdom.
- Its houses and workshops: state, occupants and capacity, fire fuel.
- **Chest contents** for each house.
- Relations: allies (the kingdom), wars, and the top ± relation scores with other groups.
- Current task board for the group and the kingdom.

A wild fire shows who placed it and its fuel.

### 1.2 Click a loot bag → loot panel **(agreed)**
- **Who dropped it, and why:** killed by #X / died of cold / died of hunger / dumped as junk / chest destroyed.
- Contents (stacks and tools with durability).
- Time left until it despawns.

### 1.3 Changes
- **Loot bags despawn after 2 minutes** (`LOOT_DESPAWN = 120`) **(agreed)**.
- Left-click priority: agent → fire → loot bag → chest/furniture (furniture shows its contents or recipe).

---

## 2. Houses v2: Floors and Chests (Phase B)

### 2.1 Wood floors **(agreed)**
- Every interior tile of a house (and of a workshop, **agreed**) needs a **wood floor: 1 wood per tile**. The fire tile is excluded.
- A building is only **COMPLETE** when its walls, door **and floors** are all placed.
- Floors are walkable. Furniture goes on top of a floored tile.
- Floors decay with the walls when unprotected (10 min to 0).

### 2.2 Interior size
`interior cells = 4 × occupants + 1 (fire) + 1 per furniture piece`. A house has 1 chest, so it gets +1.

### 2.3 Chests **(agreed)**
| Chest | Cost | Slots |
|---|---|---|
| Basic chest | 5 wood | 30 |
| Reinforced chest | 4 planks + 1 handle | 60 |

- A chest sits on an interior floor tile. Only members of the owning group can use it.
- **Stocking goal (agreed):** 5 berries per member, 1 spare axe, 1 spare pickaxe, 1 spare weapon.
  - Agents deposit any surplus beyond that.
  - Agents at home eat from the chest before going out for berries.
- When the chest decays to 0 HP (house abandoned or raided), its contents drop as a loot bag with drop reason "chest destroyed".
- Raiders who win a raid loot it (§6.5).

### 2.4 Group goal ladder (replaces v1 step 5 for groups) **(agreed)**
1. Build a **basic house**: house fire → walls → floors → door.
2. Place a **basic chest**.
3. **Stock the chest** with food and spare tools.
4. Build a **workshop**, or use the kingdom's (§3).
5. **Reinforce the house**: walls, door, chest.
6. **Reinforce the workshop**.
7. (Gangs only) Craft **raiding axes**, then raid (§6).

---

## 3. Workshop, Processing and Tiered Items (Phase C)

### 3.1 Workshop building **(agreed)**
- It's a separate building with its own **workshop fire** (the "home firepit"). The fire gives build privilege like a house fire and needs fuel.
- Fixed interior of **5 × 4** (starting value): fire + **sawmill** + **stone cutter**, all floored.
- **Owner:** the group that built it. **Access:** its door opens for **every group in the same kingdom (agreed)**. House doors still open only for their own group.
- Independent groups and gangs can build their own workshop.
- Each kingdom aims for 1 workshop, plus 1 more per 4 groups.

### 3.2 Processing (sawmill and stone cutter)
| Machine | Input → Output | Time |
|---|---|---|
| Sawmill | 2 wood → 1 **plank** | 4 s |
| Sawmill | 1 wood → 2 **handles** | 4 s |
| Stone cutter | 2 stone → 1 **cut stone** **(agreed: processed stone)** | 5 s |

Agents carry the raw materials into the workshop, stand at the machine, and process them in batches.

### 3.3 Basic vs reinforced pieces **(agreed concept)**
| Piece | Basic | Reinforced |
|---|---|---|
| Wall | 2 wood → 100 HP | 2 planks → 250 HP |
| Door | 3 wood + 1 hemp → 80 HP | 2 planks + 1 handle → 200 HP |
| Chest | 5 wood → 30 slots | 4 planks + 1 handle → 60 slots |
| Road | 1 stone → 1.3× speed | 1 cut stone → 1.5× speed |

### 3.4 Upgrade rule **(agreed)**
- To upgrade, the old piece must be **broken first**. Breaking returns **no resources**. Then the new piece is placed.
- The agent must **already be carrying the upgrade materials** before breaking anything, so the gap is only open for a moment.
- Upgrades go one piece at a time, as task-board tasks (`UPGRADE_WALL`, `UPGRADE_DOOR`, `UPGRADE_CHEST`, `UPGRADE_ROAD`).
- **Order (agreed):** reinforce the house first, then the workshop.

### 3.5 Raiding axe **(agreed)**
- **Recipe:** 2 planks + 2 cut stone + 1 handle. Crafted at a workshop.
- **Durability:** 60. **×5 damage against walls and doors.** No gathering bonus.
- Every melee weapon can damage walls and doors at normal damage. The raiding axe just makes it practical: about 4 hits on a reinforced wall, versus about 18 with a club.
- The normal axe is unchanged **(agreed)**.

---

## 4. Relations, Alliances and Kingdoms (Phase D)

### 4.1 Group relation score **(agreed)**
Each pair of groups has a score from −100 to +100, changed by what their members do to each other:

| Event | Change |
|---|---|
| Trade | +5 |
| Shared a fire | +3 |
| Defended a member of the other group | +10 |
| Robbery (demand complied, or robbed after surrender) | −15 |
| Took a servant from them | −25 |
| Killed one of their members | −30 |

The existing pairwise agent opinions stay and keep doing their v1 jobs.

### 4.2 Group-level meetings **(agreed thresholds)**
When members of two different groups meet (group pair cooldown 60 s):
- **Relation ≥ +40** → **20% chance to ally**:
  - Two independent non-gang groups → **form a new kingdom**.
  - An independent group meets a kingdom group → **joins that kingdom**, if it has room (max 6 groups).
  - **Kingdoms never merge (agreed)**, and gangs never ally **(agreed)**.
- **Relation ≤ −40** → **20% chance to declare war** (§6.1).

### 4.3 Kingdom rules
- **Leading group** = highest total AUTH. **King** = highest AUTH in that group **(agreed)**. Both are recalculated whenever AUTH or membership changes.
- **Shared territory (agreed):** inside a kingdom, any member group can build in any member group's privilege zone. Their zones merge into one kingdom territory.
- **No fire spacing inside a kingdom (agreed):** house fires of the same kingdom ignore the 17-cell spacing rule, so city houses can slot together. Spacing still applies between different kingdoms and independent groups.
- **No shared housing (agreed):** every group has its own house(s), even inside a kingdom. Workshops *are* shared.
- **Kingdom board:** a physical object at the city plaza (cost 4 wood). It holds city-level tasks: clear plots and roads, build roads, build workshops, defence calls.
- **Collapse:** if the leading group disbands, leadership is recalculated. A kingdom down to 1 group dissolves back into an independent group.
- **Rendering:** an agent's fill colour stays its group colour. A kingdom-coloured outline is drawn around kingdom territory.

---

## 5. Cities and Roads (Phase E)

### 5.1 City grid
- When a kingdom forms, it lays out a **city grid anchored on the king group's house fire**. That house becomes the centre plot, even if it's slightly off-grid.
- **Plots:** 10 × 10 cells on an **11-cell pitch**, separated by **1-cell roads**. A plot fits even an 8-person house or a workshop.
- **Assignment by distance from the centre:**
  - The centre plot is the king group's house.
  - The first ring holds the **plaza** with the kingdom board, then other groups' houses.
  - Workshops go on the next ring.
  - New groups get the nearest free plot.
- A full 6-group city with workshops is about 55 × 55 cells.
- If the king changes to another group, the grid stays where it is; plots don't move.

### 5.2 Relocation **(agreed: groups move near the original leader)**
- When a group joins a kingdom, it gets a plot and builds a **new house there first**.
- Its old house is only **abandoned once the new house is COMPLETE**, so members are never left homeless.

### 5.3 Clearing **(agreed)**
- Trees and rocks must be **completely removed** before a road piece (or a building) can be placed on that cell.
- The kingdom board posts `CLEAR_NODE` tasks: chop or mine the node down to nothing. This yields plenty of wood and stone.
- **Resource respawns never land on roads or city plots.**

### 5.4 Roads **(agreed)**
| Road | Cost | Speed |
|---|---|---|
| Stone road | 1 stone per cell | 1.3× |
| Paved road | 1 cut stone per cell | 1.5× |

- Only kingdoms build roads.
- Build order: the plaza, then the roads between plots, then a spur to each door.
- Paving is an upgrade (break, then replace).
- A* path costs are lowered on road cells (`AStarGrid2D` point weights), so agents prefer roads.

### 5.5 Visual pass **(agreed this sprint)**
- Wood **floor tiles** inside houses and workshops.
- **Road tiles:** a gravel look for stone roads, cobbles for paved roads.
- Separate visuals for basic and reinforced walls and doors, chests, sawmill and stone cutter.
- A darker, Songs of Syx-leaning palette. Still placeholder shapes, no sprites.

---

## 6. War and Raids (Phase F)

### 6.1 Declaring war
- **Normal groups and kingdoms must declare war before raiding (agreed).** Declaration happens through §4.2 (relation ≤ −40, 20% per meeting).
- **War is kingdom-wide.** If a kingdom group declares war, the whole kingdom is at war with the target's whole kingdom, or with the target group if it's independent.
- **Gangs never need to declare war (agreed).** Raiding is their main goal once they have raiding axes.
- **Peace:** a war ends after **10 minutes with no raids** between the sides. The relation score then resets to −20.

### 6.2 When a group raids
- A group only considers raiding once it carries **at least 1 raiding axe (agreed)**. Each extra axe raises its raid chance and lets it pick tougher targets.
- **Gang targets:** the weakest nearby group with the richest chest(s).
- **At-war targets:** the nearest enemy house.

### 6.3 Raid party **(agreed)**
- **Every member above 50% HP joins.** If the group has 4 or more members, **one keeper stays home** to keep the fire fuelled.
- The party gathers at a rally point, marches to the target, and attacks the **door or the weakest wall** (raiding axes first). It fights defenders, then pushes inside.

### 6.4 Defence **(agreed)**
- When raiders enter a group's zone, **every member drops what it's doing and goes home to defend**. This is the critical priority layer.
- Same-kingdom groups within 30 cells send their healthy members to help.

### 6.5 Raid outcome **(agreed)**
- **Win:** a raider is inside the house while no defenders are left standing in the zone (all dead, fled or surrendered).
  - **The fire is put out** (fuel set to 0), so the zone dies and the house decays naturally.
  - **Raiders loot the chest** and the house for whatever they need and can carry.
  - **Surrendering defenders** follow the normal rules: 50/50 to accept, becoming servants if there's room **(agreed)**.
- **Loss:** half the raiders are down, or **3 minutes** have passed. The raiders retreat home.
- Raids lower the relation score heavily (robbery and kill events apply).

---

## 7. Changes to Existing v1 Systems

| System | Change |
|---|---|
| `Faction` | Becomes the "group". Gains `kingdom`, a `relations` dictionary and an `is_gang()` check (leader angry) |
| Privilege / `can_build` | Kingdom members can build in each other's zones. Fire spacing is skipped within a kingdom |
| Doors | House door: own group only. Workshop door: whole kingdom |
| `House` | Gains a type (HOUSE / WORKSHOP), floor cells, furniture (chest / sawmill / stone cutter) and piece tiers. COMPLETE requires floors |
| Walls | Get a tier and become attackable on purpose. Raiding axe does ×5 |
| Loot bags | Despawn after 120 s. Record the dropper and the drop reason |
| Node respawn | Excludes roads and city plots |
| A* | Road cells get lower path cost |
| Inventory | New stackables: plank, handle, cut_stone. New tool: raiding_axe |
| HUD | Click a fire or loot bag to open the new panels. The top bar adds kingdoms and active wars |

---

## 8. Implementation Phases **(agreed order)**

Each phase ends with something runnable and gets its own commit. Each is checked with `--bench` and `--shot` before moving on.

| # | Phase | Done when |
|---|---|---|
| A | **Viewer and loot:** fire and loot panels, click priority, 120 s despawn, drop reasons | Clicking a fire shows the group, and clicking a bag shows its dropper and contents |
| B | **Floors and chests:** floor tasks, COMPLETE needs floors, basic chest, stocking, eating from the chest, chest decay → loot | Houses get floored and chests fill with berries and spare tools |
| C | **Workshop and tiers:** workshop blueprint, sawmill, stone cutter, planks/handles/cut stone, reinforced pieces, break-and-replace upgrades, raiding axe | Groups build workshops and reinforce the house, then the workshop |
| D | **Relations and kingdoms:** relation scores, ally/war rolls, kingdom formation and joining, leading group and king, kingdom board, shared territory and workshops, no-spacing rule | Kingdoms form, and their territory and king show in the panels |
| E | **Cities and roads:** city grid, plot assignment, relocation, clearing, roads and paving, road path weights, floor and road visuals | Kingdoms grow a structured grid city with roads |
| F | **War and raids:** war declaration and peace, gang raid logic, raid party and keeper, wall breaching, defence recall, raid outcome (fire out, looting, servants) | Gangs and warring kingdoms raid; bases fall and decay |

---

## 9. Things to Watch in Playtests
- **Pacing:** how quickly kingdoms and wars appear. The ±40 thresholds and the 20% roll are the main knobs.
- **Wood economy:** houses, floors, chests, two fires per group and upgrades all eat wood. Watch the planks bottleneck.
- **Map space:** a few 55 × 55 cities plus spacing between kingdoms on a 200 × 200 map. The map may need to grow.
- **Gang strength:** gangs need their own workshop for raiding axes, so check they actually get one.
- **Pathfinding cost:** raids path across the map and breach walls. Keep the failed-path cache in mind.
