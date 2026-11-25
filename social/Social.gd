class_name Social
## Social interactions triggered when agents come within range of each other.

## P(A wins) = CHA_A / (CHA_A + CHA_B) (agreed). Winner gains CHA XP.
static func cha_roll(a: Agent, b: Agent, a_mult: float = 1.0) -> bool:
	var ca: float = a.stats.cha * a_mult
	var cb: float = b.stats.cha
	var a_wins := World.rng.randf() < ca / (ca + cb)
	(a if a_wins else b).add_xp("cha", Cfg.XP_CHA_WIN)
	return a_wins


## Called from the initiator's think. Neutral agents never initiate (agreed).
static func scan(a: Agent) -> void:
	if a.is_neutral() or a.is_servant() or a.in_combat():
		return
	for b in World.agents_near(a.pos, Cfg.SOCIAL_RANGE):
		if b == a or not b.alive or not a.can_interact(b.id) or b.in_combat():
			continue
		if a.faction == b.faction:
			continue
		if a.is_angry() and World.same_side(a.faction.id, b.faction.id):
			continue # allies don't shake each other down
		a.set_cooldown(b.id)
		b.set_cooldown(a.id) # the player's own actions use action_cooldowns (R1), not this
		if a.is_happy():
			if _happy_meets(a, b):
				return
		elif a.is_angry():
			_angry_meets(a, b)
			return


static func _happy_meets(a: Agent, b: Agent) -> bool:
	if a.opinion_of(b.id) <= Cfg.GRUDGE or b.opinion_of(a.id) <= Cfg.GRUDGE or b.is_angry():
		return false
	var fa := a.faction
	var fb := b.faction
	if a.is_player() or b.is_player():
		# NPCs never invite the player, nor join the player's group unasked (Player Group
		# Plan D4): the player recruits by invite. Groups still trade with the player.
		if not fa.solo and not fb.solo and not b.is_angry() and (b.is_happy() or b.is_neutral()):
			_trade(a, b)
			return true
		return false
	if b.is_happy():
		if fa.solo and fb.solo:
			if a.opinion_of(b.id) >= 0.0 and b.opinion_of(a.id) >= 0.0:
				Factions.form(a, b)
				return true
		elif not fa.solo and fb.solo and fa.has_room():
			Factions.join(b, fa)
			return true
		elif fa.solo and not fb.solo and fb.has_room():
			Factions.join(a, fb)
			return true
		elif not fa.solo and not fb.solo:
			_trade(a, b)
			return true
	elif b.is_neutral() and not fa.solo and not fb.solo:
		_trade(a, b) # neutrals don't start trades, but they take part
		return true
	elif b.is_neutral() and fb.solo and (fa.solo or fa.has_room()):
		# Neutrals comply with a happy invite only if the inviter wins the charisma roll.
		if cha_roll(a, b):
			if fa.solo:
				Factions.form(a, b)
			else:
				Factions.join(b, fa)
			return true
	return false


## Returns [what a gave, what b gave] ("" for nothing).
static func _trade(a: Agent, b: Agent) -> Array:
	var give_a := _surplus_for(a, b)
	var give_b := _surplus_for(b, a)
	if give_a != "" or give_b != "":
		World.social_counts.trades += 1
		# A trade: one or both sides hand over 2 of something the other is short of.
		if give_a != "":
			a.inv.remove(give_a, 2)
			b.inv.add(give_a, 2)
		if give_b != "":
			b.inv.remove(give_b, 2)
			a.inv.add(give_b, 2)
		if give_a != "" and give_b != "":
			a.change_mood(5.0) # a real swap cheers both up (v1); a one-way hand-over doesn't
			b.change_mood(5.0)
		a.change_opinion(b.id, 10.0)
		b.change_opinion(a.id, 10.0)
		Relations.change(a.faction, b.faction, Cfg.REL_TRADE)
	else:
		a.change_opinion(b.id, 2.0)
		b.change_opinion(a.id, 2.0)
	return [give_a, give_b]


static func _surplus_for(giver: Agent, taker: Agent) -> String:
	for k in Items.STACKABLES:
		var have := giver.inv.count(k)
		if have >= 4 and taker.inv.count(k) * 2 < have and taker.free_space(k) >= 2:
			return k
	return ""


static func _angry_meets(a: Agent, b: Agent) -> void:
	if b.is_angry() and b.is_player() and b.faction.solo and (a.faction.solo or a.faction.has_room()):
		# Player Social Plan §3: an angry player is asked to run with them.
		var what := " wants you to run with them as a gang." if a.faction.solo else " wants you in their gang %s." % a.faction.display_name()
		if ask_player(b, &"gang", a, what, "Join", "Refuse", Cfg.OFFER_SECS_GANG):
			return
		# Nobody to ask: the default rule (the player never joins a gang) falls through.
	if b.is_angry() and not b.is_player(): # the player never joins a gang (default rule, §5)
		if cha_roll(a, b):
			if b.faction.solo and (a.faction.solo or a.faction.has_room()):
				if a.faction.solo:
					Factions.form(a, b)
				else:
					Factions.join(b, a.faction)
				EventBus.log_event("%s and %s run together as a gang." % [a.short(), b.short()])
			elif a.faction.solo and not b.faction.solo and b.faction.has_room():
				Factions.join(a, b.faction)
				EventBus.log_event("%s muscles into gang %s." % [a.short(), b.faction.name])
			else:
				_demand(a, b, false)
		else:
			EventBus.log_event("%s and %s fight to the death!" % [a.short(), b.short()])
			Combat.start_fight(a, b, true) # lost roll → fight to the death (agreed)
		return

	var attack := World.rng.randf() < _attack_chance(a, b)
	var dominant: bool = a.stats.auth >= b.stats.auth * Cfg.AUTH_DOMINANCE
	if not dominant and b.is_happy():
		if cha_roll(b, a, Cfg.TALK_DOWN_MULT):
			EventBus.log_event("%s talks %s down and slips away." % [b.short(), a.short()])
			Brain.flee(b, a.pos, a.id, Job.PRIO_NEEDS, Cfg.TALK_DOWN_FLEE)
			return
	_demand(a, b, attack)


static func _attack_chance(a: Agent, b: Agent) -> float:
	var p := 0.3
	if b.power() < a.power():
		p += 0.3
	if a.opinion_of(b.id) <= Cfg.GRUDGE:
		p += 0.3
	if b.inv.total() > 15:
		p += 0.1
	return p


## Target responds to an angry initiator: comply, flee or fight.
static func _demand(a: Agent, b: Agent, attack: bool) -> void:
	if b.is_player():
		# Player Social Plan §3: ask; with nobody to ask, the default rule refuses and fights.
		if not ask_player(b, &"demand", a, " demands your goods.", "Hand over", "Refuse",
				Cfg.OFFER_SECS_DEMAND, Job.PRIO_NEEDS, true):
			_refuse_demand(a, b, false)
		return
	var mine := b.power()
	var theirs := a.power()
	if mine >= theirs * 1.2:
		EventBus.log_event("%s stands up to %s." % [b.short(), a.short()])
		Combat.start_fight(b, a)
	elif b.speed() > a.speed() or a.has_bow_ready():
		Brain.flee(b, a.pos, a.id)
		if attack or World.rng.randf() < 0.5:
			Combat.start_fight(a, b)
	elif attack:
		EventBus.log_event("%s attacks %s on sight." % [a.short(), b.short()])
		Combat.start_fight(a, b)
	else:
		var n := Combat.rob(a, b, Cfg.DEMAND_FRACTION)
		World.social_counts.robberies += 1
		b.change_mood(-15.0)
		b.change_opinion(a.id, -40.0)
		if n > 0:
			EventBus.social(&"robbed", "%s hands %d items to %s." % [b.short(), n, a.short()], [a, b], [], b.pos, n)
			Relations.change(a.faction, b.faction, Cfg.REL_ROB)


# --- The player's answers (Player Social Plan §3) ---

## Asks the player instead of applying a default rule: queues a prompt on their controller
## and has the asker wait nearby for the answer. False if nobody can be asked (no player
## controller, the queue is full, or this NPC already has a prompt open).
static func ask_player(p: Agent, kind: StringName, npc: Agent, text: String, yes: String, no: String, secs: float,
		hold_prio: int = Job.PRIO_TASK, urgent: bool = false) -> bool:
	var pc = p.controller
	if pc == null or not ("offers" in pc):
		return false
	var f := npc.faction
	var col: Color = f.color.lightened(0.35) if f and not f.solo else Color.WHITE
	if not pc.offers.add({"kind": kind, "from_id": npc.id, "fid": f.id if f else -1, "secs": secs,
			"who": npc.short(), "text": text, "yes": yes, "no": no, "color": col}, urgent):
		return false
	if urgent or not npc.in_combat():
		# Wait for the answer. Invites linger (needs still come first); a demand holds its
		# ground; a pleading victim stops fighting (PRIO_CRITICAL).
		var j := Job.new(Job.Kind.IDLE, hold_prio)
		j.timer = secs
		j.item = WAIT_ANSWER
		Brain.set_job(npc, j)
	return true


const WAIT_ANSWER := "await answer" # Job.item marking an NPC that waits for the player


## The asker stops waiting (answered, timed out, or the player's body changed hands).
static func release_asker(npc_id: int) -> void:
	var npc: Agent = World.agents.get(npc_id)
	if npc and npc.job and npc.job.kind == Job.Kind.IDLE and npc.job.item == WAIT_ANSWER:
		Brain.set_job(npc, null)


## Applies the player's answer to an offer (Offers.step, inside the sim step). A timeout
## is a refusal, the default rule.
static func answer_offer(p: Agent, o: Dictionary, yes: bool, timed_out: bool) -> void:
	release_asker(o.from_id)
	var npc: Agent = World.agents.get(o.from_id)
	if npc == null or not npc.alive or not p.alive:
		return
	if yes:
		var why := offer_blocked(p, o)
		if why != "":
			if p.controller:
				p.controller.say("The offer is no longer open: %s." % why)
			return
	match o.kind:
		&"invite":
			if not yes:
				_refuse_invite(npc, p, timed_out)
			elif npc.faction.solo:
				Factions.form(npc, p)
			else:
				Factions.join(p, npc.faction)
		&"gang":
			if not yes:
				npc.change_opinion(p.id, Cfg.OFFER_DECLINE_OPINION)
				EventBus.social(&"gang_refused", "%s refuses to run with %s." % [p.short(), npc.short()], [npc, p], [], EventBus.NO_POS, 1 if timed_out else 0)
				if World.rng.randf() < _attack_chance(npc, p):
					Combat.start_fight(npc, p)
			elif npc.faction.solo:
				Factions.form(npc, p)
				EventBus.log_event("%s and %s run together as a gang." % [npc.short(), p.short()])
			else:
				Factions.join(p, npc.faction)
		&"demand":
			if yes:
				_hand_over(npc, p)
			else:
				_refuse_demand(npc, p, timed_out)
		&"plead":
			if timed_out:
				Combat.plead_roll(npc, p) # no answer: the usual 50/50 roll decides
			elif yes:
				Combat.accept_surrender(p, npc)
			else:
				Combat.refuse_plea(npc, p)


## Why accepting no longer works ("" if it still does): checked again on the answer, since
## things change while the prompt is up.
static func offer_blocked(p: Agent, o: Dictionary) -> String:
	var npc: Agent = World.agents.get(o.from_id)
	if npc == null or not npc.alive:
		return "they are gone"
	if World.dist(npc.pos, p.pos) > Cfg.OFFER_RANGE:
		return "%s is too far away" % npc.short()
	match o.kind:
		&"invite", &"gang":
			if npc.in_combat() or p.in_combat():
				return "there's a fight on"
			if not p.faction.solo:
				return "you're already in a group"
			if npc.faction.id != o.fid:
				return "%s's group changed" % npc.short()
			if not npc.faction.solo and not npc.faction.has_room():
				return "their group is full"
	return ""


static func _refuse_invite(a: Agent, p: Agent, timed_out: bool) -> void:
	var fa := a.faction
	if p.is_player():
		a.change_opinion(p.id, Cfg.OFFER_DECLINE_OPINION)
	EventBus.social(&"invite", "%s invites %s to join %s; they refuse." % [a.short(), p.short(), "them" if fa.solo else fa.name],
		[a, p], [fa], EventBus.NO_POS, 1 if timed_out else 0)


## The player hands over their goods to a demand: the same as an NPC complying in _demand.
static func _hand_over(a: Agent, p: Agent) -> void:
	var n := Combat.rob(a, p, Cfg.DEMAND_FRACTION)
	World.social_counts.robberies += 1
	p.change_mood(-15.0)
	p.change_opinion(a.id, -40.0)
	var text := ("You hand %d items to %s." % [n, a.short()]) if n > 0 else ("You have nothing %s wants." % a.short())
	EventBus.social(&"p_handover", text, [a, p], [], p.pos, n)
	if n > 0:
		Relations.change(a.faction, p.faction, Cfg.REL_ROB)


## The player refuses a demand, walks away or doesn't answer: the NPC attacks (default rule).
static func _refuse_demand(a: Agent, p: Agent, timed_out: bool) -> void:
	EventBus.social(&"demand", "%s demands %s's goods and is refused." % [a.short(), p.short()], [a, p], [], EventBus.NO_POS, 1 if timed_out else 0)
	Combat.start_fight(a, p)


# --- The player starts social actions (Player Social Plan §4, the radial menu) ---

## Radial options in fixed positions, clockwise from the top: friendly ones on top,
## hostile ones at the bottom (so muscle memory works).
const PLAYER_OPTIONS := [
	{"id": &"invite", "label": "Invite to group"},
	{"id": &"trade", "label": "Trade"},
	{"id": &"demand", "label": "Demand goods"},
	{"id": &"challenge", "label": "Challenge"},
	{"id": &"recruit", "label": "Recruit to gang"},
]


## Every radial option for the player `p` facing `t`: [{id, label, why}], why = "" if it
## can be used now. The menu only reads this, so the rules stay here.
static func player_options(p: Agent, t: Agent) -> Array:
	var out := []
	for o in PLAYER_OPTIONS:
		var why := player_why(p, t, o.id)
		if o.id == &"trade" and is_groupmate(p, t):
			why = member_trade_why(p, t) # opens their inventory (R2), not a swap
		out.append({"id": o.id, "label": o.label, "why": why})
	return out


## Why the player can't do `opt` to `t` right now ("" if they can).
static func player_why(p: Agent, t: Agent, opt: StringName) -> String:
	if t == null or not t.alive:
		return "They're gone."
	if World.dist(p.pos, t.pos) > Cfg.SOCIAL_RANGE * 1.5:
		return "Too far away."
	var fp := p.faction
	var ft := t.faction
	var same_side := fp == ft or (fp.kingdom != null and fp.kingdom == ft.kingdom)
	if opt == &"challenge":
		return "They're in your group." if fp == ft and not fp.solo else ""
	if t.in_combat():
		return "They're fighting."
	var why := _option_why(p, t, opt, fp, ft, same_side)
	if why == "" and not p.can_act_on(t.id):
		return "Ask again in %d s." % ceili(p.action_cooldowns.get(t.id, 0.0) - SimClock.time)
	return why


static func _option_why(p: Agent, t: Agent, opt: StringName, fp: Faction, ft: Faction, same_side: bool) -> String:
	match opt:
		&"invite":
			if not ft.solo:
				return "They're already in a group."
			if t.is_servant():
				return "They serve someone."
			if not fp.solo and not fp.has_room():
				return "Your group is full."
			if t.is_angry():
				return "They're angry with the world."
		&"trade":
			if fp.solo or ft.solo:
				return "Trade is between groups."
			if fp == ft:
				return "They're in your group."
			if t.is_angry():
				return "They're angry with the world."
		&"demand":
			if same_side and not fp.solo:
				return "They're on your side."
		&"recruit":
			if not p.is_angry():
				return "Only angry people run gangs."
			if not t.is_angry():
				return "They aren't angry enough."
			if not ft.solo:
				return "They're already in a group."
			if not fp.solo and not fp.has_room():
				return "Your gang is full."
	return ""


## Does what the player picked from the radial menu (inside the sim step). Returns a
## short line for the player; the full result goes to the feed.
static func player_act(p: Agent, t: Agent, opt: StringName) -> String:
	var why := player_why(p, t, opt)
	if why != "":
		return why
	if opt != &"challenge":
		p.set_action_cooldown(t.id)
		t.set_cooldown(p.id)
	match opt:
		&"invite": return _player_invite(p, t)
		&"trade": return _player_trade(p, t)
		&"demand": return _player_demand(p, t)
		&"challenge":
			Combat.start_fight(p, t, true)
			return _say(&"p_challenge", "You challenge %s to a fight to the death!" % t.short(), p, t)
		&"recruit": return _player_recruit(p, t)
	return ""


## Feed and log line for a player-started action (kind p_*: the feed shows the text as is).
static func _say(kind: StringName, text: String, p: Agent, t: Agent, n: int = 0) -> String:
	EventBus.social(kind, text, [p, t], [], t.pos, n)
	return text


## Same answer an NPC gets: happy and not against you joins, a neutral may be talked round
## (charisma roll, as in _happy_meets), angry never (greyed out).
static func _willing(p: Agent, t: Agent) -> bool:
	if t.opinion_of(p.id) <= Cfg.GRUDGE:
		return false
	if t.is_happy():
		return t.opinion_of(p.id) >= 0.0
	return cha_roll(p, t)


## Someone who outranks the player never follows them (Player Group Plan D6); the option
## stays open so the player can find that out.
static func _player_invite(p: Agent, t: Agent) -> String:
	p.set_action_cooldown(t.id, Cfg.PLAYER_INVITE_RETRY) # refused: try again soon (R1)
	if Factions.outranks(t, p):
		t.change_opinion(p.id, -3.0)
		return _say(&"p_refused", "%s won't follow someone with less standing." % t.short(), p, t)
	if not _willing(p, t):
		t.change_opinion(p.id, -2.0)
		return _say(&"p_refused", "%s turns down your invite." % t.short(), p, t)
	_bring_in(p, t)
	return _say(&"p_invite", "%s agrees to join you." % t.short(), p, t)


## The player brings `t` into their group: founds one (the player leads it), or adds `t`
## to the group they lead (which becomes player-led, D1). In an NPC gang the player only
## belongs to, `t` just joins and rank still decides (D2).
static func _bring_in(p: Agent, t: Agent) -> void:
	if p.faction.solo:
		Factions.form(p, t, true)
		return
	if p.faction.leader_id == p.id:
		p.faction.player_led = true
	Factions.join(t, p.faction)


static func _player_trade(p: Agent, t: Agent) -> String:
	var got: Array = _trade(p, t)
	if got[0] == "" and got[1] == "":
		return _say(&"p_trade", "You and %s have nothing the other needs." % t.short(), p, t)
	var parts: Array[String] = []
	if got[0] != "":
		parts.append("you give 2 %s" % Items.label(got[0]))
	if got[1] != "":
		parts.append("%s gives 2 %s" % [t.short(), Items.label(got[1])])
	return _say(&"p_trade", "Trade with %s: %s." % [t.short(), " and ".join(parts)], p, t)


## "Verbal rob" (Player Social Plan §4.3): the target is talked down, stands up, flees, or
## drops half of each stack at its feet and backs off.
static func _player_demand(p: Agent, t: Agent) -> String:
	var dominant: bool = p.stats.auth >= t.stats.auth * Cfg.AUTH_DOMINANCE
	if not dominant and t.is_happy() and cha_roll(t, p, Cfg.TALK_DOWN_MULT):
		Brain.flee(t, p.pos, p.id, Job.PRIO_NEEDS, Cfg.TALK_DOWN_FLEE)
		return _say(&"p_demand", "%s talks you down and walks away." % t.short(), p, t)
	if t.power() >= p.power() * 1.2:
		Combat.start_fight(t, p)
		return _say(&"p_demand", "%s stands up to you!" % t.short(), p, t)
	if t.speed() > p.speed() or p.has_bow_ready():
		Brain.flee(t, p.pos, p.id)
		return _say(&"p_demand", "%s runs for it." % t.short(), p, t)
	var stacks := {}
	var n := 0
	for k in t.inv.stacks.keys():
		var c := int(floor(t.inv.count(k) * Cfg.DEMAND_FRACTION))
		if c <= 0:
			continue
		t.inv.remove(k, c)
		stacks[k] = c
		n += c
	World.social_counts.robberies += 1
	t.change_mood(-15.0)
	t.change_opinion(p.id, -40.0)
	if n == 0:
		return _say(&"p_demand", "%s has nothing worth taking." % t.short(), p, t)
	World.drop_loot(t.cell(), stacks, [], t.id, "dropped for %s" % p.short())
	Relations.change(p.faction, t.faction, Cfg.REL_ROB)
	Brain.flee(t, p.pos, p.id, Job.PRIO_NEEDS, 5) # backs off from the pile
	var what: Array[String] = []
	for k in stacks:
		what.append("%d %s" % [stacks[k], Items.label(k)])
	return _say(&"p_demand", "%s drops %s." % [t.short(), ", ".join(what)], p, t, n)


static func _player_recruit(p: Agent, t: Agent) -> String:
	if cha_roll(p, t):
		_bring_in(p, t)
		return _say(&"p_recruit", "%s runs with you now." % t.short(), p, t)
	Combat.start_fight(t, p, true) # a lost roll: a fight to the death, as between NPCs
	return _say(&"p_recruit", "%s takes it as an insult: a fight to the death!" % t.short(), p, t)


# --- Groupmates' gear and other groups' storage (Player Group Base Plan R2, R8) ---

## Is `t` in the player's own group (servants included)? Trade on them opens their
## inventory (player/Station.gd open_member) instead of a swap.
static func is_groupmate(p: Agent, t: Agent) -> bool:
	return t != null and t != p and p.faction == t.faction and not p.faction.solo


## Why the player can't open groupmate `t`'s inventory now ("" if they can). No cooldown:
## it's not a social roll.
static func member_trade_why(p: Agent, t: Agent) -> String:
	if t == null or not t.alive or not World.agents.has(t.id):
		return "They're gone."
	if not is_groupmate(p, t):
		return "They aren't in your group."
	if World.dist(p.pos, t.pos) > Cfg.SOCIAL_RANGE * 1.5:
		return "Too far away."
	if t.in_combat():
		return "They're fighting."
	return ""


## The player took from another live group's chest or crate (once per opening): relations
## with the owner drop by REL_ROB, and every owner member near enough to see it (walls and
## doors block the view) attacks. Returns how many turned on the player.
static func theft(p: Agent, ch: Furniture) -> int:
	var owner: Faction = World.factions.get(ch.owner_id)
	if owner == null:
		return 0
	Relations.change(p.faction, owner, Cfg.REL_ROB)
	var n := 0
	for mid in owner.members:
		var o: Agent = World.agents.get(mid)
		if o == null or o == p or not o.alive or o.is_player():
			continue
		if World.dist(o.pos, World.center(ch.cell)) > Cfg.DEFEND_RADIUS:
			continue
		if not World.line_clear(o.cell(), p.cell()):
			continue
		o.change_opinion(p.id, -30.0)
		Combat.start_fight(o, p)
		n += 1
	EventBus.social(&"p_theft", "%s steals from %s's %s%s." % [p.short(), owner.display_name(), ch.label(), (" and is seen by %d" % n) if n > 0 else ""], [p], [], World.center(ch.cell))
	return n
