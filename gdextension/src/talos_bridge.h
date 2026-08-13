// talos_bridge.h — the decision half of `insimul-talos-bridge`, the third
// artifact of TALOS_INSIMUL_BRIDGE.md §7.5.
//
// WHAT THIS IS. §7.5 settles the shape: the Talos bridge for an Insimul game is
// an artifact that depends on both projects and is depended on by NEITHER. On
// Godot the game-side contract is duck-typed — a node in six declared groups
// exposing four methods and two signals, with no Talos type anywhere — so the
// bridge is `addons/insimul_talos/`, and this file is the part of it that
// DECIDES rather than acts:
//
//   * the `capabilities.insimul` payload of §3.1,
//   * the six-rung refuse-at-hello decision of §7.7 (docs/REFUSE_AT_HELLO.md),
//   * the archive rule — a persisted checkpoint outside its `snapshot_version`
//     is INVALIDATED, never restored,
//   * which TBP verb this bridge answers from the KB and which why-not token
//     every other one is refused with,
//   * the canonical sort §3.4 requires before a query digest is capped.
//
// The ACTING half — `insimul_kb_snapshot`, `insimul_kb_restore`, a Prolog query,
// an assert — is GDScript in the addon, going through the Insimul plugin's own
// `InsimulProlog`. This file touches neither libinsimul nor godot-cpp: readings
// in, orders out, the same shape CLAUDE.md names for a C ABI with no callbacks.
//
// WHY C++ AND NOT ONE GDSCRIPT FILE, which is what §7.5 pictured. There is no
// Godot binary in this repository's gates (every `gdextension/test/run_*.sh`
// builds with a plain C/C++ compiler), so a decision procedure written in
// GDScript could not be executed by anything that gates a merge — and this
// project's own rule is that a gate which cannot fail is worse than no gate.
// Putting the decision here keeps ONE implementation and makes it executable:
// `run_talos_bridge_tests.sh` replays the reference implementation's own 21
// cases through it. The cost is honest and bounded — the bridge ADDON stays
// buildless GDScript plus data, and nothing here names a Talos symbol or
// changes what `addons/insimul/` ships.
//
// NOTHING IS COMPILED IN THAT THE MATRIX PUBLISHES. The decision reads
// `addons/insimul_talos/supported-versions.json` (mirrored by
// tools/vendor-supported-versions.mjs) and `bridge-contract.json`. §7.7's whole
// point is that the answer is knowable before a run, from artifacts, and a build
// that likes itself is not evidence.

#ifndef INSIMUL_GODOT_TALOS_BRIDGE_H
#define INSIMUL_GODOT_TALOS_BRIDGE_H

#include "json_value.h"

#include <cstddef>
#include <string>
#include <vector>

namespace insimul {
namespace talos {

// TBP's `query_state` digest cap (talos:docs/03-engine-bridge.md §2.5). Named
// here because §3.4's correction rides on it: solutions must be canonically
// sorted BEFORE the cap, or a capped Insimul query is not reproducible across
// engines — core compares solutions as an unordered multiset by design.
const std::size_t QUERY_DIGEST_CAP_BYTES = 16 * 1024;

/// What the adapter knows about the build and the world, gathered by the addon
/// and handed in. `kb_ready` false is the §7.5 state: a world has not been
/// loaded, so no reading here came from the knowledge base.
struct Readings {
	std::string engine = "godot";
	std::string engine_version;   // Engine.get_version_info()
	std::string plugin_version;   // addons/insimul_talos/plugin.cfg
	std::string core_version;     // insimul_version() — the c_abi axis
	std::string snapshot_version; // the save-format gate
	std::string world_id;
	std::string seed;
	std::vector<std::string> active_modules;
	bool kb_ready = false;
};

/// The decision surface. Every method returns a JSON document: an admission
/// carrying what the caller needs, or the TBP refusal envelope of §2.11 with one
/// why-not token in `data.sub_code`.
class Bridge {
public:
	/// Hand the bridge its two shipped data files. Returns false — and leaves
	/// `error()` set — when either is missing or unreadable, because a
	/// half-present install must answer nothing rather than default to something
	/// (§7.8).
	bool configure(const std::string &contract_json, const std::string &matrix_json);
	bool configured() const { return configured_; }
	const std::string &error() const { return error_; }

	/// The six group names of §7.4, in contract order. The addon joins exactly
	/// these and `talos.game.yaml` declares exactly these; a group in one and not
	/// the other is an adapter that is invisible to the Bridge.
	std::vector<std::string> groups() const;

	/// The `capabilities.insimul` block of §3.1. Declares `kb_ready`, and the
	/// world half is null until it is true — never an empty world id read as a
	/// world with no name.
	std::string capabilities(const Readings &readings) const;

	/// A whole tbp/1.x hello result carrying that block, so the adapter can put
	/// its own build through the decision below before a session starts.
	std::string hello(const Readings &readings) const;

	/// §7.7 / REFUSE_AT_HELLO.md: admit, or refuse with the FIRST blocking reason
	/// in contract order. Order is contract, not taste — two adapters refusing
	/// the same build must produce the same token.
	///
	/// `matrix_override` decides against a matrix other than the shipped one. It
	/// exists for the reference corpus, whose cases point at synthetic matrices to
	/// reach cells no published one has: the why-not VOCABULARY still comes from
	/// the shipped mirror, so a case can move the cell without moving the words.
	std::string evaluate_hello(const std::string &hello_json,
			const std::string &matrix_override = std::string()) const;

	/// The archive rule. Every uncertainty resolves to `invalidate`: an unstamped
	/// entry, a half-stamped entry, an axis the matrix publishes no value for.
	std::string evaluate_archive(const std::string &archive_json,
			const std::string &matrix_override = std::string()) const;

	/// The stamp `talos_save()` writes beside a checkpoint. TBP's
	/// `save_checkpoint` response carries no version field, so an archive is
	/// unstamped — and therefore uninvalidatable — unless the adapter records the
	/// axes itself.
	std::string checkpoint_stamp(const Readings &readings) const;

	/// May this bridge answer `verb`? Refuses an undeclared verb, a host-owned
	/// one, an unmapped one, a state verb before the KB is live
	/// (`insimul_kb_uninitialized`, retryable), and one that needs a module this
	/// world's genre never activated. `required_module` may be empty.
	std::string verb(const std::string &name, const Readings &readings,
			const std::string &required_module = std::string()) const;

	/// §3.4's fix. `solutions_json` is the array of binding sets a KB query
	/// produced; they are sorted by their canonical serialization and only then
	/// capped, so two engines enumerating in different orders truncate the same
	/// digest. Reports `overflow` and how many solutions were dropped.
	std::string query_digest(const std::string &solutions_json,
			std::size_t cap_bytes = QUERY_DIGEST_CAP_BYTES) const;

	/// §3.6. A progress var IS a fact, so the order is an assert — refused when
	/// it targets a world TEMPLATE, which would corrupt every future playthrough
	/// of that world invisibly. The fact TEXT is the game's, not the bridge's:
	/// the order names the variable and its value, and the addon's declared
	/// registry says which predicate carries it.
	std::string progress_var(const std::string &name, const std::string &value_json,
			bool targets_template, const Readings &readings) const;

	/// Every why-not token this bridge can emit, hello-stage and verb-stage
	/// alike. The gate checks each one against a published vocabulary.
	std::vector<std::string> tokens() const;

private:
	bool configured_ = false;
	std::string error_;
	JsonValuePtr contract_;
	JsonValuePtr matrix_;

	/// The matrix a decision reads: the override when one was given and parsed,
	/// the shipped mirror otherwise. `holder` keeps the parsed override alive for
	/// the duration of the call.
	const JsonValue *matrix_for(const std::string &override_json, JsonValuePtr &holder) const;
	const JsonValue *engine_row(const JsonValue &matrix, const std::string &engine) const;
	const JsonValue *token_meta(const std::string &token) const;
	std::string refuse(const std::string &token, const std::string &message,
			const std::vector<std::pair<std::string, JsonValuePtr>> &extra) const;
	std::string not_configured() const;
};

} // namespace talos
} // namespace insimul

#endif // INSIMUL_GODOT_TALOS_BRIDGE_H
