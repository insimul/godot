// insimul_runtime_core.h — the Godot-facing GDExtension class for the portable
// startup orchestrator (US-GC4).
//
// InsimulRuntimeCore (RefCounted) wraps the dependency-free bootstrap core
// (bootstrap.h → RuntimeContext) and exposes the full template-startup loop —
// world source → save slot → KB → systems — to GDScript. All the semantics that
// matter (boot/resume, migration, canonical save, radiant tick, fact-asserting
// quest transitions, world-hash stability) live ENTIRELY in the host-tested core,
// so GDScript never re-implements them.
//
// Named InsimulRuntimeCore (not InsimulRuntime) to leave the class_name
// InsimulRuntime free for the GDScript runtime bootstrap (addons/insimul/runtime/
// runtime_bootstrap.gd), mirroring the InsimulSaveCodec / InsimulSaveSystem and
// InsimulQuestCore / InsimulQuestSystem splits.
//
// BUILD NOTE: requires godot-cpp headers. Not available in the Ralph harness (no
// scons/godot/godot-cpp), so this file is *syntax-gated* only — the real gate is
// the host test (test/run_bootstrap_tests.sh).

#ifndef INSIMUL_GODOT_INSIMUL_RUNTIME_CORE_H
#define INSIMUL_GODOT_INSIMUL_RUNTIME_CORE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "bootstrap.h"

namespace godot {

class InsimulRuntimeCore : public RefCounted {
	GDCLASS(InsimulRuntimeCore, RefCounted)

public:
	InsimulRuntimeCore() = default;
	~InsimulRuntimeCore() = default;

	// ── Boot / load (full loop) ──────────────────────────────────────────────

	// The startup decision. `existing_save_json` empty (or corrupt) → new game from
	// `fallback_world_snapshot_json`; otherwise resume it. `options` is a Dictionary
	// { id, user_id, world_id, name, slot_index, created_at }. Returns
	// { ok: bool, resumed_save: bool, error: String }.
	Dictionary boot(const String &existing_save_json, const String &fallback_world_snapshot_json,
			const Dictionary &options);

	bool start_new_game(const String &world_snapshot_json, const Dictionary &options);
	bool load_from_save(const String &save_json);

	bool is_loaded() const { return ctx_.is_loaded(); }
	String last_error() const { return String(last_error_.c_str()); }

	// ── World entity counts / accessors (what the spawn/AI consumers read) ─────

	Dictionary entity_counts() const;
	String world_id() const { return String(ctx_.world_id().c_str()); }
	String spawn_character_id(int index) const { return String(ctx_.spawn_character_id(index).c_str()); }

	// ── KB + systems ──────────────────────────────────────────────────────────

	// The live KB as Array[Dictionary]{predicate, args}.
	Array kb_facts() const;
	// Overwrite the live KB from a fact list (Array[Dictionary]{predicate, args}).
	void set_kb(const Array &facts);
	// Assert one ground fact (idempotent). `args` is Array[String|int|float].
	void assert_fact(const String &predicate, const Array &args);

	// Run the deterministic radiant tick; returns the asserted quest_offered facts.
	Array run_radiant_tick(int max_offering, int ticks);
	// Evaluate every objective-bearing quest; returns Array[Dictionary] transitions
	// { quest_id, completed, satisfied_objective_ids: Array[String] }.
	Array evaluate_all_quests();

	// ── Save output ────────────────────────────────────────────────────────────

	void commit_to_save() { ctx_.commit_to_save(); }
	String serialize_canonical() const { return String(ctx_.serialize_canonical().c_str()); }
	String compute_integrity() const { return String(ctx_.compute_integrity().c_str()); }
	String build_envelope(const String &insimul_version, const String &exported_at) const;
	String world_snapshot_integrity() const { return String(ctx_.world_snapshot_integrity().c_str()); }

protected:
	static void _bind_methods();

private:
	insimul::RuntimeContext ctx_;
	std::string last_error_;
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_RUNTIME_CORE_H
