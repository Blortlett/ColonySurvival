extends Node2D
## Builds the scene, steps the sim on sim time, handles observer input.

var _agents: Node2D
var _dynamic: Node2D
var _camera: Camera2D
var _hud: CanvasLayer


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


## Fast-forward N sim minutes, then save a full-map and a zoomed screenshot to user://.
func _shot(minutes: int) -> void:
	for i in int(minutes * 60.0 / Cfg.MAX_SIM_STEP):
		World.step(Cfg.MAX_SIM_STEP)
	var busiest: House = null
	for h in World.all_houses():
		if h.state == House.State.COMPLETE and (busiest == null or h.occupants.size() > busiest.occupants.size()):
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
	return "min %3d | %4d ms | deaths %d | moods %s | factions %d servants %d | houses %s | fires %d walls %d floors %d | chests %d (%d items) | tools %d | warm %.2f hunger %.2f | jobs %s" % [
		minute, ms, World.deaths, moods, Factions.real_count(), servants, houses,
		World.fires.size(), World.walls.size(), World.floors.size(), chests, stored, tools, warmth / n, hunger / n, jobs]


func _process(delta: float) -> void:
	# Cap catch-up so a slow frame doesn't spiral.
	var remaining: float = min(SimClock.scaled(delta), Cfg.MAX_SIM_STEP * 20)
	while remaining > 0.0:
		var s: float = min(remaining, Cfg.MAX_SIM_STEP)
		World.step(s)
		remaining -= s


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
