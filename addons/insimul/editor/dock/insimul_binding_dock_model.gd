@tool
class_name InsimulBindingDockModel
extends RefCounted
## Binding Editor dock — logic layer (US-GB3).
##
## The pure, UI-free heart of the binding-management dock: it turns a set of
## taxonomy archetype keys + an InsimulBindingTable into the data the dock renders
## (a taxonomy tree with bound/unbound status), ranks scene-picker suggestions by
## name/tag over the project, and drives bind / bind-descendants / pack
## import-export. Keeping this a RefCounted with NO Control dependencies is what
## makes the dock's logic testable headless (reimport_test.gd-style) while the
## Control (insimul_binding_dock.gd) is only structurally checked — the split the
## story's "logic layer tested; UI structurally checked" criterion calls for.

## The binding table this dock edits (the project-override tier, priority high).
var table: InsimulBindingTable


func _init(binding_table: InsimulBindingTable = null) -> void:
	table = binding_table if binding_table != null else InsimulBindingTable.new()


# ---------------------------------------------------------------------------
# Taxonomy tree + bound/unbound status
# ---------------------------------------------------------------------------

## True if `archetype` resolves to a binding in THIS table — either an exact
## entry or a descendant/wildcard match (so a `building` binding counts every
## `building.*` archetype as bound, the "bind descendants" affordance).
func is_bound(archetype: String) -> bool:
	return not table.best_match(archetype).is_empty()


## The archetype keys that have a binding, and those that do not, given the full
## set of taxonomy keys the world uses. Both sorted ascending.
func bound_keys(archetypes: Array) -> Array:
	return _partition(archetypes, true)


func unbound_keys(archetypes: Array) -> Array:
	return _partition(archetypes, false)


func _partition(archetypes: Array, want_bound: bool) -> Array:
	var out: Array = []
	for a in archetypes:
		var key := String(a)
		if is_bound(key) == want_bound:
			out.append(key)
	out.sort()
	return out


## Build a nested taxonomy tree from dot-path archetype keys. Each node is a
## Dictionary:
##   { "segment": String, "path": String, "bound": bool, "scene": String,
##     "children": { segment -> node } }
## Intermediate nodes (no exact archetype at that path) carry bound=false/scene=""
## unless they are themselves a used archetype. Deterministic (children keyed by
## segment; the dock sorts keys for display).
func build_taxonomy_tree(archetypes: Array) -> Dictionary:
	var root := {"segment": "", "path": "", "bound": false, "scene": "", "children": {}}
	var sorted := []
	for a in archetypes:
		sorted.append(String(a))
	sorted.sort()
	for key in sorted:
		var segments := key.split(".", false)
		var node := root
		var path := ""
		for seg in segments:
			path = seg if path.is_empty() else path + "." + seg
			if not node["children"].has(seg):
				node["children"][seg] = {
					"segment": seg, "path": path, "bound": false, "scene": "", "children": {},
				}
			node = node["children"][seg]
		# The full key is a used archetype — annotate its bound status + asset.
		node["bound"] = is_bound(key)
		var matched := table.best_match(key)
		node["scene"] = String(matched.get("scene", matched.get("mesh", ""))) if not matched.is_empty() else ""
	return root


# ---------------------------------------------------------------------------
# Scene-picker suggestions (name/tag matching over the project)
# ---------------------------------------------------------------------------

## Rank project assets as scene-picker suggestions for `archetype`. `assets` is an
## Array of Dictionaries { "path": String, "name": String, "tags": Array }. Score
## = count of the archetype's dot segments that appear (case-insensitive
## substring) in the asset name, path, or tags. Only assets with score > 0 are
## returned, sorted by score descending then path ascending (deterministic).
func suggest_bindings(archetype: String, assets: Array) -> Array:
	var segments: Array = []
	for seg in archetype.to_lower().split(".", false):
		segments.append(String(seg))
	var scored: Array = []
	for asset in assets:
		var haystack := (String(asset.get("name", "")) + " " + String(asset.get("path", ""))).to_lower()
		for tag in asset.get("tags", []):
			haystack += " " + String(tag).to_lower()
		var score := 0
		for seg in segments:
			if not String(seg).is_empty() and haystack.contains(String(seg)):
				score += 1
		if score > 0:
			scored.append({"path": String(asset.get("path", "")), "score": score})
	scored.sort_custom(func(a, b):
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return String(a["path"]) < String(b["path"]))
	return scored


# ---------------------------------------------------------------------------
# Bind operations + pack import/export
# ---------------------------------------------------------------------------

## Bind `archetype` to a PackedScene (or Mesh) asset. Passing a non-leaf taxonomy
## key (e.g. `building`) binds every descendant that has no more specific entry —
## the "bind descendants" affordance (descendant matching lives in the resolver).
func bind(archetype: String, scene_path: String, is_mesh: bool = false) -> void:
	var binding := {}
	if is_mesh:
		binding["mesh"] = scene_path
	else:
		binding["scene"] = scene_path
	table.set_binding(archetype, binding)
	table.sort_entries()


## Bind a parent taxonomy key so it covers all its descendants. Convenience alias
## that documents intent; identical to bind() on the parent key.
func bind_descendants(parent_key: String, scene_path: String, is_mesh: bool = false) -> void:
	bind(parent_key, scene_path, is_mesh)


## Remove the binding for `archetype` (exact key only). Returns true if removed.
func unbind(archetype: String) -> bool:
	for i in table.entries.size():
		if String(table.entries[i].get("key", "")) == archetype:
			table.entries.remove_at(i)
			return true
	return false


## Export the current table as portable-pack JSON (the insimul-binding-pack
## interchange shared with Unity/Unreal, and the reimport/US-GB1 contract).
func export_pack_json() -> String:
	return table.export_pack_json()


## Replace the current table from portable-pack JSON. Returns true on a parseable
## pack. The dock uses this for pack import.
func import_pack_json(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	table.from_pack_dict(parsed)
	table.sort_entries()
	return true
