class_name InsimulContentLibrary
extends RefCounted
## Host-testable content-library importer for the Godot SDK (content-portability).
##
## Reads a shared, engine-neutral CONTENT LIBRARY (a portable pack of authored
## items / characters / towns / quests / narratives — the artifact a creator
## authors once and imports into every engine) and materializes it into native
## Godot entities. Validation gates on the library-format schemaVersion and on the
## structural contract (required collections, per-entity `id`) so an invalid
## library is rejected with a clear error BEFORE any entity is materialized —
## never partially imported.
##
## Cross-engine parity: this mirrors the Unity / Unreal content importers against
## the SAME shared fixture (conformance/content/library.json). The vendored core
## schemas own the contract; see conformance/content/README.md and MIGRATION.md.

## Oldest library-format version this importer can consume.
const MIN_SUPPORTED_SCHEMA_VERSION := 1

## Newest library-format version this importer understands. A library stamped
## beyond this was produced by a newer build and is rejected.
const MAX_SUPPORTED_SCHEMA_VERSION := 1

## The entity collections, in canonical order, paired with the native entity
## `kind` each element materializes as. The whole contract flows from this table:
## required top-level keys, counts, accessors, and materialization all derive from
## it, so adding a collection is a one-line change.
const COLLECTIONS := [
	{"key": "items", "kind": "item"},
	{"key": "characters", "kind": "character"},
	{"key": "towns", "kind": "town"},
	{"key": "quests", "kind": "quest"},
	{"key": "narratives", "kind": "narrative"},
]


## A single materialized native entity. RefCounted (a native Godot object), it
## carries the engine-neutral payload plus the importer-assigned `kind`. The
## scene-side path (build_scene) stamps the same identity onto Nodes using the
## standard insimul_* metadata convention (see InsimulSceneGenerator).
class Entity extends RefCounted:
	var kind: String = ""
	var id: String = ""
	var name: String = ""
	var data: Dictionary = {}

	static func of(entity_kind: String, source: Dictionary) -> Entity:
		var e := Entity.new()
		e.kind = entity_kind
		e.id = str(source.get("id", ""))
		# Characters carry firstName/lastName rather than a single `name`.
		if source.has("name"):
			e.name = str(source["name"])
		elif source.has("title"):
			e.name = str(source["title"])
		elif source.has("firstName"):
			e.name = str(source["firstName"])
			if source.has("lastName"):
				e.name += " " + str(source["lastName"])
		e.data = source
		return e


var _loaded := false
var _schema_version := 0
var _source: Dictionary = {}
var _last_error := ""


## Pure schema-version gate — no I/O. Returns a Dictionary mirroring the world
## source's version gate: { compatible: bool, version: int, status: String,
## message: String }. `status` is "current" | "supported" | "incompatible".
static func check_schema_version(version: int) -> Dictionary:
	var result := {
		"compatible": false,
		"version": version,
		"status": "",
		"message": "",
	}
	if version < MIN_SUPPORTED_SCHEMA_VERSION:
		result.status = "incompatible"
		result.message = "Content-library schema version %d is older than the minimum supported version %d." % [version, MIN_SUPPORTED_SCHEMA_VERSION]
		return result
	if version > MAX_SUPPORTED_SCHEMA_VERSION:
		result.status = "incompatible"
		result.message = "Content-library schema version %d was produced by a newer build (max supported %d). Please update the game." % [version, MAX_SUPPORTED_SCHEMA_VERSION]
		return result
	result.compatible = true
	result.status = "current" if version == MAX_SUPPORTED_SCHEMA_VERSION else "supported"
	result.message = "Content-library schema version %d is compatible." % version
	return result


## Load and validate a content library from JSON text. Returns false (and sets
## last_error()) on malformed JSON, an unsupported schemaVersion, a missing/
## non-array collection, or an entity without an `id`. On failure NOTHING is
## imported — is_loaded() stays false.
func load_from_json(json_text: String) -> bool:
	_loaded = false
	_schema_version = 0
	_source = {}
	_last_error = ""

	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "Content-library root is not a JSON object"
		return false
	var root: Dictionary = parsed

	if not root.has("schemaVersion"):
		_last_error = "Content-library is missing 'schemaVersion'"
		return false
	_schema_version = int(root.get("schemaVersion", 0))
	var gate := check_schema_version(_schema_version)
	if not gate.compatible:
		_last_error = gate.message
		return false

	if not root.has("id") or str(root.get("id", "")).is_empty():
		_last_error = "Content-library is missing a non-empty 'id'"
		return false

	# Every collection must be present and an Array; every entity must have an id.
	for spec in COLLECTIONS:
		var key: String = spec["key"]
		if not root.has(key):
			_last_error = "Content-library is missing the '%s' collection" % key
			return false
		if typeof(root[key]) != TYPE_ARRAY:
			_last_error = "Content-library field '%s' must be an array" % key
			return false
		var seen := {}
		for i in (root[key] as Array).size():
			var entity: Variant = root[key][i]
			if typeof(entity) != TYPE_DICTIONARY:
				_last_error = "Content-library '%s'[%d] is not an object" % [key, i]
				return false
			var eid := str((entity as Dictionary).get("id", ""))
			if eid.is_empty():
				_last_error = "Content-library '%s'[%d] is missing a non-empty 'id'" % [key, i]
				return false
			if seen.has(eid):
				_last_error = "Content-library '%s' has a duplicate id '%s'" % [key, eid]
				return false
			seen[eid] = true

	_source = root
	_loaded = true
	return true


func is_loaded() -> bool:
	return _loaded


func loaded_schema_version() -> int:
	return _schema_version


func last_error() -> String:
	return _last_error


## The library's declared id / name ("" when not loaded).
func library_id() -> String:
	return str(_source.get("id", ""))


func library_name() -> String:
	return str(_source.get("name", ""))


# ── Typed collection accessors (opaque source Dictionaries) ──────────────────

func items() -> Array:
	return _collection("items")


func characters() -> Array:
	return _collection("characters")


func towns() -> Array:
	return _collection("towns")


func quests() -> Array:
	return _collection("quests")


func narratives() -> Array:
	return _collection("narratives")


func _collection(key: String) -> Array:
	return _source.get(key, []) if _loaded else []


func item_count() -> int:
	return items().size()


func character_count() -> int:
	return characters().size()


func town_count() -> int:
	return towns().size()


func quest_count() -> int:
	return quests().size()


func narrative_count() -> int:
	return narratives().size()


## Total materialized entity count across every collection.
func entity_count() -> int:
	var total := 0
	for spec in COLLECTIONS:
		total += _collection(spec["key"]).size()
	return total


func find_item(id: String) -> Dictionary:
	return _find_by_id(items(), id)


func find_character(id: String) -> Dictionary:
	return _find_by_id(characters(), id)


func find_town(id: String) -> Dictionary:
	return _find_by_id(towns(), id)


func find_quest(id: String) -> Dictionary:
	return _find_by_id(quests(), id)


func find_narrative(id: String) -> Dictionary:
	return _find_by_id(narratives(), id)


func _find_by_id(arr: Array, id: String) -> Dictionary:
	for item in arr:
		if item is Dictionary and str(item.get("id", "")) == id:
			return item
	return {}


# ── Materialization into native Godot entities ───────────────────────────────

## Materialize every collection into native Entity objects (in COLLECTIONS
## order). Returns [] when the library did not load. Pure — no I/O, no Nodes, so
## it is host-checkable; the scene path (build_scene) layers Nodes on top.
func materialize() -> Array:
	var out: Array = []
	if not _loaded:
		return out
	for spec in COLLECTIONS:
		for src in _collection(spec["key"]):
			if src is Dictionary:
				out.append(Entity.of(spec["kind"], src))
	return out


## Build a native Godot scene subtree under `root`: one child Node per entity,
## each stamped with the standard insimul_* metadata (entity id / kind /
## generated flag) so the re-import diff (InsimulReimport) can reconcile it like
## any other generated node. Returns the number of nodes added. Requires the
## Godot runtime (Nodes), so it runs under a real editor/headless binary, not the
## host lint.
func build_scene(root: Node) -> int:
	var added := 0
	for entity in materialize():
		var node := Node.new()
		node.name = "%s_%s" % [entity.kind, entity.id]
		node.set_meta("insimul_entity_id", entity.id)
		node.set_meta("insimul_kind", entity.kind)
		node.set_meta("insimul_generated", true)
		node.set_meta("insimul_content_name", entity.name)
		root.add_child(node)
		added += 1
	return added


## The raw validated source Dictionary ({} when not loaded). Round-trip and
## re-export read off this (US-IM2).
func source() -> Dictionary:
	return _source


# ── Round-trip export (US-IM2: author-once / use-anywhere parity) ─────────────

## Re-export the imported content back into an engine-neutral content-library
## Dictionary — the export leg of the round-trip. It is REBUILT from the
## materialized native entities (grouped back into their collections by `kind`),
## not handed a copy of the raw source, so a fresh importer loading it must
## reproduce the same semantics the shared golden pins. Returns {} when not loaded.
func export_library() -> Dictionary:
	if not _loaded:
		return {}
	var out := {
		"schemaVersion": _schema_version,
		"id": library_id(),
		"name": library_name(),
	}
	for spec in COLLECTIONS:
		out[spec["key"]] = []
	for entity in materialize():
		var key := _kind_to_key(entity.kind)
		if not key.is_empty():
			(out[key] as Array).append(entity.data)
	return out


## export_library() serialized back to JSON text — feeds straight into a fresh
## InsimulContentLibrary.load_from_json() to close the round-trip.
func export_json() -> String:
	return JSON.stringify(export_library())


## The collection key a materialized `kind` belongs to ("" if unknown) — the
## inverse of the COLLECTIONS kind mapping.
func _kind_to_key(kind: String) -> String:
	for spec in COLLECTIONS:
		if spec["kind"] == kind:
			return spec["key"]
	return ""
