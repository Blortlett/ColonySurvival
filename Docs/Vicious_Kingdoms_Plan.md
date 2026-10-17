# Anarchy Colony Sim — Vicious Kingdoms Plan (draft)

**Status: draft, not ready to build.**
> **Before starting:** ask the user to settle the **vassal tier** (§2). It is underbaked on purpose. Kingdom rivalry (§1) and the simple tax (§3) are close to ready.

**Builds on:** v3 (`Docs/Kingdoms_Plan_v3.md`): push-out ladder, power checks, wars, raids.
**Goal:**
- Kingdoms aim to be the only kingdom on the map.
- They are nice to small groups but squeeze them for tax.
- Taxed groups resent it, and that resentment keeps the anarchy going (angry groups turn into gangs).

> As before, **(agreed)** marks values decided in design and **(start)** marks starting values for playtest tuning.

---

## 1. Kingdoms against kingdoms (agreed idea)

- **Bad standing by default:** every pair of kingdoms starts at a poor relation (start: −30), and it drifts down over time.
- **Opportunistic war:** a kingdom declares war on a rival when it is clearly stronger (start: total power ≥ 1.3× the rival's). It uses the same power sums as the v3 push-out check, so armour counts. Weaker kingdoms hold back and arm up.
- **Nice to groups:** relations with independent groups work as today (trades, shared fires, invites).
- **Conquest:** when a kingdom's capital (the king's house) is sacked, its groups either **scatter** (leave, become independent) or **join the winner** as vassals (§2). Each group chooses by mood and relation.
- **Watch:** the v3 playtest already showed one bloody push-out war (about 55 deaths in 6 minutes). Kingdom wars could make that much worse.

## 2. Vassal tier — open (user to settle)

Rough idea from the user:
- **Knighted groups:** the original up to 6 groups (the agreed v2 cap) are the kingdom's knighted groups.
- **Vassal groups:** second-class groups beyond the cap. Conquered groups and taxed neighbours could take this route instead of scattering.
- **Layout:** vassals build their houses around the knighted groups. For example, on the outer blocks (block ring 2+) of the city, with knights in the leader's and adjacent blocks.

Open questions:
- What rights do vassals have: shared workshops and smelteries, kingdom board tasks, defence help?
- Do vassals pay tax (§3) while knights don't?
- Can a vassal group rise to knighted (when a knighted group dies out, or on merit)?
- Is there a vassal cap?
- How do vassals revolt (tie in with tax resentment)?

## 3. Tax — simple version first (agreed)

**Every few minutes** (start: 5), a kingdom taxes each independent group whose house is within the tax radius (start: 2× the push-out radius = 44 cells). Vassals may be taxed too, depending on §2.

**What is taken:**
- What the kingdom needs: shortfalls on its task board and stocking goals.
- If nothing is needed, the baseline: wood, food (berries) and iron (start: 5 wood, 5 berries, 1 iron per member).
- It is taken directly from the group's chest; nobody walks anywhere in this version.

**Resist or pay:**
- The decision mirrors the v1 demand rule at group level, using `fight_power()` (gear included).
- The group resists if `group power × anger factor > kingdom power near the group × courage threshold`.
  - The anger factor rises with how angry the members are and how often they've been taxed (start: 1.0 + 0.5 × the share of members who are angry).
  - "Kingdom power near the group" counts kingdom members within a radius of the group's house, not the whole kingdom. That makes a lightly guarded area worth resisting.
- **This keeps the user's point:** fighting armoured soldiers is futile, so resistance only happens when the kingdom is weak nearby.

| Outcome | Effects (start values) |
|---|---|
| **Pays** | Goods move to the kingdom's chests or crates; −8 mood per member; −5 relation |
| **Resists** | Treated as a refused demand: war, or a raid on the group's house (v3 rules); −15 relation |

**Why this matters:** repeated tax pushes moods down, so taxed groups drift towards gangs. That should keep gangs alive past the early game, which v3 lacks.

### Later: tax collector parties (not now)
- Built on the raid machinery: rally, march, then "collect" instead of "assault".
- The target group decides when the collectors arrive, using the power of the collectors actually present.
- A natural role for the player later: collector, guard, or rebel.

## 4. Phases (proposed)

| # | Phase | Done when |
|---|---|---|
| 1 | **Rivalry:** bad default standing, opportunistic kingdom wars | Kingdoms war with each other; the strongest grows |
| 2 | **Simple tax** | Groups pay or resist; taxed groups' moods drop; gangs last longer |
| 3 | **Vassal tier and conquest** | After the user settles §2 |
| 4 | **Tax collectors** (optional) | After the player controller exists |

## 5. Things to watch
- Does one kingdom take over the map? Is that a fun end state, or should there be a revolt mechanic?
- Do war deaths outpace the respawns (the population is held at 120)?
- Does tax resentment make gangs viable without separate mood tuning?
