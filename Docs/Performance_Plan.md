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

### B2. Event-driven decay
- `World` keeps the unprotected walls, floors and furniture in three lists, in the same order as the piece dictionaries, so pieces decay and break in the same order as before.
- **Full rescan** when `zone_version` (fires lit or out, kingdom changes) or the new `protect_version` (house abandonment changes owners, a faction disbands) has changed since the last tick. Otherwise only pieces placed since the last tick are checked and appended (new dictionary keys go last, so order holds), and removed pieces are dropped.
- **Bench:** 189 s, lines identical to B1, so decay timings match.

| Minute 60 profile | Before (B0) | After |
|---|---|---|
| `world_timers` | 15,830 ms | 5,443 ms |
| `decay` | 13,150 ms | 3,241 ms |
| full rescans | 3,600 (every second) | 422 |

- **Web-safe:** yes.

### B3. Lighter thinking for idle agents
- **Per-job think interval:** 0.25 s for fights, flight, raids, defence and having no job; 0.5 s for everything else (`Cfg.THINK_WORK`, `Cfg.THINK_IDLE`). A job ending, or a job set from outside `think` (being attacked, fleeing, a raid call), brings the next think forward to that job's interval, so interruptions still react at once.
- **Deviation 1, social scans stay at 0.25 s:** `Relations.meet` and `Social.scan` keep their own 0.25 s timer between slower thinks. With the scans slowed as planned, fights fell by about 45% and raids by half: agents passing each other were missed.
- **Deviation 2, idle at 0.5 s, not 1.0 s:** with wandering, idling and warming at 1.0 s, raids roughly doubled and kills rose by half (more wars, which raids keep alive). At 0.5 s the rates match.
- **Bench tools added:** `--seed=N` (overrides `Cfg.SEED`), and end-of-bench counters `social:` (trades, robberies, group meetings, fights started, thinks) and `fight sources:` (who called `Combat.start_fight`).
- **Rate comparison:** 60-minute benches, mean over seeds. The baseline is this code with every interval at 0.25 s (9 runs, seeds 12345 and 1–7). Single runs swing a lot: the same seed gave 76 or 58 kills after a change that only moved one early social check.

| Mean per run | Baseline (n=9) | Plan as written (n=4) | Scans 0.25, idle 1.0 (n=8) | **Built: scans 0.25, 0.5 / 0.5 (n=4)** |
|---|---|---|---|---|
| kills | 65 | 55 | 111 | **56** |
| fights started | 146 | 111 | 246 | **122** |
| raids (won + lost) | 7.2 | 4.3 | 17.0 | **7.0** |
| trades | 5,321 | 5,394 | 5,048 | **5,445** |
| group meetings | 1,754 | 1,937 | 1,660 | **1,971** |
| robberies | 8.2 | 10.8 | 8.0 | **8.2** |
| servants (avg over the run) | 12.4 | 10.5 | 11.9 | **9.1** |
| kingdoms at minute 60 | 5.8 | 6.0 | 5.4 | **5.5** |
| thinks | 1.73 M | 0.80 M | 0.82 M | **0.90 M** |

- **Bench (seed 12345):** 173.8 s (B2: 188.7 s). `think` 42.7 s → 26.2 s, `think_ladder` 10.0 → 6.6 s. `think_social` stays about 17 s, since the scans keep their rate.
- **Watch:** servants average a little lower (9.1 vs 12.4). That is within the seed noise seen for single runs, but worth checking in a playtest.
- **Web-safe:** yes.

### B4. Cache group lookups
- `Factions.shared_workshops / shared_smelteries`, a new `Factions.machine_houses` (workshops then smelteries, the order `nearest_machine` and `find_path` use) and `Stock.storages` are cached per group.
- **Exact invalidation, not a 1 s timer:** the cache is cleared whenever `World.buildings_version` moves. It is bumped when a group's building list changes, a house is abandoned, a faction disbands, kingdom membership changes, and furniture is placed or removed. Nothing can go stale, so the existing "object still exists" checks are enough, and the sim stays deterministic. Callers treat the cached arrays as read-only (they already did).
- **Bench:** 172.2 s (B3: 173.8 s, within noise), lines identical to B3.
- **Profile:** `think_ladder` 6,576 → 5,568 ms, `path_doors` 4,475 → 3,651 ms, `run_CRAFT` 1,863 → 1,715 ms. Everything else is unchanged. These lookups weren't a big cost on their own: the time in `TASK.obtain` is the node search and the walking (B5).
- **Web-safe:** yes.

### B5. Smaller wins
B0 and B4 showed where the remaining time went, so B5 took the items that mattered and skipped the rest. Everything here gives the same results as before, so bench lines are identical to B4.
- **Node search** (a new item from B0, the biggest one): `World.nearest_node` visits only each ring's edge buckets (it used to loop the whole square and skip the inside), in the same order, and skips buckets that can't hold a closer node. `gather_node_search` 9,972 → 5,174 ms.
- **House site search** (instead of the plan's "throttle `plan_house` harder", which would change behaviour): `_site_ok`'s checks are all pure, so the cheap per-cell ones now run first. `house_fire_spacing_ok` and `footprint_clash` loop the factions directly instead of building `all_houses()` for each of the 80–120 candidate sites. `plan_house_fail` 7,020 → 656 ms, `hk_workshop_goals` 5,729 → 2,122 ms, `hk_plan_house` 3,385 → 761 ms.
- **No string keys:** the unreachable-cell blacklist, the failed-path memo and the group-pair cooldowns are keyed by `Vector3i` / `Vector4i` instead of formatted strings. They behave the same, and the formatting is no longer paid on every node, chest and machine check.
- **Skipped, because they don't matter:**
  - `TaskBoard.claim` / `_shell_done` index: the whole task pick (`think_raid_task`) is 2.5 s.
  - `house_at` building index: timed at 2.2 s in total, so it isn't worth the bookkeeping.
- **Bench:** 157.7 s, then 159.3 s with the `social_meet` split added to the profile (B4: 172.2 s). `housekeeping` 17.6 → 11.0 s, `run_TASK` 59.4 → 56.1 s.
- **Web-safe:** yes.

### Result
- **60-minute bench:** 159 s, against 197 s in the plan and 203 s after Part A. That is **19% faster than the plan baseline (22% faster than Part A)**, short of the 30% goal (138 s).
- **Windowed frames (minute 60, map view):**
  - **1×:** 11.7 ms average (about 85 fps), 15 ms p95. It was 176 ms before B1.
  - **16×:** 107 ms average, 82 ms of it sim (city view 128 / 100 ms). It was 463 ms.
  - **60 fps at 16× is not met.**
- **Remaining bottleneck, written down:**
  - **The sim at 16×:** late in the game a sim step costs about 4.8 ms, so 16× (160 steps per real second) takes about 77% of a CPU core for the sim alone. Every frame also carries about 9 ms of drawing and engine overhead (at 1× the frame is 11.7 ms with 2.5 ms of sim).
  - **Catch-up feedback:** the main loop catches up to the full speed every frame (up to 20 steps), so frames settle at about 100 ms. Short frames also run extra partial steps, because a step costs the same whatever its `dt`.
  - **Biggest remaining sim costs (B5 profile):** `Social.scan` and `Relations.meet` 17 s, walking (`move_to` in tasks, gathering and wandering) about 25 s, A* 8.6 s plus 4 s of failed wander searches, house upkeep (`hk_houses`) 7 s.
- **Next options, not built (behaviour or design decisions):**
  1. **A frame time budget for the catch-up:** run sim steps until about 10 ms of the frame is used, and let the speed fall below 16× when the sim can't keep up. That gives smooth frames at any speed, but 16× is then a target, not a promise.
  2. **Fixed 0.1 s steps with render interpolation of agent positions:** this stops the partial steps, so about 10 steps per second at 1× instead of 60.
  3. **The plan's "Not now" items:** a sim thread separate from rendering (not web-safe without threads), or C# / C++ for the hot loops (not web-safe here), revisited now that B4 is done.
