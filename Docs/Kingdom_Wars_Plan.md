# Anarchy Colony Sim — Kingdom Wars and Tax Plan

**Status: built (KW1–KW6). Implementation notes and first playtest in §9–§10.**
**Replaces:** `Docs/Vicious_Kingdoms_Plan.md` (the earlier draft). Where the two disagree, this plan wins.
**Builds on:**
- v3 (`Docs/Kingdoms_Plan_v3.md`): push-out ladder, power checks, raids, smelteries and gear.
- The Performance Plan (B1–B5): cached group lookups, per-job think intervals.

**Goal:**
- Kingdoms hate each other and fight until one side is broken.
- Losing kingdoms scatter, so their survivors restart the anarchy.
- Kingdoms tax the independent groups around them. The resentment drives those groups towards gangs.

> **(agreed)** marks values decided in design. **(start)** marks starting values for playtest tuning.

---

## 1. Kingdom wars

### 1.1 Standing between kingdoms (agreed)
- **All kingdoms hate each other, always.** Kingdom-to-kingdom relations are not tracked.
- The random −40 war roll (`Relations.encounter`) is **switched off** between groups of different kingdoms.
  - The ally roll already can't merge kingdoms (`Kingdoms.try_ally`).
- Relations between a kingdom's groups and independent groups or gangs work as today: trades, shared fires, invites, push-outs.

### 1.2 Who declares war on whom (agreed)
**The war check runs every 60 s per kingdom.** A kingdom may declare war only if all of these hold:
- It is **not already at war** with another kingdom. A kingdom is only ever in **one kingdom war at a time**, as attacker or defender. This stops the weakest kingdom from being dogpiled.
- It is **not under grace** (§1.3).

**The target:**
- The **weakest rival kingdom** that is not at war with a kingdom and not under grace.
- The attacker must have at least **0.8×** that rival's power (start). Near-equals still fight, so there is no stalemate. Hopeless kingdoms wait.
- Power is `PushOut.kingdom_power()`: the sum of members' `fight_power()`, gear included.

**Ties and order:** if two free kingdoms could each declare on the other in the same round, the **stronger one declares**.
- Implementation: run all kingdoms' checks in one pass each 60 s, in order from strongest to weakest.

**No range limit.** Any kingdom can war with any other kingdom on the map.

**The defender has no choice:** the war starts the moment it is declared.

### 1.3 Grace period (agreed)
- A newly formed kingdom gets **20 minutes of grace** (start), counted from `Kingdom.founded`.
- **Grace works both ways:** a kingdom under grace can't be declared on, and it can't declare war itself.
- It can still tax (§3) and push neighbours out (v3) as normal.

### 1.4 No prisoners (agreed)
Between members of two kingdoms at war with each other:
- **No pleading, no surrender, no servants.** Every fight is to the death (`Combat.start_fight(..., to_death = true)`, which already skips pleading).
- **The one exception is fleeing:** a member **below 30% HP** (start) runs from enemy kingdom members instead of attacking.
  - It doesn't start fights, and it flees if attacked (`Brain.flee`).
  - It still counts as **alive** for the retreat and scatter checks (§1.6, §1.8).

### 1.5 Attack on sight (agreed)
- During a kingdom war, **every member** of either kingdom drops what it is doing and attacks an enemy kingdom member **within 8 cells** (start). Mood doesn't matter.
- Members below 30% HP flee instead (§1.4).
- Respawned lone agents and independent groups aren't involved.
- Implementation: a periodic check for each member of a warring kingdom, at the 0.25 s combat think rate, that starts a to-the-death fight at `PRIO_CRITICAL`.

### 1.6 The kingdom-wide raid (agreed)
Kingdom wars use **one big raid per kingdom** instead of separate group raids.

**Both sides raid.** The defender may raid the attacker, even when it is the weaker kingdom: offensive defence.

**Party:**
- Every group in the kingdom sends its healthy members (above 50% HP).
- A group with 4+ members keeps one keeper at home, as in today's `Raids._party`.
- One raiding axe per group in the party is enough to start the raid (start), not one per raider.

**Rally:**
- The party gathers at **its own kingdom's capital** (§1.7), then marches on the target kingdom together.
- The rally phase waits for 70% of the party, or gives up waiting after a time limit, as today.

**Targets, in order (agreed):**
1. The enemy **capital** (the king's house).
2. **Smeltery**.
3. **Workshop**.
4. The **nearest** other enemy building.

When one target is sacked, the same raid moves on to the next target in the list. It doesn't go home after each sack.

**Retreat (agreed):** the raid retreats only when both are true:
- **25% or less** of the party it set out with is still alive (75% killed).
- The **live defenders** in the target's zone outnumber the **live raiders** **2× or more**.

Otherwise it keeps fighting.
- The time limit for a kingdom raid is **6 minutes** (start), against 3 for other raids, to allow for the longer march.
- Gang raids and raids against independent groups keep today's rules (retreat when half the party is down, 3-minute limit).

**Next raid:** once a raid ends, the next one launches when at least **70% of the kingdom's members are above 50% HP** (start).

**Loot:**
- Raiders take everything from sacked chests and crates, as today.
- Kingdom raiders then carry their loot home to the **capital's chest**.

**Defence:**
- Every member of the target kingdom is called home to defend, not just groups within 30 cells. The on-sight rule (§1.5) already pulls everyone into the fight.

### 1.7 The capital (agreed)
- The capital is the **king's house**: the leading group's city house (`Cities.centre_cell` already points at the king's house fire).
- If the king changes, the capital moves to the new king's house.
- If the capital is sacked (fire out) and the kingdom hasn't scattered, the king's group rebuilds through the normal ladder.
  - While there is no capital, raids skip straight to the smeltery, then the workshop.

### 1.8 Scatter: losing a war (agreed)
**The losing kingdom scatters when both are true:**
- **25% or less** of the members it had **when the war started** are still alive.
  - The baseline is recorded at declaration. Recruits who join during the war count towards the living total.
- The **enemy kingdom** has at least **2×** its living members.

If both kingdoms are at 25% or less and neither outnumbers the other 2×, **they keep fighting**.

**Mid-war dissolution:** if the losing kingdom drops below 2 groups during the war (for example, a group turns gang), its survivors **scatter too**.

**What scattering does:**
- Every group in the losing kingdom **disbands**, so every member becomes a lone agent.
- They **lose each other**: each survivor picks its **own random direction** and runs **40–80 cells** (start), then carries on as a normal loner. There's no guarantee they will ever end up in the same group again.
- Their houses are **abandoned**: fires go out and the houses decay. Chests are left as they are, for anyone to loot.
- Servants are freed.
- **The winner does not chase** scattering agents. They also can't join the winner: they lost.
- The kingdom dissolves, and the war ends as a **win** for the other side.

### 1.9 War without a winner (agreed)
- A kingdom war ends after **10 minutes without raids** (the v2 `PEACE_SECS`).
- A **5-minute truce** (start) follows for that pair. Neither may declare on the other until it ends.
- Both kingdoms are free to declare on **other** kingdoms straight away (§1.2).
- When the truce ends, the 60 s check may declare between them again, by the 0.8× rule.

### 1.10 Kingdom wars and other wars (agreed)
- **"At war" in §1.2 means kingdom wars only.** These don't count:
  - push-out wars with independent groups
  - tax wars (§3)
  - gang raids
- Those keep running under v3 rules, alongside any kingdom war.

---

## 2. Vassals: deferred

Not part of this plan. Losers scatter (§1.8); nobody joins the winner. To be revisited after this plan has been playtested.

---

## 3. Tax

### 3.1 Who is taxed (agreed)
- **Every 5 minutes** (start), each kingdom taxes every **independent group** with a house in its **tax ring**.
- **The tax ring:** within **44 cells of the capital** (2× `PUSH_RADIUS`). Groups within 22 cells are handled by push-outs instead.
- **Not taxed:**
  - gangs
  - lone agents
  - groups that belong to any kingdom
  - groups without a chest
- A group inside two kingdoms' rings pays only the **nearest** kingdom.
- **Taxing continues while the kingdom is at war.**
- A group can escape tax only by happening to settle outside the ring. Nothing makes it move.
- **A group can't escape tax by joining the kingdom:** being taxed never leads to an invite.

### 3.2 What is taken (agreed)
- **What the kingdom needs first:** shortfalls on its task board and stocking goals.
- **If nothing is needed, a baseline:** 5 wood, 5 berries and 1 iron per member (start).
- **The total is capped at the baseline's worth:** up to 11 items per member.
- **Take what is there:** if the chest is short, the kingdom takes what it has. If nothing is there, nothing is taken. Either way the tax counts as **paid**.
- It is taken directly from the group's chest. Nobody walks anywhere in this version.

**Where it goes:**
- Iron goes into the kingdom's **smeltery crates** if there is room.
- Everything else goes into the **capital's chest**.
- **Correction:** ordinary chests do have limits (30 / 60 / 90 slots by tier). Only the **capital's chest** has no limit (see §9), so taxed and plundered goods always fit there.

### 3.3 Resist or pay (agreed)
**The group resists if:**

> group power × anger factor > kingdom power near the group × courage threshold

Where:
- **Group power** = `PushOut.group_power()` (`fight_power()`, gear included).
- **Anger factor** = 1.0 + 0.5 × the share of members who are angry + 0.1 × the times this group was taxed in the last 30 minutes.
- **Kingdom power near the group** = the summed `fight_power()` of that kingdom's members within **30 cells** of the group's house.
  - A lightly guarded area is worth resisting; armoured soldiers nearby make resistance futile.
- **Courage threshold** = 1.0 (start).

| Outcome | Effects (start values) |
|---|---|
| **Pays** (including "nothing to take") | Goods move as in §3.2; −8 mood per member; −5 relation with the kingdom's leading group |
| **Resists** | The existing push-out war (`PushOut._war`) against that group: the kingdom raids its houses until peace; −15 relation |

- **A tax war isn't a kingdom war:** it doesn't count towards the one-kingdom-war limit (§1.10).
- **Why this matters:** repeated tax pushes moods down, so taxed groups drift towards gangs. That should keep gangs alive past the early game, which v3 lacks.

### 3.4 Later: tax collector parties (not now)
- These would be built on the raid machinery: rally, march, then "collect" instead of "assault".
- The target group would decide when the collectors arrive, using the power of the collectors actually present.
- This is a natural role for the player later: collector, guard or rebel.

---

## 4. Config (proposed names)

| Constant | Value | Meaning |
|---|---|---|
| `KWAR_CHECK_SECS` | 60.0 | How often kingdoms check for a war (agreed) |
| `KWAR_POWER_RATIO` | 0.8 | Attacker power ≥ this × target power (agreed) |
| `KWAR_GRACE_SECS` | 1200.0 | New kingdom grace, both ways (agreed) |
| `KWAR_TRUCE_SECS` | 300.0 | Truce between a pair after peace (agreed) |
| `KWAR_FLEE_HP` | 0.3 | Below this share of HP, flee instead of fighting (agreed) |
| `KWAR_SIGHT` | 8.0 | Attack-on-sight range in cells (start) |
| `KWAR_LOSS_SHARE` | 0.25 | Scatter / retreat when this share or less is alive (agreed) |
| `KWAR_OUTNUMBER` | 2.0 | The enemy must have this many times the living members (agreed) |
| `KWAR_RAID_MAX_SECS` | 360.0 | Kingdom raid time limit (start) |
| `KWAR_RAID_READY` | 0.7 | Share of members above 50% HP before the next raid (start) |
| `SCATTER_MIN` / `SCATTER_MAX` | 40 / 80 | How far each scattered survivor runs, in cells (start) |
| `TAX_SECS` | 300.0 | Tax interval (start) |
| `TAX_RADIUS` | 44 | Tax ring around the capital (start) |
| `TAX_BASE` | wood 5, berries 5, raw_iron 1 | Per member, also the cap (start) |
| `TAX_NEAR_RADIUS` | 30 | "Kingdom power near the group" radius (agreed) |
| `TAX_ANGER_SHARE` / `TAX_ANGER_REPEAT` | 0.5 / 0.1 | Anger factor terms (agreed) |
| `TAX_REPEAT_WINDOW` | 1800.0 | Window for "times taxed" (agreed) |
| `TAX_COURAGE` | 1.0 | Courage threshold (start) |
| `TAX_MOOD` / `TAX_REL` / `TAX_RESIST_REL` | −8 / −5 / −15 | Pay and resist effects (start) |

---

## 5. Implementation notes (where it plugs in)

- **Wars (`faction/Wars.gd`):** each war entry gains:
  - `kingdom: bool`
  - `attacker: side`
  - `start_members: {side: int}`, recorded at declaration for §1.8
  - a truce list `{pair: until}`

  `Wars.update` keeps the 10-minute peace rule and adds the truce on a kingdom-war peace.
- **War check:** a new `KingdomWars.update()` runs every `KWAR_CHECK_SECS` from `World` next to `Kingdoms.update_all()`. It sorts kingdoms by power and applies §1.2–§1.3.
- **Relations:** `Relations.encounter` skips the war roll when both groups are in different kingdoms.
- **No prisoners:** in `Combat.start_fight`, `on_attacked` and `call_defenders`, fights between members of warring kingdoms are `to_death`. `apply_damage` already skips pleading for death-match pairs. Below `KWAR_FLEE_HP`, `on_attacked` flees instead of fighting back.
- **Attack on sight:** a check in `Brain` for members of a kingdom at war, using `World.agents_near`, run at the combat think rate (the B3 per-job intervals keep fights at 0.25 s).
- **Kingdom raid (`faction/Raids.gd`):**
  - `Raid` gains a `kingdom` reference and a target queue.
  - `consider` for a kingdom at war in a kingdom war builds one party from all groups (one raid per kingdom) instead of per group.
  - The war target follows §1.6 (capital → smeltery → workshop → nearest), with no range limit.
  - The retreat check follows §1.6.
  - `_win` advances to the next target instead of ending the raid.
  - Loot is delivered to the capital chest via a chest job after the raid.
- **Scatter:** a new `KingdomWars.scatter(k)`:
  - For each group, abandon its houses (`Factions.abandon_house`) and free its servants.
  - Then `Factions.disband` the group, and give each agent a far `Brain.flee` towards a random point 40–80 cells away.
  - Then dissolve the kingdom, end the war, and log it.
- **Tax:** a new `Tax.update(k)` runs from `Cities.update` on its own timer. Each group keeps a list of tax times for the anger factor's repeat term.
- **Cache invalidation (B4):** anything that changes membership or houses must bump `World.buildings_version` and set `World.zones_dirty = true`, as `Kingdoms.join`/`leave` do. That covers scatter, disband and abandoning houses, so the cached group lookups don't go stale.

---

## 6. Phases

| # | Phase | Done when |
|---|---|---|
| 1 | **War check:** no kingdom relations, the 60 s check, the 0.8× weakest-target rule, one war per kingdom, grace, truce | Kingdoms declare on each other in the log; no kingdom is ever in two kingdom wars; new kingdoms are left alone for 20 min |
| 2 | **No prisoners and attack on sight:** to-the-death fights, fleeing below 30% HP, the 8-cell on-sight rule | Warring members fight wherever they meet; no servants or surrenders between warring kingdoms |
| 3 | **Kingdom-wide raid:** one party per kingdom, rally at own capital, target order, retreat rule, next-raid readiness, loot home | One big party marches on the enemy capital; raids move from target to target; both sides raid |
| 4 | **Scatter:** the loss check, disband, run in random directions, houses abandoned | Losing kingdoms break up into loners spread over the map; the winner doesn't chase |
| 5 | **Tax:** the ring, what is taken, resist or pay, tax wars | Groups in the ring pay or resist; taxed groups' moods drop; gangs last longer |
| 6 | **Counters:** bench line and HUD | Everything in §7 is visible |

Run a 60-minute bench after each phase.

## 7. Bench line and HUD

**Bench line:**
- kingdom wars declared, ended by scatter and ended by peace
- capitals sacked
- kingdom raids started, won and retreated
- deaths during kingdom wars
- agents scattered
- tax runs: paid, nothing to take, resisted
- tax wars

**Group panel:**
- the kingdom's current war (enemy, and members alive against the starting count)
- grace or truce time left
- for taxed groups: the last tax taken and the times taxed in the last 30 minutes

## 8. Things to watch

- **The death toll against respawns** (the population is held at 120). The v3 push-out war already killed about 55 in 6 minutes, and to-the-death kingdom wars could be much worse.
- **One kingdom taking over:** scattered loners should re-form groups and then new kingdoms. The 20-minute grace should give them time. Does the map cycle, or does one kingdom sit alone?
- **Stalemates:** do two kingdoms that are both below 25% ever finish? If not, the 10-minute peace rule ends it. Check that this happens.
- **Raid marches across the map:** pathing cost and time limits on long marches. Is 6 minutes enough?
- **Tax and gangs:** does tax resentment make gangs viable without separate mood tuning?
- **The capital chest:** with no size limit it grows forever. That is fine for now, but it makes the capital a very rich raid target, which may be a feature.

---

## 9. Implementation notes

All six phases are built. New modules: `faction/KingdomWars.gd` (war check, grace, truce, attack on sight, scatter, capital) and `faction/Tax.gd`.

**Deviations from the plan and clarifications:**
- **The capital's chest has no limit.** The plan assumed chests had no size limit, but they do (30 / 60 / 90 by tier). Only the capital's chest is unlimited (`Furniture.slots()` checks the cached `Kingdom.capital`). Other chests keep their limits.
- **The capital** is the king's group's finished city house with a burning fire, nearest the city centre. When it is sacked, the next such house becomes the capital, so a raid may "move on to the capital" twice in a row.
- **Push-outs no longer touch other kingdoms.** The v3 "city stands too close: war" rule between kingdoms is removed. All kingdom-against-kingdom wars come from `KingdomWars`.
- **Group raids pause during a kingdom war.** A group in a kingdom at war in a kingdom war starts no raids of its own, not even in push-out or tax wars. Every hand goes to the kingdom-wide raid. Those wars resume once the kingdom war ends.
- **Raiding axes:** a kingdom raid needs at least **one raiding axe in the whole party**, not one per group.
- **Mid-war falling apart:** if a kingdom dissolves during a kingdom war (a group turns gang, groups die out), its survivors scatter. The log says "falls apart mid-war" instead of "is broken by".
- **What the tax takes first:** the capital chest's stocking shortfall (berries, spare axe and pickaxe, a weapon) comes first, then the baseline. Board-task shortfalls are not included.
- **Tax wars** use `Wars.declare` (a normal kingdom-versus-group war) and skip groups already at war with the kingdom. A group that resists is taxed again once that war ends in peace.
- **Fleeing below 30% HP** applies to fights between warring kingdoms only: on sight, when attacked, and mid-fight (`Brain._run_fight`). A fleeing agent stays in the raid party and counts as alive.

## 10. First playtest observations (seed 12345, 60-minute bench)

**Run A (KW1–KW4, before tax):**
- 3 kingdom wars declared, the first at minute 28 (right after the 20-minute grace ran out for the first kingdoms).
- 2 kingdoms scattered (10 survivors). 61 deaths from enemy kingdom members.
- 5 kingdom raids, 1 retreat, 3 capitals sacked.
- **Norholt against Valdale:** Norholt marched 18 raiders on the capital. The sacks went capital → capital → smeltery → workshop → house, the plunder (29–32 items per sack) went home, Valdale raided back, and Valdale scattered at minute 52.
- Morgard then declared on the weakened winner at once (280 vs 77). The weakest-target rule punishes a winner straight after its war.
- Deaths 160 in 60 minutes (v3 baseline: 116). 179 s real for 60 sim minutes.

**Run B (all phases):**
- 5 kingdom wars, 5 scatters (13 survivors), 41 war deaths, 2 kingdom raids, 2 capitals sacked.
- Several small kingdoms broke or fell apart within a minute or two of being declared on. A kingdom of two small groups barely survives a war.
- Halmoor ended up breaking Ostholt (the kingdom that had broken three others) with a 16-raider march.
- Deaths 188 in 60 minutes. 157 s real for 60 sim minutes, about 2.6 s per sim minute, no slower than before.
- **Tax: 1 paid, 10 resisted.** Almost every resist logged **0 kingdom power nearby**. The groups being taxed sit 23–44 cells from the capital, and the 30-cell "near" radius around *their* house rarely catches a kingdom member, since members cluster in the city. Result:
  - Tax mostly produces tax wars rather than payments.
  - Moods stay high (about 75–90 happy agents of 120).
  - Gangs haven't been helped yet.
- **Tuning to decide:** count "kingdom power near the group" from a larger radius (for example 50), count the whole kingdom's power scaled by distance, or lower the courage threshold. `TAX_NEAR_RADIUS` is marked (agreed), so it was left as is.
