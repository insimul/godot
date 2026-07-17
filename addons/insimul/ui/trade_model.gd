class_name InsimulTradeModel
extends RefCounted
## Trade view-model — inventory / container / merchant (US-GU2).
##
## The Godot mirror of the engine-neutral trade contract
## (packages/core/src/ui/trade-model.ts), backed EXCLUSIVELY by save.currentState.
## Every read and every mutation goes through the live currentState Dictionary
## handed to attach() — the model keeps NO private item store, which is the
## "state-location invariant": inventory, container loot, and merchant stock live in
## exactly one place (the save), so a snapshot at any moment is the whole truth.
##
## State paths (a structural subset of CurrentGameState):
##   - player.gold / player.inventory
##   - containers.containers[container_id].items
##   - npcs.merchantStates[merchant_id].{goldReserve, items}
##
## Conservation is a hard invariant of every op: items MOVE between stacks (never
## created/destroyed); a merchant trade conserves gold (player.gold +
## merchant.goldReserve constant). Shared matrices:
## packages/core/conformance/ui/trade-cases.json. Each item stack is a Dictionary
## { itemId, quantity, value? }.

var _state: Dictionary = {}


## Bind the live currentState slice. The model mutates it IN PLACE; it never copies.
func attach(current_state: Dictionary) -> void:
	_state = current_state


func _init(current_state: Dictionary = {}) -> void:
	_state = current_state


# ── Reads (all straight off currentState — no private copy) ────────────────────

func player_gold() -> int:
	return int(_player().get("gold", 0))


## The player's live inventory array (same reference as currentState).
func player_items() -> Array:
	return _player().get("inventory", [])


func container_items(container_id: String) -> Array:
	var c := _container(container_id)
	return c.get("items", []) if not c.is_empty() else []


func merchant_items(merchant_id: String) -> Array:
	var m := _merchant(merchant_id)
	return m.get("items", []) if not m.is_empty() else []


func merchant_gold(merchant_id: String) -> int:
	var m := _merchant(merchant_id)
	return int(m.get("goldReserve", 0)) if not m.is_empty() else 0


# ── Container transfer ─────────────────────────────────────────────────────────

## Take `qty` of `item_id` from a container into the player inventory. qty <= 0
## takes the whole stack; a request larger than stock is clamped. Returns
## { ok, reason, moved }.
func take_from_container(container_id: String, item_id: String, qty: int = 0) -> Dictionary:
	var container := _container(container_id)
	if container.is_empty():
		return _fail("no_container")
	var items: Array = container.get("items", [])
	var stack := _find_stack(items, item_id)
	var avail := int(stack.get("quantity", 0)) if not stack.is_empty() else 0
	if avail <= 0:
		return _fail("not_present")
	var moved := min(qty, avail) if qty > 0 else avail
	var value: Variant = stack.get("value", null)
	_remove_stack(items, item_id, moved)
	_add_stack(player_items(), item_id, moved, value)
	return _ok(moved)


## Take every stack from a container into the player inventory.
func take_all_from_container(container_id: String) -> Dictionary:
	var container := _container(container_id)
	if container.is_empty():
		return _fail("no_container")
	var moved := 0
	# Snapshot the id list first — take_from_container mutates container.items.
	var ids: Array = []
	for s in container.get("items", []):
		ids.append(String(s.get("itemId", "")))
	for id in ids:
		var r := take_from_container(container_id, id, 0)
		if r.get("ok", false):
			moved += int(r.get("moved", 0))
	return _ok(moved)


# ── Merchant buy / sell ────────────────────────────────────────────────────────

## Buy `qty` of `item_id` from a merchant: item merchant->player, gold player->merchant.
func buy(merchant_id: String, item_id: String, qty: int) -> Dictionary:
	if qty <= 0:
		return _fail("bad_qty")
	var merchant := _merchant(merchant_id)
	if merchant.is_empty():
		return _fail("no_merchant")
	var items: Array = merchant.get("items", [])
	var stack := _find_stack(items, item_id)
	var avail := int(stack.get("quantity", 0)) if not stack.is_empty() else 0
	if avail < qty:
		return _fail("out_of_stock")
	var unit := int(stack.get("value", 0))
	var cost := unit * qty
	if player_gold() < cost:
		return _fail("insufficient_gold")
	_remove_stack(items, item_id, qty)
	_add_stack(player_items(), item_id, qty, unit)
	_player()["gold"] = player_gold() - cost
	merchant["goldReserve"] = int(merchant.get("goldReserve", 0)) + cost
	return _ok(qty)


## Sell `qty` of `item_id` to a merchant: item player->merchant, gold merchant->player.
func sell(merchant_id: String, item_id: String, qty: int) -> Dictionary:
	if qty <= 0:
		return _fail("bad_qty")
	var merchant := _merchant(merchant_id)
	if merchant.is_empty():
		return _fail("no_merchant")
	var stack := _find_stack(player_items(), item_id)
	var have := int(stack.get("quantity", 0)) if not stack.is_empty() else 0
	if have < qty:
		return _fail("insufficient_items")
	var unit := int(stack.get("value", 0))
	var revenue := unit * qty
	if int(merchant.get("goldReserve", 0)) < revenue:
		return _fail("merchant_cannot_afford")
	_remove_stack(player_items(), item_id, qty)
	_add_stack(merchant.get("items", []), item_id, qty, unit)
	_player()["gold"] = player_gold() + revenue
	merchant["goldReserve"] = int(merchant.get("goldReserve", 0)) - revenue
	return _ok(qty)


# ── Internal helpers ───────────────────────────────────────────────────────────

func _player() -> Dictionary:
	return _state.get("player", {})


func _container(container_id: String) -> Dictionary:
	var containers: Dictionary = _state.get("containers", {}).get("containers", {})
	return containers.get(container_id, {})


func _merchant(merchant_id: String) -> Dictionary:
	var merchants: Dictionary = _state.get("npcs", {}).get("merchantStates", {})
	return merchants.get(merchant_id, {})


func _find_stack(items: Array, item_id: String) -> Dictionary:
	for i in items:
		if String(i.get("itemId", "")) == item_id:
			return i
	return {}


## Merge `qty` of `item_id` into `items`, stacking onto an existing entry.
func _add_stack(items: Array, item_id: String, qty: int, value: Variant = null) -> void:
	if qty <= 0:
		return
	var existing := _find_stack(items, item_id)
	if not existing.is_empty():
		existing["quantity"] = int(existing.get("quantity", 0)) + qty
		return
	var stack := {"itemId": item_id, "quantity": qty}
	if value != null:
		stack["value"] = value
	items.append(stack)


## Remove `qty` of `item_id` from `items`, dropping the stack when it hits 0.
func _remove_stack(items: Array, item_id: String, qty: int) -> void:
	for idx in range(items.size()):
		if String(items[idx].get("itemId", "")) == item_id:
			items[idx]["quantity"] = int(items[idx].get("quantity", 0)) - qty
			if int(items[idx]["quantity"]) <= 0:
				items.remove_at(idx)
			return


func _ok(moved: int) -> Dictionary:
	return {"ok": true, "reason": "", "moved": moved}


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "moved": 0}
