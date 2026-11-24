# Anarchy Colony Sim — Player Controller Plan (draft)

**Status: ready to build (2026-11-24).** This is phase 1 of `Docs/Summer_Roadmap.md`. Follow that doc's "rules from day one" (§2): wrap-aware distance helpers, one agent scheduler, and a sim that never depends on rendering.
> Social features are their own later phase (roadmap phase 3). This plan ships the **placeholder** behaviour and the **social feed** (§5); interactive replies come later.

**Builds on:** Kingdom Wars (`Docs/Kingdom_Wars_Plan.md`), Godot 4.7.2, GDScript.
**Goal:** a playable character that feels like Hotline Miami (fast top-down movement, mouse aim, quick melee). It can run around, harvest stone, place walls and fight. The player is one of the sim's agents, driven by input instead of the AI.

> As before, **(agreed)** marks values decided in design and **(start)** marks starting values for playtest tuning.

---

## 1. Core idea: one body, two controllers (agreed)

| Layer | What it is | Today |
|---|---|---|
| **Agent** (body) | Stats, needs, inventory, worn gear, position, faction. Pure data. | `agent/Agent.gd`, unchanged |
| **Actions** (shared verbs) | Move, swing, harvest, place a piece, use a chest. The only way a body changes the world. | Buried inside `Brain`'s job runners; must be pulled out |
| **AIController** | Decides what to do and calls actions. | `Brain` + `GoalLadder`, rewired to call actions |
| **PlayerController** | Reads input and calls the same actions. | New |

- Every agent has exactly one controller. The player's agent swaps the AI for the PlayerController.
- Because both go through the same actions, rules stay identical: costs, durability, damage, privileges, build rules.
- Later this also allows possessing an NPC, or handing the player's body back to the AI (for example on death or for testing).

## 2. Movement

- **NPCs keep path movement (agreed).** A* paths at cell centres, as today. They don't need wall collision, because paths already avoid solid cells.
- **The player moves freely (agreed):**
  - WASD input sets a desired direction.
  - Velocity with quick acceleration and friction gives a snappy, Hotline Miami feel (start: 0.05 s to full speed).
  - Speed uses the same formula as agents (AGI bonus, road bonus), so stats still matter.
  - It collides with solid cells (walls, closed doors, nodes, fires) using a simple box-against-grid check, sliding along walls.
  - Own and kingdom doors are passable, using the same `World.passable` rule.
- **Facing** follows the mouse, and it drives the swing direction (§3).
- **Time (agreed):** the sim always runs at 1× for the player. The player cannot speed up time. See §6a for the debug menu.

## 3. Combat: directional melee

- Today combat is target-based: attack one chosen agent within reach.
- **New shared action: a swing** in a facing direction. It hits every hostile agent inside an arc (start: 90°, reach from the weapon's reach).
- **NPCs use the same swing:** the AI turns to face its target and swings. That keeps one combat system. **NPC swings only hit agents they are fighting (agreed)**; the player's swing hits everyone in the arc.
- Damage, cooldown, durability, armour and the plead / surrender hooks all stay in `Combat` and are reused.
- **Bows:** they fire towards the aim point (line of sight as today). NPCs aim at their target.
- **Feel:** short hit-stop, a knock-back nudge and a screen-shake hook. Purely visual, so the sim isn't affected.

## 4. Other player actions

| Input | Action | Rules reused |
|---|---|---|
| Hold E on a node | Harvest (tree, rock, metal with a tier-2 pickaxe) | Gather times, tool use, durability |
| Choose a piece, click a cell | Place a wall, door, floor or fire | `can_build`, privilege zones, build costs |
| E on a chest or crate | Open a simple transfer panel | `Stock.transfer` |
| E on a machine | Process or craft (sawmill, cutter, furnace, anvil) | `PROCESS`, recipes |
| Hotkeys | Eat, equip, swap weapon | Needs and gear rules |

- **The player's needs** (hunger, warmth) keep running. The HUD shows them.
- **Group tasks:** the player can ignore the board. Optionally, the player could claim a task and see it highlighted.

## 5. Social: placeholder now, feed from the start

The player is one of 120 agents, so the social systems act on them:
- being robbed or asked to surrender, and pleading
- being recruited, joining or leaving a group
- becoming someone's servant, or taking servants
- leading a group or kingdom, and how a player leader gives orders

**Interactive social is roadmap phase 3 (agreed),** designed with the user then. It's the route to the player leading their own kingdom. Menus and quick replies are added one at a time as that work goes on.

**Placeholder for this phase:** NPCs treat the player like any other agent. Anything that needs a choice is decided by a default rule: refuse to join, fight back when attacked. Later quick replies keep this default as a timeout fallback, so the game never pauses for a prompt.

### 5.1 Social feed (agreed)
All social requests and outcomes that touch the player are printed to a text feed in the player HUD, so the player can see the social mechanics working even before they can answer them.

**Colour coded by tier, all three shown (agreed):**

| Tier | Examples | Colour (start) |
|---|---|---|
| **Involves you** | You're asked to join, robbed, asked to surrender, taxed, attacked; your default rule's answer | Gold |
| **Your group or kingdom** | You join or leave a group or kingdom; your kingdom declares war or is declared on, wins or loses a war, is scattered; a new leader or king | Faction colour |
| **Witnessed nearby** | A fight, a robbery or a house fire within view | Grey |

- **Rule (agreed):** group and kingdom events go to the feed when they relate to the player's own standing. Joining a new group or kingdom: yes. Your kingdom going to war: yes. A groupmate being attacked: no.
- Builds on the existing event log in `ui/Hud.gd`. Each social event gets a "who is involved" tag so the feed can filter by tier.
- Messages are short and name agents, for example: "Bram robbed you: 12 wood", "Your kingdom (Ash) declared war on Reed".

## 5a. Player death (agreed)

When the player's body dies, a death panel offers two choices:
1. **Take control of the agent with the highest authority** in the player's kingdom (or group, if not in a kingdom). That's the highest AUTH living member, the same measure as `Kingdom.king_id`. If that agent was the AI's king or leader, the player now plays the ruler.
2. **Fresh respawn:** a new solo agent at a random free spot. The old kingdom carries on under AI, and the player has no ties to it.

- Solo player, or no member left alive: only option 2.
- The sim keeps running at 1× behind the panel.
- Taking control uses the controller swap from §1: the body's AIController is swapped for the PlayerController, and the dead body is handled as any death.
- Feed message, for example: "You died. You now play Mira, king of Ash."

## 6. Camera and HUD

- The camera follows the player with a slight look-ahead towards the mouse.
- HUD: HP, hunger, warmth, held weapon and armour with durability, inventory, selected build piece, and the **social feed** (§5.1).

## 6a. Debug menu (agreed)

- Speed-up (today's 1–5 keys), pause, free camera / watch mode and the zone and label overlays move **behind a debug menu**. It's still reachable in exported test builds (start: F1 toggles it).
- Watch mode hands the player's body to the AI while watching, and gives it back on return.

## 7. Phases (proposed)

| # | Phase | Done when |
|---|---|---|
| 1 | **Actions layer:** pull move, swing, harvest, place and chest use out of `Brain`; the AI calls them | Bench numbers match the current build (same behaviour) |
| 2 | **Directional swing** for everyone | Fight and kill counts stay similar; no script errors |
| 3 | **PlayerController:** input, velocity, collision, camera follow, HUD, debug menu (§6a) | Can walk around, harvest, place walls and fight; speed-up only through the debug menu |
| 4 | **Interaction panels:** chest, machine, build menu | Can craft and stock a chest by hand |
| 5 | **Social feed and placeholder rules** (§5) | All three tiers appear, colour coded, following the §5.1 rule |
| 6 | **Death and takeover** (§5a) | Dying offers takeover or respawn, and both work |

Phase 1 also adds `World.delta` / `World.dist` (roadmap §2), since `Brain` code is being moved anyway.

## 8. Open questions
- Leader and king controls: how a player ruler gives orders. That's roadmap phase 3.
- Sprite scale and layering: roadmap phase 2. Until then the player is drawn as a disc with a facing marker.

## 9. Implementation notes (phases 1–3)

Phases 1–3 are built. New modules:
- `agent/Actions.gd`: the shared verbs.
- `agent/Scheduler.gd`: the one agent update entry point.
- `player/PlayerController.gd`
- `render/PlayerLayer.gd`
- `ui/PlayerHud.gd`
- `ui/DebugMenu.gd`
- `player/PlayTest.gd`: scripted checks.

**Where things plug in:**
- **Controllers:** `Agent.controller` is null for the AI. Otherwise it is an object with `control(a, dt)`. `Scheduler.update` runs needs (`Agent.tick_needs`, moved out of `Brain`) and the attack cooldown for every body, then the AI (`Brain.update`) or the controller. `World.step` calls `Scheduler.update_agents`.
- **Actions:**
  - `move_path` is the NPC A* movement (`Brain.move_to` forwards to it).
  - `move_free` is the player's box-against-grid movement. It slides along walls and treats cells already overlapped as free, so a body is never stuck inside a new piece.
  - `swing` and `shoot` for combat.
  - `harvest_secs`, `harvest_unit` and `can_harvest` for gathering.
  - `place` and `can_place` for pieces.
  - `use_chest`, `finish_warming` and `eat`.
  - `Brain`'s gather, CLEAR_NODE, wild fire and task placements all call these, and so does the raid sack's chest transfer.
- **Wrap-aware helpers:** `World.delta`, `World.dist` and `World.dist_sq` are plain subtraction for now. All new and moved code uses them.
- **Facing:** `Agent.facing` (unit Vector2, aim / torso direction) and `Agent.move_dir` (legs). `Agent.last_swing` holds the sim time of the last swing. NPCs face their target before a swing or a shot. The player's facing follows the mouse.
- **Input:** read per frame into intents (move, aim, swing, harvest, place, eat). They are used only inside the sim step, so the sim never depends on rendering. The player's AGI XP is per cell walked, like path movement.
- **Test modes:**
  - `-- --playtest` (headless or windowed) drives the intents and checks walk, accelerate, stop, wall stop and slide, placing (and refusals), harvesting, the swing arc hitting and missing, a fight, the social defaults and watch mode.
  - `-- --inputtest` (windowed) does the same through injected key and mouse events: WASD, mouse facing, 1 + LMB placing, X, F1, menu keys and watch mode.
  - Both pass. `--bench`, `--shot` and `--frames` run without a player.

**Bench:**
- **Phase 1** (40 min, seed 12345): every per-minute stat line is **identical** to the build before, and the sim is deterministic. Time was +3% (101.6 s against 99.6 s and 98.9 s for two baseline runs), from the extra call layers.
- **Phase 2:** the sim diverges, so it was compared over 8 seeds (12345, 1–7) at 40 min:

  | | before | directional swing |
  |---|---|---|
  | deaths (mean) | 110 (range 52–162) | 128 (range 86–163) |
  | fights started (mean) | 263 | 277 |
  | kingdom wars declared (total) | 14 | 19 |

  - About 15% of hits land on someone other than the swinger's target: other enemies bunched on nearby cells, and bystanders.
  - A 60° arc made no difference (4 seeds).
  - **`Cfg.NPC_SWING_HITS_BYSTANDERS`** (off, agreed with the user 2026-11-24; §3 originally had it on) limits NPC swings to agents they're already fighting. The player's swing always hits everyone in the arc. With it off, 4 seeds still averaged 134 deaths, so bystander hits aren't the main driver; one swing landing on several fighters is.

**Deviations and clarifications:**
- **Speed-up works in watch mode only.** The debug menu holds pause, 1–5 speed, watch / free camera (V), and the zones (Z) and labels (L) overlays; the shortcuts work while it's open. While playing, the speed keys are refused ("the player always runs at 1×"). Leaving watch mode resets to 1×.
- **Who a swing hits:** anyone not on the swinger's side (group or kingdom), plus anyone the two are already fighting, so a servant's rebellion still lands. Allies are never hit.
- **A swing at nothing** still costs the cooldown. If no agent is in the arc, a wall or door in front that isn't the swinger's own takes the blow (`Combat.attack_wall`, raiding axes ×5).
- **Bows:** RMB fires at the hostile agent nearest the aim point, within bow range and line of sight. NPC bows are unchanged, except that they now face the target.
- **Player controls:** WASD, mouse aim, LMB swing, RMB bow, hold E harvest (the node in reach most in front), 1–4 pick wall / door / floor / wild fire (LMB place, RMB or X stop), F eat a berry. Walking onto a loot bag picks it up. Standing within `WARM_RADIUS` of a burning fire for 10 s warms the body, like the NPC WARM job.
- **Player build rules:** `can_build` / `can_floor` (zones, no agents, no loot), reach `PLAYER_BUILD_REACH`, and not on the player's own collision box. Solo player pieces decay outside a house zone like anyone's.
- **Jobs on the player's body:** other systems still set jobs on it (fight back, flee). On the player those jobs are only markers, so it counts as in combat and isn't drafted or chatted to mid-fight. They never run, and the controller drops them when the fight ends.
- **Placeholder social rules (§5), now in code:**
  - The player refuses happy invites and gang joins (logged).
  - A robbery demand on the player is refused, and the NPC attacks.
  - The player never pleads.
  - The player isn't drafted as a defender.
  - The player doesn't start social encounters, since it never runs `Social.scan`.
- **Death (until phase 6):** the HUD offered R to carry on as the newcomer who just wandered in (every death spawns one). Phase 6 replaced this with the death panel (see the phase 6 notes below).
- **Feel:** screen shake on landing or taking a hit is in (`PLAYER_SHAKE`). Hit-stop and knock-back are not in yet. Hit-stop would pause the sim, so it needs a rule-1-safe design (for example freezing only the renderers).
- **Starting agent:** the solo agent nearest the map centre.
- **New tunables (start values):** `SWING_ARC_DEG` 90, `NPC_SWING_HITS_BYSTANDERS` false (agreed), `PLAYER_ACCEL_SECS` 0.05, `PLAYER_HARVEST_REACH` 1.6, `PLAYER_BUILD_REACH` 3.5, `PLAYER_LOOK_AHEAD` 0.25 (capped at `PLAYER_LOOK_MAX` 6 cells), `PLAYER_ZOOM` 1.5, `PLAYER_SHAKE` 6 px.

## 9. Implementation notes – phase 4 (interaction panels)

Phase 4 is built. You can craft an item and stock a chest entirely through the panels.

**New files:**
- `player/Station.gd`: the sim side of the open chest or machine. It holds what's open, the running processing job and the requests queued by the panel. `PlayerController.control` applies the requests inside the sim step, through `Actions`. The UI never changes the sim directly (roadmap rule 1).
- `ui/StationPanel.gd`: the chest and machine panels.
- `ui/BuildMenu.gd`: the build menu.

**Shared verbs added to `Actions`:**
- `can_use_storage` and `can_use_machine`.
- `machine_menu`: what each machine processes and crafts.
- `process_batch` and `craft`.
- `Brain._process_step`, `Brain._run_craft` and `GoalLadder.craft_or_gather` now call `process_batch` and `craft` instead of paying and adding items inline. Behaviour is unchanged (see the bench below).

**Rules (all the AI's own):**
- **Chests and crates:** only those of your own side (group or kingdom), as for the AI. Moves go through `Stock.transfer`, so chest slots and your pack's capacity both limit them. Tools move the freshest copy first.
- **Machines:**
  - Only a workshop or smeltery your side may use (`Factions.machine_houses`), and only while it's operational (built, fire burning, every machine standing). That's the same test as `Factions.nearest_machine`.
  - Processing runs `Items.PROCESS` batches at the AI's times.
  - Crafting is instant, as for the AI on arrival. Anvil recipes are at the anvil, and the raiding axe and tier-2 pickaxe are at the sawmill.
  - A solo player has no workshop, so can't use machines until they're in a group that has one.

**Controls:**
- **E** opens the chest, crate or machine in reach (`PLAYER_USE_REACH` 1.6 cells, the one most in front). Furniture wins over a node for that press. **E** or **Esc** closes the panel, and so does the panel's **x**. Holding E doesn't harvest while a panel is open.
- **Chest panel:** your pack and the chest side by side, with **1** / **All** per stack or tool type, plus **Put everything in** and **Take everything**.
- **Machine panel:**
  - Each process row has **1** / **All**. All runs until the input runs out. A progress bar shows the running batch, with a **Stop** button.
  - Each craft row has a **Craft** button.
  - Rows you can't afford are greyed out. If the building isn't running, the panel says why.
- **B** toggles the build menu. It lists wall, door, floor and wild fire with their costs, and greys out what you can't afford. Click a piece or press **1–4** while the menu is open to pick it. Picking closes the menu. Then LMB places it, and RMB / X stop building as before. The old 1–4 keys outside the menu are gone.
- The HUD hint shows "E open <thing>" when something is in reach.

**Decisions:**
- **Nothing pauses.** Time stays at 1×.
- **Movement keeps working** while a panel is open, so you can walk off or fight. Walking out of reach (reach + 0.25) closes the panel.
- **Clicks on the panel** are taken by the panel and don't swing. Clicks elsewhere still swing.
- A single hit of more than `PANEL_CLOSE_HIT` (5 HP, start) closes the panel. An unarmed punch (4 HP) doesn't. Death, watch mode, taking over another body, or the furniture going also close it.
- Picking a build piece closes an open panel, and opening a panel stops building.

**Tests:**
- `--playtest` builds a finished workshop and a chest for the player's faction. It then does all of the following through the panel buttons:
  - cuts stone at the cutter (All, until it runs out)
  - walks away (the panel closes)
  - saws a plank and handles
  - crafts a tier-2 pickaxe (greyed out before)
  - checks that a hard hit closes the panel
  - stocks the chest with the pickaxe and handles, and takes one back
- It also checks that another side's chest is refused, and that the build menu greys out and picks.
- `--inputtest` now does B → 1 → LMB for building. It also does E on a chest, a real mouse click on a panel button (moves 1 wood, no swing) and Esc to close.
- Both pass with 0 failures.
- `--bench=40` (seed 12345) runs with no errors. Every stat line is **identical** to the build before phase 4. Real time was 122.0 s against 118.1 s, but both runs were going at the same time, so that difference is noise.

**Deferred:**
- Hand-crafting outside machines (axe, spear, bow, arrows): the AI does this anywhere, but there's no player panel for it yet.
- Placing chests and machines by hand: they belong to houses, so they're built by house tasks.
- Looting enemy chests: the raid sack.
- Equip and swap hotkeys.
- Drag-and-drop and keyboard navigation in the panels.
- Machine worker claims: the player doesn't take a smeltery claim. The AI only checks claims when it starts a job, so the two can share a machine.

## 9. Implementation notes – phase 5 (social feed)

Phase 5 is built. New module: `ui/SocialFeed.gd` (bottom right of the screen, added in `Main.gd` next to the player HUD).

**How it plugs in:**
- **Events are plain data.** `EventBus.social(kind, text, actors, groups, pos, n)` logs `text` to the normal event log (as `log_event` did) and emits `EventBus.social_event` with ids only: kind, actor ids and names (in sentence order, usually doer then target), group ids, kingdom ids, group names, position, a count and the sim time. A Faction in `groups` also brings its kingdom, and a Kingdom all its groups, so "your side" still matches after the event has changed membership.
- **No cost without a listener.** The event is only built while `EventBus.feed_on` is true (the feed sets it when it has a player). `--bench`, `--shot` and `--frames` have no player, so they don't build it. Hits are the one frequent event, and their call site checks `feed_on` first.
- **Emitters (kinds):** Social (`invite`, `demand`, `robbed`), Combat (`fight` from `start_fight`, `hit`, `plead`, `surrender`, `robbed`, `rebel`, `breach`), Brain (`rebel`), World (`killed`, `died`), Factions (`group_form`, `group_join`, `group_leave`, `leader`, `freed`, `servant`), Kingdoms (`kingdom_form`, `kingdom_join`, `kingdom_leave`, `kingdom_dissolve`, `king`), KingdomWars (`war`, `scatter`), Wars (`war`, `peace`), Tax (`tax`, `tax_refused`), PushOut (`pushout`) and Raids (`sack`). The sim never knows whether a feed exists.

**Tiers (the feed decides, from the controlled agent at the time of the event):**
- **1, involves you (gold):** you are one of the actors, or your group is taxed or pushed out. Short second-person lines, for example "Bram demands your goods. You refuse and fight back!", "Bram attacks you! You fight back.", "You join F10." Kinds without a template use the log text with your name turned into "you".
- **2, your group or kingdom (faction colour, lightened; kingdom colour if you're in one):** only standing events: a new leader or king, your group forming, joining or leaving a kingdom, your kingdom dissolving or scattering, war and peace for your side. Other groups joining or leaving your kingdom, and fights involving groupmates, are not shown (agreed rule).
- **3, witnessed nearby (grey):** fights, kills, robberies, demands, pleas, surrenders, rebellions, sacks and wall breaches within `FEED_NEAR` (16 cells, start) of you, by `World.dist`. Single hits are left out.
- **Lightweight:** at most 8 entries (`FEED_MAX`), each at full strength for 20 s, then fading over 4 s (real time). The same line again within 8 s, among the newest 3, collapses into "x2", "x3" and moves back to the bottom.
- **Debug menu:** "Feed, witnessed nearby: on/off [G]" hides tier 3 (G, not N: N is the death panel's respawn key).
- **The player's own deaths and takeovers:** the feed reads `player.body` per event, so it follows whatever body is controlled. While dead it only shows events that name the dead body ("Bram killed you.").

**Tests:** `--playtest` now also checks that a refused invite and a refused demand are tier 1, an NPC fight 5 cells away is tier 3, the debug toggle hides tier 3, joining and leaving a group are tier 1, a groupmate attacked 40 cells away is not shown, and repeats collapse. Windowed, it saves `user://playtest_feed.png`.

**Bench (40 min, seed 12345):** every per-minute stat line is identical to the build before (the feed is off without a player, and no rule changed). Time was 117.3, 118.0 and 122.4 s against 113.0 and 124.1 s for the build before, so the cost is unchanged within run-to-run noise. `--playtest` and `--inputtest` pass. `--inputtest` failed its "LMB places a wall" check in 2 of 6 runs (the cursor cell landed away from where the test put the mouse), and passed the other 4 in a row. That looks like the real mouse over the window; the build before passed 5 of 5.

**Small changes to shared code:** in `Factions.join` the "joins" log line now comes before the leader recompute (so "You join" comes before "You now lead"); `Kingdoms.dissolve` reports before it clears the groups. No rules changed.

## 9. Implementation notes – phase 6 (death and takeover)

Phase 6 is built. The "press R" stopgap is gone.

**New and changed modules:**
- `ui/DeathPanel.gd` (new): shown while the controlled body is dead, near the top of the screen so the death animation stays visible. **[T]** takes over, **[N]** starts fresh. It refreshes 4× a second, because the candidate can move or die while the panel is open.
- `World.agent_died(a, killer, group, kingdom, newcomer)` (new signal): emitted at the end of `kill_agent`, after the body has left its group and the newcomer has spawned. `group` and `kingdom` are what the body belonged to just before it died. Nothing in the sim listens to it, so `--bench` is unchanged.
- `PlayerController`: `death` (empty while alive), `dead()`, `takeover_candidate()`, `role_of(a)`, `take_over(a)`, `respawn()`, plus the signals `died` and `body_changed`. `possess` now also clears every buffered intent (swing, shoot, place, eat, harvest, build piece).
- `Main.gd`: adds the panel. On `body_changed` the camera follows again (from watch mode: back to the player's zoom) and the selection clears.
- `DebugMenu`: **Take control of selected [C]** moves the player to the agent picked with LMB in watch mode (or while dead). Speed-up is no longer unlocked just because the body is dead.

**Rules as built:**
- **On death:** the panel opens, watch mode ends and the speed resets to 1×. The sim keeps running.
- **Option A, the candidate:** the living member with the highest AUTH across the kingdom's current groups, using the same order as group leadership (AUTH, then CHA, then lowest id).
  - If the kingdom has dissolved since the death (for example, the player's group died with them), the groups it had at the moment of death are used.
  - Not in a kingdom: the player's own group.
  - Solo, or nobody left alive: the button is hidden.
  - The panel shows the candidate's id, role ("king of Ash", "leader of F12 (Ash)", "member of …"), AUTH, and distance from where the player died.
- **Taking over:**
  - Same controller swap as possession: the AI's job, task claim and path are dropped, `think_t` is reset, and the body leaves any raid party (`raid_id` / `defend_raid` cleared).
  - The body keeps its inventory, worn gear, stats, group and rank, plus any fights it is already in (`death_match`).
  - Feed line: "You died. You now play #34, king of Ash." (agents have no names yet).
- **Fresh respawn:** the player takes the newcomer that the death spawned, so the population stays constant. If that newcomer has died, joined a group or been taken meanwhile, a new agent spawns instead. The old kingdom carries on under the AI.
- **Stale references:** the dead body is handled like any death (it leaves its group, and leader slots are recomputed). For the player's death only, the kingdom's king is recomputed straight away rather than on the 2 s kingdom tick, and the body is removed from raid parties straight away rather than on the next raid tick. The dead body's `controller` is cleared on the swap, so `is_player()` is false for it.
- **Everything player-centred follows the controller, not a body:** camera, `PlayerHud`, `PlayerLayer`, `DeathPanel` and the debug menu all read `PlayerController.body`, so they switch automatically (Summer Roadmap §2.5).

**Tests:**
- `--playtest` gained the death checks:
  - Build a 3-group kingdom around the player and kill them. The takeover picks the highest-AUTH member in another group and makes them king. The panel shows them. No group, kingdom or raid still holds the dead id. The new body keeps its group, inventory and AUTH, has its AI state dropped, and walks and swings.
  - Respawn from inside the kingdom: the newcomer, solo, no kingdom; the kingdom carries on.
  - Group without a kingdom: the group's highest AUTH.
  - Solo death: only a fresh start is offered.
  - The debug menu's take control.
- `--inputtest` gained: kill → the panel at 1× → **N** → a solo body that **A** moves.
- `--playtest`, `--inputtest` and `--bench=30` pass with no script errors.

**Open:**
- When the player takes over a king, the AI's kingdom decisions (wars, tax, raids) still run, because they are kingdom-level systems rather than the king's brain. How a player ruler gives orders is roadmap phase 3.
