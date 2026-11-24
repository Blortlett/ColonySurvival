class_name Inventory
extends RefCounted
## Slot inventory (agreed with the user 2026-11-24): a fixed number of slots, each holding
## one stack of a stackable item (up to its stack size) or one tool. Agents have
## Cfg.AGENT_SLOTS: slots 0-5 are the hotbar, the rest the pack. Chests and crates get their
## slot count from Furniture.slots() (cap_fn); the capital's chest has no limit.
##
## `stacks` (item -> total count) and `tools` (the tool dicts, the same objects as in the
## slots) are caches kept by this class for fast reads. Change contents only through the
## methods here, never by writing to `stacks`, `tools` or `slots` directly.

const DEFAULT_STACK := 20
## Stack sizes (start). Anything not listed stacks to DEFAULT_STACK (wood, stone, hemp).
const STACK := {"berry": 10, "arrow": 20, "plank": 10, "handle": 10, "cut_stone": 10, "raw_iron": 10, "iron_bar": 10, "metal_door": 1}
const PREFILL_MAX := 256 # slot arrays up to this size are kept full length (grid UIs show the empties)

var slots: Array = [] # null | {"item": String, "n": int} | tool dict {"type": String, "dur": int}
var stacks := {} # cache: item -> count
var tools: Array = [] # cache: the tool dicts in the slots
var size := -1 # slot count; -1 = no limit (also see cap_fn)
var cap_fn := Callable() # if valid, returns the slot count (chests: Furniture.slots)
var _used := 0


func _init(n := -1) -> void:
	size = n
	_fit()


static func stack_of(item: String) -> int:
	return STACK.get(item, DEFAULT_STACK)


static func is_tool_entry(e) -> bool:
	return e != null and e.has("type")


func cap() -> int:
	if cap_fn.is_valid():
		return cap_fn.call()
	return size if size >= 0 else 1 << 30


## Grow the slot array up to the cap (small inventories are kept full length).
func _fit() -> void:
	var c := cap()
	if c <= PREFILL_MAX and slots.size() < c:
		slots.resize(c)


func count(item: String) -> int:
	return stacks.get(item, 0)


## Units held: each stackable unit and each tool counts as 1.
func total() -> int:
	var n := tools.size()
	for k in stacks:
		n += stacks[k]
	return n


func used_slots() -> int:
	return _used


func free_slots() -> int:
	return maxi(0, cap() - _used)


## How many of `item` would still fit: room in its partial stacks plus empty slots.
func room_for(item: String) -> int:
	var st := stack_of(item)
	var n := 0
	for e in slots:
		if e != null and not is_tool_entry(e) and e.item == item:
			n += st - e.n
	return n + free_slots() * st


## Room in units for a fresh item with the default stack (AI budgets).
func free_units() -> int:
	return free_slots() * DEFAULT_STACK


# --- Slot bookkeeping (keeps the caches) ---

func entry(i: int):
	_fit()
	return slots[i] if i >= 0 and i < slots.size() else null


func _assign(i: int, e) -> void:
	while i >= slots.size():
		slots.append(null)
	var old = slots[i]
	if old != null:
		_used -= 1
		if is_tool_entry(old):
			tools.erase(old)
		else:
			_count(old.item, -old.n)
	slots[i] = e
	if e != null:
		_used += 1
		if is_tool_entry(e):
			tools.append(e)
		else:
			_count(e.item, e.n)


func _count(item: String, d: int) -> void:
	var n: int = stacks.get(item, 0) + d
	if n <= 0:
		stacks.erase(item)
	else:
		stacks[item] = n


## Change the count of a stack in place (keeps the caches).
func _set_n(i: int, n: int) -> void:
	var e: Dictionary = slots[i]
	if n <= 0:
		_assign(i, null)
		return
	_count(e.item, n - e.n)
	e.n = n


## The first empty slot, in the preferred order. Tools fill the hotbar first, stacks the
## pack first (agents); other inventories fill from the top.
func _empty_slot(prefer_hotbar: bool) -> int:
	_fit()
	if free_slots() <= 0:
		return -1
	var hb := Cfg.HOTBAR_SLOTS if size == Cfg.AGENT_SLOTS else 0
	var order: Array = []
	if hb > 0 and not prefer_hotbar:
		order = range(hb, slots.size()) + range(0, hb)
	else:
		order = range(slots.size())
	for i in order:
		if slots[i] == null:
			return i
	if slots.size() < cap():
		slots.append(null)
		return slots.size() - 1
	return -1


# --- Stackables ---

## Adds up to n; returns how many fitted.
func add(item: String, n: int) -> int:
	if n <= 0:
		return 0
	_fit()
	var st := stack_of(item)
	var left := n
	for i in slots.size():
		var e = slots[i]
		if left > 0 and e != null and not is_tool_entry(e) and e.item == item and e.n < st:
			var m: int = mini(left, st - e.n)
			_set_n(i, e.n + m)
			left -= m
	while left > 0:
		var i := _empty_slot(false)
		if i < 0:
			break
		var m: int = mini(left, st)
		_assign(i, {"item": item, "n": m})
		left -= m
	return n - left


## Removes up to n, from the last slots first (the hotbar keeps its stacks longest).
func remove(item: String, n: int) -> int:
	var left: int = mini(n, count(item))
	var taken := left
	var hb := Cfg.HOTBAR_SLOTS if size == Cfg.AGENT_SLOTS else 0
	var order: Array = range(slots.size() - 1, -1, -1)
	if hb > 0:
		order = range(slots.size() - 1, hb - 1, -1) + range(hb - 1, -1, -1)
	for i in order:
		if left <= 0:
			break
		var e = slots[i]
		if e != null and not is_tool_entry(e) and e.item == item:
			var m: int = mini(left, e.n)
			_set_n(i, e.n - m)
			left -= m
	return taken


func has_cost(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		remove(k, cost[k])


# --- Tools ---

func has_tool(t: String) -> bool:
	for tool in tools:
		if tool.type == t:
			return true
	return false


func get_tool(t: String):
	for tool in tools:
		if tool.type == t:
			return tool
	return null


## Spend one durability; returns true if the tool broke.
func wear(t: String) -> bool:
	return wear_tool(get_tool(t))


func wear_tool(tool) -> bool:
	if tool == null:
		return false
	tool.dur -= 1
	if tool.dur <= 0:
		take_tool(tool)
		return true
	return false


## A new tool at full durability. False if there's no free slot.
func add_tool(t: String) -> bool:
	return put_tool({"type": t, "dur": Items.DURABILITY[t]})


## Put an existing tool dict into a free slot. False if there's none.
func put_tool(tool: Dictionary) -> bool:
	var i := _empty_slot(true)
	if i < 0:
		return false
	_assign(i, tool)
	return true


func take_tool(tool) -> void:
	var i := slots.find(tool)
	if i >= 0:
		_assign(i, null)


func slot_of(e) -> int:
	return slots.find(e)


# --- Moving between slots (the player's inventory UI) ---

## Take what's in slot i out (null if empty).
func take_slot(i: int):
	var e = entry(i)
	if e != null:
		_assign(i, null)
	return e


## Put an entry into slot i if it's empty, or merge a matching stack. Returns what's left
## over (null if it all went in). Slot i must be within the cap.
func put_slot(i: int, e):
	if e == null or i < 0 or i >= cap():
		return e
	_fit()
	var cur = entry(i)
	if cur == null:
		_assign(i, e)
		return null
	if is_tool_entry(cur) or is_tool_entry(e) or cur.item != e.item:
		return e
	var m: int = mini(e.n, stack_of(e.item) - cur.n)
	_set_n(i, cur.n + m)
	if e.n - m <= 0:
		return null
	return {"item": e.item, "n": e.n - m}


## Add an entry anywhere it fits (stacks merge). Returns what's left over (null if none).
func put_any(e):
	if e == null:
		return null
	if is_tool_entry(e):
		return null if put_tool(e) else e
	var got := add(e.item, e.n)
	return null if got >= e.n else {"item": e.item, "n": e.n - got}


## Put an entry into slots lo..hi-1 only: merge into matching stacks there, then the first
## empty slot. Returns what's left over (null if it all went in).
func put_in_range(e, lo: int, hi: int):
	if e == null:
		return null
	_fit()
	hi = mini(hi, cap())
	if not is_tool_entry(e):
		for i in range(lo, mini(hi, slots.size())):
			var cur = slots[i]
			if cur != null and not is_tool_entry(cur) and cur.item == e.item:
				e = put_slot(i, e)
				if e == null:
					return null
	for i in range(lo, hi):
		if entry(i) == null:
			return put_slot(i, e)
	return e


func summary() -> String:
	var parts: Array[String] = []
	for k in stacks:
		parts.append("%s:%d" % [k, stacks[k]])
	for tool in tools:
		parts.append("%s(%d)" % [tool.type, tool.dur])
	return ", ".join(parts) if parts.size() > 0 else "empty"
