extends Node
## Inventory System -- autoloaded singleton.
## Manages player inventory with item stacks, gold, equipment slots, and mercantile support.
## Mirrors the Babylon.js InventorySystem and DataSource item handling.

signal item_added(item: Dictionary)
signal item_removed(item_id: String)
signal item_dropped(item: Dictionary)
signal item_used(item: Dictionary)
signal item_equipped(item: Dictionary)
signal item_unequipped(item: Dictionary)
signal gold_changed(new_gold: int)

## Item types matching Insimul's shared ItemType enum.
const ITEM_TYPES: Array[String] = [
	"quest", "collectible", "key", "consumable", "weapon", "armor",
	"food", "drink", "material", "tool", "document", "environmental",
	"decoration", "furniture", "equipment", "container", "accessory", "ammunition",
]

## Equipment slot names.
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "accessory"]

## Filter categories for UI.
const FILTER_CATEGORIES: Array[String] = [
	"all", "weapons_armor", "consumables", "materials", "quest", "other",
]

## Rarity tiers.
const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]

var max_slots := 20
var player_gold := 100

## Whether language-learning mode is active.
var _language_learning := false

## Each slot Dictionary may contain:
##   id, name, description, type, quantity, icon, quest_id, value, sell_value,
##   weight, tradeable, equipped, effects, equip_slot, category, material,
##   base_type, rarity, possessable, translations
var _slots: Array[Dictionary] = []

## Equipped items by slot name ("weapon", "armor", "accessory")
var _equipped_slots: Dictionary = {}

func initialize() -> void:
	_slots.clear()
	_equipped_slots.clear()
	player_gold = 100
	_language_learning = false
	print("[Insimul] InventorySystem initialized (max slots: %d, gold: %d)" % [max_slots, player_gold])

# --- Language-Learning Mode ---

## Enable language-learning mode so inventory shows target-language item names.
func set_language_learning(enabled: bool) -> void:
	_language_learning = enabled
	print("[Insimul] Language learning mode: %s" % ["ON" if enabled else "OFF"])

## Get whether language-learning mode is active.
func is_language_learning() -> bool:
	return _language_learning

## Get the display name for an item, using target language when available.
## translations is a Dictionary keyed by language, e.g. { "French": { "target_word": "Épée", ... } }
func get_display_name(item: Dictionary, target_language: String = "") -> String:
	if _language_learning:
		var translations: Dictionary = item.get("translations", {})
		if not translations.is_empty():
			# Use specified language if available
			if not target_language.is_empty() and translations.has(target_language):
				var entry: Dictionary = translations[target_language]
				var tw: String = entry.get("target_word", "")
				if not tw.is_empty():
					return tw
			# Fallback: first available translation
			for lang in translations:
				var entry: Dictionary = translations[lang]
				var tw: String = entry.get("target_word", "")
				if not tw.is_empty():
					return tw
	return item.get("name", item.get("id", ""))

# --- Item Management ---

## Add an item to inventory. The item Dictionary should have at minimum an "id" key.
## Supported fields: id, name, description, type, quantity, icon, quest_id, value,
## sell_value, weight, tradeable, equipped, effects, equip_slot, category, material,
## base_type, rarity, possessable, language_learning_data.
func add_item(item: Dictionary) -> bool:
	var item_id: String = item.get("id", item.get("item_id", ""))
	var qty: int = item.get("quantity", item.get("count", 1))
	# Stack onto existing slot if possible
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			slot["quantity"] = slot.get("quantity", slot.get("count", 0)) + qty
			item_added.emit(slot.duplicate())
			return true
	if _slots.size() >= max_slots:
		return false
	# Normalize to "id" and "quantity" keys
	var normalized := item.duplicate()
	if not normalized.has("id") and normalized.has("item_id"):
		normalized["id"] = normalized["item_id"]
	if not normalized.has("quantity"):
		normalized["quantity"] = qty
	_slots.append(normalized)
	item_added.emit(normalized.duplicate())
	return true

func add_item_by_id(item_id: String, quantity: int = 1) -> bool:
	return add_item({"id": item_id, "name": item_id, "quantity": quantity, "type": "collectible", "tradeable": true})

## Remove [quantity] units of an item. Returns false if insufficient quantity.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(_slots.size()):
		var slot_id: String = _slots[i].get("id", _slots[i].get("item_id", ""))
		if slot_id == item_id:
			var current: int = _slots[i].get("quantity", _slots[i].get("count", 0))
			if current < quantity:
				return false
			if str(_slots[i].get("type", "")) == "quest" and not str(_slots[i].get("quest_id", "")).is_empty():
				return false
			_slots[i]["quantity"] = current - quantity
			if _slots[i]["quantity"] <= 0:
				_slots.remove_at(i)
			item_removed.emit(item_id)
			return true
	return false

func drop_item(item_id: String) -> bool:
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			if str(slot.get("type", "collectible")) == "quest":
				return false  # Cannot drop quest items
			if slot.get("equipped", false):
				return false  # Cannot drop equipped items
			var copy := slot.duplicate()
			remove_item(item_id, 1)
			item_dropped.emit(copy)
			return true
	return false

func use_item(item_id: String) -> bool:
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			var item_type: String = str(slot.get("type", "collectible"))

			# Quest, key, document, collectible items: emit event without consuming
			if item_type in ["quest", "key", "document", "collectible"]:
				item_used.emit(slot.duplicate())
				return true

			# Consumable, food, drink: apply effects and consume
			if item_type in ["consumable", "food", "drink"]:
				var copy := slot.duplicate()
				remove_item(item_id, 1)
				item_used.emit(copy)
				return true

	return false

func get_item_count(item_id: String) -> int:
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			return slot.get("quantity", slot.get("count", 0))
	return 0

## Check if the player has at least one of the given item.
func has_item(item_id: String) -> bool:
	return get_item_count(item_id) > 0

## Return the item Dictionary for a given id, or empty dict if not found.
func get_item(item_id: String) -> Dictionary:
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			return slot
	return {}

## Return a copy of all inventory items.
func get_all_items() -> Array[Dictionary]:
	return _slots.duplicate()

## Remove all items from inventory.
func clear_all() -> void:
	_slots.clear()
	_equipped_slots.clear()
	print("[Insimul] InventorySystem cleared")

# --- Equipment Management ---

func _get_slot_for_type(item_type: String) -> String:
	match item_type:
		"weapon": return "weapon"
		"armor": return "armor"
		"tool": return "accessory"
		_: return ""

func equip_item(item_id: String) -> bool:
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			var equip_slot: String = slot.get("equip_slot", "")
			if equip_slot.is_empty():
				equip_slot = _get_slot_for_type(str(slot.get("type", "collectible")))
			if equip_slot.is_empty():
				return false

			# Unequip any existing item in the slot
			unequip_slot(equip_slot)

			slot["equipped"] = true
			_equipped_slots[equip_slot] = item_id
			item_equipped.emit(slot.duplicate())
			print("[Insimul] Equipped: %s in slot %s" % [slot.get("name", item_id), equip_slot])
			return true
	return false

func unequip_slot(slot_name: String) -> bool:
	if not _equipped_slots.has(slot_name):
		return false
	var item_id: String = _equipped_slots[slot_name]
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			slot["equipped"] = false
			item_unequipped.emit(slot.duplicate())
			print("[Insimul] Unequipped: %s from slot %s" % [slot.get("name", item_id), slot_name])
			break
	_equipped_slots.erase(slot_name)
	return true

func get_equipped_item(slot_name: String) -> Dictionary:
	if not _equipped_slots.has(slot_name):
		return {}
	var item_id: String = _equipped_slots[slot_name]
	for slot in _slots:
		var slot_id: String = slot.get("id", slot.get("item_id", ""))
		if slot_id == item_id:
			return slot
	return {}

func has_equipped_in_slot(slot_name: String) -> bool:
	return _equipped_slots.has(slot_name)

## Update the equipment display from a Dictionary of {slot_name: item_dict}.
func update_equipment_display(equipped: Dictionary) -> void:
	for slot_name in equipped:
		var item: Dictionary = equipped[slot_name]
		if item.is_empty():
			unequip_slot(slot_name)
		else:
			var item_id: String = item.get("id", item.get("item_id", ""))
			if not item_id.is_empty():
				equip_item(item_id)

# --- Gold Management ---

func get_gold() -> int:
	return player_gold

func set_gold(amount: int) -> void:
	player_gold = max(0, amount)
	gold_changed.emit(player_gold)

func add_gold(amount: int) -> void:
	player_gold += amount
	gold_changed.emit(player_gold)
	print("[Insimul] AddGold: +%d (total: %d)" % [amount, player_gold])

func remove_gold(amount: int) -> bool:
	if player_gold < amount:
		return false
	player_gold -= amount
	gold_changed.emit(player_gold)
	print("[Insimul] RemoveGold: -%d (total: %d)" % [amount, player_gold])
	return true

# --- Cleanup ---

## Clear all inventory state and reset.
func dispose() -> void:
	_slots.clear()
	_equipped_slots.clear()
	player_gold = 0
	print("[Insimul] InventorySystem disposed")
