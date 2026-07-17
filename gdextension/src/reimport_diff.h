// reimport_diff.h — the engine-neutral RE-IMPORT DIFF POLICY core (US-GB3).
//
// When a world's IR is re-exported and the scene is regenerated, the editor must
// reconcile the freshly computed placement manifest (US-GB2) against the scene
// tree already on disk WITHOUT clobbering a human's hand edits. This core is the
// authority on that reconciliation policy — the same shared policy the Unity and
// Unreal legs implement:
//
//   - EntityId matching   — old and new nodes are matched by their stable
//                           InsimulEntityId (the manifest's `entityId`).
//   - generated-only       — only nodes flagged `generated: true` are ever
//     updates                touched; a node the user re-flagged `generated:false`
//                           (a hand edit / manual override) is left EXACTLY as it
//                           is, even when the new manifest still lists it.
//   - hand-edits untouched — a hand-edited node absent from the new manifest is
//                           kept as-is too (never auto-removed).
//   - Deprecated group     — a GENERATED node that the new manifest no longer
//                           lists is not deleted; it is marked for the editor's
//                           "Deprecated" group so the human can review/remove it.
//   - dry-run report       — the diff is a pure, side-effect-free classification;
//                           the editor renders it as a preview before applying.
//
// Like binding_resolver.h / scene_placement.h this uses ONLY the C++ standard
// library so it host-tests under a plain clang toolchain (no godot-cpp, no
// libinsimul — see test/run_reimport_tests.sh). The @tool GDScript twin
// (addons/insimul/editor/reimport/insimul_reimport.gd) mirrors this exact
// classification and then APPLIES it to the live scene tree; the shared golden
// (addons/insimul/editor/reimport/fixtures/golden-diff-report.json) pins BOTH so
// they can never diverge. This is the same host-vs-editor split the whole Godot
// leg uses, and the cross-engine contract Unity/Unreal reconcile against too.
//
// Determinism contract: the report is a pure function of (old manifest, new
// manifest). Every id list is emitted in ascending order and the serialization
// is canonical (key-sorted, minified) so two runs — or two engines — produce
// byte-identical reports.

#ifndef INSIMUL_GODOT_REIMPORT_DIFF_H
#define INSIMUL_GODOT_REIMPORT_DIFF_H

#include "json_value.h"
#include "scene_placement.h"

#include <string>
#include <vector>

namespace insimul {

// How re-import classifies a single entityId. Mutually exclusive.
enum class DiffAction {
	Added,      // in NEW, absent from OLD -> materialize a new generated node
	Updated,    // in BOTH, old is generated, transform/asset changed -> re-apply
	Unchanged,  // in BOTH, old is generated, byte-identical -> no-op
	Skipped,    // OLD is a hand edit (generated=false) -> preserve verbatim
	Deprecated, // OLD is generated but absent from NEW -> move to Deprecated group
};

// The dry-run report: one sorted id list per action plus derived counts.
struct DiffReport {
	std::vector<std::string> added;
	std::vector<std::string> updated;
	std::vector<std::string> unchanged;
	std::vector<std::string> skipped;
	std::vector<std::string> deprecated;
};

// True if two nodes differ only in identity (same entityId) but are otherwise
// byte-identical after coordinate quantization — i.e. an update is a no-op.
bool placed_nodes_equivalent(const PlacedNode &a, const PlacedNode &b);

// Classify every entityId across the old + new manifests. Matched by entityId;
// pure and deterministic (id lists ascending).
DiffReport compute_reimport_diff(const std::vector<PlacedNode> &old_nodes,
		const std::vector<PlacedNode> &new_nodes);

// Parse a placement-manifest JSON document's `nodes` array into PlacedNodes.
// Accepts the canonical manifest shape emitted by serialize_placement_manifest.
// Returns false + `error` set on a malformed document.
bool parse_manifest_nodes(const JsonValue &manifest, std::vector<PlacedNode> &out,
		std::string &error);

// Serialize a DiffReport as canonical JSON (the dry-run report artifact compared
// against the shared golden). Key-sorted, minified, deterministic.
std::string serialize_diff_report(const DiffReport &report);

// Convenience: parse `old_manifest_json` + `new_manifest_json`, diff, and
// serialize in one call. Returns the canonical report, or "" with `error` set.
std::string generate_reimport_report(const std::string &old_manifest_json,
		const std::string &new_manifest_json, std::string &error);

} // namespace insimul

#endif // INSIMUL_GODOT_REIMPORT_DIFF_H
