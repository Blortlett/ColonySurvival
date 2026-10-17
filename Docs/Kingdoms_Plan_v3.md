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
