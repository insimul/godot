// test_scene_placement.cpp — host gate for the scene-generation placement math
// core (US-GB2). Builds under a plain clang toolchain (no godot-cpp, no
// libinsimul; see test/run_placement_tests.sh) and exercises:
//
//   1. golden-match — the placement manifest computed from the shared golden IR
//      (editor/scene/fixtures/golden-ir.json) resolved against the placeholder
//      pack (placeholder-pack.json) is byte-identical to the committed golden
//      manifest (golden-placement-manifest.json). This is the cross-engine
//      placement contract Unity/Unreal also generate against;
//   2. placeholder coverage — every archetype the golden IR emits resolves
//      through the placeholder pack to a DEDICATED taxonomy entry (never the
//      bare "*" catch-all), proving full golden-IR coverage;
//   3. determinism — computing the manifest twice yields identical bytes.
//
// Bootstrap: `test_scene_placement <fixtures_dir> dump` prints the manifest to
// stdout (used to regenerate the golden). The @tool GDScript twin
// (editor/scene/insimul_scene_generator.gd + scene_generator_test.gd) mirrors
// this exact math against the SAME fixtures; this host gate runs on a box with
// no Godot binary.

#include "../src/binding_resolver.h"
#include "../src/canonical_json.h"
#include "../src/json_value.h"
#include "../src/scene_placement.h"

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
	std::printf("  %s  %-46s%s%s\n", ok ? "PASS" : "FAIL", name.c_str(),
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

// Trim leading/trailing whitespace (the golden file has a trailing newline).
std::string trim(const std::string &s) {
	std::size_t a = s.find_first_not_of(" \t\r\n");
	if (a == std::string::npos) return "";
	std::size_t b = s.find_last_not_of(" \t\r\n");
	return s.substr(a, b - a + 1);
}

BindingResolver build_placeholder_resolver(const std::string &pack_json) {
	JsonParseResult pack = parse_json(pack_json);
	if (!pack.ok || !pack.root) {
		throw std::string("placeholder pack parse: ") + pack.error;
	}
	BindingResolver resolver;
	BindingSource src;
	std::string err;
	if (!parse_binding_source(*pack.root, src, err)) {
		throw std::string("placeholder pack source: ") + err;
	}
	resolver.add_source(std::move(src));
	resolver.sort_sources_by_priority();
	return resolver;
}

} // namespace

int main(int argc, char **argv) {
	std::filesystem::path fixtures = argc > 1
			? std::filesystem::path(argv[1])
			: std::filesystem::path("../addons/insimul/editor/scene/fixtures");
	bool dump = argc > 2 && std::string(argv[2]) == "dump";

	std::string ir_json, pack_json;
	try {
		ir_json = read_file(fixtures / "golden-ir.json");
		pack_json = read_file(fixtures / "placeholder-pack.json");
	} catch (const std::string &e) {
		std::fprintf(stderr, "fixture load error: %s\n", e.c_str());
		return 2;
	}

	std::string err;
	std::string manifest = generate_placement_manifest(ir_json, pack_json, err);
	if (manifest.empty()) {
		std::fprintf(stderr, "placement generation error: %s\n", err.c_str());
		return 2;
	}

	if (dump) {
		std::printf("%s\n", manifest.c_str());
		return 0;
	}

	std::printf("Scene placement host tests (US-GB2)\n");

	// ---- 1. golden-match ---------------------------------------------------
	try {
		std::string golden = trim(read_file(fixtures / "golden-placement-manifest.json"));
		bool ok = manifest == golden;
		report("placement manifest matches golden", ok,
				ok ? "" : "manifest diverged from committed golden");
		if (!ok) {
			std::fprintf(stderr, "  got:    %s\n", manifest.c_str());
			std::fprintf(stderr, "  golden: %s\n", golden.c_str());
		}
	} catch (const std::string &e) {
		report("placement manifest matches golden", false, e);
	}

	// ---- 2. placeholder coverage ------------------------------------------
	try {
		BindingResolver resolver = build_placeholder_resolver(pack_json);
		// Every archetype the golden IR materializes (kinds that carry an asset).
		std::vector<std::string> archetypes = {
				"terrain",
				"road.street", "road",
				"building.downtown", "building.commercial", "building.residential",
				"interior.downtown",
				"prop.tree", "prop.lamp",
		};
		bool all_covered = true;
		std::string missing;
		for (const std::string &a : archetypes) {
			ResolveResult r = resolver.resolve(a);
			// Must resolve, and to a DEDICATED taxonomy entry (not the "*" fallback).
			if (!r.resolved || r.key == "*") {
				all_covered = false;
				missing += (missing.empty() ? "" : ", ") + a;
			}
		}
		report("placeholder pack covers every golden archetype", all_covered,
				all_covered ? "" : "uncovered/catch-all-only: " + missing);
	} catch (const std::string &e) {
		report("placeholder pack covers every golden archetype", false, e);
	}

	// ---- 3. determinism ----------------------------------------------------
	{
		std::string again = generate_placement_manifest(ir_json, pack_json, err);
		report("two runs produce identical manifest", again == manifest);
	}

	std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
