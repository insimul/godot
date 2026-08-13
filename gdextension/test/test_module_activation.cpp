// test_module_activation.cpp — the genre-bundle ACTIVATION gate (tasklist 147,
// US-3).
//
// US-1 proved the seven decision layers are REACHABLE; US-2 proved they are
// RIGHT. This proves the plugin activates the ones a world actually selected —
// and, harder and more important, that a module it did NOT select contributes
// nothing.
//
// ── WHY EACH PART IS HERE ───────────────────────────────────────────────────
//
//   1. THE TABLE. `conformance/modules/genre-activation.json` is core's
//      committed genre -> active-module-set table, emitted from `INSIMUL_MODULES`
//      by core's own `moduleActivationTable()`. `modules.table` calls that same
//      function inside this build, so the vendored bytes and the shipped answer
//      have one definition between them and any difference is drift. A corpus
//      nothing executes is a checked-in file — this repository has shipped that,
//      and this file is the reason `modules/` could leave NOT_MIRRORED.
//
//   2. THE RESOLUTION, ONE GENRE AT A TIME. Every bundle in the table is
//      resolved through `modules.activate`, by genre id AND through a World IR's
//      `meta.genreConfig.id` (which is the path a game actually takes), and
//      deep-compared to the committed set. Core's three answers are kept apart,
//      because conflating any two is a different bug: a KNOWN genre gets what it
//      selects, an UNKNOWN genre gets the shared vocabulary and NOT every
//      mechanic in the build, and a host that declared NOTHING gets every pack —
//      right for a tool, a warning in a game.
//
//   3. THE WITNESS, IN A REAL KB. "An inactive module contributes nothing" is
//      not provable by reading a list back: it is a claim about a knowledge
//      base. So for every genre x every pack in the build, this consults exactly
//      the packs the active set names — through `prolog.packs` and the natively
//      linked Trealla — and asks `current_predicate/1` for that pack's SIGNATURE
//      predicate, one this build measured to be defined by that pack and by no
//      other. It must be there when the module is active and absent when it is
//      not. A plugin that quietly consulted all eleven packs would pass every
//      other check in this file and fail this one.
//
//   4. THE SCENE. The playable scene ships its steps as data
//      (`templates/project/insimul/scenarios/*.json`), so the same steps the
//      scene drives run here, through the same rows, on any box with no Godot
//      binary. Each scenario declares the genre it plays in, and every module it
//      opens must be one that genre ACTIVATES — a bundle that stopped selecting
//      the mechanic breaks the scene here rather than in a player's hands.
//
// WHAT IT DOES NOT PROVE, said plainly: no GDScript runs here. That the addon's
// reader and activator behave is covered structurally by
// `tools/verify-mechanics/check-mechanics.mjs` check 7 (which is what makes
// "no hardcoded list" checkable at all) and by the human scene pass in
// VERIFICATION.md.

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

// ── Floors. Growing the table must not break the gate; shrinking it must. ────
//
// The same discipline as the corpus gate's, and duplicated from
// `tools/vendor-conformance.mjs`'s TABLE_FLOORS on purpose: that one guards the
// vendored BYTES, this one guards what was EXECUTED. Counts are core 76782e5's.
const int MIN_GENRES = 8;
const int MIN_ACTIVATIONS = 24;
const int MIN_PACKS = 11;
const int MIN_SCENARIOS = 1;
const int MIN_SCENARIO_STEPS = 5;

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
	std::vector<std::filesystem::path> files;
	if (!std::filesystem::is_directory(dir)) return files;
	for (const std::filesystem::directory_entry &entry : std::filesystem::directory_iterator(dir)) {
		if (entry.is_regular_file() && entry.path().extension() == ".json") files.push_back(entry.path());
	}
	std::sort(files.begin(), files.end());
	return files;
}

// ── Comparison — JavaScript `toEqual` semantics, as in the corpus gate ───────
//
// Objects match on their KEY SET (the bridge answers in core's literal order,
// the file was emitted from a different traversal), arrays are ordered (every
// ordered list in the activation table is core's manifest order and IS the
// contract), numbers compare by value.

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
	if (s.size() > 900) s = s.substr(0, 900) + "…";
	return s;
}

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

// ── Building JSON to send ───────────────────────────────────────────────────

JsonValuePtr json_string(const std::string &s) {
	JsonValuePtr v = std::make_shared<JsonValue>();
	v->type = JsonType::String;
	v->string_value = s;
	return v;
}

JsonValuePtr json_object() {
	JsonValuePtr v = std::make_shared<JsonValue>();
	v->type = JsonType::Object;
	return v;
}

/** Set (or replace) a member, so an argument object can be extended in place. */
void put(const JsonValuePtr &object, const std::string &key, const JsonValuePtr &value) {
	for (std::pair<std::string, JsonValuePtr> &kv : object->object_items) {
		if (kv.first == key) {
			kv.second = value;
			return;
		}
	}
	object->object_items.emplace_back(key, value);
}

/** A deep copy, so a scenario's authored arguments are never mutated in place. */
JsonValuePtr clone(const JsonValue *v) {
	JsonValuePtr out = std::make_shared<JsonValue>();
	if (v == nullptr) return out;
	*out = *v;
	out->array_items.clear();
	out->object_items.clear();
	for (const JsonValuePtr &item : v->array_items) out->array_items.push_back(clone(item.get()));
	for (const std::pair<std::string, JsonValuePtr> &kv : v->object_items) {
		out->object_items.emplace_back(kv.first, clone(kv.second.get()));
	}
	return out;
}

/** `a.b[0].c` — the path language the scenario's expectations are written in. */
const JsonValue *at_path(const JsonValue *root, const std::string &path) {
	const JsonValue *node = root;
	std::string token;
	auto step = [&](const std::string &t, bool index) -> bool {
		if (node == nullptr) return false;
		if (index) {
			if (!node->is_array()) return false;
			size_t i = static_cast<size_t>(std::stoul(t));
			if (i >= node->array_items.size()) return false;
			node = node->array_items[i].get();
			return true;
		}
		if (t.empty()) return true;
		node = node->find(t);
		return node != nullptr;
	};
	for (size_t i = 0; i <= path.size(); i++) {
		if (i == path.size() || path[i] == '.' || path[i] == '[') {
			if (!step(token, false)) return nullptr;
			token.clear();
			if (i < path.size() && path[i] == '[') {
				size_t close = path.find(']', i);
				if (close == std::string::npos) return nullptr;
				if (!step(path.substr(i + 1, close - i - 1), true)) return nullptr;
				i = close;
				if (i + 1 < path.size() && path[i + 1] == '.') i++;
			}
			continue;
		}
		token += path[i];
	}
	return node;
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

std::vector<std::string> strings_of(const JsonValue *array) {
	std::vector<std::string> out;
	if (array != nullptr && array->is_array()) {
		for (const JsonValuePtr &item : array->array_items) out.push_back(item->as_string());
	}
	return out;
}

std::string join(const std::vector<std::string> &items, const std::string &sep = ", ") {
	std::string out;
	for (const std::string &item : items) out += (out.empty() ? "" : sep) + item;
	return out;
}

// ── Part 1 + 2: the table, and every bundle resolved through the bridge ─────

/** `{"genre":"x"}` and the World IR path, which is what a game actually takes. */
std::string genre_args(const std::string &genre) {
	JsonValuePtr args = json_object();
	put(args, "genre", json_string(genre));
	return insimul::canonical_json_stringify(*args);
}

std::string world_ir_args(const std::string &genre) {
	JsonValuePtr config = json_object();
	put(config, "id", json_string(genre));
	JsonValuePtr meta = json_object();
	put(meta, "genreConfig", config);
	JsonValuePtr ir = json_object();
	put(ir, "meta", meta);
	JsonValuePtr args = json_object();
	put(args, "ir", ir);
	return insimul::canonical_json_stringify(*args);
}

void run_table(insimul_core *core, const JsonValue *committed, int &genres_seen, int &activations_seen) {
	std::printf("\nthe committed table, and the answer this build gives\n");

	CallResult table = call(core, "modules.table", "");
	if (!table.ok) {
		fail("modules.table answers", table.error);
		return;
	}
	if (deep_equal(table.root.get(), committed)) {
		ok("`modules.table` is byte-equal to conformance/modules/genre-activation.json");
	} else {
		fail("`modules.table` is byte-equal to conformance/modules/genre-activation.json",
				"DIVERGE at `" + first_difference(committed, table.root.get()) +
						"` — the vendored table and this build came from different core commits\n        vendored: " +
						show(committed) + "\n        build:    " + show(table.root.get()));
	}

	const JsonValue *genres = committed->find("genres");
	if (genres == nullptr || !genres->is_object()) {
		fail("the vendored table declares genre bundles", "no `genres` object");
		return;
	}

	for (const std::pair<std::string, JsonValuePtr> &entry : genres->object_items) {
		const std::string &genre = entry.first;
		const JsonValue *want = entry.second.get();
		genres_seen++;
		const JsonValue *modules = want->find("modules");
		activations_seen += modules != nullptr ? static_cast<int>(modules->size()) : 0;

		CallResult by_genre = call(core, "modules.activate", genre_args(genre));
		CallResult by_ir = call(core, "modules.activate", world_ir_args(genre));
		if (!by_genre.ok || !by_ir.ok) {
			fail("genre `" + genre + "` resolves", by_genre.ok ? by_ir.error : by_genre.error);
			continue;
		}
		const JsonValue *got = by_genre.root->find("active");
		if (!deep_equal(got, want)) {
			fail("genre `" + genre + "` activates exactly what the table says",
					"DIVERGE at `" + first_difference(want, got) + "`\n        pinned: " + show(want) +
							"\n        got:    " + show(got));
			continue;
		}
		// The World IR path must produce the SAME set — the genre riding in
		// `meta.genreConfig.id` is the only thing a plugin carries across the ABI.
		if (!deep_equal(by_ir.root->find("active"), want)) {
			fail("genre `" + genre + "` resolves identically from a World IR",
					"DIVERGE at `" + first_difference(want, by_ir.root->find("active")) + "`");
			continue;
		}
		if (by_ir.root->get_string("source") != "worldIr" || by_genre.root->get_string("source") != "genre") {
			fail("genre `" + genre + "` reports where its genre came from",
					"sources: " + by_genre.root->get_string("source") + " / " + by_ir.root->get_string("source"));
			continue;
		}
		const int module_count = modules != nullptr ? static_cast<int>(modules->size()) : 0;
		std::printf("  ✓ %-18s %d module(s), %zu pack(s), %zu host interface(s)\n", genre.c_str(),
				module_count, strings_of(want->find("predicatePacks")).size(),
				strings_of(want->find("hostInterfaces")).size());
		checks++;
	}
}

/** The two answers that are NOT a genre bundle, and are not each other. */
void run_edges(insimul_core *core, const JsonValue *committed, const std::vector<std::string> &all_packs) {
	std::printf("\nthe answers that are not a bundle\n");

	const std::vector<std::string> always = strings_of(committed->find("alwaysActivePacks"));

	CallResult unknown = call(core, "modules.activate", genre_args("not-a-genre-core-has-heard-of"));
	if (!unknown.ok) {
		fail("an unknown genre resolves", unknown.error);
	} else {
		const JsonValue *set = unknown.root->find("active");
		const bool known = set != nullptr && set->get_bool("known");
		const JsonValue *modules = set != nullptr ? set->find("modules") : nullptr;
		check(!known && modules != nullptr && modules->size() == 0,
				"an UNKNOWN genre activates no module — it does not inherit the build",
				"known=" + std::string(known ? "true" : "false"));
		check(strings_of(unknown.root->find("predicatePacks")) == always,
				"an unknown genre consults the always-active packs and nothing else",
				join(strings_of(unknown.root->find("predicatePacks"))));
	}

	CallResult none = call(core, "modules.activate", "{}");
	if (!none.ok) {
		fail("a host that declared nothing resolves", none.error);
	} else {
		check(none.root->get_string("source") == "undeclared" && none.root->find("active")->is_null(),
				"declaring NOTHING is reported as its own answer, not as an unknown genre",
				none.root->get_string("source"));
		check(strings_of(none.root->find("predicatePacks")) == all_packs,
				"a host that declared nothing gets every pack — right for a tool, a warning in a game",
				join(strings_of(none.root->find("predicatePacks"))));
	}

	// A World IR with no genreConfig is the third shape a game meets, and it is
	// the undeclared answer rather than an unknown genre. See §13.2.
	CallResult bare = call(core, "modules.activate", "{\"ir\":{\"meta\":{}}}");
	if (!bare.ok) {
		fail("a World IR with no genreConfig resolves", bare.error);
	} else {
		check(bare.root->get_string("source") == "undeclared" &&
						!bare.root->get_string("reason").empty(),
				"a World IR carrying no genre is UNDECLARED, with the reason said",
				bare.root->get_string("source") + " / " + bare.root->get_string("reason"));
	}
}

// ── Part 3: the witness, in a real KB ───────────────────────────────────────

struct Pack {
	std::string area;
	std::string prolog;
	std::vector<std::string> runtime_predicates;
	/** A predicate this build MEASURED to come from this pack and no other. */
	std::string signature;
};

/** Consult `kb` and run `query`, through the same row the corpus gate uses. */
CallResult prolog_run(insimul_core *core, const std::string &kb, const std::string &query) {
	JsonValuePtr args = json_object();
	put(args, "kb", json_string(kb));
	put(args, "query", json_string(query));
	return call(core, "prolog.run", insimul::canonical_json_stringify(*args));
}

/** How many solutions a query had; -1 when it could not run at all. */
int solutions_of(const CallResult &res) {
	if (!res.ok) return -1;
	if (!res.root->get_bool("ok")) return -1;
	const JsonValue *solutions = res.root->find("solutions");
	return solutions != nullptr ? static_cast<int>(solutions->size()) : 0;
}

std::string kb_of(const std::vector<Pack> &packs, const std::set<std::string> &areas) {
	std::string kb;
	for (const Pack &pack : packs) {
		if (areas.count(pack.area) == 0) continue;
		kb += pack.prolog + "\n";
	}
	return kb;
}

/**
 * Every `name/arity` this pack's text defines a clause for, in order of
 * appearance.
 *
 * A pack's `runtimePredicates` is the first place to look for a signature, but
 * it is deliberately only the PER-PLAYTHROUGH ones (core keeps authored facts
 * out of it so world-template data cannot ride into a save file), and two packs
 * in the build declare none at all. So the clause heads are read too — a
 * rule-pack text is a list of them, and this is the same shape core's own
 * `buildPredicateSchemaSnapshot()` reads for its collision guard.
 */
std::vector<std::string> clause_heads(const std::string &prolog) {
	std::vector<std::string> out;
	std::set<std::string> seen;
	std::istringstream lines(prolog);
	std::string line;
	while (std::getline(lines, line)) {
		// A clause head starts a line: an atom, an open paren, and no leading
		// space. Continuations, directives (`:-`) and comments (`%`) are not.
		if (line.empty() || line[0] < 'a' || line[0] > 'z') continue;
		size_t open = line.find('(');
		if (open == std::string::npos) continue;
		const std::string name = line.substr(0, open);
		if (name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") !=
				std::string::npos) {
			continue;
		}
		// Arity: top-level commas inside the head's parentheses.
		int depth = 0;
		int arity = 1;
		bool closed = false;
		bool quoted = false;
		for (size_t i = open; i < line.size(); i++) {
			const char c = line[i];
			if (quoted) {
				if (c == '\'') quoted = false;
				continue;
			}
			if (c == '\'') {
				quoted = true;
			} else if (c == '(' || c == '[') {
				depth++;
			} else if (c == ')' || c == ']') {
				depth--;
				if (depth == 0 && c == ')') {
					closed = true;
					break;
				}
			} else if (c == ',' && depth == 1) {
				arity++;
			}
		}
		if (!closed) continue;
		const std::string signature = name + "/" + std::to_string(arity);
		if (seen.insert(signature).second) out.push_back(signature);
	}
	return out;
}

/**
 * Ask the build for every pack, then MEASURE a signature for each: a runtime
 * predicate that is defined when this pack alone is consulted and undefined
 * when every other pack is. Measured rather than listed, because a listed one
 * would be this file's opinion about core's vocabulary — the thing the whole
 * story is trying not to have.
 */
std::vector<Pack> measure_packs(insimul_core *core) {
	std::vector<Pack> packs;
	CallResult all = call(core, "prolog.packs", "{}");
	if (!all.ok) {
		fail("prolog.packs answers with the build's rule packs", all.error);
		return packs;
	}
	const JsonValue *list = all.root->find("packs");
	if (list == nullptr || !list->is_array()) {
		fail("prolog.packs answers with the build's rule packs", "no `packs` array");
		return packs;
	}
	for (const JsonValuePtr &entry : list->array_items) {
		Pack pack;
		pack.area = entry->get_string("area");
		pack.prolog = entry->get_string("prolog");
		pack.runtime_predicates = strings_of(entry->find("runtimePredicates"));
		packs.push_back(pack);
	}

	std::set<std::string> every;
	for (const Pack &pack : packs) every.insert(pack.area);

	int measured = 0;
	for (Pack &pack : packs) {
		std::set<std::string> alone = { pack.area };
		std::set<std::string> without = every;
		without.erase(pack.area);
		const std::string kb_alone = kb_of(packs, alone);
		const std::string kb_without = kb_of(packs, without);
		std::vector<std::string> candidates = pack.runtime_predicates;
		for (const std::string &head : clause_heads(pack.prolog)) candidates.push_back(head);
		for (const std::string &candidate : candidates) {
			const std::string query = "current_predicate(" + candidate + ")";
			if (solutions_of(prolog_run(core, kb_alone, query)) <= 0) continue;
			if (solutions_of(prolog_run(core, kb_without, query)) != 0) continue;
			pack.signature = candidate;
			measured++;
			break;
		}
	}
	std::string unsigned_packs;
	for (const Pack &pack : packs) {
		if (pack.signature.empty()) {
			unsigned_packs += (unsigned_packs.empty() ? "" : ", ") + pack.area + " (" +
					std::to_string(pack.runtime_predicates.size()) + " runtime predicate(s), " +
					std::to_string(clause_heads(pack.prolog).size()) + " clause head(s))";
		}
	}
	check(measured == static_cast<int>(packs.size()),
			"every pack in the build has a measurable signature predicate",
			std::to_string(measured) + " of " + std::to_string(packs.size()) + " — no signature for: " +
					unsigned_packs);
	return packs;
}

void run_witness(insimul_core *core, const JsonValue *committed, const std::vector<Pack> &packs,
		int &witnessed) {
	std::printf("\nthe witness — for every genre, in a real KB\n");
	const JsonValue *genres = committed->find("genres");
	if (genres == nullptr) return;

	for (const std::pair<std::string, JsonValuePtr> &entry : genres->object_items) {
		const std::string &genre = entry.first;
		CallResult resolved = call(core, "modules.activate", genre_args(genre));
		if (!resolved.ok) {
			fail("genre `" + genre + "` resolves for the witness", resolved.error);
			continue;
		}
		const std::vector<std::string> active_packs = strings_of(resolved.root->find("predicatePacks"));
		const std::set<std::string> active(active_packs.begin(), active_packs.end());
		const std::string kb = kb_of(packs, active);

		std::string wrong;
		int present = 0;
		for (const Pack &pack : packs) {
			if (pack.signature.empty()) continue;
			const bool should = active.count(pack.area) > 0;
			const int solutions = solutions_of(
					prolog_run(core, kb, "current_predicate(" + pack.signature + ")"));
			if (solutions < 0) {
				wrong += (wrong.empty() ? "" : ", ") + pack.area + " (the KB would not run)";
				continue;
			}
			const bool is_there = solutions > 0;
			if (is_there) present++;
			if (is_there != should) {
				wrong += (wrong.empty() ? "" : ", ") + pack.area + " " + pack.signature + " is " +
						(is_there ? "PRESENT" : "ABSENT") + " and the module is " +
						(should ? "active" : "inactive");
			}
			witnessed++;
		}
		if (wrong.empty()) {
			std::printf("  ✓ %-18s %d of %zu pack(s) in the KB, and exactly the active ones\n",
					genre.c_str(), present, packs.size());
			checks++;
		} else {
			fail("genre `" + genre + "` consults exactly its active packs", wrong);
		}
	}
}

// ── Part 4: the playable scene's own steps ──────────────────────────────────

/** One `expect` entry: a path and one assertion about what is there. */
bool expectation_holds(const JsonValue *result, const JsonValue *want, std::string &why) {
	const std::string path = want->get_string("path");
	const JsonValue *got = at_path(result, path);
	if (const JsonValue *exists = want->find("exists")) {
		const bool there = got != nullptr && !got->is_null();
		if (there == exists->as_bool()) return true;
		why = path + ": expected " + (exists->as_bool() ? "something" : "nothing") + ", got " + show(got);
		return false;
	}
	if (const JsonValue *equals = want->find("equals")) {
		if (deep_equal(got, equals)) return true;
		why = path + ": pinned " + show(equals) + ", got " + show(got);
		return false;
	}
	if (const JsonValue *least = want->find("atLeast")) {
		if (got != nullptr && got->is_number() && got->as_number() >= least->as_number()) return true;
		why = path + ": expected at least " + show(least) + ", got " + show(got);
		return false;
	}
	if (const JsonValue *most = want->find("atMost")) {
		if (got != nullptr && got->is_number() && got->as_number() <= most->as_number()) return true;
		why = path + ": expected at most " + show(most) + ", got " + show(got);
		return false;
	}
	if (const JsonValue *length = want->find("length")) {
		if (got != nullptr && got->is_array() &&
				got->array_items.size() == static_cast<size_t>(length->as_int())) {
			return true;
		}
		why = path + ": expected " + show(length) + " item(s), got " + show(got);
		return false;
	}
	if (const JsonValue *order = want->find("orderCount")) {
		int seen = 0;
		const JsonValue *orders = result->find("orders");
		if (orders != nullptr && orders->is_array()) {
			for (const JsonValuePtr &o : orders->array_items) {
				if (o->get_string("host") == want->get_string("host") &&
						o->get_string("call") == want->get_string("call")) {
					seen++;
				}
			}
		}
		if (seen == static_cast<int>(order->as_int())) return true;
		why = want->get_string("host") + "." + want->get_string("call") + ": expected " +
				show(order) + " order(s), saw " + std::to_string(seen);
		return false;
	}
	why = "the expectation names no assertion (exists / equals / atLeast / atMost / length / orderCount)";
	return false;
}

void run_scenarios(insimul_core *core, const std::filesystem::path &dir, const std::vector<Pack> &packs,
		int &scenarios_run, int &steps_run) {
	std::printf("\nthe playable scene, replayed through the same rows\n");

	for (const std::filesystem::path &file : json_files(dir)) {
		insimul::JsonParseResult parsed = insimul::parse_json(read_file(file));
		if (!parsed.ok) {
			fail("scenario " + file.filename().string() + " parses", parsed.error);
			continue;
		}
		const JsonValue *doc = parsed.root.get();
		const std::string name = doc->get_string("scene", file.stem().string());
		const std::string genre = doc->get_string("genre");

		CallResult resolved = call(core, "modules.activate", genre_args(genre));
		if (!resolved.ok) {
			fail("scenario " + name + " resolves its genre", resolved.error);
			continue;
		}
		std::set<std::string> active_modules;
		const JsonValue *set = resolved.root->find("active");
		const JsonValue *modules = set != nullptr ? set->find("modules") : nullptr;
		if (modules != nullptr && modules->is_array()) {
			for (const JsonValuePtr &m : modules->array_items) active_modules.insert(m->get_string("id"));
		}
		const std::vector<std::string> pack_areas = strings_of(resolved.root->find("predicatePacks"));
		const std::string kb = kb_of(packs, std::set<std::string>(pack_areas.begin(), pack_areas.end())) +
				doc->get_string("worldFacts");

		// Every module the scene opens must be one this genre ACTIVATES. That is
		// what makes the scene a test of activation rather than of seven rows.
		std::map<std::string, std::string> handles;
		bool opened_all = true;
		const JsonValue *sessions = doc->find("sessions");
		if (sessions != nullptr && sessions->is_array()) {
			for (const JsonValuePtr &s : sessions->array_items) {
				const std::string module = s->get_string("module");
				if (active_modules.count(module) == 0) {
					fail("scenario " + name + " opens only modules the genre activates",
							"`" + module + "` is not activated by `" + genre + "`");
					opened_all = false;
					break;
				}
				JsonValuePtr args = clone(s->find("args"));
				if (!args->is_object()) args = json_object();
				put(args, "kb", json_string(kb));
				// A session that takes another module's session, by module name, so
				// the scenario never has to know a handle.
				if (const JsonValue *link = s->find("shares")) {
					for (const std::pair<std::string, JsonValuePtr> &kv : link->object_items) {
						auto it = handles.find(kv.second->as_string());
						if (it == handles.end()) continue;
						JsonValuePtr handle = std::make_shared<JsonValue>();
						handle->type = JsonType::Number;
						handle->number_value = std::stod(it->second);
						handle->raw_number = it->second;
						put(args, kv.first, handle);
					}
				}
				CallResult created = call(core, (module + ".create").c_str(),
						insimul::canonical_json_stringify(*args));
				if (!created.ok) {
					fail("scenario " + name + ": " + module + ".create opens", created.error);
					opened_all = false;
					break;
				}
				handles[module] = std::to_string(created.root->get_int("session"));
			}
		}
		if (!opened_all) continue;

		int step_index = 0;
		bool all_green = true;
		const JsonValue *steps = doc->find("steps");
		if (steps != nullptr && steps->is_array()) {
			for (const JsonValuePtr &step : steps->array_items) {
				step_index++;
				const std::string module = step->get_string("module");
				const std::string row = step->get_string("row");
				auto handle = handles.find(module);
				if (handle == handles.end()) {
					fail("scenario " + name + " step " + std::to_string(step_index),
							"no open session for `" + module + "`");
					all_green = false;
					continue;
				}
				JsonValuePtr args = clone(step->find("args"));
				if (!args->is_object()) args = json_object();
				JsonValuePtr session = std::make_shared<JsonValue>();
				session->type = JsonType::Number;
				session->number_value = std::stod(handle->second);
				session->raw_number = handle->second;
				put(args, "session", session);
				CallResult res = call(core, (module + "." + row).c_str(),
						insimul::canonical_json_stringify(*args));
				if (!res.ok) {
					fail("scenario " + name + " step " + std::to_string(step_index) + " (" + module + "." + row + ")",
							res.error);
					all_green = false;
					continue;
				}
				steps_run++;
				const JsonValue *expect = step->find("expect");
				if (expect == nullptr || !expect->is_array()) continue;
				for (const JsonValuePtr &want : expect->array_items) {
					std::string why;
					if (expectation_holds(res.root.get(), want.get(), why)) continue;
					fail("scenario " + name + " step " + std::to_string(step_index) + " (" + module + "." + row + ")",
							why + "\n        result: " + show(res.root.get()));
					all_green = false;
				}
			}
		}

		for (const std::pair<const std::string, std::string> &kv : handles) {
			call(core, "mechanic.dispose", "{\"session\":" + kv.second + "}");
		}
		if (all_green) {
			scenarios_run++;
			std::printf("  ✓ %-18s %s: %d step(s) across %zu module(s), every expectation met\n",
					name.c_str(), genre.c_str(), step_index, handles.size());
			checks++;
		}
	}
}

} // namespace

int main(int argc, char **argv) {
	std::filesystem::path repo = argc > 1
			? std::filesystem::path(argv[1])
			: std::filesystem::path(__FILE__).parent_path().parent_path().parent_path();
	const std::filesystem::path table_file = repo / "conformance" / "modules" / "genre-activation.json";
	const std::filesystem::path scenarios = repo / "templates" / "project" / "insimul" / "scenarios";
	if (!std::filesystem::is_regular_file(table_file)) {
		std::fprintf(stderr, "error: %s has no conformance/modules/genre-activation.json\n",
				repo.string().c_str());
		return 2;
	}

	insimul::JsonParseResult committed = insimul::parse_json(read_file(table_file));
	if (!committed.ok) {
		std::fprintf(stderr, "error: genre-activation.json does not parse: %s\n", committed.error.c_str());
		return 2;
	}

	insimul_core *core = insimul_core_create();
	if (core == nullptr) {
		std::fprintf(stderr, "error: insimul_core_create() failed — the bundle did not evaluate\n");
		return 2;
	}
	std::printf("libinsimulcore %s, repo %s\n", insimul_core_version(), repo.string().c_str());

	int genres_seen = 0;
	int activations_seen = 0;
	int witnessed = 0;
	int scenarios_run = 0;
	int steps_run = 0;

	run_table(core, committed.root.get(), genres_seen, activations_seen);

	std::printf("\nthe rule packs the active set names\n");
	std::vector<Pack> packs = measure_packs(core);
	std::vector<std::string> all_packs;
	for (const Pack &pack : packs) all_packs.push_back(pack.area);
	std::printf("  packs: %s\n", join(all_packs).c_str());

	run_edges(core, committed.root.get(), all_packs);
	run_witness(core, committed.root.get(), packs, witnessed);
	run_scenarios(core, scenarios, packs, scenarios_run, steps_run);

	std::printf("\nThe gate on the gate\n");
	check(genres_seen >= MIN_GENRES,
			"every one of the " + std::to_string(MIN_GENRES) + " genre bundle(s) was resolved",
			"saw " + std::to_string(genres_seen));
	check(activations_seen >= MIN_ACTIVATIONS,
			"the table still holds at least " + std::to_string(MIN_ACTIVATIONS) + " module activation(s)",
			"saw " + std::to_string(activations_seen));
	check(static_cast<int>(packs.size()) >= MIN_PACKS,
			"the build still carries at least " + std::to_string(MIN_PACKS) + " rule pack(s)",
			"saw " + std::to_string(packs.size()));
	check(witnessed >= MIN_GENRES * MIN_PACKS,
			"every genre x pack pair was witnessed in a KB",
			"witnessed " + std::to_string(witnessed));
	check(scenarios_run >= MIN_SCENARIOS,
			"at least " + std::to_string(MIN_SCENARIOS) + " playable scenario ran end to end",
			"ran " + std::to_string(scenarios_run));
	check(steps_run >= MIN_SCENARIO_STEPS,
			"the scene's steps still number at least " + std::to_string(MIN_SCENARIO_STEPS),
			"ran " + std::to_string(steps_run));

	insimul_core_destroy(core);

	std::printf("\n%d check(s), %d failure(s)\n", checks, failures);
	if (failures > 0) {
		std::printf("FAILED\n");
		return 1;
	}
	std::printf("PASSED\n");
	return 0;
}
