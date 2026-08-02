// test_quest_parity.cpp — the two-implementation diff (US-3 of tasklist 100).
//
// THE QUESTION THIS ANSWERS. US-2 adopted radiant generation, where this engine
// had NO prior implementation — so the `--source none` leg of the radiant gate
// shows only capability gain, and no regression is even constructible. That is
// an honest result but a weak diff. RUNTIME_CORE_ADOPTION.md §5.3 therefore
// promised a second, real one at near-zero cost: this repo ALREADY carries a
// hand-ported C++ implementation of quest hydration and the radiant tick
// (`gdextension/src/quest_system.cpp`, 649 lines — option D of §4.4), and core
// implements the same two things. Both are pinned by the SAME vendored vectors
// (`conformance/quests/{hydration,radiant}-cases.json`). Running both over those
// vectors in one harness is a genuine implementation-vs-implementation
// comparison, and it is the evidence needed to decide whether the hand-port can
// eventually retire.
//
// THREE LEGS, ONE CANONICALIZER. Each case is reduced to a canonical string by
// `canonical_json_stringify` / `QuestSystem::canonical_fact_list` — the SAME
// C++ functions for all three legs — so a difference is a semantic difference
// and never a serializer difference:
//
//   corpus  the committed `expected`, emitted by core's TS authority
//   cpp     gdextension/src/quest_system.cpp        (the hand-port that ships)
//   core    @insimul/core through libinsimulcore    (the adopted stack)
//
// Every case is classified, and the classification is printed:
//
//   AGREE       all three legs identical — nothing to decide
//   FIX         core matches the corpus, cpp does not (adoption corrects a bug)
//   SHAPE       cpp and core differ only in a way the corpus does not pin
//   REGRESSION  cpp matches the corpus, core does not — this BLOCKS the tasklist
//
// THE COUNT IS ASSERTED, NOT REPORTED, for the same reason as the radiant gate:
// this codebase has shipped gates that could not fail. Both corpus files must be
// present, the case count must clear a floor, and every case must be classified.
//
// `--source both|cpp` selects which legs run (default `both`). `cpp` runs the
// hand-port alone against the corpus and needs no libinsimulcore, no QuickJS and
// no libinsimul — it is the pre-adoption gate, kept runnable so the diff can be
// bisected when one of the two legs starts failing.

#include "canonical_json.h"
#include "json_value.h"
#include "quest_system.h"
#include "save_file.h"

extern "C" {
#include "insimulcore.h"
}

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#ifndef INSIMUL_QUESTS_DIR
#define INSIMUL_QUESTS_DIR "."
#endif

using namespace insimul;

// The corpus as vendored at adoption time: 4 hydration + 3 radiant cases.
// Growing it must not break the gate, shrinking it must.
static const int MIN_HYDRATION_CASES = 4;
static const int MIN_RADIANT_CASES = 3;

namespace {

int g_failures = 0;
int g_agree = 0, g_fix = 0, g_shape = 0, g_regression = 0;
int g_hydration_cases = 0, g_radiant_cases = 0;

void fail(const std::string &what) {
	++g_failures;
	std::fprintf(stderr, "  [FAIL] %s\n", what.c_str());
}

std::string read_file(const std::string &dir, const std::string &name, bool &ok) {
	const std::string path = dir + "/" + name;
	std::ifstream in(path, std::ios::binary);
	if (!in) {
		ok = false;
		return std::string();
	}
	std::ostringstream buffer;
	buffer << in.rdbuf();
	ok = true;
	return buffer.str();
}

enum class Verdict { Agree, Fix, Shape, Regression };

/**
 * The classification rule, as a pure function of the three canonical strings.
 *
 * Pure so it can be exercised directly by `self_test()` below: a classifier that
 * has only ever been shown agreeing inputs is a classifier nobody has proved can
 * disagree, and this repo has shipped gates that could not fail.
 */
Verdict verdict_of(const std::string &corpus, const std::string &cpp_out, const std::string &core_out) {
	const bool cpp_ok = cpp_out == corpus;
	const bool core_ok = core_out == corpus;
	if (cpp_ok && core_ok) return Verdict::Agree;
	if (!cpp_ok && core_ok) return Verdict::Fix;
	if (cpp_ok && !core_ok) return Verdict::Regression;
	// Neither matches the corpus: if the two implementations agree with each
	// OTHER the corpus itself is stale, otherwise both are wrong. Either way it
	// is not a shape change the corpus tolerates.
	return Verdict::Shape;
}

/**
 * Classify one case and report it.
 *
 * `have_core` is false when the core leg was not run (`--source cpp`), in which
 * case only the corpus-vs-cpp agreement is asserted and nothing is classified —
 * a leg that did not run must not be able to produce a green classification.
 */
void classify(const std::string &name, const std::string &corpus, const std::string &cpp_out,
		bool have_core, const std::string &core_out) {
	if (!have_core) {
		if (cpp_out == corpus) {
			std::printf("  ·  %-28s cpp matches corpus (core leg not run)\n", name.c_str());
		} else {
			fail(name + ": cpp differs from corpus\n    corpus: " + corpus + "\n    cpp:    " + cpp_out);
		}
		return;
	}

	switch (verdict_of(corpus, cpp_out, core_out)) {
		case Verdict::Agree:
			++g_agree;
			std::printf("  ✓  %-28s AGREE\n", name.c_str());
			return;
		case Verdict::Fix:
			++g_fix;
			std::printf("  ↑  %-28s FIX — core matches the corpus, the hand-port does not\n"
						"       corpus/core: %s\n       cpp:         %s\n",
					name.c_str(), corpus.c_str(), cpp_out.c_str());
			return;
		case Verdict::Regression:
			++g_regression;
			++g_failures;
			std::printf("  ✗  %-28s REGRESSION — the hand-port matches the corpus, core does not\n"
						"       corpus/cpp: %s\n       core:       %s\n",
					name.c_str(), corpus.c_str(), core_out.c_str());
			return;
		case Verdict::Shape:
			++g_shape;
			++g_failures;
			std::printf("  ✗  %-28s %s\n       corpus: %s\n       cpp:    %s\n       core:   %s\n",
					name.c_str(),
					cpp_out == core_out ? "BOTH DIFFER FROM CORPUS (identically) — the corpus is stale"
										: "BOTH DIFFER FROM CORPUS (differently)",
					corpus.c_str(), cpp_out.c_str(), core_out.c_str());
			return;
	}
}

/**
 * Prove the classifier can reach every verdict.
 *
 * Runs first, so a build in which the diff has collapsed to "everything agrees"
 * fails before it can print seven reassuring ticks.
 */
void self_test() {
	struct Sample {
		const char *label;
		const char *corpus, *cpp_out, *core_out;
		Verdict want;
	};
	static const Sample samples[] = {
		{ "agree", "A", "A", "A", Verdict::Agree },
		{ "fix", "A", "B", "A", Verdict::Fix },
		{ "regression", "A", "A", "B", Verdict::Regression },
		{ "shape (both differ, agreeing)", "A", "B", "B", Verdict::Shape },
		{ "shape (both differ, disagreeing)", "A", "B", "C", Verdict::Shape },
	};
	int reached = 0;
	for (const auto &s : samples) {
		if (verdict_of(s.corpus, s.cpp_out, s.core_out) == s.want) {
			++reached;
		} else {
			fail(std::string("classifier self-test: '") + s.label + "' did not classify as expected");
		}
	}
	std::printf("classifier self-test: %d/%zu verdicts reachable\n\n", reached,
			sizeof(samples) / sizeof(samples[0]));
}

/** Call a bridge method; returns false and reports on any failure. */
bool core_call(insimul_core *core, const char *method, const std::string &args, std::string &out) {
	const char *result = insimul_core_call(core, method, args.c_str());
	if (!result) {
		fail(std::string(method) + " failed: " + insimul_core_last_error(core));
		return false;
	}
	out = result;
	return true;
}

// ── hydration ──────────────────────────────────────────────────────────────

void run_hydration(const std::string &dir, insimul_core *core) {
	std::printf("== quest hydration — corpus vs quest_system.cpp vs core ==\n");
	bool ok = false;
	const std::string json = read_file(dir, "hydration-cases.json", ok);
	if (!ok) {
		fail("could not read hydration-cases.json");
		return;
	}
	JsonParseResult parsed = parse_json(json);
	if (!parsed.ok || !parsed.root) {
		fail("hydration-cases.json does not parse: " + parsed.error);
		return;
	}
	const JsonValue *cases = parsed.root->find("cases");
	if (!cases || !cases->is_array()) {
		fail("hydration-cases.json has no cases[]");
		return;
	}

	for (const auto &c : cases->array_items) {
		const std::string name = c->get_string("name");
		const JsonValue *input = c->find("input");
		const JsonValue *expected = c->find("expected");
		if (!input || !expected) {
			fail("case " + name + " is missing input/expected");
			continue;
		}
		++g_hydration_cases;

		const std::string content = input->get_string("content");
		const std::string status = input->get_string("status");
		const std::string corpus = canonical_json_stringify(*expected);
		const std::string cpp_out = QuestSystem::hydrate_canonical(content, status);

		std::string core_out;
		bool have_core = false;
		if (core) {
			// The whole "no engine type crosses into core" rule at the C level:
			// what goes across is a JSON object of strings.
			std::string args = "{\"content\":" + canonical_json_string(content);
			if (!status.empty()) args += ",\"status\":" + canonical_json_string(status);
			args += "}";
			std::string raw;
			if (!core_call(core, "quest.hydrate", args, raw)) continue;
			JsonParseResult got = parse_json(raw);
			const JsonValue *quest = (got.ok && got.root) ? got.root->find("quest") : nullptr;
			if (!quest) {
				fail(name + ": core returned no `quest` object: " + raw);
				continue;
			}
			// Re-canonicalized by the SAME serializer the other two legs use.
			core_out = canonical_json_stringify(*quest);
			have_core = true;
		}
		classify(name, corpus, cpp_out, have_core, core_out);
	}
}

// ── radiant tick ───────────────────────────────────────────────────────────

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

std::string facts_canonical(const JsonValue *arr) {
	std::vector<PrologFact> facts;
	if (arr && arr->is_array()) {
		for (const auto &f : arr->array_items) facts.push_back(fact_from_json(*f));
	}
	return QuestSystem::canonical_fact_list(facts);
}

void run_radiant(const std::string &dir, insimul_core *core) {
	std::printf("\n== radiant tick — corpus vs quest_system.cpp vs core ==\n");
	bool ok = false;
	const std::string json = read_file(dir, "radiant-cases.json", ok);
	if (!ok) {
		fail("could not read radiant-cases.json");
		return;
	}
	JsonParseResult parsed = parse_json(json);
	if (!parsed.ok || !parsed.root) {
		fail("radiant-cases.json does not parse: " + parsed.error);
		return;
	}
	const JsonValue *cases = parsed.root->find("cases");
	if (!cases || !cases->is_array()) {
		fail("radiant-cases.json has no cases[]");
		return;
	}

	for (const auto &c : cases->array_items) {
		const std::string name = c->get_string("name");
		const int max_offering = static_cast<int>(c->get_int("maxOffering"));
		const int ticks = static_cast<int>(c->get_int("ticks"));
		++g_radiant_cases;

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

		const std::string corpus = facts_canonical(c->find("expected"));
		const std::string cpp_out =
				QuestSystem::canonical_fact_list(QuestSystem::radiant_tick(quests, max_offering, ticks));

		std::string core_out;
		bool have_core = false;
		if (core) {
			std::string args = "{\"quests\":[";
			for (size_t i = 0; i < quests.size(); i++) {
				if (i) args += ",";
				args += "{\"id\":" + canonical_json_string(quests[i].id) + ",\"tags\":[";
				for (size_t t = 0; t < quests[i].tags.size(); t++) {
					if (t) args += ",";
					args += canonical_json_string(quests[i].tags[t]);
				}
				args += "],\"status\":" + canonical_json_string(quests[i].status) + "}";
			}
			args += "],\"maxOffering\":" + std::to_string(max_offering) +
					",\"ticks\":" + std::to_string(ticks) + "}";
			std::string raw;
			if (!core_call(core, "quest.radiantTick", args, raw)) continue;
			JsonParseResult got = parse_json(raw);
			const JsonValue *facts = (got.ok && got.root) ? got.root->find("facts") : nullptr;
			if (!facts || !facts->is_array()) {
				fail(name + ": core returned no `facts` array: " + raw);
				continue;
			}
			core_out = facts_canonical(facts);
			have_core = true;
		}
		classify(name, corpus, cpp_out, have_core, core_out);
	}
}

} // namespace

int main(int argc, char **argv) {
	std::string dir = INSIMUL_QUESTS_DIR;
	std::string source = "both";
	for (int i = 1; i < argc; i++) {
		if (std::strcmp(argv[i], "--source") == 0 && i + 1 < argc) source = argv[++i];
		else dir = argv[i];
	}
	if (source != "both" && source != "cpp") {
		std::fprintf(stderr, "usage: test_quest_parity [--source both|cpp] <conformance/quests dir>\n");
		return 2;
	}
	const bool want_core = source != "cpp";

	insimul_core *core = nullptr;
	if (want_core) {
		core = insimul_core_create();
		if (!core) {
			std::fprintf(stderr, "error: insimul_core_create() failed — the core bridge could not start\n");
			return 1;
		}
		std::printf("libinsimulcore %s\n", insimul_core_version());
		// The compared surface, asserted rather than assumed: a bundle that lost
		// these methods must fail here, not quietly report perfect agreement.
		const char *methods = insimul_core_call(core, "core.methods", nullptr);
		if (!methods) {
			std::fprintf(stderr, "error: core.methods failed: %s\n", insimul_core_last_error(core));
			insimul_core_destroy(core);
			return 1;
		}
		const std::string surface(methods);
		for (const char *needed : {"quest.hydrate", "quest.radiantTick"}) {
			if (surface.find(needed) == std::string::npos) {
				std::fprintf(stderr, "error: the bundle does not expose %s\n", needed);
				insimul_core_destroy(core);
				return 1;
			}
		}
		std::printf("compared surface: %s\n", methods);
	}
	std::printf("corpus: %s (source=%s)\n\n", dir.c_str(), source.c_str());

	self_test();
	run_hydration(dir, core);
	run_radiant(dir, core);

	if (core) insimul_core_destroy(core);

	// ── the gate cannot pass without having executed something ───────────────
	const int total = g_hydration_cases + g_radiant_cases;
	std::printf("\n%d case(s) executed: %d hydration + %d radiant\n", total, g_hydration_cases,
			g_radiant_cases);
	if (total == 0) {
		std::fprintf(stderr, "error: the gate executed ZERO cases\n");
		return 1;
	}
	if (g_hydration_cases < MIN_HYDRATION_CASES) {
		std::fprintf(stderr, "error: only %d hydration case(s), expected at least %d — the corpus shrank\n",
				g_hydration_cases, MIN_HYDRATION_CASES);
		++g_failures;
	}
	if (g_radiant_cases < MIN_RADIANT_CASES) {
		std::fprintf(stderr, "error: only %d radiant case(s), expected at least %d — the corpus shrank\n",
				g_radiant_cases, MIN_RADIANT_CASES);
		++g_failures;
	}

	if (want_core) {
		const int classified = g_agree + g_fix + g_shape + g_regression;
		std::printf("classification: %d AGREE, %d FIX, %d SHAPE, %d REGRESSION\n", g_agree, g_fix,
				g_shape, g_regression);
		if (classified != total) {
			std::fprintf(stderr, "error: %d case(s) executed but only %d classified\n", total, classified);
			++g_failures;
		}
		if (g_regression > 0) {
			std::fprintf(stderr, "error: %d REGRESSION(s) — a regression blocks adoption\n", g_regression);
		}
	}

	if (g_failures == 0) {
		std::printf("PASS\n");
		return 0;
	}
	std::printf("FAIL: %d\n", g_failures);
	return 1;
}
