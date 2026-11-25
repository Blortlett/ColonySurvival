class_name PlayerController
extends Node2D
## Drives one agent's body from input instead of the AI (Player Controller Plan §1, §2, §4).
## Input is read every frame into intents; the body acts on them only inside the sim step
## (Scheduler -> control()), through the same Actions the AI uses. So the sim never
## depends on rendering, and every rule (costs, durability, damage, zones) is shared.
##
## Controls: WASD move, mouse aims, 1-6 pick the held hotbar slot, LMB uses what's held
## (swing a weapon or tool, punch empty-handed, eat food, shoot a held bow; with a build
## piece picked it places it), RMB shoot a bow, hold E harvest, E on a chest or machine opens
## it (a chest opens the inventory too; E / Esc close), Tab inventory, B the build menu
## (ui/BuildMenu.gd sets build_piece), X / Esc stop building. Eating is LMB with food in hand.
## F1 / F2 (or the prompt's buttons) accept / decline what an NPC asks (Player Social Plan §3).
## Hold F over a character to open the social radial menu (§4): move the mouse to an option,
## LMB confirms it (and closes the menu); releasing F closes it without choosing.
## Movement keeps working while a panel is open; walking out of reach closes it.

signal hit_landed # the player's swing or shot hit someone (camera shake)
signal hurt # the player took damage
signal died # the controlled body died; the death panel offers takeover or respawn (§5a)
signal body_changed # the controller now drives another body (takeover, respawn, debug)

const Station := preload("res://player/Station.gd")
const InvMoves := preload("res://player/InvMoves.gd")
const Offers := preload("res://player/Offers.gd")

var body: Agent = null
var watching := false # debug watch mode: the AI drives the body (§6a)
var keys_blocked := false # the debug menu has the number keys
var scripted := false # --playtest sets the intents itself instead of reading input

var vel := Vector2.ZERO # cells / s
var aim_point := Vector2.ZERO # cells
var build_piece := "" # selected piece, "" = not building
var hover_cell := Vector2i.ZERO
var harvest_node: ResourceNode = null # what E is working on
var harvest_t := 0.0
var harvest_secs := 0.0
var warm_t := 0.0
var station := Station.new() # the open chest or machine panel (phase 4)
var offers := Offers.new() # what NPCs are asking the player (Player Social Plan §3)
var hover_id := -1 # the character under the mouse (Player Social Plan §5), -1 if none
var radial_id := -1 # whom the radial menu is open on while F is held (§4), -1 if closed
var radial_sel: StringName = &"" # the usable option under the mouse (set by ui/SocialRadial.gd)
var radial_why := "" # why the option under the mouse is greyed out ("" if it isn't)
var use_target: Furniture = null # what E would open right now (HUD hint)
var message := ""
var held := 0 # hotbar slot in hand (0-5); copied to body.held while the player drives it
var inv_open := false # Tab inventory (pack grid, armour, stats); a chest opens it too
var _inv_auto := false # the inventory was opened by a chest: close it with the chest
var _inv_reqs: Array = [] # inventory moves queued by the UI, applied in the sim step
var message_t := 0.0
## Set when the controlled body dies, cleared when the player picks a new body (§5a):
## {cause, pos, fids (groups it could pass to), kingdom, newcomer_id}.
var death := {}

# Intents, filled from input each frame and used up by the sim step.
var _move_in := Vector2.ZERO
var _swing_t := 0.0 # a click is buffered this long if the weapon is still cooling down
var _shoot_t := 0.0
var _place := false
var _harvest_held := false
var _use := 0 # 1 open what's in reach, -1 close the panel
var _social: Array = [] # [option, target id] picked from the radial menu, applied in the sim step
var _e_latch := false # this E press opened or closed a panel: don't harvest until it's released
var _xp_dist := 0.0
var _last_hp := 0.0


func _ready() -> void:
	World.agent_died.connect(_on_agent_died)


func possess(a: Agent) -> void:
	if body and body.controller == self:
		body.controller = null
	if body:
		body.held = -1 # back to the AI's "best weapon carried"
	if a != body:
		offers.clear() # asks were for the old body
	body = a
	hover_id = -1
	close_radial()
	_social = []
	inv_open = false
	_inv_auto = false
	_inv_reqs.clear()
	vel = Vector2.ZERO
	harvest_node = null
	station.close("")
	harvest_t = 0.0
	warm_t = 0.0
	build_piece = ""
	_move_in = Vector2.ZERO
	_swing_t = 0.0
	_shoot_t = 0.0
	_place = false
	_xp_dist = 0.0
	if a == null:
		return
	_last_hp = a.hp
	aim_point = a.pos + a.facing
	if not watching:
		_take(a)


func _take(a: Agent) -> void:
	a.controller = self
	a.held = held
	Brain.set_job(a, null) # drops any task claim too
	a.path.clear()


## Watch mode (§6a): hand the body to the AI while watching, take it back on return.
func set_watching(on: bool) -> void:
	watching = on
	station.close("")
	offers.clear()
	hover_id = -1
	close_radial()
	if body == null or not body.alive:
		return
	if on:
		body.controller = null
		body.held = -1
		inv_open = false
		Brain.set_job(body, null)
		body.think_t = 0.0
	else:
		_take(body)
	vel = Vector2.ZERO


## The living character nearest `p` (cells) within Cfg.HOVER_PICK, not the player's own
## body; null if none. Shared by the hover card and (later) the radial menu.
func pick_agent(p: Vector2) -> Agent:
	var best: Agent = null
	var bd := Cfg.HOVER_PICK
	for o in World.agents_near(p, Cfg.HOVER_PICK):
		if o == body or not o.alive:
			continue
		var d := World.dist(o.pos, p)
		if d <= bd:
			best = o
			bd = d
	return best


## F pressed: open the radial menu on the hovered character, if one is in reach.
func open_radial() -> void:
	var h := hover_agent()
	if h == null:
		say("Hover someone to interact with them.")
	elif World.dist(h.pos, body.pos) > Cfg.SOCIAL_RANGE:
		say("Get closer to %s." % h.short())
	else:
		radial_id = h.id
		radial_sel = &""
		radial_why = ""


func close_radial() -> void:
	radial_id = -1
	radial_sel = &""
	radial_why = ""


func hover_agent() -> Agent:
	return World.agents.get(hover_id) if hover_id != -1 else null


func alive() -> bool:
	return body != null and body.alive


func say(text: String, secs := 2.5) -> void:
	message = text
	message_t = secs


## Pick the hotbar slot in hand (keys 1-6).
func select_slot(i: int) -> void:
	held = clampi(i, 0, Cfg.HOTBAR_SLOTS - 1)
	if body and body.controller == self:
		body.held = held


## What's in hand: the hotbar entry (null if empty).
func held_entry():
	return body.inv.entry(held) if body else null


func toggle_inventory() -> void:
	set_inventory(not inv_open)


func set_inventory(on: bool) -> void:
	inv_open = on and alive() and not watching
	_inv_auto = false
	if not inv_open and station.is_chest():
		_use = -1 # closing the inventory closes the chest with it


## Inventory UI requests (applied in the next sim step): drag (src, si) onto (dst, di).
func request_move(src: String, si: int, dst: String, di: int) -> void:
	_inv_reqs.append(["move", src, si, dst, di])


## Right click: the whole stack across.
func request_quick(src: String, si: int) -> void:
	_inv_reqs.append(["quick", src, si])


## Hand crafting (Tab inventory): the recipes anyone can make from their pack, anywhere,
## instantly, as the AI does (GoalLadder). Workshop and anvil recipes need their machine.
static func hand_recipes() -> Array[String]:
	var out: Array[String] = []
	for k in Items.RECIPES:
		if not k in Items.WORKSHOP_RECIPES and not k in Items.ANVIL_RECIPES:
			out.append(k)
	return out


func request_craft(item: String) -> void:
	_inv_reqs.append(["craft", item])


func request_put_all() -> void:
	_inv_reqs.append(["put_all"])


func request_take_all() -> void:
	_inv_reqs.append(["take_all"])


# --- Death and takeover (Player Controller Plan §5a) ---

func _on_agent_died(a: Agent, killer: Agent, group: Faction, kingdom: Kingdom, newcomer: Agent) -> void:
	if a != body:
		return
	# The body is handled like any death (World.kill_agent). Leader slots were recomputed
	# as it left its group; the king slot is only refreshed every 2 s, so do it now, and
	# take the body out of raid parties straight away rather than on the next raid tick.
	if kingdom and World.kingdoms.has(kingdom.id):
		Kingdoms.recompute(kingdom)
	for r in Raids.active:
		r.party.erase(a.id)
	var fids: Array[int] = []
	if kingdom:
		fids.assign(kingdom.groups)
	elif group and not group.solo:
		fids.append(group.id)
	death = {
		"cause": ("killed by %s" % killer.short()) if killer else ("died of %s" % ("cold" if a.warmth <= 0.0 else "hunger")),
		"pos": a.pos,
		"fids": fids,
		"kingdom": kingdom,
		"newcomer_id": newcomer.id if newcomer else -1,
	}
	watching = false # the body is gone: nothing to hand back
	offers.clear()
	SimClock.set_speed(1.0) # the sim keeps running at 1x behind the death panel (agreed)
	build_piece = ""
	died.emit()


func dead() -> bool:
	return body != null and not body.alive


## Option A: the living member with the highest AUTH in the kingdom the body died in (or its
## group, if it wasn't in a kingdom). Same order as Factions.recompute_leader: AUTH, then
## CHA, then lowest id. Null if there is nobody (solo, or everyone is dead).
func takeover_candidate() -> Agent:
	if death.is_empty():
		return null
	var fids: Array[int] = death.fids
	var k: Kingdom = death.kingdom
	if k and World.kingdoms.has(k.id):
		fids = k.groups # the kingdom as it is now (groups may have joined or left)
	var best: Agent = null
	for fid in fids:
		var f: Faction = World.factions.get(fid)
		if f == null or f.solo:
			continue
		for mid in f.members:
			var m: Agent = World.agents.get(mid)
			if m == null or not m.alive or m == body:
				continue
			if best == null or Factions.outranks(m, best):
				best = m
	return best


## "king of Ash", "leader of F12 (Ash)", "member of F12".
func role_of(a: Agent) -> String:
	var f := a.faction
	var k: Kingdom = f.kingdom if f else null
	if f == null or f.solo:
		return "on their own"
	var in_k := (" (%s)" % k.name) if k else ""
	if k and k.king_id == a.id:
		return "king of %s" % k.name
	if f.leader_id == a.id:
		return "leader of %s%s" % [f.name, in_k]
	return "member of %s%s" % [f.name, in_k]


## Take control of another living body (death option A, and the debug menu). The body keeps
## its inventory, stats, faction and rank; its AI state is dropped.
func take_over(a: Agent) -> void:
	if a == null or not a.alive:
		return
	var was_dead := dead()
	watching = false
	possess(a)
	_reset_ai(a)
	SimClock.set_speed(1.0)
	var line := "You now play %s, %s." % [a.short(), role_of(a)]
	EventBus.social(&"takeover", ("You died. " if was_dead else "") + line, [a])
	say(line, 4.0)
	death = {}
	body_changed.emit()


## Option B: a fresh solo agent at a random free spot, with no ties to the old kingdom. It is
## the newcomer the death spawned (population stays constant) if that one is still a free,
## solo agent; otherwise a new agent is spawned.
func respawn() -> void:
	var a: Agent = World.agents.get(death.get("newcomer_id", -1))
	if a == null or not a.alive or not a.faction.solo or a.is_servant() or a.controller != null:
		a = World.spawn_agent(Cfg.RESPAWN_MIN_DIST)
	watching = false
	possess(a)
	_reset_ai(a)
	SimClock.set_speed(1.0)
	EventBus.social(&"respawn", "You start again as %s, a newcomer on their own." % a.short(), [a])
	say("A fresh start as %s." % a.short(), 4.0)
	death = {}
	body_changed.emit()


## Drop what the AI was doing with this body: job (and task claim, in possess), path,
## raid duties. Fights it is already in (death_match) belong to the body and stay.
func _reset_ai(a: Agent) -> void:
	a.think_t = 0.0
	if a.raid_id != -1:
		var r := Raids.find(a.raid_id)
		if r:
			r.party.erase(a.id)
		a.raid_id = -1
	a.defend_raid = -1
	aim_point = a.pos + a.facing


# --- Input (per frame) ---

func _process(dt: float) -> void:
	message_t -= dt
	if scripted:
		return
	if not alive() or watching:
		_move_in = Vector2.ZERO
		_harvest_held = false
		hover_id = -1
		close_radial()
		return
	var m := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): m.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): m.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): m.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): m.x += 1.0
	_move_in = m.normalized()
	var e := Input.is_physical_key_pressed(KEY_E)
	if not e:
		_e_latch = false
	_harvest_held = e and not _e_latch and not station.active()
	use_target = Station.target(body) if not station.active() else null
	aim_point = World.wrap_pos(get_global_mouse_position() / Cfg.CELL) # the camera can be past the seam
	hover_cell = Vector2i(aim_point.floor())
	var h := pick_agent(aim_point)
	hover_id = h.id if h else -1
	if radial_id != -1:
		var t: Agent = World.agents.get(radial_id)
		if not Input.is_physical_key_pressed(KEY_F) or t == null or not t.alive \
				or World.dist(t.pos, body.pos) > Cfg.SOCIAL_RANGE * 1.5:
			close_radial() # F released, or the target died or got away
	if body.hp < _last_hp - 0.01:
		hurt.emit()
	_last_hp = body.hp


func _unhandled_input(event: InputEvent) -> void:
	if not alive() or watching:
		return
	if event is InputEventMouseButton and event.pressed and radial_id != -1:
		# While the radial menu is open, LMB only confirms an option; nothing swings.
		if event.button_index == MOUSE_BUTTON_LEFT:
			if radial_sel != &"":
				_social = [radial_sel, radial_id]
				close_radial()
			elif radial_why != "":
				say(radial_why)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if build_piece != "":
				_place = true
			else:
				_swing_t = 0.25
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if build_piece != "":
				build_piece = ""
			else:
				_shoot_t = 0.25
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k == KEY_E:
			if station.active():
				_use = -1
				_e_latch = true
			elif Station.target(body) != null:
				_use = 1
				_e_latch = true
		elif k == KEY_ESCAPE and station.active():
			_use = -1
			get_viewport().set_input_as_handled()
		elif k == KEY_TAB:
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and inv_open:
			set_inventory(false)
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k < KEY_1 + Cfg.HOTBAR_SLOTS and not keys_blocked:
			select_slot(k - KEY_1)
		elif k == KEY_F:
			open_radial()
		elif (k == KEY_F1 or k == KEY_F2) and not offers.queue.is_empty():
			offers.answer(k == KEY_F1)
			get_viewport().set_input_as_handled()
		elif k == KEY_X or k == KEY_ESCAPE:
			build_piece = ""


# --- Sim step (called by Scheduler.update instead of Brain) ---

func control(a: Agent, dt: float) -> void:
	_job_hygiene(a, dt)
	_move(a, dt)
	a.facing = _aim_dir(a)
	_swing_t -= dt
	_shoot_t -= dt
	a.held = held
	_apply_inv(a)
	if _swing_t > 0.0 and a.attack_cd <= 0.0:
		_swing_t = 0.0
		_use_held(a)
	if _shoot_t > 0.0 and a.attack_cd <= 0.0:
		_shoot_t = 0.0
		_shoot(a)
	if _place:
		_place = false
		_place_piece(a)
	offers.step(a)
	if not _social.is_empty():
		var t: Agent = World.agents.get(_social[1])
		if t and _social[0] == &"trade" and Social.is_groupmate(a, t):
			say(open_member(a, t), 3.0) # your own group: their inventory, not a swap (R2)
		else:
			say(Social.player_act(a, t, _social[0]) if t else "They're gone.", 3.0)
		_social = []
	_use_station(a, dt)
	_follow_chest()
	_harvest(a, dt)
	_warm(a, dt)
	var bag: LootBag = World.loot.get(World.wc(a.cell()))
	if bag:
		World.take_loot(a, bag)


## LMB with what's in hand: food is eaten, a bow shoots at the aim, anything else swings
## (weapons as their weapon, everything else is a punch).
func _use_held(a: Agent) -> void:
	var e = a.inv.entry(held)
	if e != null and not Inventory.is_tool_entry(e) and e.item == "berry":
		if not Actions.eat(a):
			say("No berries to eat.")
		return
	if Inventory.is_tool_entry(e) and e.type == "bow":
		_shoot(a)
		return
	if Actions.swing(a, a.facing, a.melee_weapon()) > 0:
		hit_landed.emit()


func _apply_inv(a: Agent) -> void:
	var reqs := _inv_reqs
	_inv_reqs = []
	for r in reqs:
		match r[0]:
			"move":
				InvMoves.move(a, station, r[1], r[2], r[3], r[4])
			"quick":
				InvMoves.quick(a, station, r[1], r[2])
			"put_all":
				InvMoves.put_all(a, station)
			"take_all":
				InvMoves.take_all(a, station)
			"craft":
				_hand_craft(a, r[1])


func _hand_craft(a: Agent, item: String) -> void:
	if not item in hand_recipes():
		return
	var cost: Dictionary = Items.RECIPES[item]
	if not a.inv.has_cost(cost):
		say("Can't craft a %s: needs %s." % [Items.label(item), Actions.cost_text(cost)])
	elif not Actions.craft(a, item):
		say("No room in your pack for a %s." % Items.label(item))
	else:
		var n := Items.ARROWS_PER_CRAFT if item == "arrow" else 1
		say("Crafted %s." % (("%d arrows" % n) if item == "arrow" else "a " + Items.label(item)))
		EventBus.log_event("%s crafts a %s." % [a.short(), Items.label(item)])


## A chest being open opens the inventory with it (agreed); when that chest closes (E, Esc,
## walking away, a hard hit) the inventory closes again, unless Tab opened it first.
func _follow_chest() -> void:
	if station.is_chest() and not inv_open:
		inv_open = true
		_inv_auto = true
	elif _inv_auto and not station.is_chest():
		inv_open = false
		_inv_auto = false


func _aim_dir(a: Agent) -> Vector2:
	var d := World.delta(a.pos, aim_point)
	return d.normalized() if d.length() > 0.05 else a.facing


## Snappy acceleration and friction (start: 0.05 s to full speed), agent speed formula
## (AGI and road bonus), sliding collision against cells the body can't pass.
func _move(a: Agent, dt: float) -> void:
	var top := a.speed()
	vel = vel.move_toward(_move_in * top, top / Cfg.PLAYER_ACCEL_SECS * dt)
	if vel == Vector2.ZERO:
		return
	var want := vel * dt
	var moved := Actions.move_free(a, want)
	for axis in 2:
		if absf(moved[axis]) < absf(want[axis]) * 0.5:
			vel[axis] = 0.0 # blocked on this axis: don't keep pushing into the wall
	_xp_dist += moved.length()
	while _xp_dist >= 1.0:
		_xp_dist -= 1.0
		a.add_xp("agi", Cfg.XP_PER_CELL) # same AGI training per cell as path movement


## Bows fire at the agent nearest the aim point (within reach and line of sight).
func _shoot(a: Agent) -> void:
	if not a.has_bow_ready():
		say("No bow and arrows.")
		return
	var best: Agent = null
	var best_d := 1.5
	for o in World.agents_near(aim_point, 1.5):
		if o == a or World.same_side(o.faction.id, a.faction.id):
			continue
		var d := World.dist(o.pos, aim_point)
		if d < best_d and World.dist(a.pos, o.pos) <= a.bow_range():
			best_d = d
			best = o
	if best == null:
		say("Nothing to shoot at there.")
		return
	if Actions.shoot(a, best):
		hit_landed.emit()
	else:
		say("No line of sight.")


func _place_piece(a: Agent) -> void:
	var why := Actions.can_place(a, build_piece, hover_cell, Cfg.PLAYER_BUILD_REACH)
	if why != "":
		say("Can't place %s: %s." % [Items.label(build_piece), why])
		return
	Actions.place(a, build_piece, hover_cell, Items.BUILD_COSTS[build_piece])


## The node E works on: within reach, the one most in front of the body.
func harvest_target(a: Agent) -> ResourceNode:
	var best: ResourceNode = null
	var best_score := -INF
	var c := a.cell()
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var n: ResourceNode = World.nodes.get(World.wc(c + Vector2i(dx, dy)))
			if n == null or n.amount <= 0:
				continue
			var d := World.delta(a.pos, World.center(n.cell))
			var len := d.length()
			if len > Cfg.PLAYER_HARVEST_REACH:
				continue
			var score := a.facing.dot(d / len) - len * 0.5
			if score > best_score:
				best_score = score
				best = n
	return best


## Hold E: gather times, tool use and durability as for everyone (Actions).
func _harvest(a: Agent, dt: float) -> void:
	var n: ResourceNode = harvest_target(a) if _harvest_held else null
	if n != harvest_node:
		harvest_node = n
		harvest_t = 0.0
	if n == null:
		return
	if not Actions.can_harvest(a, n):
		say("Metal needs a tier-2 pickaxe.")
		harvest_node = null
		return
	if a.free_space(n.item()) <= 0:
		say("Your pack is full.")
		return
	var g := Actions.harvest_secs(a, n)
	harvest_secs = g[0]
	harvest_t += dt
	if harvest_t >= harvest_secs:
		harvest_t -= harvest_secs
		if Actions.harvest_unit(a, n, g[1], true, n.type != ResourceNode.Type.BUSH):
			harvest_node = null


## E opens the chest, machine or mailbox in reach (or closes the open one); the open panel's
## requests run here, inside the sim step. A mailbox opens the group panel (ui/MailboxUI.gd).
func _use_station(a: Agent, dt: float) -> void:
	if _use == -1:
		station.close("")
	elif _use == 1:
		var fu := Station.target(a)
		if fu != null:
			build_piece = ""
			var why: String = station.try_open(a, fu)
			if why != "":
				say("Can't use the %s: %s." % [fu.label(), why])
	_use = 0
	station.step(a, dt)
	if station.why_closed != "":
		say("Panel closed: %s." % station.why_closed)
		station.why_closed = ""


## Trade on a groupmate (Player Group Base Plan R2): open their pack, hotbar and worn gear
## beside the player's (ui/MemberPanel.gd). Returns the line for the player.
func open_member(a: Agent, t: Agent) -> String:
	build_piece = ""
	var why: String = station.open_member(a, t)
	return why if why != "" else "%s's gear is open: drag to move, right click: whole stack across." % t.short()


## Standing by a burning fire warms the body like an NPC's WARM job (10 s next to it).
func _warm(a: Agent, dt: float) -> void:
	var c := a.cell()
	var r := Cfg.WARM_RADIUS
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var f: Campfire = World.fires.get(World.wc(c + Vector2i(dx, dy)))
			if f and f.burning():
				warm_t += dt
				if warm_t >= Cfg.WARM_SIT_SECS:
					warm_t = 0.0
					Actions.finish_warming(a, f)
				return
	warm_t = 0.0


## Other systems set jobs on every agent (fight back, flee, defend). On the player's body a
## job is only a marker that tells the sim it is fighting (so it isn't drafted or chatted
## to mid-fight); it never runs. Drop it when the fight is over, like the AI would.
func _job_hygiene(a: Agent, dt: float) -> void:
	var j := a.job
	if j == null:
		return
	var keep := false
	if j.kind == Job.Kind.FIGHT:
		var t: Agent = World.agents.get(j.target_id)
		keep = t != null and t.alive and World.dist(a.pos, t.pos) <= Cfg.CHASE_GIVE_UP
	elif j.kind == Job.Kind.FLEE:
		j.timer -= dt
		keep = j.timer > 0.0
	if not keep:
		Brain.set_job(a, null)
