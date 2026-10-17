class_name Combat
## Fights, damage, pleading, surrender and robbery.

static func start_fight(att: Agent, vic: Agent, to_death: bool = false) -> void:
	if not att.alive or not vic.alive or att == vic:
		return
	var j := Job.new(Job.Kind.FIGHT, Job.PRIO_CRITICAL)
	j.target_id = vic.id
	j.to_death = to_death
	Brain.set_job(att, j)
	if to_death:
		att.death_match[vic.id] = true
		vic.death_match[att.id] = true
	on_attacked(vic, att)


static func _fighting(a: Agent, other_id: int) -> bool:
	return a.job != null and a.job.prio >= Job.PRIO_CRITICAL \
		and (a.job.kind == Job.Kind.FIGHT or a.job.kind == Job.Kind.FLEE) and a.job.target_id == other_id


## Victim reacts: fight back or flee. Allies nearby come to help.
static func on_attacked(vic: Agent, att: Agent) -> void:
	vic.last_attacker = att.id
	if not _fighting(vic, att.id):
		if vic.job == null or vic.job.kind != Job.Kind.FIGHT or vic.job.prio < Job.PRIO_CRITICAL:
			vic.change_mood(-15.0)
			vic.change_opinion(att.id, -30.0)
			if vic.death_match.has(att.id) or vic.power() >= att.power() * 0.8:
				var j := Job.new(Job.Kind.FIGHT, Job.PRIO_CRITICAL)
				j.target_id = att.id
				j.to_death = vic.death_match.has(att.id)
				Brain.set_job(vic, j)
			else:
				Brain.flee(vic, att.pos, att.id)
	call_defenders(vic, att)


## Group mates and kingdom allies nearby help; so do happy bystanders who like the victim.
## Helping a member of another group: +10 relation (agreed).
static func call_defenders(vic: Agent, att: Agent) -> void:
	if vic.faction == att.faction:
		return
	for m in World.agents_near(vic.pos, Cfg.DEFEND_RADIUS):
		if m == vic or m == att or m.in_combat() or m.hp < 30.0 or m.faction == att.faction:
			continue
		var ally: bool = not vic.faction.solo and World.same_side(m.faction.id, vic.faction.id)
		var friend: bool = m.is_happy() and m.opinion_of(vic.id) >= Cfg.BYSTANDER_DEFEND_OPINION
		if not ally and not friend:
			continue
		var j := Job.new(Job.Kind.FIGHT, Job.PRIO_CRITICAL)
		j.target_id = att.id
		Brain.set_job(m, j)
		vic.change_opinion(m.id, 20.0)
		if m.faction != vic.faction:
			Relations.change(m.faction, vic.faction, Cfg.REL_DEFEND)


## One attack with the given weapon. Returns false if it couldn't be made (e.g. no line of sight).
static func attack(a: Agent, t: Agent, weapon: String) -> bool:
	var w: Dictionary = Items.WEAPONS[weapon]
	var dmg: float
	if weapon == "bow":
		if not World.line_clear(a.cell(), t.cell()):
			return false # walls block arrows (agreed)
		a.inv.remove("arrow", 1)
		a.add_xp("agi", Cfg.XP_BOW_SHOT)
		if a.inv.wear("bow"):
			EventBus.log_event("%s's bow broke." % a.short())
		a.attack_cd = w.cooldown
		if World.rng.randf() > a.bow_hit_chance():
			on_attacked(t, a)
			return true # miss
		dmg = w.damage * a.bow_mult()
	else:
		dmg = w.damage * a.melee_mult()
		a.add_xp("str", Cfg.XP_MELEE_HIT)
		if weapon != "unarmed" and a.inv.wear(weapon):
			EventBus.log_event("%s's %s broke." % [a.short(), weapon])
		a.attack_cd = w.cooldown
	apply_damage(t, dmg, a)
	return true


## Hit a wall or door. Every melee weapon does its normal damage; the raiding axe does x5 (agreed).
static func attack_wall(a: Agent, w: Wall) -> void:
	if a.attack_cd > 0.0:
		return
	var weapon := "raiding_axe" if a.inv.has_tool("raiding_axe") else a.melee_weapon()
	var dmg: float
	if weapon == "raiding_axe":
		dmg = Items.RAID_AXE_DAMAGE * Items.RAID_AXE_WALL_MULT
		a.attack_cd = 1.2
	else:
		dmg = Items.WEAPONS[weapon].damage
		a.attack_cd = Items.WEAPONS[weapon].cooldown
	a.add_xp("str", Cfg.XP_MELEE_HIT)
	if weapon != "unarmed" and a.inv.wear(weapon):
		EventBus.log_event("%s's %s broke." % [a.short(), weapon.replace("_", " ")])
	w.hp -= dmg
	if w.hp <= 0.0:
		var owner: Faction = World.factions.get(w.owner_id)
		EventBus.log_event("%s breaks through %s's %s!" % [a.short(), owner.name if owner else "an old", "door" if w.is_door else "wall"])
		World.remove_wall(w)


static func apply_damage(t: Agent, dmg: float, a: Agent) -> void:
	t.hp -= dmg
	if t.hp <= 0.0:
		World.kill_agent(t, a)
		return
	on_attacked(t, a)
	if t.hp <= Cfg.PLEAD_HP * Cfg.MAX_HP and not t.pleaded.has(a.id) and not t.death_match.has(a.id):
		plead(t, a)


## The victim begs. 50/50 (agreed), nudged by the attacker's opinion of them.
static func plead(v: Agent, a: Agent) -> void:
	v.pleaded[a.id] = true
	var chance: float = Cfg.SURRENDER_ACCEPT + clamp(a.opinion_of(v.id) / 100.0, -1.0, 1.0) * Cfg.SURRENDER_OPINION_SWING
	if World.rng.randf() < chance:
		accept_surrender(a, v)
	else:
		EventBus.log_event("%s begs %s for mercy... and is refused." % [v.short(), a.short()])
		v.death_match[a.id] = true
		a.death_match[v.id] = true
		var j := Job.new(Job.Kind.FIGHT, Job.PRIO_CRITICAL)
		j.target_id = a.id
		j.to_death = true
		Brain.set_job(v, j)


static func accept_surrender(a: Agent, v: Agent) -> void:
	a.gain_authority()
	Factions.recompute_leader(a.faction)
	_stop_fight(a, v)
	a.set_cooldown(v.id, 60.0)
	v.set_cooldown(a.id, 60.0)
	# Rebellion outcomes.
	if v.id == a.master_id:
		EventBus.log_event("%s overpowered their master %s and walks free." % [a.short(), v.short()])
		Factions.free_agent(a)
		return
	if a.id == v.master_id:
		EventBus.log_event("%s crushed %s's rebellion." % [a.short(), v.short()])
		return
	var master := a
	if a.is_servant() and World.agents.has(a.master_id):
		master = World.agents[a.master_id] # servants can't have servants
	if master.faction.has_room():
		EventBus.log_event("%s surrenders to %s." % [v.short(), a.short()])
		Factions.make_servant(v, master)
	else:
		var n := rob(a, v, Cfg.DEMAND_FRACTION)
		Relations.change(a.faction, v.faction, Cfg.REL_ROB)
		v.change_mood(-20.0) # no happy boost for being spared (agreed)
		v.change_opinion(a.id, -50.0)
		EventBus.log_event("%s spares %s but takes %d items." % [a.short(), v.short(), n])
		Brain.flee(v, a.pos, a.id, Job.PRIO_NEEDS)


static func _stop_fight(a: Agent, v: Agent) -> void:
	for x in World.agent_list:
		if x.job and x.job.kind == Job.Kind.FIGHT:
			if (x.job.target_id == v.id and x.faction == a.faction) or x == v:
				x.job = null
	if a.job and a.job.kind == Job.Kind.FIGHT and a.job.target_id == v.id:
		a.job = null


## Moves a fraction of each stackable from victim to robber, limited by robber's space.
static func rob(robber: Agent, victim: Agent, frac: float) -> int:
	var moved := 0
	for k in victim.inv.stacks.keys():
		var n: int = min(int(floor(victim.inv.count(k) * frac)), robber.free_space())
		if n <= 0:
			continue
		victim.inv.remove(k, n)
		robber.inv.add(k, n)
		moved += n
	return moved
