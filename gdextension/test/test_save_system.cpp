// test_save_system.cpp — host tests for the Godot portable save-file core (US-GC2).
//
// Covers the four save-system guarantees ported from the TS semantics authority
// (packages/core/src/save-file.ts, save-envelope.ts, save-file-migrations.ts):
//
//   1. Canonical JSON (key order, number formatting, unicode) — fixture vectors.
//   2. SHA-256 integrity byte-compatible with computeSaveFileIntegrity(): the
//      hashes here MUST equal the committed golden vectors in
//      packages/core/conformance/saves/integrity-vectors.json, which a vitest
//      drift guard independently pins to the TS implementation.
//   3. Round-trip + migration (v1 -> v3) preserve/normalize state as TS does.
//   4. KB snapshot/restore into currentState.prologFacts.
//
// It also writes a Godot-produced export envelope to the build dir; the committed
// copy (packages/godot/tools/cross-check/cpp-produced.envelope.json) is what the
// TS cross-check (save-integrity-crosscheck-godot.test.ts) validates — proving
// cross-runtime save portability end to end.
//
// This mirrors packages/unreal/tools/verify-unreal/test_save_system.cpp; the
// canonical bytes are byte-identical across the two runtimes.

#include "canonical_json.h"
#include "json_value.h"
#include "save_file.h"
#include "sha256.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

#ifndef INSIMUL_FIXTURE_DIR
#define INSIMUL_FIXTURE_DIR "."
#endif
#ifndef INSIMUL_CROSSCHECK_DIR
#define INSIMUL_CROSSCHECK_DIR "."
#endif
#ifndef INSIMUL_GEN_DIR
#define INSIMUL_GEN_DIR "."
#endif

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

void check_str(const std::string &actual, const std::string &expected, const char *message) {
	++g_checks;
	if (actual != expected) {
		++g_failures;
		std::fprintf(stderr, "  [FAIL] %s\n    expected: %s\n    got:      %s\n", message,
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

std::string read_fixture(const std::string &name) { return read_file(INSIMUL_FIXTURE_DIR, name); }

// Read a committed golden integrity hash from integrity-vectors.json.
std::string vector_for(const std::string &fixture_name) {
	const std::string json = read_fixture("integrity-vectors.json");
	insimul::JsonParseResult parsed = insimul::parse_json(json);
	if (!parsed.ok || !parsed.root) {
		return std::string();
	}
	const insimul::JsonValue *vectors = parsed.root->find("vectors");
	const insimul::JsonValue *table = vectors ? vectors : parsed.root.get();
	return table->get_string(fixture_name);
}

std::string canon_of(const std::string &json) {
	insimul::JsonParseResult parsed = insimul::parse_json(json);
	if (!parsed.ok || !parsed.root) {
		return std::string();
	}
	return insimul::canonical_json_stringify(*parsed.root);
}

} // namespace

int main() {
	using namespace insimul;

	std::printf("== Godot SaveSystem host tests ==\n");

	// ── 1a. SHA-256 primitive (NIST test vectors) ───────────────────────────
	check_str(sha256_hex(""),
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256(\"\")");
	check_str(sha256_hex("abc"),
		"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256(\"abc\")");

	// ── 1b. Canonical JSON: key order (deep sort) ────────────────────────────
	check_str(canon_of("{\"b\":1,\"a\":2,\"c\":{\"z\":1,\"y\":2}}"),
		"{\"a\":2,\"b\":1,\"c\":{\"y\":2,\"z\":1}}", "keys sorted at every depth");
	check_str(canon_of("[{\"b\":1,\"a\":2},{\"d\":3,\"c\":4}]"),
		"[{\"a\":2,\"b\":1},{\"c\":4,\"d\":3}]", "array order preserved, member keys sorted");

	// ── 1c. Canonical JSON: number formatting (JS ToString(Number)) ──────────
	check_str(canonical_number(100, "100"), "100", "integer 100");
	check_str(canonical_number(0, "0"), "0", "integer 0");
	check_str(canonical_number(-5, "-5"), "-5", "integer -5");
	check_str(canonical_number(1739642400000.0, "1739642400000"), "1739642400000", "ms timestamp");
	check_str(canonical_number(0.6, "0.6"), "0.6", "decimal 0.6");
	check_str(canonical_number(2.5, "2.5"), "2.5", "decimal 2.5");
	check_str(canonical_number(1.5, "1.5"), "1.5", "decimal 1.5");
	// Re-encoded lexemes normalize to the JS canonical form.
	check_str(canonical_number(100, "1e2"), "100", "1e2 -> 100");
	check_str(canonical_number(1.5, "1.50"), "1.5", "1.50 -> 1.5");

	// ── 1d. Canonical JSON: unicode + control-char escaping ──────────────────
	check_str(canonical_json_string("caf\xC3\xA9"), "\"caf\xC3\xA9\"", "raw UTF-8 (café)");
	check_str(canonical_json_string("a\nb\tc"), "\"a\\nb\\tc\"", "\\n and \\t escaped");
	check_str(canonical_json_string("x\x01y"), "\"x\\u0001y\"", "control char -> \\u0001");
	check_str(canonical_json_string("a/b"), "\"a/b\"", "slash not escaped");
	check_str(canonical_json_string("q\"\\"), "\"q\\\"\\\\\"", "quote + backslash escaped");
	// A parsed \u escape round-trips through canonical form as raw UTF-8.
	check_str(canon_of("{\"s\":\"\\u00e9\"}"), "{\"s\":\"\xC3\xA9\"}", "\\u00e9 -> raw é");

	// ── 2. Integrity byte-compatible with TS (committed golden vectors) ──────
	for (const char *name : {"v1-minimal.json", "v2-typical.json", "v2-with-extensions.json"}) {
		const std::string json = read_fixture(name);
		JsonParseResult parsed = parse_json(json);
		check(parsed.ok && parsed.root != nullptr, name);
		if (parsed.ok && parsed.root) {
			const std::string actual = canonical_json_integrity(*parsed.root);
			const std::string expected = vector_for(name);
			check_str(actual, expected, name);
		}
	}

	// ── 3a. Round-trip: canonical serialization is idempotent + hash-stable ──
	{
		const std::string json = read_fixture("v2-typical.json");
		const std::string once = canon_of(json);
		const std::string twice = canon_of(once);
		check_str(twice, once, "canonical serialization is idempotent");
		check_str(sha256_hex(once), vector_for("v2-typical.json"), "re-serialized hash stable");
	}

	// ── 3b. Migration v1 -> v3 (matches save-file-migrations.ts) ─────────────
	{
		SaveSystem save;
		std::string error;
		const bool loaded = save.load(read_fixture("v1-minimal.json"), error);
		check(loaded, "v1-minimal loads");
		if (!loaded) {
			std::fprintf(stderr, "  load error: %s\n", error.c_str());
		}
		check(save.version() == 3, "v1 migrated to v3");

		const JsonValue *root = save.save_file();
		check(root != nullptr, "migrated save has a tree");
		if (root) {
			// v1 -> v2: languageProgress proficiency fields backfilled.
			const JsonValue *lp =
				root->find("currentState") ? root->find("currentState")->find("languageProgress") : nullptr;
			check(lp != nullptr, "languageProgress present");
			if (lp) {
				check(lp->find("srsState") != nullptr, "srsState backfilled");
				check(lp->find("proficiencyHistory") != nullptr, "proficiencyHistory backfilled");
				check(lp->find("weakAreaHistory") != nullptr, "weakAreaHistory backfilled");
				check(lp->find("arrivalAssessment") != nullptr, "arrivalAssessment key present");
			}
			// v2 -> v3: worldSnapshot version stamps backfilled.
			const JsonValue *snap = root->find("worldSnapshot");
			check(snap != nullptr, "worldSnapshot present");
			if (snap) {
				check_str(snap->get_string("insimulVersion"), "pre-versioning", "insimulVersion stamped");
				check_str(snap->get_string("engineRevision"), "pre-versioning", "engineRevision stamped");
				check_str(snap->get_string("snapshotCreatedAt"), "pre-versioning", "snapshotCreatedAt stamped");
			}
		}
	}

	// ── 3c. A future-version save is rejected at load ────────────────────────
	{
		SaveSystem save;
		std::string error;
		const bool loaded = save.load(
			"{\"version\":999,\"currentState\":{},\"worldSnapshot\":{\"world\":{}}}", error);
		check(!loaded, "future-version save rejected");
		check(!save.is_loaded(), "not loaded after rejection");
	}

	// ── 3d. new_game builds a fresh current-version save around a snapshot ────
	{
		SaveSystem save;
		std::string error;
		NewGameOptions opts;
		opts.id = "save-1";
		opts.user_id = "user-1";
		opts.world_id = "world-1";
		opts.name = "New Game";
		opts.slot_index = 0;
		opts.created_at = "2026-07-17T00:00:00.000Z";
		const bool ok = save.new_game(
			"{\"world\":{\"id\":\"w\",\"name\":\"World\"},\"characters\":[]}", opts, error);
		check(ok, "new_game builds a save");
		check(save.version() == 3, "new_game save is current version");
		const JsonValue *root = save.save_file();
		check(root != nullptr, "new_game save has a tree");
		if (root) {
			check_str(root->get_string("status"), "active", "new_game status active");
			check(root->find("currentState") != nullptr, "new_game has currentState");
			check(root->find("worldSnapshot") != nullptr, "new_game has worldSnapshot");
			// The integrity of a fresh save is stable/reproducible.
			check(!save.compute_integrity().empty(), "new_game integrity computed");
		}
	}

	// ── 4. KB snapshot / restore into currentState.prologFacts ───────────────
	{
		SaveSystem save;
		std::string error;
		save.load(read_fixture("v2-typical.json"), error);

		std::vector<PrologFact> facts;
		{
			PrologFact f;
			f.predicate = "has_gold";
			f.args = {PrologArg::atom("player"), PrologArg::number(42)};
			facts.push_back(f);
		}
		{
			PrologFact f;
			f.predicate = "at_location";
			f.args = {PrologArg::atom("player"), PrologArg::atom("lot-shop")};
			facts.push_back(f);
		}
		save.snapshot_facts(facts);

		// Serialize -> reload -> restore: the facts survive a full save cycle.
		SaveSystem reloaded;
		const bool ok = reloaded.load(save.serialize_canonical(), error);
		check(ok, "snapshotted save reloads");
		const std::vector<PrologFact> restored = reloaded.restore_facts();
		check(restored.size() == 2, "restored fact count");
		check(restored == facts, "facts round-trip byte-faithful (atoms + numbers)");
	}

	// ── AC1: Godot-written envelope validates + integrity verifies (cross-check) ─
	{
		SaveSystem save;
		std::string error;
		const bool loaded = save.load(read_fixture("v2-typical.json"), error);
		check(loaded, "v2-typical loads for envelope build");

		// Deterministic inputs so the produced envelope is byte-reproducible and
		// can be pinned to the committed golden the TS cross-check validates.
		const std::string envelope =
			save.build_envelope_json("insimul-godot-gc2", "2026-07-17T00:00:00.000Z");

		// Self-consistency: the envelope's integrity equals a fresh hash of its
		// saveFile (the exact check validateSaveFileEnvelope performs TS-side).
		JsonParseResult parsed = parse_json(envelope);
		check(parsed.ok && parsed.root && parsed.root->is_object(), "envelope parses");
		if (parsed.ok && parsed.root) {
			check_str(parsed.root->get_string("format"), "insimul-save-v2", "envelope format tag");
			const JsonValue *save_node = parsed.root->find("saveFile");
			check(save_node != nullptr, "envelope carries saveFile");
			if (save_node) {
				check_str(parsed.root->get_string("integrity"), canonical_json_integrity(*save_node),
					"envelope integrity matches saveFile hash");
			}
		}

		// Emit the produced envelope to the (transient) build dir for humans/CI,
		// then pin it against the committed golden the TS cross-check validates.
		std::ofstream out(std::string(INSIMUL_GEN_DIR) + "/cpp-produced.envelope.json",
			std::ios::binary);
		if (out) {
			out << envelope;
		}
		const std::string golden = read_file(INSIMUL_CROSSCHECK_DIR, "cpp-produced.envelope.json");
		check(!golden.empty(), "committed golden envelope exists (tools/cross-check)");
		if (!golden.empty()) {
			check_str(envelope, golden, "envelope byte-matches committed golden (TS cross-check input)");
		}
	}

	std::printf("\n%d checks, %d failures\n", g_checks, g_failures);
	if (g_failures == 0) {
		std::printf("PASS\n");
		return 0;
	}
	std::printf("FAIL\n");
	return 1;
}
