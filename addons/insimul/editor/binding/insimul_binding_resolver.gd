@tool
class_name InsimulBindingResolver
extends RefCounted
## Asset Binding Layer resolver (US-GB1) — resolves a query archetype key against
## a prioritized fallback chain of InsimulBindingTable tiers
## (project -> packs -> placeholder). The first tier (highest priority) that has
## ANY match wins, and within that tier the most specific entry is chosen.
##
## Mirrors BindingResolver::resolve() in
## packages/godot/gdextension/src/binding_resolver.cpp. The shared matrix
## (editor/binding/fixtures/resolver-matrix.json) pins both implementations.

## Ordered tiers, highest priority first after sort_tiers().
var tiers: Array[InsimulBindingTable] = []


func add_tier(table: InsimulBindingTable) -> void:
	tiers.append(table)


## Stable sort tiers by priority descending (project first).
func sort_tiers() -> void:
	tiers.sort_custom(func(a, b): return a.priority > b.priority)


## Resolve `query` to { "resolved": bool, "source": String, "key": String,
## "entry": Dictionary }. Fallback chain, most-specific-within-tier.
func resolve(query: String) -> Dictionary:
	for table in tiers:
		var best := table.best_match(query)
		if not best.is_empty():
			return {
				"resolved": true,
				"source": table.source_name,
				"key": String(best.get("key", "")),
				"entry": best,
			}
	return {"resolved": false, "source": "", "key": "", "entry": {}}


## Build a resolver from a parsed matrix "sources" array (Array of Dictionaries).
static func from_matrix_sources(sources: Array) -> InsimulBindingResolver:
	var resolver := InsimulBindingResolver.new()
	for src in sources:
		if src is Dictionary:
			var table := InsimulBindingTable.new()
			table.from_pack_dict(src)
			resolver.add_tier(table)
	resolver.sort_tiers()
	return resolver
