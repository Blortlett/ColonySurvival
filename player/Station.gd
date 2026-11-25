extends RefCounted
## The chest or machine the player has open (Player Controller Plan §4, phase 4): the sim
## side of the interaction panels. The panels (ui/StationPanel.gd) only read this and queue
## requests; the requests are applied inside the sim step (PlayerController.control ->
## step), through Actions, so the rules are the AI's and the sim never depends on the UI.
##
## Nothing pauses: time keeps running at 1x. The panel closes when the body walks out of
## reach, takes a hit bigger than Cfg.PANEL_CLOSE_HIT, dies, or the furniture is gone.

var open: Furniture = null
## A groupmate whose pack, hotbar and worn gear the player has open (Player Group Base Plan
## R2: Trade on your own group's member). Only one of `open` / `member` is set.
var member: Agent = null
var stolen := false # this opening's theft was already counted (R8: once per opening)
var why_closed := "" # last reason the panel closed by itself (shown by the controller)

# Processing at a machine: one item at a time, `left` batches to go (-1 = until out of input).
var job := ""
var left := 0
var t := 0.0

var _requests: Array = [] # [kind, ...] queued by the panel, applied in step()
var _hp := 0.0


func is_chest() -> bool:
	return open != null and open.is_storage()


func is_member() -> bool:
	return member != null


## Anything open (a chest, machine, mailbox or a groupmate's inventory).
func active() -> bool:
	return open != null or member != null


## Taking from the open chest would be theft (another live group's; R8).
func is_theft(a: Agent) -> bool:
	return is_chest() and Actions.storage_theft(a, open)


## Something left the open chest for the player: the first time in an opening of a live
## foreign group's storage, that's theft (relations drop, witnesses attack).
func took(a: Agent) -> void:
	if stolen or not is_theft(a):
		return
	stolen = true
	Social.theft(a, open)


## Open groupmate `m`'s inventory (Trade on your own group). Returns why not, or "".
func open_member(a: Agent, m: Agent) -> String:
	var why := Social.member_trade_why(a, m)
	if why != "":
		return why
	close("")
	member = m
	_hp = a.hp
	return ""


func is_machine() -> bool:
	return Actions.is_machine(open)


## A mailbox: opens the group panel (ui/MailboxUI.gd). Any side's mailbox opens; a foreign
## one shows a read-only summary.
func is_mailbox() -> bool:
	return open != null and open.kind == Furniture.Kind.MAILBOX


## Chests, crates, machines and mailboxes E can open: within reach, the one most in front of the body.
static func target(a: Agent) -> Furniture:
	var best: Furniture = null
	var best_score := -INF
	var c := a.cell()
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var fu: Furniture = World.furniture.get(World.wc(c + Vector2i(dx, dy)))
			if fu == null or not (fu.is_storage() or Actions.is_machine(fu) or fu.kind == Furniture.Kind.MAILBOX):
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


## Open a chest, machine or mailbox. Returns why not, or "".
func try_open(a: Agent, fu: Furniture) -> String:
	var why := ""
	if fu.is_storage():
		why = Actions.can_use_storage(a, fu)
	elif fu.kind != Furniture.Kind.MAILBOX:
		why = Actions.can_use_machine(a, fu)
	if why != "":
		return why
	close("")
	open = fu
	_hp = a.hp
	return ""


func close(reason: String) -> void:
	if active() and reason != "":
		why_closed = reason
	open = null
	member = null
	stolen = false
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
	if not active():
		return
	var hit := _hp - a.hp
	_hp = a.hp
	if not a.alive:
		close("you died")
		return
	if hit > Cfg.PANEL_CLOSE_HIT:
		close("hit")
		return
	if member != null:
		if not member.alive or not World.agents.has(member.id):
			close("%s is gone" % member.short())
		elif not Social.is_groupmate(a, member):
			close("%s left your group" % member.short())
		elif World.dist(a.pos, member.pos) > Cfg.SOCIAL_RANGE * 1.5:
			close("%s is out of reach" % member.short())
		_requests.clear() # moves run through InvMoves (PlayerController), nothing queued here
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
				if Actions.use_chest(a, open, r[1]) > 0 and r[1].values().any(func(n): return n < 0):
					took(a)
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
