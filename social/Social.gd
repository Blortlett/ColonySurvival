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
		b.set_cooldown(a.id)
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
	if b.is_player() and fb.solo and (fa.solo or fa.has_room()):
		# Player Social Plan §3: ask the player; with nobody to ask, the default rule refuses.
		var what := " invites you to form a group." if fa.solo else " invites you to join %s (%d members)." % [fa.display_name(), fa.members.size()]
		if not ask_player(b, &"invite", a, what, "Join", "Refuse", Cfg.OFFER_SECS_INVITE):
			_refuse_invite(a, b, false)
		return true
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


static func _trade(a: Agent, b: Agent) -> void:
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
		# Default rule (Player Controller Plan §5): the player refuses and fights back.
		EventBus.social(&"demand", "%s demands %s's goods and is refused." % [a.short(), b.short()], [a, b])
		Combat.start_fight(a, b)
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
static func ask_player(p: Agent, kind: StringName, npc: Agent, text: String, yes: String, no: String, secs: float) -> bool:
	var pc = p.controller
	if pc == null or not ("offers" in pc):
		return false
	var f := npc.faction
	var col: Color = f.color.lightened(0.35) if f and not f.solo else Color.WHITE
	if not pc.offers.add({"kind": kind, "from_id": npc.id, "fid": f.id if f else -1, "secs": secs,
			"who": npc.short(), "text": text, "yes": yes, "no": no, "color": col}):
		return false
	if not npc.in_combat():
		var j := Job.new(Job.Kind.IDLE, Job.PRIO_TASK) # linger for the answer; needs still come first
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


## Why accepting no longer works ("" if it still does): checked again on the answer, since
## things change while the prompt is up.
static func offer_blocked(p: Agent, o: Dictionary) -> String:
	var npc: Agent = World.agents.get(o.from_id)
	if npc == null or not npc.alive:
		return "they are gone"
	if World.dist(npc.pos, p.pos) > Cfg.OFFER_RANGE:
		return "%s is too far away" % npc.short()
	if npc.in_combat() or p.in_combat():
		return "there's a fight on"
	match o.kind:
		&"invite", &"gang":
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
