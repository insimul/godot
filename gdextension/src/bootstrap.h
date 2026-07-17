// bootstrap.h — the host-testable startup orchestrator for the Godot runtime
// (US-GC4).
//
// Ties the three portable cores established by US-GC1..GC3 into the single
// "full loop" the template startup path drives:
//
//     world source  ->  save slot  ->  KB  ->  systems init
//
//   - BOOT: prefer an existing save slot (integrity-checked, migrated up); if
//     there is none (or it is unreadable) start a NEW GAME from the golden world
//     snapshot. Either way we land in the same loaded state. A corrupt slot must
//     not brick startup — it falls back to a new game.
//   - REHYDRATE: from the (possibly migrated) SaveFile, restore the KB from
//     currentState.prologFacts and hydrate every world quest's Prolog content.
//   - COMMIT: snapshot the live KB back into currentState.prologFacts so a save
//     captures quest + radiant progress. The worldSnapshot is never mutated by a
//     currentState-only commit, so its integrity hash stays stable across the
//     save/reload boundary (the §5.2 B2 cross-runtime save-portability exit
//     criterion).
//
// std-only (no godot-cpp, no libinsimul) so the whole startup sequence runs under
// test/. This is the Godot twin of packages/unreal/Source/InsimulRuntime/Portable/
// InsimulBootstrap.{h,cpp} — same semantics, same golden fixtures. The godot-cpp
// shim (insimul_runtime_core.h) wraps this for GDScript; the GDScript runtime
// (addons/insimul/runtime/runtime_bootstrap.gd, class_name InsimulRuntime) drives
// the same loop against the live InsimulProlog KB + generated DTOs.
//
// Note: the Godot leg's world source (world_source.gd) is GDScript over the
// generated DTOs, so this core does not embed a C++ world source — it counts the
// world's entities directly off the loaded SaveFile's embedded worldSnapshot
// (json_value navigation). The entity counts are the same cross-runtime parity
// numbers every engine asserts.

#ifndef INSIMUL_GODOT_BOOTSTRAP_H
#define INSIMUL_GODOT_BOOTSTRAP_H

#include "quest_system.h" // QuestSystem, QuestKB, HydratedQuest, RadiantQuest
#include "save_file.h"     // SaveSystem, NewGameOptions, PrologFact

#include <string>
#include <vector>

namespace insimul {

// Outcome of a boot attempt — did we resume a save or start fresh?
struct BootResult {
	bool ok = false;
	// True if a valid existing save was resumed; false if a new game started.
	bool resumed_save = false;
	std::string error;
};

// The runtime context owned by the startup path. It is the single object the
// GDScript InsimulRuntime holds: after boot() it exposes the entity counts (for
// the spawn/AI consumers), the KB, the save system, and the hydrated quests (for
// the quest system).
class RuntimeContext {
public:
	// ── Full-loop entry points ──────────────────────────────────────────────

	// Start a fresh playthrough around `world_snapshot_json` (the golden world, or
	// a WorldIR export). Builds a current-version SaveFile, then rehydrates the
	// KB/quests from it. Returns false (with out_error) on malformed input.
	bool start_new_game(const std::string &world_snapshot_json, const NewGameOptions &options,
			std::string &out_error);

	// Resume from an existing SaveFile JSON document (migrating it up to the
	// current version), then rehydrate. Returns false (with out_error) if the save
	// is malformed or fails its version gate.
	bool load_from_save(const std::string &save_json, std::string &out_error);

	// The template startup decision: if `existing_save_json` is non-empty and loads
	// cleanly, resume it; otherwise start a new game from `fallback_world_snapshot_json`.
	// A save that is present but corrupt does NOT abort startup — it falls back to a
	// new game (resumed_save=false) so a bad slot never bricks the boot.
	BootResult boot(const std::string &existing_save_json,
			const std::string &fallback_world_snapshot_json, const NewGameOptions &options);

	// ── Systems ──────────────────────────────────────────────────────────────

	// Snapshot the live KB into currentState.prologFacts (call before serializing
	// a save so quest/radiant progress is captured).
	void commit_to_save();

	// Evaluate every hydrated quest against the KB, applying the fact-asserting
	// transitions. Returns the transitions that fired so the caller can broadcast
	// UI signals. Only objective-bearing quests are evaluated.
	std::vector<QuestTransition> evaluate_all_quests();

	// Run the deterministic radiant tick over the world's radiant-tagged quests and
	// assert the offering facts into the KB. Returns the asserted facts.
	std::vector<PrologFact> run_radiant_tick(int max_offering, int ticks);

	// ── Save output ────────────────────────────────────────────────────────────

	std::string serialize_canonical() const { return save_sys_.serialize_canonical(); }
	std::string compute_integrity() const { return save_sys_.compute_integrity(); }
	std::string build_envelope_json(const std::string &insimul_version, const std::string &exported_at) const {
		return save_sys_.build_envelope_json(insimul_version, exported_at);
	}

	// SHA-256 hex of the worldSnapshot alone. Stable across a currentState-only
	// commit + save/reload — the world-hash-stability parity check.
	std::string world_snapshot_integrity() const;

	// ── Accessors (what the spawn/quest consumers read) ───────────────────────

	bool is_loaded() const { return loaded_; }
	SaveSystem &save() { return save_sys_; }
	const SaveSystem &save() const { return save_sys_; }
	QuestKB &kb() { return kb_; }
	const QuestKB &kb() const { return kb_; }
	std::vector<HydratedQuest> &quests() { return hydrated_quests_; }
	const std::vector<HydratedQuest> &quests() const { return hydrated_quests_; }

	// Entity counts off the loaded worldSnapshot — the cross-runtime parity numbers.
	int country_count() const { return world_array_size("countries"); }
	int settlement_count() const { return world_array_size("settlements"); }
	int character_count() const { return world_array_size("characters"); }
	int lot_count() const { return world_array_size("lots"); }
	int quest_count() const { return world_array_size("quests"); }
	int rule_count() const { return world_array_size("rules"); }
	int action_count() const { return world_array_size("actions"); }
	int grammar_count() const { return world_array_size("grammars"); }

	// The world id off the loaded worldSnapshot.world.id.
	std::string world_id() const;

	// The id of spawn character #index (the world source the spawner reads), or "".
	std::string spawn_character_id(int index) const;

private:
	// (Re)build KB + hydrated quests from the current SaveFile.
	bool rehydrate(std::string &out_error);

	// The loaded SaveFile's embedded worldSnapshot node (nullptr if not loaded).
	const JsonValue *world_snapshot() const;
	int world_array_size(const std::string &key) const;

	bool loaded_ = false;
	SaveSystem save_sys_;
	QuestKB kb_;
	std::vector<HydratedQuest> hydrated_quests_;
};

} // namespace insimul

#endif // INSIMUL_GODOT_BOOTSTRAP_H
