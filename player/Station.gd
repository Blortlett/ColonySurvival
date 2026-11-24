extends RefCounted
## The chest or machine the player has open (Player Controller Plan §4, phase 4): the sim
## side of the interaction panels. The panels (ui/StationPanel.gd) only read this and queue
## requests; the requests are applied inside the sim step (PlayerController.control ->
## step), through Actions, so the rules are the AI's and the sim never depends on the UI.
##
## Nothing pauses: time keeps running at 1x. The panel closes when the body walks out of
## reach, takes a hit bigger than Cfg.PANEL_CLOSE_HIT, dies, or the furniture is gone.

var open: Furniture = null
var why_closed := "" # last reason the panel closed by itself (shown by the controller)

# Processing at a machine: one item at a time, `left` batches to go (-1 = until out of input).
var job := ""
var left := 0
var t := 0.0

var _requests: Array = [] # [kind, ...] queued by the panel, applied in step()
var _hp := 0.0


func is_chest() -> bool:
	return open != null and open.is_storage()


func is_machine() -> bool:
	return Actions.is_machine(open)


## Chests, crates and machines E can open: within reach, the one most in front of the body.
static func target(a: Agent) -> Furniture:
	var best: Furniture = null
	var best_score := -INF
	var c := a.cell()
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var fu: Furniture = World.furniture.get(c + Vector2i(dx, dy))
			if fu == null or not (fu.is_storage() or Actions.is_machine(fu)):
				continue
			var d := World.delta(a.pos, World.center(fu.cell))
			var len := d.length()
			if len > Cfg.PLAYER_USE_REACH:
				continue
			var score := (a.facing.dot(d / len) if len > 0.01 else 1.0) - len * 0.5
			if score > best_score:
				best_score = score
				best = fu
	return best


## Open a chest or machine. Returns why not, or "".
func try_open(a: Agent, fu: Furniture) -> String:
	var why := Actions.can_use_storage(a, fu) if fu.is_storage() else Actions.can_use_machine(a, fu)
	if why != "":
		return why
	close("")
	open = fu
	_hp = a.hp
	return ""


func close(reason: String) -> void:
	if open != null and reason != "":
		why_closed = reason
	open = null
	job = ""
	left = 0
	t = 0.0
	_requests.clear()


# --- Requests from the panel (applied in the next sim step) ---

## Move items: a Stock plan (+ deposit, - take; tools as "tool:<type>").
func request_transfer(plan: Dictionary) -> void:
	_requests.append(["transfer", plan])


## Run `n` batches of a processed item (-1 = until out of input). Replaces any running job.
func request_process(item: String, n: int) -> void:
	_requests.append(["process", item, n])


func request_craft(item: String) -> void:
	_requests.append(["craft", item])


func request_stop() -> void:
	_requests.append(["stop"])


## Progress of the running batch, 0..1.
func progress() -> float:
	return clampf(t / Items.PROCESS[job].secs, 0.0, 1.0) if job != "" else 0.0


# --- Sim step ---

func step(a: Agent, dt: float) -> void:
	if open == null:
		return
	var hit := _hp - a.hp
	_hp = a.hp
	if not a.alive:
		close("you died")
		return
	if hit > Cfg.PANEL_CLOSE_HIT:
		close("hit")
		return
	if World.furniture.get(open.cell) != open:
		close("the %s is gone" % open.label())
		return
	if World.dist(a.pos, World.center(open.cell)) > Cfg.PLAYER_USE_REACH + 0.25:
		close("out of reach")
		return
	var reqs := _requests
	_requests = []
	for r in reqs:
		_apply(a, r)
	_run(a, dt)


func _apply(a: Agent, r: Array) -> void:
	match r[0]:
		"transfer":
			if is_chest() and Actions.can_use_storage(a, open) == "":
				Actions.use_chest(a, open, r[1])
		"process":
			if is_machine() and Actions.can_use_machine(a, open) == "" and Items.PROCESS.has(r[1]) and Items.PROCESS[r[1]].machine == open.kind:
				if job != r[1]:
					t = 0.0
				job = r[1]
				left = r[2]
		"craft":
			if is_machine() and Actions.can_use_machine(a, open) == "" and r[1] in Actions.machine_menu(open.kind).craft:
				if Actions.craft(a, r[1]):
					EventBus.log_event("%s crafts a %s%s." % [a.short(), Items.label(r[1]), " at the anvil" if open.kind == Furniture.Kind.ANVIL else ""])
		"stop":
			job = ""
			t = 0.0


## Stand at the machine and run batches, like the AI's process step.
func _run(a: Agent, dt: float) -> void:
	if job == "":
		return
	if left == 0 or Actions.can_use_machine(a, open) != "" or not a.inv.has_cost(Items.PROCESS[job]["in"]):
		job = ""
		t = 0.0
		return
	t += dt
	if t >= Items.PROCESS[job].secs:
		t = 0.0
		Actions.process_batch(a, job)
		if left > 0:
			left -= 1
