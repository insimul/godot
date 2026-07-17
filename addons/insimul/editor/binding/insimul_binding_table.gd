@tool
class_name InsimulBindingTable
extends Resource
## Asset Binding Layer table (US-GB1) — a .tres-friendly Godot Resource mapping
## archetype keys (dot-path taxonomy labels such as `building.residential.house`)
## to PackedScene / Mesh assets plus transform fixups and named sockets.
##
## This is the editor-facing twin of the host-tested C++ resolver core
## (packages/godot/gdextension/src/binding_resolver.{h,cpp}). The matching
## semantics here MUST stay byte-identical to that core; the shared matrix
## (editor/binding/fixtures/resolver-matrix.json) pins both, and
## binding_resolver_test.gd runs this GDScript against it end-to-end when a Godot
## binary is present (the C++ host gate covers the bare Ralph box).
##
## Serialization is SORTED (entries ascending by key) so a saved .tres — and the
## exported portable pack JSON — is byte-deterministic across runs and machines,
## the cross-engine round-trip contract shared with Unity/Unreal.

## Interchange format tag for exported/imported portable packs.
const PACK_FORMAT := "insimul-binding-pack"
const PACK_VERSION := 1

## Match-kind ranks (mirror MatchKind in binding_resolver.h). Higher = more
## specific for the same matched-segment count.
const MATCH_NONE := 0
const MATCH_WILDCARD := 1
const MATCH_DESCENDANT := 2
const MATCH_EXACT := 3

## Human-facing name of this tier (e.g. "project", "packs", "placeholder").
@export var source_name: String = ""

## Resolution priority; higher tiers are consulted first in the fallback chain.
@export var priority: int = 0

## Binding entries. Each is a Dictionary:
##   { "key": String, "scene": String, "mesh": String,
##     "transform": Dictionary, "sockets": Dictionary }
## Stored as plain Dictionaries so the Resource stays .tres-serializable without
## a nested custom-resource-per-entry explosion.
@export var entries: Array = []


## Sort entries ascending by key (stable) so the serialized .tres / pack JSON is
## deterministic. Call before ResourceSaver.save() or export.
func sort_entries() -> void:
	entries.sort_custom(func(a, b): return String(a.get("key", "")) < String(b.get("key", "")))


## Add or replace the binding for `key`.
func set_binding(key: String, binding: Dictionary) -> void:
	for i in entries.size():
		if String(entries[i].get("key", "")) == key:
			var merged := binding.duplicate(true)
			merged["key"] = key
			entries[i] = merged
			return
	var e := binding.duplicate(true)
	e["key"] = key
	entries.append(e)


## Count dot-separated segments ("a.b.c" -> 3, "a" -> 1, "" -> 0). Mirrors
## segment_count() in binding_resolver.cpp.
static func _segment_count(key: String) -> int:
	if key.is_empty():
		return 0
	return key.count(".") + 1


## Score how `entry_key` matches `query`. Returns { "kind": int, "segments": int }.
## kind == MATCH_NONE means no match. Mirrors match_archetype() exactly.
static func match_archetype(entry_key: String, query: String) -> Dictionary:
	var result := {"kind": MATCH_NONE, "segments": 0}
	if entry_key.is_empty() or query.is_empty():
		return result
	# Match-all wildcard.
	if entry_key == "*":
		result["kind"] = MATCH_WILDCARD
		result["segments"] = 0
		return result
	# Prefix wildcard "prefix.*".
	if entry_key.length() >= 2 and entry_key.ends_with(".*"):
		var prefix := entry_key.substr(0, entry_key.length() - 2)
		if prefix.is_empty():
			return result
		if query == prefix or query.begins_with(prefix + "."):
			result["kind"] = MATCH_WILDCARD
			result["segments"] = _segment_count(prefix)
		return result
	# Exact.
	if query == entry_key:
		result["kind"] = MATCH_EXACT
		result["segments"] = _segment_count(entry_key)
		return result
	# Descendant: query starts with entry_key + '.'.
	if query.begins_with(entry_key + "."):
		result["kind"] = MATCH_DESCENDANT
		result["segments"] = _segment_count(entry_key)
	return result


## Compare two match scores. >0 if `a` more specific than `b`, <0 if less, 0 equal.
static func compare_scores(a: Dictionary, b: Dictionary) -> int:
	var asg := int(a.get("segments", 0))
	var bsg := int(b.get("segments", 0))
	if asg != bsg:
		return -1 if asg < bsg else 1
	var ak := int(a.get("kind", 0))
	var bk := int(b.get("kind", 0))
	if ak != bk:
		return -1 if ak < bk else 1
	return 0


## Most specific matching entry in THIS table for `query`, or {} if none. Ties
## keep the earlier-declared entry (stable), mirroring the C++ resolve loop.
func best_match(query: String) -> Dictionary:
	var best := {}
	var best_score := {"kind": MATCH_NONE, "segments": 0}
	for entry in entries:
		var score := match_archetype(String(entry.get("key", "")), query)
		if int(score.get("kind", 0)) == MATCH_NONE:
			continue
		if best.is_empty() or compare_scores(score, best_score) > 0:
			best = entry
			best_score = score
	return best


## Build a portable pack Dictionary (sorted entries) suitable for JSON export.
func to_pack_dict() -> Dictionary:
	sort_entries()
	var out_entries: Array = []
	for entry in entries:
		var e := {"key": String(entry.get("key", ""))}
		if not String(entry.get("scene", "")).is_empty():
			e["scene"] = String(entry["scene"])
		if not String(entry.get("mesh", "")).is_empty():
			e["mesh"] = String(entry["mesh"])
		if entry.has("transform") and entry["transform"] is Dictionary and not entry["transform"].is_empty():
			e["transform"] = entry["transform"]
		if entry.has("sockets") and entry["sockets"] is Dictionary and not entry["sockets"].is_empty():
			e["sockets"] = entry["sockets"]
		out_entries.append(e)
	return {
		"format": PACK_FORMAT,
		"version": PACK_VERSION,
		"name": source_name,
		"priority": priority,
		"entries": out_entries,
	}


## Load this table from a portable pack Dictionary (parsed pack JSON). Accepts
## both a standalone pack ({format,version,name,priority,entries}) and an inline
## matrix source ({name,priority,entries}).
func from_pack_dict(pack: Dictionary) -> void:
	source_name = String(pack.get("name", ""))
	priority = int(pack.get("priority", 0))
	entries = []
	var raw = pack.get("entries", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary and not String(item.get("key", "")).is_empty():
				entries.append(item.duplicate(true))


## Export the sorted pack as a JSON string (stable ordering; keys not sorted here
## because Godot's JSON keeps insertion order — the canonical byte-parity check
## lives host-side in serialize_pack_sorted()).
func export_pack_json() -> String:
	return JSON.stringify(to_pack_dict(), "  ")


## Static: parse a pack JSON string into a new table.
static func import_pack_json(text: String) -> InsimulBindingTable:
	var parsed = JSON.parse_string(text)
	var table := InsimulBindingTable.new()
	if parsed is Dictionary:
		table.from_pack_dict(parsed)
	return table
