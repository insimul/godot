class_name InsimulWorldSource
extends RefCounted
## Host-testable world loader for the Godot SDK.
##
## Loads a SaveFile's embedded `worldSnapshot` (or a bare world-snapshot /
## WorldIR document) into the GENERATED DTO classes (addons/insimul/generated),
## gating on the save-format schema version so incompatible saves are rejected
## before any accessor runs. This replaces the ad-hoc `world_export.json` reads
## for the covered world shapes; the conversation-oriented export path
## (InsimulWorldExport) stays untouched — it still serves the existing SDK.
##
## Cross-engine parity: this mirrors the Unreal FInsimulWorldSource
## (packages/unreal/Source/InsimulRuntime/Portable/InsimulWorldSource.*) and the
## Unity leg — same version gate, same golden entity counts against
## packages/core/conformance/saves/v2-typical.json. See MIGRATION.md.

## Oldest save-format version this reader can consume. Older saves must be
## migrated up first (the save-file-migrations chain).
const MIN_SUPPORTED_SAVE_VERSION := 1

## Newest save-format version this reader understands. MUST track
## SAVE_FILE_VERSION in packages/core/src/save-file.ts. A save stamped beyond
## this was produced by a newer build and is rejected.
const MAX_SUPPORTED_SAVE_VERSION := 3

var _loaded := false
var _version := 0
var _snapshot: InsimulSaveFile.WorldSnapshot = null
var _last_error := ""


## Pure schema-version gate — no I/O. Returns a Dictionary mirroring the Unreal
## FVersionGateResult: { compatible: bool, version: int, status: String,
## message: String }. `status` is "current" | "supported" | "incompatible".
static func check_version(version: int) -> Dictionary:
	var result := {
		"compatible": false,
		"version": version,
		"status": "",
		"message": "",
	}
	if version < MIN_SUPPORTED_SAVE_VERSION:
		result.status = "incompatible"
		result.message = "Save version %d is older than the minimum supported version %d." % [version, MIN_SUPPORTED_SAVE_VERSION]
		return result
	if version > MAX_SUPPORTED_SAVE_VERSION:
		result.status = "incompatible"
		result.message = "Save version %d was produced by a newer build (max supported %d). Please update the game." % [version, MAX_SUPPORTED_SAVE_VERSION]
		return result
	result.compatible = true
	result.status = "current" if version == MAX_SUPPORTED_SAVE_VERSION else "supported"
	result.message = "Save version %d is compatible." % version
	return result


## Load from a full SaveFile JSON document. Reads and gates the top-level
## `version`, then parses `worldSnapshot`. Returns false (and sets last_error())
## if the version is incompatible or the document is malformed.
func load_from_save_file_json(json_text: String) -> bool:
	_loaded = false
	_last_error = ""
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "SaveFile root is not a JSON object"
		return false
	var root: Dictionary = parsed

	# Schema-version compatibility gate.
	_version = int(root.get("version", 0))
	var gate := check_version(_version)
	if not gate.compatible:
		_last_error = gate.message
		return false

	if not root.has("worldSnapshot") or typeof(root["worldSnapshot"]) != TYPE_DICTIONARY:
		_last_error = "SaveFile is missing a worldSnapshot object"
		return false
	return _parse_snapshot(root["worldSnapshot"])


## Load from a bare world-snapshot / WorldIR JSON object (the shape of a
## SaveFile.worldSnapshot, or a WorldIR document that nests it under
## `worldSnapshot`). No save-format version gate is applied here; callers that
## have a version stamp should gate separately via check_version().
func load_from_world_snapshot_json(json_text: String) -> bool:
	_loaded = false
	_last_error = ""
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "World snapshot root is not a JSON object"
		return false
	var root: Dictionary = parsed
	var obj: Dictionary = root
	if root.has("worldSnapshot") and typeof(root["worldSnapshot"]) == TYPE_DICTIONARY:
		obj = root["worldSnapshot"]
	return _parse_snapshot(obj)


func _parse_snapshot(obj: Dictionary) -> bool:
	if not obj.has("world") or typeof(obj["world"]) != TYPE_DICTIONARY:
		_last_error = "worldSnapshot is missing a world object"
		return false
	# from_dict surfaces missing-required / unknown-field validation warnings
	# (via push_warning) on malformed fixtures — the covered-shape entry point.
	_snapshot = InsimulSaveFile.WorldSnapshot.from_dict(obj)
	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded


func loaded_version() -> int:
	return _version


func last_error() -> String:
	return _last_error


## The loaded snapshot DTO (InsimulSaveFile.WorldSnapshot), or null if not loaded.
func world() -> InsimulSaveFile.WorldSnapshot:
	return _snapshot


# ── Typed accessors ─────────────────────────────────────────────────────────

func country_count() -> int:
	return _snapshot.countries.size() if _snapshot != null else 0


func settlement_count() -> int:
	return _snapshot.settlements.size() if _snapshot != null else 0


func character_count() -> int:
	return _snapshot.characters.size() if _snapshot != null else 0


func lot_count() -> int:
	return _snapshot.lots.size() if _snapshot != null else 0


func quest_count() -> int:
	return _snapshot.quests.size() if _snapshot != null else 0


func rule_count() -> int:
	return _snapshot.rules.size() if _snapshot != null else 0


func action_count() -> int:
	return _snapshot.actions.size() if _snapshot != null else 0


func grammar_count() -> int:
	return _snapshot.grammars.size() if _snapshot != null else 0


## The loaded character DTOs (opaque Array[Dictionary]), or [] when not loaded.
## The spawn/AI consumers read this as the authoritative source of character
## identity (see the template npc_spawner world-source path, US-GC4).
func characters() -> Array:
	return _snapshot.characters if _snapshot != null else []


## Find an entity Dictionary by its `id` field, or {} when absent. Entities are
## opaque (schema additionalProperties) so they stay Dictionaries in the DTO.
func find_character(id: String) -> Dictionary:
	return _find_by_id(_snapshot.characters if _snapshot != null else [], id)


func find_settlement(id: String) -> Dictionary:
	return _find_by_id(_snapshot.settlements if _snapshot != null else [], id)


func find_quest(id: String) -> Dictionary:
	return _find_by_id(_snapshot.quests if _snapshot != null else [], id)


func _find_by_id(arr: Array, id: String) -> Dictionary:
	for item in arr:
		if item is Dictionary and str(item.get("id", "")) == id:
			return item
	return {}
