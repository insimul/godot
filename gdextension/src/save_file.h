// save_file.h — the host-testable, portable save-file core for the Godot runtime.
//
// The cross-runtime save contract, ported from the semantics authority in
// packages/core/src (save-file.ts, save-envelope.ts, save-file-migrations.ts):
//
//   - new-game construction of a fresh, current-version SaveFile,
//   - load + version-gated migration up to SAVE_FILE_VERSION (v1 -> v2 -> v3),
//   - canonical-JSON serialization + SHA-256 integrity byte-compatible with
//     computeSaveFileIntegrity() (see canonical_json.h / sha256.h),
//   - export/import Envelope build, and
//   - KB snapshot/restore into currentState.prologFacts (the canonical truth
//     state the Prolog runtime hydrates from).
//
// This is the Godot twin of packages/unreal/Source/InsimulRuntime/Portable/
// InsimulSaveSystem.{h,cpp} — same semantics, same golden fixtures. The
// godot-cpp shim (insimul_save_file.h) wraps this for GDScript; the GDScript
// portable save system (addons/insimul/runtime/save_system.gd) owns slot I/O.
//
// std-only (no godot-cpp) so the whole contract runs under test/.

#ifndef INSIMUL_GODOT_SAVE_FILE_H
#define INSIMUL_GODOT_SAVE_FILE_H

#include "json_value.h"

#include <string>
#include <vector>

namespace insimul {

// Current save-file format version. MUST track SAVE_FILE_VERSION in save-file.ts.
constexpr int SAVE_FILE_VERSION = 3;

// Export-envelope format tag. MUST match SAVE_ENVELOPE_FORMAT in save-envelope.ts.
inline const char *save_envelope_format() { return "insimul-save-v2"; }

// A single argument of a Prolog fact — either an atom/string or a number.
struct PrologArg {
	bool is_number = false;
	std::string str;
	double num = 0.0;

	static PrologArg atom(const std::string &in_str) { PrologArg a; a.str = in_str; return a; }
	static PrologArg number(double in_num) { PrologArg a; a.is_number = true; a.num = in_num; return a; }

	bool operator==(const PrologArg &other) const {
		return is_number == other.is_number && (is_number ? num == other.num : str == other.str);
	}
};

// A Prolog fact: `predicate(arg0, arg1, ...)`. Mirrors currentState.prologFacts.
struct PrologFact {
	std::string predicate;
	std::vector<PrologArg> args;

	bool operator==(const PrologFact &other) const {
		return predicate == other.predicate && args == other.args;
	}
};

// Inputs for constructing a fresh save (the non-defaulted identity fields).
struct NewGameOptions {
	std::string id;
	std::string user_id;
	std::string world_id;
	std::string name;
	int slot_index = 0;
	// ISO-8601 timestamp stamped into createdAt/lastSavedAt.
	std::string created_at = "1970-01-01T00:00:00.000Z";
};

class SaveSystem {
public:
	// Parse a SaveFile JSON document and migrate it up to SAVE_FILE_VERSION.
	// Rejects (false + out_error) malformed JSON or a version produced by a
	// newer build than this reader understands.
	bool load(const std::string &json, std::string &out_error);

	// Build a fresh, current-version SaveFile around a world-snapshot document
	// (the shape of SaveFile.worldSnapshot or a WorldIR export). currentState
	// is populated with defaults; prologFacts starts empty.
	bool new_game(const std::string &world_snapshot_json, const NewGameOptions &options, std::string &out_error);

	bool is_loaded() const { return root_ != nullptr; }
	int version() const { return loaded_version_; }

	// Canonical (key-sorted, minified) JSON of the current SaveFile.
	std::string serialize_canonical() const;

	// SHA-256 hex of the canonical SaveFile — byte-compatible with TS.
	std::string compute_integrity() const;

	// Build an export Envelope JSON string wrapping the current SaveFile with
	// its integrity hash. Emitted canonically so the bytes are reproducible.
	std::string build_envelope_json(const std::string &insimul_version, const std::string &exported_at) const;

	// ── KB snapshot / restore (currentState.prologFacts) ────────────────────

	// Overwrite currentState.prologFacts with `facts`.
	void snapshot_facts(const std::vector<PrologFact> &facts);

	// Read currentState.prologFacts back out.
	std::vector<PrologFact> restore_facts() const;

	// Direct access to the parsed SaveFile tree (for accessors/tests).
	const JsonValue *save_file() const { return root_.get(); }

private:
	void migrate_to_current();

	JsonValuePtr root_;
	int loaded_version_ = 0;
};

} // namespace insimul

#endif // INSIMUL_GODOT_SAVE_FILE_H
