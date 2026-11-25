extends RefCounted
## Moving items between the player's slots (the inventory UI, agreed with the user
## 2026-11-24): drag and drop between the hotbar, the pack, an open chest and the armour
## slots; right click moves a whole stack across (pack <-> chest; with no chest open, pack
## <-> hotbar; armour on and off). The UI only queues these; they run inside the sim step
## (PlayerController.control), so the sim never depends on rendering.
##
## Places: "inv" (the body's 30 slots: 0-5 hotbar, 6-29 pack), "chest" (the open chest's
## store), "worn" (index into Items.ARMOR). With a groupmate's inventory open (Player Group
## Base Plan R2, Station.member): "minv" (their 30 slots) and "mworn" (their armour). The
## player moves anything either way, worn pieces included.
##
## Anything leaving a chest goes through Station.took: taking from another live group's
## storage is theft (R8). Putting in is always free.

const INV := "inv"
const CHEST := "chest"
const WORN := "worn"
const M_INV := "minv"
const M_WORN := "mworn"


## The inventory behind a place, or null (no chest / member open, or not allowed).
static func _inv_of(a: Agent, station, place: String) -> Inventory:
	match place:
		INV:
			return a.inv
		CHEST:
			if station.is_chest() and Actions.can_use_storage(a, station.open) == "":
				return station.open.store
		M_INV:
			if station.is_member():
				return station.member.inv
	return null


static func _is_worn(place: String) -> bool:
	return place == WORN or place == M_WORN


## The body whose armour a worn place shows, or null.
static func _body_of(a: Agent, station, place: String) -> Agent:
	if place == WORN:
		return a
	if place == M_WORN and station.is_member():
		return station.member
	return null


## Where a right click sends things from `place`: the other side of the open panel (chest or
## groupmate), or null with nothing open (then pack <-> hotbar, armour on / off).
static func _across(a: Agent, station, place: String) -> Inventory:
	if place == CHEST or place == M_INV or place == M_WORN:
		return a.inv
	var chest := _inv_of(a, station, CHEST)
	if chest != null:
		return chest
	return _inv_of(a, station, M_INV)


## Pack first, then the hotbar. Returns what didn't fit (or null).
static func _into_pack(inv: Inventory, e):
	var left = inv.put_in_range(e, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
	return inv.put_in_range(left, 0, Cfg.HOTBAR_SLOTS) if left != null else null


## Drag slot (src, si) onto slot (dst, di). Same item stacks merge (the rest stays behind),
## anything else swaps. Returns true if something moved.
static func move(a: Agent, station, src: String, si: int, dst: String, di: int) -> bool:
	if src == dst and si == di:
		return false
	if _is_worn(src) or _is_worn(dst):
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
		_took(a, station, src, dst)
		return true
	if left != e: # merged part of a stack: the rest goes back where it came from
		from.put_slot(si, left)
		_took(a, station, src, dst)
		return true
	# Different things: swap them.
	var other = to.take_slot(di)
	to.put_slot(di, e)
	from.put_slot(si, other)
	_took(a, station, src, dst, true)
	return true


## Note a take from the open chest (src chest, or a swap that brought a chest item out).
static func _took(a: Agent, station, src: String, dst: String, swapped := false) -> void:
	if src == dst:
		return
	if src == CHEST or (dst == CHEST and swapped):
		station.took(a)


## Armour: only a matching piece (iron or cloth for that slot) goes into a worn slot; taking one off needs an empty
## slot or a piece of the same kind to swap with. Worn to worn (player <-> groupmate) swaps
## the pieces in that slot.
static func _move_armour(a: Agent, station, src: String, si: int, dst: String, di: int) -> bool:
	if _is_worn(src) and _is_worn(dst):
		var sa := _body_of(a, station, src)
		var da := _body_of(a, station, dst)
		if sa == null or da == null or sa == da or si != di or si < 0 or si >= Items.ARMOR.size():
			return false
		var s: String = Items.ARMOR[si]
		if not sa.worn.has(s):
			return false
		var old = da.worn.get(s)
		da.worn[s] = sa.worn[s]
		if old != null:
			sa.worn[s] = old
		else:
			sa.worn.erase(s)
		return true
	if _is_worn(dst):
		var da := _body_of(a, station, dst)
		if da == null or di < 0 or di >= Items.ARMOR.size():
			return false
		var from := _inv_of(a, station, src)
		if from == null:
			return false
		var e = from.entry(si)
		if not Inventory.is_tool_entry(e) or Items.wear_slot(e.type) != Items.ARMOR[di]:
			return false
		var ok := _wear(da, from, si)
		if ok:
			_took(a, station, src, dst)
		return ok
	# src is worn: take it off into slot di of dst.
	var sa := _body_of(a, station, src)
	if sa == null or si < 0 or si >= Items.ARMOR.size():
		return false
	var slot: String = Items.ARMOR[si]
	var to := _inv_of(a, station, dst)
	if to == null or not sa.worn.has(slot) or di < 0 or di >= to.cap():
		return false
	var cur = to.entry(di)
	if cur == null:
		to.put_slot(di, sa.worn[slot])
		sa.worn.erase(slot)
		return true
	if Inventory.is_tool_entry(cur) and Items.wear_slot(cur.type) == slot:
		var ok := _wear(sa, to, di)
		if ok:
			_took(a, station, src, dst, true)
		return ok
	return false


## Put the armour in slot i of `inv` on `body`; whatever was worn there takes its place.
static func _wear(body: Agent, inv: Inventory, i: int) -> bool:
	var e = inv.take_slot(i)
	if not Inventory.is_tool_entry(e) or Items.wear_slot(e.type) == "":
		inv.put_slot(i, e)
		return false
	var slot := Items.wear_slot(e.type)
	var old = body.worn.get(slot)
	body.worn[slot] = e
	if old != null:
		inv.put_slot(i, old)
	return true


## Right click: move the whole stack across. Pack or hotbar -> the open chest (or the open
## groupmate's pack), chest or groupmate -> the player's pack; with nothing open, pack <->
## hotbar. Armour in the pack goes on; worn armour comes off into the pack (across, if a
## panel is open).
static func quick(a: Agent, station, src: String, si: int) -> bool:
	var across := _across(a, station, src)
	if _is_worn(src):
		var body := _body_of(a, station, src)
		if body == null or si < 0 or si >= Items.ARMOR.size() or not body.worn.has(Items.ARMOR[si]):
			return false
		# Off into a pack: the groupmate's for the player's own armour while they're open,
		# else the player's (also with a chest open, as before).
		var to: Inventory = across if station.is_member() else a.inv
		var left = to.put_in_range(body.worn[Items.ARMOR[si]], Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
		if left == null:
			body.worn.erase(Items.ARMOR[si])
			return true
		return false
	var from := _inv_of(a, station, src)
	if from == null:
		return false
	var e = from.entry(si)
	if e == null:
		return false
	if src == INV and across == null and Inventory.is_tool_entry(e) and Items.wear_slot(e.type) != "":
		return _wear(a, from, si)
	e = from.take_slot(si)
	var left
	if across != null and (across == a.inv or station.is_member()):
		left = _into_pack(across, e)
	elif across != null:
		left = across.put_any(e)
	elif si < Cfg.HOTBAR_SLOTS:
		left = from.put_in_range(e, Cfg.HOTBAR_SLOTS, Cfg.AGENT_SLOTS)
	else:
		left = from.put_in_range(e, 0, Cfg.HOTBAR_SLOTS)
	if left != null:
		var back = from.put_slot(si, left)
		if back != null:
			from.put_any(back) # can't happen (the slot was just emptied), but never lose items
	if left != e and src == CHEST:
		station.took(a)
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
