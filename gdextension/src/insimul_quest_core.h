// insimul_quest_core.h — the Godot-facing GDExtension class for the portable
// quest core (US-GC3).
//
// InsimulQuestCore (RefCounted) wraps the dependency-free quest core
// (quest_system.h) and exposes hydration, the radiant tick, and query-driven
// completion / fact-asserting transitions to GDScript. The parity that matters —
// hydration + radiant facts byte-identical to the TS semantics authority
// (packages/core/src/prolog/quest-hydrator.ts) — lives ENTIRELY in the host-tested
// core, so GDScript never re-implements it.
//
// Named InsimulQuestCore (not InsimulQuestSystem) to leave the class_name
// InsimulQuestSystem free for the GDScript runtime (addons/insimul/runtime/
// quest_system.gd), mirroring the InsimulSaveCodec / InsimulSaveSystem split.
//
// BUILD NOTE: requires godot-cpp headers. Not available in the Ralph harness (no
// scons/godot/godot-cpp), so this file is *syntax-gated* only — the real gate is
// the host test (test/run_quest_tests.sh). See README "Structural fallback".

#ifndef INSIMUL_GODOT_INSIMUL_QUEST_CORE_H
#define INSIMUL_GODOT_INSIMUL_QUEST_CORE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include "quest_system.h"

namespace godot {

class InsimulQuestCore : public RefCounted {
	GDCLASS(InsimulQuestCore, RefCounted)

public:
	InsimulQuestCore() = default;
	~InsimulQuestCore() = default;

	// Hydrate Prolog `content` (+ optional runtime status) into the present-only
	// projection, returned as canonical JSON (parse in GDScript with JSON.parse).
	String hydrate_canonical(const String &content, const String &status) const;

	// Deterministic radiant distribution: `quests` is Array[Dictionary]{id, tags:
	// Array[String], status}; returns Array[Dictionary]{predicate, args} of the
	// asserted quest_offered facts.
	Array radiant_tick(const Array &quests, int max_offering, int ticks) const;

	// Evaluate a hydrated quest against a KB fact list (Array[Dictionary]{predicate,
	// args}). Returns a Dictionary { quest_id, completed, status,
	// satisfied_objective_ids: Array[String], facts: Array[Dictionary] } where
	// `facts` is the post-evaluation KB (the caller re-snapshots it into the save).
	Dictionary evaluate_quest(const String &content, const String &status, const Array &facts) const;

protected:
	static void _bind_methods();
};

} // namespace godot

#endif // INSIMUL_GODOT_INSIMUL_QUEST_CORE_H
