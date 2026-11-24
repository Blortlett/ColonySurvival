extends RefCounted
## Moving items between the player's slots (the inventory UI, agreed with the user
## 2026-11-24): drag and drop between the hotbar, the pack, an open chest and the armour
## slots; right click moves a whole stack across (pack <-> chest; with no chest open, pack
## <-> hotbar; armour on and off). The UI only queues these; they run inside the sim step
## (PlayerController.control), so the sim never depends on rendering.
##
## Places: "inv" (the body's 30 slots: 0-5 hotbar, 6-29 pack), "chest" (the open chest's
## store), "worn" (index into Items.ARMOR).

const INV := "inv"
const CHEST := "chest"
const WORN := "worn"


## The inventory behind a place, or null (no chest open / not allowed).
static func _inv_of(a: Agent, station, place: String) -> Inventory:
	if place == INV:
		return a.inv
	if place == CHEST and station.is_chest() and Actions.can_use_storage(a, station.open) == "":
		return station.open.store
	return null


## Drag slot (src, si) onto slot (dst, di). Same item stacks merge (the rest stays behind),
## anything else swaps. Returns true if something moved.
static func move(a: Agent, station, src: String, si: int, dst: String, di: int) -> bool:
	if src == dst and si == di:
		return false
	if src == WORN or dst == WORN:
		return _move_armour(a, station, src, si, dst, di)
	var from := _inv_of(a, station, src)
	var to := _inv_of(a, station, dst)
	if from == null or to == null or di < 0 or di >= to.cap():
		return false
	var e = from.take_slot(si)
	if e == null:
		return false
	var left = to.put_slot(di, e)
	if left == null:
		return true
	if left != e: # merged part of a stack: the rest goes back where it came from
		from.put_slot(si, left)
		return true
	# Different things: swap them.
	var other = to.take_slot(di)
	to.put_slot(di, e)
	from.put_slot(si, other)
	return true


## Armour: only the matching piece goes into a worn slot; taking one off needs an empty
## slot or a piece of the same kind to swap with.
static func _move_armour(a: Agent, station, src: String, si: int, dst: String, di: int) -> bool:
	if src == WORN and dst == WORN:
		return false
	if dst == WORN:
		if di < 0 or di >= Items.ARMOR.size():
			return false
		var from := _inv_of(a, station, src)
		if from == null:
			return false
		var e = from.entry(si)
		if not Inventory.is_tool_entry(e) or e.type != Items.ARMOR[di]:
			return false
		return _wear(a, from, si)
	# src == WORN: take it off into slot di of dst.
	if si < 0 or si >= Items.ARMOR.size():
		return false
	var slot: String = Items.ARMOR[si]
	var to := _inv_of(a, station, dst)
	if to == null or not a.worn.has(slot) or di < 0 or di >= to.cap():
		return false
	var cur = to.entry(di)
	if cur == null:
		to.put_slot(di, a.worn[slot])
		a.worn.erase(slot)
		return true
	if Inventory.is_tool_entry(cur) and cur.type == slot:
		return _wear(a, to, di)
	return false


## Put on the armour in slot i of `inv`; whatever was worn there takes its place.
static func _wear(a: Agent, inv: Inventory, i: int) -> bool:
	var e = inv.take_slot(i)
	if not Inventory.is_tool_entry(e) or not e.type in Items.ARMOR:
		inv.put_slot(i, e)
		return false
	var old = a.worn.get(e.type)
	a.worn[e.type] = e
	if old != null:
		inv.put_slot(i, old)
	return true


## Right click: move the whole stack across. Pack or hotbar -> the open chest, chest -> the
## pack; with no chest open, pack <-> hotbar. Armour in the pack goes on; worn armour comes
## off into the pack.
static func quick(a: Agent, station, src: String, si: int) -> bool:
	var chest := _inv_of(a, station, CHEST)
	if src == WORN:
		if si < 0 or si >= Items.ARMOR.size() or not a.worn.has(Items.ARMOR[si]):
			return false
		var piece = a.worn[Items.ARMOR[si]]
		var left = a.inv.put_in_range(piece, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
		if left == null:
			a.worn.erase(Items.ARMOR[si])
			return true
		return false
	var from := _inv_of(a, station, src)
	if from == null:
		return false
	var e = from.entry(si)
	if e == null:
		return false
	if src == INV and chest == null and Inventory.is_tool_entry(e) and e.type in Items.ARMOR:
		return _wear(a, from, si)
	e = from.take_slot(si)
	var left
	if src == CHEST:
		left = a.inv.put_in_range(e, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
		left = a.inv.put_in_range(left, 0, Cfg.HOTBAR_SLOTS)
	elif chest != null:
		left = chest.put_any(e)
	elif si < Cfg.HOTBAR_SLOTS:
		left = from.put_in_range(e, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
	else:
		left = from.put_in_range(e, 0, Cfg.HOTBAR_SLOTS)
	if left != null:
		var back = from.put_slot(si, left)
		if back != null:
			from.put_any(back) # can't happen (the slot was just emptied), but never lose items
	return left != e


## Everything in the pack (not the hotbar) into the open chest.
static func put_all(a: Agent, station) -> int:
	var chest := _inv_of(a, station, CHEST)
	if chest == null:
		return 0
	var moved := 0
	for i in range(Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS):
		if a.inv.entry(i) != null and quick(a, station, INV, i):
			moved += 1
	return moved


## Everything in the open chest into the pack (then the hotbar), as far as it fits.
static func take_all(a: Agent, station) -> int:
	var chest := _inv_of(a, station, CHEST)
	if chest == null:
		return 0
	var moved := 0
	for i in range(chest.slots.size()):
		if chest.entry(i) != null and quick(a, station, CHEST, i):
			moved += 1
	return moved
