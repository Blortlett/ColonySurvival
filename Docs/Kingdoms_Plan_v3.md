# Anarchy Colony Sim — v3 Plan: Territorial Cities, Metal and the Smeltery

**Builds on:** `Docs/Kingdoms_Plan_v2.md` (v2, implemented in commits `a2dc0b9`..`dc9ea38`; implementation notes in its §10)
**Engine:** Godot 4.7.2, GDScript
**Goal of this cycle:**
- Kingdoms pack their cities tightly and push close neighbours out.
- A metal tier (metal rock, smeltery, furnace, anvil) gives combat real progression: swords, armour, metal doors, stone walls and iron raiding axes.
- Kingdoms become powerful. Gangs stay dangerous by raiding smelteries and building their own.

> As before, every number is a tunable in `core/Cfg.gd` or `combat/Items.gd`. **(agreed)** marks values decided in design. **(start)** marks starting values for playtest tuning.

---

## 0. Memory Fix (Phase 0)

The v2 build leaks objects at runtime: Godot reports about 800 leaked instances at exit, against 31 on v1. The cause is reference loops between RefCounted objects, which are never freed:
- `House.fire` ↔ `Campfire.house` (from v1)
- `House.chest` and the workshop machines ↔ `Furniture.house`
- `Raid` ↔ `Job.raid`
- possibly `Task.board` ↔ `TaskBoard.tasks`

**Fix:** break each loop. Make the back-reference a `weakref()`, or store an id and look the object up through `World`. Behaviour must not change.

**Done when:** a 12-minute bench shows far fewer leaked instances, with no script errors, and the screenshots render the same.

---

## 1. Territorial Kingdoms (Phase 1)

### 1.1 Tight packing **(agreed)**
- **Blocks:**
  - City plots are grouped into **2 × 2 blocks**. The 4 plots in a block touch, with no road between them.
  - **Roads run only around each block.**
  - Each house keeps **its own walls**; there are no shared walls. Houses in a block sit wall to wall.
- **Doors face outward:** each house's door faces the block's outer road, away from the other houses. In a 2 × 2 block every plot touches the outer road on two sides; pick the side facing the nearest road.
- **Road spurs** run from each door straight to the block's ring road.
- **Plot assignment** keeps the v2 order: centre (king's house), plaza, then houses, with workshops and smelteries further out. Fill a block before starting a new one.

### 1.2 Where a new kingdom house goes **(agreed order)**
1. **Free space right next to the leader's house:** the free plots in the leader's block, then the adjacent blocks.
2. **The nearest free plot** anywhere in the city.
3. **Push neighbours out** (§1.3), only when no free plot is close enough.

### 1.3 Pushing neighbours out **(agreed ladder, least to most violent)**
Targets are foreign houses within **22 cells (start)** of the king's house, or on plots the city wants.

1. **Invite.** If the house's group is independent, not a gang and the kingdom has room, it is invited to join.
   - **A group that joins must still rebuild on a city plot and abandon its old house (agreed).** The old house was not built for the grid.
   - It uses the v2 relocation rule: build the new house first, abandon the old one once the new one is COMPLETE.
2. **Demand they leave.** For groups that can't or won't join.
   - **The group accepts** if the kingdom's total power is at least **1.5× (start)** its own.
     - It plans a new house outside the city, beyond the kingdom's push-out radius.
     - It abandons the old house once the new one is COMPLETE.
     - Relation change: −10 (start).
   - **The group refuses** otherwise. The kingdom then **declares war** (§1.4).
3. **War and raids.** The kingdom raids the house (the v2 raid rules) until the group is gone, leaves, or peace comes.
   - Gangs skip steps 1 and 2: a gang house in range means war straight away.

### 1.4 War declaration from push-outs
- A refused demand is a war declaration in its own right. It does not need the −40 relation roll.
- The kingdom-wide war and peace rules from v2 apply unchanged.

### 1.5 Demolish **(agreed)**
- A new task, **DEMOLISH**, posted on the kingdom board. Kingdom members tear down abandoned walls, doors, floors and furniture inside the city area, plus anything blocking a plot or road. **No refund.**
- This replaces waiting for 10 minutes of decay inside cities.
- Chests that are demolished spill their contents as a loot bag ("chest destroyed").

---

## 2. Metal Rock and the Tier-2 Pickaxe (Phase 2)

### 2.1 Metal rock **(agreed: dispersed and rare)**
- **A new resource node** that yields **raw iron**.
- **Spread out, not clustered**, at about **1/6 of normal rock density (start)**, with **15 raw iron per node (start)**.
- It respawns like other nodes, never on city plots or roads.
- Nothing stops a group mining a node inside another group's zone (gathering isn't restricted by zone). Fighting over metal is out of scope (§7).

### 2.2 Tier-2 pickaxe **(agreed)**
- Made from processed wood and processed stone at a **workshop**.
  - Recipe: **1 plank + 2 cut stone + 1 handle (start)**.
  - Durability: **150 (start)**.
- **It is the only tool that can mine metal rock (agreed).** Without it, agents cannot gather metal at all.
- On normal rock it works like a normal pickaxe.

---

## 3. Smeltery and the Stone Tier (Phase 3)

### 3.1 Smeltery building **(agreed)**
- **A third building kind** (HOUSE / WORKSHOP / SMELTERY), reusing the house code like the workshop does.
- **Walls must be stone (agreed).** Built with cut stone only, never raw stone. Its door can start as a basic or reinforced door.
- **Interior: 6 × 5 (start)**, with every tile floored. It holds:
  - the **smeltery fire**: claims land and needs fuel, like a workshop fire
  - a **furnace**
  - an **anvil**
  - **2 storage crates (agreed)** for raw and processed goods
- **Placement:** it follows the workshop rules (outside other sides' zones; its zone yields to house zones). In a city it goes on a ring-2+ plot.
- **Who builds it (agreed):** any group, **gangs included**. Gangs actively aim for one. Kingdoms aim for 1 to start.
- **Access:** its door opens for the whole kingdom, like a workshop's.

### 3.2 Crates
- **60 slots each (start).** Usable by every member of the owning side.
- **Stocking goal (start):** spare raw iron, iron bars and one spare set of gear. Surplus metal goods are deposited here.
- When destroyed or decayed, their contents drop as a loot bag ("chest destroyed").

### 3.3 Stone tier for houses **(agreed: houses go stone too)**
| Piece | Tier 0 | Tier 1 | Tier 2 |
|---|---|---|---|
| Wall | 2 wood, 100 HP | 2 planks, 250 HP | **2 cut stone, 400 HP (start)** |
| Door | 3 wood + 1 hemp, 80 HP | 2 planks + 1 handle, 200 HP | **Metal door: 2 iron bars, made at the anvil (agreed), 500 HP (start)** |
| Chest | 5 wood, 30 slots | 4 planks + 1 handle, 60 slots | **Iron-bound: 2 iron bars + 2 planks, 90 slots (agreed tier, start numbers)** |

- Upgrades follow the v2 rule: carry the materials, break the old piece (no refund), then place the new one.
- **Order:** house first, then the smeltery's door, then the workshop.

---

## 4. Furnace and Anvil (Phase 4)

### 4.1 Furnace **(agreed)**
| Input | Output | Time |
|---|---|---|
| 1 raw iron + 1 wood | 1 iron bar | 8 s (start) |

Agents carry the inputs to the furnace and process them in batches, like the sawmill and stone cutter.

### 4.2 Anvil **(agreed)**
| Item | Recipe |
|---|---|
| Sword | 1 iron bar + 1 handle |
| Helmet | 1 iron bar |
| Chest piece | 1 iron bar |
| Leg armour | 1 iron bar |
| Metal door | 2 iron bars |
| Iron raiding axe | 2 iron bars + 1 handle |

Anvil items are crafted only at a smeltery.

---

## 5. Combat Progression (Phase 5)

### 5.1 Sword
- **20 damage (start)** (club 14, spear 9), reach 1.5, cooldown 1.0 s, **durability 150 (start)**.
- It is the preferred melee weapon when an agent owns one.

### 5.2 Armour
| Piece | Damage reduction | Durability |
|---|---|---|
| Helmet | 10% (start) | 100 hits (start) |
| Chest piece | 20% (start) | 100 hits (start) |
| Leg armour | 10% (start) | 100 hits (start) |

- The reductions add up: a full set gives **−40%**.
- **Worn armour takes no inventory slots.** Spare pieces carried in the inventory do take slots.
- Every hit taken costs each worn piece 1 durability. A piece at 0 breaks.

### 5.3 Iron raiding axe **(agreed)**
- About **twice the wall damage of the wooden raiding axe (start):** 25 × 5 = 125 per hit.
- Against a metal door (500 HP) that is about 4 hits, against 8 with the old axe.
- Durability: **80 (start)**.

### 5.4 Who gets gear **(agreed)**
- **Priority:** the leader first, then fighters (members who aren't servants), then servants.
- **Agents equip the best item they own automatically.**
- **Gear in the group's crates or chest** goes to the highest-priority member who lacks it.

### 5.5 Power and loot **(agreed)**
- **`Agent.power()` includes the sword's damage and the armour's damage reduction.** Comply / flee / fight decisions, the raid target choice and the push-out strength check all see armoured agents as strong.
- **Worn gear drops into the loot bag on death**, so killers can strip armoured victims.

### 5.6 Gangs **(agreed)**
- **Smelteries are prime raid targets.** A gang's target score counts crate contents, and iron and gear count extra.
- **Gangs aim to build their own smeltery**, after their workshop. On their ladder: workshop → smeltery → iron raiding axes and gear.
- It is fine if their workstations are understaffed.

### 5.7 No repair **(agreed)**
Gear breaks and gets replaced. That keeps the metal economy flowing.

---

## 6. Viewer (with each phase) **(agreed)**
- **Agent panel:** equipped sword and armour, with durability.
- **Smeltery panel:**
  - crate contents
  - what the furnace is processing
  - who is working at it
  - the anvil recipes
- **Armoured agents** get a grey outer ring.
- **New visuals:**
  - stone walls (grey blocks)
  - metal doors (dark iron with rivets)
  - the iron-bound chest
  - furnace (glowing), anvil and crates
  - metal rock (a rock with rust-orange flecks)
- **Group panel:** the smeltery row, plus push-out state ("demanding F12 leave", "F12 refused: war").
- **Bench line:** metal nodes, raw iron and bars in circulation, gear counts (swords, armour pieces), smelteries, stone walls and metal doors.
- **--shot:** adds a smeltery close-up.

---

## 7. Out of Scope This Cycle
- Kingdoms claiming or fighting over metal deposits. A kingdom stays where it was founded.
- Gear repair.
- Growing the map. Tighter cities should free up space; re-check after Phase 1.
- Mood and anarchy tuning. First see whether push-out wars keep the world from settling.

---

## 8. Implementation Phases **(agreed order)**

Each phase ends with something runnable and gets its own commit. Each is checked with `--bench` and `--shot` before moving on.

| # | Phase | Done when |
|---|---|---|
| 0 | **Memory fix:** break the RefCounted loops | Leaked-instance count at exit drops sharply; behaviour unchanged |
| 1 | **Territorial kingdoms:** 2 × 2 blocks, outward doors, placement order, invite / demand-leave / war ladder, DEMOLISH | Kingdom houses pack wall to wall next to the leader; nearby groups get invited, leave, or are fought; abandoned pieces are demolished |
| 2 | **Metal:** metal rock nodes, tier-2 pickaxe, raw iron | Groups craft tier-2 pickaxes and mine raw iron; nobody mines metal without one |
| 3 | **Smeltery and stone tier:** smeltery building with stone walls, fire, furnace, anvil, 2 crates; stone walls, metal doors, iron-bound chests as upgrades | Groups (gangs too) build smelteries; houses get stone walls and metal doors |
| 4 | **Furnace and anvil:** iron bars, swords, armour, metal doors, iron raiding axes | Iron bars and gear appear and flow through the crates |
| 5 | **Combat progression:** sword and armour stats, gear priority, auto-equip, power includes gear, gear drops on death, gangs target smelteries | Armoured kingdom fighters win most fights; gangs raid smelteries and wear stolen gear |

---

## 9. Things to Watch in Playtests
- **Packing vs. war:** do push-outs cause constant war around every capital, or settle into tight cities with a quiet edge?
- **Metal scarcity:** at 1/6 rock density and 1:1 smelting, is there enough iron for a few armoured squads per kingdom? Too much makes everyone armoured.
- **Gang survival:** do gangs ever get a smeltery? If not, do smeltery raids keep them armed?
- **Wood and stone drain:** stone walls (2 cut stone = 4 stone each) and furnace fuel compete with v2's upgrades.
- **Performance:** v2 runs at about 2.5–3 s of real time per sim minute in bench mode. Keep 16× running in real time.

---

## 10. Implementation Notes (v3 build)

Phases 0–5 are each one commit (`4f1b956`, `947408f`, `8c2ec05`, `b841f77`, `e3aeeb3`, `62b92ed`). Where the build differs from the plan above, or fills in something the plan left open:

### Memory fix (0)
- `Campfire.house`, `Furniture.house` and `Task.board` are now weak references (a property over a `WeakRef`, so call sites are unchanged). `Raid` ↔ `Job.raid` turned out not to be a loop.
- A cleared task board marks its tasks done, so agents holding one stop cleanly.
- **Result:** a 12-minute bench gives identical output and leaks **0** instances at exit (was 802). The "6 resources still in use" error is gone too.

### Territorial kingdoms (1)
- **Grid:** plot (0,0) is the king's house, the bottom-left plot of block (0,0). The grid is anchored so that house sits in its plot's inner corner and its v2 bottom door faces the outer road. Blocks are 21 cells apart (two 10-cell plots plus the ring road). Cities reach out to block ring 2.
- **Doors:** a `House` now has a door side. City houses sit in their plot's inner corner and face the outer side with the smaller gap to the road. Houses outside cities keep bottom doors.
- **Plaza:** goes on plot (0,1), across the road from the king's door, so the leader's own block stays free for houses.
- **Workshops and smelteries:** take plots outside the leader's block (block ring 1+), not the v2 plot ring 2+.
- **Placement order:** candidate plots are sorted by block ring, then by blocks already started (fill a block first), then by distance from the centre.
- **Moving closer (gap filled):**
  - Early on, close plots are often blocked, mostly by abandoned fires and old walls; demolition clears them.
  - Groups that got a far plot meanwhile move whenever a free plot opens in a nearer block ring, using the v2 rule: build first, abandon once COMPLETE.
  - Without this, the leader's block stayed empty while groups sat two blocks out.
- **"Close enough"** means the leader's block and the adjacent ones (block ring ≤ 1). A search that has to go further, or fails, marks the city as short of room for 60 s.
- **Ladder timing:** each step waits one check (`PUSH_CHECK_SECS` 10 s), so the panel can show inviting → demanding → leaving / war.
  - An invite is accepted if relations are ≥ −10 (`INVITE_MIN_RELATION`, start) and the two sides are not at war.
  - Power is the sum of members' `fight_power()` (HP-scaled best damage, gear included from Phase 5, no ally bonus).
- **Gaps filled in the ladder:**
  - A group that agreed to leave but is still there after 6 minutes means war.
  - After peace, a 5-minute truce comes before the ladder restarts.
  - A lone settler (a solo agent) can't wage war, so it just has to leave.
  - A house of another kingdom standing on its own city plot can't move, so it means war straight away.
  - Blockers of wanted plots beyond the 22-cell radius are only picked from groups outside any kingdom, one at a time, so cities don't start kingdom wars just to expand.
- **No settling on others' land:** nobody plans a building within 24 cells of a foreign kingdom's centre. Groups told to leave search for a site past the radius, away from the king.
- **Demolition scope:**
  - The city area is the leader's block plus the adjacent blocks, plus every block holding a plot, with their ring roads.
  - Any wall, door, floor, furniture piece (not the kingdom board) or abandoned house fire there that is inside no live building's footprint is torn down.
  - It takes 2 s per piece (`DEMOLISH_SECS`, start). Walls go first, so floors and chests inside can be reached.

### Metal (2)
- **Metal rock:** about 200 nodes are scattered in a separate pass after the normal world generation, at least 6 cells apart (`METAL_MIN_GAP`). Respawns pick random spots, never next to existing nodes.
- **Mining:** takes 8 s per raw iron with the tier-2 pickaxe (`GATHER_METAL`, start). Clearing a metal node without one yields nothing.
- **Gap filled, who mines:** a group with a workshop gives one member (`MINERS_PER_GROUP`) a tier-2 pickaxe. That member mines towards 20 raw iron (`IRON_STOCK_GOAL`), counting the group's members, chests and crates.
- A tier-2 pickaxe also counts as the basic pickaxe on the goal ladder.
- **Storage:** raw iron is always deposited, in a smeltery crate if one is in range, otherwise in the chest.

### Smeltery and stone tier (3)
- **Machine costs (start, the plan gave none):**
  - furnace: 4 cut stone + 4 stone
  - anvil: 4 raw iron + 2 wood
  - crate: 4 planks + 1 handle
- **Layout:** furnace and anvil in the top corners, crates in the bottom corners. Floors are wood like every other building.
- **When groups build one:**
  - Groups build a smeltery after their house and workshop are reinforced.
  - Gangs build one straight after their workshop.
  - Independent groups and kingdoms aim for 1 each (`KINGDOM_SMELTERIES`).
- **Stone tier timing:** starts once the side has a working smeltery.
- **Upgrade tiers:** upgrade tasks now carry a target tier, so a tier-0 wall can go straight to stone.
- **Metal doors and iron-bound chests** are only posted once the anvil and furnace recipes exist. In practice they first appeared with Phase 4.

### Furnace and anvil (4)
- **Making metal doors:** the metal door is an item made at the anvil (2 bars, 6 s, start). Material sourcing now follows processing chains: door → bars → raw iron + wood.
- **Gap filled, smeltery staffing:** one agent per machine at a time (a 120 s claim). The furnace keeps the side's stock at 6 bars (`BAR_STOCK_GOAL`), up to 4 per trip. The anvil then makes one spare set of gear (sword, helmet, chest piece, leg armour) for the crates.
- **Iron raiding axe:** raiders craft one instead of the wooden axe when there is an anvil and at least 2 iron on hand. Its wall damage (25 × 5) and 80 durability went in here, with the item, rather than in Phase 5.

### Combat progression (5)
- **Armour storage:** worn armour lives in `Agent.worn`, outside the inventory. Agents put on any armour they carry for an empty slot, on every think.
- **Gear priority:** applies within a group. A member takes a piece from the side's chests or crates only if no higher-ranked member of its own group lacks it.
- **Gangs and smelteries:** a gang may raid a smeltery of a group up to 4 members bigger than it would take on for a house (`RAID_SMELTERY_SIZE_BONUS`, start).
  - Each unit of iron in the target's crates counts 3× in the gang's score; gear counts 6×.
  - A sacked smeltery's crates are emptied like a chest.
- **Bench line** now also prints:
  - metal nodes, raw iron, bars, crate contents
  - tier-2 picks, swords, armour pieces, iron axes
  - smelteries (working, gang-owned), stone walls, metal doors, iron-bound chests
  - worn gear and armoured agents
  - kills between armoured and unarmoured agents
  - smeltery raids
  - push-out counts and demolitions
- **`--shot`** adds `shot_smeltery` and `shot_gear`.

### Later change: paving (Performance Plan A2)
- **Deviation from v2 Phase E:** a city no longer paves every road. It paves only the shortest road links from the king's door to each other finished building's door (`Cities.paving_cells`). The plaza and the rest of the roads stay stone, so cut stone is left for the smeltery and the stone tier.

### First playtest observations (seed 12345, 60-minute bench)
- **Performance:**
  - Real time per sim minute in bench mode: about 2.8 s after Phase 1, 3.3 s on average after Phase 5, with peaks of 4–5.5 s per minute after minute 50.
  - 16× is at the edge of real time late in the game.
  - The biggest costs are `run_TASK` (material sourcing and pathing) and the per-second decay loops.
- **Packing:**
  - The leader's block fills wall to wall once early blockers are demolished, by about minute 25.
  - By minute 60: 4 kingdoms holding 18 groups, 32 plots, about 1,600 road cells (800 paved) and about 1,800 pieces demolished.
- **Push-outs:**
  - 16 invites, 14 joins, 3 groups left, 5 push-out wars in 60 minutes.
  - One push-out war around minute 30–36 was very bloody: about 55 deaths in 6 minutes (deaths 61 → 116).
  - After that, the edge stays mostly quiet.
- **Metal:**
  - First tier-2 picks at minute 9, first smeltery at minute 10, first iron bars at about minute 25, first gear at about minute 40.
  - By minute 60: 19 swords, 37 worn armour pieces on 14 armoured agents, 28 metal doors, 19 iron-bound chests and about 620 stone walls.
  - Raw iron piles up (about 250), mostly in chests of groups without a smeltery. The bar goal of 6 per side is the bottleneck.
- **Armour wins:** armoured agents won 2 of 2 kills against unarmoured agents. That sample is too small, and came late.
- **Gangs:**
  - Gangs did build smelteries early (3 of the first 3, by minute 10), but lost them as they dissolved.
  - Gangs are gone well before gear exists, so no smeltery raids and no gang members wearing stolen gear were seen.
  - A forced gang next to a stocked smeltery also dissolved within a minute.
  - User decision: gangs dying out is fine for now and will be addressed later. The smeltery-raid scoring is in place but unverified in a live run.
