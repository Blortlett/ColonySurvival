# Anarchy Colony Sim — Player Controller Plan (draft)

**Status: draft, not ready to build.**
> **Before starting:** ask the user about the **social features** for the player (§5). They want to design those themselves. Don't start building until that is settled.

**Builds on:** v3 (`Docs/Kingdoms_Plan_v3.md`), Godot 4.7.2, GDScript.
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
- **Time:** the sim runs at 1× while the player is in control. Speed-up is for skipping time (resting, watching). Exact rules are open.

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

## 5. Social features — open (user to design)

The player is one of 120 agents, so the social systems will act on them:
- being robbed or asked to surrender, and pleading
- being recruited, joining or leaving a group
- becoming someone's servant, or taking servants
- leading a group or kingdom, and how a player leader gives orders

**Not designed yet. Ask the user before building any of this.** Until then, a safe placeholder: the player is a solo agent that NPCs treat like any other agent. Prompts that would need a choice resolve automatically (refuse to join, fight back when attacked).

## 6. Camera and HUD

- The camera follows the player with a slight look-ahead towards the mouse. Free camera mode stays for watching.
- HUD: HP, hunger, warmth, held weapon and armour with durability, inventory, selected build piece.
- A key to toggle between watching the sim and playing.

## 7. Phases (proposed)

| # | Phase | Done when |
|---|---|---|
| 1 | **Actions layer:** pull move, swing, harvest, place and chest use out of `Brain`; the AI calls them | Bench numbers match the current build (same behaviour) |
| 2 | **Directional swing** for everyone | Fight and kill counts stay similar; no script errors |
| 3 | **PlayerController:** input, velocity, collision, camera follow, HUD | Can walk around, harvest, place walls and fight |
| 4 | **Interaction panels:** chest, machine, build menu | Can craft and stock a chest by hand |
| 5 | **Social features** | After the user's design (§5) |

## 8. Open questions
- How sim speed-up works while the player is alive.
- What happens on player death: respawn as a fresh agent, possess someone, or game over.
- Whether the player can be the leader or king, and what the controls for that look like (part of §5).
