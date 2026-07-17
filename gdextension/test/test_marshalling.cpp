// test_marshalling.cpp — host-side unit tests for the marshalling core.
//
// Builds and runs under a plain clang toolchain with NO godot-cpp and NO
// libinsimul (see test/run_host_tests.sh). This is the marshalling gate for
// US-GP1: it proves the binding-set JSON -> PrologValue decode is correct in
// isolation, so that when libinsimul + godot-cpp are wired up, only the thin
// Variant adapter is unverified by the host build.
//
// The JSON fed here mirrors exactly what libinsimul's insimul_query_next() emits
// (see docs/consuming.md / libinsimul US-LI2), including the shapes that appear in
// packages/core/conformance/prolog/*.json.

#include "../src/prolog_value.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace insimul;

namespace {

int g_pass = 0;
int g_fail = 0;

void report(const std::string &name, bool ok, const std::string &detail = "") {
	std::printf("  %s  %-38s%s%s\n", ok ? "PASS" : "FAIL", name.c_str(),
			detail.empty() ? "" : "  ", detail.c_str());
	if (ok) {
		g_pass++;
	} else {
		g_fail++;
	}
}

// Expect a successful parse whose bindings equal `expected` as an unordered set.
void expect_bindings(const std::string &name, const std::string &json,
		const BindingSet &expected) {
	ParseResult r = parse_binding_set(json);
	if (!r.ok) {
		report(name, false, "parse failed: " + r.error);
		return;
	}
	if (r.bindings.size() != expected.size()) {
		report(name, false, "arity " + std::to_string(r.bindings.size()) +
						" != " + std::to_string(expected.size()) + " got " +
						to_debug_string(r.bindings));
		return;
	}
	// Unordered comparison: every expected pair must appear once.
	std::vector<bool> used(r.bindings.size(), false);
	for (const auto &want : expected) {
		bool matched = false;
		for (size_t k = 0; k < r.bindings.size(); k++) {
			if (used[k]) {
				continue;
			}
			if (r.bindings[k].first == want.first &&
					r.bindings[k].second == want.second) {
				used[k] = true;
				matched = true;
				break;
			}
		}
		if (!matched) {
			report(name, false, "missing " + want.first + "=" +
							to_debug_string(want.second) + " in " +
							to_debug_string(r.bindings));
			return;
		}
	}
	report(name, true);
}

void expect_reject(const std::string &name, const std::string &json) {
	ParseResult r = parse_binding_set(json);
	report(name, !r.ok, r.ok ? "accepted invalid input" : "");
}

} // namespace

int main() {
	std::printf("Insimul GDExtension — host marshalling tests\n");
	std::printf("--------------------------------------------\n");

	// --- Empty solution: success with no bindings (corpus `[{}]`) ----------
	expect_bindings("empty-solution-success", "{}", {});

	// --- Atom binding (unification.json parent(tom,X) -> X=bob) ------------
	expect_bindings("atom-binding", "{\"X\":\"bob\"}",
			{{"X", PrologValue::atom("bob")}});

	// --- Two-variable atom binding (likes(P,F)) ----------------------------
	expect_bindings("two-atom-bindings", "{\"P\":\"sam\",\"F\":\"pizza\"}",
			{{"P", PrologValue::atom("sam")}, {"F", PrologValue::atom("pizza")}});

	// --- Integer binding (arithmetic.json X=5, length N=3) -----------------
	expect_bindings("int-binding", "{\"X\":5}",
			{{"X", PrologValue::integer(5)}});
	expect_bindings("int-binding-large", "{\"X\":42}",
			{{"X", PrologValue::integer(42)}});

	// --- Float binding (numbers with a decimal component) ------------------
	expect_bindings("float-binding", "{\"X\":3.5}",
			{{"X", PrologValue::real(3.5)}});
	expect_bindings("negative-int", "{\"D\":-7}",
			{{"D", PrologValue::integer(-7)}});

	// --- List binding (findall of atoms) -----------------------------------
	expect_bindings("list-of-atoms", "{\"L\":[\"a\",\"b\",\"c\"]}",
			{{"L", PrologValue::list({PrologValue::atom("a"),
					PrologValue::atom("b"), PrologValue::atom("c")})}});

	// --- Empty list --------------------------------------------------------
	expect_bindings("empty-list", "{\"L\":[]}",
			{{"L", PrologValue::list({})}});

	// --- Mixed list (numbers + atoms) --------------------------------------
	expect_bindings("mixed-list", "{\"L\":[1,\"two\",3]}",
			{{"L", PrologValue::list({PrologValue::integer(1),
					PrologValue::atom("two"), PrologValue::integer(3)})}});

	// --- Compound term binding: point(1,2) ---------------------------------
	expect_bindings("compound-binding",
			"{\"P\":{\"functor\":\"point\",\"args\":[1,2]}}",
			{{"P", PrologValue::compound("point", {PrologValue::integer(1),
					PrologValue::integer(2)})}});

	// --- Nested compound: quest_reward(gold, item(sword,3)) ----------------
	expect_bindings("nested-compound",
			"{\"R\":{\"functor\":\"reward\",\"args\":["
			"\"gold\",{\"functor\":\"item\",\"args\":[\"sword\",3]}]}}",
			{{"R", PrologValue::compound("reward",
					{PrologValue::atom("gold"),
							PrologValue::compound("item",
									{PrologValue::atom("sword"),
											PrologValue::integer(3)})})}});

	// --- List of compounds -------------------------------------------------
	expect_bindings("list-of-compounds",
			"{\"Qs\":[{\"functor\":\"q\",\"args\":[\"a\"]},"
			"{\"functor\":\"q\",\"args\":[\"b\"]}]}",
			{{"Qs", PrologValue::list({
					PrologValue::compound("q", {PrologValue::atom("a")}),
					PrologValue::compound("q", {PrologValue::atom("b")})})}});

	// --- Bool + null edge terms --------------------------------------------
	expect_bindings("bool-term", "{\"B\":true}",
			{{"B", PrologValue::boolean(true)}});
	expect_bindings("null-term", "{\"N\":null}",
			{{"N", PrologValue::null()}});

	// --- Escapes + unicode in an atom --------------------------------------
	expect_bindings("atom-with-escapes", "{\"S\":\"line\\nbreak\"}",
			{{"S", PrologValue::atom("line\nbreak")}});
	expect_bindings("atom-with-unicode", "{\"S\":\"caf\\u00e9\"}",
			{{"S", PrologValue::atom("caf\xC3\xA9")}});

	// --- Whitespace tolerance ----------------------------------------------
	expect_bindings("whitespace", "  {  \"X\" :  \"y\"  }  ",
			{{"X", PrologValue::atom("y")}});

	// --- Rejections: malformed / wrong-shape inputs ------------------------
	expect_reject("reject-not-object", "[1,2,3]");
	expect_reject("reject-truncated", "{\"X\":");
	expect_reject("reject-trailing", "{}garbage");
	expect_reject("reject-bad-compound-args",
			"{\"P\":{\"functor\":\"f\",\"args\":42}}");
	expect_reject("reject-plain-object-term", "{\"P\":{\"a\":1}}");
	expect_reject("reject-empty-string", "");

	std::printf("--------------------------------------------\n");
	std::printf("%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
