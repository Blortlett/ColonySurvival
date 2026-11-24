# Anarchy Colony Sim — Character Spritekit Plan (draft)

**Status: the naked human is built and wired in (2026-11-24).** All the unarmed, tool and weapon animations below are in the game. Clothing (§4–§7) is the next phase and not started.

**Builds on:** the agent sprite renderer (`render/AgentLayer.gd`, `render/SpriteAtlas.gd`, `render/BodySets.gd`; Summer Roadmap §3), Godot 4.7.2, GDScript, Python 3 + Pillow for the generator.
**Goal:** one shared, extendable top-down human for every agent and the player. Bodies come in skin tones, carry and use every weapon and tool, and take clothing and armour as separate layers, so pants and shirts are independent. All art comes from one script, so a change to the rig or a palette updates every sheet at once.

> As in the other plans, **(agreed)** marks things decided in review and **(start)** marks starting values for tuning.

---

## 1. What exists today

### 1.1 The generator

`tools/spritekit/spritekit.py` draws every sheet from code. Nothing is hand-painted. Running it rewrites `art/characters/human/` (70 PNGs today).

- **Frame:** 48 × 48 px, character centred at (24, 24), facing **+X**, the same as the old Sci-Fi TDS pack (agreed).
- **Rig:**
  - The torso is an ellipse plus two shoulder balls. `twist` turns the torso around its centre; a positive twist puts the right shoulder back.
  - Each arm is upper arm → elbow → hand, solved with two-bone IK (`elbow()`, bend capped by `MAX_BEND`).
  - The head is a hair cap over a face, with a nose pixel at +X.
  - The legs are a separate layer: hips to bare feet.
- **Pose:** a dict per frame, e.g. `{"twist", "hand_l", "hand_r", "bend", "ox", "over", …}`. An animation is a list of poses. Tool poses use `pommel`/`hand` + `ang` (+ `grip_l`, `fs`, `scale`) and a `*_pose()` helper turns them into hand positions.
- **Drawing:** shapes are ellipses, capsules and polygons, rasterised at pixel centres with banded shading: shadow, base and light by "height". The shading is roughly the same in every direction, so it survives the sprite being rotated in-game.
- **Outlines (agreed):**
  - 1 px dark outline on the **outside** only.
  - Where a part crosses another (an arm over the torso), the outline becomes a soft line: outline mixed with shadow.
  - At joints (shoulder) there's no line at all, so arms read as one limb.
- **Palettes:** `SKINS` (light, dark), `HAIR`, `WOOD`, `DARK_WOOD` (club), `IRON`, plus `STRING`, `FLETCH` and `SMEAR`.
- **Tool layer:**
  - The tool is drawn on its own sheet, frame for frame with the body, with the hands, arms and head **cut out**, so it can always draw on top.
  - Cut-out options per pose: `under_r_shoulder` (spear passes under the right shoulder), `tool_on_arm` (pickaxe resting on the shoulder: only the hand covers it), `over` (arms raised over the head; the head no longer covers the tool).
- **Extras:** `smear_arc()` (pale motion arc on fast cuts, used by the sword) and `bow_layer()` (stave, string, nocked arrow; the bow is held flat).
- **Tool table:** every tool animation is one `TOOL_ANIMS` row: `(name, draw function, pose helper, poses)`.

### 1.2 The animations

Unless noted, every row has one body sheet per skin tone and, for tools, one item sheet shared by both skins.

| Set | Animations | Frames | Plays at |
|---|---|---|---|
| Legs | idle, walk (also run) | 1, 6 | 10 / 12 fps, scaled to speed |
| Unarmed | idle, walk (also run), gather (`use`), punch left / right (`attack`, alternating), death | 1, 6, 8, 4+4, 4 | 1, 10/14, 9, 14, 8 fps |
| Axe | chop (horizontal two-handed), carry idle, carry walk | 6, 1, 6 | 10 fps loop |
| Pickaxe | mine (vertical overhead, head turned to strike tip-first), shoulder idle, shoulder walk | 6, 1, 6 | 9 fps loop |
| Spear | thrust (side-on, the shaft slides through the left hand), carry idle, carry walk | 6, 1, 6 | 14 fps |
| Club | swing (one-handed), carry idle, carry walk | 6, 1, 6 | 14 fps |
| Sword | slash in front with smear, carry idle, carry walk | 6, 1, 6 | 16 fps |
| Bow | fire (flat bow, string bends at full draw), carry idle, carry walk | 6, 1, 6 | 10 fps |

### 1.3 How the game uses them

- **`BodySets.gd`:** one set per skin tone (`human_light`, `human_dark`, equal weight), both built by `_human(skin)`. Each set has `legs`, `torso` and `items`, where `items` maps a torso animation name to the tool sheet drawn over it.
- **`SpriteAtlas.gd`:**
  - Packs every sheet into one mipmapped texture, so all agents draw in **one MultiMesh call**.
  - An item copies its torso animation's fps and looping, so the two can't drift apart. A mismatch in frame count is an assert (agreed, after the axe bug).
- **`AgentLayer.gd` draws per agent:** legs → torso → item (when the torso animation has one). The torso animation is chosen like this:

| Situation | Animation | Rule |
|---|---|---|
| Attacking | `attack_<weapon>` if the set has it, else `attack` | A bow shot is spotted when an arrow leaves the quiver as `attack_cd` jumps. Using the cooldown size alone breaks at high sim speed. |
| Standing at work | `chop` (axe on a tree), `mine` (pickaxe on rock or metal), else `use` (gather) | The player's held-E harvest counts too (`player.harvest_node`). |
| Idle / walk / run | `<anim>_<weapon>` if the set has it, else plain | The weapon shown is `_shown_weapon()`: melee weapon, else the player's held tool (`CARRY_ALIAS` maps `pickaxe_t2 → pickaxe`), else the axe or pickaxe on the way to a tree or rock, else a bow with arrows. |

- **Debug kit:** with the F3 menu open, numpad 1 gives every weapon and tool, 60 arrows, 40 wood and 40 stone (`DebugMenu.give_kit`).

---

## 2. Workflow: adding or tuning an animation

The loop that worked for every animation so far (agreed):

1. **Pose it.** Add the pose list to `spritekit.py`:
   - A plain body animation is a `sheets[...]` line in `build()`.
   - A tool animation is a `TOOL_ANIMS` row (plus an item drawing function if it's a new tool).
   - Name tool rows `<tool>_<anim>` (`club_swing`, `bow_walk`, …).
2. **Generate.** Run this from the project folder:
   ```
   python tools/spritekit/spritekit.py tools/spritekit/preview/kit_preview.png 6
   ```
   It writes every sheet plus an upscaled preview sheet.
3. **Look at it upscaled** (6–8×) as still frames, then as a GIF at the in-game fps, with legs, body and item composited, for both skin tones. GIFs live in `tools/spritekit/preview/`.
4. **Iterate on the poses.** Most fixes so far were pose numbers, not code (§3 lists the recurring ones).
5. **Register it** in `BodySets._human()`. Follow the naming conventions and `AgentLayer` picks it up with no code change:

   | Kind | Name in `BodySets` |
   |---|---|
   | Weapon attack | `attack_<weapon>` (+ item entry) |
   | Carrying | `idle_<tool>`, `walk_<tool>`, `run_<tool>` (run reuses the walk sheet at a higher fps) |
   | Work | `chop` / `mine` / `use` |

   Only a new *kind* of trigger (a new work type, a new way to spot an attack) needs `AgentLayer` code.
6. **Import and load-check:**
   ```
   C:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --import
   C:/Godot/Godot_v4.7.2-stable_win64.exe --headless --path . --quit-after 120
   ```
   The second line must print no errors. The atlas asserts catch item/torso frame mismatches.
7. **Check in-game** with the debug kit (F3, numpad 1).

---

## 3. Style rules learned in review (agreed)

- **Limbs:** arms are one continuous limb with a visible elbow and no inner outline. A relaxed bend looks better than a straight arm; stiff arms were rejected twice (gather, bow carry). Lower `bend` only where an animation needs rigidity (gather uses 0.7).
- **Body turn drives the action:** a positive twist puts the right shoulder back. Thrusts and draws use a side-on stance (left shoulder forward); the right shoulder then drives through. Never let a hand go behind its own shoulder (the first spear wind-up).
- **Hands on long tools slide:** the spear's left hand stays forward on the shaft while the shaft slides through it.
- **Show the tool off:** carried tools sit past the body's outline over the ground, not grey-on-skin. They're scaled up when needed (pickaxe carry ×1.15). Contrast matters (`DARK_WOOD` for the club).
- **Keep tools inside the 48 px frame:** the sword blade was shortened so the hit frame isn't clipped. Moving to bigger frames for one weapon is possible later (the atlas supports any square frame size), but the item and body sheets must match.
- **Attacks land in front:** the hit frame points dead ahead, where the game's swing arc is (`Cfg.SWING_ARC_DEG` around the facing).
- **Vertical swings from above:** foreshortening (`fs`), a bigger tool when raised (`scale`), arms over the head (`over`) and a slight lean (`ox`). The pick head turns into the swing plane so the tip strikes.
- **Death:** the corpse lies on its back, head to −X, arms out. The death sheet includes the legs, because corpses don't draw the legs layer.

---

## 4. Clothing: the approach

### 4.1 Slots and layers (agreed in principle)

Pants and shirts must be independent, so clothing is split by body region into **three outfit slots**, each its own layer:

| Slot | Covers | Draw order | Example contents |
|---|---|---|---|
| `legs` | legs layer (and the legs inside the death sheet) | after legs, before torso | trousers, greaves + sabatons |
| `torso` | torso, shoulders, arms, hands | after torso, before item | tunic, chest plate + pauldrons, gauntlets |
| `head` | head | after torso outfit, before item | hood, helmet |

The full per-agent stack becomes: **legs → legs outfit → torso → torso outfit → head outfit → item**, so up to 6 instances per agent.

### 4.2 Drawing outfits: draw the dressed body, keep only the changed pixels

A torso garment can't just be painted on top of the body sheet. Arms often cross in front of the chest, so a shirt layer on top would cover the bare forearm that should be on top of it.

- **Method:** the generator draws the body twice for every frame, once naked and once dressed. The rig draws the dressed version with garment materials and garment shapes in the **same draw order**, so a forearm still crosses over the shirt. The outfit layer is **every pixel that differs between the two**.
- **Why it works:** drawn over the naked sheet, that difference reproduces the dressed body exactly, whatever the arms are doing. That includes the soft inner lines and the `over` poses where the arms are above the head.
- **Cost:** wherever a bare arm crosses the garment, the difference contains skin pixels, so **outfit sheets are per skin tone**. (A palette-swap shader could fold skins together later, see §7.)
- **Shape:** garments get their own shapes on the rig, e.g. a sleeve is a capsule along the upper arm and a tunic is the torso ellipse grown about 0.6 px. Armour may add up to about 1 px of bulk.
- **Tools:** item sheets stay shared. Their cut-outs come from the naked body, and since armour adds at most about 1 px, a tool may overlap a pauldron's edge by a pixel. That's accepted (start). If it shows, cut tools out using the bulkiest outfit instead.

### 4.3 Colour variety from tinting

- Cloth is drawn in light, undyed tones. `AgentLayer` gives each outfit instance its own modulate colour, so tunics and trousers can be dyed per agent or per faction (e.g. tunics in faction colour) with no new art.
- Iron stays untinted.
- The instance colour already carries the red hit-flash; outfit layers get the same flash.

---

## 5. Outfit designs (start)

### 5.1 Peasant cloth

- **Tunic (torso):** undyed linen covering the torso and shoulders, short sleeves to about the elbow, and a rope belt as a 1 px darker band across the waist. The forearms and hands stay bare.
- **Trousers (legs):** wool, covering the legs to the ankle. The feet stay bare, or get wrapped cloth if the bare feet read oddly.
- **Hood (head, optional):** cloth over the hair cap with an opening at the face (+X).

### 5.2 Iron armour, matching the game's armour slots

`Agent.worn` already has `helmet`, `chest_armor` and `leg_armor` (`Items.ARMOR`).

- **`chest_armor` → torso:** a breastplate over the torso ellipse, pauldrons over the shoulder balls (about 1 px bigger, with a rivet highlight), and mail on the upper arm. Hands bare, or gauntlets as a later variant.
- **`leg_armor` → legs:** greaves along the legs and sabatons on the feet.
- **`helmet` → head:** a round iron cap with a nose guard at +X. In `over` poses (pickaxe) the arms draw over it, which the difference method handles.
- Uses the `IRON` palette, plus a darker mail colour.

### 5.3 How slots combine

Each slot is independent, so any mix works: tunic + greaves, chest plate + bare legs, and so on. The difference for each slot is taken against the **naked** body. Slots barely overlap (legs vs torso vs head), so stacking them reproduces the combined look. Where two slots meet (helmet edge vs pauldron), the later layer wins; draw order (§4.1) decides.

---

## 6. Engine changes for clothing

1. **`BodySets.gd`:** a new `outfits` section per set:
   ```
   "outfits": {
       "torso": {"tunic": {<torso anim> -> sheet}, "iron": {...}},
       "legs":  {"trousers": {"idle": ..., "walk": ..., "death": ...}, "iron": {...}},
       "head":  {"hood": {...}, "helmet": {...}},
   }
   ```
   - An outfit animation plays frame for frame with its body animation, so it takes fps and looping from it, like items do. A frame-count mismatch is an assert.
   - Run reuses walk as it does now.
2. **`SpriteAtlas.gd`:**
   - Compile `outfits`.
   - **Pack the atlas in 2D:** today every sheet is a full row in a 384 px wide strip (3,360 px tall). Outfits bring it to about 230 sheets, about 11,000 px tall, past the 8,192 px texture limit on many GPUs. Placing several strips side by side in a 2,048 px wide atlas gives about 2,048 × 2,300.
   - Keep the 16 px row alignment for mips.
3. **`AgentLayer.gd`:**
   - Draw the outfit instances in the §4.1 order, using the torso animation name (legs outfits use the legs animation).
   - Pick each slot's outfit from the agent (§6.4).
   - Apply outfit tints.
   - **Corpses:** draw torso death + legs-outfit death + torso-outfit death + head-outfit death. Today a corpse is one instance.
   - Reserve up to 6 instances per agent. 120 agents → about 720 instances, still one draw call.
4. **Game data:** decide where cloth comes from (§8 Q1). Armour already exists: `worn.chest_armor → torso:"iron"`, `leg_armor → legs:"iron"`, `helmet → head:"helmet"`.
5. **Generator:**
   - Garment shapes and materials on the rig (§5).
   - A dressed draw for each `(outfit, slot)`.
   - The difference against the naked body.
   - Write `human_outfit_<slot>_<outfit>_<anim>_<skin>_Sheet.png`.
   - The preview and GIF helpers composite outfits.

---

## 7. Phases

| # | Phase | Contents | Size (start) |
|---|---|---|---|
| 1 | Generator outfit support | Garment shapes and materials on the rig, the dressed/naked difference, outfit sheet output, outfit previews and GIFs | ~1 day |
| 2 | Peasant tunic + trousers | Design and tune both over every animation (24 body animations + legs), both skins; review loop as in §2 | ~1 day with review |
| 3 | Engine wiring | `BodySets.outfits`, 2D atlas packing, `AgentLayer` outfit instances, tints, corpses, slot selection; load-check | ~1 day |
| 4 | Iron armour | Chest plate + pauldrons, greaves, helmet; wired to `Agent.worn` | ~1 day with review |
| 5 | Polish (later) | Hood; gauntlets; a palette-swap skin shader (one sheet per animation instead of per skin, unlocking more skin tones cheaply); pain animation; a pickaxe dust puff on the strike | as wanted |

Do phase 2 before phase 3 so the look is agreed on still frames and GIFs before any engine work, the way the naked body was done.

---

## 8. Open questions

1. **Where does cloth come from?** Options:
   - (a) Everyone wears peasant clothes by default. Simplest, and nobody walks around naked.
   - (b) Tunic and trousers become craftable items in new `worn` slots, so being unclothed is a real state.
   - (c) NPCs dress by default and the player starts naked.
2. **Dye:** faction colour on tunics, random earth tones per agent, or both (faction for grouped agents, earth tones for solo)?
3. **Does armour replace cloth or layer on it?** E.g. a chest plate over a tunic, with the tunic's sleeves showing under the pauldrons. Layering looks richer but needs a fourth "under" layer or combined sheets; replacing keeps three slots.
4. **More skin tones:** two today. If more are wanted, do the palette-swap shader (phase 5) before the outfit sheet count grows.

---

## 9. Sheet and memory budget

| | Sheets now | After phases 2 + 4 |
|---|---|---|
| Body (24 anims × 2 skins) + legs (2 × 2) | 52 | 52 |
| Items | 18 | 18 |
| Torso outfits (tunic, iron × 24 × 2) | — | 96 |
| Legs outfits (trousers, iron × idle/walk/death × 2) | — | 12 |
| Head outfits (helmet × 24 × 2) | — | 48 |
| **Total** | **70** | **~226** |

At 48 px frames that's roughly a 2,048 × 2,300 RGBA atlas with mips, about 25 MB of VRAM. That's fine on desktop, but it's why the 2D packing in §6.2 comes before more skins. With the palette-swap shader, the body and outfit sheets halve.
