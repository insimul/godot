extends Node
## Save System — autoloaded singleton.
## Manages save slots with quest progress, inventory, player stats, and time.

const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 3
const SAVE_VERSION := 1

signal save_completed(slot: int)
signal load_completed(slot: int)
signal save_error(message: String)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ─────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────

func save_game(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		save_error.emit("Invalid save slot: %d" % slot)
		return false

	var data := _collect_save_data()
	var path := _slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		save_error.emit("Failed to open save file: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	save_completed.emit(slot)
	print("[Insimul] Game saved to slot %d" % slot)
	return true

func load_game(slot: int) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		save_error.emit("Invalid save slot: %d" % slot)
		return false

	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		save_error.emit("No save found in slot %d" % slot)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		save_error.emit("Failed to open save file: %s" % path)
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		save_error.emit("Failed to parse save data")
		return false

	var data: Dictionary = json.data if json.data is Dictionary else {}
	_apply_save_data(data)
	load_completed.emit(slot)
	print("[Insimul] Game loaded from slot %d" % slot)
	return true

func delete_save(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("[Insimul] Deleted save slot %d" % slot)

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))

func get_save_info(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var file := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if not file:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data: Dictionary = json.data if json.data is Dictionary else {}
	return {
		"slot": slot,
		"timestamp": data.get("timestamp", ""),
		"day": data.get("time", {}).get("day", 1),
		"hour": data.get("time", {}).get("hour", 6),
		"quest_count": data.get("quests", {}).get("active", []).size(),
		"gold": data.get("inventory", {}).get("gold", 0),
		"version": data.get("version", 0),
	}

func get_all_save_info() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(MAX_SLOTS):
		result.append(get_save_info(i))
	return result

# ─────────────────────────────────────────────
# Data collection
# ─────────────────────────────────────────────

func _collect_save_data() -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
	}

	# Time
	data["time"] = {
		"day": GameClock.day,
		"hour": GameClock.current_hour,
	}

	# Player position and stats
	var player: Node3D = _find_player()
	if player:
		data["player"] = {
			"position": {"x": player.global_position.x, "y": player.global_position.y, "z": player.global_position.z},
			"rotation_y": player.rotation.y,
			"health": player.get("health") if player.get("health") != null else 100,
			"energy": player.get("energy") if player.get("energy") != null else 100,
		}

	# Inventory
	data["inventory"] = {
		"gold": InventorySystem.gold,
		"items": InventorySystem.get_all_items(),
		"equipped": {
			"weapon": InventorySystem.get_equipped_item("weapon"),
			"armor": InventorySystem.get_equipped_item("armor"),
			"accessory": InventorySystem.get_equipped_item("accessory"),
		},
	}

	# Quests
	data["quests"] = {
		"active": QuestSystem.get_active_quests(),
		"completed": QuestSystem.get_completed_quests() if QuestSystem.has_method("get_completed_quests") else [],
	}

	# Survival
	var survival: Node = get_node_or_null("/root/SurvivalSystem")
	if survival and survival.has_method("get_all_needs"):
		var needs: Array = survival.get_all_needs()
		data["survival"] = {}
		for need in needs:
			data["survival"][need.get("id", "")] = need.get("value", 100)

	return data

# ─────────────────────────────────────────────
# Data application
# ─────────────────────────────────────────────

func _apply_save_data(data: Dictionary) -> void:
	# Time
	var time_data: Dictionary = data.get("time", {})
	GameClock.day = time_data.get("day", 1)
	GameClock.current_hour = time_data.get("hour", 6.0)

	# Player
	var player: Node3D = _find_player()
	var player_data: Dictionary = data.get("player", {})
	if player and not player_data.is_empty():
		var pos: Dictionary = player_data.get("position", {})
		player.global_position = Vector3(pos.get("x", 0), pos.get("y", 0), pos.get("z", 0))
		player.rotation.y = player_data.get("rotation_y", 0)
		if player.get("health") != null:
			player.health = player_data.get("health", 100)
		if player.get("energy") != null:
			player.energy = player_data.get("energy", 100)

	# Inventory
	var inv_data: Dictionary = data.get("inventory", {})
	InventorySystem.set_gold(inv_data.get("gold", 0))
	# Clear and reload items
	var items: Array = inv_data.get("items", [])
	for item in items:
		InventorySystem.add_item(item)

	# Quests — restore active quest states
	var quest_data: Dictionary = data.get("quests", {})
	var active_quests: Array = quest_data.get("active", [])
	for quest in active_quests:
		var qid: String = quest.get("id", "")
		if qid != "" and QuestSystem.has_method("accept_quest"):
			QuestSystem.accept_quest(qid)

	# Survival
	var survival: Node = get_node_or_null("/root/SurvivalSystem")
	var survival_data: Dictionary = data.get("survival", {})
	if survival and survival.has_method("modify_need"):
		for need_id in survival_data:
			survival.modify_need(need_id, survival_data[need_id])

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

func _slot_path(slot: int) -> String:
	return SAVE_DIR + "save_slot_%d.json" % slot

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0] as Node3D
	return null
