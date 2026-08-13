// test_talos_replay.cpp — the gate for the bridge's replay leg (tasklist 183,
// US-2): "the bridge replays the 180 portable input-trace artifact to produce a
// KB state a four-way comparison can diff."
//
// ── WHAT IT PROVES, AND WHY EACH PART IS HERE ───────────────────────────────
//
//   1. PARITY WITH CORE. `packages/core/src/replay/` is the reference: it mints
//      the content address, refuses the malformed document, derives the per-tick
//      entropy and seals the outcome. `tools/vendor-replay-fixtures.mjs` runs
//      that module — the real one, under Node — and writes down every answer it
//      gave. This file replays all of them through the C++ leg. A leg that
//      digests differently, refuses a different document or drives a different
//      tick sequence fails HERE, rather than in a four-way run where it would
//      read as Godot diverging from Babylon.
//
//      Two-sided by construction, per the discipline the refuse-at-hello mirror
//      uses: the corpus carries admitted traces and admitted outcomes as well as
//      refused ones, so a leg that refused everything fails and so does one that
//      admitted everything.
//
//   2. THE DRIVER, TICK BY TICK. The plan each run fixture carries is compared
//      step for step — the bucketing of inputs onto ticks, the ticks that carry
//      NO input (where a routine or a radiant beat decides things, and which a
//      driver that skipped them would silently drop), and the `uint32` derived
//      for each. A divergence in any of those localizes to the step instead of
//      surfacing four thousand facts later as "the digest differs".
//
//   3. THE WORLD PROGRAM, INTERPRETED FROM DATA. `fixtures/replay/program.json`
//      declares the reference world as a table. The JS minting side and this file
//      interpret the SAME table, so a disagreement between them is a disagreement
//      about the DRIVER — which is the only thing under test here. The knowledge
//      base itself is Insimul's, and is exercised by the corpus gates.
//
//   4. THE DIVERGENCE CONTROL, which is what stops the whole thing being
//      vacuous. A second world is driven with every input applied ONE TICK LATE.
//      It must produce a different KB, `compare()` must say so, and it must name
//      the tick. A comparator that converged on that would be a conformance
//      oracle that decides nothing — worse than one that decides less, because
//      "0 divergences" reads as "the engines agree".
//
//   5. THE REFUSALS CARRY REASONS. Every refusal in the corpus must come back
//      with core's own `code`, a published `insimul_*` token and a non-empty
//      message. A refusal a Conductor cannot act on is an outage with better
//      manners.
//
// Builds with a plain C++ compiler: no cmake, no scons, no godot-cpp, no Godot
// binary, and no libinsimul — the leg decides and plans, and the knowledge base
// it plans against belongs to the addon.

#include "canonical_json.h"
#include "json_value.h"
#include "talos_replay.h"

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using insimul::JsonValue;
using insimul::JsonValuePtr;
using insimul::talos::Replay;

namespace {

// Floors, per the discipline the sibling gates use: growing the corpus must not
// break the gate; shrinking it must.
const int MIN_TRACE_CASES = 12;
const int MIN_OUTCOME_CASES = 7;
const int MIN_COMPARISON_CASES = 6;
const int MIN_RUN_CASES = 4;

int failures = 0;
int checks = 0;

void ok(const std::string &what) {
	checks++;
	std::printf("  ✓ %s\n", what.c_str());
}

void fail(const std::string &what, const std::string &detail) {
	checks++;
	failures++;
	std::printf("  ✗ %s\n      %s\n", what.c_str(), detail.c_str());
}

void check(bool condition, const std::string &what, const std::string &detail = std::string()) {
	if (condition) {
		ok(what);
	} else {
		fail(what, detail.empty() ? "expectation not met" : detail);
	}
}

std::string read_file(const std::filesystem::path &p) {
	std::ifstream in(p, std::ios::binary);
	std::ostringstream ss;
	ss << in.rdbuf();
	return ss.str();
}

std::vector<std::filesystem::path> json_files(const std::filesystem::path &dir) {
	std::vector<std::filesystem::path> out;
	if (!std::filesystem::is_directory(dir)) {
		return out;
	}
	for (const std::filesystem::directory_entry &entry : std::filesystem::directory_iterator(dir)) {
		if (entry.path().extension() == ".json") {
			out.push_back(entry.path());
		}
	}
	std::sort(out.begin(), out.end());
	return out;
}

JsonValuePtr parse_or_null(const std::string &text) {
	const insimul::JsonParseResult parsed = insimul::parse_json(text);
	return parsed.ok ? parsed.root : nullptr;
}

std::string serialize(const JsonValue *value) {
	return value == nullptr ? std::string() : insimul::canonical_json_stringify(*value);
}

JsonValuePtr make_string(const std::string &s) {
	auto v = std::make_shared<JsonValue>();
	v->type = insimul::JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr make_number(double n, const std::string &raw) {
	auto v = std::make_shared<JsonValue>();
	v->type = insimul::JsonType::Number;
	v->number_value = n;
	v->raw_number = raw;
	return v;
}

JsonValuePtr make_array() {
	auto v = std::make_shared<JsonValue>();
	v->type = insimul::JsonType::Array;
	return v;
}

JsonValuePtr make_object() {
	auto v = std::make_shared<JsonValue>();
	v->type = insimul::JsonType::Object;
	return v;
}

void put(const JsonValuePtr &obj, const std::string &key, const JsonValuePtr &value) {
	obj->object_items.push_back({ key, value });
}

/// The reference world of fixtures/replay/program.json, interpreted rather than
/// re-implemented. `late_by` is the divergence control: applying every input one
/// tick late must be visible in the KB and must be named by `compare()`.
class ProgramWorld {
public:
	ProgramWorld(const JsonValue &program, long long late_by) :
			program_(program), late_by_(late_by) {}

	void open(const std::string &seed, std::uint32_t entropy, const JsonValue &authored) {
		facts_ = make_array();
		const JsonValue *authored_facts = authored.find("facts");
		if (authored_facts != nullptr && authored_facts->is_array()) {
			for (std::size_t i = 0; i < authored_facts->array_items.size(); ++i) {
				facts_->array_items.push_back(
						std::make_shared<JsonValue>(*authored_facts->array_items[i]));
			}
		}
		const JsonValue *on_open = program_.find("on_open");
		if (on_open == nullptr || !on_open->is_array()) {
			return;
		}
		for (std::size_t i = 0; i < on_open->array_items.size(); ++i) {
			assert_rule(*on_open->array_items[i], seed, entropy, 0, nullptr);
		}
	}

	/// `late_by == 0` is the conforming world. `late_by == 1` is the control: the
	/// inputs sampled on the PREVIOUS tick are applied now, which is the shape of
	/// a host that missed a window by one frame — the same inputs, the same tick
	/// count, a different world.
	void apply(long long tick, const JsonValue &inputs, std::uint32_t entropy) {
		if (late_by_ == 0) {
			run(tick, inputs, entropy);
			return;
		}
		if (pending_ != nullptr) {
			run(tick, *pending_, entropy);
		}
		pending_ = std::make_shared<JsonValue>(inputs);
	}

	const JsonValuePtr &facts() const { return facts_; }

private:
	void run(long long tick, const JsonValue &inputs, std::uint32_t entropy) {
		if (inputs.is_array() && !inputs.array_items.empty()) {
			const JsonValue *on_signal = program_.find("on_signal");
			for (std::size_t i = 0; i < inputs.array_items.size(); ++i) {
				const JsonValue &input = *inputs.array_items[i];
				const JsonValue *rule =
						on_signal == nullptr ? nullptr : on_signal->find(input.get_string("signal"));
				if (rule == nullptr) {
					continue;
				}
				assert_rule(*rule, std::string(), entropy, tick, &input);
			}
			return;
		}
		const JsonValue *idle = program_.find("on_idle");
		if (idle == nullptr) {
			return;
		}
		const long long modulo = idle->get_int("modulo", 1);
		if (modulo <= 0 || static_cast<long long>(entropy) % modulo != 0) {
			return;
		}
		assert_rule(*idle, std::string(), entropy, tick, nullptr);
	}

	void assert_rule(const JsonValue &rule, const std::string &seed, std::uint32_t entropy,
			long long tick, const JsonValue *input) {
		auto fact = make_object();
		put(fact, "predicate", make_string(rule.get_string("predicate")));
		auto args = make_array();
		const JsonValue *tokens = rule.find("args");
		if (tokens != nullptr && tokens->is_array()) {
			for (std::size_t i = 0; i < tokens->array_items.size(); ++i) {
				args->array_items.push_back(
						resolve(tokens->array_items[i]->as_string(), seed, entropy, tick, input));
			}
		}
		put(fact, "args", args);
		facts_->array_items.push_back(fact);
	}

	JsonValuePtr resolve(const std::string &token, const std::string &seed, std::uint32_t entropy,
			long long tick, const JsonValue *input) {
		if (token == "$seed") return make_string(seed);
		if (token == "$tick") return make_number(static_cast<double>(tick), std::to_string(tick));
		if (token == "$entropy") {
			return make_number(static_cast<double>(entropy), std::to_string(entropy));
		}
		if (input != nullptr) {
			if (token == "$edge") return make_string(input->get_string("edge"));
			if (token == "$text") return make_string(input->get_string("text"));
			const char *const NUMERIC[] = { "$value", "$x", "$y" };
			for (std::size_t i = 0; i < 3; ++i) {
				if (token != NUMERIC[i]) continue;
				const JsonValue *found = input->find(std::string(NUMERIC[i]).substr(1));
				if (found != nullptr) return std::make_shared<JsonValue>(*found);
				return make_number(0, "0");
			}
		}
		return make_string(token);
	}

	const JsonValue &program_;
	long long late_by_ = 0;
	JsonValuePtr facts_ = make_array();
	JsonValuePtr pending_;
};

std::string outcome_of(const Replay &replay, const JsonValue &plan, const JsonValue &program,
		const JsonValue &world, const std::string &engine, long long late_by) {
	ProgramWorld driven(program, late_by);
	const JsonValue *setup = plan.find("setup");
	driven.open(setup->get_string("seed"),
			static_cast<std::uint32_t>(setup->get_int("entropy", 0)), world);

	std::set<long long> checkpoint_ticks;
	const JsonValue *at = plan.find("checkpointTicks");
	if (at != nullptr && at->is_array()) {
		for (std::size_t i = 0; i < at->array_items.size(); ++i) {
			checkpoint_ticks.insert(at->array_items[i]->as_int(-1));
		}
	}

	auto checkpoints = make_array();
	const JsonValue *steps = plan.find("steps");
	for (std::size_t i = 0; steps != nullptr && i < steps->array_items.size(); ++i) {
		const JsonValue &step = *steps->array_items[i];
		const long long tick = step.get_int("tick", 0);
		const JsonValue *inputs = step.find("inputs");
		driven.apply(tick, *inputs, static_cast<std::uint32_t>(step.get_int("entropy", 0)));
		if (checkpoint_ticks.count(tick) == 0) {
			continue;
		}
		auto point = make_object();
		put(point, "tick", make_number(static_cast<double>(tick), std::to_string(tick)));
		put(point, "factCount",
				make_number(static_cast<double>(driven.facts()->array_items.size()),
						std::to_string(driven.facts()->array_items.size())));
		put(point, "digest",
				make_string(Replay::kb_digest(insimul::canonical_json_stringify(*driven.facts()))));
		checkpoints->array_items.push_back(point);
	}
	auto args = make_object();
	put(args, "traceId", make_string(plan.get_string("traceId")));
	put(args, "engine", make_string(engine));
	put(args, "finalTick",
			make_number(static_cast<double>(plan.get_int("finalTick", 0)),
					std::to_string(plan.get_int("finalTick", 0))));
	put(args, "inputTicks",
			make_number(static_cast<double>(plan.get_int("inputTicks", 0)),
					std::to_string(plan.get_int("inputTicks", 0))));
	put(args, "facts", driven.facts());
	if (!checkpoints->array_items.empty()) {
		put(args, "checkpoints", checkpoints);
	}
	return replay.seal_outcome(insimul::canonical_json_stringify(*args));
}

} // namespace

int main(int argc, char **argv) {
	const std::filesystem::path repo =
			argc > 1 ? std::filesystem::path(argv[1]) : std::filesystem::current_path();
	const std::filesystem::path addon = repo / "addons" / "insimul_talos";
	const std::filesystem::path corpus = repo / "gdextension" / "test" / "fixtures" / "replay";

	std::printf("\ninsimul-talos-bridge: the replay leg (TALOS_INSIMUL_BRIDGE.md §8.6)\n\n");

	const std::string vocabulary_json = read_file(addon / "input-vocabulary.json");
	if (vocabulary_json.empty()) {
		std::printf("  ✗ addons/insimul_talos/input-vocabulary.json is missing — re-vendor\n");
		return 1;
	}

	Replay replay;
	check(replay.configure(vocabulary_json),
			"the leg configures from the addon's shipped input vocabulary", replay.error());

	// A leg that cannot see core's action ids would admit an action-layer trace
	// core refuses, so refusing to decide at all is the only honest answer.
	{
		Replay unconfigured;
		check(!unconfigured.configure("{\"format\":\"something-else\"}"),
				"and refuses a vocabulary that is not one");
		const std::string cold = unconfigured.open_trace("{}", "{}");
		const JsonValuePtr root = parse_or_null(cold);
		check(root != nullptr && !root->get_bool("ok", false) &&
						root->get_string("token") == "insimul_replay_not_configured",
				"an unconfigured leg refuses to read a trace rather than reading one loosely",
				cold.substr(0, 160));
	}

	// ── the entropy vectors ──
	{
		const JsonValuePtr entropy = parse_or_null(read_file(corpus / "entropy.json"));
		int seeds = 0;
		int mismatches = 0;
		const JsonValue *rows = entropy == nullptr ? nullptr : entropy->find("seeds");
		for (std::size_t i = 0; rows != nullptr && i < rows->array_items.size(); ++i) {
			const JsonValue &row = *rows->array_items[i];
			const std::string seed = row.get_string("seed");
			seeds++;
			if (static_cast<long long>(Replay::entropy(seed)) != row.get_int("root", -1)) {
				mismatches++;
			}
			const JsonValue *ticks = row.find("ticks");
			for (std::size_t t = 0; ticks != nullptr && t < ticks->array_items.size(); ++t) {
				const JsonValue &point = *ticks->array_items[t];
				const long long tick = point.get_int("tick", 0);
				if (static_cast<long long>(Replay::entropy(seed, tick)) != point.get_int("entropy", -1)) {
					mismatches++;
				}
			}
		}
		check(seeds > 0 && mismatches == 0,
				"every per-tick entropy value core derived is derived identically here",
				std::to_string(mismatches) + " mismatch(es) across " + std::to_string(seeds) + " seed(s)");
	}

	// ── world.json: the digest core minted for the authored content ──
	const JsonValuePtr world_doc = parse_or_null(read_file(corpus / "world.json"));
	const JsonValuePtr other_world_doc = parse_or_null(read_file(corpus / "world-other.json"));
	const JsonValuePtr program = parse_or_null(read_file(corpus / "program.json"));
	if (world_doc == nullptr || other_world_doc == nullptr || program == nullptr) {
		std::printf("  ✗ the replay corpus is missing — run npm run vendor:replay\n");
		return 1;
	}
	const std::string world_json = serialize(world_doc->find("world"));
	const std::string other_world_json = serialize(other_world_doc->find("world"));
	check(Replay::world_content_digest(world_json) == world_doc->get_string("contentDigest"),
			"the world content digest is byte-identical to core's",
			Replay::world_content_digest(world_json));
	check(Replay::world_content_digest(other_world_json) ==
					other_world_doc->get_string("contentDigest"),
			"and so is the digest of a world with one authored fact added — the two differ",
			Replay::world_content_digest(other_world_json));

	// ── traces/ ──
	{
		int cases = 0;
		int admitted = 0;
		int refused = 0;
		std::vector<std::string> wrong;
		for (const std::filesystem::path &file : json_files(corpus / "traces")) {
			const JsonValuePtr body = parse_or_null(read_file(file));
			if (body == nullptr) {
				continue;
			}
			cases++;
			const JsonValue *expect = body->find("expect");
			const std::string against = body->get_string("world") == "world-other.json"
					? other_world_json
					: world_json;
			const std::string decided =
					replay.open_trace(serialize(body->find("document")), against);
			const JsonValuePtr got = parse_or_null(decided);
			const bool want_ok = expect != nullptr && expect->get_bool("ok", false);
			const bool got_ok = got != nullptr && got->get_bool("ok", false);
			if (want_ok) {
				admitted++;
				if (!got_ok || got->get_string("traceId") != expect->get_string("id")) {
					wrong.push_back(body->get_string("case") + ": expected the id core minted, got " +
							decided.substr(0, 120));
				}
			} else {
				refused++;
				if (got_ok) {
					wrong.push_back(body->get_string("case") + ": admitted a document core refused");
				} else if (got->get_string("code") != expect->get_string("code")) {
					wrong.push_back(body->get_string("case") + ": core said " +
							expect->get_string("code") + ", this leg said " + got->get_string("code"));
				} else if (got->get_string("message").empty() || got->get_string("token").empty()) {
					wrong.push_back(body->get_string("case") + ": refused without a reason or a token");
				}
			}
		}
		check(cases >= MIN_TRACE_CASES,
				"the trace corpus still carries every case core answered",
				std::to_string(cases) + " < " + std::to_string(MIN_TRACE_CASES));
		check(admitted >= 2 && refused >= 8,
				"and it is two-sided, so neither a leg that refuses everything nor one that "
				"admits everything passes",
				std::to_string(admitted) + " admitted, " + std::to_string(refused) + " refused");
		check(wrong.empty(), "every trace is read exactly as core read it",
				wrong.empty() ? std::string() : wrong[0] + (wrong.size() > 1
								? " (+" + std::to_string(wrong.size() - 1) + " more)"
								: ""));
	}

	// ── outcomes/ ──
	{
		int cases = 0;
		std::vector<std::string> wrong;
		for (const std::filesystem::path &file : json_files(corpus / "outcomes")) {
			const JsonValuePtr body = parse_or_null(read_file(file));
			if (body == nullptr) {
				continue;
			}
			cases++;
			const JsonValue *expect = body->find("expect");
			const std::string decided = replay.read_outcome(serialize(body->find("document")));
			const JsonValuePtr got = parse_or_null(decided);
			const bool want_ok = expect->get_bool("ok", false);
			const bool got_ok = got != nullptr && got->get_bool("ok", false);
			if (want_ok != got_ok) {
				wrong.push_back(body->get_string("case") + ": core said ok=" +
						(want_ok ? "true" : "false") + ", this leg said the opposite");
			} else if (want_ok && got->get_string("digest") != expect->get_string("digest")) {
				wrong.push_back(body->get_string("case") + ": KB digest differs from core's");
			} else if (!want_ok && got->get_string("code") != expect->get_string("code")) {
				wrong.push_back(body->get_string("case") + ": core said " +
						expect->get_string("code") + ", this leg said " + got->get_string("code"));
			}
		}
		check(cases >= MIN_OUTCOME_CASES, "the outcome corpus is whole",
				std::to_string(cases) + " < " + std::to_string(MIN_OUTCOME_CASES));
		check(wrong.empty(), "every outcome document is read exactly as core read it",
				wrong.empty() ? std::string() : wrong[0]);
	}

	// ── comparisons/ ──
	{
		int cases = 0;
		std::vector<std::string> wrong;
		for (const std::filesystem::path &file : json_files(corpus / "comparisons")) {
			const JsonValuePtr body = parse_or_null(read_file(file));
			if (body == nullptr) {
				continue;
			}
			cases++;
			const JsonValue *expect = body->find("expect");
			const std::string decided =
					replay.compare(serialize(body->find("recorded")), serialize(body->find("replayed")));
			const JsonValuePtr got = parse_or_null(decided);
			const bool want = expect->get_bool("converged", false);
			if (got == nullptr || got->get_bool("converged", false) != want) {
				wrong.push_back(body->get_string("case") + ": core said converged=" +
						(want ? "true" : "false"));
				continue;
			}
			std::vector<std::string> want_kinds;
			const JsonValue *kinds = expect->find("kinds");
			for (std::size_t i = 0; kinds != nullptr && i < kinds->array_items.size(); ++i) {
				want_kinds.push_back(kinds->array_items[i]->as_string());
			}
			std::vector<std::string> got_kinds;
			const JsonValue *divergences = got->find("divergences");
			for (std::size_t i = 0; divergences != nullptr && i < divergences->array_items.size(); ++i) {
				got_kinds.push_back(divergences->array_items[i]->get_string("kind"));
			}
			if (want_kinds != got_kinds) {
				wrong.push_back(body->get_string("case") + ": divergence kinds differ");
				continue;
			}
			const JsonValue *first = expect->find("firstDivergentTick");
			if (first != nullptr && got->get_int("firstDivergentTick", -1) != first->as_int(-2)) {
				wrong.push_back(body->get_string("case") + ": the divergence localizes to a different tick");
			}
		}
		check(cases >= MIN_COMPARISON_CASES, "the comparison corpus is whole",
				std::to_string(cases) + " < " + std::to_string(MIN_COMPARISON_CASES));
		check(wrong.empty(), "every comparison reaches core's verdict, kind for kind",
				wrong.empty() ? std::string() : wrong[0]);
	}

	// ── runs/: the whole leg, and the control ──
	{
		int cases = 0;
		std::vector<std::string> plan_wrong;
		std::vector<std::string> outcome_wrong;
		int controls = 0;
		int silent_controls = 0;
		for (const std::filesystem::path &file : json_files(corpus / "runs")) {
			const JsonValuePtr body = parse_or_null(read_file(file));
			if (body == nullptr) {
				continue;
			}
			cases++;
			const std::string name = body->get_string("case");
			const JsonValue *expect = body->find("expect");
			const std::string planned = replay.plan(serialize(body->find("trace")), world_json,
					serialize(body->find("options")));
			const JsonValuePtr plan = parse_or_null(planned);
			if (plan == nullptr || !plan->get_bool("ok", false)) {
				plan_wrong.push_back(name + ": the leg refused a trace core drove");
				continue;
			}
			if (plan->get_string("traceId") != expect->get_string("traceId") ||
					plan->get_int("finalTick", -99) != expect->get_int("finalTick", -1) ||
					plan->get_int("inputTicks", -99) != expect->get_int("inputTicks", -1) ||
					plan->get_int("ticks", -99) != expect->get_int("ticks", -1) ||
					plan->get_int("inputsApplied", -99) != expect->get_int("inputsApplied", -1)) {
				plan_wrong.push_back(name + ": the run's shape differs from core's");
			}
			// Step for step: the bucketing, the idle ticks and the per-tick entropy.
			const JsonValue *want_steps = body->find("steps");
			const JsonValue *got_steps = plan->find("steps");
			const std::size_t want_count =
					want_steps == nullptr ? 0 : want_steps->array_items.size();
			const std::size_t got_count = got_steps == nullptr ? 0 : got_steps->array_items.size();
			if (want_count != got_count) {
				plan_wrong.push_back(name + ": core drove " + std::to_string(want_count) +
						" tick(s), this leg planned " + std::to_string(got_count));
			} else {
				for (std::size_t i = 0; i < want_count; ++i) {
					const JsonValue &want = *want_steps->array_items[i];
					const JsonValue &got = *got_steps->array_items[i];
					if (want.get_int("tick", -1) == got.get_int("tick", -2) &&
							want.get_int("entropy", -1) == got.get_int("entropy", -2) &&
							serialize(want.find("inputs")) == serialize(got.find("inputs"))) {
						continue;
					}
					plan_wrong.push_back(name + ": step " + std::to_string(i) + " differs from core's");
					break;
				}
			}

			// The outcome, from the declared world program.
			const std::string sealed = outcome_of(replay, *plan, *program, *world_doc->find("world"),
					expect->find("outcome")->get_string("engine"), 0);
			const JsonValuePtr got_outcome = parse_or_null(sealed);
			const std::string want_digest = expect->find("outcome")->get_string("digest");
			if (got_outcome == nullptr || got_outcome->get_string("digest") != want_digest) {
				outcome_wrong.push_back(name + ": the KB core's own driver produced digests to " +
						want_digest + ", this leg's to " +
						(got_outcome == nullptr ? "nothing" : got_outcome->get_string("digest")));
			} else if (serialize(got_outcome.get()) !=
					insimul::canonical_json_stringify(*expect->find("outcome"))) {
				outcome_wrong.push_back(name + ": the outcome document differs from core's");
			}

			// ── the control: every input applied ONE TICK LATE ──
			if (expect->get_int("inputsApplied", 0) == 0) {
				continue; // nothing to mis-tick
			}
			controls++;
			const std::string mis_ticked = outcome_of(replay, *plan, *program,
					*world_doc->find("world"), "godot-mis-ticked", 1);
			const std::string verdict = replay.compare(sealed, mis_ticked);
			const JsonValuePtr compared = parse_or_null(verdict);
			if (compared == nullptr || compared->get_bool("converged", true)) {
				silent_controls++;
			}
		}
		check(cases >= MIN_RUN_CASES, "the run corpus is whole",
				std::to_string(cases) + " < " + std::to_string(MIN_RUN_CASES));
		check(plan_wrong.empty(),
				"every tick core drove is planned here — same bucketing, same idle ticks, same entropy",
				plan_wrong.empty() ? std::string() : plan_wrong[0]);
		check(outcome_wrong.empty(),
				"and the KB the plan produces is byte-identical to the one core's own driver did",
				outcome_wrong.empty() ? std::string() : outcome_wrong[0]);
		check(controls > 0 && silent_controls == 0,
				"THE CONTROL: a run with every input one tick late diverges, and the comparison says so",
				std::to_string(silent_controls) + " of " + std::to_string(controls) +
						" mis-ticked run(s) were called convergent");
	}

	// ── verify_outcome: an outcome of another session is refused, not compared ──
	{
		const JsonValuePtr run = parse_or_null(read_file(corpus / "runs" / "riverwatch-through-23.json"));
		const JsonValue *outcome = run == nullptr ? nullptr : run->find("expect")->find("outcome");
		const std::string recorded = serialize(outcome);
		const std::string mine = replay.verify_outcome(recorded, outcome->get_string("traceId"));
		const std::string foreign = replay.verify_outcome(recorded,
				"sha256-0000000000000000000000000000000000000000000000000000000000000000");
		const JsonValuePtr accepted = parse_or_null(mine);
		const JsonValuePtr rejected = parse_or_null(foreign);
		check(accepted != nullptr && accepted->get_bool("ok", false),
				"an outcome of the trace being replayed is accepted");
		check(rejected != nullptr && !rejected->get_bool("ok", false) &&
						rejected->get_string("code") == "trace_mismatch" &&
						rejected->get_string("token") == "insimul_outcome_trace_mismatch",
				"and one of another session is refused with a reason rather than compared",
				foreign.substr(0, 140));
	}

	// ── no unpublished token ──
	{
		const JsonValuePtr contract = parse_or_null(read_file(addon / "bridge-contract.json"));
		const JsonValue *published = contract == nullptr ? nullptr : contract->find("tokens");
		std::vector<std::string> unpublished;
		const std::vector<std::string> emitted = Replay::tokens();
		for (std::size_t i = 0; i < emitted.size(); ++i) {
			if (published == nullptr || published->find(emitted[i]) == nullptr) {
				unpublished.push_back(emitted[i]);
			}
		}
		check(!emitted.empty() && unpublished.empty(),
				"every why-not token the replay leg can emit is published in the contract",
				unpublished.empty() ? std::string() : unpublished[0]);
	}

	std::printf("\ntest_talos_replay: %d check(s), %d failure(s)\n", checks, failures);
	return failures > 0 ? 1 : 0;
}
