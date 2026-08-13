// test_corpus_conformance.cpp — the band-120 PARITY gate (tasklist 147, US-2).
//
// US-1 proved the seven decision layers are REACHABLE across the C ABI. This
// proves they are RIGHT: it executes core's own golden vectors — the corpora
// vendored under `conformance/` — in this engine, through the same bundle a
// shipped game loads, and compares every answer to the pinned one.
//
// ── WHY A SEPARATE GATE, AND WHY IT IS THE POINT OF THE STORY ───────────────
//
// A vendored corpus that nothing executes is a checked-in file. This repository
// has shipped that failure: at the start of tasklist 100 the vendored Prolog
// corpus was 41 of core's 76 cases, drifted from the source, with a manifest
// nobody checked and a harness that returned 0 on an empty directory. The
// vendoring half of US-2 is `tools/vendor-conformance.mjs`; this file is the
// half that makes the vendored bytes mean something.
//
// ── THE TWO HALVES OF PARITY, AND WHY NEITHER IS ENOUGH ─────────────────────
//
//   1. VOCABULARY — `conformance/prolog/*.json`, 255 cases. A KB and a query
//      with its solution set pinned. Run here through `prolog.run` on the
//      NATIVELY linked Trealla, which is a different engine BUILD from the
//      wasm32 one core's own runner uses. That difference is the whole reason
//      this half exists: `js/host-prolog-engine.js` asserts and retracts IN
//      PLACE where core's engine rebuilds the KB, and its header calls this
//      gate the thing that "holds the no-observable-divergence claim to
//      account". `assert-retract.json` is where a mechanism divergence would
//      surface first, and it is in the corpus.
//
//   2. DECISION — `conformance/{combat,stealth,traversal,skills,items,
//      routines}/`, 212 cases. What the damage was, which rung the guard is on,
//      which route was cheapest, what the sword sold for. NO Prolog corpus can
//      pin any of these, because no rule computes them (core says so in each
//      file's own description). Run through `conformance.run`.
//
// The marshalling gate (`run_conformance.sh`) is a third thing and stays: it
// DECODES every pinned solution through the extension's `prolog_value` layer
// without running a query. Decode-only would pass on an engine that answered
// everything wrong; run-only would pass on a build whose GDScript could not
// read the answer. See RUNTIME_CORE_ADOPTION.md §12.1.
//
// ── CLASSIFICATION, NOT AMENDMENT ───────────────────────────────────────────
//
// Every case lands in one of four buckets and the counts are printed:
//
//   AGREE     ran, and matched the pinned vector.
//   AMEND     did not run as authored, ran after ONE documented rewrite that
//             core's own runner and libinsimul's three harnesses also apply.
//             Unamended-first, always, so a stale amendment reports STALE.
//   DIVERGE   ran, and disagreed. A real parity failure — the diff is printed.
//   ERROR     could not run at all (consult/query/bridge failure).
//
// Only AGREE and AMEND are green. A divergence is never fixed by editing the
// corpus: the corpus is core's, vendored byte-for-byte, and amending a case to
// please this engine would erase the evidence in every other repo that reads
// the same file.

#include "canonical_json.h"
#include "json_value.h"

extern "C" {
#include "insimulcore.h"
}

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using insimul::JsonValue;
using insimul::JsonValuePtr;
using insimul::JsonType;

namespace {

// ── Floors. Growing the corpus must not break the gate; shrinking it must. ───
//
// These are the counts at core 84be9ad. They are duplicated from
// `tools/vendor-conformance.mjs`'s CASE_FLOORS on purpose: that one guards the
// vendored BYTES, this one guards what was EXECUTED, and a corpus can be
// present and skipped. Two numbers that must agree is the cheapest way to
// notice a runner that quietly stopped visiting a directory.
const int MIN_PROLOG_FILES = 21;
const int MIN_PROLOG_CASES = 255;
const int MIN_DECISION_AREAS = 18;
const int MIN_DECISION_CASES = 212;

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

/** Every `*.json` directly under `dir`, sorted, so a run is reproducible. */
std::vector<std::filesystem::path> json_files(const std::filesystem::path &dir) {
	std::vector<std::filesystem::path> files;
	if (!std::filesystem::is_directory(dir)) return files;
	for (const std::filesystem::directory_entry &entry : std::filesystem::directory_iterator(dir)) {
		if (entry.is_regular_file() && entry.path().extension() == ".json") files.push_back(entry.path());
	}
	std::sort(files.begin(), files.end());
	return files;
}

// ── The comparison ──────────────────────────────────────────────────────────

/**
 * Structural equality with JavaScript `toEqual` semantics, which is what core's
 * own runners compare with:
 *
 *  - objects match on their KEY SET, never on key order — the bridge answers in
 *    the order core's object literals happen to be written and the corpus was
 *    emitted from a different traversal, so an ordered compare would report
 *    hundreds of divergences that are not ones;
 *  - arrays are ordered, because every ordered collection in these corpora is a
 *    pinned tie-break (core's runners re-run each case REVERSED for exactly
 *    that reason);
 *  - numbers compare by VALUE, so `1` and `1.0` agree — JSON's lexeme is not
 *    the contract, IEEE-754 is.
 */
bool deep_equal(const JsonValue *a, const JsonValue *b) {
	if (a == nullptr || b == nullptr) return a == b;
	if (a->type != b->type) return false;
	switch (a->type) {
		case JsonType::Null:
			return true;
		case JsonType::Bool:
			return a->bool_value == b->bool_value;
		case JsonType::Number:
			return a->number_value == b->number_value;
		case JsonType::String:
			return a->string_value == b->string_value;
		case JsonType::Array: {
			if (a->array_items.size() != b->array_items.size()) return false;
			for (size_t i = 0; i < a->array_items.size(); i++) {
				if (!deep_equal(a->array_items[i].get(), b->array_items[i].get())) return false;
			}
			return true;
		}
		case JsonType::Object: {
			if (a->object_items.size() != b->object_items.size()) return false;
			for (const std::pair<std::string, JsonValuePtr> &kv : a->object_items) {
				const JsonValue *other = b->find(kv.first);
				if (other == nullptr) return false;
				if (!deep_equal(kv.second.get(), other)) return false;
			}
			return true;
		}
	}
	return false;
}

std::string show(const JsonValue *v) {
	if (v == nullptr) return "<absent>";
	std::string s = insimul::canonical_json_stringify(*v);
	// Long enough to see WHICH field moved, short enough that 200 failing cases
	// do not bury the summary.
	if (s.size() > 900) s = s.substr(0, 900) + "…";
	return s;
}

/** The first path at which two trees differ, e.g. `resolution.damage`. */
std::string first_difference(const JsonValue *a, const JsonValue *b, const std::string &at = "") {
	if (a == nullptr || b == nullptr || a->type != b->type) return at.empty() ? "<root>" : at;
	if (a->type == JsonType::Object) {
		for (const std::pair<std::string, JsonValuePtr> &kv : a->object_items) {
			const JsonValue *other = b->find(kv.first);
			if (other == nullptr) return at + (at.empty() ? "" : ".") + kv.first + " (missing on the other side)";
			if (!deep_equal(kv.second.get(), other)) {
				return first_difference(kv.second.get(), other, at + (at.empty() ? "" : ".") + kv.first);
			}
		}
		for (const std::pair<std::string, JsonValuePtr> &kv : b->object_items) {
			if (a->find(kv.first) == nullptr) {
				return at + (at.empty() ? "" : ".") + kv.first + " (missing on the other side)";
			}
		}
		return at;
	}
	if (a->type == JsonType::Array) {
		size_t n = std::min(a->array_items.size(), b->array_items.size());
		for (size_t i = 0; i < n; i++) {
			if (!deep_equal(a->array_items[i].get(), b->array_items[i].get())) {
				return first_difference(a->array_items[i].get(), b->array_items[i].get(),
						at + "[" + std::to_string(i) + "]");
			}
		}
		if (a->array_items.size() != b->array_items.size()) {
			return at + " (length " + std::to_string(a->array_items.size()) + " vs " +
					std::to_string(b->array_items.size()) + ")";
		}
		return at;
	}
	return at.empty() ? "<root>" : at;
}

// ── The bridge ──────────────────────────────────────────────────────────────

struct CallResult {
	bool ok = false;
	std::string error;
	JsonValuePtr root;
};

CallResult call(insimul_core *core, const char *method, const std::string &args) {
	CallResult out;
	const char *raw = insimul_core_call(core, method, args.empty() ? nullptr : args.c_str());
	if (raw == nullptr) {
		out.error = std::string(method) + " failed: " + insimul_core_last_error(core);
		return out;
	}
	insimul::JsonParseResult parsed = insimul::parse_json(raw);
	if (!parsed.ok) {
		out.error = std::string(method) + " returned unparseable JSON: " + parsed.error;
		return out;
	}
	out.ok = true;
	out.root = parsed.root;
	return out;
}

// ── Part 1: the Prolog vocabulary corpora ───────────────────────────────────

/**
 * The ONE documented rewrite, and the ONE place this gate deliberately follows
 * libinsimul rather than core.
 *
 * `assert-retract.json::asserta-prepends` uses `log/1` as a user dynamic
 * predicate. ISO reserves `log` only as an EVALUABLE FUNCTOR, so tau-prolog —
 * which the corpus was authored against — lets a program define `log/1`;
 * Trealla additionally registers the arithmetic functors as STATIC BUILTIN
 * predicates, so touching `log/1` raises permission_error. The case is about
 * asserta-before-assertz ORDERING and not about the name, so every leg renames
 * the predicate. None of them edits the corpus file: it is the source copy four
 * repositories vendor byte-identically, and amending it to please one engine
 * would erase the evidence in the other three.
 *
 * THE DIVERGENCE, recorded rather than smoothed over. Core's TS runner applies
 * ONE substitution (`log(` -> `entry(`) and leaves `:- dynamic(log/1).` in the
 * KB, because its wasm wrapper does not surface a failing DIRECTIVE as a failed
 * consult — the case only breaks there when the query runs. The natively linked
 * Trealla does surface it, so the directive raises at consult and the rename
 * has to reach the indicator too. libinsimul's own harness, which runs on this
 * same build, therefore lists TWO substitutions (`tests/conformance.c`:
 * `{"log(", "entry("}, {"log/", "entry/"}`), and this table matches THAT one.
 *
 * Which is the right lockstep to keep: this gate's engine is libinsimul's
 * engine. The mismatch is in where a directive error becomes visible, not in
 * what the program means — the amended case produces the corpus's pinned
 * solutions on both. Classified in RUNTIME_CORE_ADOPTION.md §12.3 as SHAPE
 * (the same answer reported at a different stage), not as a REGRESSION.
 */
struct Substitution {
	const char *from;
	const char *to;
};

struct Amendment {
	const char *key; // "<file>::<case name>"
	std::vector<Substitution> subs;
	const char *why;
};

const std::vector<Amendment> AMENDMENTS = {
	{
		"assert-retract.json::asserta-prepends",
		{ { "log(", "entry(" }, { "log/", "entry/" } },
		"`log` collides with Trealla's static builtin arithmetic functor log/1; renamed "
		"to preserve the asserta-before-assertz ordering the case is actually about. "
		"Two substitutions, not core's one, because the native engine reports the "
		"`:- dynamic(log/1).` directive as a failed CONSULT where the wasm wrapper only "
		"fails at the query — see the header.",
	},
};

std::string rewrite(const std::string &text, const Amendment &a) {
	std::string out = text;
	for (const Substitution &sub : a.subs) {
		const std::string from(sub.from);
		std::string next;
		size_t at = 0;
		while (true) {
			size_t hit = out.find(from, at);
			if (hit == std::string::npos) {
				next += out.substr(at);
				break;
			}
			next += out.substr(at, hit - at) + sub.to;
			at = hit + from.size();
		}
		out = next;
	}
	return out;
}

const Amendment *amendment_for(const std::string &key) {
	for (const Amendment &a : AMENDMENTS) {
		if (key == a.key) return &a;
	}
	return nullptr;
}

/** One binding set as a canonical, key-sorted string — core's `canon`. */
std::string canon_binding(const JsonValue *binding) {
	if (binding == nullptr || !binding->is_object()) return "<not-an-object>";
	std::vector<std::string> keys;
	for (const std::pair<std::string, JsonValuePtr> &kv : binding->object_items) keys.push_back(kv.first);
	std::sort(keys.begin(), keys.end());
	std::string out = "[";
	for (size_t i = 0; i < keys.size(); i++) {
		if (i > 0) out += ",";
		out += insimul::canonical_json_string(keys[i]) + ":" +
				insimul::canonical_json_stringify(*binding->find(keys[i]));
	}
	return out + "]";
}

/** Core's `sameSolutionSet`: an unordered MULTISET compare. */
bool same_solution_set(const JsonValue *actual, const JsonValue *expected, std::string &detail) {
	std::vector<std::string> a, e;
	if (actual != nullptr && actual->is_array()) {
		for (const JsonValuePtr &s : actual->array_items) a.push_back(canon_binding(s.get()));
	}
	if (expected != nullptr && expected->is_array()) {
		for (const JsonValuePtr &s : expected->array_items) e.push_back(canon_binding(s.get()));
	}
	std::sort(a.begin(), a.end());
	std::sort(e.begin(), e.end());
	if (a == e) return true;
	std::string got, want;
	for (const std::string &s : a) got += (got.empty() ? "" : " ") + s;
	for (const std::string &s : e) want += (want.empty() ? "" : " ") + s;
	detail = "got " + std::to_string(a.size()) + " solution(s) " + (got.empty() ? "{}" : got) +
			", corpus pins " + std::to_string(e.size()) + " " + (want.empty() ? "{}" : want);
	return false;
}

struct Tally {
	int agree = 0;
	int amended = 0;
	int diverged = 0;
	int errored = 0;
	int total() const { return agree + amended + diverged + errored; }
};

/** `{"kb": [...], "query": "..."}` for one case, honouring an amendment. */
std::string prolog_args(const JsonValue *c, const Amendment *a) {
	JsonValue payload;
	payload.type = JsonType::Object;
	const JsonValue *kb = c->find("kb");
	JsonValuePtr kb_copy = std::make_shared<JsonValue>();
	kb_copy->type = JsonType::Array;
	if (kb != nullptr && kb->is_array()) {
		for (const JsonValuePtr &line : kb->array_items) {
			JsonValuePtr s = std::make_shared<JsonValue>();
			s->type = JsonType::String;
			s->string_value = a == nullptr ? line->as_string() : rewrite(line->as_string(), *a);
			kb_copy->array_items.push_back(s);
		}
	}
	JsonValuePtr q = std::make_shared<JsonValue>();
	q->type = JsonType::String;
	q->string_value = a == nullptr ? c->get_string("query") : rewrite(c->get_string("query"), *a);
	payload.object_items.emplace_back("kb", kb_copy);
	payload.object_items.emplace_back("query", q);
	return insimul::canonical_json_stringify(payload);
}

void run_prolog_corpus(insimul_core *core, const std::filesystem::path &dir, Tally &tally,
		int &files_seen, std::set<std::string> &amendments_used) {
	std::printf("\nProlog vocabulary corpora — consulted and QUERIED on the native Trealla\n");
	for (const std::filesystem::path &file : json_files(dir)) {
		files_seen++;
		insimul::JsonParseResult doc = insimul::parse_json(read_file(file));
		if (!doc.ok || !doc.root->is_object()) {
			fail(file.filename().string(), "unparseable corpus file: " + doc.error);
			continue;
		}
		const JsonValue *cases = doc.root->find("cases");
		if (cases == nullptr || !cases->is_array()) {
			fail(file.filename().string(), "corpus file has no `cases` array");
			continue;
		}
		int agreed = 0;
		for (const JsonValuePtr &item : cases->array_items) {
			const JsonValue *c = item.get();
			const std::string name = c->get_string("name");
			const std::string key = file.filename().string() + "::" + name;

			// Unamended first, ALWAYS — that is what keeps the table honest: an
			// amendment that is no longer needed shows up as STALE below, and a
			// case that newly needs one shows up as ERROR rather than being
			// silently patched.
			CallResult res = call(core, "prolog.run", prolog_args(c, nullptr));
			bool amended = false;
			if (res.ok && !res.root->get_bool("ok")) {
				const Amendment *a = amendment_for(key);
				if (a != nullptr) {
					std::printf("  [AMEND] %s — %s: %s\n", key.c_str(),
							res.root->get_string("stage").c_str(), res.root->get_string("error").c_str());
					res = call(core, "prolog.run", prolog_args(c, a));
					amended = true;
					amendments_used.insert(key);
				}
			}
			if (!res.ok) {
				tally.errored++;
				fail(key, res.error);
				continue;
			}
			if (!res.root->get_bool("ok")) {
				tally.errored++;
				fail(key, res.root->get_string("stage") + " failed: " + res.root->get_string("error"));
				continue;
			}
			std::string detail;
			// An amended case is compared against its amended expectation.
			const JsonValue *expected = c->find("expected");
			JsonValuePtr amended_expected;
			if (amended) {
				const Amendment *a = amendment_for(key);
				insimul::JsonParseResult reparsed = insimul::parse_json(
						rewrite(insimul::canonical_json_stringify(*expected), *a));
				if (reparsed.ok) {
					amended_expected = reparsed.root;
					expected = amended_expected.get();
				}
			}
			if (same_solution_set(res.root->find("solutions"), expected, detail)) {
				if (amended) {
					tally.amended++;
				} else {
					tally.agree++;
				}
				agreed++;
			} else {
				tally.diverged++;
				fail(key, "DIVERGE: " + detail);
			}
		}
		std::printf("  ✓ %-32s %3d/%3zu case(s) agree\n", file.filename().string().c_str(), agreed,
				cases->array_items.size());
		checks++;
	}
}

// ── Part 2: the decision corpora ────────────────────────────────────────────

void run_decision_corpus(insimul_core *core, const std::filesystem::path &root, Tally &tally,
		std::set<std::string> &areas_run) {
	std::printf("\nDecision corpora — core's golden vectors, resolved by core, in this engine\n");
	// The six adopted modules with a decision corpus. `stamina` has none of its
	// own and says so in js/host-corpus.js; a directory added to conformance/
	// that is not listed here is caught by the area count, not by silence.
	const char *dirs[] = { "combat", "items", "routines", "skills", "stealth", "traversal" };
	for (const char *sub : dirs) {
		for (const std::filesystem::path &file : json_files(root / sub)) {
			insimul::JsonParseResult doc = insimul::parse_json(read_file(file));
			if (!doc.ok || !doc.root->is_object()) {
				fail(std::string(sub) + "/" + file.filename().string(),
						"unparseable corpus file: " + doc.error);
				continue;
			}
			const std::string area = doc.root->get_string("area");
			const JsonValue *cases = doc.root->find("cases");
			if (area.empty() || cases == nullptr || !cases->is_array()) {
				fail(std::string(sub) + "/" + file.filename().string(),
						"corpus file has no `area` or no `cases` array");
				continue;
			}
			areas_run.insert(area);
			int agreed = 0;
			for (const JsonValuePtr &item : cases->array_items) {
				const JsonValue *c = item.get();
				const std::string key = area + "::" + c->get_string("name");

				JsonValue payload;
				payload.type = JsonType::Object;
				JsonValuePtr area_v = std::make_shared<JsonValue>();
				area_v->type = JsonType::String;
				area_v->string_value = area;
				payload.object_items.emplace_back("area", area_v);
				payload.object_items.emplace_back("case", item);

				CallResult res = call(core, "conformance.run", insimul::canonical_json_stringify(payload));
				if (!res.ok) {
					tally.errored++;
					fail(key, res.error);
					continue;
				}
				const JsonValue *got = res.root->find("result");
				const JsonValue *want = c->find("expected");
				if (deep_equal(got, want)) {
					tally.agree++;
					agreed++;
				} else {
					tally.diverged++;
					fail(key, "DIVERGE at `" + first_difference(want, got) + "`\n        pinned: " +
									show(want) + "\n        got:    " + show(got));
				}
			}
			std::printf("  ✓ %-34s %3d/%3zu case(s) agree\n", area.c_str(), agreed,
					cases->array_items.size());
			checks++;
		}
	}
}

} // namespace

int main(int argc, char **argv) {
	std::filesystem::path corpus = argc > 1
			? std::filesystem::path(argv[1])
			: std::filesystem::path(__FILE__).parent_path().parent_path().parent_path() / "conformance";
	if (!std::filesystem::is_directory(corpus / "prolog")) {
		std::fprintf(stderr, "error: %s is not a conformance corpus (no prolog/)\n", corpus.string().c_str());
		return 2;
	}

	insimul_core *core = insimul_core_create();
	if (core == nullptr) {
		std::fprintf(stderr, "error: insimul_core_create() failed — the bundle did not evaluate\n");
		return 2;
	}
	std::printf("libinsimulcore %s, corpus %s\n", insimul_core_version(), corpus.string().c_str());

	// The build must SAY which corpora it can run before we believe a green
	// number: a runner that silently stopped visiting an area would otherwise
	// report "all cases agree" over a shrinking set.
	CallResult areas = call(core, "conformance.areas", "");
	std::set<std::string> declared;
	if (areas.ok) {
		const JsonValue *list = areas.root->find("areas");
		if (list != nullptr && list->is_array()) {
			for (const JsonValuePtr &a : list->array_items) declared.insert(a->as_string());
		}
	}
	check(!declared.empty(), "the build declares which decision corpora it can execute",
			areas.ok ? "conformance.areas returned no areas" : areas.error);

	Tally prolog_tally;
	Tally decision_tally;
	int prolog_files = 0;
	std::set<std::string> amendments_used;
	std::set<std::string> areas_run;

	run_prolog_corpus(core, corpus / "prolog", prolog_tally, prolog_files, amendments_used);
	run_decision_corpus(core, corpus, decision_tally, areas_run);

	std::printf("\nThe gate on the gate\n");

	check(prolog_files >= MIN_PROLOG_FILES,
			"the Prolog corpus still has at least " + std::to_string(MIN_PROLOG_FILES) + " file(s)",
			"saw " + std::to_string(prolog_files));
	check(prolog_tally.total() >= MIN_PROLOG_CASES,
			"the Prolog corpus still has at least " + std::to_string(MIN_PROLOG_CASES) + " case(s)",
			"ran " + std::to_string(prolog_tally.total()));
	check(static_cast<int>(areas_run.size()) >= MIN_DECISION_AREAS,
			"every one of the " + std::to_string(MIN_DECISION_AREAS) + " decision areas was executed",
			"ran " + std::to_string(areas_run.size()));
	check(decision_tally.total() >= MIN_DECISION_CASES,
			"the decision corpora still have at least " + std::to_string(MIN_DECISION_CASES) + " case(s)",
			"ran " + std::to_string(decision_tally.total()));

	// Every area the build DECLARES it can run must actually have been reached by
	// a vendored file, and every vendored area must be declared. The first
	// catches a corpus that was excluded from vendoring while its runner stayed;
	// the second catches a corpus vendored with nothing behind it — the exact
	// failure this story exists to close.
	std::string undeclared, unvisited;
	for (const std::string &a : areas_run) {
		if (declared.count(a) == 0) undeclared += (undeclared.empty() ? "" : ", ") + a;
	}
	for (const std::string &a : declared) {
		if (areas_run.count(a) == 0) unvisited += (unvisited.empty() ? "" : ", ") + a;
	}
	check(undeclared.empty(), "no vendored corpus ran through an undeclared runner", undeclared);
	check(unvisited.empty(),
			"every runner this build declares had a vendored corpus to run",
			"declared with no corpus: " + unvisited);

	// A stale amendment is a lie about the engine, so it fails like a divergence.
	std::string stale;
	for (const Amendment &a : AMENDMENTS) {
		if (amendments_used.count(a.key) == 0) stale += (stale.empty() ? "" : ", ") + std::string(a.key);
	}
	check(stale.empty(),
			"every listed amendment was still needed by the engine that ran",
			"STALE (the case now runs as authored — delete the entry): " + stale);

	insimul_core_destroy(core);

	std::printf("\nclassification\n");
	std::printf("  prolog vocabulary : %d AGREE, %d AMEND, %d DIVERGE, %d ERROR  (%d case(s), %d file(s))\n",
			prolog_tally.agree, prolog_tally.amended, prolog_tally.diverged, prolog_tally.errored,
			prolog_tally.total(), prolog_files);
	std::printf("  module decisions  : %d AGREE, %d AMEND, %d DIVERGE, %d ERROR  (%d case(s), %zu area(s))\n",
			decision_tally.agree, decision_tally.amended, decision_tally.diverged, decision_tally.errored,
			decision_tally.total(), areas_run.size());
	std::printf("\n%d check(s), %d failure(s)\n", checks, failures);
	if (failures > 0) {
		std::printf("FAILED\n");
		return 1;
	}
	std::printf("PASSED\n");
	return 0;
}
