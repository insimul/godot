extends Node
## Static data loader — autoloaded singleton.
## Loads JSON data from res://data/.
## Mirrors the FileDataSource from the Babylon.js DataSource.ts.

const DATA_PATH := "res://data/"

## Cached world IR data (loaded lazily).
var _world_ir: Dictionary = {}
var _world_ir_loaded: bool = false

## Cached geography data (extracted from world_ir or geography.json).
var _geography: Dictionary = {}

# ── Core loaders (match DataSource interface) ──────────────────

func load_world() -> Dictionary:
	_ensure_world_ir()
	var meta: Dictionary = _world_ir.get("meta", {})
	if not meta.has("name") and meta.has("worldName"):
		meta["name"] = meta["worldName"]
	return meta

func load_world_data() -> Dictionary:
	return _load_json("world_ir.json")

func load_characters() -> Array:
	return _load_json_array("characters.json")

func load_npcs() -> Array:
	return _load_json_array("npcs.json")

func load_actions() -> Array:
	return _load_json_array("actions.json")

func load_base_actions() -> Array:
	_ensure_world_ir()
	var systems: Dictionary = _world_ir.get("systems", {})
	return systems.get("actions", [])

func load_rules() -> Array:
	return _load_json_array("rules.json")

func load_base_rules() -> Array:
	_ensure_world_ir()
	var systems: Dictionary = _world_ir.get("systems", {})
	return systems.get("rules", [])

## Load base quests. Per-playthrough state (status, progress) should be
## overlaid at runtime from save game state (see save_game_state/load_game_state).
func load_quests() -> Array:
	return _load_json_array("quests.json")

func load_settlements() -> Array:
	_ensure_geography()
	var settlements: Array = _geography.get("settlements", [])
	if settlements.size() == 0:
		settlements = _load_json_array("settlements.json")
	# Map IR streetNetwork to the 'streets' format the game expects.
	# Re-center waypoints from IR world-space to lot coordinate space.
	for s in settlements:
		if s.has("streetNetwork") and not s.has("streets"):
			var sn: Dictionary = s["streetNetwork"]
			# Compute lot centroid (DB map-space)
			var lots: Array = s.get("lots", [])
			var lot_cx := 0.0
			var lot_cz := 0.0
			var lot_count := 0
			for l in lots:
				var lx = l.get("positionX", l.get("position", {}).get("x", null))
				var lz = l.get("positionZ", l.get("position", {}).get("z", null))
				if lx != null:
					lot_cx += float(lx)
					lot_cz += float(lz) if lz != null else 0.0
					lot_count += 1
			if lot_count > 0:
				lot_cx /= lot_count
				lot_cz /= lot_count
			# Compute street waypoint centroid (IR world-space)
			var wp_cx := 0.0
			var wp_cz := 0.0
			var wp_count := 0
			for seg in sn.get("segments", []):
				for wp in seg.get("waypoints", []):
					if wp.has("x") and wp.has("z"):
						wp_cx += float(wp["x"])
						wp_cz += float(wp["z"])
						wp_count += 1
			if wp_count > 0:
				wp_cx /= wp_count
				wp_cz /= wp_count
			# Offset to re-center
			var dx := lot_cx - wp_cx
			var dz := lot_cz - wp_cz
			var streets: Array = []
			for seg in sn.get("segments", []):
				var mapped_wps: Array = []
				for wp in seg.get("waypoints", []):
					mapped_wps.append({
						"x": float(wp.get("x", 0)) + dx,
						"y": float(wp.get("y", 0)),
						"z": float(wp.get("z", 0)) + dz,
					})
				streets.append({
					"id": seg.get("id", ""),
					"name": seg.get("name", ""),
					"waypoints": mapped_wps,
					"width": seg.get("width", 6),
					"properties": {
						"waypoints": mapped_wps,
						"width": seg.get("width", 6),
					},
				})
			s["streets"] = streets
	return settlements

func load_buildings() -> Array:
	return _load_json_array("buildings.json")

func load_asset_manifest() -> Dictionary:
	return _load_json("asset-manifest.json")

func load_countries() -> Array:
	_ensure_geography()
	return _geography.get("countries", [])

func load_states() -> Array:
	_ensure_geography()
	return _geography.get("states", [])

func load_base_resources() -> Dictionary:
	_ensure_world_ir()
	var systems: Dictionary = _world_ir.get("systems", {})
	return systems.get("resources", {})

func load_assets() -> Array:
	var manifest: Dictionary = load_asset_manifest()
	var assets_arr: Array = manifest.get("assets", [])

	# Add virtual asset entries for MongoDB asset IDs found in the IR's assetIdToPath map.
	# This allows world3DConfig texture IDs (which are MongoDB ObjectIDs) to match
	# assets in the worldAssets list.
	_ensure_world_ir()
	var meta: Dictionary = _world_ir.get("meta", {})
	var id_map: Dictionary = meta.get("assetIdToPath", {})
	if id_map.size() > 0:
		var existing_ids := {}
		for a in assets_arr:
			existing_ids[str(a.get("id", ""))] = true
		for mongo_id in id_map:
			if existing_ids.has(mongo_id):
				continue
			var file_path: String = str(id_map[mongo_id])
			var ext: String = file_path.get_extension().to_lower()
			var is_texture: bool = ext in ["png", "jpg", "jpeg"]
			var asset_type: String = _infer_asset_type(file_path, is_texture)
			var mime: String
			if is_texture:
				mime = "image/jpeg" if ext == "jpg" else ("image/%s" % ext)
			else:
				mime = "model/gltf-binary"
			assets_arr.append({
				"id": mongo_id,
				"name": mongo_id,
				"assetType": asset_type,
				"filePath": file_path if file_path.begins_with(".") else ("./" + file_path),
				"fileName": file_path.get_file(),
				"fileSize": 0,
				"mimeType": mime,
			})
	return assets_arr

## Resolve full asset metadata by ID. Checks the assetIdToPath map first,
## then falls back to the loaded asset manifest.
## Returns an empty Dictionary if not found.
## Mirrors DataSource.resolveAssetById() in the Babylon.js client.
func resolve_asset_by_id(asset_id: String) -> Dictionary:
	_ensure_world_ir()
	var meta: Dictionary = _world_ir.get("meta", {})
	var id_map: Dictionary = meta.get("assetIdToPath", {})
	if id_map.has(asset_id):
		var file_path: String = str(id_map[asset_id])
		var ext: String = file_path.get_extension().to_lower()
		var is_texture: bool = ext in ["png", "jpg", "jpeg"]
		var asset_type: String = _infer_asset_type(file_path, is_texture)
		var mime: String
		if is_texture:
			mime = "image/jpeg" if ext == "jpg" else ("image/%s" % ext)
		else:
			mime = "model/gltf-binary"
		return {
			"id": asset_id,
			"name": asset_id,
			"assetType": asset_type,
			"filePath": file_path if file_path.begins_with(".") else ("./" + file_path),
			"fileName": file_path.get_file(),
			"fileSize": 0,
			"mimeType": mime,
		}
	# Fall back to loaded assets
	var assets: Array = load_assets()
	for a in assets:
		if str(a.get("id", "")) == asset_id:
			return a
	return {}


## Return a loadable file path for an asset without loading full metadata.
## Returns empty string if the asset ID is not in the assetIdToPath map.
## Mirrors DataSource.resolveAssetUrl() in the Babylon.js client.
func resolve_asset_url(asset_id: String) -> String:
	_ensure_world_ir()
	var meta: Dictionary = _world_ir.get("meta", {})
	var id_map: Dictionary = meta.get("assetIdToPath", {})
	if id_map.has(asset_id):
		var p: String = str(id_map[asset_id])
		return p if p.begins_with(".") else ("./" + p)
	return ""


func load_config_3d() -> Dictionary:
	var config: Dictionary = _load_json("3d_config.json")

	# Merge world3DConfig from IR — this has the full asset collection settings
	# including procedural building presets, texture IDs, and type overrides.
	# Texture IDs are MongoDB ObjectIDs which the asset ID-to-path map resolves.
	_ensure_world_ir()
	var meta: Dictionary = _world_ir.get("meta", {})
	var ir_config: Dictionary = meta.get("world3DConfig", {})
	if ir_config.size() > 0:
		# Procedural building config (style presets with colors, textures, architecture)
		if ir_config.has("proceduralBuildings"):
			config["proceduralBuildings"] = ir_config["proceduralBuildings"]
		# Per-building-type overrides (e.g., Restaurant -> colonial_warm preset)
		if ir_config.has("buildingTypeOverrides"):
			config["buildingTypeOverrides"] = ir_config["buildingTypeOverrides"]
		# Global texture IDs (fall back to manifest-derived if not present)
		if ir_config.has("wallTextureId"):
			config["wallTextureId"] = ir_config["wallTextureId"]
		if ir_config.has("roofTextureId"):
			config["roofTextureId"] = ir_config["roofTextureId"]
		# Model scaling overrides
		if ir_config.has("modelScaling"):
			config["modelScaling"] = ir_config["modelScaling"]
		# Audio assets config
		if ir_config.has("audioAssets"):
			config["audioAssets"] = ir_config["audioAssets"]
	return config

# ── Array loaders ───────────────────────────────────────────────

func load_items() -> Array:
	return _load_json_array("items.json")

## Alias matching DataSource.loadWorldItems().
func load_world_items() -> Array:
	return load_items()

func load_texts() -> Array:
	return _load_json_array("texts.json")

func load_loot_tables() -> Array:
	return _load_json_array("loot_tables.json")

## Mirrors Container from types.ts.
func load_containers() -> Array:
	return _load_json_array("containers.json")

func load_truths() -> Array:
	_ensure_world_ir()
	var truths: Array = _world_ir.get("truths", [])
	if truths.size() > 0:
		return truths
	return _load_json_array("truths.json")

func load_grammars() -> Array:
	return _load_json_array("grammars.json")

func load_businesses() -> Array:
	return _load_json_array("businesses.json")

func load_roads() -> Array:
	return _load_json_array("roads.json")

func load_water_features() -> Array:
	return _load_json_array("water_features.json")

func load_lots() -> Array:
	return _load_json_array("lots.json")

func load_dialogue_contexts() -> Array:
	return _load_json_array("dialogue_contexts.json")

func load_resources() -> Array:
	return _load_json_array("resources.json")

func load_foliage_layers() -> Array:
	return _load_json_array("foliage_layers.json")

func load_biome_zones() -> Array:
	return _load_json_array("biome_zones.json")

# ── Single-entity loaders ──────────────────────────────────────

## Load a single character by id. Scans characters.json.
func load_character(character_id: String) -> Dictionary:
	var chars: Array = load_characters()
	for ch in chars:
		if str(ch.get("id", "")) == character_id:
			return ch
	return {}

# ── Settlement sub-data ────────────────────────────────────────

## Load businesses for a specific settlement.
## Falls back to deriving from buildings data if settlement has no businesses.
func load_settlement_businesses(settlement_id: String) -> Array:
	_ensure_geography()
	var settlements: Array = _geography.get("settlements", [])
	for s in settlements:
		if str(s.get("id", "")) == settlement_id:
			var businesses: Array = s.get("businesses", [])
			if businesses.size() > 0:
				return businesses
	# Fall back to deriving from buildings data
	var all_buildings: Array = load_buildings()
	var all_businesses: Array = load_businesses()
	var result: Array = []
	for b in all_buildings:
		if str(b.get("settlementId", "")) == settlement_id and b.get("businessId", "") != "":
			var spec: Dictionary = b.get("spec", {})
			var occupants: Array = b.get("occupantIds", [])
			var has_occupants: bool = occupants.size() > 0
			# Fallback: look up BusinessIR.ownerId when occupantIds is empty
			var biz_ir = null
			var biz_id_str: String = str(b.get("businessId", ""))
			for biz in all_businesses:
				if str(biz.get("id", "")) == biz_id_str:
					biz_ir = biz
					break
			var owner_id = occupants[0] if has_occupants else (biz_ir.get("ownerId", null) if biz_ir != null else null)
			var employees: Array = occupants.slice(1) if occupants.size() > 1 else []
			var biz_type: String = spec.get("buildingRole", "Shop")
			var biz_name: String = spec.get("buildingRole", "Business")
			if biz_ir != null:
				biz_type = biz_ir.get("businessType", biz_type)
				biz_name = biz_ir.get("name", biz_name)
			result.append({
				"id": b.get("businessId", b.get("id", "")),
				"settlementId": b.get("settlementId", ""),
				"businessType": biz_type,
				"name": biz_name,
				"ownerId": owner_id,
				"employees": employees,
				"lotId": b.get("lotId", ""),
				"position": b.get("position", {}),
			})
	return result

## Load lots for a specific settlement.
func load_settlement_lots(settlement_id: String) -> Array:
	_ensure_geography()
	var settlements: Array = _geography.get("settlements", [])
	for s in settlements:
		if str(s.get("id", "")) == settlement_id:
			return s.get("lots", [])
	return []

## Load residences for a specific settlement.
## Falls back to deriving from buildings data if settlement has no residences.
func load_settlement_residences(settlement_id: String) -> Array:
	_ensure_geography()
	var settlements: Array = _geography.get("settlements", [])
	for s in settlements:
		if str(s.get("id", "")) == settlement_id:
			var residences: Array = s.get("residences", [])
			if residences.size() > 0:
				return residences
	# Fall back to deriving from buildings data
	var all_buildings: Array = load_buildings()
	var result: Array = []
	for b in all_buildings:
		if str(b.get("settlementId", "")) == settlement_id and b.get("residenceId", "") != "":
			var spec: Dictionary = b.get("spec", {})
			result.append({
				"id": b.get("residenceId", b.get("id", "")),
				"settlementId": b.get("settlementId", ""),
				"residenceType": spec.get("buildingRole", "House"),
				"name": spec.get("buildingRole", "Residence"),
				"occupantIds": b.get("occupantIds", []),
				"lotId": b.get("lotId", ""),
				"position": b.get("position", {}),
			})
	return result

# ── Local state management ────────────────────────────────────
# Inventories, quest progress, merchant stock, and fines are tracked
# in-memory and persisted via save_game_state/load_game_state.
# This mirrors the LocalGameState class from DataSource.ts.
#
# TODO: Implement full local state tracking with dictionaries for
# _inventories, _quest_updates, _merchant_caches, _fines_paid.

var _inventories: Dictionary = {}
var _quest_updates: Dictionary = {}
var _merchant_caches: Dictionary = {}
var _fines_paid: Dictionary = {}
var _playthrough_id: String = ""

## Get inventory for an entity from local state.
func get_entity_inventory(entity_id: String) -> Dictionary:
	if _inventories.has(entity_id):
		var inv: Dictionary = _inventories[entity_id]
		return {"entityId": entity_id, "items": inv.get("items", []), "gold": inv.get("gold", 0)}
	return {"entityId": entity_id, "items": [], "gold": 0}

## Get player inventory. Delegates to get_entity_inventory.
## world_id is accepted for interface compatibility but unused in exported mode.
func get_player_inventory(_world_id: String, player_id: String) -> Dictionary:
	return get_entity_inventory(player_id)

## Get container contents by container ID from containers.json.
func get_container_contents(container_id: String) -> Dictionary:
	var containers: Array = load_containers()
	for c in containers:
		if str(c.get("id", "")) == container_id:
			return c
	return {}

## Transfer an item between entities. Updates local inventory state.
## Supports buy/sell/steal/give/discard/quest_reward transaction types.
func transfer_item(transfer: Dictionary) -> Dictionary:
	var qty: int = transfer.get("quantity", 1)
	var price: int = transfer.get("total_price", 0)
	var from_id: String = transfer.get("from_entity_id", "")
	var to_id: String = transfer.get("to_entity_id", "")

	# Remove from source
	if not from_id.is_empty() and _inventories.has(from_id):
		var from_inv: Dictionary = _inventories[from_id]
		var items: Array = from_inv.get("items", [])
		for i in range(items.size()):
			if str(items[i].get("id", "")) == transfer.get("item_id", ""):
				var cur_qty: int = items[i].get("quantity", 1)
				if cur_qty <= qty:
					items.remove_at(i)
				else:
					items[i]["quantity"] = cur_qty - qty
				break
		if transfer.get("transaction_type", "") == "sell" and price > 0:
			from_inv["gold"] = from_inv.get("gold", 0) + price

	# Add to destination
	if not to_id.is_empty():
		if not _inventories.has(to_id):
			_inventories[to_id] = {"items": [], "gold": 0}
		var to_inv: Dictionary = _inventories[to_id]
		var to_items: Array = to_inv.get("items", [])
		var found := false
		for item in to_items:
			if str(item.get("id", "")) == transfer.get("item_id", ""):
				item["quantity"] = item.get("quantity", 1) + qty
				found = true
				break
		if not found:
			to_items.append({
				"id": transfer.get("item_id", ""),
				"name": transfer.get("item_name", ""),
				"type": transfer.get("item_type", "misc"),
				"quantity": qty,
			})
		if transfer.get("transaction_type", "") == "buy" and price > 0:
			to_inv["gold"] = to_inv.get("gold", 0) - price

	var result := transfer.duplicate()
	result["success"] = true
	result["timestamp"] = Time.get_unix_time_from_system()
	return result

## Get merchant inventory. Generates stock based on NPC occupation if not cached.
func get_merchant_inventory(merchant_id: String) -> Dictionary:
	if _merchant_caches.has(merchant_id):
		return _merchant_caches[merchant_id]
	# TODO: Look up NPC from characters/npcs, check occupation, generate stock
	return {}

## Update quest progress locally. Merged into quest data on load_quests.
func update_quest(quest_id: String, update_data: Dictionary) -> void:
	if not _quest_updates.has(quest_id):
		_quest_updates[quest_id] = {}
	_quest_updates[quest_id].merge(update_data, true)

## Mark a quest as completed locally.
func complete_quest(quest_id: String) -> Dictionary:
	var now_iso := Time.get_datetime_string_from_system(true)
	update_quest(quest_id, {"status": "completed", "completedAt": now_iso})
	print("[Insimul] complete_quest(%s)" % quest_id)
	return {"success": true, "questId": quest_id}

## Get quest guidance context for an NPC. Scans active quests for objectives
## targeting this NPC and returns a system prompt addition.
func get_npc_quest_guidance(npc_id: String) -> Dictionary:
	var quests: Array = load_quests()
	var hints: Array = []
	for q in quests:
		var status: String = q.get("status", "")
		if _quest_updates.has(str(q.get("id", ""))):
			status = _quest_updates[str(q.get("id", ""))].get("status", status)
		if status != "active" and status != "in_progress":
			continue
		var objectives: Array = q.get("objectives", [])
		for obj in objectives:
			if str(obj.get("targetNpcId", "")) == npc_id or str(obj.get("npcId", "")) == npc_id:
				var desc: String = obj.get("description", obj.get("title", "Talk to this NPC"))
				hints.append("Quest \"%s\": %s" % [q.get("title", ""), desc])
	if hints.size() == 0:
		return {"hasGuidance": false}
	return {
		"hasGuidance": true,
		"systemPromptAddition": "The player has active quest objectives involving you:\n" + "\n".join(hints),
	}

## Get main quest journal data built from local main quest data.
func get_main_quest_journal(player_id: String, cefr_level: String = "") -> Dictionary:
	var quests: Array = load_quests()
	var chapters: Array = []
	for q in quests:
		if q.get("questType", "") != "main_quest":
			continue
		var q_id: String = str(q.get("id", ""))
		var status: String = q.get("status", "locked")
		if _quest_updates.has(q_id):
			status = _quest_updates[q_id].get("status", status)
		chapters.append({
			"id": q_id,
			"title": q.get("title", ""),
			"description": q.get("description", ""),
			"order": q.get("questChainOrder", 0),
			"status": status,
			"objectives": q.get("objectives", []),
		})
	var current_id = chapters[0].get("id") if chapters.size() > 0 else null
	return {
		"state": {"currentChapterId": current_id, "totalXPEarned": 0, "caseNotes": []},
		"chapters": chapters,
		"playerCefrLevel": cefr_level if not cefr_level.is_empty() else null,
		"investigationBoard": null,
	}

## Try to unlock the next CEFR-gated main quest chapter.
func try_unlock_main_quest(player_id: String, cefr_level: String) -> void:
	var quests: Array = load_quests()
	var main_quests: Array = []
	for q in quests:
		if q.get("questType", "") == "main_quest":
			main_quests.append(q)
	main_quests.sort_custom(func(a, b): return a.get("questChainOrder", 0) < b.get("questChainOrder", 0))
	for q in main_quests:
		var q_id: String = str(q.get("id", ""))
		var status: String = q.get("status", "locked")
		if _quest_updates.has(q_id):
			status = _quest_updates[q_id].get("status", status)
		if status == "locked" and q.has("cefrRequirement"):
			if cefr_level >= str(q.get("cefrRequirement", "")):
				update_quest(q_id, {"status": "active"})
				print("[Insimul] try_unlock_main_quest: unlocked %s" % q_id)
				break

## Record a main quest completion. In exported mode, just acknowledges the completion.
func record_main_quest_completion(player_id: String, quest_type: String, _cefr_level: String = "") -> Dictionary:
	print("[Insimul] record_main_quest_completion(%s, %s)" % [player_id, quest_type])
	return {"result": {"questType": quest_type, "recorded": true}}

## Pay fines for a settlement. Clears accumulated fines.
func pay_fines(settlement_id: String) -> Dictionary:
	var amount: int = _fines_paid.get(settlement_id, 0)
	_fines_paid[settlement_id] = 0
	return {"success": true, "finesPaid": amount}

## List existing playthroughs from the persistent index file.
func list_playthroughs() -> Array:
	return _load_playthroughs_index()

## Start a new playthrough with a unique local ID.
## Generates an ID like "local-1679500000-a3f2b1", persists to index, and sets _playthrough_id.
func start_playthrough(playthrough_name: String) -> Dictionary:
	var timestamp := int(Time.get_unix_time_from_system())
	var random_hex := "%06x" % (randi() & 0xFFFFFF)
	var new_id := "local-%d-%s" % [timestamp, random_hex]
	_playthrough_id = new_id

	var now_iso := Time.get_datetime_string_from_system(true)
	var entry := {
		"id": new_id,
		"name": playthrough_name,
		"status": "active",
		"createdAt": now_iso,
		"lastPlayedAt": now_iso,
		"playtime": 0,
	}

	var index := _load_playthroughs_index()
	index.append(entry)
	_save_playthroughs_index(index)

	print("[Insimul] start_playthrough: created %s (%s)" % [new_id, playthrough_name])
	return entry

## Look up a specific playthrough by ID from the index.
func get_playthrough(playthrough_id: String) -> Dictionary:
	var index := _load_playthroughs_index()
	for entry in index:
		if str(entry.get("id", "")) == playthrough_id:
			return entry
	return {}

## Update playthrough metadata. Merges provided fields into the existing entry.
## Returns true on success.
func update_playthrough(playthrough_id: String, updates: Dictionary) -> bool:
	var index := _load_playthroughs_index()
	var found := false
	for entry in index:
		if str(entry.get("id", "")) == playthrough_id:
			for key in updates:
				entry[key] = updates[key]
			entry["lastPlayedAt"] = Time.get_datetime_string_from_system(true)
			found = true
			break
	if not found:
		return false
	_save_playthroughs_index(index)
	return true

## Delete a playthrough and all associated save data.
## Returns true on success.
func delete_playthrough(playthrough_id: String) -> bool:
	# Remove save slot files
	for i in range(10):
		var save_path := "user://insimul_save_%s_%d.json" % [playthrough_id, i]
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
	# Remove quest progress
	var quest_path := "user://insimul_quest_progress_%s.json" % playthrough_id
	if FileAccess.file_exists(quest_path):
		DirAccess.remove_absolute(quest_path)
	# Remove from index
	var index := _load_playthroughs_index()
	var filtered := []
	for entry in index:
		if str(entry.get("id", "")) != playthrough_id:
			filtered.append(entry)
	_save_playthroughs_index(filtered)
	print("[Insimul] delete_playthrough: removed %s" % playthrough_id)
	return true

# ── Single-object loaders ──────────────────────────────────────

func load_theme() -> Dictionary:
	return _load_json("theme.json")

func load_player_config() -> Dictionary:
	return _load_json("player.json")

func load_combat_config() -> Dictionary:
	return _load_json("combat.json")

func load_ui_config() -> Dictionary:
	return _load_json("ui.json")

func load_ai_config() -> Dictionary:
	return _load_json("ai_config.json")

func load_survival_config() -> Dictionary:
	return _load_json("survival.json")

# ── Text file loaders ──────────────────────────────────────────

## Load the Prolog knowledge base as a raw string. Returns "" if not found.
## Checks knowledge-base.pl first, then falls back to knowledge_base.pl.
func load_prolog_knowledge_base() -> String:
	var content: String = _load_text("knowledge-base.pl")
	if content.is_empty():
		content = _load_text("knowledge_base.pl")
	return content

## Alias matching DataSource.loadPrologContent().
func load_prolog_content() -> String:
	return load_prolog_knowledge_base()

## Load geography data (heightmap, terrain features). Returns empty dict if not found.
func load_geography() -> Dictionary:
	return _load_json("geography.json")

# ── Save / Load ───────────────────────────────────────────────

## Save game state dictionary to a numbered slot (0-2), scoped per playthrough.
## Writes to user://insimul_save_<playthrough_id>_<slot_index>.json.
## Also updates the lastPlayedAt timestamp in the playthroughs index.
func save_game_state(slot_index: int, game_state: Dictionary, playthrough_id: String = "") -> bool:
	if slot_index < 0 or slot_index > 2:
		push_warning("[Insimul] save_game_state: invalid slot %d (must be 0-2)" % slot_index)
		return false
	var pt_id := playthrough_id if not playthrough_id.is_empty() else _playthrough_id
	if pt_id.is_empty():
		push_warning("[Insimul] save_game_state: no playthrough_id set")
		return false
	var save_path := "user://insimul_save_%s_%d.json" % [pt_id, slot_index]
	var json := JSON.stringify(game_state)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("[Insimul] save_game_state: could not open %s for writing" % save_path)
		return false
	file.store_string(json)
	_update_last_played(pt_id)
	print("[Insimul] save_game_state: saved to slot %d (playthrough %s)" % [slot_index, pt_id])
	return true

## Load game state dictionary from a numbered slot (0-2), scoped per playthrough.
## Returns empty dictionary if no save exists.
func load_game_state(slot_index: int, playthrough_id: String = "") -> Dictionary:
	if slot_index < 0 or slot_index > 2:
		push_warning("[Insimul] load_game_state: invalid slot %d (must be 0-2)" % slot_index)
		return {}
	var pt_id := playthrough_id if not playthrough_id.is_empty() else _playthrough_id
	if pt_id.is_empty():
		push_warning("[Insimul] load_game_state: no playthrough_id set")
		return {}
	var save_path := "user://insimul_save_%s_%d.json" % [pt_id, slot_index]
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("[Insimul] load_game_state: JSON parse error in slot %d" % slot_index)
		return {}
	print("[Insimul] load_game_state: loaded slot %d (playthrough %s)" % [slot_index, pt_id])
	return json.data if json.data is Dictionary else {}

## Delete game state from a numbered slot (0-2), scoped per playthrough.
## Returns true if the file was deleted or did not exist.
func delete_game_state(slot_index: int, playthrough_id: String = "") -> bool:
	if slot_index < 0 or slot_index > 2:
		push_warning("[Insimul] delete_game_state: invalid slot %d (must be 0-2)" % slot_index)
		return false
	var pt_id := playthrough_id if not playthrough_id.is_empty() else _playthrough_id
	if pt_id.is_empty():
		push_warning("[Insimul] delete_game_state: no playthrough_id set")
		return false
	var save_path := "user://insimul_save_%s_%d.json" % [pt_id, slot_index]
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	print("[Insimul] delete_game_state: deleted slot %d (playthrough %s)" % [slot_index, pt_id])
	return true

## Save quest progress dictionary to a dedicated file, scoped per playthrough.
## Returns true on success.
func save_quest_progress(quest_progress: Dictionary, playthrough_id: String = "") -> bool:
	var pt_id := playthrough_id if not playthrough_id.is_empty() else _playthrough_id
	if pt_id.is_empty():
		push_warning("[Insimul] save_quest_progress: no playthrough_id set")
		return false
	var save_path := "user://insimul_quest_progress_%s.json" % pt_id
	var json := JSON.stringify(quest_progress)
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_error("[Insimul] save_quest_progress: could not open %s for writing" % save_path)
		return false
	file.store_string(json)
	print("[Insimul] save_quest_progress: saved (playthrough %s)" % pt_id)
	return true

## Load quest progress dictionary from the dedicated file, scoped per playthrough.
## Returns empty dictionary if no quest progress has been saved.
func load_quest_progress(playthrough_id: String = "") -> Dictionary:
	var pt_id := playthrough_id if not playthrough_id.is_empty() else _playthrough_id
	if pt_id.is_empty():
		push_warning("[Insimul] load_quest_progress: no playthrough_id set")
		return {}
	var save_path := "user://insimul_quest_progress_%s.json" % pt_id
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("[Insimul] load_quest_progress: JSON parse error")
		return {}
	print("[Insimul] load_quest_progress: loaded (playthrough %s)" % pt_id)
	return json.data if json.data is Dictionary else {}

# ── Playthrough relationships ─────────────────────────────────

## Load playthrough relationship overlays (empty in exported mode).
func load_playthrough_relationships() -> Array:
	return []  # No server in exported mode

## Update a playthrough relationship (no-op in exported mode).
func update_playthrough_relationship(_from_id: String, _to_id: String, _type: String, _strength: float) -> bool:
	return false  # No server in exported mode

## Get all reputations for the current playthrough (empty in exported mode).
func get_reputations() -> Array:
	return []  # No server in exported mode

# ── Language progress ─────────────────────────────────────────

## Load persisted language progress for a player (empty in exported mode).
func load_language_progress(_player_id: String, _world_id: String) -> Variant:
	return null  # No server in exported mode

## Save language progress data (no-op in exported mode).
func save_language_progress(_data: Dictionary) -> void:
	pass  # No server in exported mode

## Get a language profile summary for a player (empty in exported mode).
func get_language_profile(_world_id: String, _player_id: String) -> Variant:
	return null  # No server in exported mode

## Get all languages defined in the world.
func get_languages() -> Array:
	_ensure_world_ir()
	if _world_ir.has("languages") and _world_ir["languages"] is Array:
		return _world_ir["languages"]
	return []

# ── NPC Conversation & Assessments ────────────────────────────

## Start an NPC-NPC conversation (returns empty — no AI server in exported mode).
func start_npc_npc_conversation(_npc1_id: String, _npc2_id: String, _topic: String = "") -> Dictionary:
	return {}  # No AI server in exported mode

## Create an assessment session (stub in exported mode).
func create_assessment_session(_player_id: String, _world_id: String, _assessment_type: String) -> Dictionary:
	return {}

## Submit results for an assessment phase (stub in exported mode).
func submit_assessment_phase(_session_id: String, _phase_id: String, _data: Dictionary = {}) -> Dictionary:
	return {}

## Complete an assessment session (stub in exported mode).
func complete_assessment(_session_id: String, _total_score: float, _max_score: float = 0.0, _cefr_level: String = "") -> Dictionary:
	return {}

## Get player's assessment history for a world (returns empty in exported mode).
func get_player_assessments(_player_id: String, _world_id: String) -> Array:
	return []

## Check if conversation streaming service is available (always false in exported mode).
func check_conversation_health() -> bool:
	return false  # No conversation service in exported mode

## Simulate a rich conversation between two characters (no-op in exported mode).
func simulate_rich_conversation(world_id: String, char1_id: String, char2_id: String, turn_count: int) -> Variant:
	return null  # No AI server in exported mode

## Text-to-speech synthesis (no-op in exported mode).
func text_to_speech(text: String, voice: String, gender: String, target_language: String) -> Variant:
	return null  # No TTS service in exported mode

## Get player portfolio data (no-op in exported mode).
func get_portfolio(world_id: String, player_name: String) -> Variant:
	return null  # No server in exported mode

## Load reading progress (no-op in exported mode).
func load_reading_progress(player_id: String, world_id: String, playthrough_id: String = "") -> Variant:
	return null  # No server in exported mode

## Sync reading progress (no-op in exported mode).
func sync_reading_progress(data: Dictionary) -> void:
	pass  # No-op in exported mode

# ── Quest management ──────────────────────────────────────────

## Create a dynamic quest at runtime.
func create_dynamic_quest(_world_id: String, quest_data: Dictionary) -> Dictionary:
	var quest_id = "dynamic_%d" % Time.get_unix_time_from_system()
	var quest_dir = OS.get_user_data_dir() + "/quests"
	DirAccess.make_dir_recursive_absolute(quest_dir)
	var file = FileAccess.open(quest_dir + "/" + quest_id + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(quest_data))
		file.close()
	print("[Insimul] Created dynamic quest: ", quest_id)
	return {"id": quest_id, "status": "active"}

## Branch a quest based on player choice.
func branch_quest(_world_id: String, quest_id: String, choice_id: String, _target_stage_id: String = "") -> Dictionary:
	print("[Insimul] BranchQuest: %s, choice: %s" % [quest_id, choice_id])
	return {"success": true}

## Adjust reputation for an entity.
func adjust_reputation(_playthrough_id: String, entity_type: String, entity_id: String, amount: int, reason: String) -> Dictionary:
	print("[Insimul] AdjustReputation: %s/%s by %d (%s)" % [entity_type, entity_id, amount, reason])
	return {"success": true}

# ── Playthroughs index helpers ─────────────────────────────────

const PLAYTHROUGHS_INDEX_PATH := "user://insimul_playthroughs.json"

## Load the playthroughs index from disk. Returns an Array of playthrough entries.
func _load_playthroughs_index() -> Array:
	if not FileAccess.file_exists(PLAYTHROUGHS_INDEX_PATH):
		return []
	var file := FileAccess.open(PLAYTHROUGHS_INDEX_PATH, FileAccess.READ)
	if file == null:
		return []
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("[Insimul] _load_playthroughs_index: JSON parse error")
		return []
	return json.data if json.data is Array else []

## Save the playthroughs index array to disk.
func _save_playthroughs_index(index: Array) -> void:
	var json := JSON.stringify(index)
	var file := FileAccess.open(PLAYTHROUGHS_INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[Insimul] _save_playthroughs_index: could not open %s for writing" % PLAYTHROUGHS_INDEX_PATH)
		return
	file.store_string(json)

## Update the lastPlayedAt timestamp for a playthrough in the index.
func _update_last_played(pt_id: String) -> void:
	var index := _load_playthroughs_index()
	var now_iso := Time.get_datetime_string_from_system(true)
	for entry in index:
		if str(entry.get("id", "")) == pt_id:
			entry["lastPlayedAt"] = now_iso
			break
	_save_playthroughs_index(index)

# ── Internal caching ──────────────────────────────────────────

func _ensure_world_ir() -> void:
	if _world_ir_loaded:
		return
	_world_ir = _load_json("world_ir.json")
	_world_ir_loaded = true

func _ensure_geography() -> void:
	_ensure_world_ir()
	if _geography.is_empty():
		# Try world_ir geography first, then standalone geography.json
		if _world_ir.has("geography"):
			_geography = _world_ir["geography"]
		else:
			_geography = _load_json("geography.json")

## Infer asset type from file path — mirrors DataSource.ts logic.
func _infer_asset_type(file_path: String, is_texture: bool) -> String:
	if not is_texture:
		return "model"
	var lp := file_path.to_lower()
	if "wall" in lp or "plaster" in lp or "brick" in lp or "planks" in lp:
		return "texture_wall"
	if "roof" in lp or "tiles" in lp or "slates" in lp or "corrugated" in lp:
		return "texture_material"
	if "ground" in lp or "floor" in lp or "cobblestone" in lp or "forrest" in lp:
		return "texture_ground"
	return "texture"

# ── Internal helpers ───────────────────────────────────────────

func _load_json(filename: String) -> Dictionary:
	var path := DATA_PATH + filename
	if not FileAccess.file_exists(path):
		push_warning("[Insimul] File not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("[Insimul] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}

func _load_json_array(filename: String) -> Array:
	var path := DATA_PATH + filename
	if not FileAccess.file_exists(path):
		push_warning("[Insimul] File not found: %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("[Insimul] JSON parse error in %s: %s" % [path, json.get_error_message()])
		return []
	return json.data if json.data is Array else []

func _load_text(filename: String) -> String:
	var path := DATA_PATH + filename
	if not FileAccess.file_exists(path):
		push_warning("[Insimul] Text file not found: %s" % path)
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text()
