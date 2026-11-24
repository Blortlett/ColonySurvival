extends RefCounted
## What NPCs are asking the player right now (Player Social Plan §3): a short queue of
## offers, each with a timeout. The prompt UI (ui/OfferPrompt.gd) shows the first one;
## F1 / F2 or its buttons set the answer, and PlayerController.control() applies it inside
## the sim step through Social.answer_offer. An offer that runs out gets the default answer.
##
## Offer: {id, kind, from_id, fid, secs, expires (sim time), who, text, yes, no, color}

var queue: Array[Dictionary] = []
var _next_id := 1
## The answer waiting for the next sim step: [offer id, accept?], or [] if none.
var _answer: Array = []


## Queues an offer. False if the queue is full or this NPC already has one open, so the
## caller applies the default rule instead.
func add(o: Dictionary) -> bool:
	if queue.size() >= Cfg.OFFER_QUEUE_MAX or has_from(o.from_id):
		return false
	o.id = _next_id
	_next_id += 1
	o.expires = SimClock.time + o.secs
	queue.append(o)
	return true


func has_from(agent_id: int) -> bool:
	for o in queue:
		if o.from_id == agent_id:
			return true
	return false


## The offer on screen ({} if none).
func current() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


## Input and prompt buttons: answer the offer on screen (applied in the next sim step).
func answer(accept: bool) -> void:
	if not queue.is_empty():
		_answer = [queue[0].id, accept]


## Sim step: apply the answer given, then let offers that ran out take the default.
func step(p: Agent) -> void:
	if not _answer.is_empty():
		var id: int = _answer[0]
		var yes: bool = _answer[1]
		_answer = []
		for o in queue:
			if o.id == id:
				queue.erase(o)
				Social.answer_offer(p, o, yes, false)
				break
	for o in queue.duplicate():
		var npc: Agent = World.agents.get(o.from_id)
		if npc == null or not npc.alive:
			queue.erase(o) # the asker died: nothing to answer
		elif SimClock.time >= o.expires:
			queue.erase(o)
			Social.answer_offer(p, o, false, true)


## The body changed hands (death, takeover, watch mode): drop everything. Every offer kind's
## default is a plain refusal, so there's nothing to apply; the askers stop waiting.
func clear() -> void:
	for o in queue:
		Social.release_asker(o.from_id)
	queue.clear()
	_answer = []
