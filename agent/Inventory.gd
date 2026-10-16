class_name Inventory
extends RefCounted
## Single item-count capacity: each stackable unit and each tool counts as 1.

var stacks := {} # item -> count
var tools: Array = [] # [{type: String, dur: int}]


func count(item: String) -> int:
	return stacks.get(item, 0)


func total() -> int:
	var n := tools.size()
	for k in stacks:
		n += stacks[k]
	return n


func add(item: String, n: int) -> void:
	if n <= 0:
		return
	stacks[item] = count(item) + n


func remove(item: String, n: int) -> int:
	var have := count(item)
	var taken: int = min(have, n)
	if have - taken <= 0:
		stacks.erase(item)
	else:
		stacks[item] = have - taken
	return taken


func has_cost(cost: Dictionary) -> bool:
	for k in cost:
		if count(k) < cost[k]:
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k in cost:
		remove(k, cost[k])


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
	var tool = get_tool(t)
	if tool == null:
		return false
	tool.dur -= 1
	if tool.dur <= 0:
		tools.erase(tool)
		return true
	return false


func add_tool(t: String) -> void:
	tools.append({"type": t, "dur": Items.DURABILITY[t]})


func summary() -> String:
	var parts: Array[String] = []
	for k in stacks:
		parts.append("%s:%d" % [k, stacks[k]])
	for tool in tools:
		parts.append("%s(%d)" % [tool.type, tool.dur])
	return ", ".join(parts) if parts.size() > 0 else "empty"
