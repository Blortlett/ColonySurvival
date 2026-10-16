# Anarchy Colony Sim — Prototype Plan (v1)

**Engine:** Godot 4.7.2 stable, GDScript
**View:** 2D, direct top-down (Hotline Miami style), placeholder shapes
**Pitch:** 120 fully autonomous AI agents spawn into a wild map. Out of the anarchy (robbery, murder, servitude) colonies emerge: factions, houses, campfires and pecking orders.

There is no player control over agents. The player is an observer who can pan, zoom, inspect and change the sim speed.

> Every number in this document is a **tunable** and lives in one config file (`Config.gd`). The numbers marked **(agreed)** were decided during design. The ones marked **(starting value)** are first guesses to tune during playtesting.

---

## 1. Core Loop

```
Spawn → survive (eat berries, stay warm) → gather (wood / stone / hemp) → craft tools
      → claim land (house fire) → build shelter → keep fire fuelled
      → meet other agents → ally / rob / fight / surrender / serve
      → die → a fresh agent respawns somewhere
```

The population is constant: each death spawns one fresh agent with random stats **(agreed)**.

---

## 2. World

| Property | Value |
|---|---|
| Map size | 200 × 200 cells (starting value) |
| Cell size | 16 px (starting value) |
| Starting agents | 120 (starting value) |
| Day/night | None. It is always day **(agreed)** |
| RNG | One seeded RNG for the whole sim, so runs can be replayed |

### 2.1 Resource nodes

Each node occupies one cell, blocks movement and blocks building on its cell.

| Node | Yields | Capacity | Notes |
|---|---|---|---|
| Tree | Wood | 20 wood | Faster with an axe |
| Rock | Stone | 20 stone | Faster with a pickaxe |
| Hemp | Hemp | 3 hemp | **Same speed regardless of tools (agreed)** |
| Berry bush | Berries | 5 berries | Regrows 1 berry every 60 s. The bush itself is never depleted |

- **Respawn (agreed):** when a tree, rock or hemp node is used up, it is removed. A replacement of the same type spawns later at a random empty cell (starting value: 3–6 min).
- Starting density (starting value): about 6% trees, 3% rocks, 1.5% hemp, 1% berry bushes. Trees and rocks are placed in loose clusters with noise, so there are forests and quarries.

### 2.2 Gathering rates (unarmed, base strength)

| Action | Unarmed | With tool |
|---|---|---|
| Wood from tree | 1 per 4 s | 1 per 2 s (axe) |
| Stone from rock | 1 per 5 s | 1 per 2.5 s (pickaxe) |
| Hemp | 1 per 3 s | same |
| Berries | 1 per 1 s | same |

The final rate is multiplied by the strength gather multiplier (§3.2). Each gather tick costs a tool 1 durability.

---

## 3. Agents

### 3.1 Stats

There are four stats, each rolled randomly in the range **5–10** at spawn **(agreed)**.

| Stat | Affects | How it levels |
|---|---|---|
| **Strength (STR)** | Gather rate, melee damage, inventory capacity | XP per gather tick at a node, and per successful melee hit |
| **Agility (AGI)** | Move speed, bow damage, bow range, bow hit chance | XP per cell moved (small) and per bow shot |
| **Charisma (CHA)** | Winning social rolls (§6.3) | XP per social roll won |
| **Authority (AUTH)** | Dominance, leadership | **Only** +1 per kill or per accepted surrender. It has no XP **(agreed)** |

**Levelling (agreed: rising XP cost with a soft cap):**
- XP to the next level = `10 × level^1.5` (starting value).
- Above level 30 (the soft cap), each further level costs 3× as much XP.
- Authority ignores this system and simply increments.
- The XP gained per cell moved is kept very small, so agility doesn't inflate.

### 3.2 Stat formulas (starting values)

| Derived value | Formula |
|---|---|
| Gather multiplier | `1 + (STR − 5) × 0.05` |
| Melee damage multiplier | `1 + (STR − 5) × 0.06` |
| Inventory capacity (items) | `20 + STR × 2` |
| Move speed (cells/s) | `3 × (1 + (AGI − 5) × 0.04)` |
| Bow damage multiplier | `1 + (AGI − 5) × 0.06` |
| Bow range (cells) | `6 + AGI × 0.3` |
| Bow hit chance | `clamp(0.5 + AGI × 0.02, 0, 0.95)` |

### 3.3 Needs and health

| Need | Rule |
|---|---|
| **Warmth** | Drains from full to empty over **4 min (agreed)**. The agent seeks a fire at **30% (agreed)**. Sitting within 2 cells of a burning fire for **10 s refills it completely (agreed)** |
| **Hunger** | Drains from full to empty over **8 min (agreed)**. **1 berry = +20% (agreed)**. Agents carry berries. They eat from their inventory below 50% and go looking for berries below 40% (starting values) |
| **HP** | Max 100. It **drains while warmth or hunger is at 0 (agreed)**, at 0.5 HP/s per empty need (starting value). It **regenerates while both are above 50% (agreed)**, at 0.2 HP/s (starting value) |

### 3.4 Inventory

Inventory is a single item-count capacity (§3.2). Each unit of wood, stone, hemp, berries or arrows counts as 1. Each tool or weapon counts as 1.

### 3.5 Mood

Mood is a hidden value from −100 to +100. The label shown is derived from it:

| Label | Range | Spawn split |
|---|---|---|
| Happy | > +33 | 50% **(agreed)**, starts at +60 |
| Neutral | −33 … +33 | 30% **(agreed)**, starts at 0 |
| Angry | < −33 | 20% **(agreed)**, starts at −60 |

**Mood drift (agreed; the amounts are starting values):**

| Event | Mood change |
|---|---|
| Robbed or attacked | −15 |
| Spared after surrender (whether made a servant or released) | **No happy boost (agreed)**. Released after being robbed: −20 |
| Successful trade | +5 |
| Joined a faction | +10 |
| Inside a faction | Drifts slowly toward the faction's average mood (1 point per minute) |

### 3.6 Pairwise memory (opinions)

Each agent stores a dictionary `{other_agent_id: opinion}` with values from −100 to +100. Agents only get an entry for someone once they have met them. Entries are removed when either agent dies. The worst case is about 14k integers, so the memory cost is negligible.

| Event | Opinion change toward the other agent |
|---|---|
| They robbed me / attacked me | −40 / −30 |
| They spared me and released me after taking my items | −50 **(agreed: big drop)** |
| Traded with me / shared a fire with me | +10 / +5 |
| Defended me in combat | +20 |

**Uses in v1:**
- Grudges: an agent with an opinion of −50 or lower toward someone treats them as hostile, even if the agent is happy.
- Surrender acceptance leans slightly on opinion (§7.2).
- Happy agents prefer sharing fires with agents they like.
- Opinions **do not** cause anyone to leave a faction. Leaving voluntarily doesn't exist in v1.

---

## 4. Crafting and Items

Agents craft anywhere, instantly, from their inventory (a 2 s crafting animation is optional).

| Item | Cost | Stats | Durability |
|---|---|---|---|
| Axe | 3 wood + 2 stone + 1 hemp | 2× wood gather | 100 uses |
| Pickaxe | 3 wood + 2 stone + 1 hemp | 2× stone gather | 100 uses |
| Spear | 3 wood + 1 hemp | 9 damage, **reach 2 cells**, 1.0 s cooldown | 60 hits |
| Club | 4 wood + 1 stone | **14 damage**, reach 1 cell, 1.2 s cooldown | 60 hits |
| Bow | 4 wood + 3 hemp | 10 damage, AGI range, 1.5 s cooldown | 80 shots |
| Arrows ×5 | 1 wood + 1 stone | Consumed per shot, hit or miss | — |
| Wood wall | 2 wood | 100 HP | — |
| Door | 3 wood + 1 hemp | 80 HP. Only the placer's faction can open it | — |
| Wild fire | 2 wood | See §5.2 | — |
| House fire | 5 wood + 3 stone | See §5.2 | — |

Unarmed attacks do 4 damage at reach 1 with a 1.0 s cooldown. Building and crafting costs are deducted from the inventory. The first unit of fire fuel comes free with placement.

**Durability (agreed):** once an item's durability hits 0, the item is destroyed. It can't be repaired and must be crafted again.

---

## 5. Building

### 5.1 Placement rules
- Walls, doors and fires go on an empty cell: no agent, resource node, wall, fire or loot bag on it **(agreed)**.
- A cell inside another owner's **build privilege zone** can't be built on, including by placing a fire.
- A door is passable only for members of the faction that placed it (or the solo agent who placed it). Everyone else treats it as a wall.

### 5.2 Campfires: two roles, one concept **(agreed)**

| | **House fire** | **Wild fire** |
|---|---|---|
| Purpose | Claiming land and founding a house | Quick warm-up out in the wild |
| Cost | 5 wood + 3 stone | 2 wood |
| Fuel on placement | 1 wood (3 min) | 1 wood (3 min) |
| Max fuel | 10 wood (30 min) | 3 wood (9 min) |
| Burn rate | **1 wood = 3 min (agreed)** | same |
| Build privilege zone | **Yes, 8-cell radius** | **No** |
| On the task board | Yes. An auto "refuel" task is posted at 3 wood or less | No |
| Unlit (0 fuel) | Destroyed after **60 s** | Destroyed after **60 s** |
| Who can warm at it | Owner's faction only (it's indoors) | Anyone. Shared by happy agents (§6.6) |

- A fire burns whenever it has fuel. There is no on/off switch.
- **Privilege zone:** while a house fire is burning, only its owner can build within 8 cells of it. Zones can't overlap, so a new house fire must be at least 17 cells from any other house fire.
- Agents are trusted to use house fires only when they intend to claim land **(agreed)**.

### 5.3 Wall decay **(agreed)**
A wall or door that isn't inside any burning house fire's privilege zone loses HP gradually. It goes from full to 0 over **10 minutes**, then it's destroyed. This makes the chain "fire dies → zone lost → walls crumble", so abandoned bases clean themselves up.

### 5.4 Houses **(agreed)**
- A house is a **closed rectangle of walls with one door and one house fire inside**.
- Interior space needed is **4 cells per occupant + 1 cell for the fire** (starting value: 4 cells). The house's capacity is however many occupants its interior can fit.
- **Build order (agreed):** place the house fire first (claims the land) → build the walls around it → place the door last.
- Each house has an **occupant list**:
  - A member who dies is removed **immediately**. The slot can then be filled by a faction member who isn't on any occupant list.
  - If every house is full and a member still has no home, the faction posts a blueprint for a **new house**. Each house has its own fire, zone and occupant list.
- A **solo agent** (unfactioned) builds its own 1-occupant house (5 interior cells) using the same system.
- **Joining a faction:** an agent who joins gives up its own house. Nobody refuels it, so the fire dies and the walls decay. It's free loot for passers-by.

### 5.5 Blueprint generation
Given the capacity needed, the agent picks a near-square interior with area ≥ `4 × N + 1`. For example:

| Occupants | Interior |
|---|---|
| 1 | 3 × 2 (6 cells) |
| 4 | 5 × 4 (20 cells) |
| 8 | 6 × 6 (36 cells) |

The fire goes at the centre of the interior. Walls form the perimeter, and the door goes on the side facing the faction's other houses or the map centre. A site is valid if every perimeter cell is buildable, the area is within the agent's own claim and is far enough from other zones, and the site isn't too far from trees.

---

## 6. Social System

### 6.1 Interaction trigger
- Social range: 5 cells (starting value). It's checked through the spatial hash (§10.3).
- **Each pair of agents has a 30 s cooldown** between interactions.
- Who initiates:
  - **Happy** agents initiate friendly interactions.
  - **Angry** agents initiate demands or attacks.
  - **Neutral agents never initiate (agreed).** They still respond.
- Members of the same faction don't run hostile interactions on each other.

### 6.2 Authority dominance **(agreed)**
If the initiator's AUTH is at least **1.5×** the target's, the target **skips the charisma roll**. It must choose **comply, flee or fight** (§6.7).

### 6.3 Charisma roll **(agreed)**
`P(A wins) = CHA_A / (CHA_A + CHA_B)`. The winner gains CHA XP. Higher charisma means better odds, but the result is never guaranteed.

### 6.4 Interaction matrix

| Initiator → Target | What happens |
|---|---|
| **Happy → Happy** (both unfactioned) | They form a new faction (unless either has an opinion of the other below 0) |
| **Happy → Happy** (different factions) | Trade: each gives 1 surplus item for 1 item it needs |
| **Happy (factioned) → unfactioned Happy/Neutral** | Invite. A happy target accepts if there's room. A neutral target accepts only if the inviter wins the CHA roll |
| **Angry → anyone (not angry)** | Either a demand (hand over 50% of inventory, starting value) or an attack on sight. Attacks are more likely if the target carries a lot or is weak. Apply authority dominance, then the target's response (§6.5) |
| **Angry → Angry** | CHA roll. **The winner recruits the loser into a gang**, or both join the winner's gang if one exists and has room; the highest AUTH leads. **If the roll is lost, they fight to the death (agreed)**. Pleading is disabled in this fight |

Only **unfactioned** agents can join a faction willingly **(agreed)**. A factioned agent only changes faction by surrendering and becoming a servant.

### 6.5 Responding to an angry initiator
1. If authority dominance applies, skip to step 3.
2. **Happy target:** it tries to talk the attacker down with a CHA roll. Its odds are lower if it's the weaker social side. If it wins, it **flees about 10 cells away and then carries on with its business**. It doesn't track the attacker after that **(agreed)**.
3. **Comply / flee / fight** (§6.7).

### 6.6 Fire sharing **(agreed)**
- Agents prefer their **own faction's house fire**, or building their own fire.
- **Happy agents happily share wild fires with other happy agents.** It's only desirable if both are happy. Sharing gives +5 opinion.
- Strangers can never enter another faction's house, because the doors are locked.
- **Desperate agents** (warmth < 15%) will use any reachable wild fire. A non-happy owner nearby may treat this as a provocation and trigger an interaction.

### 6.7 Comply / flee / fight decision
The target compares a "power" estimate for itself and the attacker:

`power = HP% × (weapon damage × stat multiplier) × (1 + nearby allies × 0.5)`

| Situation | Response |
|---|---|
| Own power ≥ 1.2× the attacker's | **Fight** |
| Own power below that, and the target is faster or the attacker is ranged | **Flee** |
| Otherwise | **Comply**: hand over the demanded items. If the attacker had chosen to attack, there's nothing to comply with, so the target flees or fights |

### 6.8 Alliance defence
Faction members within 10 cells of an attacked member join the fight, unless they are fleeing or are critical themselves.

---

## 7. Combat, Surrender and Death

### 7.1 Combat
- Melee: the target must be within reach, and damage = `weapon base × STR multiplier`.
- Bow: the shot needs line of sight. **Walls block arrows (agreed)**. It hits with the hit chance from §3.2 and does `10 × AGI multiplier` damage. Each shot uses 1 arrow.
- XP: STR XP for each melee hit landed, AGI XP for each shot fired.
- Walls take damage only incidentally (for example, from an arrow aimed past them). In v1 no agent targets walls on purpose; deliberate raids are planned for a later sprint.

### 7.2 Pleading and surrender **(agreed)**
1. When HP drops to **20% or below**, the victim pleads, once per fight.
2. The attacker accepts with **50% chance**, adjusted by ±10% based on its opinion of the victim (starting value).
3. **If accepted, the attacker gets AUTH +1.** Then:
   - **If the attacker's faction has room** (the cap is 8, and **servants count**): the victim **becomes the attacker's servant**, leaves its old faction (losing its house slot) and joins the attacker's faction. A **lone attacker** forms a new 2-agent faction with the servant.
   - **If the faction is full:** the victim hands over the demanded items and is released. Its mood gets angrier and its opinion of the attacker drops by 50.
   - Either way, the victim gets **no happy boost**.
4. **If refused:** the fight continues to the death.
5. If a **servant** wins a fight and the loser surrenders, the new servant is assigned to the **servant's master**, because servants can't have servants.

### 7.3 Death
- The killer gets **AUTH +1 (agreed)**.
- A **loot bag** drops with the full inventory **(agreed)**. Anyone can pick it up, and it despawns after 3 minutes (starting value).
- The agent is removed from its faction and from its house's occupant list immediately. If it was the leader, the leader is recalculated. If it was a master, its servants go free (§8.3).
- **A fresh agent respawns (agreed)** with random stats (5–10) and a mood from the 50/30/20 split. It spawns at a random empty cell at least 15 cells from any agent.

---

## 8. Factions

### 8.1 Basics
- Max **8 members, including servants (agreed)**.
- **Leader = highest AUTH, with no exceptions (agreed).** Ties go to the highest CHA, then random. The leader is recalculated whenever a member's AUTH changes, a member joins or a member dies.
- The leader chooses house sites.
- **If the last member dies, the faction is disbanded (agreed).** Its fires burn out and its walls decay.
- Factions aren't tagged by mood. A gang is just a faction whose members are mostly angry. Members' moods drift toward the faction average.

### 8.2 Task board **(agreed)**
Each faction has a shared list of tasks. A solo agent has a board of one.

```
Task { type, target_cell/target_entity, required_items, claimed_by, priority }
types: PLACE_HOUSE_FIRE, BUILD_WALL, BUILD_DOOR, REFUEL_FIRE, DELIVER_ITEMS
```

- Blueprints post one `BUILD_WALL` task per perimeter cell, plus one `BUILD_DOOR`.
- An agent **claims** a task, so nobody doubles up. It gathers or fetches the materials itself, then completes the task.
- A claim lapses if the agent dies, or doesn't make progress for 60 s.
- `REFUEL_FIRE` is posted automatically when any house fire is at 3 wood or less. It has high priority.

### 8.3 Servants **(agreed)**
- A servant keeps its autonomy (needs, self-defence) but follows its master's orders above its own goals.
- Orders: **gather and deliver**, **follow and fight**, **build here**, **fuel my fire**. In v1 the master issues these by simple rules: an angry master mostly uses gather/deliver and follow; an otherwise idle master posts build orders.
- **Rebellion:** if the servant's STR is at least 1.5× the master's, it rolls a 10% chance every 2 min to rebel. Rebelling means it attacks the master in normal combat.
- **Master dies → the servant becomes a free agent:** it has no faction and no home, **keeps its items**, and **its goals reset (agreed)**.

---

## 9. AI Decision Making

### 9.1 Architecture
A **state machine with utility-scored state selection**. Agents re-evaluate their decision a few times per second (§10.2), while movement runs every frame.

States: `Idle, Wander, MoveTo, Gather, Eat, Warm, Craft, Build, Refuel, Socialise, Fight, Flee, Plead, Obey, Loot`

### 9.2 Priority layers (the first one that applies wins)
1. **Critical:** being attacked → plead, fight or flee. Fleeing after talking an attacker down.
2. **Urgent needs:** warmth < 30% → go to a fire, or place a wild fire if none is close. Hunger < 40% → eat or find berries. HP low and no threat → seek safety and rest near a fire.
3. **Orders:** a servant obeys its master's current order.
4. **Faction work:** claim and do the highest-priority task on the board.
5. **Goal ladder (fallback) (agreed).**
6. **Wander / socialise.** Happy agents drift toward others.

### 9.3 Goal ladder (fallback when an agent has no task)
1. Keep 3 or more berries in the inventory.
2. Craft an **axe**.
3. Craft a **pickaxe**.
4. Craft a **weapon** (angry agents prefer a club or bow, others a spear).
5. If there's no house, **found a house**: house fire → walls → door.
6. Stockpile wood (for fuel) and arrows if the agent has a bow.
7. Wander and explore.

---

## 10. Technical Architecture

### 10.1 Grid and pathfinding
- One world grid stores what is in each cell: a node, a wall, a door, a fire or empty.
- `AStarGrid2D` covers the whole map. Nodes, walls, fires and **all doors** are marked solid.
- **Doors:** when an agent needs a path into its own faction's house, temporarily unmark that faction's door cells, compute the path, then mark them solid again. It's single-threaded and there are few doors per faction, so it's cheap.
- Paths are cached per agent and recomputed only when blocked or when the target changes.

### 10.2 Sim clock and ticking
- An autoload `SimClock` provides `sim_delta = real_delta × speed`. **All timers (needs, fires, decay, cooldowns, respawns) use sim time (agreed).**
- Speeds: pause, 1×, 2×, 4×, 8×.
- AI decisions run at about 4 Hz per agent, with agents spread across frames (agent `i` thinks when `frame % N == i % N`). At high speeds, the sim steps several fixed sub-ticks per frame.

### 10.3 Spatial hash
A bucket grid of 8 × 8 cells, rebuilt or updated as agents move. It's used for social range, finding the nearest resource or fire, defence calls and line-of-sight candidates. Never use `Area2D` overlaps for 120 agents.

### 10.4 Rendering
- **Terrain and nodes:** `TileMapLayer`.
- **Agents:** a `Node2D` each, drawn with `_draw()`. A circle filled with the faction colour, an outline in the mood colour (green, grey or red) and a small held-item icon. 120 nodes is fine. If needed, this can switch later to a single renderer drawing them all.
- **Fires:** an orange square. Privilege zones are an optional overlay.

### 10.5 Camera and UI
| Input | Action |
|---|---|
| Scroll wheel | Zoom to the cursor |
| Right mouse drag | Pan |
| Left click on an agent | Open the inspector panel: stats, XP, needs, mood, inventory, faction, master, servants, current state and task, top opinions |
| Keys 1–5 / Space | Sim speed / pause |
| Toggle keys | Privilege zones, faction colours, agent labels |

There is also an **event log** in the corner ("#42 surrendered to #7 and became a servant", "Faction Red founded a house"). A top bar shows live counts: agents by mood, number of factions, sim time.

### 10.6 Proposed folder layout
```
res://
  Docs/
  autoload/   Config.gd  SimClock.gd  EventBus.gd  Rng.gd
  world/      World.gd (grid, nodes, respawn)  WorldGen.gd  Pathing.gd  SpatialHash.gd
  entities/   Agent.gd  ResourceNode.gd  Campfire.gd  Wall.gd  LootBag.gd
  agent/      AgentStats.gd  AgentNeeds.gd  Inventory.gd  AgentBrain.gd  states/*.gd  GoalLadder.gd
  social/     Social.gd (interaction resolution)  Memory.gd
  faction/    Faction.gd  FactionManager.gd  TaskBoard.gd  House.gd  Blueprint.gd
  combat/     Combat.gd  Items.gd (definitions, recipes)
  ui/         CameraController.gd  Inspector.tscn  EventLog.tscn  TopBar.tscn
  main.tscn
```

---

## 11. Implementation Phases

Each phase ends with something runnable that you can watch.

| # | Phase | Done when |
|---|---|---|
| 0 | **Project setup:** autoloads, Config, SimClock, camera pan/zoom, speed controls | An empty map that can be panned, zoomed and sped up |
| 1 | **World:** grid, world generation, resource nodes, berry regrowth, node respawn | The map shows forests, rocks, hemp and bushes, and nodes respawn |
| 2 | **Agents and movement:** spawning, AStarGrid2D, spatial hash, wander state, staggered ticks | 120 agents wander smoothly at 8× speed |
| 3 | **Needs:** hunger, warmth, HP; eating berries; wild fires; sim-time fire burning and destruction | Agents eat, place wild fires, warm up, and die of neglect if the needs are tuned harshly |
| 4 | **Gathering, inventory and stats:** gather states, STR/AGI XP and levelling | Agents gather and their stats level up (visible in the inspector) |
| 5 | **Crafting and durability:** recipes, item use, goal ladder steps 1–4 | Agents craft tools and weapons, tools break and get recrafted |
| 6 | **Building:** walls, doors, house fire, privilege zones, wall decay, solo blueprint and task board | Solo agents claim land, build closed houses and keep their fires fuelled. Abandoned houses decay |
| 7 | **Combat and death:** melee, bow and arrows, line of sight, loot bags, respawn | Forced fights resolve correctly and loot gets picked up |
| 8 | **Social:** moods, drift, opinions, interaction trigger and cooldown, CHA roll, authority dominance, demand / comply / flee / fight, fire sharing | Angry agents rob and attack, happy agents talk their way out and flee |
| 9 | **Factions:** formation, invites, gangs, leader rule, shared task board, multiple houses and occupant lists, defence, disbanding | Factions form and build shared houses, and new houses appear as they grow |
| 10 | **Surrender and servants:** pleading, 50/50 acceptance, servitude vs robbery release, orders, rebellion, freeing | Masters and servants show up naturally in the event log |
| 11 | **Observability and tuning:** inspector, event log, overlays, top bar, balance pass | A 30-minute run at 4× is readable and interesting |

---

## 11b. Implementation Notes (v1 build)

Where the code differs from the plan above, or adds to it:

- **Agents are data objects, not nodes.** `Agent` extends `RefCounted`, and one `AgentLayer` draws all of them each frame. This is cheaper than 120 `Node2D`s and keeps the sim logic separate from rendering.
- **Every agent is always in a `Faction`.** An unfactioned agent has a *solo* faction (one member, its own board and house). Forming or joining a faction just changes membership, and the leader's solo faction becomes the shared one. That way the house, fire, door and task board code is the same for solo agents and teams.
- **Door placement.** The door sits one column right of the fire. With the door directly below the fire, the interior of a 1-person house could only be reached diagonally past a corner, so it was effectively sealed.
- **Privilege zones are cached** in a per-cell map that is rebuilt only when a house fire starts or stops burning.
- **Failed pathfinding is cached for 10 s per agent and destination.** Unreachable fires and tasks are blacklisted for 60 s. A failed A* search floods the whole map, so failures must not be retried.
- **Idle behaviour.** Once the goal ladder is done, angry agents prowl toward nearby strangers (up to 40 cells). Happy agents sometimes seek company. Settled agents idle near their home fire.
- **Actual layout:** `core/Cfg.gd` (all tunables), `autoload/` (SimClock, EventBus), `world/` (World autoload, WorldGen, SpatialHash), `entities/`, `agent/` (Agent, Inventory, Job, Brain, GoalLadder), `social/Social.gd`, `combat/` (Combat, Items), `faction/` (Faction, Factions, House, Task, TaskBoard), `render/`, `ui/`.

### Test and tuning commands
```
# headless fast-forward, prints per-minute stats, death causes and a profile
Godot_v4.7.2-stable_win64.exe --headless --path . -- --bench=30
# windowed: fast-forward N minutes, save full-map + zoomed screenshots to user://
Godot_v4.7.2-stable_win64.exe --path . -- --shot=5
```

### First playtest observations (seed 12345)
- Performance: about 1.5 s of real time per sim minute in bench mode (about 2.5 ms per 0.1 s step), so 16× runs in real time comfortably.
- Around 30 factions and 30 complete houses form within 5 minutes. Most deaths happen in the first 15 minutes, and almost all are combat.
- **The anarchy settles.** Angry agents fall from 20% to about 6–10% by minute 30, through faction mood drift and combat deaths. Things to try first if it's too peaceful:
  - Remove the +10 mood for joining a gang.
  - Make berries scarcer.
  - Let mood drift only pull toward the *leader's* mood.
- Cold and hunger almost never kill anyone; needs are easy to meet. Try tightening `BUSH_REGROW_SECS` or the wood economy.

## 12. Out of Scope for v1 (Next Sprints)
- **Raids:** agents deliberately attacking walls and doors.
- Births and reproduction.
- Day/night cycle and night cold.
- Smarter trading economy.
- Final art (top-down Hotline Miami style sprites).
- Any player interaction with agents.

---

## 13. Open Tuning Questions to Watch in Playtests
- Is the wood economy sustainable? Watch the house fire drain (20 wood/hour) against gather rates.
- How long does it take for the first factions to appear? Is angry aggression too dominant at 20%?
- Does authority snowball? One agent with many kills dominates every interaction through the 1.5× rule.
- Do respawning fresh agents get farmed for AUTH points by strong angry agents?
- Faction cap of 8 combined with houses: do the bases stay readable on screen?
