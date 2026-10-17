extends Node2D
## Builds the scene, steps the sim on sim time, handles observer input.

var _agents: Node2D
var _dynamic: Node2D
var _camera: Camera2D
var _hud: CanvasLayer
var _sim_usec := 0 # time spent stepping the sim in _process (--frames)


func _ready() -> void:
	World.setup()
	add_child(preload("res://render/StaticLayer.gd").new())
	_dynamic = preload("res://render/DynamicLayer.gd").new()
	add_child(_dynamic)
	_agents = preload("res://render/AgentLayer.gd").new()
	add_child(_agents)
	_camera = preload("res://ui/CameraController.gd").new()
	add_child(_camera)
	_camera.make_current()
	_hud = preload("res://ui/Hud.gd").new()
	_hud.agent_layer = _agents
	_hud.dynamic_layer = _dynamic
	add_child(_hud)
	# Headless fast-forward for testing/tuning: godot --headless -- --bench=30
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench"):
			_bench(int(arg.get_slice("=", 1)) if "=" in arg else 30)
		elif arg.begins_with("--shot"):
			_shot(int(arg.get_slice("=", 1)) if "=" in arg else 5)
		elif arg.begins_with("--frames"):
			_frames(int(arg.get_slice("=", 1)) if "=" in arg else 30)


## Windowed frame times (Performance Plan B0): fast-forward N sim minutes, then time 300
## frames at 1x and at 16x in two fixed views, the whole map and the biggest city. Vsync is
## off so the numbers show the real cost; sim = time spent stepping the sim in those frames.
func _frames(minutes: int) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in int(minutes * 60.0 / Cfg.MAX_SIM_STEP):
		World.step(Cfg.MAX_SIM_STEP)
	var views := {"map": [_camera.position, _camera.zoom]}
	var city: Kingdom = null
	for k in World.kingdoms.values():
		if k.has_city and (city == null or k.plots.size() > city.plots.size()):
			city = k
	if city:
		views["city"] = [Vector2(Cities.plot_rect(city, Vector2i.ZERO).end) * Cfg.CELL, Vector2.ONE * 1.1]
	for v in views:
		_camera.position = views[v][0]
		_camera.zoom = views[v][1]
		for speed in [1.0, 16.0]:
			SimClock.set_speed(speed)
			for frame in 30:
				await get_tree().process_frame
			var times: Array[int] = []
			_sim_usec = 0
			var last := Time.get_ticks_usec()
			for frame in 300:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				times.append(now - last)
				last = now
			var total := 0
			for x in times:
				total += x
			times.sort()
			print("frames %s %2dx (min %d): avg %.2f ms, p95 %.2f ms, worst %.2f ms, sim %.2f ms/frame" % [
				v, int(speed), minutes, total / 300000.0, times[284] / 1000.0, times[299] / 1000.0, _sim_usec / 300000.0])
	get_tree().quit()


## Fast-forward N sim minutes, then save screenshots to user://: the full map, the busiest
## house with its group panel, a workshop, the biggest city, and a raid in progress (if one
## starts within 3 more sim minutes).
func _shot(minutes: int) -> void:
	for i in int(minutes * 60.0 / Cfg.MAX_SIM_STEP):
		World.step(Cfg.MAX_SIM_STEP)
	var raid_seen: Raid = null
	for i in int(180.0 / Cfg.MAX_SIM_STEP):
		for r in Raids.active:
			if r.phase == Raid.Phase.ASSAULT:
				raid_seen = r
		if raid_seen:
			break
		World.step(Cfg.MAX_SIM_STEP)
	# The busiest complete house, preferring one in a kingdom.
	var busiest: House = null
	var best_score := -1
	for h in World.all_houses():
		var f: Faction = World.factions.get(h.faction_id)
		var score := h.occupants.size() + (100 if f and f.kingdom else 0)
		if h.state == House.State.COMPLETE and h.is_home() and score > best_score:
			best_score = score
			busiest = h
	for frame in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://shot_map.png")
	if busiest:
		_camera.position = World.center(busiest.fire_cell) * Cfg.CELL
		_camera.zoom = Vector2.ONE * 2.5
		_agents.selected_id = -1
		_hud.selected_fire = busiest.fire # show the group panel
	for frame in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://shot_zoom.png")
	# A working workshop, if any, with its group panel.
	for h in World.all_houses():
		if h.operational():
			_camera.position = World.center(h.fire_cell) * Cfg.CELL
			_hud.selected_fire = h.fire
			for frame in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shot_workshop.png")
			break
	# The biggest city.
	var city: Kingdom = null
	for k in World.kingdoms.values():
		if k.has_city and (city == null or k.plots.size() > city.plots.size()):
			city = k
	if city:
		_camera.position = Vector2(Cities.plot_rect(city, Vector2i.ZERO).end) * Cfg.CELL
		_camera.zoom = Vector2.ONE * 1.1
		var centre: House = city.plots[Vector2i.ZERO].house
		_hud.selected_fire = centre.fire if centre and centre.fire else null
		for frame in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_city.png")
	# A smeltery close-up with its panel (v3): the busiest working one, else any.
	var smelt: House = null
	for h in World.all_houses():
		if h.is_smeltery() and (smelt == null or (h.operational() and not smelt.operational()) or h.state > smelt.state):
			smelt = h
	if smelt:
		_camera.position = World.center(smelt.fire_cell) * Cfg.CELL
		_camera.zoom = Vector2.ONE * 3.0
		_hud.selected_fire = smelt.fire
		for frame in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_smeltery.png")
	# The most armoured agent with its panel (v3: grey ring, gear and durability).
	var geared: Agent = null
	for a in World.agent_list:
		if a.is_armoured() and (geared == null or a.worn.size() > geared.worn.size()):
			geared = a
	if geared:
		_camera.position = geared.pos * Cfg.CELL
		_camera.zoom = Vector2.ONE * 3.0
		_hud.selected_fire = null
		_agents.selected_id = geared.id
		for frame in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_gear.png")
		_agents.selected_id = -1
	if raid_seen and Raids.active.has(raid_seen):
		_camera.position = World.center(raid_seen.target.fire_cell) * Cfg.CELL
		_camera.zoom = Vector2.ONE * 2.0
		_hud.selected_fire = raid_seen.target.fire
		for frame in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_raid.png")
	print("shots saved to ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()


func _bench(minutes: int) -> void:
	World.profiling = true
	var t0 := Time.get_ticks_msec()
	for m in minutes:
		var s0 := Time.get_ticks_msec()
		for i in int(60.0 / Cfg.MAX_SIM_STEP):
			World.step(Cfg.MAX_SIM_STEP)
		print(_bench_line(m + 1, Time.get_ticks_msec() - s0))
	print("deaths by cause: %s" % World.death_causes)
	print("--- %d sim minutes in %.1f s real ---" % [minutes, (Time.get_ticks_msec() - t0) / 1000.0])
	var keys := World.prof.keys()
	keys.sort_custom(func(x, y): return World.prof[x] > World.prof[y])
	for k in keys:
		print("  %-24s %10.1f ms" % [k, World.prof[k] / 1000.0])
	for line in EventBus.lines.slice(max(0, EventBus.lines.size() - 40)):
		print(line)
	get_tree().quit()


func _bench_line(minute: int, ms: int) -> String:
	var moods := {"happy": 0, "neutral": 0, "angry": 0}
	var jobs := {}
	var tools := 0
	var warmth := 0.0
	var hunger := 0.0
	for a in World.agent_list:
		moods[a.mood_label()] += 1
		var k: String = Job.Kind.keys()[a.job.kind] if a.job else "none"
		jobs[k] = jobs.get(k, 0) + 1
		tools += a.inv.tools.size()
		warmth += a.warmth
		hunger += a.hunger
	var n: int = max(1, World.agent_list.size())
	var houses := {"PLANNED": 0, "BUILDING": 0, "COMPLETE": 0}
	for h in World.all_houses():
		houses[House.State.keys()[h.state]] += 1
	var servants := World.agent_list.filter(func(a): return a.is_servant()).size()
	var chests := 0
	var stored := 0
	for fu in World.furniture.values():
		if fu.kind == Furniture.Kind.CHEST:
			chests += 1
			stored += fu.store.total()
	var shops := 0
	var working := 0
	for h in World.all_houses():
		if h.is_workshop():
			shops += 1
			if h.operational():
				working += 1
	var reinforced := 0
	for w in World.walls.values():
		if w.tier > 0:
			reinforced += 1
	var raid_axes := 0
	var processed := 0
	for a in World.agent_list:
		processed += a.inv.count("plank") + a.inv.count("handle") + a.inv.count("cut_stone")
		for t in a.inv.tools:
			if t.type in Items.RAID_AXES:
				raid_axes += 1
	var in_kingdoms := 0
	var plots := 0
	for k in World.kingdoms.values():
		in_kingdoms += k.groups.size()
		plots += k.plots.size()
	var paved := 0
	for c in World.roads:
		if World.roads[c] >= 2:
			paved += 1
	var metal := _metal_line()
	var push := "push invited %d joined %d left %d wars %d demolished %d | " % [PushOut.invited, PushOut.joined, PushOut.left, PushOut.wars, Cities.demolished]
	return metal + push + ("kingdoms %d (%d groups) plots %d roads %d (paved %d) wars %d raids %d/%d won/%d lost | " % [World.kingdoms.size(), in_kingdoms, plots, World.roads.size(), paved, Wars.wars.size(), Raids.active.size(), Raids.won_count, Raids.lost_count]) + "min %3d | %4d ms | deaths %d | moods %s | factions %d servants %d | houses %s | fires %d walls %d (reinf %d) floors %d | chests %d (%d items) | workshops %d (working %d) | processed %d raid_axes %d | tools %d | warm %.2f hunger %.2f | jobs %s" % [
		minute, ms, World.deaths, moods, Factions.real_count(), servants, houses,
		World.fires.size(), World.walls.size(), reinforced, World.floors.size(), chests, stored, shops, working,
		processed, raid_axes, tools, warmth / n, hunger / n, jobs]


## v3 metal economy: nodes, items in circulation (agents, chests, loot bags), gear.
func _metal_line() -> String:
	var nodes := 0
	for b in World.node_buckets[ResourceNode.Type.METAL].values():
		for n in b:
			if n.amount > 0:
				nodes += 1
	var items := {}
	var tools := {}
	var invs: Array = []
	for a in World.agent_list:
		invs.append(a.inv)
	for fu in World.furniture.values():
		if fu.store.total() > 0:
			invs.append(fu.store)
	var in_crates := 0
	for fu in World.furniture.values():
		if fu.kind == Furniture.Kind.CRATE:
			in_crates += fu.store.total()
	for bag in World.loot.values():
		invs.append(bag)
	for inv in invs:
		for k in ["raw_iron", "iron_bar", "metal_door"]:
			items[k] = items.get(k, 0) + (inv.count(k) if inv is Inventory else inv.stacks.get(k, 0))
		for t in inv.tools:
			tools[t.type] = tools.get(t.type, 0) + 1
	var smelts := 0
	var working := 0
	var gang_smelts := 0
	for h in World.all_houses():
		if h.is_smeltery():
			smelts += 1
			working += 1 if h.operational() else 0
			var g: Faction = World.factions.get(h.faction_id)
			gang_smelts += 1 if g and g.is_gang() else 0
	var stone := 0
	var metal_doors := 0
	for w in World.walls.values():
		if w.tier >= 2:
			if w.is_door:
				metal_doors += 1
			else:
				stone += 1
	var iron_chests := 0
	for fu in World.furniture.values():
		if fu.kind == Furniture.Kind.CHEST and fu.tier >= 2:
			iron_chests += 1
	var armor := 0
	for k in Items.ARMOR:
		armor += tools.get(k, 0)
	var worn := 0
	var armoured := 0
	var gang_geared := 0
	for a in World.agent_list:
		worn += a.worn.size()
		armoured += 1 if a.is_armoured() else 0
		if a.faction.is_gang() and (a.is_armoured() or a.inv.has_tool("sword")):
			gang_geared += 1
	return ("metal nodes %d raw_iron %d bars %d (crates hold %d items) t2_picks %d swords %d armour %d iron_axes %d | " % [
		nodes, items.get("raw_iron", 0), items.get("iron_bar", 0), in_crates, tools.get("pickaxe_t2", 0), tools.get("sword", 0), armor, tools.get("iron_raiding_axe", 0)]) + (
		"smelteries %d (working %d, gangs %d) stone_walls %d metal_doors %d iron_chests %d | " % [smelts, working, gang_smelts, stone, metal_doors, iron_chests]) + (
		"worn %d (armoured agents %d, gang members geared %d) armoured kills won/lost %d/%d smeltery raids %d (won %d) | " % [worn, armoured, gang_geared, World.gear_fights.armoured_won, World.gear_fights.armoured_lost, Raids.smeltery_raids, Raids.smeltery_won])


func _process(delta: float) -> void:
	# Cap catch-up so a slow frame doesn't spiral.
	var remaining: float = min(SimClock.scaled(delta), Cfg.MAX_SIM_STEP * 20)
	var t := Time.get_ticks_usec()
	while remaining > 0.0:
		var s: float = min(remaining, Cfg.MAX_SIM_STEP)
		World.step(s)
		remaining -= s
	_sim_usec += Time.get_ticks_usec() - t


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: SimClock.toggle_pause()
			KEY_1: SimClock.set_speed(SimClock.SPEEDS[0])
			KEY_2: SimClock.set_speed(SimClock.SPEEDS[1])
			KEY_3: SimClock.set_speed(SimClock.SPEEDS[2])
			KEY_4: SimClock.set_speed(SimClock.SPEEDS[3])
			KEY_5: SimClock.set_speed(SimClock.SPEEDS[4])
			KEY_Z: _dynamic.show_zones = not _dynamic.show_zones
			KEY_L: _agents.show_labels = not _agents.show_labels
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p := get_global_mouse_position() / Cfg.CELL
		# Priority: agent -> fire -> loot bag -> furniture.
		var a := World.agent_at_point(p, 1.5)
		_agents.selected_id = a.id if a else -1
		_hud.selected_fire = null if a else _fire_at(p)
		_hud.selected_loot = null if a or _hud.selected_fire else _loot_at(p)
		_hud.selected_furniture = null if a or _hud.selected_fire or _hud.selected_loot else World.furniture.get(Vector2i(p.floor()))


## A fire on/next to the clicked cell, or the fire of the house whose interior was clicked.
func _fire_at(p: Vector2) -> Campfire:
	var c := Vector2i(p.floor())
	var best: Campfire = null
	var best_d := 1.5
	for f in World.fires.values():
		var d := World.center(f.cell).distance_to(p)
		if d < best_d:
			best_d = d
			best = f
	if best == null and not World.furniture.has(c):
		var h := World.house_at(c)
		if h and h.fire:
			best = h.fire
	return best


func _loot_at(p: Vector2) -> LootBag:
	var best: LootBag = null
	var best_d := 1.5
	for b in World.loot.values():
		var d := World.center(b.cell).distance_to(p)
		if d < best_d:
			best_d = d
			best = b
	return best
