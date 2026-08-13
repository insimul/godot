// insimul_talos_bridge.h — the Godot-facing wrapper over the bridge decision
// core (talos_bridge.h), for `addons/insimul_talos/`.
//
// The split is the same one InsimulQuestCore / quest_system.* uses: every
// decision lives in the dependency-free core so it can be host-tested under a
// plain compiler (test/run_talos_bridge_tests.sh), and this file only marshals
// Godot types across. It adds no rule of its own — a decision reachable only
// through a Godot binary would be a decision this repository cannot gate.
//
// NOTHING HERE NAMES A TALOS SYMBOL, and nothing in `addons/insimul/` reads this
// class. That is the §7.5 shape held literally: the bridge depends on both
// projects and is depended on by neither.
//
// BUILD NOTE: requires godot-cpp, which is not available in this harness, so
// this file is syntax-gated only — see README "Structural fallback".

#ifndef INSIMUL_GODOT_INSIMUL_TALOS_BRIDGE_H
#define INSIMUL_GODOT_INSIMUL_TALOS_BRIDGE_H

#include "talos_bridge.h"
#include "talos_replay.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class InsimulTalosBridge : public RefCounted {
	GDCLASS(InsimulTalosBridge, RefCounted)

public:
	// Hand the bridge the three files that ship with the addon. False on a
	// half-present install; last_error() then says which file and why, and
	// diagnose_install() names the failure MODE.
	bool configure(const String &contract_json, const String &matrix_json,
			const String &vocabulary_json = String());
	bool is_configured() const;
	String last_error() const;

	// The six group names of §7.4, in contract order.
	PackedStringArray groups() const;

	// Everything below answers with a JSON document, decoded by the addon. JSON
	// rather than Dictionary because the shapes are contracts published in
	// docs/REFUSE_AT_HELLO.md and talos:docs/03-engine-bridge.md §2.11, and a
	// Dictionary would let a field be renamed here without anything noticing.
	String capabilities(const Dictionary &readings) const;
	String hello(const Dictionary &readings) const;
	String evaluate_hello(const String &hello_json, const String &matrix_override = String()) const;
	String evaluate_archive(const String &archive_json, const String &matrix_override = String()) const;
	String checkpoint_stamp(const Dictionary &readings) const;
	String verb(const String &name, const Dictionary &readings, const String &required_module = String()) const;
	String query_digest(const String &solutions_json, int cap_bytes) const;
	String progress_var(const String &name, const String &value_json, bool targets_template,
			const Dictionary &readings) const;

	// §7.8: which piece of a half-present install is missing, and what installs
	// it. Static on the C++ side and const here, because it is answered precisely
	// when configure() failed. `readings` carries `extension_registered` plus the
	// text of each file the addon managed to read.
	String diagnose_install(const Dictionary &readings) const;

	// ── the replay leg (§8.6, tasklist 180's artifact) ──
	//
	// Readings in, orders out: `plan_replay` hands back the whole tick sequence
	// and the addon carries it out against the live knowledge base, because
	// core's driver calls back into the world once per tick and the C ABI has no
	// callbacks.
	String open_trace(const String &trace_json, const String &world_json) const;
	String plan_replay(const String &trace_json, const String &world_json,
			const String &options_json) const;
	String seal_outcome(const String &args_json) const;
	String read_outcome(const String &outcome_json) const;
	String verify_outcome(const String &recorded_json, const String &trace_id) const;
	String compare_outcomes(const String &recorded_json, const String &replayed_json) const;
	String world_content_digest(const String &world_json) const;
	String kb_digest(const String &facts_json) const;
	int replay_entropy(const String &seed, int tick) const;

protected:
	static void _bind_methods();

private:
	insimul::talos::Bridge bridge_;
	insimul::talos::Replay replay_;

	// The addon gathers readings into a Dictionary; this is the one place that
	// shape is read. `kb_ready` false means no field below it came from a KB.
	static insimul::talos::Readings to_readings(const Dictionary &readings);
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_TALOS_BRIDGE_H
