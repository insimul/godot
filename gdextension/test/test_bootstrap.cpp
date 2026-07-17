// test_bootstrap.cpp — host tests for RuntimeContext, the Godot startup
// orchestrator (US-GC4).
//
// Exercises the full template-startup loop end-to-end, in the portable core, so
// the human Godot pass (VERIFICATION.md) is confirming an already-proven sequence
// rather than debugging it:
//
//   1. BOOT/RESUME parity — booting the golden v2-typical save resumes it,
//      migrates it up, and the world reports the golden entity counts (the same
//      numbers every runtime asserts). Baseline KB facts restore.
//   2. NEW-GAME + fallback — booting with no save (or a corrupt one) starts a
//      fresh game from the golden world snapshot without bricking startup.
//   3. FULL LOOP — new game on a world with a real objective + radiant quests:
//      radiant tick offers, an objective trigger completes the quest (fact-
//      asserting transition), the run is saved and reloaded with quest + radiant
//      state intact, and the worldSnapshot hash stays stable throughout.
//
// This is the Godot twin of packages/unreal/tools/verify-unreal/test_bootstrap.cpp.

#include "bootstrap.h"
#include "canonical_json.h"
#include "json_value.h"
#include "quest_system.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifndef INSIMUL_FIXTURE_DIR
#define INSIMUL_FIXTURE_DIR "."
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

NewGameOptions default_options() {
	NewGameOptions o;
	o.id = "save-gc4";
	o.user_id = "user-1";
	o.world_id = "fixture-world";
	o.name = "GC4 Boot";
	o.slot_index = 0;
	o.created_at = "2026-01-01T00:00:00.000Z";
	return o;
}

// Extract a SaveFile's worldSnapshot as a standalone JSON document.
std::string extract_world_snapshot(const std::string &save_json) {
	JsonParseResult parsed = parse_json(save_json);
	if (!parsed.ok || parsed.root == nullptr) return std::string();
	const JsonValue *world = parsed.root->find("worldSnapshot");
	if (world == nullptr) return std::string();
	return canonical_json_stringify(*world);
}

// ── 1. Boot/resume parity on the golden save ────────────────────────────────

void test_resume_parity() {
	std::printf("== boot resumes the golden save; entity counts match parity numbers ==\n");
	const std::string fixture_json = read_file(INSIMUL_FIXTURE_DIR, "v2-typical.json");

	RuntimeContext ctx;
	BootResult boot = ctx.boot(fixture_json, /*fallback*/ std::string(), default_options());
	check(boot.ok, "boot succeeds on the golden save");
	check(boot.resumed_save, "boot resumes the existing save (not a new game)");
	check(ctx.is_loaded(), "context is loaded after boot");

	// Golden v2-typical entity counts — the cross-runtime parity numbers.
	check(ctx.country_count() == 1, "1 country");
	check(ctx.settlement_count() == 1, "1 settlement");
	check(ctx.character_count() == 1, "1 character");
	check(ctx.lot_count() == 1, "1 lot");
	check(ctx.quest_count() == 1, "1 quest");
	check(ctx.rule_count() == 0, "0 rules");
	check(ctx.action_count() == 0, "0 actions");
	check(ctx.grammar_count() == 0, "0 grammars");
	check_str(ctx.world_id(), "fixture-world", "world id is fixture-world");

	// The save was v2; boot migrates it up to the current version.
	check(ctx.save().version() == SAVE_FILE_VERSION, "resumed save migrated to current version");

	// Baseline KB facts restore from currentState.prologFacts.
	check(ctx.kb().facts().size() == 2, "2 baseline prolog facts restored");

	// The spawn consumers read the character from the world source.
	check_str(ctx.spawn_character_id(0), "npc-shopkeeper", "spawn character id from world source");

	// worldSnapshot hash is stable across a currentState-only commit.
	const std::string hash_before = ctx.world_snapshot_integrity();
	check(!hash_before.empty(), "worldSnapshot hash computes");
	PrologFact marker;
	marker.predicate = "boot_marker";
	marker.args = {PrologArg::atom("resumed")};
	ctx.kb().assert_fact(marker);
	ctx.commit_to_save();
	check_str(ctx.world_snapshot_integrity(), hash_before, "worldSnapshot hash stable across KB commit");
}

// ── 2. New-game + corrupt-save fallback ─────────────────────────────────────

void test_new_game_fallback() {
	std::printf("== new game from the golden world; corrupt save falls back ==\n");
	const std::string fixture_json = read_file(INSIMUL_FIXTURE_DIR, "v2-typical.json");
	const std::string snapshot = extract_world_snapshot(fixture_json);
	check(!snapshot.empty(), "extracted worldSnapshot from fixture");

	// No existing save -> new game from the golden world.
	{
		RuntimeContext ctx;
		BootResult boot = ctx.boot(/*existing*/ std::string(), snapshot, default_options());
		check(boot.ok, "boot succeeds with no existing save");
		check(!boot.resumed_save, "boot starts a new game when no save exists");
		check(ctx.character_count() == 1, "new game loads the golden world (1 character)");
		check(ctx.kb().facts().empty(), "new game starts with an empty KB");
		check(ctx.save().version() == SAVE_FILE_VERSION, "new game is stamped at the current version");
	}

	// A corrupt save must not brick startup — it falls back to a new game.
	{
		const std::string corrupt = "{ this is not valid json";
		RuntimeContext ctx;
		BootResult boot = ctx.boot(corrupt, snapshot, default_options());
		check(boot.ok, "boot recovers from a corrupt save");
		check(!boot.resumed_save, "corrupt save falls back to a new game");
		check(ctx.character_count() == 1, "fallback new game loaded the golden world");
	}
}

// ── 3. The full loop: radiant, objective, save, reload ──────────────────────

void test_full_loop() {
	std::printf("== full loop: radiant tick, objective completion, save, reload ==\n");

	// A world with one real objective quest and two radiant quests.
	const std::string snapshot =
			"{\"world\":{\"id\":\"synth-world\",\"name\":\"Synth\",\"worldType\":\"language\","
			"\"gameType\":\"open\",\"targetLanguage\":\"en\",\"description\":\"\"},"
			"\"countries\":[],\"settlements\":[],\"characters\":[],\"lots\":[],\"quests\":["
			"{\"id\":\"q_main\",\"status\":\"active\",\"content\":"
			"\"quest(q_main, 'Main Quest', errand, easy, active).\\n"
			"quest_objective(q_main, 0, talk_to(npc_a)).\\n"
			"quest_completion(q_main, all_objectives_complete).\"},"
			"{\"id\":\"rq_1\",\"status\":\"available\",\"content\":"
			"\"quest(rq_1, 'R1', errand, easy, available).\\nquest_tag(rq_1, radiant).\"},"
			"{\"id\":\"rq_2\",\"status\":\"available\",\"content\":"
			"\"quest(rq_2, 'R2', errand, easy, available).\\nquest_tag(rq_2, radiant).\"}"
			"]}";

	RuntimeContext ctx;
	std::string err;
	check(ctx.start_new_game(snapshot, default_options(), err), "new game on the synthetic world");
	if (!ctx.is_loaded()) {
		std::fprintf(stderr, "  boot error: %s\n", err.c_str());
		return;
	}
	check(ctx.quest_count() == 3, "three world quests loaded");
	check(ctx.quests().size() == 3, "three quests hydrated at systems init");

	const std::string hash_before = ctx.world_snapshot_integrity();

	// Radiant tick: one offering per tick over two ticks -> both radiant quests.
	const std::vector<PrologFact> offered = ctx.run_radiant_tick(/*max_offering*/ 1, /*ticks*/ 2);
	check(offered.size() == 2, "radiant tick offers both radiant quests");
	check(ctx.kb().has("quest_offered", {PrologArg::atom("rq_1"), PrologArg::number(0)}),
			"rq_1 offered on tick 0");
	check(ctx.kb().has("quest_offered", {PrologArg::atom("rq_2"), PrologArg::number(1)}),
			"rq_2 offered on tick 1");

	// The main quest is not complete until its objective trigger fires.
	std::vector<QuestTransition> t1 = ctx.evaluate_all_quests();
	check(t1.size() == 1, "only the objective-bearing quest is evaluated");
	check(!t1.empty() && !t1[0].completed, "main quest incomplete before its trigger");

	// Assert the talk trigger, then re-evaluate -> the fact-asserting transition.
	PrologFact talked;
	talked.predicate = "talked_to";
	talked.args = {PrologArg::atom("player"), PrologArg::atom("npc_a")};
	ctx.kb().assert_fact(talked);
	std::vector<QuestTransition> t2 = ctx.evaluate_all_quests();
	check(!t2.empty() && t2[0].completed, "main quest completes when its objective triggers");
	check(ctx.kb().has("quest_complete", {PrologArg::atom("q_main")}),
			"quest_complete fact asserted on transition");

	// Save the run: commit KB -> currentState, then serialize.
	ctx.commit_to_save();
	const std::string saved = ctx.serialize_canonical();
	check_str(ctx.world_snapshot_integrity(), hash_before, "worldSnapshot hash stable after progress + commit");
	const std::vector<PrologFact> facts_before_reload = ctx.kb().facts();

	// Reload from the saved document and confirm state survives.
	RuntimeContext reloaded;
	check(reloaded.load_from_save(saved, err), "saved run reloads");
	check_str(QuestSystem::canonical_fact_list(reloaded.kb().facts()),
			QuestSystem::canonical_fact_list(facts_before_reload),
			"KB (quest + radiant facts) round-trips through save/reload");
	check_str(reloaded.world_snapshot_integrity(), hash_before, "worldSnapshot hash stable across save/reload");
	check(reloaded.kb().has("quest_complete", {PrologArg::atom("q_main")}),
			"completed-quest fact survives reload");
	check(reloaded.kb().has("quest_offered", {PrologArg::atom("rq_2"), PrologArg::number(1)}),
			"radiant offering survives reload");
}

} // namespace

int main() {
	test_resume_parity();
	test_new_game_fallback();
	test_full_loop();

	std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
	if (g_failures == 0) {
		std::printf("PASS\n");
		return 0;
	}
	std::printf("FAIL\n");
	return 1;
}
