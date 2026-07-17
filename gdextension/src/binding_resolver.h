// binding_resolver.h — the Asset Binding Layer resolution core (US-GB1).
//
// This is the engine-neutral, dependency-free heart of the Godot Binding Table:
// given a query archetype key (a dot-path taxonomy label such as
// `building.residential.house`) it picks the best-matching binding entry from a
// prioritized chain of sources (project overrides -> packs -> placeholder pack).
//
// Like json_value.h / canonical_json.h this header uses ONLY the C++ standard
// library so it host-tests under a plain clang toolchain (no godot-cpp, no
// libinsimul — see test/run_binding_tests.sh). The GDScript editor resource
// (addons/insimul/editor/binding/insimul_binding_table.gd) mirrors this exact
// algorithm; the shared resolver matrix
// (addons/insimul/editor/binding/fixtures/resolver-matrix.json) pins the
// behavior for BOTH so they can never diverge. This is the same host-vs-editor
// split used across the Godot leg (run_world_source_headless.sh) and the
// cross-engine contract the Unity/Unreal binding layers resolve against too.
//
// Matching semantics (see match_archetype):
//   - exact       entry.key == query
//   - descendant  query starts with entry.key + "."  (a binding on `building`
//                 covers `building.residential.house` — "bind descendants")
//   - wildcard    entry.key ends with ".*" (prefix match) or is "*" (match-all)
// Specificity ranks by matched segment count, then match kind
// (exact > descendant > wildcard). The resolution chain is a FALLBACK order:
// the first source (highest priority) that has ANY match wins, and within that
// source the most specific entry is chosen.

#ifndef INSIMUL_GODOT_BINDING_RESOLVER_H
#define INSIMUL_GODOT_BINDING_RESOLVER_H

#include "json_value.h"

#include <string>
#include <vector>

namespace insimul {

// How an entry key matched a query, most specific last.
enum class MatchKind {
	None = 0,
	Wildcard = 1,   // "*" or "prefix.*"
	Descendant = 2, // query is a strict descendant of the entry key
	Exact = 3,      // query == entry key
};

// One archetype -> asset binding. transform/sockets are carried through as raw
// JSON (passthrough) so the resolution core stays agnostic to their shape.
struct BindingEntry {
	std::string key;
	std::string scene; // res:// PackedScene path (or engine-neutral asset id)
	std::string mesh;  // optional Mesh resource path (alternative to scene)
	JsonValuePtr transform; // may be null
	JsonValuePtr sockets;   // may be null
};

// A resolution tier: project overrides, an imported pack, or the placeholder
// pack. Higher priority tiers are consulted first.
struct BindingSource {
	std::string name;
	long long priority = 0;
	std::vector<BindingEntry> entries;
};

// The specificity of a single entry-vs-query match.
struct MatchScore {
	MatchKind kind = MatchKind::None;
	int matched_segments = 0;

	bool matched() const { return kind != MatchKind::None; }

	// >0 if `a` is strictly more specific than `b`, <0 if less, 0 if equal.
	static int compare(const MatchScore &a, const MatchScore &b);
};

// Score how `entry_key` matches `query`. kind == None means no match.
MatchScore match_archetype(const std::string &entry_key, const std::string &query);

struct ResolveResult {
	bool resolved = false;
	std::string source_name;
	std::string key;   // the matched entry key (for reporting)
	const BindingEntry *entry = nullptr;
};

class BindingResolver {
public:
	void add_source(BindingSource source);

	// Stable sort of sources by priority, descending (project first). Called by
	// resolve() implicitly is NOT done — the caller controls the chain order;
	// use this to establish the project -> packs -> placeholder order.
	void sort_sources_by_priority();

	ResolveResult resolve(const std::string &query) const;

	const std::vector<BindingSource> &sources() const { return sources_; }

private:
	std::vector<BindingSource> sources_;
};

// Parse a binding pack / source object into a BindingSource. Accepts both the
// standalone pack shape ({format,version,name,priority,entries}) and the inline
// matrix-source shape ({name,priority,entries}). Returns false + `error` set on
// a malformed object.
bool parse_binding_source(const JsonValue &obj, BindingSource &out, std::string &error);

// Build a resolver from a matrix "sources" array (array of source objects).
bool parse_resolver_matrix_sources(const JsonValue &sources_arr,
		BindingResolver &out, std::string &error);

// Canonical, key-sorted serialization of a pack: entries sorted ascending by
// key, every object's keys sorted, minified — byte-deterministic across runs
// and engines (the ".tres-friendly sorted serialization" invariant, expressed
// over the portable JSON pack form). `format`/`version` default to the pack
// contract when omitted by the source.
std::string serialize_pack_sorted(const BindingSource &source);

} // namespace insimul

#endif // INSIMUL_GODOT_BINDING_RESOLVER_H
