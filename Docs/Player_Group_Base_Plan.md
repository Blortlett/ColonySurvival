# Player Group & Base Plan

Status: **built, not yet committed** (2026-11-25). Packages A–D are in; `--playtest` passes 153 checks. Not yet checked by hand in a real game.

Goal: the player founds and runs their own group. They recruit NPCs by invite, always lead
(and are always king), place the group's base fire themselves, and every building gets a
mailbox that opens a group panel (members, faction, command view).

## Agreed decisions

| # | Decision |
|---|---|
| D1 | The player is always leader of a group they lead (formed or invited into). Authority no longer decides it. |
| D2 | Exception: an angry player may accept an NPC's **gang** ask. In that gang they are an ordinary member and the NPC can lead (rare, high risk). |
| D3 | The player is always king of any kingdom their group is in (when they lead that group). |
| D4 | NPCs never invite the player to a group. The gang ask stays (D2). |
| D5 | "Ask to join" is removed from the radial menu. |
| D6 | The player may invite an NPC who outranks them; that NPC always refuses. Outranks = higher AUTH, or equal AUTH and higher CHA (same order as `recompute_leader`). |
| D7 | The base fire (`house_fire`) is in the build menu. It can only be placed by a group leader with at least 1 other member, whose group has no home yet. |
| D8 | When the player places it, a House is planned around it and members build it through the normal task board. From then on the group runs its usual ladder (stock, workshop, reinforce, smeltery, stone). |
| D9 | The AI never auto-plans the first home of a player-led group. Later houses, workshops and smelteries stay automatic. |
| D10 | Every house, workshop and smeltery gets a mailbox: one tile outside the door, one tile to the side (left, else right). NPC buildings too. |
| D11 | Mailbox UI: Members / Faction / Command tabs. Command is view-only in this pass. |
| D12 | If the player's group shrinks back to just the player, the house stays. |

## Work packages

### A. Leadership & invites
Files: `faction/Faction.gd`, `faction/Factions.gd` (`recompute_leader`, `form` only), `faction/Kingdoms.gd`, `social/Social.gd`, `ui/SocialRadial.gd`, `player/PlayerController.gd` (`takeover_candidate` only, to use the shared helper).

- `Faction.player_led: bool`. Set true when the player forms a group, invites someone, recruits a gang, or founds with a servant. Left false when the player joins an NPC gang (D2).
- One shared rank helper, e.g. `Factions.outranks(a, b) -> bool` (AUTH, then CHA, then lower id), used by `recompute_leader`, `form`, `Kingdoms` king choice and `takeover_candidate`.
- `recompute_leader`: if `player_led` and the player is a member, the player leads.
- `form(a, b)`: if either is the player and this is not the gang-ask path, the player's faction becomes the group and the player leads.
- `Kingdoms` king pick (~line 101): if any member group is `player_led`, that group leads and the player is king (D3).
- `Social._happy_meets`: remove the branch that asks the player to join/form (D4). Leave `_angry_meets` gang ask (D2).
- `Social._player_invite`: if `outranks(t, p)`, refuse with a line like "X won't follow someone with less standing." and a small opinion drop (D6). The option stays enabled for them.
- Remove `ask_join` from `PLAYER_OPTIONS`, `_option_why`, `player_act`, `_player_ask_join`, and fix any fixed-slot layout in `ui/SocialRadial.gd` (D5).
- `player/PlayTest.gd`: update any test that relies on Ask to join or NPC invites.

### B. Mailbox piece (world side)
Files: `entities/Furniture.gd`, `faction/House.gd`, `faction/Task.gd`, `agent/Brain.gd`, `agent/Job.gd` (if needed), `world/World.gd`, `combat/Items.gd` (cost), `render/PieceLayer.gd`, mailbox sprite art.

- `Furniture.Kind.MAILBOX` (append at the end of the enum so saved indices don't shift). Not storage, not a machine.
- `House.mailbox_cell`: `door_cell + door_dir + side`, where side is the perpendicular to `door_dir`, left first. `House.mailbox_cell_alt` for the right side. Set for every Kind.
- `House.mailbox: Furniture` and `live_mailbox()`, like the chest.
- `Task.Type.PLACE_MAILBOX` with cost `Items.BUILD_COSTS["mailbox"]` (start: 2 wood). Brain task runner places it like the chest task does; World places/removes it and keeps it solid.
- Render the mailbox (sprite, or a placeholder shape until art exists).
- Does **not** touch `Factions.gd`: posting the task and the site check are wired in package D.

### C. Mailbox UI
Files: new `ui/MailboxUI.gd`, `player/PlayerController.gd` (E on a mailbox opens it, like a chest), `Main.gd` (create the UI).

- Opens for any mailbox the player can reach. Own side: all tabs. Foreign mailbox: Members and Faction only, read-only summary.
- **Members**: name, role (leader/member/servant), mood, key stats (AUTH, CHA, combat), current job, home.
- **Faction**: name, kingdom and king, relations and wars, number of houses / workshops / smelteries, chest stock.
- **Command** (view-only): the group ladder in `Factions._workshop_goals` order: home, stock chest, workshop, reinforce, smeltery, stone tier. Each step shows done / in progress / locked and its open board tasks (e.g. "Walls 7/14"). Data comes from one read-only helper, `Factions.ladder_status(f) -> Array[Dictionary]`, so a later pass can make steps orderable or toggleable without changing the UI's data shape.
- `ladder_status` lives in `Factions.gd` but is a pure read; package C may add it as a new function at the end of the file.

### D. Base fire + integration
Files: `agent/Actions.gd`, `ui/BuildMenu.gd`, `faction/Factions.gd` (housekeeping, site check, mailbox task posting).

- `Actions.PIECES` gains `house_fire`, labelled "Base fire" in the menu.
- `Actions.can_place(a, "house_fire", c, reach)`: must lead (`leader_id == a.id`) a non-solo group with no home (planned or built); site must pass a public `Factions.site_ok_at(f, fire_cell)` that reuses `_site_ok` (interior centred on `c`, size from `House.size_for(HOUSE, cap)` with cap = members + 1, clamped like housekeeping). Each failure returns its own reason.
- `Actions.place(..., "house_fire", ...)` for a leader without a planned house: create the House, add it to `f.houses`, fill occupants, place the fire, call `Factions.on_house_fire_placed`. The AI path (task with a planned house) is unchanged.
- ~~Door faces the side nearest the player.~~ Built: the door always faces south, because `site_why` (the shared site check) only handles south doors.
- Built as a separate piece, `base_fire` (same cost as `house_fire`), so the AI's `house_fire` path is untouched. `Factions.base_why` / `found_base` do the work; `_site_ok` now wraps `site_why`, which returns a reason.
- Also fixed: `Cities.gd` city clean-up no longer treats a live mailbox as rubbish.
- Known gap: a player-led group that joins a kingdom with a city before placing a base fire may still get a house planned on a city plot (`Cities.gd`).
- `Factions.housekeeping`: skip the "homeless → plan_house" step when `f.player_led` and the group has no home yet (D9).
- `_site_ok`: also require the mailbox cell (or its alt) to be buildable.
- `_ensure_piece_tasks`: post `PLACE_MAILBOX` once the building is complete, for every kind (D10).
- Wild fire stays as it is.

### E. Verification
- Headless/PlayTest coverage: invite refusal by rank, player stays leader after a higher-AUTH join, player is king after a kingdom forms, gang exception, base fire refused when solo / already housed / bad site, members build the house after placement, mailbox appears on houses, workshops and smelteries.
- One manual run: recruit 2 NPCs, place a base fire, watch them build, open the mailbox.

## Running the work in parallel

A, B and C touch separate files and can run at the same time as three sessions sharing
this folder (no worktrees: the user commits by hand, so uncommitted worktree branches would
have to be merged by hand). Rules for every session: only touch your package's files, commit
nothing, switch no branch.

- Shared-file care: `Factions.gd` is touched by A (two functions) and C (one new function at the end). They are separate hunks.
- `PlayerController.gd`: A changes only `takeover_candidate`; C only the interaction code.
- C uses `Furniture.Kind.MAILBOX` from B; until B adds it the UI script won't parse, so C should land after B or add its own check last.
- While three sessions edit at once, a game run can catch another session's half-finished edit. Each session runs the game only at the end.

D waits for A and B (it needs `player_led` and the mailbox task) and runs here, followed by E.
