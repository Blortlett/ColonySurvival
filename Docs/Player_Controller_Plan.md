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
- **NPCs use the same swing:** the AI turns to face its target and swings. That keeps one combat system, and NPCs can now hit bystanders by accident.
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
