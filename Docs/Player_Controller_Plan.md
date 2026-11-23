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
- **Death (until phase 6):** the HUD offers R to carry on as the newcomer who just wandered in (every death spawns one).
- **Feel:** screen shake on landing or taking a hit is in (`PLAYER_SHAKE`). Hit-stop and knock-back are not in yet. Hit-stop would pause the sim, so it needs a rule-1-safe design (for example freezing only the renderers).
- **Starting agent:** the solo agent nearest the map centre.
- **New tunables (start values):** `SWING_ARC_DEG` 90, `NPC_SWING_HITS_BYSTANDERS` false (agreed), `PLAYER_ACCEL_SECS` 0.05, `PLAYER_HARVEST_REACH` 1.6, `PLAYER_BUILD_REACH` 3.5, `PLAYER_LOOK_AHEAD` 0.25 (capped at `PLAYER_LOOK_MAX` 6 cells), `PLAYER_ZOOM` 1.5, `PLAYER_SHAKE` 6 px.
