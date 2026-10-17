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

### A2. Paving waits for the smeltery
- Today paving (`UPGRADE_ROAD`) starts once the road stage is done and a kingdom workshop is working.
- **Fix:** paving also needs a working kingdom smeltery.

### A3. Smeltery before joining a kingdom
- **Fix:** a group must have a working smeltery (its own) before an alliance roll can make it form or join a kingdom (`Kingdoms.try_ally`).
- Kingdom **invitations** (the v3 push-out ladder) still work without one, because the kingdom already has a smeltery to share.
- Record this in the v3 doc's §10 as a deviation: a group's ladder step order changes.
- **Watch:** metal, and so armour, arrives earlier. Kingdoms may form later.

**Done when:** a bench shows no script errors, kingdoms still form, and paving starts only after a kingdom smeltery is working. A screenshot shows floor under the fires.

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
