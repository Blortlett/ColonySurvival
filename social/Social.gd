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
		if have >= 4 and taker.inv.count(k) * 2 < have and taker.free_space() >= 2:
			return k
	return ""


static func _angry_meets(a: Agent, b: Agent) -> void:
	if b.is_angry():
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
		b.change_mood(-15.0)
		b.change_opinion(a.id, -40.0)
		if n > 0:
			EventBus.log_event("%s hands %d items to %s." % [b.short(), n, a.short()])
			Relations.change(a.faction, b.faction, Cfg.REL_ROB)
