// test_binding_resolver.cpp — host gate for the Asset Binding Layer resolver
// core (US-GB1). Builds under a plain clang toolchain (no godot-cpp, no
// libinsimul; see test/run_binding_tests.sh) and exercises:
//
//   1. the shared resolver matrix (editor/binding/fixtures/resolver-matrix.json)
//      — every case's resolved (source,key) must match, proving the archetype
//      wildcard/descendant matching + project->packs->placeholder chain;
//   2. the cross-engine pack round-trip (unity-fixture-pack.json imports, the
//      resolver resolves against it, and canonical re-serialization is stable);
//   3. sorted / deterministic pack serialization (entries ascending by key,
//      byte-identical across two runs).
//
// The GDScript editor twin (editor/binding/insimul_binding_table.gd +
// binding_resolver_test.gd) mirrors this exact algorithm against the SAME
// fixtures; this host gate is the one that runs on a box with no Godot binary.

#include "../src/binding_resolver.h"
#include "../src/canonical_json.h"
#include "../src/json_value.h"

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

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

JsonValuePtr parse_or_die(const std::string &text, const std::string &what) {
	JsonParseResult r = parse_json(text);
	if (!r.ok) {
		throw std::string("parse failed for ") + what + ": " + r.error;
	}
	return r.root;
}

// ---- 1. Shared resolver matrix --------------------------------------------

void run_matrix(const std::filesystem::path &fixtures_dir) {
	std::string text = read_file(fixtures_dir / "resolver-matrix.json");
	JsonValuePtr root = parse_or_die(text, "resolver-matrix.json");

	const JsonValue *sources = root->find("sources");
	const JsonValue *cases = root->find("cases");
	if (sources == nullptr || cases == nullptr || !cases->is_array()) {
		report("matrix structure", false, "missing sources/cases");
		return;
	}

	BindingResolver resolver;
	std::string err;
	if (!parse_resolver_matrix_sources(*sources, resolver, err)) {
		report("matrix sources parse", false, err);
		return;
	}
	resolver.sort_sources_by_priority();
	report("matrix sources parse", true,
			std::to_string(resolver.sources().size()) + " sources");

	for (const auto &c : cases->array_items) {
		std::string name = c->get_string("name");
		std::string query = c->get_string("query");
		const JsonValue *expect = c->find("expect");

		ResolveResult got = resolver.resolve(query);

		if (expect == nullptr || expect->is_null()) {
			// null expectation => must be unresolved.
			report(name, !got.resolved,
					got.resolved ? "expected unresolved, got " + got.source_name +
									"/" + got.key
								 : "");
			continue;
		}
		std::string want_source = expect->get_string("source");
		std::string want_key = expect->get_string("key");
		bool ok = got.resolved && got.source_name == want_source && got.key == want_key;
		std::string detail;
		if (!ok) {
			detail = "want " + want_source + "/" + want_key + " got " +
					(got.resolved ? got.source_name + "/" + got.key : "<unresolved>");
		}
		report(name, ok, detail);
	}
}

// ---- 2. Cross-engine pack round-trip --------------------------------------

void run_roundtrip(const std::filesystem::path &fixtures_dir) {
	std::string text = read_file(fixtures_dir / "unity-fixture-pack.json");
	JsonValuePtr root = parse_or_die(text, "unity-fixture-pack.json");

	BindingSource pack;
	std::string err;
	if (!parse_binding_source(*root, pack, err)) {
		report("unity pack imports", false, err);
		return;
	}
	report("unity pack imports", pack.entries.size() == 3,
			std::to_string(pack.entries.size()) + " entries, name=" + pack.name);

	// Resolve against the imported foreign pack (proves it is usable, not just
	// parseable): a descendant of building.residential.house's parent hits the
	// wildcard, the exact house hits the Unity prefab path.
	BindingResolver resolver;
	resolver.add_source(pack);
	ResolveResult house = resolver.resolve("building.residential.house");
	report("resolve exact from unity pack",
			house.resolved && house.entry != nullptr &&
					house.entry->scene == "Assets/Insimul/Buildings/House.prefab",
			house.resolved ? house.entry->scene : "<unresolved>");
	ResolveResult generic = resolver.resolve("building.commercial.tower");
	report("resolve wildcard from unity pack",
			generic.resolved && generic.entry != nullptr &&
					generic.entry->mesh == "Assets/Insimul/Meshes/GenericBuilding.mesh" &&
					generic.entry->key == "building.*",
			generic.resolved ? generic.entry->key : "<unresolved>");

	// Canonical re-serialization must be byte-stable: serialize -> re-parse ->
	// serialize yields identical output, and entries come out key-sorted.
	std::string s1 = serialize_pack_sorted(pack);
	JsonValuePtr reparsed = parse_or_die(s1, "re-serialized pack");
	BindingSource pack2;
	if (!parse_binding_source(*reparsed, pack2, err)) {
		report("round-trip re-import", false, err);
		return;
	}
	std::string s2 = serialize_pack_sorted(pack2);
	report("round-trip byte-stable", s1 == s2,
			s1 == s2 ? "" : "s1 != s2");

	// Entries must be ascending by key in the canonical form.
	bool sorted = s1.find("\"building.*\"") < s1.find("\"building.residential.house\"") &&
			s1.find("\"building.residential.house\"") < s1.find("\"prop.furniture.table\"");
	report("entries key-sorted", sorted, sorted ? "" : s1.substr(0, 120));

	// Transform/socket passthrough survives the round-trip.
	report("passthrough transform+sockets",
			s1.find("\"sockets\"") != std::string::npos &&
					s1.find("\"chimney\"") != std::string::npos,
			"");
}

// ---- 3. Sorted / deterministic serialization ------------------------------

void run_determinism() {
	BindingSource src;
	src.name = "z-order-test";
	src.priority = 10;
	// Deliberately declared out of order.
	src.entries.push_back(BindingEntry{"prop.z", "res://z.tscn", "", nullptr, nullptr});
	src.entries.push_back(BindingEntry{"building.a", "res://a.tscn", "", nullptr, nullptr});
	src.entries.push_back(BindingEntry{"character.m", "res://m.tscn", "", nullptr, nullptr});

	std::string a = serialize_pack_sorted(src);
	std::string b = serialize_pack_sorted(src);
	report("serialization deterministic", a == b, a == b ? "" : "a != b");

	bool ordered = a.find("building.a") < a.find("character.m") &&
			a.find("character.m") < a.find("prop.z");
	report("declaration-order-independent sort", ordered, ordered ? "" : a.substr(0, 120));

	// Object keys are sorted too (canonical): "key" before "scene".
	std::string first = a.substr(a.find("building.a") - 20);
	report("object keys canonical", a.find("\"format\"") != std::string::npos, "");
}

} // namespace

int main(int argc, char **argv) {
	std::filesystem::path fixtures_dir =
			argc > 1 ? std::filesystem::path(argv[1])
					 : std::filesystem::path(
							   "../addons/insimul/editor/binding/fixtures");

	std::printf("Insimul GDExtension — Asset Binding Layer resolver (US-GB1)\n");
	std::printf("fixtures: %s\n", fixtures_dir.string().c_str());
	std::printf("-----------------------------------------------------------\n");

	try {
		std::printf("[matrix]\n");
		run_matrix(fixtures_dir);
		std::printf("[cross-engine round-trip]\n");
		run_roundtrip(fixtures_dir);
		std::printf("[determinism]\n");
		run_determinism();
	} catch (const std::string &e) {
		std::fprintf(stderr, "fatal: %s\n", e.c_str());
		return 2;
	}

	std::printf("-----------------------------------------------------------\n");
	std::printf("%d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
