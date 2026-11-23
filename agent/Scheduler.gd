class_name Scheduler
## The one place agent updates go through (Summer Roadmap §2.3). For now it updates every
## living agent every sim step. Later (bigger world, §4.3) it decides who gets updated and
## how often. Each body runs its needs, then its controller: the AI (Brain) when
## Agent.controller is null, otherwise that controller (the PlayerController).


static func update_agents(dt: float) -> void:
	for a in World.agent_list.duplicate():
		if a.alive:
			update(a, dt)


static func update(a: Agent, dt: float) -> void:
	a.tick_needs(dt)
	if not a.alive:
		return
	a.attack_cd -= dt
	if a.controller:
		a.controller.control(a, dt)
	else:
		Brain.update(a, dt)
