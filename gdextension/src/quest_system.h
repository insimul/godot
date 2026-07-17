// quest_system.h — the host-testable, portable quest core for the Godot runtime
// (US-GC3).
//
// The Godot twin of packages/unreal/Source/InsimulRuntime/Portable/
// InsimulQuestSystem.{h,cpp} — same semantics, same golden corpus. Ported from the
// semantics authority in packages/core/src:
//
//   - Quest HYDRATION per prolog/quest-hydrator.ts: the quest's Prolog `content`
//     is the single source of truth; parsing it populates the structured fields
//     the engine reads (title, type, difficulty, status, objectives, rewards,
//     prerequisites, tags, completion criteria). Validated byte-for-byte against
//     the golden hydration corpus (packages/core/conformance/quests/
//     hydration-cases.json), which a vitest drift guard pins to
//     hydrateQuestFromProlog().
//
//   - QUERY-DRIVEN completion on the real KB (currentState.prologFacts, the same
//     ground-fact store the save system snapshots/restores): an objective is
//     complete when the KB contains its trigger fact; when all objectives are
//     satisfied the quest transition ASSERTS `quest_complete(questId)` and flips
//     status active -> completed (a fact-asserting transition).
//
//   - The RADIANT TICK: a deterministic distributor of side quests tagged
//     'radiant'. Validated byte-for-byte against the golden radiant corpus
//     (packages/core/conformance/quests/radiant-cases.json).
//
// std-only (no godot-cpp, no libinsimul) so the whole contract runs under test/
// with a plain clang toolchain. The godot-cpp shim (insimul_quest_core.h) wraps
// this for GDScript; the GDScript quest runtime (addons/insimul/runtime/
// quest_system.gd) drives it against a live InsimulProlog KB.

#ifndef INSIMUL_GODOT_QUEST_SYSTEM_H
#define INSIMUL_GODOT_QUEST_SYSTEM_H

#include "json_value.h"
#include "save_file.h" // PrologArg / PrologFact (the KB fact shape)

#include <cstddef>
#include <string>
#include <vector>

namespace insimul {

// ── Hydration output ────────────────────────────────────────────────────────

// A single hydrated objective — the present-only projection subset.
struct HydratedObjective {
	std::string id;
	std::string type;
	std::string description;
	double required_count = 1.0;
	bool has_target = false;
	std::string target;
	bool has_npc_id = false;
	std::string npc_id;
};

// A hydrated quest — the fields the engine reads, derived from Prolog content.
struct HydratedQuest {
	std::string id; // parsed from the quest/N head atom (not part of the projection)

	bool has_title = false;         std::string title;
	bool has_quest_type = false;    std::string quest_type;
	bool has_difficulty = false;    std::string difficulty;
	bool has_status = false;        std::string status;
	bool has_target_language = false; std::string target_language;
	bool has_assigned_to = false;   std::string assigned_to;
	bool has_assigned_by = false;   std::string assigned_by;
	bool has_experience = false;    double experience_reward = 0.0;

	std::vector<std::string> tags;
	std::vector<std::string> prerequisite_quest_ids;

	// Completion criteria (subset the corpus exercises).
	bool has_completion = false;
	std::string completion_type;             // "all_objectives" | "conversation_turns"
	bool has_completion_description = false;  std::string completion_description;
	bool has_completion_turns = false;        double completion_turns = 0.0;

	std::vector<HydratedObjective> objectives;

	// Build the present-only projection object (mirrors projectHydratedQuest).
	JsonValuePtr to_projection() const;
};

// ── The KB (ground-fact store the quest system queries / asserts into) ──────

// A thin ground-fact store over currentState.prologFacts. Assertions dedupe so a
// snapshot after repeated transitions is deterministic. This is the "real KB"
// surface the quest system drives; the native Prolog engine (InsimulProlog) plugs
// in behind the same assert/has query shape.
class QuestKB {
public:
	// Assert a ground fact (idempotent — duplicates are ignored).
	void assert_fact(const PrologFact &fact);

	// True if a fact with this predicate + exact args is present.
	bool has(const std::string &predicate, const std::vector<PrologArg> &args) const;

	const std::vector<PrologFact> &facts() const { return facts_; }
	void load(const std::vector<PrologFact> &facts) { facts_ = facts; }

private:
	std::vector<PrologFact> facts_;
};

// Result of evaluating a quest's completion against the KB.
struct QuestTransition {
	std::string quest_id;
	bool completed = false;               // all objectives satisfied this eval
	std::vector<std::string> satisfied_objective_ids;
};

// ── Radiant tick ────────────────────────────────────────────────────────────

// A radiant candidate: id + tags + current status.
struct RadiantQuest {
	std::string id;
	std::vector<std::string> tags;
	std::string status;
};

// ── The quest system ────────────────────────────────────────────────────────

class QuestSystem {
public:
	// Hydration ---------------------------------------------------------------

	// Parse Prolog `content` (+ optional runtime status) into a hydrated quest.
	static HydratedQuest hydrate_from_content(const std::string &content,
			const std::string &input_status = std::string());

	// Canonical JSON of the hydration projection — byte-comparable with TS.
	static std::string hydrate_canonical(const std::string &content,
			const std::string &input_status = std::string());

	// Query-driven completion + fact-asserting transitions --------------------

	// True if objective #index of `quest` is satisfied by the KB — either an
	// explicit `objective_satisfied(questId, objId)` fact or a type-specific
	// trigger fact (talk_to_npc -> talked_to, visit_location -> visited,
	// deliver_item -> delivered; player is the acting subject).
	static bool is_objective_satisfied(const HydratedQuest &quest, std::size_t index,
			const QuestKB &kb);

	// Evaluate `quest` against `kb`. Asserts `quest_objective_complete(questId,
	// objId)` for each satisfied objective; when ALL objectives are satisfied and
	// the completion criterion is all-objectives, asserts `quest_complete(questId)`
	// and flips quest.status to "completed" (the fact-asserting transition).
	static QuestTransition evaluate_quest(HydratedQuest &quest, QuestKB &kb);

	// Radiant tick ------------------------------------------------------------

	// Deterministic radiant distribution: over `ticks` ticks, offer up to
	// `max_offering` still-available radiant quests per tick (ascending id order,
	// never re-offering), asserting `quest_offered(questId, tick)` facts.
	static std::vector<PrologFact> radiant_tick(const std::vector<RadiantQuest> &quests,
			int max_offering, int ticks);

	// Canonical `predicate(arg0,arg1)` string for one ground fact.
	static std::string canonical_fact_string(const PrologFact &fact);

	// Order-independent canonical serialization of a fact multiset.
	static std::string canonical_fact_list(const std::vector<PrologFact> &facts);
};

} // namespace insimul

#endif // INSIMUL_GODOT_QUEST_SYSTEM_H
