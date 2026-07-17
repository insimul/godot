// test_quest_system.cpp — host tests for the Godot portable quest core (US-GC3).
//
// The Godot twin of packages/unreal/tools/verify-unreal/test_quest_system.cpp.
// Covers the three quest guarantees ported from the TS semantics authority
// (packages/core/src/prolog/quest-hydrator.ts) and validated against the shared
// golden corpus under packages/core/conformance/quests:
//
//   1. HYDRATION parity — every case in hydration-cases.json hydrates to the
//      committed `expected` projection byte-for-byte (the same projection
//      hydrateQuestFromProlog + projectHydratedQuest produce TS-side).
//   2. RADIANT parity — every case in radiant-cases.json distributes to the
//      committed `expected` facts (order-independent multiset).
//   3. Query-driven completion + fact-asserting transitions on the KB, and a
//      save round-trip that preserves quest + radiant facts while the
//      worldSnapshot hash stays stable.
//
// Compiled + run by test/run_quest_tests.sh with a plain C++ toolchain (no
// godot-cpp/libinsimul). This is THE US-GC3 gate on the Ralph box.

#include "canonical_json.h"
#include "json_value.h"
#include "quest_system.h"
#include "save_file.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifndef INSIMUL_FIXTURE_DIR
#define INSIMUL_FIXTURE_DIR "."
#endif
#ifndef INSIMUL_QUESTS_DIR
#define INSIMUL_QUESTS_DIR "."
#endif

using namespace insimul;

namespace {

int g_failures = 0;
int g_checks = 0;

void check(bool condition, const char *message) {
	++g_checks;
	if (!condition) {
		++g_failures;
		std::fprintf(stderr, "  [FAIL] %s\n", message);
	}
}

void check_str(const std::string &actual, const std::string &expected, const std::string &message) {
	++g_checks;
	if (actual != expected) {
		++g_failures;
		std::fprintf(stderr, "  [FAIL] %s\n    expected: %s\n    got:      %s\n", message.c_str(),
				expected.c_str(), actual.c_str());
	}
}

std::string read_file(const std::string &dir, const std::string &name) {
	const std::string path = dir + "/" + name;
	std::ifstream in(path, std::ios::binary);
	if (!in) {
		std::fprintf(stderr, "  [FAIL] could not open: %s\n", path.c_str());
		++g_failures;
		return std::string();
	}
	std::ostringstream buffer;
	buffer << in.rdbuf();
	return buffer.str();
}

// Convert a golden fact node {predicate, args:[...]} to a PrologFact.
PrologFact fact_from_json(const JsonValue &node) {
	PrologFact f;
	f.predicate = node.get_string("predicate");
	const JsonValue *args = node.find("args");
	if (args && args->is_array()) {
		for (const auto &a : args->array_items) {
			if (a->is_number()) f.args.push_back(PrologArg::number(a->as_number()));
			else f.args.push_back(PrologArg::atom(a->as_string()));
		}
	}
	return f;
}

// ── 1. Hydration parity ────────────────────────────────────────────────────

void test_hydration() {
	std::printf("== hydration parity (conformance/quests/hydration-cases.json) ==\n");
	const std::string json = read_file(INSIMUL_QUESTS_DIR, "hydration-cases.json");
	JsonParseResult parsed = parse_json(json);
	check(parsed.ok && parsed.root != nullptr, "hydration-cases.json parses");
	if (!parsed.ok || !parsed.root) return;

	const JsonValue *cases = parsed.root->find("cases");
	check(cases && cases->is_array() && cases->size() > 0, "hydration corpus has cases");
	if (!cases || !cases->is_array()) return;

	for (const auto &c : cases->array_items) {
		const std::string name = c->get_string("name");
		const JsonValue *input = c->find("input");
		const JsonValue *expected = c->find("expected");
		check(input != nullptr && expected != nullptr, ("case " + name + " well-formed").c_str());
		if (!input || !expected) continue;

		const std::string content = input->get_string("content");
		const std::string status = input->get_string("status");
		const std::string produced = QuestSystem::hydrate_canonical(content, status);
		const std::string golden = canonical_json_stringify(*expected);
		check_str(produced, golden, "hydration " + name + " matches golden projection");
	}
}

// ── 2. Radiant parity ──────────────────────────────────────────────────────

void test_radiant() {
	std::printf("== radiant parity (conformance/quests/radiant-cases.json) ==\n");
	const std::string json = read_file(INSIMUL_QUESTS_DIR, "radiant-cases.json");
	JsonParseResult parsed = parse_json(json);
	check(parsed.ok && parsed.root != nullptr, "radiant-cases.json parses");
	if (!parsed.ok || !parsed.root) return;

	const JsonValue *cases = parsed.root->find("cases");
	check(cases && cases->is_array() && cases->size() > 0, "radiant corpus has cases");
	if (!cases || !cases->is_array()) return;

	for (const auto &c : cases->array_items) {
		const std::string name = c->get_string("name");
		const int max_offering = static_cast<int>(c->get_int("maxOffering"));
		const int ticks = static_cast<int>(c->get_int("ticks"));

		std::vector<RadiantQuest> quests;
		const JsonValue *quests_node = c->find("quests");
		if (quests_node && quests_node->is_array()) {
			for (const auto &q : quests_node->array_items) {
				RadiantQuest rq;
				rq.id = q->get_string("id");
				rq.status = q->get_string("status");
				const JsonValue *tags = q->find("tags");
				if (tags && tags->is_array()) {
					for (const auto &t : tags->array_items) rq.tags.push_back(t->as_string());
				}
				quests.push_back(rq);
			}
		}

		const std::vector<PrologFact> produced =
			QuestSystem::radiant_tick(quests, max_offering, ticks);

		std::vector<PrologFact> expected_facts;
		const JsonValue *expected = c->find("expected");
		if (expected && expected->is_array()) {
			for (const auto &f : expected->array_items) expected_facts.push_back(fact_from_json(*f));
		}

		check_str(QuestSystem::canonical_fact_list(produced),
				QuestSystem::canonical_fact_list(expected_facts),
				"radiant " + name + " facts match golden");
	}
}

// ── 3. Query-driven completion + fact-asserting transitions ────────────────

void test_completion() {
	std::printf("== query-driven completion + fact-asserting transitions ==\n");
	const std::string content =
		"quest(q_c, 'Two Steps', errand, easy, active).\n"
		"quest_objective(q_c, 0, talk_to(npc_x)).\n"
		"quest_objective(q_c, 1, visit_location('Square')).";

	HydratedQuest q = QuestSystem::hydrate_from_content(content);
	check(q.id == "q_c", "quest id parsed from content");
	check(q.objectives.size() == 2, "two objectives hydrated");

	// Partial: only the talk objective is triggered.
	QuestKB kb;
	PrologFact talked; talked.predicate = "talked_to";
	talked.args = {PrologArg::atom("player"), PrologArg::atom("npc_x")};
	kb.assert_fact(talked);

	QuestTransition t1 = QuestSystem::evaluate_quest(q, kb);
	check(!t1.completed, "quest not complete with one objective outstanding");
	check(t1.satisfied_objective_ids.size() == 1, "one objective satisfied");
	check(kb.has("quest_objective_complete",
			{PrologArg::atom("q_c"), PrologArg::atom("obj_0")}),
			"objective-complete fact asserted for obj_0");
	check(q.has_status && q.status == "active", "status stays active while incomplete");

	// Satisfy the second objective — the transition fires.
	PrologFact visited; visited.predicate = "visited";
	visited.args = {PrologArg::atom("player"), PrologArg::atom("Square")};
	kb.assert_fact(visited);

	QuestTransition t2 = QuestSystem::evaluate_quest(q, kb);
	check(t2.completed, "quest completes when all objectives satisfied");
	check(kb.has("quest_complete", {PrologArg::atom("q_c")}),
			"quest_complete fact asserted on transition");
	check(q.status == "completed", "status flipped active -> completed");

	// Idempotent: re-evaluating asserts nothing new (KB dedupes).
	const std::size_t before = kb.facts().size();
	QuestSystem::evaluate_quest(q, kb);
	check(kb.facts().size() == before, "re-evaluation is idempotent (KB dedupes)");
}

// ── 4. Save round-trip preserves quest + radiant state; hash stable ────────

void test_save_round_trip() {
	std::printf("== save round-trip preserves quest+radiant state; worldSnapshot hash stable ==\n");
	const std::string fixture_json = read_file(INSIMUL_FIXTURE_DIR, "v2-typical.json");
	SaveSystem save;
	std::string err;
	check(save.load(fixture_json, err), "v2-typical loads");
	if (!save.is_loaded()) return;

	// worldSnapshot hash BEFORE any KB mutation.
	const JsonValue *world_before = save.save_file()->find("worldSnapshot");
	check(world_before != nullptr, "save has worldSnapshot");
	const std::string hash_before = world_before ? canonical_json_integrity(*world_before) : std::string();

	// Build KB facts: existing prologFacts + quest completion + radiant offering.
	QuestKB kb;
	kb.load(save.restore_facts());
	const std::size_t base_fact_count = kb.facts().size();
	check(base_fact_count == 2, "fixture carries 2 baseline prolog facts");

	PrologFact complete; complete.predicate = "quest_complete";
	complete.args = {PrologArg::atom("quest-welcome")};
	kb.assert_fact(complete);

	std::vector<RadiantQuest> radiants = {
		{"rq_1", {"radiant"}, "available"},
		{"rq_2", {"radiant"}, "available"},
	};
	for (const auto &f : QuestSystem::radiant_tick(radiants, 1, 2)) kb.assert_fact(f);
	check(kb.facts().size() == base_fact_count + 3, "quest + 2 radiant facts added");

	// Snapshot into currentState.prologFacts and re-serialize.
	save.snapshot_facts(kb.facts());
	const std::string serialized = save.serialize_canonical();

	// worldSnapshot hash is unchanged by a currentState-only mutation.
	const JsonValue *world_after = save.save_file()->find("worldSnapshot");
	const std::string hash_after = world_after ? canonical_json_integrity(*world_after) : std::string();
	check_str(hash_after, hash_before, "worldSnapshot hash stable across KB mutation");

	// Reload and confirm the fact multiset round-trips intact.
	SaveSystem reloaded;
	check(reloaded.load(serialized, err), "re-serialized save reloads");
	const std::vector<PrologFact> round_tripped = reloaded.restore_facts();
	check_str(QuestSystem::canonical_fact_list(round_tripped),
			QuestSystem::canonical_fact_list(kb.facts()),
			"prolog facts round-trip through save/reload");

	// And the worldSnapshot hash survives the save/reload boundary.
	const JsonValue *world_reloaded = reloaded.save_file()->find("worldSnapshot");
	const std::string hash_reloaded = world_reloaded ? canonical_json_integrity(*world_reloaded) : std::string();
	check_str(hash_reloaded, hash_before, "worldSnapshot hash stable across save/reload");
}

} // namespace

int main() {
	test_hydration();
	test_radiant();
	test_completion();
	test_save_round_trip();

	std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
	if (g_failures == 0) {
		std::printf("PASS\n");
		return 0;
	}
	std::printf("FAIL\n");
	return 1;
}
