// test_talos_bridge.cpp — the gate for `insimul-talos-bridge`, the third
// artifact of TALOS_INSIMUL_BRIDGE.md §7.5 (tasklist 183, US-1).
//
// ── WHAT IT PROVES, AND WHY EACH PART IS HERE ───────────────────────────────
//
//   1. PARITY WITH THE REFERENCE. `docs/REFUSE_AT_HELLO.md` exists so that "the
//      three per-engine adapters port a decision procedure instead of deriving
//      three that drift", and `scripts/engine-versions/check-hello.mjs` is that
//      procedure. Its own 21 cases are mirrored into fixtures/refuse-at-hello/
//      and replayed through this port; each case carries the verdict and the
//      token the reference produced, so a port that decides differently fails
//      here rather than in a joint run. The suite is TWO-SIDED by construction —
//      it contains an admitted hello and a restored archive — because a decision
//      procedure that refused everything would pass every refusal case.
//
//   2. THE CONTROLS. Parity with a corpus proves agreement, not sensitivity. So
//      two controls run after it, both from the reference's own selftest: the
//      SKEW control nudges one axis of the admitted hello and demands a refusal,
//      and the MATRIX control demotes an axis in the matrix and demands that the
//      SAME, untouched hello is then refused. The second is the one that matters:
//      it proves the decision is read from the published matrix rather than
//      baked into this build, which is §7.7's whole point.
//
//   3. THE §7.5 RULE, in the shape US-1 can prove it: a verb that needs the
//      knowledge base, asked before a world is live, is refused as
//      `insimul_kb_uninitialized` and never answered with an empty success. US-2
//      proves the addon's half of the same rule.
//
//   4. THE KB<->TBP MAPPING as data: the six groups of §7.4, the
//      `capabilities.insimul` payload of §3.1 (tier 1, `kb_authoritative`, and a
//      world half that is null until there IS a world), the checkpoint stamp
//      that makes an archive invalidatable at all, the §3.6 refusal of a write
//      to a world template, and §3.4's canonical sort before the digest cap.
//
//   5. NO UNPUBLISHED TOKEN. Every token this bridge can emit must appear in a
//      published vocabulary — the workspace matrix's 42 for the hello and
//      restore stages, the addon's contract for the verb stage. A refusal
//      carrying a token nobody published is a refusal a Conductor cannot act on.
//
// Builds with a plain C++ compiler: no cmake, no scons, no godot-cpp, no Godot
// binary, and — unlike the corpus gates — no libinsimul either, because nothing
// in the decision half touches a knowledge base.

#include "canonical_json.h"
#include "json_value.h"
#include "talos_bridge.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using insimul::JsonValue;
using insimul::JsonValuePtr;
using insimul::talos::Bridge;
using insimul::talos::Readings;

namespace {

// Floors, per the discipline the sibling gates use: growing the corpus must not
// break the gate; shrinking it must. 21 is what the reference publishes.
const int MIN_CASES = 21;
const int MIN_HELLO_CASES = 15;
const int MIN_ARCHIVE_CASES = 6;

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

void json_files(const std::filesystem::path &dir, std::vector<std::filesystem::path> &out) {
	if (!std::filesystem::is_directory(dir)) {
		return;
	}
	std::vector<std::filesystem::path> entries;
	for (const std::filesystem::directory_entry &entry : std::filesystem::directory_iterator(dir)) {
		entries.push_back(entry.path());
	}
	std::sort(entries.begin(), entries.end());
	for (std::size_t i = 0; i < entries.size(); ++i) {
		if (std::filesystem::is_directory(entries[i])) {
			json_files(entries[i], out);
		} else if (entries[i].extension() == ".json") {
			out.push_back(entries[i]);
		}
	}
}

JsonValuePtr parse_or_null(const std::string &text) {
	const insimul::JsonParseResult parsed = insimul::parse_json(text);
	return parsed.ok ? parsed.root : nullptr;
}

std::string field(const std::string &json, const std::string &key) {
	const JsonValuePtr root = parse_or_null(json);
	if (root == nullptr) {
		return std::string();
	}
	return root->get_string(key);
}

std::string sub_code(const std::string &json) {
	const JsonValuePtr root = parse_or_null(json);
	if (root == nullptr) {
		return std::string();
	}
	const JsonValue *error = root->find("error");
	const JsonValue *data = error == nullptr ? nullptr : error->find("data");
	return data == nullptr ? std::string() : data->get_string("sub_code");
}

bool retryable(const std::string &json) {
	const JsonValuePtr root = parse_or_null(json);
	if (root == nullptr) {
		return false;
	}
	const JsonValue *error = root->find("error");
	const JsonValue *data = error == nullptr ? nullptr : error->find("data");
	return data != nullptr && data->get_bool("retryable", false);
}

bool has_unblock(const std::string &json) {
	const JsonValuePtr root = parse_or_null(json);
	if (root == nullptr) {
		return false;
	}
	const JsonValue *error = root->find("error");
	const JsonValue *data = error == nullptr ? nullptr : error->find("data");
	if (data == nullptr) {
		return false;
	}
	const JsonValue *unblock = data->find("unblock");
	return unblock != nullptr && unblock->is_string() && !unblock->string_value.empty();
}

/// One replayed reference case: which matrix it points at, and what the
/// reference decided.
struct Case {
	std::string name;
	std::string matrix_json;
	std::string input_json;
	bool is_hello = false;
	std::string want_verdict;
	std::string want_token;
};

Readings sample_readings(bool kb_ready) {
	Readings r;
	r.engine = "godot";
	r.engine_version = "4.3.0";
	r.plugin_version = "0.1.0";
	r.core_version = "0.1.0";
	r.snapshot_version = "3.0";
	if (kb_ready) {
		r.kb_ready = true;
		r.world_id = "w-la-louisiane";
		r.seed = "la-louisiane";
		r.active_modules.push_back("combat");
		r.active_modules.push_back("quests");
	}
	return r;
}

} // namespace

int main(int argc, char **argv) {
	const std::filesystem::path repo = argc > 1 ? std::filesystem::path(argv[1])
											   : std::filesystem::current_path();
	const std::filesystem::path addon = repo / "addons" / "insimul_talos";
	const std::filesystem::path cases_dir = repo / "gdextension" / "test" / "fixtures" / "refuse-at-hello";

	const std::string contract_json = read_file(addon / "bridge-contract.json");
	const std::string matrix_json = read_file(addon / "supported-versions.json");
	if (contract_json.empty() || matrix_json.empty()) {
		std::printf("error: the bridge's shipped data files are missing under %s\n", addon.c_str());
		std::printf("       (bridge-contract.json, supported-versions.json)\n");
		return 1;
	}

	std::printf("insimul-talos-bridge: the decision half (TALOS_INSIMUL_BRIDGE.md §7.5)\n\n");

	Bridge bridge;
	check(bridge.configure(contract_json, matrix_json),
			"the bridge configures from its two shipped data files",
			bridge.error());

	// ── 1. Parity with the reference implementation ─────────────────────────
	std::printf("\nthe reference implementation's own cases, replayed\n");
	std::vector<std::filesystem::path> files;
	json_files(cases_dir, files);
	std::vector<Case> cases;
	for (std::size_t i = 0; i < files.size(); ++i) {
		const std::filesystem::path &file = files[i];
		if (file.parent_path().filename() == "matrix") {
			continue; // the synthetic matrices cases point at, not cases
		}
		const JsonValuePtr spec = parse_or_null(read_file(file));
		if (spec == nullptr) {
			fail("case " + file.filename().string() + " parses", "unreadable JSON");
			continue;
		}
		Case c;
		c.name = spec->get_string("case", file.filename().string());
		const std::string matrix_ref = spec->get_string("matrix");
		if (matrix_ref.empty() || matrix_ref == "published") {
			c.matrix_json = matrix_json;
		} else {
			c.matrix_json = read_file(std::filesystem::path(file).parent_path() / matrix_ref);
		}
		const JsonValue *hello = spec->find("hello");
		const JsonValue *archive = spec->find("archive");
		if (hello != nullptr) {
			c.is_hello = true;
			c.input_json = insimul::canonical_json_stringify(*hello);
		} else if (archive != nullptr) {
			c.input_json = insimul::canonical_json_stringify(*archive);
		} else {
			fail("case " + c.name + " declares an input", "neither hello nor archive");
			continue;
		}
		const JsonValue *expect = spec->find("expect");
		c.want_verdict = expect == nullptr ? std::string() : expect->get_string("verdict");
		c.want_token = expect == nullptr ? std::string() : expect->get_string("token");
		cases.push_back(c);
	}

	int hello_cases = 0;
	int archive_cases = 0;
	int admitted = 0;
	int restored = 0;
	std::set<std::string> tokens_exercised;
	for (std::size_t i = 0; i < cases.size(); ++i) {
		const Case &c = cases[i];
		// The case's matrix decides the CELL; the shipped mirror still supplies the
		// why-not vocabulary, so a synthetic matrix can move a cell without moving
		// the words a refusal is reported in.
		const std::string over = c.matrix_json == matrix_json ? std::string() : c.matrix_json;
		const std::string decided = c.is_hello ? bridge.evaluate_hello(c.input_json, over)
											   : bridge.evaluate_archive(c.input_json, over);
		const std::string verdict = field(decided, "verdict");
		const std::string token = field(decided, "token");
		if (c.is_hello) {
			hello_cases++;
		} else {
			archive_cases++;
		}
		if (verdict == "admit") {
			admitted++;
		}
		if (verdict == "restore") {
			restored++;
		}
		if (!token.empty()) {
			tokens_exercised.insert(token);
		}
		check(verdict == c.want_verdict && token == c.want_token,
				c.name,
				"expected " + c.want_verdict + (c.want_token.empty() ? "" : "/" + c.want_token) +
						", got " + verdict + (token.empty() ? "" : "/" + token));
	}

	check(static_cast<int>(cases.size()) >= MIN_CASES,
			"the mirrored suite still carries at least " + std::to_string(MIN_CASES) + " case(s)",
			"saw " + std::to_string(cases.size()));
	check(hello_cases >= MIN_HELLO_CASES, "hello cases still number at least " + std::to_string(MIN_HELLO_CASES),
			"saw " + std::to_string(hello_cases));
	check(archive_cases >= MIN_ARCHIVE_CASES, "archive cases still number at least " + std::to_string(MIN_ARCHIVE_CASES),
			"saw " + std::to_string(archive_cases));
	// The vacuity controls the reference's own selftest names: a gate that
	// refuses everything is exactly as informative as one that admits everything.
	check(admitted >= 1, "the suite ADMITS at least one hello", "admitted " + std::to_string(admitted));
	check(restored >= 1, "the suite RESTORES at least one archive", "restored " + std::to_string(restored));

	// ── 2. The controls ─────────────────────────────────────────────────────
	std::printf("\nthe controls — a decision that cannot refuse is not a decision\n");
	const std::filesystem::path admit_case = cases_dir / "hello" / "admit-supported-cell.json";
	const JsonValuePtr admit_spec = parse_or_null(read_file(admit_case));
	if (admit_spec == nullptr) {
		fail("the admitted case is readable", admit_case.string());
	} else {
		const std::string synthetic = read_file(cases_dir / "matrix" / "SYNTHETIC-supported-cell.json");
		const JsonValue *hello = admit_spec->find("hello");
		const std::string clean = insimul::canonical_json_stringify(*hello);
		check(field(bridge.evaluate_hello(clean, synthetic), "verdict") == "admit",
				"the untouched hello is admitted against the synthetic matrix",
				bridge.evaluate_hello(clean, synthetic));

		// SKEW CONTROL: one axis nudged, everything else identical.
		std::string nudged = clean;
		const std::string needle = "\"core_version\":\"0.1.0\"";
		const std::size_t at = nudged.find(needle);
		if (at == std::string::npos) {
			fail("the skew control can nudge an axis", "core_version not found in the case");
		} else {
			nudged.replace(at, needle.size(), "\"core_version\":\"0.2.0\"");
			const std::string decided = bridge.evaluate_hello(nudged, synthetic);
			check(field(decided, "token") == "insimul_c_abi_skew",
					"FATAL if admitted — the skew control: one axis nudged is refused",
					decided);
		}

		// MATRIX CONTROL: the same, untouched hello, against a matrix that demotes
		// an axis. This is the one that proves the decision is READ rather than
		// baked in.
		std::string demoted = synthetic;
		const std::string verified = "\"status\": \"verified\"";
		const std::size_t first = demoted.find(verified);
		if (first == std::string::npos) {
			fail("the matrix control can demote an axis", "no verified axis in the synthetic matrix");
		} else {
			demoted.replace(first, verified.size(), "\"status\": \"declared\"");
			const std::string decided = bridge.evaluate_hello(clean, demoted);
			check(field(decided, "verdict") == "refuse" &&
							field(decided, "token").find("_declared") != std::string::npos,
					"FATAL if admitted — the matrix control: demoting an axis refuses the same hello",
					decided);
		}
	}

	// ── 3. The §7.5 rule: never an empty success before the KB is live ──────
	std::printf("\nthe §7.5 rule — a state verb before a world is loaded\n");
	const Readings cold = sample_readings(false);
	const Readings warm = sample_readings(true);
	const std::string early = bridge.verb("query_state", cold);
	check(field(early, "verdict") == "refuse", "query_state before a world is REFUSED, not answered", early);
	check(sub_code(early) == "insimul_kb_uninitialized",
			"and the refusal carries the insimul_kb_uninitialized why-not token", sub_code(early));
	check(retryable(early), "and it is RETRYABLE — this is a warm-up, not a verdict about the game", early);
	check(has_unblock(early), "and it carries its unblock recipe (§2.11)", early);
	check(field(bridge.verb("query_state", warm), "verdict") == "admit",
			"the same verb is admitted once the world is live",
			bridge.verb("query_state", warm));

	// US-2's sharper claim, and the reason §7.5 exists at all: a Conductor must be
	// able to tell "the world has no such fact" from "there is no world yet". A
	// bridge that answered the early query with an empty solution set would make
	// those two the same document, and the Conductor would record a fact.
	{
		const JsonValuePtr refused = parse_or_null(early);
		const std::string empty = bridge.query_digest("[]");
		const JsonValuePtr answered = parse_or_null(empty);
		check(refused != nullptr && !refused->get_bool("ok", false) &&
						refused->find("solutions") == nullptr && refused->find("count") == nullptr,
				"the early refusal carries NO solution set — not an empty one", early);
		check(answered != nullptr && answered->get_bool("ok", false) &&
						answered->get_int("count", -1) == 0 && !answered->get_bool("overflow", true),
				"while a genuinely empty result IS an admitted success with zero solutions", empty);
		check(field(early, "verdict") != field(empty, "ok"),
				"so 'no facts' and 'no world yet' are different documents, which is the whole rule");
	}

	// ── 3b. §7.8: a half-present install names its failure MODE ─────────────
	std::printf("\na half-present install (§7.8)\n");
	{
		insimul::talos::InstallReadings whole;
		whole.extension_registered = true;
		whole.contract_json = contract_json;
		whole.matrix_json = matrix_json;
		whole.vocabulary_json = read_file(addon / "input-vocabulary.json");
		const std::string admitted = Bridge::diagnose_install(whole);
		check(field(admitted, "verdict") == "admit",
				"a whole install is diagnosed as one — otherwise every install would be broken",
				admitted);

		// Each mode, one missing or corrupt piece at a time. The token is what a
		// Conductor keys on and the failure_mode is what a human reads; a diagnosis
		// with only one of the two is half a diagnosis.
		std::vector<std::pair<std::string, insimul::talos::InstallReadings> > broken;
		insimul::talos::InstallReadings no_extension = whole;
		no_extension.extension_registered = false;
		broken.push_back({ "insimul_bridge_extension_absent", no_extension });
		insimul::talos::InstallReadings no_contract = whole;
		no_contract.contract_json.clear();
		broken.push_back({ "insimul_bridge_contract_absent", no_contract });
		insimul::talos::InstallReadings no_matrix = whole;
		no_matrix.matrix_json.clear();
		broken.push_back({ "insimul_bridge_matrix_absent", no_matrix });
		insimul::talos::InstallReadings no_vocabulary = whole;
		no_vocabulary.vocabulary_json.clear();
		broken.push_back({ "insimul_bridge_vocabulary_absent", no_vocabulary });
		insimul::talos::InstallReadings bad_contract = whole;
		bad_contract.contract_json = "{\"format\":\"something-else\"}";
		broken.push_back({ "insimul_bridge_contract_malformed", bad_contract });
		insimul::talos::InstallReadings bad_matrix = whole;
		bad_matrix.matrix_json = "{\"engines\":[]}";
		broken.push_back({ "insimul_bridge_matrix_malformed", bad_matrix });
		insimul::talos::InstallReadings bad_vocabulary = whole;
		bad_vocabulary.vocabulary_json = "{\"format\":\"not-the-vocabulary\"}";
		broken.push_back({ "insimul_bridge_vocabulary_malformed", bad_vocabulary });

		std::vector<std::string> wrong;
		for (std::size_t i = 0; i < broken.size(); ++i) {
			const std::string decided = Bridge::diagnose_install(broken[i].second);
			const JsonValuePtr root = parse_or_null(decided);
			if (root == nullptr || root->get_bool("ok", true)) {
				wrong.push_back(broken[i].first + ": a broken install was diagnosed as whole");
			} else if (root->get_string("token") != broken[i].first) {
				wrong.push_back(broken[i].first + ": named " + root->get_string("token") + " instead");
			} else if (root->get_string("failure_mode").empty() || root->get_string("message").empty() ||
					!has_unblock(decided)) {
				wrong.push_back(broken[i].first + ": named the mode without saying what installs it");
			}
		}
		check(broken.size() == Bridge::install_tokens().size() && wrong.empty(),
				"every way this artifact can be half-installed is NAMED, with what installs it",
				wrong.empty() ? std::string("the mode table and the cases disagree in number")
							  : wrong[0]);
		// The order is contract, not taste: two adapters looking at the same broken
		// install must name the same piece, or a Conductor aggregating install
		// failures across engines is counting two names for one fault.
		insimul::talos::InstallReadings nothing;
		check(field(Bridge::diagnose_install(nothing), "token") == "insimul_bridge_extension_absent",
				"and an install missing everything names the FIRST piece in decision order");
	}

	// ── 4. The mapping, as data ─────────────────────────────────────────────
	std::printf("\nthe KB<->TBP mapping\n");
	const std::vector<std::string> groups = bridge.groups();
	check(groups.size() == 6, "the contract registers the six groups of §7.4",
			"saw " + std::to_string(groups.size()));
	std::set<std::string> group_set(groups.begin(), groups.end());
	check(group_set.size() == groups.size(), "and every group name is distinct");

	const std::string caps_cold = bridge.capabilities(cold);
	const JsonValuePtr caps_cold_v = parse_or_null(caps_cold);
	check(caps_cold_v != nullptr && caps_cold_v->find("world_id") != nullptr &&
					caps_cold_v->find("world_id")->is_null(),
			"capabilities.insimul reports a NULL world before one is loaded", caps_cold);
	check(caps_cold_v != nullptr && !caps_cold_v->get_bool("kb_ready", true),
			"and declares kb_ready false rather than omitting it", caps_cold);
	const JsonValuePtr caps_warm = parse_or_null(bridge.capabilities(warm));
	check(caps_warm != nullptr && caps_warm->get_string("world_id") == "w-la-louisiane",
			"and the world half arrives once there is a world to read");
	check(caps_warm != nullptr && caps_warm->find("active_modules") != nullptr &&
					caps_warm->find("active_modules")->size() == 2,
			"active_modules is declared, so a Conductor can say 'not applicable' rather than 'unresponsive'");
	check(caps_warm != nullptr && caps_warm->get_int("checkpoint_tier", 0) == 1 &&
					caps_warm->get_string("checkpoint_fidelity") == "kb_authoritative",
			"the checkpoint claim is tier 1 / kb_authoritative — never the tier 2 a KB snapshot has not earned");

	const std::string hello_doc = bridge.hello(warm);
	const JsonValuePtr hello_v = parse_or_null(hello_doc);
	const JsonValue *hello_result = hello_v == nullptr ? nullptr : hello_v->find("result");
	const JsonValue *hello_caps = hello_result == nullptr ? nullptr : hello_result->find("capabilities");
	check(hello_caps != nullptr && hello_caps->find("insimul") != nullptr,
			"the bridge's own hello carries the capabilities.insimul block of §3.1", hello_doc);

	// The archive rule needs something to check, and TBP's save_checkpoint
	// response carries no version field — so an archive is unstamped, and
	// therefore uninvalidatable, unless the adapter stamps it itself.
	const JsonValuePtr stamp = parse_or_null(bridge.checkpoint_stamp(warm));
	check(stamp != nullptr && stamp->find("axes") != nullptr &&
					stamp->find("axes")->object_items.size() == 4,
			"talos_save stamps all four axes beside the checkpoint");
	check(stamp != nullptr && stamp->get_int("tier", 0) == 1, "and records the tier it really is");

	// Verb refusals, one per class, each with its own token.
	const std::string host_owned = bridge.verb("screenshot", warm);
	check(sub_code(host_owned) == "insimul_verb_host_owned",
			"a host-owned verb is refused as host-owned", sub_code(host_owned));
	const std::string unmapped = bridge.verb("play_input_trace", warm);
	check(sub_code(unmapped) == "insimul_verb_unmapped",
			"an unmapped verb is refused apart from a host-owned one — different fixes",
			sub_code(unmapped));
	const std::string unknown = bridge.verb("teleport_but_misspelled", warm);
	check(sub_code(unknown) == "insimul_verb_unknown",
			"an undeclared verb is refused rather than guessed at", sub_code(unknown));
	const std::string injected = bridge.verb("inject_input", warm);
	check(sub_code(injected) == "insimul_verb_host_owned",
			"inject_input is REFUSED — injecting at Insimul's action layer would manufacture "
			"the false green the consumption echo exists to prevent (§3.3)",
			sub_code(injected));
	const std::string inactive = bridge.verb("query_state", warm, "stealth");
	check(sub_code(inactive) == "insimul_module_inactive",
			"a verb about a module the genre never activated is 'not applicable', not 'unresponsive'",
			sub_code(inactive));
	check(field(bridge.verb("query_state", warm, "combat"), "verdict") == "admit",
			"and an ACTIVE module admits — the module gate is not a blanket refusal");

	// §3.6 — the write that would corrupt every future playthrough, invisibly.
	const std::string to_template = bridge.progress_var("quest.act", "3", true, warm);
	check(sub_code(to_template) == "insimul_world_template_write_refused",
			"set_progress_var against a world TEMPLATE is refused (§3.6)", sub_code(to_template));
	const std::string to_save = bridge.progress_var("quest.act", "3", false, warm);
	check(field(to_save, "verdict") == "admit", "and the same write to the playthrough is an assert order", to_save);
	check(sub_code(bridge.progress_var("quest.act", "3", false, cold)) == "insimul_kb_uninitialized",
			"and before a world is loaded it is refused for the §7.5 reason first");

	// §3.4 — the canonical sort before the cap.
	std::printf("\nthe query digest (§3.4)\n");
	const std::string forward = "[{\"x\":\"c\"},{\"x\":\"a\"},{\"x\":\"b\"}]";
	const std::string reversed = "[{\"x\":\"b\"},{\"x\":\"c\"},{\"x\":\"a\"}]";
	check(bridge.query_digest(forward) == bridge.query_digest(reversed),
			"two engines enumerating in different orders produce the SAME digest",
			bridge.query_digest(forward) + " vs " + bridge.query_digest(reversed));
	const JsonValuePtr uncapped = parse_or_null(bridge.query_digest(forward));
	check(uncapped != nullptr && !uncapped->get_bool("overflow", true) && uncapped->get_int("count", 0) == 3,
			"an uncapped digest keeps every solution and does not claim overflow");
	const JsonValuePtr capped = parse_or_null(bridge.query_digest(forward, 16));
	check(capped != nullptr && capped->get_bool("overflow", false),
			"a digest over the cap reports overflow rather than lying about completeness");
	check(capped != nullptr && capped->get_int("count", 0) >= 1 &&
					capped->get_int("dropped", 0) >= 1,
			"and says how many solutions it dropped");
	const JsonValuePtr capped_rev = parse_or_null(bridge.query_digest(reversed, 16));
	check(capped != nullptr && capped_rev != nullptr &&
					insimul::canonical_json_stringify(*capped) == insimul::canonical_json_stringify(*capped_rev),
			"and TRUNCATES deterministically — the sort happens before the cap, which is the "
			"whole of §3.4's correction");

	// ── 5. No unpublished token ─────────────────────────────────────────────
	std::printf("\nthe why-not vocabulary\n");
	const JsonValuePtr matrix = parse_or_null(matrix_json);
	const JsonValuePtr contract = parse_or_null(contract_json);
	const JsonValue *refuse_at_hello = matrix == nullptr ? nullptr : matrix->find("refuse_at_hello");
	const JsonValue *published = refuse_at_hello == nullptr ? nullptr : refuse_at_hello->find("tokens");
	const JsonValue *contract_tokens = contract == nullptr ? nullptr : contract->find("tokens");
	int unpublished = 0;
	std::string first_unpublished;
	const std::vector<std::string> tokens = bridge.tokens();
	for (std::size_t i = 0; i < tokens.size(); ++i) {
		const bool in_matrix = published != nullptr && published->find(tokens[i]) != nullptr;
		const bool in_contract = contract_tokens != nullptr && contract_tokens->find(tokens[i]) != nullptr;
		if (!in_matrix && !in_contract) {
			unpublished++;
			if (first_unpublished.empty()) {
				first_unpublished = tokens[i];
			}
		}
	}
	check(unpublished == 0,
			"every token this bridge can emit is published in a vocabulary",
			std::to_string(unpublished) + " unpublished, first: " + first_unpublished);
	check(tokens.size() >= 40, "and the vocabulary it can reach is the whole contract's",
			"saw " + std::to_string(tokens.size()));
	// Every token the replayed corpus produced must be one of them, which is what
	// makes the check above about REACHABLE tokens rather than a list.
	int corpus_unknown = 0;
	std::set<std::string> declared(tokens.begin(), tokens.end());
	for (std::set<std::string>::const_iterator it = tokens_exercised.begin(); it != tokens_exercised.end(); ++it) {
		if (declared.find(*it) == declared.end()) {
			corpus_unknown++;
		}
	}
	check(corpus_unknown == 0, "and every token the corpus exercised is one of them",
			std::to_string(corpus_unknown) + " unaccounted for");

	// ── 6. A half-present install decides nothing ───────────────────────────
	std::printf("\na half-present install\n");
	Bridge empty;
	check(!empty.configure("", matrix_json), "a bridge with no contract refuses to configure");
	check(!empty.configured(), "and reports itself unconfigured");
	const std::string undecided = empty.verb("query_state", warm);
	check(sub_code(undecided) == "insimul_bridge_not_configured",
			"and answers nothing rather than defaulting to something", sub_code(undecided));
	check(field(undecided, "verdict") == "refuse", "as a refusal, never an empty success");
	Bridge wrong_file;
	check(!wrong_file.configure(matrix_json, matrix_json),
			"and a contract slot holding the wrong document is refused by format, not by shape");

	std::printf("\n%d check(s), %d failure(s)\n", checks, failures);
	if (failures > 0) {
		std::printf("FAILED\n");
		return 1;
	}
	std::printf("PASSED\n");
	return 0;
}
