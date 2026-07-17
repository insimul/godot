// test_reimport_diff.cpp — host gate for the re-import diff policy core
// (US-GB3). Builds under a plain clang toolchain (no godot-cpp, no libinsimul;
// see test/run_reimport_tests.sh) and exercises the shared re-import policy:
//
//   1. golden-match — the diff report computed from the shared old/new manifests
//      (editor/reimport/fixtures/{old,new}-manifest.json) is byte-identical to
//      the committed golden (golden-diff-report.json). This is the cross-engine
//      re-import contract Unity/Unreal reconcile against;
//   2. policy coverage — every one of the five actions is exercised at least
//      once (added / updated / unchanged / skipped / deprecated) and the
//      hand-edit invariants hold: a generated=false node is NEVER updated or
//      deprecated (always skipped), whether present in or absent from the new
//      manifest;
//   3. determinism — computing the report twice yields identical bytes, and a
//      no-op re-import (new == old) classifies every node unchanged/skipped with
//      zero adds/updates/deprecations.
//
// Bootstrap: `test_reimport_diff <fixtures_dir> dump` prints the report to stdout
// (used to regenerate the golden). The @tool GDScript twin
// (editor/reimport/insimul_reimport.gd + reimport_test.gd) mirrors this exact
// classification against the SAME fixtures; this host gate runs on a box with no
// Godot binary.

#include "../src/json_value.h"
#include "../src/reimport_diff.h"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

using namespace insimul;

namespace {

int g_pass = 0;
int g_fail = 0;

void report(const std::string &name, bool ok, const std::string &detail = "") {
	std::printf("  %s  %-52s%s%s\n", ok ? "PASS" : "FAIL", name.c_str(),
			detail.empty() ? "" : "  ", detail.c_str());
	if (ok) {
		g_pass++;
	} else {
		g_fail++;
	}
}

std::string read_file(const std::filesystem::path &p) {
	std::ifstream in(p, std::ios::binary);
	if (!in) {
		throw std::string("cannot open ") + p.string();
	}
	std::ostringstream ss;
	ss << in.rdbuf();
	return ss.str();
}

std::string trim(const std::string &s) {
	std::size_t a = s.find_first_not_of(" \t\r\n");
	if (a == std::string::npos) return "";
	std::size_t b = s.find_last_not_of(" \t\r\n");
	return s.substr(a, b - a + 1);
}

std::vector<PlacedNode> load_nodes(const std::string &json) {
	JsonParseResult p = parse_json(json);
	if (!p.ok || !p.root) {
		throw std::string("parse: ") + p.error;
	}
	std::vector<PlacedNode> nodes;
	std::string err;
	if (!parse_manifest_nodes(*p.root, nodes, err)) {
		throw std::string("nodes: ") + err;
	}
	return nodes;
}

bool contains(const std::vector<std::string> &v, const std::string &s) {
	for (const std::string &x : v) {
		if (x == s) return true;
	}
	return false;
}

} // namespace

int main(int argc, char **argv) {
	std::filesystem::path fixtures = argc > 1
			? std::filesystem::path(argv[1])
			: std::filesystem::path("../addons/insimul/editor/reimport/fixtures");
	bool dump = argc > 2 && std::string(argv[2]) == "dump";

	std::string old_json, new_json;
	try {
		old_json = read_file(fixtures / "old-manifest.json");
		new_json = read_file(fixtures / "new-manifest.json");
	} catch (const std::string &e) {
		std::fprintf(stderr, "fixture load error: %s\n", e.c_str());
		return 2;
	}

	std::string err;
	std::string report_json = generate_reimport_report(old_json, new_json, err);
	if (report_json.empty()) {
		std::fprintf(stderr, "reimport diff error: %s\n", err.c_str());
		return 2;
	}

	if (dump) {
		std::printf("%s\n", report_json.c_str());
		return 0;
	}

	std::printf("Re-import diff host tests (US-GB3)\n");

	// ---- 1. golden-match ---------------------------------------------------
	try {
		std::string golden = trim(read_file(fixtures / "golden-diff-report.json"));
		bool ok = report_json == golden;
		report("diff report matches golden", ok,
				ok ? "" : "report diverged from committed golden");
		if (!ok) {
			std::fprintf(stderr, "  got:    %s\n", report_json.c_str());
			std::fprintf(stderr, "  golden: %s\n", golden.c_str());
		}
	} catch (const std::string &e) {
		report("diff report matches golden", false, e);
	}

	// ---- 2. policy coverage + hand-edit invariants -------------------------
	try {
		std::vector<PlacedNode> old_nodes = load_nodes(old_json);
		std::vector<PlacedNode> new_nodes = load_nodes(new_json);
		DiffReport d = compute_reimport_diff(old_nodes, new_nodes);

		report("added covers a new-only node", contains(d.added, "prop.c"));
		report("updated covers a moved generated node", contains(d.updated, "building.b"));
		report("unchanged covers an identical generated node", contains(d.unchanged, "building.a"));
		report("deprecated covers a dropped generated node", contains(d.deprecated, "prop.e"));
		report("skipped covers a present hand edit", contains(d.skipped, "prop.d"));
		report("skipped covers an absent hand edit", contains(d.skipped, "prop.f"));

		// Hand-edit invariant: a generated=false node is NEVER updated/deprecated.
		bool handedit_safe = true;
		for (const PlacedNode &o : old_nodes) {
			if (!o.generated) {
				if (contains(d.updated, o.entity_id) || contains(d.deprecated, o.entity_id)
						|| contains(d.added, o.entity_id) || contains(d.unchanged, o.entity_id)) {
					handedit_safe = false;
				}
			}
		}
		report("hand edits are only ever skipped (never touched)", handedit_safe);

		// Every id appears in exactly one bucket.
		std::vector<std::string> all;
		for (auto *b : {&d.added, &d.updated, &d.unchanged, &d.skipped, &d.deprecated}) {
			for (const std::string &id : *b) all.push_back(id);
		}
		std::vector<std::string> sorted_all = all;
		std::sort(sorted_all.begin(), sorted_all.end());
		bool unique = true;
		for (std::size_t i = 1; i < sorted_all.size(); ++i) {
			if (sorted_all[i] == sorted_all[i - 1]) unique = false;
		}
		report("every id lands in exactly one bucket", unique,
				"total ids: " + std::to_string(all.size()));
	} catch (const std::string &e) {
		report("policy coverage", false, e);
	}

	// ---- 3. determinism + no-op re-import ----------------------------------
	{
		std::string again = generate_reimport_report(old_json, new_json, err);
		report("two runs produce identical report", again == report_json);
	}
	try {
		// Re-importing the SAME manifest must add/update/deprecate nothing.
		std::vector<PlacedNode> new_nodes = load_nodes(new_json);
		DiffReport noop = compute_reimport_diff(new_nodes, new_nodes);
		bool clean = noop.added.empty() && noop.updated.empty() && noop.deprecated.empty()
				&& noop.unchanged.size() == new_nodes.size();
		report("no-op re-import touches nothing", clean,
				"unchanged " + std::to_string(noop.unchanged.size()) + "/" + std::to_string(new_nodes.size()));
	} catch (const std::string &e) {
		report("no-op re-import", false, e);
	}

	std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
