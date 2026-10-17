# Anarchy Colony Sim — Quick Fixes and Performance Plan

**Status: ready to build.**
**Builds on:** v3 (`Docs/Kingdoms_Plan_v3.md`, implementation notes in §10).
**Goal:**
- Three small gameplay fixes.
- Then make the sim run faster when time is sped up, and keep frames smooth at any speed. This prepares for the player controller (`Docs/Player_Controller_Plan.md`), which needs a smooth 1×.

---

## Part A — Quick fixes (one commit)

### A1. Floor under house fires
- Today the house fire cell has no floor tile: the v2 rule is "every interior cell except the fire (agreed)", so grass shows around the fire.
- **Fix: render only.** Draw a floor tile under every house, workshop and smeltery fire. Leave `floor_cells`, wood costs and decay alone, so the agreed rule doesn't change.

### A2. Pave only the roads that link buildings
- Today paving (`UPGRADE_ROAD`) starts once the road stage is done and a kingdom workshop is working, and then paves every city road, the plaza around the kingdom board included. That spends the cut stone the smeltery and the stone tier need.
- **Fix (agreed):** paving can still start at any time (no smeltery needed), but only the roads that connect buildings are paved: the shortest road links from the king's door to every other finished building's door. The plaza and other roads stay stone.

### A3. Dropped (agreed)
- The first draft made groups wait for their own smeltery before an alliance roll could form or join a kingdom. A bench showed kingdoms then formed only near minute 52.
- **User decision:** groups ally before they have a smeltery. They relocate into the city anyway, so building a smeltery each first is wasted work. `Kingdoms.try_ally` is unchanged.

**Done when:** a bench shows no script errors, kingdoms still form, and only building links get paved. A screenshot shows floor under the fires.

---

## Part B — Performance

### Baseline (seed 12345, 60-minute headless bench, v3 build)
- 197 s real time, about 3.3 s per sim minute on average, with peaks of 4–5.5 s after minute 50.
- Profile:

| Section | Time | Likely cause |
|---|---|---|
| `run_TASK` | 67 s | material sourcing re-scans storage and machines; walking |
| `think` | 37 s | every agent, 4× a second |
| `run_GATHER` | 25 s | |
| housekeeping | 17 s | per-group house and task upkeep |
| `think_social` | 17 s | spatial social scans every think |
| `world_timers` | 15 s | per-second decay loops over every wall, floor and furniture piece |
| `astar` | 8 s | |

- **The bench is headless, so it hides rendering cost.** Rendering is measured separately (B1).

### B0. Measure first
- Split `run_TASK` into sub-sections in the bench profile: obtain step, chest step, process step, move, perform. That shows what dominates.
- Add a windowed frame-time measurement: average and worst frame milliseconds at 1× and 16×, in a fixed camera view after N sim minutes.
- Record the before numbers in this doc.

### B1. Cache the static drawing (windowed game)
- `DynamicLayer._draw` redraws every road, floor, wall, door and furniture piece on every frame (thousands of rectangles).
- **Fix:**
  - Move roads, floors, walls, doors and furniture into a cached layer that redraws only when one of them changes (a dirty flag, like `StaticLayer`), or into a `TileMapLayer`.
  - Animated things stay in the per-frame layer: fires, the furnace glow, raid outlines, loot bags, zone overlays.
- Wall damage shading needs the cached layer redrawn when a wall's HP changes. Throttle that (at most a few times a second).

### B2. Event-driven decay
- Only pieces outside protection decay. Protection changes only when zones rebuild, a piece's owner changes, or pieces are placed or removed.
- **Fix:** keep a set of unprotected pieces. Rebuild it on zone changes and on placement or ownership changes, and tick only that set each second.
- **Done when:** `world_timers` drops by most of its 15 s, and decay timings match the current build.

### B3. Lighter thinking for idle agents
- Agents that are wandering, warming up, or in a long gather or task don't need to think 4× a second.
- **Fix:** a per-job think interval (start: 0.25 s in a fight, flee or raid; 0.5 s working; 1.0 s idle or wandering). Anything that interrupts (being attacked, needs) still reacts immediately through the existing hooks.
- The social scans (`Relations.meet`, `Social.scan`) follow the same interval.
- **Watch:** fights, robberies and meetings must keep about the same rates. Compare the bench's kill, servant, trade and kingdom numbers.

### B4. Cache group lookups
- `Stock.storages()`, `Factions.shared_workshops()` / `shared_smelteries()` and `Factions.nearest_machine()` rebuild lists on every call, often several times per agent per step.
- **Fix:** cache them per group (or per kingdom) for about 1 s, or clear the cache on building changes.
- **Watch:** decisions must not use a stale machine or chest. Check that the object still exists before using it, as the code already does.

### B5. Smaller wins (only if B0 shows they matter)
- `TaskBoard.claim` loops over every task, and `_shell_done` loops again for each door task. Index tasks by house.
- `World.house_at` and `all_houses` scan every faction. Keep a building index (an interior-cell lookup) updated on plan and destroy.
- Throttle failed `plan_house` searches more aggressively (`plan_house_fail` was 7 s).

### Not now
- **Threads:** the shared RefCounted state and `find_path` toggling A* points aren't thread-safe. A single sim thread separate from rendering is possible later, for smoothness rather than throughput.
- **C# or C++ for the hot loops:** the big throughput jump if the GDScript fixes aren't enough. Revisit after B4.
- **Level of detail by camera or player distance:** fits better once the player exists.

### Rules
- **Behaviour must stay the same, or near enough.**
  - Each step is its own commit, checked with `--bench=60` (no script errors) and `--shot` (screenshots render the same).
  - Steps that keep the sim deterministic (B1, B2, B4, B5) should give identical bench lines.
  - B3 changes timing, so compare rates instead.
- Record before and after numbers for each step in an "Implementation Notes" section at the end of this doc.

**Done when:** the 60-minute bench runs at least 30% faster than 197 s, and windowed frames at 16× hold 60 fps in the standard view (or the remaining bottleneck is written down).

---

## Implementation Notes

All steps are **web-safe**: GDScript only, no threads, no C# or native code, nothing outside what the web export already runs. Bench numbers are seed 12345, 60-minute headless bench, on the dev PC; run-to-run timing noise is about ±5%.

### Part A (`31672c3`)
- A1 as planned. A2 and A3 changed by user decision before the build (see Part A above): paving goes to building links only, and A3 was dropped.
- **Bench after Part A:** 203 s (the plan's 197 s baseline was before Part A). Kingdoms form from minute 6; 5 kingdoms (21 groups) by minute 60; 1,813 road cells, 454 paved (about 800 before A2). No script errors.

### B0. Measure first
- **Profile sub-sections** (bench only): `TASK.obtain` with `obtain_chest / process / pick / gather` under it (also for `CRAFT`), `TASK.move`, `TASK.perform.<type>`, `gather_node_search`, `path_doors` (the door opening around each A* search), `decay` and `wars` inside `world_timers`, `think_raid_task` and `think_ladder` inside `think`, and `hk_houses / plan_house / workshop_goals / relocate / raids` inside housekeeping.
- **`--frames=N`** (windowed): fast-forwards N sim minutes, then times 300 frames at 1× and at 16× in two fixed views, the whole map (the default camera) and the biggest city (zoom 1.1). Vsync is off, so the numbers show the real cost. `sim` is the part of each frame spent stepping the sim.
- **Bench with profiling:** 212 s, bench lines identical to Part A.

| Section (60 min) | ms |
|---|---|
| `run_TASK` | 64,541 |
| — `TASK.obtain` | 32,576 |
| —— `obtain_gather` | 16,250 (almost all `gather_node_search`) |
| —— `obtain_process` | 10,630 (walking to the machine) |
| —— `obtain_pick` / `obtain_chest` | 803 / 71 |
| — `TASK.move` | 7,720 |
| — `TASK.perform.*` | about 4,500 (`CLEAR_NODE` 2,163, `DEMOLISH` 1,104) |
| `think` | 42,710 (`think_ladder` 9,994, `think_raid_task` 3,936) |
| `run_GATHER` | 19,466 |
| `housekeeping` | 17,883 (`hk_houses` 7,716, `hk_workshop_goals` 5,451, `hk_plan_house` 3,433) |
| `think_social` | 17,661 |
| `gather_node_search` (all callers) | 16,271 |
| `world_timers` | 15,830 (`decay` 13,150) |
| `run_WANDER` | 14,716 |
| `astar` | 12,360 (+ `path_doors` 5,779) |

- **Windowed frames before B1** (minute 60, about 1,640 walls, 1,400 floors, 1,800 roads):

| View | 1× avg / p95 / worst | 16× avg / p95 / worst | sim per frame (1× / 16×) |
|---|---|---|---|
| map | 176 / 466 / 501 ms | 463 / 631 / 741 ms | 12 / 126 ms |
| city | 154 / 163 / 505 ms | 465 / 679 / 737 ms | 9 / 114 ms |

- **Reading:** in the window, drawing costs far more than the sim: about 150 ms of a 1× frame is not sim time. B1 comes first. Of the sim cost, the node search (a new find, not in the plan) and decay are the clearest targets.

### B1. Cache the static drawing
- **Pieces cached:** `render/PieceLayer.gd` (a child of `DynamicLayer`, drawn behind it) holds the zone overlays, roads, floors, the floor under fires, walls, doors and furniture. It redraws when `World.pieces_version` (bumped on placing or removing a wall, floor, road, furniture piece or fire, on wall or floor HP changes, and on house loss or abandonment) or `zone_version` changes, at most every 0.25 s, plus a 1 s refresh for anything not flagged (blueprint states, colours).
- **Per frame** (`DynamicLayer`): fires, the lit furnace glow, crate iron marks, raid outlines and loot bags.
- **The bigger find: `draw_circle`.** The frame timing showed per-frame `_draw` of bushes and fires alone at about 67 ms, and the tree layer at about 160 ms per redraw. Each `draw_circle` builds its own polygon, and those don't batch. Every filled circle (trees, hemp, bushes, berries, agents) is now one shared mipmapped white disc texture, tinted per draw (`render/Disc.gd`). It looks the same, with slightly smoother edges.
- **Trees and bushes:** `StaticLayer` redraws at most every 0.25 s. Bushes moved there (redrawn when berry counts change), so they still draw under walls.
- **`--frames`** also prints `_draw` milliseconds per frame for each layer.
- **Bench:** 197 s, lines identical to B0 (B1 changes rendering only).

| Minute 60 | Before (B0) avg / p95 | After (B1) avg / p95 / worst | sim per frame |
|---|---|---|---|
| map 1× | 176 / 466 ms | 14.1 / 23.7 / 58.8 ms | 4.1 ms |
| map 16× | 463 / 631 ms | 149 / 196 / 219 ms | 120 ms |
| city 1× | 154 / 163 ms | 11.7 / 15.2 / 61.0 ms | 2.5 ms |
| city 16× | 465 / 679 ms | 147 / 189 / 206 ms | 116 ms |

- **Reading:** 1× now runs at about 70–85 fps. At 16× the frame is now almost all sim: the main loop catches up up to 2 sim seconds (20 steps) per frame, so a slow sim makes long frames. The cached piece layer costs about 13 ms per frame at 16× (one redraw of about 50 ms every 0.25 s, since decay shading changes every sim second). Worst 1× frames (about 60 ms) are those redraws plus the housekeeping or kingdom tick.
- **Web-safe:** yes (canvas drawing and an `ImageTexture` only).
