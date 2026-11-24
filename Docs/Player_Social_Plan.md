# Anarchy Colony Sim — Player Social Plan (draft)

**Status: all five phases built (2026-11-24).** See §9 for implementation notes. Next steps are in §7 (later). This is roadmap phase 3 ("Player social", `Docs/Summer_Roadmap.md`). It replaces the placeholder default rules from `Docs/Player_Controller_Plan.md` §5 with real choices, and follows that roadmap's "rules from day one": the sim never depends on rendering, player input is applied only inside the sim step, and the sim never pauses for the player.

**Builds on:** Player Controller (`Docs/Player_Controller_Plan.md`, phases 1–6 built), the social feed (§5.1 there), Godot 4.7.2, GDScript.
**Goal:** the player takes part in the social system that NPCs already run. NPCs can ask the player things, and the player answers with quick prompts. The player can start social actions on NPCs from a radial menu. UI shows social state (mood, opinion, health), so the player can read a situation before acting. All of it should be obvious but not intrusive.

> As before, **(agreed)** marks values decided in design and **(start)** marks starting values for playtest tuning.

---

## 1. What exists today (assessment)

Every NPC-to-NPC social action lives in `social/Social.gd` and `combat/Combat.gd`. Where the player is involved, a fixed default rule answers for them:

| Action | Between NPCs | Player today | Where |
|---|---|---|---|
| **Invite / form a group** | Happy pairs team up if opinions are ≥ 0; a neutral can be won over with a CHA roll | Always refuses | `Social._happy_meets` (`b.is_player()` branch) |
| **Gang recruitment** | Two angry agents roll CHA: the winner forms or joins a gang, a lost roll means a fight to the death | Never joins | `Social._angry_meets` |
| **Trade** | Two groups swap 2 of a surplus stack; opinion +10, relations up | Happens automatically and silently if the player is in a group | `Social._trade` |
| **Demand goods (robbery)** | The target stands up (power ≥ 1.2×), flees, is attacked, or hands over 50% of each stack (`Combat.rob`); opinion −40, `REL_ROB` | Always refuses and fights back | `Social._demand` |
| **Talk down** | A happy target may talk an angry one down (CHA × 0.5) and flee | Never offered | `Social._angry_meets` |
| **Plead / surrender** | A beaten agent begs: accepted means servant (or spared and robbed if the group is full), refused means a fight to the death | Never pleads; when an NPC begs the player, a dice roll answers for them | `Combat.apply_damage`, `Combat.plead` |
| **Servants / rebellion** | Servants serve their master; they may rebel | Works; no orders yet | `Factions.make_servant`, `Combat.accept_surrender` |
| **Kingdom level** (ally, tax, push-out, war) | Leader decisions | Only matters as a leader | `faction/` |

The player never runs `Social.scan`, so they never start an encounter.

**Robbery is already built.** The player-facing "verbal rob" (§4.3) reuses `_demand`, so it's a small job (about half a day).

## 2. Input changes (agreed)

| Input | Before | After |
|---|---|---|
| **F** | Eat a berry | **Hold:** open the social radial menu over the hovered character (§4). Release closes it. |
| **Eat** | F, or LMB with a berry in hand | **Only** LMB with food in the active hotbar slot (agreed). That path already exists in `PlayerController._use_held`. |
| **F1 / F2** | F1 toggled the debug menu | Accept / decline the incoming prompt (§3). **The debug menu moved to F3.** |
| **LMB** | Use what's held | Also clicks prompt buttons and confirms a radial option. While the radial is open, LMB never swings or eats. |

- Remove the `KEY_F → _eat` branch in `PlayerController._unhandled_input` and the `_eat` intent. Update the header comment and the HUD control hints.
- `--playtest` / `--inputtest` steps that eat with F switch to LMB with a berry selected.

## 3. Incoming prompts (agreed)

NPCs ask, the player answers. The game never pauses. Each prompt has a timeout, and when it runs out, the current default rule answers (Player Controller Plan §5: "quick replies keep this default as a timeout fallback").

### 3.1 Prompt kinds

| Kind | Trigger | F1 (Accept) | F2 (Decline) | Timeout (default rule) |
|---|---|---|---|---|
| `invite` | A happy NPC invites the solo player to form or join a group | `Factions.form(npc, player)` or `Factions.join(player, npc.faction)` | Refuse; the NPC's opinion of you −5 (start) | Refuse (as today) |
| `gang` | An angry NPC invites the angry player into a gang | Form or join the gang, as in `_angry_meets` | Refuse; the NPC's opinion of you −5, then it rolls `_attack_chance` and may attack | Same as decline |
| `demand` | An angry NPC demands the player's goods | Hand over: `Combat.rob(npc, player, DEMAND_FRACTION)`, then the same mood and opinion effects as an NPC complying | Refuse and fight: `Combat.start_fight(npc, player)` | Refuse and fight (as today) |
| `plead` | An NPC the player beat begs for mercy | Spare: `Combat.accept_surrender(player, npc)` (servant, or spare and take goods if the group is full) | Finish: refused plea, fight to the death (as `Combat.plead`'s refused branch) | Today's dice roll (`SURRENDER_ACCEPT` ± opinion) |

- **Timeouts (start):** `invite` / `gang` 10 s, `demand` 5 s, `plead` 5 s (sim time).
- **Re-checked on answer:** before applying an accept, re-check what the NPC side checked: both alive, in range (`SOCIAL_RANGE` × 2, start), the group still has room, and the player is still solo where required. If anything fails, show "The offer is no longer open." and drop it.
- **Plead details:** when the plea goes to the player, the victim stops fighting (job `IDLE` at `PRIO_CRITICAL`, start) until the answer. **Hitting them again counts as F2 (finish).**
- **Demand details:** while waiting, the demanding NPC holds position facing the player (job `IDLE` at `PRIO_NEEDS`, start). If the player walks out of range, that counts as a refusal. Talk-down for the player is not in this phase (see §7).
- **Cooldowns:** the pair cooldown (`set_cooldown`) is set when the prompt opens, as today, so the same NPC doesn't ask again straight away.

### 3.2 How it plugs in

- New `player/Offers.gd` (owned by `PlayerController`): a small queue of pending offers `{kind, from_id, fid, expires, data}`.
- Social and Combat call `World.player.offer(kind, npc, data)` where they now apply the default rule. The sim never knows whether a UI exists: if there's no controller (bench, `--shot`), they apply the default rule straight away, as today.
- **One prompt shown at a time.** Others wait in the queue (max 3, start). An older one that expires while queued just applies its default. `plead` and `demand` jump the queue, because they're time-critical.
- F1, F2 and button clicks set an intent. The answer is applied in `control()` (inside the sim step), like all player input.
- Death, takeover, respawn and watch mode clear the queue, and the askers stop waiting. Nothing else is applied: the old body is dead or back with the AI, and a pleading NPC just walks away, because its fight stopped while it begged.

### 3.3 Prompt UI (agreed: obvious, not intrusive)

- A small card at the top centre of the screen, under any top HUD (new `ui/OfferPrompt.gd`, a CanvasLayer):
  - Line 1: the NPC's name in their faction colour, plus a short ask: "**Bram** invites you to join **Ash** (4 members)."
  - Line 2: two **clickable buttons**, `[F1] Accept` and `[F2] Decline` (agreed: keyboard or mouse). The labels change by kind (Join / Refuse, Hand over / Refuse, Spare / Finish).
  - A slim timer bar along the bottom edge that shrinks to the timeout.
  - A small "+2 more" tag when others are queued.
- Slides or fades in. A soft sound cue if there's an audio bus by then (optional). No pause, and it doesn't take keyboard focus away from movement.
- **World marker:** a small "!" over the asking NPC's head while their offer is open (drawn by the social overlay, §5).
- The answer goes to the social feed as a tier 1 (gold) line ("You join Ash.", "You refuse Bram.", "You spare Mira; she is now your servant.").

## 4. Radial menu (agreed)

### 4.1 Interaction (agreed)

1. **Hover** a character (the nearest living agent to the mouse within 0.75 cells of `aim_point`, start) within reach (`SOCIAL_RANGE` = 5 cells).
2. **Hold F:** the radial opens around that character's screen position, and the target is locked for as long as the menu stays open.
3. **Move the mouse** to an option. The option in the mouse's direction from the centre is highlighted. Inside a small dead zone (start: 24 px), nothing is highlighted.
4. **Left click** confirms the highlighted option and closes the menu.
5. **Releasing F** closes the menu without choosing anything.

- WASD movement keeps working while the menu is open. The menu closes by itself if the target dies, leaves range (`SOCIAL_RANGE` × 1.5, start) or the player dies.
- While the menu is open, LMB only confirms options and RMB does nothing.
- Holding F with no character under the cursor does nothing (the HUD hint can say "Hover someone to interact").

### 4.2 Options (start set)

Each option shows an icon and a short label. Options that can't be used right now are greyed out, and hovering one shows the reason ("They're angry with you.", "Their group is full.", "You're in a group: leave it first.").

| Option | Available when | Resolution (reuses) |
|---|---|---|
| **Invite to group** | Player is solo, or leads a group with room; target is solo | Target is happy: accepts if opinion of you ≥ 0. Neutral: `Social.cha_roll(player, target)`. Angry: refuses. Same logic as `_happy_meets`. |
| **Ask to join** | Player is solo; target's group has room | Target is happy or neutral: their opinion of you ≥ 0, or a CHA roll. Then `Factions.join(player, target.faction)`. |
| **Demand goods** | Target is not in your group or kingdom | §4.3 |
| **Recruit to gang** | Player is angry; target is angry | The `_angry_meets` gang path, with the player as initiator (a lost roll means a fight to the death) |
| **Trade** | Both in groups, not the same group | `Social._trade(player, target)` (the existing automatic surplus swap). A real barter window comes later (§7). |
| **Challenge** | Target not in your group | `Combat.start_fight(player, target, true)` (fight to the death) |

- Options sit at fixed positions so muscle memory works (start: friendly ones on top, hostile ones on the bottom).
- The pair cooldown (`PAIR_COOLDOWN`, 30 s) applies to player-started actions too, so a refused invite can't be spammed. A greyed option shows "Ask again in 12 s".
- Every result goes to the feed as tier 1 ("Bram agrees to join you.", "Bram refuses: he doesn't like you.").

### 4.3 Demand goods ("verbal rob")

New `Social.player_demand(p, t)`, built on `_demand`:
- **Not gated on the player's mood** (agreed: the player chooses their own actions).
- **Talk down:** if the target is happy and the player isn't dominant (`auth < target.auth × AUTH_DOMINANCE`), the target gets the usual `cha_roll(t, p, TALK_DOWN_MULT)` to talk you down and walk away.
- Otherwise the target responds as in `_demand` with `attack = false`: **stands up and fights** (power ≥ 1.2×), **flees** (faster than you, or you have a bow ready), or **complies**.
- **Complying drops the goods** (agreed with the user's example): instead of `Combat.rob` moving the goods straight into the robber's pack, the target drops `DEMAND_FRACTION` of each stack as a loot bag at their cell (`World.drop_loot(t.cell(), stacks, [], t.id, "dropped for %s")`). The player walks over it to pick it up. This works with a full pack, and other people can see it.
- Same consequences as an NPC robbery: the target's mood −15 and opinion of you −40, `Relations.change(.., REL_ROB)`, `World.social_counts.robberies += 1`. Their group may remember it (raids, war), just as if an NPC did it.
- Feed: "You demand Bram's goods. He drops 8 wood and 3 stone." / "Bram stands up to you!" / "Bram flees." / "Bram talks you down."

### 4.4 How it plugs in

- New `ui/SocialRadial.gd` (a CanvasLayer that draws the ring with `_draw()` and handles the hover direction and LMB).
- `PlayerController` keeps `social_target_id` and the F-held state. On confirm it sets a `_social` intent `{option, target_id}`, and `control()` calls the matching `Social.player_*` function inside the sim step.
- New functions in `social/Social.gd`: `player_invite`, `player_ask_join`, `player_demand`, `player_recruit_gang`, `player_trade`, plus `player_options(p, t) -> Array` (availability and reasons). The UI reads only `player_options`, so the rules stay in one place.

## 5. Showing social state (agreed)

### 5.1 Hover card

When a character is hovered (same rule as §4.1, no F needed), show a compact label above them:
- **Name**, in their faction colour, with the group name after it ("Bram · Ash").
- **A very slim health bar** under the name (agreed). Start: 2 px tall and as wide as the name, red over dark grey, only the bar with no number.
- **Mood:** an icon for happy, neutral or angry.
- **Opinion of you:** a small word plus colour (start: Hostile ≤ −50, Wary < 0, Neutral, Friendly ≥ 30).
- A tag for "your group", "your servant" or "at war" where it applies.

### 5.2 Mood icons near the player

- NPCs within `MOOD_ICON_RANGE` (start: 8 cells) of the player get a small mood icon over their head (happy, angry, or nothing for neutral to keep the screen calm, start).
- The hovered NPC shows the hover card instead of the icon.
- The "!" offer marker (§3.3) replaces the mood icon on the asking NPC.

### 5.3 How it plugs in

- New `ui/SocialOverlay.gd` (a CanvasLayer under the HUD that draws in screen space, so text stays crisp at any zoom). It reads agent state only. It doesn't draw anything outside the player's nearby set, so the cost stays tiny at 120 agents.
- It shares the hover pick with `PlayerController` (one `hover_agent()` helper), so the hover card and the radial always agree on the target.
- Icons: placeholder shapes drawn in code at first, then sprites once art exists.

## 6. Phases (proposed)

| # | Phase | Done when |
|---|---|---|
| 1 | **Input cleanup:** F no longer eats; eating is LMB with food only (§2) | `--playtest` / `--inputtest` pass with the new eat path |
| 2 | **Hover and social state** (§5): hover pick, hover card with a slim health bar, mood icons near the player | Hovering shows name, health, mood and opinion; icons appear within range |
| 3 | **Offer system and prompt UI** (§3): `Offers` queue, card with clickable F1 / F2 buttons, timeouts, `invite` and `gang` | Accepting an invite joins the group; declining or a timeout refuses; mouse and keys both work |
| 4 | **Time-critical prompts:** `demand` and `plead` | Handing over, refusing, sparing and finishing all work; hitting a pleading NPC finishes them |
| 5 | **Radial menu** (§4) with Invite, Ask to join, Demand goods (loot drop), Recruit, Trade, Challenge | Every option resolves through `Social.player_*`; greyed options show reasons; cooldowns hold |

- Each phase: `--bench` (40 min, seed 12345) per-minute stats must match the build before. Nothing here may change NPC-only behaviour, and with no player the offer path applies today's defaults.
- `--playtest` grows a check per phase (prompt accept, decline, timeout; radial demand drops a bag; greyed reasons).
- **Effort (rough):** phase 1 ~1 h, phase 2 ~1 day, phases 3–4 ~1–2 days, phase 5 ~2–3 days.

## 7. Later (out of scope here)

- Giving servants orders (follow, gather, guard).
- Leader and king controls: kingdom invites and alliances, tax, push-out, declaring war.
- A real barter window for Trade.
- Talk-down for the player when an NPC demands their goods (a third prompt button with a CHA roll).
- Player-started compliments or insults as cheap opinion levers.

## 8. Open questions

- The F1 / F2 keys: fine for now. Revisit if F1 is wanted for help or an overlay later.
- ~~Should groupmates defend the player?~~ **Yes (agreed 2026-11-24).** This already worked: `Combat.call_defenders` only skips the player as a *defender*. A `--playtest` check now covers it.
- Should opinion be shown as a word (start) or as a number on the hover card?

## 9. Implementation notes – phases 1–3 (2026-11-24)

Phases 1–3 are built. Phases 4 and 5 are covered in the next section.

**Phase 1: input**
- F no longer eats (`_eat` intent and `KEY_F` branch removed from `PlayerController`). Eating is LMB with berries in the active slot (`_use_held`, unchanged). F is free for the radial menu (phase 5).
- **The debug menu moved from F1 to F3** (`ui/DebugMenu.gd`, HUD hints, `--inputtest`), because F1 / F2 now answer prompts.

**Phase 2: hover and social state**
- `PlayerController.pick_agent(p)` / `hover_agent()` / `hover_id`: the living character nearest the mouse within `HOVER_PICK` (0.75 cells), never the player's own body. Updated per frame in `_process`; cleared while dead or watching. The radial menu will reuse it.
- `ui/SocialOverlay.gd` (CanvasLayer, placed under the HUD in `Main.gd`): the hover card (name · group (kingdom) in the group's colour; a 2 px health bar under the name; a mood face, the mood word, the opinion word in colour, and a tag: your group / kingdom / servant / master, at war), mood faces over happy and angry NPCs within `MOOD_ICON_RANGE` (8 cells), and a pulsing gold "!" over the NPC whose prompt is on screen.
- Opinion words (start): Hostile ≤ `GRUDGE` (−50) < Wary < −10 ≤ Indifferent < 30 ≤ Friendly.

**Phase 3: offers and prompts**
- `player/Offers.gd` (owned by `PlayerController.offers`): the queue (max `OFFER_QUEUE_MAX` = 3, one per NPC). `answer(yes)` is set by F1 / F2 or the prompt buttons and applied in `control()` → `Offers.step` → `Social.answer_offer`, inside the sim step. Offers whose asker died are dropped; expired ones get the default answer.
- `Social.ask_player(p, kind, npc, text, yes, no, secs)`: queues the prompt and gives the asker an `IDLE` job (`PRIO_TASK`, marked `Job.item = Social.WAIT_ANSWER`) so it waits nearby. Needs and fights still come first. It returns false with no player controller, a full queue, or an offer already open from that NPC, and the caller then applies the old default rule. So `--bench` (no player) is untouched.
- `Social.offer_blocked`: on accept, re-checks that the asker is alive and within `OFFER_RANGE` (12 cells), nobody is fighting, the player is still solo, the asker's group is the same one (`fid`) and still has room. If not, the player gets "The offer is no longer open: …".
- Kinds built: `invite` (`_happy_meets`) and `gang` (`_angry_meets`, only when the gang join is possible; otherwise the old angry flow runs). Timeouts: `OFFER_SECS_INVITE` / `OFFER_SECS_GANG` 10 s.
- Feed: `invite` now reads "You turn down Bram's invite." or, on a timeout, "Bram's invite runs out. You don't join." The new kind `gang_refused` reads "You refuse to run with Bram." or "Bram's gang offer runs out. You don't join."
- `ui/OfferPrompt.gd` (CanvasLayer 2): the top-centre card with a gold border, the asker's name in their group colour, `[F1] Join` / `[F2] Refuse` buttons (`FOCUS_NONE`, so keys stay with the game), "+N more" when others are queued, a 0.2 s fade-in and a timer bar that turns orange in the last 30%.
- **Rule change for the player only:** declining an invite or gang offer costs −5 of the asker's opinion of you (`OFFER_DECLINE_OPINION`). A declined or expired gang offer rolls `_attack_chance` instead of always ending in a fight.
- **Not covered yet:** an NPC joining the *player's* group (`_happy_meets`, when the player is in a group with room) still happens without asking. It's a candidate for a later "Bram asks to join your group" prompt, which needs a rule for who answers when the player isn't the leader.

**Tests**
- `--playtest`: an invite asks instead of refusing; the inviter waits; the card shows the right text and buttons; declining (and the feed line); the inviter stops waiting; a timeout refuses (and the feed line); clicking Join forms a group; **a groupmate defends the player**; an angry NPC's gang offer, accepted; the hover pick; the opinion words. It also frees any servant left from the fight test first, since a player with a servant is a group, not solo. All pass, headless and windowed. Windowed, it saves `user://playtest_prompt.png`.
- `--inputtest`: F3 opens and closes the debug menu, F2 declines and F1 accepts a real invite. The F1 check retries with a fresh NPC if the asker joined someone else first (the sim runs in real time there). The old "LMB places a wall at the cursor" flake (the real mouse over the window) still shows up in some runs, as noted in the Player Controller Plan.
- `--bench=40` (seed 12345): every line matches the build before, compared against a run of HEAD with the same seed (121.9 s real).

## 9. Implementation notes – phases 4–5 (2026-11-24)

**Phase 4: demand and plead prompts**
- `Social._demand` asks a player target (`demand`, `OFFER_SECS_DEMAND` 5 s). The robber waits with an `IDLE` job at `PRIO_NEEDS`.
  - **Hand over** (`Social._hand_over`): `Combat.rob` at `DEMAND_FRACTION`, with the same mood, opinion and relations effects as an NPC complying. Feed: "You hand 5 items to Bram."
  - **Refuse, timeout, or walking more than 2 × `SOCIAL_RANGE` away:** the NPC attacks, as the old default did. Feed: "… You refuse and fight back!" or "… You don't answer, and they attack!"
- `Combat.plead` asks a player attacker (`plead`, `OFFER_SECS_PLEAD` 5 s). The victim stops fighting (`IDLE` at `PRIO_CRITICAL`). The old body of `plead` is split into `plead_roll` (the 50/50 roll) and `refuse_plea` (the fight to the death). NPC-only behaviour is unchanged (same RNG order, and the bench matches).
  - **Spare:** `Combat.accept_surrender(player, npc)`, which makes them a servant, or spares and robs them if your group is full.
  - **Finish:** `refuse_plea`.
  - **Hitting them while the prompt is up counts as Finish** (`Combat.apply_damage` takes the offer back out of the queue).
  - **No answer:** the usual `plead_roll`.
  - Feed: "Bram begs you for mercy." then "Bram surrenders to you." or "You refuse Bram's plea."
- Demand and plea prompts are **urgent**: they jump to the front of the queue and may go one past `OFFER_QUEUE_MAX`.
- Feed: kinds named `p_*` carry text already written for the player and are shown as they are.

**Phase 5: radial menu**
- **Input (agreed):** F press opens the menu on the hovered character within `SOCIAL_RANGE` (otherwise a hint: "Hover someone…" or "Get closer to Bram."). Releasing F closes it (checked per frame with `Input.is_physical_key_pressed`). While it's open, LMB only confirms the highlighted usable option, which closes the menu; clicking a greyed option shows its reason. RMB does nothing. WASD still moves. The menu also closes if the target dies or gets more than 1.5 × `SOCIAL_RANGE` away.
- `ui/SocialRadial.gd` (CanvasLayer 2): centred on the target (kept on screen), 6 bubbles at `RADIUS` 84 px, a dead zone of 24 px, a gold highlight and pointer. A greyed option is drawn grey, and its reason shows under the ring when highlighted. It reads only `Social.player_options` and sets `player.radial_sel` / `radial_why`. The choice is applied in `control()` → `Social.player_act`, and the result shows as the HUD message and a feed line.
- **Options and positions** (clockwise from the top): Invite to group, Ask to join, Trade, Demand goods (bottom), Challenge, Recruit to gang.
- **Rules as built** (`Social.player_why` / `player_act`):
  - Common: the target must be within 1.5 × `SOCIAL_RANGE` and not fighting (Challenge excepted). Structural reasons ("They're in your group.") show before the pair cooldown ("Ask again in 12 s"). Every action except Challenge sets the 30 s pair cooldown.
  - **Invite:** target solo, not a servant, not angry; your group (if any) has room. Any member can invite, as with NPCs, not only the leader. Accepts if happy and their opinion of you ≥ 0, or neutral and you win the CHA roll. Never if their opinion is at or below `GRUDGE`. A refusal costs −2 opinion.
  - **Ask to join:** you're solo; their group has room; they're not angry. Same willingness rule.
  - **Trade:** both in groups, different groups, they're not angry. It runs the existing `_trade` (which now returns what changed hands). Feed: "Trade with Bram: you give 2 Wood and Bram gives 2 Stone."
  - **Demand goods:** anyone not on your side (your group or kingdom). §4.3 as planned: the talk-down roll if they're happy and you aren't dominant; they stand up if their power ≥ 1.2 × yours; they flee if faster or you hold a ready bow. Otherwise they drop half of each stack as a loot bag at their feet and back off 5 cells. Same robbery effects as NPCs.
  - **Challenge:** anyone not in your group. `Combat.start_fight(player, t, true)`.
  - **Recruit to gang:** you and they are both angry; they're solo; your gang has room. CHA roll: a win forms or joins the gang. **A loss means a fight to the death, the same as between NPCs.**
- HUD hint: "hold F talk" in the controls line. While the menu is open: "Move the mouse to an option, LMB to confirm, release F to cancel". The hover card hides for the menu's target.

**Tests**
- `--playtest`:
  - Phase 4: a demand prompt jumps the queue and the robber holds its ground; handing over gives up half; an unanswered demand means a fight. A plea prompt stops the victim; Spare makes a servant; a hit finishes; an unanswered plea rolls.
  - Phase 5: the direction pick and the dead zone; Demand drops a loot bag and greys the next action with the cooldown; Invite and Ask to join work; greyed reasons (recruit while not angry, trade while solo, too far, own group); the menu lists 6 options. Windowed, it saves `user://playtest_radial.png`.
  - It also clears offers NPCs made naturally during the earlier steps.
- `--inputtest`, with real input: hovering picks the NPC; holding F opens the menu; moving the mouse down highlights Demand goods; LMB confirms it without a swing and closes the menu; releasing F closes it. The respawn walk check now walks towards open ground, because the random respawn spot sometimes has a wall beside it.
- `--bench=40` (seed 12345): every line matches a run of HEAD with the same seed (118.3 s vs 118.0 s real).
