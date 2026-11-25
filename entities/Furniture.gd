class_name Furniture
extends RefCounted
## A piece of furniture on a floor tile: a chest or smeltery crate (with storage), a
## workshop machine (sawmill, stone cutter) or a smeltery machine (furnace, anvil).
## Walkable (agents stand on or next to it), except the mailbox outside a building's door,
## which is solid. Decays like walls when unprotected.

enum Kind { CHEST, SAWMILL, CUTTER, BOARD, FURNACE, ANVIL, CRATE, MAILBOX } # append only: saved indices

var cell: Vector2i
var kind: Kind
var tier := 0 # chests: 0 basic, 1 reinforced, 2 iron-bound
var owner_id: int # faction id
var _house: WeakRef = null
## House (or workshop) it belongs to. Weak, to avoid a House <-> chest reference loop.
var house = null:
	get: return _house.get_ref() if _house else null
	set(v): _house = weakref(v) if v else null
var store := Inventory.new() # chest contents (slots: see slots())
var hp: float
var max_hp: float


func _init(c: Vector2i, k: Kind, owner: int, t: int = 0) -> void:
	cell = c
	kind = k
	owner_id = owner
	tier = t
	max_hp = Items.FURNITURE_HP * [1.0, 2.5, 4.0][t]
	hp = max_hp
	store.cap_fn = slots


func slots() -> int:
	match kind:
		Kind.CHEST:
			var h: House = house
			if h and h.plot_kid != -1:
				var k: Kingdom = World.kingdoms.get(h.plot_kid)
				if k and k.capital == h:
					return 1 << 30 # the capital's chest has no limit (Kingdom Wars Plan §3.2)
			return Items.CHEST_SLOTS[tier]
		Kind.CRATE: return Items.CRATE_SLOTS
	return 0


## Chests and crates hold items (and spill them as a loot bag when destroyed).
func is_storage() -> bool:
	return kind == Kind.CHEST or kind == Kind.CRATE


func free_slots() -> int:
	return store.free_slots()


## Room in units for a fresh 20-stack per free slot (AI budgets).
func free_units() -> int:
	return store.free_units()


func free_for(item: String) -> int:
	return store.room_for(item)


## Blocks movement. Nothing does any more: agents walk through mailboxes (R7). Furniture
## still blocks building (World.can_build checks it).
func is_solid() -> bool:
	return false


## Swap in a store (chest upgrade, emptied chest); its slot count follows this furniture.
func set_store(inv: Inventory) -> void:
	store = inv
	store.cap_fn = slots


func label() -> String:
	match kind:
		Kind.CHEST: return ["basic chest", "reinforced chest", "iron-bound chest"][tier]
		Kind.FURNACE: return "furnace"
		Kind.ANVIL: return "anvil"
		Kind.CRATE: return "storage crate"
		Kind.SAWMILL: return "sawmill"
		Kind.CUTTER: return "stone cutter"
		Kind.BOARD: return "kingdom board"
		Kind.MAILBOX: return "mailbox"
	return "furniture"


## Build-cost key for placing this kind (Items.BUILD_COSTS).
static func cost_key(k: int) -> String:
	match k:
		Kind.SAWMILL: return "sawmill"
		Kind.CUTTER: return "cutter"
		Kind.FURNACE: return "furnace"
		Kind.ANVIL: return "anvil"
		Kind.CRATE: return "crate"
		Kind.BOARD: return "board"
		Kind.MAILBOX: return "mailbox"
	return "chest"
